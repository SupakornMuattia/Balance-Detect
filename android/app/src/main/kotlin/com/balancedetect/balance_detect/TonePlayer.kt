package com.balancedetect.balance_detect

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

data class ToneNote(val frequencyHz: Double, val durationMs: Int, val volume: Float)

/**
 * Synthesizes short sine-wave cues for hands-free guidance.
 *
 * Each request renders one PCM buffer and plays it on a static AudioTrack. A
 * new request replaces the previous track, so cues never pile up behind each
 * other. All AudioTrack work runs on one background thread.
 */
class TonePlayer {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var current: AudioTrack? = null

    fun play(notes: List<ToneNote>) {
        if (executor.isShutdown) return
        executor.execute {
            releaseCurrent()
            val samples = render(notes)
            if (samples.isEmpty()) return@execute
            try {
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            // Same usage as the Thai voice guidance, so beeps
                            // follow the media volume. SONIFICATION would map
                            // to the system stream, which is muted in silent
                            // or vibrate mode and is often turned down.
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build(),
                    )
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(samples.size * 2)
                    .build()
                track.write(samples, 0, samples.size)
                track.play()
                current = track
            } catch (error: Exception) {
                Log.w(TAG, "tone playback failed", error)
            }
        }
    }

    fun stop() {
        if (executor.isShutdown) return
        executor.execute { releaseCurrent() }
    }

    fun release() {
        if (executor.isShutdown) return
        executor.execute { releaseCurrent() }
        executor.shutdown()
    }

    private fun releaseCurrent() {
        val track = current ?: return
        current = null
        try {
            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop()
        } catch (_: IllegalStateException) {
        }
        track.release()
    }

    private fun render(notes: List<ToneNote>): ShortArray {
        val lengths = notes.map { (SAMPLE_RATE * it.durationMs.coerceIn(0, MAX_NOTE_MS) / 1000) }
        val output = ShortArray(lengths.sum())
        var offset = 0
        notes.forEachIndexed { index, note ->
            val length = lengths[index]
            val amplitude = note.volume.coerceIn(0f, 1f) * Short.MAX_VALUE * HEADROOM
            if (note.frequencyHz > 0 && amplitude > 0) {
                // Short linear fades avoid audible clicks at note boundaries.
                val attack = min(SAMPLE_RATE * 8 / 1000, length / 4).coerceAtLeast(1)
                val release = min(SAMPLE_RATE * 30 / 1000, length / 3).coerceAtLeast(1)
                for (i in 0 until length) {
                    val envelope = when {
                        i < attack -> i.toFloat() / attack
                        i > length - release -> (length - i).toFloat() / release
                        else -> 1f
                    }
                    val phase = 2.0 * PI * note.frequencyHz * i / SAMPLE_RATE
                    output[offset + i] = (sin(phase) * amplitude * envelope).toInt().toShort()
                }
            }
            offset += length
        }
        return output
    }

    private companion object {
        const val TAG = "TonePlayer"
        const val SAMPLE_RATE = 44100
        const val MAX_NOTE_MS = 2000
        const val HEADROOM = 0.85f
    }
}
