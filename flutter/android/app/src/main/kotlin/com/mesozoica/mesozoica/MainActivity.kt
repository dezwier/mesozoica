package com.mesozoica.mesozoica

import android.app.NotificationManager
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import com.mapbox.maps.MapView
import com.mapbox.maps.plugin.viewport.data.ViewportOptions
import com.mapbox.maps.plugin.viewport.viewport
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.random.Random

class MainActivity : FlutterActivity() {
  companion object {
    private val splashNames = listOf(
      "giganotosaurus",
      "tyrannosaurus",
      "triceratops",
      "spinosaurus",
      "microraptor",
      "argentinosaurus",
    )

    /** Chosen once per process so native window + Flutter splash match. */
    val splashIndex: Int = Random.nextInt(splashNames.size)
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    applyFlutterAssetSplashBackground()
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mesozoica/splash")
      .setMethodCallHandler { call, result ->
        if (call.method == "getSplashIndex") {
          result.success(splashIndex)
        } else {
          result.notImplemented()
        }
      }

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

  /**
   * Load the chosen splash PNG from Flutter assets (`assets/images/splash/`)
   * so Android does not need its own drawable copies.
   */
  private fun applyFlutterAssetSplashBackground() {
    val name = splashNames[splashIndex]
    val assetPath = "assets/images/splash/$name.png"
    val loader = FlutterInjector.instance().flutterLoader()
    if (!loader.initialized()) {
      loader.startInitialization(applicationContext)
      loader.ensureInitializationComplete(applicationContext, null)
    }
    val key = loader.getLookupKeyForAsset(assetPath)
    try {
      assets.open(key).use { stream ->
        val bitmap = BitmapFactory.decodeStream(stream) ?: return
        window.setBackgroundDrawable(BitmapDrawable(resources, bitmap))
      }
    } catch (_: Exception) {
      // Keep the solid launch_background color if the asset is missing.
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
