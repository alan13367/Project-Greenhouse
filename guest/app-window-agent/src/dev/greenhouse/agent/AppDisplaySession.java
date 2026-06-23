/*
 * SPDX-License-Identifier: Apache-2.0
 */
package dev.greenhouse.agent;

import android.app.ActivityOptions;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.hardware.display.VirtualDisplayConfig;
import android.hardware.input.InputManager;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.Log;
import android.view.Surface;
import android.view.WindowManager;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicBoolean;

final class AppDisplaySession implements AutoCloseable {
    private static final String TAG = "GreenhouseAppWindow";
    private static final String MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC;
    private static final int DEFAULT_BITRATE = 12_000_000;
    private static final int DEFAULT_FRAME_RATE = 60;
    // Hidden/TestApi flags from Android 16 QPR2 DisplayManager. Keep the
    // numeric values here so the source also compiles against AOSP test stubs.
    private static final int VIRTUAL_DISPLAY_FLAG_SUPPORTS_TOUCH = 1 << 6;
    private static final int VIRTUAL_DISPLAY_FLAG_DESTROY_CONTENT_ON_REMOVAL = 1 << 8;
    private static final int VIRTUAL_DISPLAY_FLAG_OWN_DISPLAY_GROUP = 1 << 11;

    private final Context context;
    private final int streamId;
    private final String packageName;
    private final DataOutputStream output;
    private final Object writeLock;
    private final HandlerThread callbackThread;
    private final AtomicBoolean closed = new AtomicBoolean();

    private int width;
    private int height;
    private int densityDpi;
    private int bitRate;
    private int frameRate;
    private MediaCodec encoder;
    private Surface encoderSurface;
    private VirtualDisplay virtualDisplay;
    private InputRouter inputRouter;
    private Thread drainThread;
    private AudioCapture audioCapture;

    AppDisplaySession(
            Context context,
            int streamId,
            JSONObject request,
            DataOutputStream output,
            Object writeLock
    ) throws Exception {
        this.context = context;
        this.streamId = streamId;
        packageName = request.getString("packageName");
        width = alignDimension(request.optInt("width", 1280));
        height = alignDimension(request.optInt("height", 720));
        densityDpi = request.optInt("densityDpi", 240);
        bitRate = request.optInt("bitRate", DEFAULT_BITRATE);
        frameRate = request.optInt("frameRate", DEFAULT_FRAME_RATE);
        this.output = output;
        this.writeLock = writeLock;
        callbackThread = new HandlerThread("greenhouse-display-" + streamId);
        callbackThread.start();

        try {
            createEncoder();
            createDisplay();
            launchApp();
            inputRouter = new InputRouter(
                    context.getSystemService(InputManager.class),
                    virtualDisplay.getDisplay().getDisplayId()
            );
            sendHello();
            startDrainThread();
            if (request.optBoolean("audio", true)) {
                AudioCapture capture = new AudioCapture(
                    context,
                    packageName,
                    streamId,
                    output,
                    writeLock
                );
                try {
                    capture.start();
                    audioCapture = capture;
                } catch (Exception audioError) {
                    capture.close();
                    Log.w(
                            TAG,
                            "audio capture unavailable for display " + displayId(),
                            audioError
                    );
                }
            }
        } catch (Exception error) {
            close();
            throw error;
        }
    }

    int displayId() {
        return virtualDisplay.getDisplay().getDisplayId();
    }

