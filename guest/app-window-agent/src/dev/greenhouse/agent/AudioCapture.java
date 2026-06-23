/*
 * SPDX-License-Identifier: Apache-2.0
 */
package dev.greenhouse.agent;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.audiopolicy.AudioMix;
import android.media.audiopolicy.AudioMixingRule;
import android.media.audiopolicy.AudioPolicy;
import android.os.SystemClock;

import org.json.JSONObject;

import java.io.DataOutputStream;
import java.util.concurrent.atomic.AtomicBoolean;

final class AudioCapture implements AutoCloseable {
    private static final int SAMPLE_RATE = 48_000;
    private static final int CHANNEL_COUNT = 2;

    private final Context context;
    private final String packageName;
    private final int streamId;
    private final DataOutputStream output;
    private final Object writeLock;
    private final AtomicBoolean closed = new AtomicBoolean();
    private AudioManager audioManager;
    private AudioPolicy audioPolicy;
    private AudioRecord recorder;
    private Thread captureThread;

    AudioCapture(
            Context context,
            String packageName,
            int streamId,
            DataOutputStream output,
            Object writeLock
    ) {
        this.context = context;
        this.packageName = packageName;
        this.streamId = streamId;
        this.output = output;
        this.writeLock = writeLock;
    }

    void start() throws Exception {
        ApplicationInfo applicationInfo = context.getPackageManager().getApplicationInfo(
                packageName,
                PackageManager.ApplicationInfoFlags.of(0)
        );
        AudioFormat format = new AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                .build();
        AudioMixingRule rule = new AudioMixingRule.Builder()
                .setTargetMixRole(AudioMixingRule.MIX_ROLE_PLAYERS)
                .addMixRule(AudioMixingRule.RULE_MATCH_UID, applicationInfo.uid)
                .allowPrivilegedPlaybackCapture(true)
                .build();
        AudioMix mix = new AudioMix.Builder(rule)
                .setFormat(format)
                .setRouteFlags(AudioMix.ROUTE_FLAG_LOOP_BACK)
                .build();
        audioPolicy = new AudioPolicy.Builder(context)
                .addMix(mix)
                .build();
        audioManager = context.getSystemService(AudioManager.class);
        int registration = audioManager.registerAudioPolicy(audioPolicy);
        if (registration != AudioManager.SUCCESS) {
            audioPolicy = null;
            throw new IllegalStateException(
                    "could not register app-scoped audio policy for " + packageName
            );
        }

        recorder = audioPolicy.createAudioRecordSink(mix);
        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            recorder.release();
            recorder = null;
            audioManager.unregisterAudioPolicy(audioPolicy);
            audioPolicy = null;
            throw new IllegalStateException(
                    "app-scoped audio capture is unavailable for " + packageName
            );
        }
        int bufferSize = Math.max(
                recorder.getBufferSizeInFrames() * CHANNEL_COUNT * 2,
                SAMPLE_RATE / 10 * CHANNEL_COUNT * 2
        );
        Protocol.writeJson(
                output,
                writeLock,
                Protocol.AUDIO_CONFIG,
                streamId,
                new JSONObject()
                        .put("codec", "pcm_s16le")
                        .put("sampleRate", SAMPLE_RATE)
                        .put("channels", CHANNEL_COUNT)
                        .put("packageName", packageName)
                        .put("uid", applicationInfo.uid)
                        .put("scope", "application-uid")
        );
        try {
            recorder.startRecording();
            AudioRecord activeRecorder = recorder;
            captureThread = new Thread(
                    () -> captureLoop(activeRecorder, bufferSize),
                    "greenhouse-audio-" + streamId
            );
            captureThread.start();
        } catch (Exception error) {
            close();
            throw error;
        }
    }

    private void captureLoop(AudioRecord activeRecorder, int bufferSize) {
        byte[] buffer = new byte[bufferSize / 2];
        while (!closed.get() && !Thread.currentThread().isInterrupted()) {
            int count = activeRecorder.read(
                    buffer,
                    0,
                    buffer.length,
                    AudioRecord.READ_BLOCKING
            );
            if (count <= 0) {
                continue;
            }
            byte[] packet = new byte[count];
            System.arraycopy(buffer, 0, packet, 0, count);
            try {
                Protocol.write(
                        output,
                        writeLock,
                        Protocol.AUDIO_FRAME,
                        streamId,
                        Protocol.audioPayload(SystemClock.elapsedRealtimeNanos() / 1000, packet)
                );
            } catch (Exception error) {
                return;
            }
        }
    }

    @Override
    public void close() {
        if (!closed.compareAndSet(false, true)) {
            return;
        }
        if (captureThread != null) {
            captureThread.interrupt();
        }
        if (recorder != null) {
            try {
                recorder.stop();
            } catch (IllegalStateException ignored) {
            }
        }
        if (captureThread != null && captureThread != Thread.currentThread()) {
            try {
                captureThread.join(1000);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
            captureThread = null;
        }
        if (recorder != null) {
            recorder.release();
            recorder = null;
        }
        if (audioPolicy != null && audioManager != null) {
            audioManager.unregisterAudioPolicy(audioPolicy);
            audioPolicy = null;
        }
    }
}
