package io.ikhlaas.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Screenshot deterrence (PRD §4.3: FLAG_SECURE on Android). Disabled
    // during development so the app can be screenshotted for testing;
    // flip to true for beta/release builds.
    private val screenshotProtection = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (screenshotProtection) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }
}
