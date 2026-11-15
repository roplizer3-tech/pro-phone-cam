package com.prophone.cam

import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class UsbSocketServer(
    private val port: Int = 5000,
    private val onCommandReceived: (JSONObject) -> Unit,
    private val onConnectionStateChanged: (Boolean, String?) -> Unit
) {
    companion object {
        private const val TAG = "UsbSocketServer"
        private val MAGIC_BYTES = byteArrayOf('P'.code.toByte(), 'P'.code.toByte(), 'C'.code.toByte(), 'M'.code.toByte())
        const val TYPE_VIDEO_FRAME: Byte = 0x01
        const val TYPE_TELEMETRY: Byte = 0x02
        const val TYPE_ACK: Byte = 0x03
        private const val HEADER_SIZE = 16
        private const val MAX_QUEUE_CAPACITY = 2
    }

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null
    private val isRunning = AtomicBoolean(false)
    private val isClientConnected = AtomicBoolean(false)

    private val frameQueue = ArrayBlockingQueue<FramePacket>(MAX_QUEUE_CAPACITY)
    private val serverScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    data class FramePacket(
        val type: Byte,
        val flags: Byte,
        val cameraIdIndex: Short,
        val timestampMs: Int,
        val payload: ByteArray
    )

    fun start() {
        if (isRunning.getAndSet(true)) return

        serverScope.launch {
            try {
                serverSocket = ServerSocket(port).apply {
                    reuseAddress = true
                }
                Log.i(TAG, "USB Socket Server successfully listening on port $port")
                onConnectionStateChanged(false, "Listening on port $port (Waiting for USB/PC...)")

                while (isRunning.get()) {
                    try {
                        val socket = serverSocket?.accept() ?: break
                        handleClient(socket)
                    } catch (e: Exception) {
                        if (isRunning.get()) {
                            Log.e(TAG, "Error accepting client: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Fatal ServerSocket failure: ${e.message}", e)
                onConnectionStateChanged(false, "Server Error: ${e.message}")
            }
        }

        serverScope.launch {
            val headerBuffer = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.BIG_ENDIAN)
            while (isRunning.get()) {
                try {
                    val packet = frameQueue.poll(50, TimeUnit.MILLISECONDS) ?: continue
                    val out = outputStream
                    if (out != null && isClientConnected.get()) {
                        headerBuffer.clear()
                        headerBuffer.put(MAGIC_BYTES)
                        headerBuffer.put(packet.type)
                        headerBuffer.put(packet.flags)
                        headerBuffer.putShort(packet.cameraIdIndex)
                        headerBuffer.putInt(packet.payload.size)
                        headerBuffer.putInt(packet.timestampMs)

                        out.write(headerBuffer.array())
                        out.write(packet.payload)
                        out.flush()
                    }
                } catch (e: SocketException) {
                    disconnectClient()
                } catch (e: Exception) {
                    Log.e(TAG, "Frame transmission error: ${e.message}")
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        disconnectClient()

        clientSocket = socket.apply {
            tcpNoDelay = true
            sendBufferSize = 512 * 1024
            receiveBufferSize = 64 * 1024
        }
        outputStream = BufferedOutputStream(socket.getOutputStream(), 128 * 1024)
        isClientConnected.set(true)
        onConnectionStateChanged(true, "Connected via USB (Port $port)")

        serverScope.launch {
            try {
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
                while (isClientConnected.get() && isRunning.get()) {
                    val line = reader.readLine() ?: break
                    if (line.isNotBlank()) {
                        try {
                            val json = JSONObject(line)
                            onCommandReceived(json)
                        } catch (je: Exception) {
                            Log.w(TAG, "Malformed command JSON from PC: $line")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.i(TAG, "Client input stream ended: ${e.message}")
            } finally {
                disconnectClient()
            }
        }
    }

    fun enqueueVideoFrame(
        payload: ByteArray,
        cameraIdIndex: Short,
        flags: Byte,
        timestampMs: Int
    ) {
        if (!isClientConnected.get()) return

        val packet = FramePacket(
            type = TYPE_VIDEO_FRAME,
            flags = flags,
            cameraIdIndex = cameraIdIndex,
            timestampMs = timestampMs,
            payload = payload
        )

        if (!frameQueue.offer(packet)) {
            frameQueue.poll()
            frameQueue.offer(packet)
        }
    }

    fun sendTelemetry(jsonString: String) {
        if (!isClientConnected.get()) return
        val payload = jsonString.toByteArray(Charsets.UTF_8)
        val packet = FramePacket(
            type = TYPE_TELEMETRY,
            flags = 0,
            cameraIdIndex = 0,
            timestampMs = (System.currentTimeMillis() % Int.MAX_VALUE).toInt(),
            payload = payload
        )
        frameQueue.offer(packet)
    }

    private fun disconnectClient() {
        if (!isClientConnected.getAndSet(false)) return
        try {
            outputStream?.close()
            outputStream = null
            clientSocket?.close()
            clientSocket = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing client: ${e.message}")
        }
        frameQueue.clear()
        onConnectionStateChanged(false, "PC Disconnected (Listening on Port $port...)")
    }

    fun stop() {
        isRunning.set(false)
        disconnectClient()
        try {
            serverSocket?.close()
            serverSocket = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing server socket: ${e.message}")
        }
        serverScope.cancel()
    }
}
