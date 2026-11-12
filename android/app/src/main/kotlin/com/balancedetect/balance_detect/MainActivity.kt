package com.balancedetect.balance_detect

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val tonePlayer = TonePlayer()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playSequence" -> {
                        val rawNotes = call.argument<List<Map<String, Any?>>>("notes")
                        if (rawNotes == null) {
                            result.error("invalid_arguments", "notes is required", null)
                            return@setMethodCallHandler
                        }
                        val notes = rawNotes.map { note ->
                            ToneNote(
                                frequencyHz = (note["frequencyHz"] as Number).toDouble(),
                                durationMs = (note["durationMs"] as Number).toInt(),
                                volume = (note["volume"] as Number).toFloat(),
                            )
                        }
                        tonePlayer.play(notes)
                        result.success(null)
                    }
                    "stop" -> {
                        tonePlayer.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        tonePlayer.release()
        super.onDestroy()
    }

    private companion object {
        const val TONE_CHANNEL = "com.balancedetect/tone"
    }
}
