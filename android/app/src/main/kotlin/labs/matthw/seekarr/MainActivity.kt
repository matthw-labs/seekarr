package labs.matthw.seekarr

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CLIPBOARD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copySecret" -> {
                        val secret = call.argument<String>("secret")
                        if (secret.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            result.success(copySecret(secret))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Puts [secret] on the clipboard marked as sensitive.
     *
     * From Android 13 the system shows a preview of every copy, which for a
     * credential means rendering it in cleartext over whatever is on screen.
     * `EXTRA_IS_SENSITIVE` is what suppresses that preview, and it is only
     * reachable through [ClipDescription.setExtras] — Flutter's own clipboard
     * plumbing never sets it.
     *
     * Returns false rather than throwing when there is no clipboard service, so
     * Dart can fall back to the plain copy: an unhardened key on the clipboard
     * is still better than a copy button that does nothing.
     */
    private fun copySecret(secret: String): Boolean {
        val clipboard =
            getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return false

        val clip = ClipData.newPlainText("", secret)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras =
                PersistableBundle().apply {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
        }

        return try {
            clipboard.setPrimaryClip(clip)
            true
        } catch (e: IllegalStateException) {
            // Some OEM builds throw when the app is not the focused window.
            false
        }
    }

    private companion object {
        const val SECURE_CLIPBOARD_CHANNEL = "labs.matthw.seekarr/secure_clipboard"
    }
}
