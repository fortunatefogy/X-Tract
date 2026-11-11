package com.example.linky

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

class ShareActivity : LinkyFlutterActivity() {
    override val shareModeName: String get() = "share"
    override val supportsShare: Boolean get() = true

    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(R.style.ShareSheetTheme)
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        super.onCreate(savedInstanceState)
    }

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent
}
