package com.example.intern_noter

import android.content.Intent
import android.os.Bundle
import com.example.intern_noter.widget.TodayNoteWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.example.intern_noter/widget"
    }

    private var pendingOpenToday = false

    override fun onCreate(savedInstanceState: Bundle?) {
        captureIntentExtras(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIntentExtras(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        TodayNoteWidgetProvider.updateAllWidgets(applicationContext)
                        result.success(null)
                    }
                    "consumePendingRoute" -> {
                        val route = if (pendingOpenToday) {
                            pendingOpenToday = false
                            TodayNoteWidgetProvider.EXTRA_OPEN_TODAY
                        } else {
                            null
                        }
                        result.success(route)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun captureIntentExtras(intent: Intent?) {
        if (intent?.getBooleanExtra(TodayNoteWidgetProvider.EXTRA_OPEN_TODAY, false) == true) {
            pendingOpenToday = true
            intent.removeExtra(TodayNoteWidgetProvider.EXTRA_OPEN_TODAY)
        }
    }
}
