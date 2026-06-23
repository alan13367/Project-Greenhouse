/*
 * SPDX-License-Identifier: Apache-2.0
 */
package dev.greenhouse.agent;

import android.hardware.input.InputManager;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.MotionEvent;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class InputRouter {
    // InputEventInjectionSync.NONE in Android 16 QPR2.
    private static final int INJECT_ASYNC = 0;

    private final InputManager inputManager;
    private final int displayId;
    private long pointerDownTime;

    InputRouter(InputManager inputManager, int displayId) {
        this.inputManager = inputManager;
        this.displayId = displayId;
    }

    void pointer(JSONObject payload) throws JSONException {
        int action = payload.getInt("action");
        int source = payload.optInt("source", InputDevice.SOURCE_MOUSE);
        long now = SystemClock.uptimeMillis();
        if (action == MotionEvent.ACTION_DOWN) {
            pointerDownTime = now;
        }
        if (pointerDownTime == 0) {
            pointerDownTime = now;
        }

        MotionEvent.PointerProperties properties = new MotionEvent.PointerProperties();
        properties.id = 0;
        properties.toolType = source == InputDevice.SOURCE_TOUCHSCREEN
                ? MotionEvent.TOOL_TYPE_FINGER
                : MotionEvent.TOOL_TYPE_MOUSE;
        MotionEvent.PointerCoords coordinates = new MotionEvent.PointerCoords();
        coordinates.x = (float) payload.getDouble("x");
        coordinates.y = (float) payload.getDouble("y");
        coordinates.pressure = action == MotionEvent.ACTION_UP ? 0 : 1;
        coordinates.size = 1;
        coordinates.setAxisValue(
                MotionEvent.AXIS_RELATIVE_X,
                (float) payload.optDouble("deltaX", 0)
        );
        coordinates.setAxisValue(
                MotionEvent.AXIS_RELATIVE_Y,
                (float) payload.optDouble("deltaY", 0)
        );
        coordinates.setAxisValue(
                MotionEvent.AXIS_HSCROLL,
                (float) payload.optDouble("scrollX", 0)
        );
        coordinates.setAxisValue(
                MotionEvent.AXIS_VSCROLL,
                (float) payload.optDouble("scrollY", 0)
        );

        MotionEvent event = MotionEvent.obtain(
                pointerDownTime,
                now,
                action,
                1,
                new MotionEvent.PointerProperties[] { properties },
                new MotionEvent.PointerCoords[] { coordinates },
                payload.optInt("metaState", 0),
                payload.optInt("buttons", 0),
                1,
                1,
                0,
                0,
                source,
                0
        );
        event.setDisplayId(displayId);
        inject(event);
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            pointerDownTime = 0;
        }
    }

    void key(JSONObject payload) throws JSONException {
        long now = SystemClock.uptimeMillis();
        int action = payload.getInt("action");
        KeyEvent event = new KeyEvent(
                now,
                now,
                action,
                payload.getInt("keyCode"),
                payload.optInt("repeat", 0),
                payload.optInt("metaState", 0),
                KeyCharacterMap.VIRTUAL_KEYBOARD,
                0,
                KeyEvent.FLAG_FROM_SYSTEM,
                payload.optInt("source", InputDevice.SOURCE_KEYBOARD)
        );
        event.setDisplayId(displayId);
        inject(event);
    }

    void text(JSONObject payload) throws JSONException {
        char[] characters = payload.getString("text").toCharArray();
        KeyEvent[] events = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD)
                .getEvents(characters);
        if (events == null) {
            KeyEvent event = new KeyEvent(
                    SystemClock.uptimeMillis(),
                    payload.getString("text"),
                    KeyCharacterMap.VIRTUAL_KEYBOARD,
                    KeyEvent.FLAG_SOFT_KEYBOARD
            );
            event.setDisplayId(displayId);
            inject(event);
            return;
        }
        for (KeyEvent source : events) {
            KeyEvent event = KeyEvent.changeTimeRepeat(
                    source,
                    SystemClock.uptimeMillis(),
                    source.getRepeatCount()
            );
            event.setDisplayId(displayId);
            inject(event);
        }
    }

    void controller(JSONObject payload) throws JSONException {
        long now = SystemClock.uptimeMillis();
        MotionEvent.PointerProperties properties = new MotionEvent.PointerProperties();
        properties.id = 0;
        properties.toolType = MotionEvent.TOOL_TYPE_UNKNOWN;

        MotionEvent.PointerCoords coordinates = new MotionEvent.PointerCoords();
        coordinates.setAxisValue(MotionEvent.AXIS_X, axis(payload, "leftX"));
        coordinates.setAxisValue(MotionEvent.AXIS_Y, axis(payload, "leftY"));
        coordinates.setAxisValue(MotionEvent.AXIS_Z, axis(payload, "rightX"));
        coordinates.setAxisValue(MotionEvent.AXIS_RZ, axis(payload, "rightY"));
        coordinates.setAxisValue(MotionEvent.AXIS_LTRIGGER, axis(payload, "leftTrigger"));
        coordinates.setAxisValue(MotionEvent.AXIS_RTRIGGER, axis(payload, "rightTrigger"));
        coordinates.setAxisValue(MotionEvent.AXIS_HAT_X, axis(payload, "hatX"));
        coordinates.setAxisValue(MotionEvent.AXIS_HAT_Y, axis(payload, "hatY"));

        MotionEvent event = MotionEvent.obtain(
                now,
                now,
                MotionEvent.ACTION_MOVE,
                1,
                new MotionEvent.PointerProperties[] { properties },
                new MotionEvent.PointerCoords[] { coordinates },
                0,
                payload.optInt("buttons", 0),
                1,
                1,
                0,
                0,
                InputDevice.SOURCE_JOYSTICK | InputDevice.SOURCE_GAMEPAD,
                0
        );
        event.setDisplayId(displayId);
        inject(event);

        JSONArray keys = payload.optJSONArray("keys");
        if (keys != null) {
            for (int index = 0; index < keys.length(); index++) {
                JSONObject key = keys.getJSONObject(index);
                key(key);
            }
        }
    }

    private float axis(JSONObject payload, String name) {
        return (float) payload.optDouble(name, 0);
    }

    private void inject(InputEvent event) {
        inputManager.injectInputEvent(event, INJECT_ASYNC);
    }
}
