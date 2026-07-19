package com.mesozoica.mesozoica

import android.app.NotificationManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mesozoica/app_badge")
      .setMethodCallHandler { call, result ->
        if (call.method == "setBadgeCount") {
          val count = (call.arguments as? Int) ?: 0
          // Android launcher badges track active shade notifications.
          if (count <= 0) {
            val manager =
              getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancelAll()
          }
          result.success(null)
        } else {
          result.notImplemented()
        }
      }
  }
}