    void handle(Protocol.Packet packet) throws Exception {
        JSONObject payload;
        switch (packet.kind) {
            case Protocol.RESIZE:
                payload = Protocol.json(packet);
                resize(
                        payload.getInt("width"),
                        payload.getInt("height"),
                        payload.getInt("densityDpi"),
                        payload.optInt("bitRate", bitRate)
                );
                break;
            case Protocol.FOCUS:
                launchApp();
                break;
            case Protocol.POINTER:
                inputRouter.pointer(Protocol.json(packet));
                break;
            case Protocol.KEY:
                inputRouter.key(Protocol.json(packet));
                break;
            case Protocol.TEXT:
                inputRouter.text(Protocol.json(packet));
                break;
            case Protocol.CONTROLLER:
                inputRouter.controller(Protocol.json(packet));
                break;
            case Protocol.PING:
                long guestReceiveNanos = SystemClock.elapsedRealtimeNanos();
                JSONObject ping = Protocol.json(packet);
                Protocol.writeJson(
                        output,
                        writeLock,
                        Protocol.PONG,
                        streamId,
                        new JSONObject()
                                .put("hostSendNanos", ping.getLong("hostSendNanos"))
                                .put("guestReceiveNanos", guestReceiveNanos)
                                .put("guestSendNanos", SystemClock.elapsedRealtimeNanos())
                );
                break;
            case Protocol.CLOSE:
                close();
                break;
            default:
                throw new IOException("unsupported session packet " + packet.kind);
        }
    }

