package com.pieblock.remote

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState

/// 汇总手机传感器位姿数据：
/// - GAME_ROTATION_VECTOR -> RPY（度）
/// - ARCore VIO -> XYZ（毫米，相对原点）
class PoseDataSource(context: Context) : SensorEventListener {

    companion object {
        private const val TAG = "PoseDataSource"
        /// 手机原始加速度计单位是 m/s²，我们用 mm，乘以 1000
        private const val M_TO_MM = 1000.0f
    }

    private val sensorManager: SensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val gameRotationSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
    private val appContext: Context = context

    /// ARCore 会话（可为 null，表示 ARCore 不可用）
    var arSession: Session? = null
        private set

    /// 当前 RPY（度），基于 GAME_ROTATION_VECTOR
    var rpy = FloatArray(3)
        private set

    /// 当前手机空间位置（mm），基于 ARCore VIO
    var position = FloatArray(3)
        private set

    /// ARCore 追踪状态
    var trackingState = TrackingState.PAUSED
        private set

    /// 原点（重置时记录）
    private var originPosition = FloatArray(3)
    private var originQuaternion = FloatArray(4)
    private var hasOrigin = false

    /// 回调
    var onPoseUpdated: ((position: FloatArray, rpy: FloatArray) -> Unit)? = null
    var onTrackingStateChanged: ((TrackingState) -> Unit)? = null

    private val rotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)

    fun start() {
        gameRotationSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        try {
            arSession = Session(appContext)
            val config = Config(arSession!!)
            config.instantPlacementMode = Config.InstantPlacementMode.DISABLED
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            arSession!!.configure(config)
            arSession!!.resume()
            Log.i(TAG, "ARCore session started")
        } catch (e: Exception) {
            Log.w(TAG, "ARCore not available: ${e.message}")
            arSession = null
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        arSession?.pause()
        hasOrigin = false
    }

    /// 重置原点：以当前位姿为零点
    fun resetOrigin() {
        originPosition = position.copyOf()
        // GAME_ROTATION_VECTOR 的四元数也记录
        System.arraycopy(quaternionBuffer, 0, originQuaternion, 0, 4)
        hasOrigin = true
    }

    /// ARCore 帧更新（由 MainActivity 的定时器驱动）
    fun updateArFrame(frame: Frame?) {
        if (frame == null) {
            if (trackingState != TrackingState.PAUSED) {
                trackingState = TrackingState.PAUSED
                onTrackingStateChanged?.invoke(trackingState)
            }
            return
        }
        val camera = frame.camera
        val newState = camera.trackingState
        if (newState != trackingState) {
            trackingState = newState
            onTrackingStateChanged?.invoke(trackingState)
            // 从暂停恢复到追踪时，重置原点避免跳跃
            if (newState == TrackingState.TRACKING) {
                val t = camera.pose.translation
                originPosition = floatArrayOf(t[0], t[1], t[2])
                hasOrigin = true
            }
        }
        if (trackingState == TrackingState.TRACKING) {
            val t = camera.pose.translation
            // 相对原点的位移，转换为 mm
            position[0] = (t[0] - originPosition[0]) * M_TO_MM
            position[1] = (t[1] - originPosition[1]) * M_TO_MM
            position[2] = (t[2] - originPosition[2]) * M_TO_MM
        }
        // 追踪丢失时 position 保持上一帧值不变（冻结），不调用 notifyUpdate
        if (trackingState == TrackingState.TRACKING) {
            notifyUpdate()
        }
    }

    // --- SensorEventListener ---

    private val quaternionBuffer = FloatArray(4)

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (event.sensor.type == Sensor.TYPE_GAME_ROTATION_VECTOR) {
            // 传感器给出的四元数 (x, y, z, w)
            quaternionBuffer[0] = event.values[0]
            quaternionBuffer[1] = event.values[1]
            quaternionBuffer[2] = event.values[2]
            quaternionBuffer[3] = if (event.values.size >= 4) event.values[3] else {
                // 某些设备只给 x,y,z，计算 w
                val s = 1f - quaternionBuffer[0] * quaternionBuffer[0] -
                        quaternionBuffer[1] * quaternionBuffer[1] -
                        quaternionBuffer[2] * quaternionBuffer[2]
                if (s > 0) kotlin.math.sqrt(s) else 0f
            }

            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
            SensorManager.getOrientation(rotationMatrix, orientationAngles)

            // 弧度 -> 度
            // orientationAngles: [0]=azimuth(yaw), [1]=pitch, [2]=roll
            rpy[0] = Math.toDegrees(orientationAngles[2].toDouble()).toFloat() // roll
            rpy[1] = Math.toDegrees(orientationAngles[1].toDouble()).toFloat() // pitch
            rpy[2] = Math.toDegrees(orientationAngles[0].toDouble()).toFloat() // yaw

            // RPY 独立于 ARCore 发送：即使 ARCore 未追踪，陀螺仪姿态也必须工作。
            // position 保持当前值（ARCore 未追踪时冻结为 0）。
            notifyUpdate()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun notifyUpdate() {
        onPoseUpdated?.invoke(position.copyOf(), rpy.copyOf())
    }
}
