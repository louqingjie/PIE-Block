package com.pieblock.remote

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CAMERA_PERM_REQUEST = 2001
    }

    private lateinit var ipInput: EditText
    private lateinit var portInput: EditText
    private lateinit var connectBtn: Button
    private lateinit var scanBtn: Button
    private lateinit var disconnectBtn: Button
    private lateinit var resetBtn: Button
    private lateinit var statusText: TextView
    private lateinit var positionText: TextView
    private lateinit var rpyText: TextView
    private lateinit var trackingText: TextView
    private lateinit var previewView: PreviewView
    private lateinit var glSurfaceView: GLSurfaceView

    private var poseDataSource: PoseDataSource? = null
    private var webSocketClient: PoseWebSocketClient? = null
    private var qrScanner: QrScanner? = null
    private var arSession: Session? = null

    /// ARCore 会话是否处于活跃（前台）状态。onPause 时为 false，此时渲染线程不调 update()。
    @Volatile private var sessionActive = false

    /// UI 更新（位姿显示）在主线程
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    /// GLSurfaceView 渲染器：在 GL 线程调用 ARCore session.update()（ARCore 必需 GL 上下文）。
    private val arRenderer = object : GLSurfaceView.Renderer {
        /// ARCore 相机纹理 ID（必须在 GL 线程生成，并 setCameraTextureName）
        private var cameraTextureId = 0
        private var pendingSession: Session? = null

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            // 生成 ARCore 所需的相机纹理
            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            cameraTextureId = textures[0]
            pendingSession?.setCameraTextureName(cameraTextureId)
            pendingSession = null
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            val session = arSession
            if (session != null && width > 0 && height > 0) {
                try {
                    session.setDisplayGeometry(
                        windowManager.defaultDisplay.rotation, width, height)
                } catch (e: Exception) {
                    Log.w(TAG, "setDisplayGeometry error: ${e.message}")
                }
            }
        }

        override fun onDrawFrame(gl: GL10?) {
            val session = arSession
            val pds = poseDataSource
            if (session == null || pds == null || !sessionActive) return
            try {
                val frame = session.update()
                pds.updateArFrame(frame)
            } catch (e: Exception) {
                Log.w(TAG, "ARCore frame update error: ${e.message}")
            }
        }

        /// 在 GL 线程设置 ARCore 会话并确保相机纹理已配置
        fun setSession(session: Session?) {
            pendingSession = session
            if (cameraTextureId != 0 && session != null) {
                session.setCameraTextureName(cameraTextureId)
            }
        }
    }


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        ipInput = findViewById(R.id.ipInput)
        portInput = findViewById(R.id.portInput)
        connectBtn = findViewById(R.id.connectBtn)
        scanBtn = findViewById(R.id.scanBtn)
        disconnectBtn = findViewById(R.id.disconnectBtn)
        resetBtn = findViewById(R.id.resetBtn)
        statusText = findViewById(R.id.statusText)
        positionText = findViewById(R.id.positionText)
        rpyText = findViewById(R.id.rpyText)
        trackingText = findViewById(R.id.trackingText)
        previewView = findViewById(R.id.previewView)
        glSurfaceView = findViewById(R.id.glSurfaceView)

        // GLSurfaceView 提供 ARCore 所需的 OpenGL 上下文，渲染线程驱动 session.update()
        glSurfaceView.setEGLContextClientVersion(2)
        glSurfaceView.setRenderer(arRenderer)
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

        connectBtn.setOnClickListener { connect() }
        scanBtn.setOnClickListener { startScanning() }
        disconnectBtn.setOnClickListener { disconnect() }
        resetBtn.setOnClickListener {
            poseDataSource?.resetOrigin()
            webSocketClient?.sendResetOrigin()
            statusText.text = "已回中"
        }

        checkArCoreAvailability()
    }

    private fun checkArCoreAvailability() {
        val availability = ArCoreApk.getInstance().checkAvailability(this)
        when (availability) {
            ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
            ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> {
                trackingText.text = "ARCore 需要安装，正在请求..."
                Thread {
                    try {
                        val installStatus = ArCoreApk.getInstance().requestInstall(this, true)
                        runOnUiThread {
                            trackingText.text = if (installStatus == ArCoreApk.InstallStatus.INSTALLED)
                                "ARCore 已安装" else "ARCore 安装请求已发出"
                        }
                    } catch (e: Exception) {
                        runOnUiThread { trackingText.text = "ARCore 安装失败: ${e.message}" }
                    }
                }.start()
            }
            ArCoreApk.Availability.SUPPORTED_INSTALLED -> {
                trackingText.text = "ARCore 就绪"
            }
            else -> {
                trackingText.text = "ARCore 不可用: $availability"
            }
        }
    }

    private fun connect() {
        // ARCore 需要相机权限（Android 6+），未授权时先申请
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            statusText.text = "需要相机权限（ARCore 追踪用），请授权后重新连接"
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERM_REQUEST
            )
            return
        }
        val ip = ipInput.text.toString().trim()
        val port = portInput.text.toString().trim().ifEmpty { "19821" }
        if (ip.isEmpty()) {
            statusText.text = "请输入 PC IP 地址"
            return
        }
        val url = "ws://$ip:$port"
        statusText.text = "正在连接 $url ..."

        // 启动传感器
        poseDataSource = PoseDataSource(this).also { pds ->
            pds.start()
            pds.onPoseUpdated = { pos, rpy ->
                webSocketClient?.updatePose(pos, rpy)
                // 更新 UI
                mainHandler.post {
                    positionText.text = "X: %.1f  Y: %.1f  Z: %.1f mm".format(pos[0], pos[1], pos[2])
                    rpyText.text = "R: %.1f°  P: %.1f°  Y: %.1f°".format(rpy[0], rpy[1], rpy[2])
                }
            }
            pds.onTrackingStateChanged = { state ->
                mainHandler.post {
                    trackingText.text = when (state) {
                        TrackingState.TRACKING -> "ARCore: 追踪中"
                        TrackingState.PAUSED -> "ARCore: 追踪暂停（请缓慢移动手机）"
                        TrackingState.STOPPED -> "ARCore: 已停止"
                    }
                }
            }
        }

        // 把 ARCore 会话交给 GLSurfaceView 渲染线程驱动（sessionActive 已在前台为 true）
        arSession = poseDataSource?.arSession
        // 在 GL 线程配置会话（确保相机纹理已设置，ARCore update 前必需）
        glSurfaceView.queueEvent { arRenderer.setSession(arSession) }

        // 启动 WebSocket
        webSocketClient = PoseWebSocketClient(url, object : PoseWebSocketClient.ClientListener {
            override fun onConnected() {
                mainHandler.post {
                    statusText.text = "已连接 $url"
                    connectBtn.isEnabled = false
                    disconnectBtn.isEnabled = true
                    scanBtn.isEnabled = false
                    previewView.visibility = View.GONE
                }
            }

            override fun onDisconnected(reason: String) {
                mainHandler.post {
                    statusText.text = "已断开: $reason"
                    connectBtn.isEnabled = true
                    disconnectBtn.isEnabled = false
                    scanBtn.isEnabled = true
                }
            }

            override fun onMessage(message: org.json.JSONObject) {
                val type = message.optString("type", "")
                if (type == "clamp_warning") {
                    // 震动提醒
                    vibrate()
                    val axes = message.optJSONArray("axes")
                    val axesStr = if (axes != null) {
                        (0 until axes.length()).joinToString(", ") { axes.getString(it) }
                    } else ""
                    mainHandler.post {
                        statusText.text = "超界: $axesStr"
                    }
                } else if (type == "welcome") {
                    Log.i(TAG, "Server welcome: ${message.optString("server")}")
                } else if (type == "reset_ack") {
                    mainHandler.post { statusText.text = "服务端已确认回中" }
                }
            }

            override fun onError(error: String) {
                mainHandler.post { statusText.text = "错误: $error" }
            }
        }).also { it.start() }
    }

    private fun disconnect() {
        webSocketClient?.stop()
        webSocketClient = null
        sessionActive = false
        poseDataSource?.stop()
        poseDataSource = null
        arSession = null
        statusText.text = "已断开"
        connectBtn.isEnabled = true
        disconnectBtn.isEnabled = false
        scanBtn.isEnabled = true
    }

    private fun startScanning() {
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERM_REQUEST
            )
            return
        }
        previewView.visibility = View.VISIBLE
        qrScanner = QrScanner(this, this, previewView) { url ->
            // 解析 ws://ip:port
            runOnUiThread {
                val regex = Regex("ws://([^:]+):(\\d+)")
                val match = regex.find(url)
                if (match != null) {
                    ipInput.setText(match.groupValues[1])
                    portInput.setText(match.groupValues[2])
                    statusText.text = "已扫码: $url"
                } else {
                    statusText.text = "无法解析二维码: $url"
                }
                previewView.visibility = View.GONE
            }
            qrScanner?.stop()
            qrScanner = null
        }
        qrScanner?.start()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERM_REQUEST) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startScanning()
            } else {
                statusText.text = "需要相机权限才能扫码"
            }
        }
    }

    private fun vibrate() {
        val vibrator = getSystemService(Vibrator::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(80)
        }
    }

    override fun onResume() {
        super.onResume()
        sessionActive = true
        try {
            arSession?.resume()
        } catch (e: Exception) {
            Log.w(TAG, "ARCore resume failed: ${e.message}")
        }
        glSurfaceView.onResume()
    }

    override fun onPause() {
        super.onPause()
        sessionActive = false
        try {
            arSession?.pause()
        } catch (e: Exception) {
            // ignore
        }
        glSurfaceView.onPause()
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
    }
}
