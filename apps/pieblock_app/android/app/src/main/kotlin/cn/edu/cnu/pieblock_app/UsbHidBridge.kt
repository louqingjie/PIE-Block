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
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android USB-HID 传输桥：只负责枚举/打开/读写 STC32G「USB-ISP」HID 设备
 * （VID 0x34BF / PID 0x1001），不实现任何烧录协议——协议层在 Dart
 * pieblock_hid（与 Windows 侧一致）。
 *
 * 平台没有公开的 HidDevice 类，这里直接通过 UsbDeviceConnection 访问 HID
 * 接口的中断端点（bulkTransfer 对中断端点同样有效并支持超时）。
 *
 * 与 Windows pieblock_hid.dll 的语义对齐：
 *  - write：发送一个 HID 报告。Windows hidapi 的缓冲区含前导 0x00 报告
 *    ID（65 字节），Android 中断端点传输的是 64 字节报告本体，因此这里
 *    去掉前导 0x00 后原样发送。
 *  - read：阻塞读取一个输入报告，超时返回空（null）。
 *  - cancel：置取消标志并关闭连接，使阻塞读立即返回。
 *
 * 平台通道方法：list / open / write / read / cancel / close
 */
class UsbHidBridge(private val activity: MainActivity) {
    companion object {
        const val VID = 0x34BF
        const val PID = 0x1001
        private const val ACTION_PERMISSION = "cn.edu.cnu.pieblock_app.USB_HID_PERMISSION"
        private const val REPORT_SIZE = 64
    }

    private val usbManager = activity.getSystemService(Context.USB_SERVICE) as UsbManager
    private val executor = Executors.newSingleThreadExecutor()
    private val canceled = AtomicBoolean(false)

    private var device: UsbDevice? = null
    private var connection: UsbDeviceConnection? = null
    private var hidInterface: UsbInterface? = null
    private var inEndpoint: UsbEndpoint? = null
    private var outEndpoint: UsbEndpoint? = null
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
                result.success(false)
                return
            }
            executor.execute { result.success(openDeviceLocked()) }
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
            "list" -> result.success(listDevices())
            "open" -> open(result)
            "write" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    result.success(false)
                    return
                }
                executor.execute { result.success(writeReport(bytes)) }
            }
            "read" -> {
                val timeout = (call.arguments as? Number)?.toInt() ?: 3000
                executor.execute {
                    val data = readReport(timeout)
                    result.success(data)
                }
            }
            "cancel" -> {
                executor.execute { cancelNow() }
                result.success(null)
            }
            "close" -> {
                executor.execute { closeNow() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
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
            result.success(false)
            return
        }
        device = found
        if (usbManager.hasPermission(found)) {
            executor.execute { result.success(openDeviceLocked()) }
            return
        }
        if (pendingOpenResult != null) {
            result.success(false)
            return
        }
        pendingOpenResult = result
        val intent = Intent(ACTION_PERMISSION).setPackage(activity.packageName)
        val flags = PendingIntent.FLAG_ONE_SHOT or
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pendingIntent = PendingIntent.getBroadcast(activity, 0, intent, flags)
        usbManager.requestPermission(found, pendingIntent)
    }

    private fun openDeviceLocked(): Boolean {
        closeNow()
        val dev = device ?: return false
        return runCatching {
            val conn = usbManager.openDevice(dev)
            if (conn == null) return false
            val iface = (0 until dev.interfaceCount)
                .map { dev.getInterface(it) }
                .firstOrNull { it.interfaceClass == UsbConstants.USB_CLASS_HID }
            if (iface == null) return false
            if (!conn.claimInterface(iface, true)) return false
            val endpoints = (0 until iface.endpointCount).map { iface.getEndpoint(it) }
            val inEp = endpoints.firstOrNull {
                it.direction == UsbConstants.USB_DIR_IN &&
                    it.type == UsbConstants.USB_ENDPOINT_XFER_INT
            }
            val outEp = endpoints.firstOrNull {
                it.direction == UsbConstants.USB_DIR_OUT &&
                    it.type == UsbConstants.USB_ENDPOINT_XFER_INT
            }
            if (inEp == null || outEp == null) return false
            connection = conn
            hidInterface = iface
            inEndpoint = inEp
            outEndpoint = outEp
            canceled.set(false)
            true
        }.getOrDefault(false)
    }

    private fun writeReport(bytes: ByteArray): Boolean {
        if (canceled.get()) return false
        val conn = connection ?: return false
        val ep = outEndpoint ?: return false
        // Windows/hidapi 缓冲区带前导 0x00 报告 ID（65 字节）；Android 中断
        // OUT 端点传输 64 字节报告本体，去掉该前缀。
        val data = if (bytes.size == REPORT_SIZE + 1 && bytes[0] == 0.toByte()) {
            bytes.copyOfRange(1, bytes.size)
        } else {
            bytes
        }
        if (data.size == 0 || data.size > REPORT_SIZE) return false
        return runCatching {
            conn.bulkTransfer(ep, data, data.size, 3000) == data.size
        }.getOrDefault(false)
    }

    private fun readReport(timeoutMilliseconds: Int): ByteArray? {
        val conn = connection ?: return null
        val ep = inEndpoint ?: return null
        if (canceled.get()) return null
        return runCatching {
            val buffer = ByteArray(REPORT_SIZE)
            val count = conn.bulkTransfer(ep, buffer, buffer.size, timeoutMilliseconds)
            if (count <= 0) null else buffer.copyOf(count)
        }.getOrNull()
    }

    private fun cancelNow() {
        canceled.set(true)
        closeNow()
    }

    private fun closeNow() {
        runCatching { connection?.releaseInterface(hidInterface) }
        runCatching { connection?.close() }
        connection = null
        hidInterface = null
        inEndpoint = null
        outEndpoint = null
    }
}
