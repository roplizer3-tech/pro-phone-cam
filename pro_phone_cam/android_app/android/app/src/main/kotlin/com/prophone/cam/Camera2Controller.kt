package com.prophone.cam

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

class Camera2Controller(
    private val context: Context,
    private val onFrameReady: (ByteArray, Short, Int) -> Unit
) {
    companion object {
        private const val TAG = "Camera2Controller"
        private const val TARGET_WIDTH = 1920
        private const val TARGET_HEIGHT = 1080
    }

    private val cameraManager: CameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var previewRequestBuilder: CaptureRequest.Builder? = null
    private var imageReader: ImageReader? = null

    private val cameraOpenCloseLock = Semaphore(1)
    private var currentCameraId: String = "0"
    private var currentCameraIndexShort: Short = 0

    private var characteristics: CameraCharacteristics? = null
    private var sensorArraySize: Rect? = null
    private var zoomRatioRange: Range<Float>? = null
    private var exposureRange: Range<Int>? = null
    private var isTorchAvailable: Boolean = false

    data class DiscoveredCamera(
        val id: String,
        val facing: String,
        val label: String,
        val focalLengthMm: Float,
        val zoomMin: Float,
        val zoomMax: Float,
        val supports60fps: Boolean,
        val hasFlash: Boolean
    )

    fun startBackgroundThread() {
        if (backgroundThread == null) {
            backgroundThread = HandlerThread("Camera2Background").apply { start() }
            backgroundHandler = Handler(backgroundThread!!.looper)
        }
    }

    fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread: ${e.message}")
        }
    }

    fun enumerateCameras(): List<DiscoveredCamera> {
        val list = mutableListOf<DiscoveredCamera>()
        try {
            for (id in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val facingInt = chars.get(CameraCharacteristics.LENS_FACING) ?: continue
                val facingStr = if (facingInt == CameraCharacteristics.LENS_FACING_FRONT) "front" else "back"

                val focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                val focalLength = focalLengths?.firstOrNull() ?: 4.0f

                val label = when {
                    facingInt == CameraCharacteristics.LENS_FACING_FRONT -> "Front Selfie Camera"
                    focalLength < 2.8f -> "Ultra-Wide Sensor (${String.format("%.1f", focalLength)}mm)"
                    focalLength > 7.0f -> "Telephoto Sensor (${String.format("%.1f", focalLength)}mm)"
                    else -> "Main Primary Sensor 108MP (${String.format("%.1f", focalLength)}mm)"
                }

                val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                val supports60 = fpsRanges?.any { it.upper >= 60 } ?: false

                var minZ = 1.0f
                var maxZ = 10.0f
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val zRange = chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
                    if (zRange != null) {
                        minZ = zRange.lower
                        maxZ = zRange.upper
                    }
                } else {
                    val maxDigital = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1.0f
                    maxZ = maxDigital
                }

                val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false

                list.add(
                    DiscoveredCamera(
                        id = id,
                        facing = facingStr,
                        label = label,
                        focalLengthMm = focalLength,
                        zoomMin = minZ,
                        zoomMax = maxZ,
                        supports60fps = supports60,
                        hasFlash = hasFlash
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error enumerating cameras: ${e.message}", e)
        }
        return list
    }

    fun getCamerasJson(): String {
        val cameras = enumerateCameras()
        val jsonArray = JSONArray()
        for (cam in cameras) {
            val obj = JSONObject().apply {
                put("id", cam.id)
                put("facing", cam.facing)
                put("label", cam.label)
                put("focal_length_mm", cam.focalLengthMm.toDouble())
                put("zoom_min", cam.zoomMin.toDouble())
                put("zoom_max", cam.zoomMax.toDouble())
                put("supports_60fps", cam.supports60fps)
                put("has_flash", cam.hasFlash)
            }
            jsonArray.put(obj)
        }
        return JSONObject().apply {
            put("type", "camera_list")
            put("cameras", jsonArray)
        }.toString()
    }

    @SuppressLint("MissingPermission")
    fun openCamera(cameraId: String) {
        startBackgroundThread()

        try {
            if (!cameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                throw RuntimeException("Timeout acquiring camera lock")
            }

            closeCamera()

            currentCameraId = cameraId
            currentCameraIndexShort = cameraId.toShortOrNull() ?: 0
            characteristics = cameraManager.getCameraCharacteristics(cameraId)

            sensorArraySize = characteristics?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            exposureRange = characteristics?.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
            isTorchAvailable = characteristics?.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                zoomRatioRange = characteristics?.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
            }

            imageReader = ImageReader.newInstance(TARGET_WIDTH, TARGET_HEIGHT, ImageFormat.JPEG, 2).apply {
                setOnImageAvailableListener({ reader ->
                    val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                    try {
                        val planes = image.planes
                        if (planes.isNotEmpty()) {
                            val buffer = planes[0].buffer
                            val bytes = ByteArray(buffer.remaining())
                            buffer.get(bytes)
                            val timestampMs = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                            onFrameReady(bytes, currentCameraIndexShort, timestampMs)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Frame buffer extraction error: ${e.message}")
                    } finally {
                        image.close()
                    }
                }, backgroundHandler)
            }

            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    cameraDevice = camera
                    createCaptureSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    cameraOpenCloseLock.release()
                    camera.close()
                    cameraDevice = null
                }
            }, backgroundHandler)

        } catch (e: Exception) {
            cameraOpenCloseLock.release()
            Log.e(TAG, "Failed opening camera $cameraId: ${e.message}", e)
        }
    }

    private fun createCaptureSession() {
        val device = cameraDevice ?: return
        val reader = imageReader ?: return

        try {
            val surface = reader.surface
            previewRequestBuilder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(surface)

                val fpsRanges = characteristics?.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                val target60 = fpsRanges?.find { it.upper >= 60 && it.lower >= 30 }
                    ?: fpsRanges?.maxByOrNull { it.upper }

                if (target60 != null) {
                    set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, target60)
                }

                set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
                set(CaptureRequest.JPEG_QUALITY, 88.toByte())
            }

            device.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (cameraDevice == null) return
                    captureSession = session
                    try {
                        previewRequestBuilder?.let { builder ->
                            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start repeating stream: ${e.message}")
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "CameraCaptureSession configuration failed")
                }
            }, backgroundHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Capture session creation error: ${e.message}", e)
        }
    }

    fun setZoom(zoomRatio: Float) {
        val builder = previewRequestBuilder ?: return
        val session = captureSession ?: return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && zoomRatioRange != null) {
                val clamped = zoomRatio.coerceIn(zoomRatioRange!!.lower, zoomRatioRange!!.upper)
                builder.set(CaptureRequest.CONTROL_ZOOM_RATIO, clamped)
            } else {
                val activeRect = sensorArraySize ?: return
                val maxZoom = characteristics?.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1.0f
                val clamped = zoomRatio.coerceIn(1.0f, maxZoom)

                val cropW = (activeRect.width() / clamped).toInt()
                val cropH = (activeRect.height() / clamped).toInt()
                val left = (activeRect.width() - cropW) / 2
                val top = (activeRect.height() - cropH) / 2
                val cropRect = Rect(left, top, left + cropW, top + cropH)
                builder.set(CaptureRequest.SCALER_CROP_REGION, cropRect)
            }
            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting zoom ratio: ${e.message}")
        }
    }

    fun setFocus(mode: String, focusDistanceNormalized: Float = 0.0f) {
        val builder = previewRequestBuilder ?: return
        val session = captureSession ?: return

        try {
            if (mode.equals("manual", ignoreCase = true)) {
                builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF)
                val minFocusDist = characteristics?.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0.0f
                val distance = (1.0f - focusDistanceNormalized.coerceIn(0.0f, 1.0f)) * minFocusDist
                builder.set(CaptureRequest.LENS_FOCUS_DISTANCE, distance)
            } else {
                builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            }
            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting focus: ${e.message}")
        }
    }

    fun setExposure(evIndex: Int) {
        val builder = previewRequestBuilder ?: return
        val session = captureSession ?: return
        val range = exposureRange ?: return

        try {
            val clamped = evIndex.coerceIn(range.lower, range.upper)
            builder.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, clamped)
            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting exposure: ${e.message}")
        }
    }

    fun setWhiteBalance(mode: String) {
        val builder = previewRequestBuilder ?: return
        val session = captureSession ?: return

        val awbMode = when (mode.lowercase()) {
            "daylight" -> CaptureRequest.CONTROL_AWB_MODE_DAYLIGHT
            "cloudy" -> CaptureRequest.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT
            "fluorescent" -> CaptureRequest.CONTROL_AWB_MODE_FLUORESCENT
            "incandescent" -> CaptureRequest.CONTROL_AWB_MODE_INCANDESCENT
            else -> CaptureRequest.CONTROL_AWB_MODE_AUTO
        }

        try {
            builder.set(CaptureRequest.CONTROL_AWB_MODE, awbMode)
            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting AWB: ${e.message}")
        }
    }

    fun setTorch(enabled: Boolean) {
        if (!isTorchAvailable) return
        val builder = previewRequestBuilder ?: return
        val session = captureSession ?: return

        try {
            builder.set(
                CaptureRequest.FLASH_MODE,
                if (enabled) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF
            )
            session.setRepeatingRequest(builder.build(), null, backgroundHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Error toggling torch: ${e.message}")
        }
    }

    fun closeCamera() {
        try {
            captureSession?.stopRepeating()
            captureSession?.close()
            captureSession = null

            cameraDevice?.close()
            cameraDevice = null

            imageReader?.close()
            imageReader = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing camera: ${e.message}")
        }
    }

    fun release() {
        closeCamera()
        stopBackgroundThread()
    }
}
