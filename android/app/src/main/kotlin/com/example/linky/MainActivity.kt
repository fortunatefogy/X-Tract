package com.example.linky

import android.os.Build

class MainActivity : LinkyFlutterActivity() {
    override fun onResume() {
        super.onResume()
        announceMode()
        announceHidden(false)
    }

    override fun onPause() {
        super.onPause()
        if (isChangingConfigurations || isFinishing) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) return
        announceHidden(true)
    }
}
