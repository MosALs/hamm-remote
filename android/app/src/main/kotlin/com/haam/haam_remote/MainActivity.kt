package com.haam.haam_remote

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetooth: BluetoothHidBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetooth = BluetoothHidBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bluetooth?.onRequestPermissionsResult(requestCode, grantResults)
    }

    @Deprecated("Activity result API; still delivered by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        bluetooth?.onActivityResult(requestCode, resultCode)
    }

    override fun onDestroy() {
        bluetooth?.dispose()
        bluetooth = null
        super.onDestroy()
    }
}
