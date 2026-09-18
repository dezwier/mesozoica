package com.mesozoica.mesozoica

import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.core.view.WindowCompat
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
    // FlutterActivity is not a ComponentActivity, so the AndroidX
    // enableEdgeToEdge() helper is unavailable. WindowCompat is the same
    // inset contract Play Console asks for, including Android 14 and below.
    WindowCompat.setDecorFitsSystemWindows(window, false)
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
    val metrics = resources.displayMetrics
    val bitmap = decodeSplashBitmap(
      assetKey = key,
      reqWidth = metrics.widthPixels.coerceAtLeast(1),
      reqHeight = metrics.heightPixels.coerceAtLeast(1),
    ) ?: return
    window.setBackgroundDrawable(BitmapDrawable(resources, bitmap))
  }

  private fun decodeSplashBitmap(
    assetKey: String,
    reqWidth: Int,
    reqHeight: Int,
  ): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    try {
      assets.open(assetKey).use { stream ->
        BitmapFactory.decodeStream(stream, null, bounds)
      }
    } catch (_: Exception) {
      return null
    }
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

    val decode = BitmapFactory.Options().apply {
      inSampleSize = calculateInSampleSize(bounds, reqWidth, reqHeight)
    }
    return try {
      assets.open(assetKey).use { stream ->
        BitmapFactory.decodeStream(stream, null, decode)
      }
    } catch (_: Exception) {
      // Keep the solid launch_background color if the asset is missing.
      null
    }
  }

  private fun calculateInSampleSize(
    options: BitmapFactory.Options,
    reqWidth: Int,
    reqHeight: Int,
  ): Int {
    val width = options.outWidth
    val height = options.outHeight
    var inSampleSize = 1
    if (height > reqHeight || width > reqWidth) {
      val halfHeight = height / 2
      val halfWidth = width / 2
      while (halfHeight / inSampleSize >= reqHeight &&
        halfWidth / inSampleSize >= reqWidth
      ) {
        inSampleSize *= 2
      }
    }
    return inSampleSize
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
