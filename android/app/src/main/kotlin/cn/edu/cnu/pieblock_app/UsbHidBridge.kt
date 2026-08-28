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
 * 上收发，同步 bulkTransfer 仅保证用于 bulk 端点，因此读写全部走异步请求。
 *
 * 时序完全对齐 Windows hidapi（真机对照实验确认的关键约束）：
 *  - 打开只做 claim，不发任何 EP0 类请求、不预先轮询中断 IN——STC 最小
 *    固件在 EP4-IN 未武装时收到 IN 轮询会出错（整对端点 STALL 并退回
 *    用户程序）；Windows 上 hidapi 同样是「写之后才读」；
 *  - write 每次单独挂一个中断 OUT 请求并等待完成（requestWait 线程派发）；
 *  - read 按需挂起中断 IN 请求并带超时等待完成；超时后请求保持挂起
 *    （等价 Windows 的 pending ReadFile），下一个 read 直接复用。
 *
 * 与 Windows pieblock_hid.dll 的语义对齐：
 *  - write：发送一个 HID 报告。Windows hidapi 的缓冲区含前导 0x00 报告
 *    ID（65 字节），Android 中断端点传输的是 64 字节报告本体，因此这里
 *    去掉前导 0x00 后原样发送。
 *  - read：等待一个输入报告，超时返回空（null）。
 *  - cancel/close：置取消标志并关闭连接，使挂起的传输立即结束。
 *
 * 另外：STC ISP 固件有入场窗口——进入 ISP 后若长时间无人认领会跳回用户
 * 程序（产品字符串仍为 USB-ISP，无法从枚举区分）。因此 list 检测到唯一
 * 板子时会立即自动授权+打开（仅 claim，不产生额外总线活动），烧录时直接
 * 复用；打开时校验产品字符串，板子在跑用户程序时向用户报明确错误。
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

        private fun ByteString(data: ByteArray, limit: Int): String =
            data.take(limit).joinToString("") { "%02x".format(it) }
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

    /** 中断 IN 请求及缓冲区：仅在 read 时挂起，不在打开时预挂。 */
    @Volatile
    private var inRequest: UsbRequest? = null

    @Volatile
    private var inBuffer: ByteBuffer? = null

    @Volatile
    private var inQueued = false

    @Volatile
    private var pendingWrite: UsbRequest? = null

    @Volatile
    private var pendingWriteBuffer: ByteBuffer? = null

    /** 已完成的中断 IN 报告；空数组为线程退出标记（连接已失效）。 */
    private val inResults = LinkedBlockingQueue<ByteArray>()

    /** 已完成的中断 OUT 写请求实际发送字节数；-1 为线程退出标记。 */
    private val writeResults = LinkedBlockingQueue<Int>()

    /** requestWait 专用线程；generation 用于区分会话，避免旧线程污染新会话队列。 */
    @Volatile
    private var ioThread: Thread? = null
    private val ioGeneration = AtomicLong(0)
    private val running = AtomicBoolean(false)

    private var pendingOpenResult: MethodChannel.Result? = null
    private var permissionRequestInFlight = false

    /** STC ISP 固件要求枚举后立即建立连续 IN 轮询会话（内核 HID 驱动的
     * probe 行为），否则端点 STALL 并跳回用户程序。因此 attach 广播一到
     * 就立刻 claim + 常驻轮询，赶在入场窗口内。 */
    private val attachReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != UsbManager.ACTION_USB_DEVICE_ATTACHED) return
            val dev = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                ?: return
            if (!matches(dev)) return
            Log.d(TAG, "attach: 检测到板子 ${dev.deviceName}，立即建立会话")
            device = dev
            executor.execute {
                if (connection != null) return@execute
                if (usbManager.hasPermission(dev)) {
                    runCatching { openDeviceLocked() }
                } else if (!permissionRequestInFlight) {
                    requestPermissionNow(dev)
                }
            }
        }
    }

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_PERMISSION) return
            val granted = intent.getBooleanExtra(
                UsbManager.EXTRA_PERMISSION_GRANTED,
                false,
            )
            val result = pendingOpenResult
            pendingOpenResult = null
            permissionRequestInFlight = false
            executor.execute {
                if (!granted) {
                    if (result != null) replySuccess(result, "permission_denied")
                    return@execute
                }
                val status = openDeviceLocked()
                if (result != null) replySuccess(result, status)
            }
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
        val attachFilter = IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(attachReceiver, attachFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(attachReceiver, attachFilter)
        }
    }

    fun dispose() {
        runCatching { activity.unregisterReceiver(permissionReceiver) }
        runCatching { activity.unregisterReceiver(attachReceiver) }
        closeNow()
        executor.shutdown()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> {
                val devices = listDevices()
                if (devices.size == 1 && connection == null && !canceled.get()) {
                    val dev = usbManager.deviceList.values.firstOrNull { matches(it) }
                    if (dev != null) {
                        if (usbManager.hasPermission(dev)) {
                            // 预打开：只 claim + 识别人格，无额外总线活动，
                            // 让烧录时能立即复用会话。
                            executor.execute { runCatching { openDeviceLocked() } }
                        } else if (!permissionRequestInFlight) {
                            requestPermissionNow(dev)
                        }
                    }
                }
                replySuccess(result, devices)
            }
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

    /** 返回状态：ok / app_mode / no_device / permission_denied / busy / failed。 */
    private fun open(result: MethodChannel.Result) {
        val found = usbManager.deviceList.values.firstOrNull { matches(it) }
        if (found == null) {
            replySuccess(result, "no_device")
            return
        }
        device = found
        if (connection != null && usbManager.hasPermission(found)) {
            // 已有预打开会话，直接复用，不打断总线活动。
            replySuccess(result, "ok")
            return
        }
        if (usbManager.hasPermission(found)) {
            executor.execute { replySuccess(result, openDeviceLocked()) }
            return
        }
        if (pendingOpenResult != null || permissionRequestInFlight) {
            replySuccess(result, "busy")
            return
        }
        pendingOpenResult = result
        requestPermissionNow(found)
    }

    private fun requestPermissionNow(dev: UsbDevice) {
        permissionRequestInFlight = true
        val intent = Intent(ACTION_PERMISSION).setPackage(activity.packageName)
        val flags = PendingIntent.FLAG_ONE_SHOT or
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pendingIntent = PendingIntent.getBroadcast(activity, 0, intent, flags)
        Log.d(TAG, "open: 请求 USB 权限 ${dev.deviceName}")
        usbManager.requestPermission(dev, pendingIntent)
    }

    private fun openDeviceLocked(): String {
        closeNow()
        val dev = device ?: return "failed"
        val conn = try {
            usbManager.openDevice(dev)
        } catch (error: Exception) {
            Log.w(TAG, "open: openDevice 异常：$error")
            return "failed"
        }
        if (conn == null) {
            Log.w(TAG, "open: openDevice 返回空")
            return "failed"
        }
        var opened = false
        return try {
            dumpRawDescriptors(conn)
            val iface = (0 until dev.interfaceCount)
                .map { dev.getInterface(it) }
                .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_HID }
            if (iface == null) {
                Log.w(TAG, "open: 未找到 HID 接口")
                return "failed"
            }
            if (!conn.claimInterface(iface, true)) {
                Log.w(TAG, "open: claimInterface 失败")
                return "failed"
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
                return "failed"
            }
            Log.d(
                TAG,
                "open: 字符串 product=${dev.productName} " +
                    "manufacturer=${dev.manufacturerName} serial=${dev.serialNumber}",
            )
            if (dev.productName != "USB-ISP") {
                Log.w(
                    TAG,
                    "open: 产品字符串 '${dev.productName}' 非 ISP 固件，板子正在运行用户程序",
                )
                return "app_mode"
            }
            connection = conn
            hidInterface = iface
            inEndpoint = inEp
            outEndpoint = outEp
            inRequest = null
            inBuffer = null
            inQueued = false
            canceled.set(false)
            inResults.clear()
            writeResults.clear()
            startIoThread()
            // 立即建立常驻 IN 轮询会话（复刻内核 HID 驱动 probe 行为），
            // 这是 STC ISP 固件保持端点武装的必要条件。
            if (!queueInRequest(conn, inEp)) {
                Log.w(TAG, "open: 建立常驻 IN 轮询失败")
            }
            opened = true
            Log.d(
                TAG,
                "open: ${dev.deviceName} iface=${iface.id} " +
                    "in=0x${"%02x".format(inEp.address)} out=0x${"%02x".format(outEp.address)}",
            )
            "ok"
        } catch (error: Exception) {
            Log.w(TAG, "open: $error")
            "failed"
        } finally {
            // 失败路径释放连接，避免重复重试时泄漏 fd。
            if (!opened) {
                runCatching { conn.close() }
            }
        }
    }

    /** 从原始配置描述符解析接口与端点参数（bInterval 等），仅用于日志。 */
    private fun dumpRawDescriptors(conn: UsbDeviceConnection) {
        val desc = runCatching { conn.rawDescriptors }.getOrNull()
        if (desc == null) {
            Log.w(TAG, "描述符: getRawDescriptors 失败")
            return
        }
        var offset = 0
        while (offset + 2 <= desc.size) {
            val length = desc[offset].toInt() and 0xff
            if (length < 2 || offset + length > desc.size) break
            val type = desc[offset + 1].toInt() and 0xff
            when (type) {
                0x04 -> { // INTERFACE
                    Log.d(
                        TAG,
                        "描述符: IFACE num=${desc[offset + 2]} alt=${desc[offset + 3]} " +
                            "endpoints=${desc[offset + 4]} class=0x${"%02x".format(desc[offset + 5])} " +
                            "subclass=0x${"%02x".format(desc[offset + 6])} protocol=${desc[offset + 8]}",
                    )
                }
                0x05 -> { // ENDPOINT
                    val address = desc[offset + 2].toInt() and 0xff
                    val attributes = desc[offset + 3].toInt() and 0xff
                    val maxPacket = ((desc[offset + 5].toInt() and 0xff) shl 8) or
                        (desc[offset + 4].toInt() and 0xff)
                    val interval = desc[offset + 6].toInt() and 0xff
                    Log.d(
                        TAG,
                        "描述符: EP addr=0x${"%02x".format(address)} attr=0x${"%02x".format(attributes)} " +
                            "maxPacket=$maxPacket interval=$interval",
                    )
                }
            }
            offset += length
        }
    }

    private fun buildOutData(bytes: ByteArray): ByteArray? {
        // Windows/hidapi 缓冲区带前导 0x00 报告 ID（65 字节）；Android 中断
        // OUT 端点传输 64 字节报告本体，去掉该前缀。
        val data = if (bytes.size == REPORT_SIZE + 1 && bytes[0] == 0.toByte()) {
            bytes.copyOfRange(1, bytes.size)
        } else {
            bytes
        }
        if (data.isEmpty() || data.size > REPORT_SIZE) return null
        return data
    }

    @Suppress("DEPRECATION")
    private fun writeReport(bytes: ByteArray): Boolean {
        val conn = connection ?: return false
        val ep = outEndpoint ?: return false
        if (canceled.get()) return false
        val data = buildOutData(bytes) ?: return false
        val request = UsbRequest()
        return try {
            writeResults.clear()
            if (!request.initialize(conn, ep)) {
                Log.w(TAG, "write: 初始化 OUT 请求失败")
                return false
            }
            // 完成后 position = 已发送字节数，以此校验发送是否真的成功。
            if (!request.queue(ByteBuffer.wrap(data), data.size)) {
                Log.w(TAG, "write: 挂起 OUT 请求失败")
                return false
            }
            pendingWrite = request
            pendingWriteBuffer = ByteBuffer.wrap(data)
            val sentBytes = try {
                writeResults.poll(WRITE_TIMEOUT_MILLISECONDS, TimeUnit.MILLISECONDS) ?: -1
            } catch (error: InterruptedException) {
                -1
            }
            pendingWrite = null
            pendingWriteBuffer = null
            Log.d(TAG, "write: 期望 ${data.size} 字节实际发送=$sentBytes")
            sentBytes == data.size
        } finally {
            runCatching { request.cancel() }
            request.close()
        }
    }

    private fun readReport(timeoutMilliseconds: Int): ByteArray? {
        val deadline = System.nanoTime() + timeoutMilliseconds * 1_000_000L
        var ioDead = false
        while (true) {
            val conn = connection ?: return null
            val inEp = inEndpoint ?: return null
            if (!inQueued && !queueInRequest(conn, inEp)) return null
            val remaining = deadline - System.nanoTime()
            if (remaining <= 0) {
                // 请求保持挂起（等价 Windows 的 pending ReadFile），下个 read 复用。
                Log.d(TAG, "read: 等待 ${timeoutMilliseconds}ms 超时")
                return null
            }
            val data = try {
                inResults.poll(remaining, TimeUnit.NANOSECONDS)
            } catch (error: InterruptedException) {
                return null
            }
            if (data == null) continue
            // 空数组 = IO 线程已退出（连接被关闭/失效）。
            if (data.isEmpty()) {
                Log.d(TAG, "read: IO 线程已退出，连接失效")
                ioDead = true
                return null
            }
            Log.d(TAG, "read: 收到 ${data.size} 字节 data=${ByteString(data, 8)}")
            return data
        }
    }

    /** 按需挂起中断 IN 请求；完成后由 IO 线程置 inQueued=false，读侧再复用。 */
    @Suppress("DEPRECATION")
    private fun queueInRequest(conn: UsbDeviceConnection, inEp: UsbEndpoint): Boolean {
        var request = inRequest
        var buffer = inBuffer
        if (request == null || buffer == null) {
            request = UsbRequest().also { inRequest = it }
            buffer = ByteBuffer.allocateDirect(REPORT_SIZE).also { inBuffer = it }
            if (!request.initialize(conn, inEp)) {
                Log.w(TAG, "read: 初始化 IN 请求失败")
                request.close()
                inRequest = null
                inBuffer = null
                return false
            }
        }
        buffer.clear()
        val queued = request.queue(buffer, REPORT_SIZE)
        inQueued = queued
        if (!queued) {
            Log.w(TAG, "read: 挂起 IN 请求失败")
        }
        return queued
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
                // getBuffer() 在新 API 级别已移除，缓冲区使用读侧持有的引用。
                val buffer = inBuffer
                val received = buffer?.position() ?: 0
                inQueued = false
                if (received > 0) {
                    val data = ByteArray(received)
                    buffer!!.position(0)
                    buffer.get(data)
                    buffer.clear()
                    Log.d(TAG, "IN 完成 received=$received data=${ByteString(data, 8)}")
                    inResults.offer(data)
                } else {
                    Log.d(TAG, "IN 完成 0 字节，稍候重新挂起保持轮询")
                    // 端点异常时完成会瞬间返回，避免热轮询空转。
                    try {
                        Thread.sleep(50)
                    } catch (error: InterruptedException) {
                    }
                }
                // 常驻轮询：完成即重新挂起，保持会话活跃。
                val conn = connection
                val inEp = inEndpoint
                if (running.get() && conn != null && inEp != null) {
                    if (!queueInRequest(conn, inEp)) {
                        Log.w(TAG, "重新挂起中断 IN 请求失败")
                    }
                }
            } else if (request === pendingWrite) {
                val sent = pendingWriteBuffer?.position() ?: 0
                Log.d(TAG, "OUT 完成 sent=$sent")
                writeResults.offer(sent)
            } else {
                Log.d(TAG, "requestWait: 忽略未知请求完成（可能是超时后取消的写）")
            }
        }
        if (ioGeneration.get() == generation) {
            running.set(false)
            inResults.offer(ByteArray(0))
            writeResults.offer(-1)
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
        inQueued = false
        pendingWrite = null
        pendingWriteBuffer = null
        ioThread?.let { thread ->
            runCatching { thread.join(500) }
            if (thread.isAlive) thread.interrupt()
        }
        ioThread = null
    }
}
