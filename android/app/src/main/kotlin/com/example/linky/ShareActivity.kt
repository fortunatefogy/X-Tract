package com.example.linky

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

class ShareActivity : LinkyFlutterActivity() {
    override val shareModeName: String get() = "share"
    override val supportsShare: Boolean get() = true

    private val overlayHandler = Handler(Looper.getMainLooper())
    private var overlay: View? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(R.style.ShareSheetTheme)
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        super.onCreate(savedInstanceState)
        showOverlay()
    }

    override fun onNewIntent(intent: Intent) {
        if (isShareIntent(intent)) showOverlay()
        super.onNewIntent(intent)
    }

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun onShareReady() = hideOverlay()

    private fun showOverlay() {
        val content = findViewById<ViewGroup>(android.R.id.content) ?: return
        overlay?.let { (it.parent as? ViewGroup)?.removeView(it) }
        val view = View(this).apply { setBackgroundColor(0xE60B1210.toInt()) }
        content.addView(
            view,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        content.bringChildToFront(view)
        overlay = view
        overlayHandler.removeCallbacksAndMessages(null)
        overlayHandler.postDelayed({ hideOverlay() }, 2000)
    }

    private fun hideOverlay() {
        val view = overlay ?: return
        overlay = null
        overlayHandler.removeCallbacksAndMessages(null)
        view.animate()
            .alpha(0f)
            .setDuration(180)
            .withEndAction { (view.parent as? ViewGroup)?.removeView(view) }
            .start()
    }
}
