package com.balancedetect.balance_detect

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Runs MediaPipe Pose Landmarker on camera frames sent from Dart.
 *
 * Channel `com.balancedetect/pose`:
 * - `initialize` {model?: String, delegate?: "gpu" | "cpu"} -> {delegate: String}
 * - `detect` {bytes: Uint8List (NV21), width, height, bytesPerRow, rotation, timestampMs}
 *     -> null when no person is found, otherwise
 *        {width, height, landmarks: Float32List(33 * 5), worldLandmarks: Float32List(33 * 3), inferenceMs}
 * - `close` -> null
 *
 * The frame is rotated upright here, before inference, so the returned
 * normalized landmarks (0..1) are relative to the upright, unmirrored image of
 * size width x height. Each landmark is [x, y, z, visibility, presence]; each
 * world landmark is [x, y, z] in meters with the origin between the hips.
 *
 * All MediaPipe work runs on one background thread; replies are posted back to
 * the main thread as Flutter requires.
 */
class PoseLandmarkerBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Owned by the executor thread only.
    private var landmarker: PoseLandmarker? = null
    private var modelPath: String = DEFAULT_MODEL
    private var activeDelegate: Delegate = Delegate.CPU
    private var lastTimestampMs = -1L
    private var pixels = IntArray(0)
    private var bitmap: Bitmap? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "detect" -> detect(call, result)
            "close" -> runOnExecutor(result) {
                closeLandmarker()
                null
            }
            else -> result.notImplemented()
        }
    }

    fun release() {
        if (executor.isShutdown) return
        executor.execute { closeLandmarker() }
        executor.shutdown()
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val model = call.argument<String>("model") ?: DEFAULT_MODEL
        val wantGpu = (call.argument<String>("delegate") ?: "gpu").lowercase() == "gpu"
        runOnExecutor(result) {
            closeLandmarker()
            modelPath = model
            landmarker = if (wantGpu) {
                try {
                    create(Delegate.GPU)
                } catch (error: Exception) {
                    Log.w(TAG, "GPU delegate unavailable, using CPU", error)
                    create(Delegate.CPU)
                }
            } else {
                create(Delegate.CPU)
            }
            mapOf("delegate" to activeDelegate.name.lowercase())
        }
    }

    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val timestampMs = call.argument<Number>("timestampMs")?.toLong()
        if (bytes == null || width == null || height == null || timestampMs == null) {
            result.error("invalid_arguments", "bytes, width, height and timestampMs are required", null)
            return
        }
        val bytesPerRow = call.argument<Int>("bytesPerRow") ?: width
        val rotation = ((call.argument<Int>("rotation") ?: 0) % 360 + 360) % 360
        if (rotation % 90 != 0) {
            result.error("invalid_arguments", "rotation must be a multiple of 90", null)
            return
        }
        runOnExecutor(result) {
            if (landmarker == null) throw IllegalStateException("Pose landmarker is not initialized")
            val image = nv21ToUprightBitmap(bytes, width, height, bytesPerRow, rotation)
            // VIDEO mode rejects timestamps that do not strictly increase.
            val timestamp = if (timestampMs > lastTimestampMs) timestampMs else lastTimestampMs + 1
            lastTimestampMs = timestamp

            val started = SystemClock.elapsedRealtime()
            val output = try {
                runDetection(image, timestamp)
            } catch (error: Exception) {
                // Some GPUs accept the delegate at creation and fail on the
                // first frame. Fall back to CPU once instead of failing forever.
                if (activeDelegate != Delegate.GPU) throw error
                Log.w(TAG, "GPU inference failed, switching to CPU", error)
                closeLandmarker()
                landmarker = create(Delegate.CPU)
                runDetection(image, timestamp)
            }
            toReply(output, image.width, image.height, SystemClock.elapsedRealtime() - started)
        }
    }

    private fun runDetection(image: Bitmap, timestampMs: Long): PoseLandmarkerResult {
        val mpImage = BitmapImageBuilder(image).build()
        return landmarker!!.detectForVideo(mpImage, timestampMs)
    }

    private fun create(delegate: Delegate): PoseLandmarker {
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(modelPath)
                    .setDelegate(delegate)
                    .build(),
            )
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(MIN_CONFIDENCE)
            .setMinPosePresenceConfidence(MIN_CONFIDENCE)
            .setMinTrackingConfidence(MIN_CONFIDENCE)
            .setOutputSegmentationMasks(false)
            .build()
        val created = PoseLandmarker.createFromOptions(context, options)
        activeDelegate = delegate
        lastTimestampMs = -1L
        return created
    }

    private fun closeLandmarker() {
        landmarker?.close()
        landmarker = null
    }

    private fun toReply(
        output: PoseLandmarkerResult,
        width: Int,
        height: Int,
        inferenceMs: Long,
    ): Map<String, Any>? {
        val pose = output.landmarks().firstOrNull() ?: return null
        val landmarks = FloatArray(pose.size * 5)
        pose.forEachIndexed { i, point ->
            landmarks[i * 5] = point.x()
            landmarks[i * 5 + 1] = point.y()
            landmarks[i * 5 + 2] = point.z()
            landmarks[i * 5 + 3] = point.visibility().orElse(0f)
            landmarks[i * 5 + 4] = point.presence().orElse(0f)
        }
        val world = output.worldLandmarks().firstOrNull().orEmpty()
        val worldLandmarks = FloatArray(world.size * 3)
        world.forEachIndexed { i, point ->
            worldLandmarks[i * 3] = point.x()
            worldLandmarks[i * 3 + 1] = point.y()
            worldLandmarks[i * 3 + 2] = point.z()
        }
        return mapOf(
            "width" to width,
            "height" to height,
            "landmarks" to landmarks,
            "worldLandmarks" to worldLandmarks,
            "inferenceMs" to inferenceMs.toInt(),
        )
    }

    /**
     * Converts an NV21 frame to ARGB and rotates it clockwise by [rotation]
     * degrees in the same pass. [rotation] uses the same meaning as ML Kit's
     * InputImageRotation: how far the sensor image must turn to be upright.
     */
    private fun nv21ToUprightBitmap(
        nv21: ByteArray,
        width: Int,
        height: Int,
        stride: Int,
        rotation: Int,
    ): Bitmap {
        val uvOffset = stride * height
        require(stride >= width && nv21.size >= uvOffset + stride * (height / 2)) {
            "NV21 buffer is too small: ${nv21.size} bytes for ${width}x$height (stride $stride)"
        }
        val swapsAxes = rotation == 90 || rotation == 270
        val outWidth = if (swapsAxes) height else width
        val outHeight = if (swapsAxes) width else height
        if (pixels.size != width * height) pixels = IntArray(width * height)

        for (y in 0 until height) {
            val yRow = y * stride
            val uvRow = uvOffset + (y shr 1) * stride
            for (x in 0 until width) {
                val luma = ((nv21[yRow + x].toInt() and 0xff) - 16).coerceAtLeast(0)
                val uvIndex = uvRow + (x and 1.inv())
                val v = (nv21[uvIndex].toInt() and 0xff) - 128
                val u = (nv21[uvIndex + 1].toInt() and 0xff) - 128
                val y1192 = 1192 * luma
                val r = (y1192 + 1634 * v).coerceIn(0, 262143)
                val g = (y1192 - 833 * v - 400 * u).coerceIn(0, 262143)
                val b = (y1192 + 2066 * u).coerceIn(0, 262143)
                val argb = -0x1000000 or
                    ((r shl 6) and 0xff0000) or
                    ((g shr 2) and 0xff00) or
                    ((b shr 10) and 0xff)
                val target = when (rotation) {
                    90 -> x * outWidth + (height - 1 - y)
                    180 -> (height - 1 - y) * outWidth + (width - 1 - x)
                    270 -> (width - 1 - x) * outWidth + y
                    else -> y * outWidth + x
                }
                pixels[target] = argb
            }
        }

        val reusable = bitmap
        val output = if (reusable != null && reusable.width == outWidth && reusable.height == outHeight) {
            reusable
        } else {
            reusable?.recycle()
            Bitmap.createBitmap(outWidth, outHeight, Bitmap.Config.ARGB_8888).also { bitmap = it }
        }
        output.setPixels(pixels, 0, outWidth, 0, 0, outWidth, outHeight)
        return output
    }

    private fun runOnExecutor(result: MethodChannel.Result, work: () -> Any?) {
        if (executor.isShutdown) {
            result.error("closed", "Pose landmarker has been released", null)
            return
        }
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                Log.e(TAG, "pose landmarker call failed", error)
                mainHandler.post { result.error("pose_error", error.message, null) }
            }
        }
    }

    private companion object {
        const val TAG = "PoseLandmarkerBridge"
        const val DEFAULT_MODEL = "pose_landmarker_full.task"
        const val MIN_CONFIDENCE = 0.5f
    }
}
