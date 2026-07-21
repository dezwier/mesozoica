package com.mesozoica.mesozoica

import android.app.NotificationManager
import android.content.Context
import android.view.View
import android.view.ViewGroup
import com.mapbox.maps.MapView
import com.mapbox.maps.plugin.viewport.data.ViewportOptions
import com.mapbox.maps.plugin.viewport.viewport
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

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "mesozoica/mapbox_viewport",
    ).setMethodCallHandler { call, result ->
      if (call.method == "disableViewportIdleOnInteraction") {
        val root = window?.decorView ?: run {
          result.success(0)
          return@setMethodCallHandler
        }
        result.success(disableViewportIdleOnInteraction(root))
      } else {
        result.notImplemented()
      }
    }
  }

  private fun disableViewportIdleOnInteraction(root: View): Int {
    var count = 0
    if (root is MapView) {
      root.viewport.options = ViewportOptions.Builder()
        .transitionsToIdleUponUserInteraction(false)
        .build()
      count += 1
    }
    if (root is ViewGroup) {
      for (i in 0 until root.childCount) {
        count += disableViewportIdleOnInteraction(root.getChildAt(i))
      }
    }
    return count
  }
}
