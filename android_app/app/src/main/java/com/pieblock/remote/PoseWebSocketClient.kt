package com.pieblock.remote

import android.util.Log
import okhttp3.*
import okio.ByteString
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/// WebSocket 客户端：连接 Godot 仿真服务端，发送位姿 JSON，接收钳位警告。
class PoseWebSocketClient(
    private val url: String,
    private val listener: ClientListener
) {
    companion object {
        private const val TAG = "PoseWebSocket"
        private const val NORMAL_CLOSURE = 1000
        private const val RECONNECT_DELAY_MS = 1000L
        private const val MAX_RECONNECT_DELAY_MS = 16000L
    }

    interface ClientListener {
        fun onConnected()
        fun onDisconnected(reason: String)
        fun onMessage(message: JSONObject)
        fun onError(error: String)
    }

    private val client: OkHttpClient = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS) // WebSocket 不超时
        .pingInterval(10, TimeUnit.SECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private var connected = false
    private var shouldReconnect = false
    private var reconnectDelay = RECONNECT_DELAY_MS
    private var sendThread: Thread? = null
    @Volatile private var running = false

    /// 最新位姿数据（由 PoseDataSource 写入）
    @Volatile private var latestPosition: FloatArray = FloatArray(3)
    @Volatile private var latestRpy: FloatArray = FloatArray(3)
    @Volatile private var latestTimestamp: Long = 0

    fun start() {
        shouldReconnect = true
        running = true
        connect()
        startSendLoop()
    }

    fun stop() {
        shouldReconnect = false
        running = false
        sendThread?.interrupt()
        webSocket?.close(NORMAL_CLOSURE, "Client stopping")
        webSocket = null
    }

    /// 更新位姿数据（由 PoseDataSource 回调调用）
    fun updatePose(position: FloatArray, rpy: FloatArray) {
        latestPosition = position
        latestRpy = rpy
        latestTimestamp = System.currentTimeMillis()
    }

    fun isConnected(): Boolean = connected

    private fun connect() {
        if (!shouldReconnect) return
        val request = Request.Builder().url(url).build()
        Log.i(TAG, "Connecting to $url ...")
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(TAG, "WebSocket connected")
                connected = true
                reconnectDelay = RECONNECT_DELAY_MS
                // 发送 hello
                val hello = JSONObject()
                hello.put("type", "hello")
                hello.put("app", "PieBlockRemote")
                hello.put("version", 1)
                webSocket.send(hello.toString())
                listener.onConnected()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val msg = JSONObject(text)
                    listener.onMessage(msg)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse message: $text")
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                onMessage(webSocket, bytes.utf8())
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(NORMAL_CLOSURE, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "WebSocket closed: $code $reason")
                handleDisconnect(reason)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "WebSocket failure: ${t.message}")
                handleDisconnect(t.message ?: "unknown error")
            }
        })
    }

    private fun handleDisconnect(reason: String) {
        connected = false
        listener.onDisconnected(reason)
        if (shouldReconnect) {
            Log.i(TAG, "Reconnecting in ${reconnectDelay}ms ...")
            Thread {
                try {
                    Thread.sleep(reconnectDelay)
                } catch (e: InterruptedException) {
                    return@Thread
                }
                reconnectDelay = (reconnectDelay * 2).coerceAtMost(MAX_RECONNECT_DELAY_MS)
                connect()
            }.start()
        }
    }

    /// 发送循环：30Hz 发送位姿
    private fun startSendLoop() {
        sendThread = Thread {
            while (running) {
                try {
                    if (connected) {
                        val msg = JSONObject()
                        msg.put("type", "pose")
                        val pos = JSONObject()
                        pos.put("x", latestPosition[0])
                        pos.put("y", latestPosition[1])
                        pos.put("z", latestPosition[2])
                        msg.put("position", pos)
                        val rpy = JSONObject()
                        rpy.put("roll", latestRpy[0])
                        rpy.put("pitch", latestRpy[1])
                        rpy.put("yaw", latestRpy[2])
                        msg.put("rpy", rpy)
                        msg.put("ts", latestTimestamp)
                        webSocket?.send(msg.toString())
                    }
                    Thread.sleep(33) // ~30Hz
                } catch (e: InterruptedException) {
                    break
                }
            }
        }.also { it.start() }
    }

    /// 发送重置原点请求
    fun sendResetOrigin() {
        val msg = JSONObject()
        msg.put("type", "reset_origin")
        webSocket?.send(msg.toString())
    }
}
