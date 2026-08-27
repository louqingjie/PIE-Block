package cn.edu.cnu.pieblock_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Android USB-HID 传输桥：只负责枚举/打开/读写 STC32G「USB-ISP」HID 设备
 * （VID 0x34BF / PID 0x1001），不实现任何烧录协议——协议层在 Dart
 * pieblock_hid（与 Windows 侧一致）。
 *
 * 平台没有公开的 HidDevice 类，这里通过 UsbDeviceConnection 访问 HID 接口的
 * 中断端点。Android 官方规定中断端点只能在异步路径（UsbRequest + requestWait）
 * 上收发，同步 bulkTransfer 仅保证用于 bulk 端点——真机（Android 16）实测
 * bulkTransfer 写能返回但读永远收不到数据，因此读写全部走异步请求：
 *  - 打开后常驻挂一个中断 IN 请求（等价于 Windows HIDCLASS 打开设备后始终
 *    挂起的读 IRP），完成报告进入 inResults 队列，read 带超时取队列；
 *  - write 每次单独挂一个中断 OUT 请求，同样由 requestWait 线程派发完成。
 *
 * 与 Windows pieblock_hid.dll 的语义对齐：
 *  - write：发送一个 HID 报告。Windows hidapi 的缓冲区含前导 0x00 报告
 *    ID（65 字节），Android 中断端点传输的是 64 字节报告本体，因此这里
 *    去掉前导 0x00 后原样发送。
 *  - read：等待一个输入报告，超时返回空（null）。
 *  - cancel/close：置取消标志并关闭连接，使挂起的传输立即结束。
 *
 * 平台通道方法：list / open / write / read / cancel / close
 */
class UsbHidBridge(private val activity: MainActivity) {
    companion object {
        private const val TAG = "UsbHidBridge"
        const val VID = 0x34BF
        const val PID = 0x1001
        private const val ACTION_PERMISSION = "cn.edu.cnu.pieblock_app.USB_HID_PERMISSION"
        private const val REPORT_SIZE = 64
        private const val WRITE_TIMEOUT_MILLISECONDS = 3000L
    }

    private val usbManager = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val canceled = AtomicBoolean(false)

    @Volatile
    private var device: UsbDevice? = null

    @Volatile
    private var connection: UsbDeviceConnection? = null

    @Volatile
    private var hidInterface: UsbInterface? = null

    @Volatile
    private var inEndpoint: UsbEndpoint? = null

    @Volatile
    private var outEndpoint: UsbEndpoint? = null

    /** 常驻中断 IN 请求及缓冲区：打开后始终挂起在内核，响应一到即被收下。 */
    @Volatile
    private var inRequest: UsbRequest? = null

    @Volatile
    private var inBuffer: ByteBuffer? = null

    @Volatile
    private var pendingWrite: UsbRequest? = null

    /** 已完成的中断 IN 报告；空数组为线程退出标记（连接已失效）。 */
    private val inResults = LinkedBlockingQueue<ByteArray>()

    /** 已完成的中断 OUT 写请求；false 为线程退出标记。 */
    private val writeResults = LinkedBlockingQueue<Boolean>()

    /** requestWait 专用线程；generation 用于区分会话，避免旧线程污染新会话队列。 */
    @Volatile
    private var ioThread: Thread? = null
    private val ioGeneration = AtomicLong(0)
    private val running = AtomicBoolean(false)

