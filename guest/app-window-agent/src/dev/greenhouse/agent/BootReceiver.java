/*
 * SPDX-License-Identifier: Apache-2.0
 */
package dev.greenhouse.agent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        context.startService(new Intent(context, AgentService.class));
    }
}