    private void createEncoder() throws IOException {
        encoder = MediaCodec.createEncoderByType(MIME_TYPE);
        MediaFormat format = MediaFormat.createVideoFormat(MIME_TYPE, width, height);
        format.setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
        );
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate);
        format.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate);
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
        format.setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
        );
        format.setInteger(MediaFormat.KEY_PRIORITY, 0);
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        encoderSurface = encoder.createInputSurface();
        encoder.start();
    }

    private void createDisplay() {
        int flags =
                DisplayManager.VIRTUAL_DISPLAY_FLAG_TRUSTED
                        | DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY
                        | VIRTUAL_DISPLAY_FLAG_OWN_DISPLAY_GROUP
                        | VIRTUAL_DISPLAY_FLAG_SUPPORTS_TOUCH
                        | DisplayManager.VIRTUAL_DISPLAY_FLAG_ROTATES_WITH_CONTENT
                        | VIRTUAL_DISPLAY_FLAG_DESTROY_CONTENT_ON_REMOVAL;

        VirtualDisplayConfig config = new VirtualDisplayConfig.Builder(
                "Greenhouse:" + packageName + ":" + streamId,
                width,
                height,
                densityDpi
        )
                .setFlags(flags)
                .setSurface(encoderSurface)
                .setRequestedRefreshRate(frameRate)
                .build();
        virtualDisplay = context.getSystemService(DisplayManager.class)
                .createVirtualDisplay(
                        config,
                        new Handler(callbackThread.getLooper()),
                        new VirtualDisplay.Callback() {
                            @Override
                            public void onStopped() {
                                close();
                            }
                        }
                );
        if (virtualDisplay == null) {
            throw new IllegalStateException("Android rejected the trusted virtual display");
        }
        context.getSystemService(WindowManager.class).setDisplayImePolicy(
                displayId(),
                WindowManager.DISPLAY_IME_POLICY_LOCAL
        );
    }

    private void launchApp() {
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(packageName);
        if (launch == null) {
            throw new IllegalArgumentException("package has no launchable activity: " + packageName);
        }
        launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        );
        ActivityOptions options = ActivityOptions.makeBasic();
        options.setLaunchDisplayId(displayId());
        Bundle bundle = options.toBundle();
        context.startActivity(launch, bundle);
    }

    private void resize(int newWidth, int newHeight, int newDensityDpi, int newBitRate)
            throws Exception {
        int alignedWidth = alignDimension(newWidth);
        int alignedHeight = alignDimension(newHeight);
        if (alignedWidth == width
                && alignedHeight == height
                && newDensityDpi == densityDpi
                && newBitRate == bitRate) {
            return;
        }

        stopDrainThread();
        virtualDisplay.setSurface(null);
        releaseEncoder();
        width = alignedWidth;
        height = alignedHeight;
        densityDpi = newDensityDpi;
        bitRate = newBitRate;
        try {
            createEncoder();
            virtualDisplay.resize(width, height, densityDpi);
            virtualDisplay.setSurface(encoderSurface);
            startDrainThread();
        } catch (Exception error) {
            close();
            throw error;
        }
    }

    private void sendHello() throws IOException, JSONException {
        Protocol.writeJson(
                output,
                writeLock,
                Protocol.HELLO,
                streamId,
                new JSONObject()
                        .put("displayId", displayId())
                        .put("packageName", packageName)
                        .put("width", width)
                        .put("height", height)
                        .put("densityDpi", densityDpi)
                        .put("frameRate", frameRate)
        );
    }

    private void startDrainThread() {
        drainThread = new Thread(this::drainEncoder, "greenhouse-encoder-" + streamId);
        drainThread.start();
    }

    private void stopDrainThread() {
        Thread thread = drainThread;
        drainThread = null;
        if (thread != null) {
            thread.interrupt();
            try {
                thread.join(1000);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private void drainEncoder() {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        MediaCodec activeEncoder = encoder;
        try {
            while (!closed.get() && !Thread.currentThread().isInterrupted()) {
                int index = activeEncoder.dequeueOutputBuffer(info, 10_000);
                if (index == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    continue;
                }
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    sendVideoConfig(activeEncoder.getOutputFormat());
                    continue;
                }
                if (index < 0) {
                    continue;
                }

                ByteBuffer buffer = activeEncoder.getOutputBuffer(index);
                boolean codecConfig =
                        (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
                if (!codecConfig && buffer != null && info.size > 0) {
                    buffer.position(info.offset);
                    buffer.limit(info.offset + info.size);
                    byte[] encoded = new byte[info.size];
                    buffer.get(encoded);
                    Protocol.write(
                            output,
                            writeLock,
                            Protocol.VIDEO_FRAME,
                            streamId,
                            Protocol.videoPayload(info.presentationTimeUs, info.flags, encoded)
                    );
                }
                activeEncoder.releaseOutputBuffer(index, false);
            }
        } catch (Exception error) {
            if (!closed.get()) {
                Log.e(TAG, "encoder drain failed for display " + displayId(), error);
                sendError("encoder", error);
            }
        }
    }

    private void sendVideoConfig(MediaFormat format) throws IOException, JSONException {
        ByteBuffer csd0 = format.getByteBuffer("csd-0");
        ByteBuffer csd1 = format.getByteBuffer("csd-1");
        if (csd0 == null || csd1 == null) {
            throw new IOException("H.264 encoder did not provide SPS/PPS");
        }
        byte[] sps = new byte[csd0.remaining()];
        byte[] pps = new byte[csd1.remaining()];
        csd0.get(sps);
        csd1.get(pps);
        Protocol.writeJson(
                output,
                writeLock,
                Protocol.VIDEO_CONFIG,
                streamId,
                Protocol.videoConfig(width, height, displayId(), sps, pps)
        );
    }

    private void sendError(String stage, Exception error) {
        try {
            Protocol.writeJson(
                    output,
                    writeLock,
                    Protocol.ERROR,
                    streamId,
                    new JSONObject()
                            .put("stage", stage)
                            .put("message", String.valueOf(error.getMessage()))
            );
        } catch (Exception ignored) {
            // The peer is already gone.
        }
    }

    private static int alignDimension(int value) {
        return Math.max(64, value - Math.floorMod(value, 8));
    }

    private void releaseEncoder() {
        if (encoder != null) {
            try {
                encoder.stop();
            } catch (IllegalStateException ignored) {
            }
            encoder.release();
            encoder = null;
        }
        if (encoderSurface != null) {
            encoderSurface.release();
            encoderSurface = null;
        }
    }

    @Override
    public void close() {
        if (!closed.compareAndSet(false, true)) {
            return;
        }
        stopDrainThread();
        if (virtualDisplay != null) {
            virtualDisplay.release();
            virtualDisplay = null;
        }
        releaseEncoder();
        if (audioCapture != null) {
            audioCapture.close();
            audioCapture = null;
        }
        callbackThread.quitSafely();
    }
}
