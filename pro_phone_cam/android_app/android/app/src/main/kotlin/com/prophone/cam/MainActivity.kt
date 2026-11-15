package com.prophone.cam

import android.os.BatteryManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.prophone.cam/methods"
        private const val EVENT_CHANNEL = "com.prophone.cam/events"
    }

    private var cameraController: Camera2Controller? = null
    private var usbServer: UsbSocketServer? = null
    private var eventSink: EventChannel.EventSink? = null

    private var isBlackScreenActive = false
    private val activityScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cameraController = Camera2Controller(this) { frameBytes, cameraIdIndex, timestampMs ->
            val flags: Byte = if (isBlackScreenActive) 0x02 else 0x00
            usbServer?.enqueueVideoFrame(frameBytes, cameraIdIndex, flags, timestampMs)
        }

        usbServer = UsbSocketServer(
            port = 5000,
            onCommandReceived = { json -> handleIncomingHostCommand(json) },
            onConnectionStateChanged = { isConnected, message ->
                activityScope.launch {
                    val map = hashMapOf(
                        "event" to "connection_state",
                        "connected" to isConnected,
                        "message" to (message ?: "")
                    )
                    eventSink?.success(map)
                }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startServer" -> {
                    usbServer?.start()
                    cameraController?.openCamera("0")
                    startTelemetryLoop()
                    result.success(true)
                }
                "stopServer" -> {
                    usbServer?.stop()
                    cameraController?.closeCamera()
                    result.success(true)
                }
                "getCameras" -> {
                    val jsonStr = cameraController?.getCamerasJson() ?: "{}"
                    result.success(jsonStr)
                }
                "switchCamera" -> {
                    val cameraId = call.argument<String>("cameraId") ?: "0"
                    cameraController?.openCamera(cameraId)
                    result.success(true)
                }
                "setZoom" -> {
                    val ratio = call.argument<Double>("zoom")?.toFloat() ?: 1.0f
                    cameraController?.setZoom(ratio)
                    result.success(true)
                }
                "setFocus" -> {
                    val mode = call.argument<String>("mode") ?: "auto"
                    val dist = call.argument<Double>("distance")?.toFloat() ?: 0.0f
                    cameraController?.setFocus(mode, dist)
                    result.success(true)
                }
                "setExposure" -> {
                    val ev = call.argument<Int>("ev") ?: 0
                    cameraController?.setExposure(ev)
                    result.success(true)
                }
                "setWhiteBalance" -> {
                    val mode = call.argument<String>("mode") ?: "auto"
                    cameraController?.setWhiteBalance(mode)
                    result.success(true)
                }
                "setTorch" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    cameraController?.setTorch(enabled)
                    result.success(true)
                }
                "setBlackScreenMode" -> {
                    isBlackScreenActive = call.argument<Boolean>("enabled") ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIncomingHostCommand(json: JSONObject) {
        val action = json.optString("action")
        when (action) {
            "get_cameras" -> {
                val camerasJson = cameraController?.getCamerasJson() ?: "{}"
                usbServer?.sendTelemetry(camerasJson)
            }
            "set_camera" -> {
                val id = json.optString("camera_id", "0")
                activityScope.launch {
                    cameraController?.openCamera(id)
                }
            }
            "set_zoom" -> {
                val ratio = json.optDouble("zoom_ratio", 1.0).toFloat()
                cameraController?.setZoom(ratio)
            }
            "set_focus_mode" -> {
                val mode = json.optString("mode", "auto")
                val dist = json.optDouble("focus_distance", 0.0).toFloat()
                cameraController?.setFocus(mode, dist)
            }
            "set_exposure" -> {
                val ev = json.optInt("ev", 0)
                cameraController?.setExposure(ev)
            }
            "set_wb" -> {
                val mode = json.optString("mode", "auto")
                cameraController?.setWhiteBalance(mode)
            }
            "set_torch" -> {
                val enabled = json.optBoolean("enabled", false)
                cameraController?.setTorch(enabled)
            }
            "set_power_save" -> {
                val enabled = json.optBoolean("enabled", false)
                isBlackScreenActive = enabled
                activityScope.launch {
                    eventSink?.success(
                        hashMapOf("event" to "power_save_toggled", "active" to enabled)
                    )
                }
            }
        }
    }

    private fun startTelemetryLoop() {
        activityScope.launch(Dispatchers.IO) {
            val batteryManager = getSystemService(BATTERY_SERVICE) as BatteryManager
            while (isActive) {
                try {
                    val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    val telemetryJson = JSONObject().apply {
                        put("type", "telemetry")
                        put("battery_level", batteryLevel)
                        put("black_screen", isBlackScreenActive)
                    }.toString()

                    usbServer?.sendTelemetry(telemetryJson)
                    delay(3000)
                } catch (e: Exception) {
                    delay(5000)
                }
            }
        }
    }

    override fun onDestroy() {
        activityScope.cancel()
        usbServer?.stop()
        cameraController?.release()
        super.onDestroy()
    }
}
