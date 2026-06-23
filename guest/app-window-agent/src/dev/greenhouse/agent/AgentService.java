/*
 * SPDX-License-Identifier: Apache-2.0
 */
package dev.greenhouse.agent;

import android.app.Service;
import android.content.Intent;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.IBinder;
import android.os.Process;
import android.os.SystemProperties;
import android.os.SystemClock;
import android.util.Log;

import org.json.JSONObject;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class AgentService extends Service {
    private static final String TAG = "GreenhouseAppWindow";
    private static final String DEFAULT_SOCKET = "greenhouse-app-window";

    private final ExecutorService clients = Executors.newCachedThreadPool();
    private final Set<AppDisplaySession> sessions = ConcurrentHashMap.newKeySet();
    private volatile boolean stopping;
    private LocalServerSocket server;
    private Thread acceptThread;

    @Override
    public void onCreate() {
        super.onCreate();
        acceptThread = new Thread(this::acceptLoop, "greenhouse-agent-accept");
        acceptThread.start();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void acceptLoop() {
        String socketName = SystemProperties.get(
                "ro.greenhouse.app_window_agent.socket",
                DEFAULT_SOCKET
        );
        try {
            server = new LocalServerSocket(socketName);
            Log.i(TAG, "listening on localabstract:" + socketName);
            while (!stopping) {
                LocalSocket socket = server.accept();
                int peerUid = socket.getPeerCredentials().getUid();
                if (peerUid != Process.SHELL_UID && peerUid != Process.ROOT_UID) {
                    Log.w(TAG, "rejected app-window socket peer uid " + peerUid);
                    socket.close();
                    continue;
                }
                clients.execute(() -> handleClient(socket));
            }
        } catch (IOException error) {
            if (!stopping) {
                Log.e(TAG, "agent socket failed", error);
                stopSelf();
            }
        }
    }

    private void handleClient(LocalSocket socket) {
        Object writeLock = new Object();
        AppDisplaySession session = null;
        try (
                DataInputStream input = new DataInputStream(socket.getInputStream());
                DataOutputStream output = new DataOutputStream(socket.getOutputStream())
        ) {
            Protocol.Packet create = Protocol.read(input);
            if (create != null && create.kind == Protocol.HEALTH) {
                Protocol.writeJson(
                        output,
                        writeLock,
                        Protocol.HEALTHY,
                        create.streamId,
                        new JSONObject()
                                .put("healthy", true)
                                .put("protocolVersion", Protocol.VERSION)
                                .put("uptimeNanos", SystemClock.elapsedRealtimeNanos())
                );
                return;
            }
            if (create == null || create.kind != Protocol.CREATE) {
                throw new IOException("first packet must create an app display");
            }
            JSONObject request = Protocol.json(create);
            session = new AppDisplaySession(
                    this,
                    create.streamId,
                    request,
                    output,
                    writeLock
            );
            sessions.add(session);

            Protocol.Packet packet;
            while ((packet = Protocol.read(input)) != null) {
                if (packet.streamId != create.streamId) {
                    throw new IOException("packet stream id changed within a session");
                }
                session.handle(packet);
            }
        } catch (Exception error) {
            Log.e(TAG, "app display client failed", error);
        } finally {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
            if (session != null) {
                sessions.remove(session);
                session.close();
            }
        }
    }

    @Override
    public void onDestroy() {
        stopping = true;
        for (AppDisplaySession session : sessions) {
            session.close();
        }
        sessions.clear();
        clients.shutdownNow();
        try {
            if (server != null) {
                server.close();
            }
        } catch (IOException ignored) {
        }
        if (acceptThread != null) {
            acceptThread.interrupt();
        }
        super.onDestroy();
    }
}
