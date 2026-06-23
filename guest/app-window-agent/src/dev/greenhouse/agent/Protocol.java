/*
 * SPDX-License-Identifier: Apache-2.0
 */
package dev.greenhouse.agent;

import android.util.Base64;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

final class Protocol {
    static final int MAGIC = 0x47524853; // "GRHS"
    static final short VERSION = 1;
    static final int MAX_PAYLOAD_BYTES = 16 * 1024 * 1024;

    static final short CREATE = 1;
    static final short RESIZE = 2;
    static final short FOCUS = 3;
    static final short POINTER = 4;
    static final short KEY = 5;
    static final short TEXT = 6;
    static final short CONTROLLER = 7;
    static final short CLOSE = 8;
    static final short PING = 9;
    static final short HEALTH = 10;

    static final short HELLO = 101;
    static final short VIDEO_CONFIG = 102;
    static final short VIDEO_FRAME = 103;
    static final short AUDIO_CONFIG = 104;
    static final short AUDIO_FRAME = 105;
    static final short METRICS = 106;
    static final short PONG = 109;
    static final short HEALTHY = 110;
    static final short ERROR = 199;

    private Protocol() {}

    static Packet read(DataInputStream input) throws IOException {
        final int magic;
        try {
            magic = input.readInt();
        } catch (EOFException eof) {
            return null;
        }
        if (magic != MAGIC) {
            throw new IOException("invalid Greenhouse protocol magic");
        }
        short version = input.readShort();
        if (version != VERSION) {
            throw new IOException("unsupported Greenhouse protocol version " + version);
        }
        short kind = input.readShort();
        int length = input.readInt();
        int streamId = input.readInt();
        if (length < 0 || length > MAX_PAYLOAD_BYTES) {
            throw new IOException("invalid Greenhouse payload length " + length);
        }
        byte[] payload = new byte[length];
        input.readFully(payload);
        return new Packet(kind, streamId, payload);
    }

    static void write(
            DataOutputStream output,
            Object writeLock,
            short kind,
            int streamId,
            byte[] payload
    ) throws IOException {
        synchronized (writeLock) {
            output.writeInt(MAGIC);
            output.writeShort(VERSION);
            output.writeShort(kind);
            output.writeInt(payload.length);
            output.writeInt(streamId);
            output.write(payload);
            output.flush();
        }
    }

    static void writeJson(
            DataOutputStream output,
            Object writeLock,
            short kind,
            int streamId,
            JSONObject payload
    ) throws IOException {
        write(
                output,
                writeLock,
                kind,
                streamId,
                payload.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8)
        );
    }

    static JSONObject json(Packet packet) throws IOException {
        try {
            return new JSONObject(
                    new String(packet.payload, java.nio.charset.StandardCharsets.UTF_8)
            );
        } catch (JSONException error) {
            throw new IOException("invalid JSON control payload", error);
        }
    }

    static byte[] videoPayload(long presentationTimeUs, int flags, byte[] encoded) {
        ByteBuffer payload = ByteBuffer
                .allocate(Long.BYTES + Integer.BYTES + encoded.length)
                .order(ByteOrder.BIG_ENDIAN);
        payload.putLong(presentationTimeUs);
        payload.putInt(flags);
        payload.put(encoded);
        return payload.array();
    }

    static byte[] audioPayload(long presentationTimeUs, byte[] pcm) {
        ByteBuffer payload = ByteBuffer
                .allocate(Long.BYTES + pcm.length)
                .order(ByteOrder.BIG_ENDIAN);
        payload.putLong(presentationTimeUs);
        payload.put(pcm);
        return payload.array();
    }

    static JSONObject videoConfig(
            int width,
            int height,
            int displayId,
            byte[] sps,
            byte[] pps
    ) throws JSONException {
        return new JSONObject()
                .put("codec", "h264")
                .put("width", width)
                .put("height", height)
                .put("displayId", displayId)
                .put("sps", Base64.encodeToString(sps, Base64.NO_WRAP))
                .put("pps", Base64.encodeToString(pps, Base64.NO_WRAP));
    }

    static final class Packet {
        final short kind;
        final int streamId;
        final byte[] payload;

        Packet(short kind, int streamId, byte[] payload) {
            this.kind = kind;
            this.streamId = streamId;
            this.payload = payload;
        }
    }
}