    private var pendingOpenResult: MethodChannel.Result? = null

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_PERMISSION) return
            val granted = intent.getBooleanExtra(
                UsbManager.EXTRA_PERMISSION_GRANTED,
                false,
            )
            val result = pendingOpenResult
            pendingOpenResult = null
            if (result == null) return
            if (!granted) {
                replySuccess(result, false)
                return
            }
            executor.execute { replySuccess(result, openDeviceLocked()) }
        }
    }

    init {
        val filter = IntentFilter(ACTION_PERMISSION)
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(permissionReceiver, filter)
        }
    }

    fun dispose() {
        runCatching { activity.unregisterReceiver(permissionReceiver) }
        closeNow()
        executor.shutdown()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> replySuccess(result, listDevices())
            "open" -> open(result)
            "write" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    replySuccess(result, false)
                    return
                }
                executor.execute { replySuccess(result, writeReport(bytes)) }
            }
            "read" -> {
                val timeout = (call.arguments as? Number)?.toInt() ?: 3000
                executor.execute { replySuccess(result, readReport(timeout)) }
            }
            "cancel" -> {
                executor.execute {
                    cancelNow()
                    replySuccess(result, null)
                }
            }
            "close" -> {
                executor.execute {
                    closeNow()
                    replySuccess(result, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** MethodChannel.Result 只允许在主线程回调，统一经主线程 Handler 转发。 */
    private fun replySuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun matches(dev: UsbDevice): Boolean =
        dev.vendorId == VID && dev.productId == PID

    private fun listDevices(): List<Map<String, Any?>> =
        usbManager.deviceList.values
            .filter { matches(it) }
            .map {
                mapOf(
                    "deviceName" to it.deviceName,
                    "productName" to (it.productName ?: "STC USB-ISP"),
                    "permission" to usbManager.hasPermission(it),
                )
            }

    private fun open(result: MethodChannel.Result) {
        val found = usbManager.deviceList.values.firstOrNull { matches(it) }
        if (found == null) {
            replySuccess(result, false)
            return
        }
        device = found
        if (usbManager.hasPermission(found)) {
            executor.execute { replySuccess(result, openDeviceLocked()) }
            return
        }
        if (pendingOpenResult != null) {
            replySuccess(result, false)
            return
        }
        pendingOpenResult = result
        val intent = Intent(ACTION_PERMISSION).setPackage(activity.packageName)
        val flags = PendingIntent.FLAG_ONE_SHOT or
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pendingIntent = PendingIntent.getBroadcast(activity, 0, intent, flags)
        Log.d(TAG, "open: 请求 USB 权限 ${found.deviceName}")
        usbManager.requestPermission(found, pendingIntent)
    }

    // queue(ByteBuffer, int) 全版本可用（minSdk 24）；替代 API queue(ByteBuffer)
    // 仅最新平台提供，故保留旧签名并抑制弃用警告。
    @Suppress("DEPRECATION")
    private fun openDeviceLocked(): Boolean {
        closeNow()
        val dev = device ?: return false
        val conn = try {
            usbManager.openDevice(dev)
        } catch (error: Exception) {
            Log.w(TAG, "open: openDevice 异常：$error")
            return false
        }
        if (conn == null) {
            Log.w(TAG, "open: openDevice 返回空")
            return false
        }
        var opened = false
        return try {
            val iface = (0 until dev.interfaceCount)
                .map { dev.getInterface(it) }
                .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_HID }
            if (iface == null) {
                Log.w(TAG, "open: 未找到 HID 接口")
                return false
            }
            if (!conn.claimInterface(iface, true)) {
                Log.w(TAG, "open: claimInterface 失败")
                return false
            }
            val endpoints = (0 until iface.endpointCount).map { iface.getEndpoint(it) }
            val inEp = endpoints.firstOrNull {
                it.direction == UsbConstants.USB_DIR_IN &&
                    it.type == UsbConstants.USB_ENDPOINT_XFER_INT
            }
            val outEp = endpoints.firstOrNull {
                it.direction == UsbConstants.USB_DIR_OUT &&
                    it.type == UsbConstants.USB_ENDPOINT_XFER_INT
            }
            if (inEp == null || outEp == null) {
                Log.w(TAG, "open: 缺少中断 IN/OUT 端点")
                return false
            }
            inResults.clear()
            writeResults.clear()
            val request = UsbRequest()
            val buffer = ByteBuffer.allocateDirect(REPORT_SIZE)
            if (!request.initialize(conn, inEp) || !request.queue(buffer, REPORT_SIZE)) {
                Log.w(TAG, "open: 挂起中断 IN 请求失败")
                request.close()
                return false
            }
            connection = conn
            hidInterface = iface
            inEndpoint = inEp
            outEndpoint = outEp
            inRequest = request
            inBuffer = buffer
            canceled.set(false)
            startIoThread()
            opened = true
            Log.d(
                TAG,
                "open: ${dev.deviceName} iface=${iface.id} " +
                    "in=0x${"%02x".format(inEp.address)} out=0x${"%02x".format(outEp.address)}",
            )
            true
        } catch (error: Exception) {
            Log.w(TAG, "open: $error")
            false
        } finally {
            // 失败路径释放连接，避免重复重试时泄漏 fd。
            if (!opened) {
                runCatching { conn.close() }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun writeReport(bytes: ByteArray): Boolean {
        val conn = connection ?: return false
        val ep = outEndpoint ?: return false
        if (canceled.get()) return false
        // Windows/hidapi 缓冲区带前导 0x00 报告 ID（65 字节）；Android 中断
        // OUT 端点传输 64 字节报告本体，去掉该前缀。
        val data = if (bytes.size == REPORT_SIZE + 1 && bytes[0] == 0.toByte()) {
            bytes.copyOfRange(1, bytes.size)
        } else {
            bytes
        }
        if (data.isEmpty() || data.size > REPORT_SIZE) return false
        val request = UsbRequest()
        return try {
            writeResults.clear()
            if (!request.initialize(conn, ep)) {
                Log.w(TAG, "write: 初始化 OUT 请求失败")
                return false
            }
            // 完成后 position = 已发送字节数，此处只关心完成事件。
            if (!request.queue(ByteBuffer.wrap(data), data.size)) {
                Log.w(TAG, "write: 挂起 OUT 请求失败")
                return false
            }
            pendingWrite = request
            val completed = try {
                writeResults.poll(WRITE_TIMEOUT_MILLISECONDS, TimeUnit.MILLISECONDS) == true
            } catch (error: InterruptedException) {
                false
            }
            pendingWrite = null
            Log.d(TAG, "write: ${data.size} 字节完成=$completed")
            completed
        } finally {
            runCatching { request.cancel() }
            request.close()
        }
    }

    private fun readReport(timeoutMilliseconds: Int): ByteArray? {
        val deadline = System.nanoTime() + timeoutMilliseconds * 1_000_000L
        try {
            while (true) {
                val remaining = deadline - System.nanoTime()
                if (remaining <= 0) return null
                val data = inResults.poll(remaining, TimeUnit.NANOSECONDS) ?: return null
                // 空数组 = IO 线程已退出（连接被关闭/失效）。
                if (data.isEmpty()) return null
                Log.d(TAG, "read: 收到 ${data.size} 字节")
                return data
            }
        } catch (error: InterruptedException) {
            return null
        }
    }

    private fun startIoThread() {
        val generation = ioGeneration.incrementAndGet()
        running.set(true)
        val thread = Thread({ requestWaitLoop(generation) }, "pieblock-usb-hid-io")
        thread.isDaemon = true
        thread.start()
        ioThread = thread
    }

    @Suppress("DEPRECATION")
    private fun requestWaitLoop(generation: Long) {
        while (running.get() && ioGeneration.get() == generation) {
            val request = try {
                connection?.requestWait()
            } catch (error: Exception) {
                Log.w(TAG, "requestWait 异常：$error")
                null
            }
            if (request == null || !running.get() || ioGeneration.get() != generation) break
            if (request === inRequest) {
                // getBuffer() 在新 API 级别已移除，缓冲区使用打开时持有的引用。
                val buffer = inBuffer ?: break
                val received = buffer.position()
                val data = ByteArray(received)
                buffer.position(0)
                buffer.get(data)
                buffer.clear()
                inResults.offer(data)
                // 复用同一请求常驻挂起，等待设备下一个报告。
                if (!request.queue(buffer, REPORT_SIZE)) {
                    Log.w(TAG, "重新挂起中断 IN 请求失败")
                    break
                }
            } else {
                writeResults.offer(true)
            }
        }
        if (ioGeneration.get() == generation) {
            running.set(false)
            inResults.offer(ByteArray(0))
            writeResults.offer(false)
        }
    }

    private fun cancelNow() {
        canceled.set(true)
        closeNow()
    }

    private fun closeNow() {
        running.set(false)
        runCatching { inRequest?.cancel() }
        runCatching { connection?.releaseInterface(hidInterface) }
        runCatching { connection?.close() }
        runCatching { inRequest?.close() }
        connection = null
        hidInterface = null
        inEndpoint = null
        outEndpoint = null
        inRequest = null
        inBuffer = null
        pendingWrite = null
        ioThread?.let { thread ->
            runCatching { thread.join(500) }
            if (thread.isAlive) thread.interrupt()
        }
        ioThread = null
    }
}
