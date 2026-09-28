package dz.nova.nova_mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ProtectedPlayback.register(flutterEngine)
        NotificationChime.register(flutterEngine, this)
        AppUpdate.register(flutterEngine, this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // D-067 / conception §6.5: the whole app is FLAG_SECURE, so
        // screenshots, screen recording, casting to non-secure displays
        // and the recents thumbnail all come out black. Set before the
        // first frame so no unprotected frame is ever composed.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
