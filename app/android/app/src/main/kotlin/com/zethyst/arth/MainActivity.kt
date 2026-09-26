package com.zethyst.arth

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A device id that survives reinstalling the app (the free AI allowance
        // is per phone). ANDROID_ID is per app signing key, user and device;
        // it changes only on a factory reset.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arth/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "stableId" -> result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                else -> result.notImplemented()
            }
        }
    }
}
