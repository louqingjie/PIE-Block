package cn.edu.cnu.pieblock_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.os.Process
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

class SdccCompilerService : Service() {
    private data class ActiveOperation(
        val id: String,
        val callback: ISdccCompilerCallback,
        @Volatile var nativeHandle: Long = 0,
        @Volatile var completed: Boolean = false,
    )

    private val executor = Executors.newSingleThreadExecutor()
    private val active = AtomicReference<ActiveOperation?>(null)

    private val binder = object : ISdccCompilerService.Stub() {
        override fun protocolVersion(): Int = PROTOCOL_VERSION

        override fun capabilities(): Bundle = Bundle().apply {
            putInt("protocolVersion", PROTOCOL_VERSION)
            putInt("apiVersion", SdccNativeBridge.apiVersion())
            putBoolean("available", SdccNativeBridge.isAvailable())
            putString("fingerprint", SdccNativeBridge.fingerprint())
            putInt("compilerPid", Process.myPid())
        }

        override fun start(
            request: Bundle,
            callback: ISdccCompilerCallback,
        ): String {
            val operation = ActiveOperation(UUID.randomUUID().toString(), callback)
            check(active.compareAndSet(null, operation)) { "已有编译任务正在运行" }
            callback.asBinder().linkToDeath(
                {
                    if (operation.nativeHandle != 0L) {
                        SdccNativeBridge.cancel(operation.nativeHandle)
                    }
                    terminateCompilerProcess(0)
                },
                0,
            )
            startForeground(NOTIFICATION_ID, createNotification("正在准备固件编译…"))
            executor.execute { execute(operation, request) }
            return operation.id
        }

        override fun cancel(operationId: String) {
            active.get()?.takeIf { it.id == operationId }?.let { operation ->
                if (operation.nativeHandle != 0L) {
                    SdccNativeBridge.cancel(operation.nativeHandle)
                }
            }
        }

        override fun acknowledge(operationId: String) {
            val operation = active.get() ?: return
            if (operation.id != operationId || !operation.completed) return
            active.compareAndSet(operation, null)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            terminateCompilerProcess(100)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "固件编译",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        cleanupInterruptedBuilds()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        active.get()?.nativeHandle?.takeIf { it != 0L }?.let {
            SdccNativeBridge.cancel(it)
        }
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun execute(operation: ActiveOperation, request: Bundle) {
        var inProgressMarker: File? = null
        try {
            require(SdccNativeBridge.apiVersion() == 4) { "SDCC C ABI 版本不匹配" }
            require(SdccNativeBridge.isAvailable()) {
                "Android SDCC 流水线尚未通过安全门自检"
            }
            val values = validateRequest(request)
            inProgressMarker = File(values.getValue("working"), ".in_progress")
                .apply { writeText("${operation.id}:${Process.myPid()}") }
            File(values.getValue("hex")).delete()
            File(values.getValue("map")).delete()
            val handle = SdccNativeBridge.start(
                values.getValue("working"),
                values.getValue("resource"),
                values.getValue("project"),
                values.getValue("main"),
                values.getValue("interrupt"),
                request.getStringArray("sources") ?: emptyArray(),
                request.getStringArray("librarySources") ?: emptyArray(),
                request.getStringArray("compileArguments") ?: emptyArray(),
                request.getStringArray("linkArguments") ?: emptyArray(),
                values.getValue("hex"),
                values.getValue("map"),
                values.getValue("log"),
            )
            require(handle > 0) { "无法启动原生编译任务（状态 ${-handle}）" }
            operation.nativeHandle = handle
            val logFile = File(values.getValue("log"))
            var deliveredLogLines = 0
            while (!operation.completed) {
                SdccNativeBridge.poll(handle)?.let { event ->
                    operation.callback.onEvent(eventBundle(event))
                    updateNotification(event.getOrNull(5) ?: "正在编译固件…")
                }
                if (logFile.isFile) {
                    val lines = runCatching { logFile.readLines(Charsets.UTF_8) }
                        .getOrDefault(emptyList())
                    for (index in deliveredLogLines until lines.size) {
                        operation.callback.onEvent(
                            Bundle().apply {
                                putInt("stage", 2)
                                putInt("level", if (
                                    lines[index].contains("error", ignoreCase = true)
                                ) 2 else 0)
                                putString("message", lines[index])
                                putInt("compilerPid", Process.myPid())
                            },
                        )
                    }
                    deliveredLogLines = lines.size
                }
                val result = SdccNativeBridge.result(handle)
                if (result != null) {
                    operation.completed = true
                    operation.callback.onFinished(resultBundle(result))
                    break
                }
                Thread.sleep(20)
            }
        } catch (error: Throwable) {
            operation.completed = true
            operation.callback.onFinished(
                Bundle().apply {
                    putBoolean("success", false)
                    putString("errorCode", "compiler_process_failed")
                    putString("message", error.message ?: "编译器进程异常退出")
                    putInt("compilerPid", Process.myPid())
                    putString("fingerprint", runCatching {
                        SdccNativeBridge.fingerprint()
                    }.getOrDefault("unavailable"))
                },
            )
        } finally {
            if (operation.nativeHandle != 0L) {
                SdccNativeBridge.destroy(operation.nativeHandle)
                operation.nativeHandle = 0
            }
            inProgressMarker?.delete()
            if (operation.completed) terminateCompilerProcess(30_000)
        }
    }

    private fun validateRequest(request: Bundle): Map<String, String> {
        val working = canonical(request.getString("workingDirectory"))
        val resource = canonical(request.getString("resourceDirectory"))
        val allowedWorkRoots = listOf(cacheDir.canonicalFile, filesDir.canonicalFile)
        require(allowedWorkRoots.any { working.isInside(it) }) { "构建目录不在应用私有目录" }
        require(resource.isInside(File(filesDir, "pieblock_sdcc").canonicalFile)) {
            "资源目录不在受控资源根目录"
        }
        val marker = File(resource, ".ready")
        require(
            marker.isFile &&
                marker.readText().trim() == resource.name &&
                resource.name.matches(Regex("[0-9a-f]{64}")),
        ) { "SDCC 资源包指纹无效" }
        fun controlledPath(key: String, root: File = working): String {
            val file = canonical(request.getString(key))
            require(file.isInside(root)) { "$key 路径越界" }
            return file.path
        }
        val sources = request.getStringArray("sources") ?: emptyArray()
        require(sources.isNotEmpty()) { "源码列表为空" }
        sources.forEach { source ->
            val file = canonical(source)
            require(file.isInside(working) || file.isInside(resource)) { "源码路径越界" }
            require(file.isFile) { "源码文件不存在：${file.name}" }
        }
        val sourceSet = sources.map { canonical(it).path }.toSet()
        (request.getStringArray("librarySources") ?: emptyArray()).forEach {
            require(canonical(it).path in sourceSet) { "库源码不在受控源码列表" }
        }
        val allowedFlags = Regex("^[A-Za-z0-9_./:+,=\\\\-]+$")
        listOf("compileArguments", "linkArguments").forEach { key ->
            (request.getStringArray(key) ?: emptyArray()).forEach { value ->
                require(
                    allowedFlags.matches(value) || value == "-Wl-b GSINIT0=0xfe0000",
                ) { "编译参数包含非法字符" }
                require(!value.contains("..")) { "编译参数包含越界路径" }
            }
        }
        return mapOf(
            "working" to working.path,
            "resource" to resource.path,
            "project" to requireNotNull(request.getString("projectKind")),
            "main" to controlledPath("mainSourcePath"),
            "interrupt" to controlledPath("interruptHeaderPath"),
            "hex" to controlledPath("hexOutputPath"),
            "map" to controlledPath("mapOutputPath"),
            "log" to controlledPath("logOutputPath"),
        )
    }

    private fun canonical(path: String?): File {
        require(!path.isNullOrBlank()) { "请求路径为空" }
        return File(path).canonicalFile
    }

    private fun File.isInside(root: File): Boolean =
        path == root.path || path.startsWith(root.path + File.separator)

    private fun eventBundle(values: Array<String>) = Bundle().apply {
        putInt("stage", values.getOrNull(0)?.toIntOrNull() ?: 0)
        putInt("level", values.getOrNull(1)?.toIntOrNull() ?: 0)
        putInt("current", values.getOrNull(2)?.toIntOrNull() ?: 0)
        putInt("total", values.getOrNull(3)?.toIntOrNull() ?: 0)
        putString("fileName", values.getOrNull(4).orEmpty())
        putString("message", values.getOrNull(5).orEmpty())
        putInt("compilerPid", Process.myPid())
    }

    private fun resultBundle(values: Array<String>) = Bundle().apply {
        putBoolean("success", values.getOrNull(0) == "0")
        putBoolean("canceled", values.getOrNull(0) == "5")
        putInt("exitCode", values.getOrNull(1)?.toIntOrNull() ?: -1)
        putInt("errorCount", values.getOrNull(2)?.toIntOrNull() ?: 1)
        putInt("warningCount", values.getOrNull(3)?.toIntOrNull() ?: 0)
        putString("hexPath", values.getOrNull(4).orEmpty())
        putString("mapPath", values.getOrNull(5).orEmpty())
        putString("logPath", values.getOrNull(6).orEmpty())
        putString("errorCode", values.getOrNull(7).orEmpty())
        putString("message", values.getOrNull(8).orEmpty())
        putInt("compilerPid", Process.myPid())
        putString("fingerprint", SdccNativeBridge.fingerprint())
    }

    private fun createNotification(text: String) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("PIE-Block")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, createNotification(text))
    }

    private fun cleanupInterruptedBuilds() {
        listOf(cacheDir, filesDir).forEach { root ->
            root.walkTopDown()
                .filter { it.isFile && it.name == ".in_progress" }
                .mapNotNull { it.parentFile }
                .toList()
                .forEach { directory ->
                    directory.listFiles()?.forEach { file ->
                        if (!file.name.endsWith(".log")) file.deleteRecursively()
                    }
                }
        }
    }

    private fun terminateCompilerProcess(delayMillis: Long) {
        Thread {
            if (delayMillis > 0) Thread.sleep(delayMillis)
            stopSelf()
            Process.killProcess(Process.myPid())
        }.start()
    }

    companion object {
        const val PROTOCOL_VERSION = 1
        private const val CHANNEL_ID = "pieblock_firmware_build"
        private const val NOTIFICATION_ID = 0x5042
    }
}
