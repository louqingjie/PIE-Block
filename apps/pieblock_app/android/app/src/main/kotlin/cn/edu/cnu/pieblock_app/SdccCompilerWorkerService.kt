package cn.edu.cnu.pieblock_app

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.os.Process
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

class SdccCompilerWorkerService : Service() {
    private data class ActiveOperation(
        val id: String,
        val callback: ISdccCompilerCallback,
        @Volatile var nativeHandle: Long = 0,
        @Volatile var completed: Boolean = false,
    )

    private val processNonce = UUID.randomUUID().toString()
    private val executor = Executors.newSingleThreadExecutor()
    private val active = AtomicReference<ActiveOperation?>(null)

    private val binder = object : ISdccWorkerService.Stub() {
        override fun protocolVersion(): Int = PROTOCOL_VERSION

        override fun capabilities(): Bundle = Bundle().apply {
            putInt("protocolVersion", PROTOCOL_VERSION)
            putInt("apiVersion", SdccNativeBridge.apiVersion())
            putBoolean("available", SdccNativeBridge.isAvailable())
            putString("fingerprint", SdccNativeBridge.fingerprint())
            putInt("workerPid", Process.myPid())
            putString("workerNonce", processNonce)
        }

        override fun start(request: Bundle, callback: ISdccCompilerCallback): String {
            val operation = ActiveOperation(UUID.randomUUID().toString(), callback)
            check(active.compareAndSet(null, operation)) { "Worker 已有运行中的阶段" }
            callback.asBinder().linkToDeath({ terminate(0) }, 0)
            executor.execute { execute(operation, request) }
            return operation.id
        }

        override fun cancel(operationId: String) {
            active.get()?.takeIf { it.id == operationId }?.nativeHandle
                ?.takeIf { it != 0L }?.let(SdccNativeBridge::cancel)
        }

        override fun acknowledge(operationId: String) {
            val operation = active.get() ?: return
            if (operation.id == operationId && operation.completed) terminate(0)
        }

        override fun shutdown() = terminate(0)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        active.get()?.nativeHandle?.takeIf { it != 0L }?.let(SdccNativeBridge::cancel)
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun execute(operation: ActiveOperation, request: Bundle) {
        try {
            require(SdccNativeBridge.apiVersion() == 5) { "SDCC C ABI 版本不匹配" }
            require(SdccNativeBridge.isAvailable()) { "单阶段 SDCC Worker 未通过自检" }
            val values = validateRequest(request)
            listOfNotNull(values["object"], values["hex"], values["map"]).forEach {
                File(it).delete()
            }
            val handle = SdccNativeBridge.start(
                request.getInt("operationKind"),
                values.getValue("working"),
                values.getValue("resource"),
                values.getValue("project"),
                values["source"],
                values["object"],
                request.getStringArray("objects") ?: emptyArray(),
                request.getStringArray("libraryObjects") ?: emptyArray(),
                request.getStringArray("arguments") ?: emptyArray(),
                values["hex"],
                values["map"],
                values.getValue("log"),
            )
            require(handle != 0L) { "无法启动原生阶段" }
            operation.nativeHandle = handle
            val logFile = File(values.getValue("log"))
            var deliveredLines = 0
            var observedWarnings = 0
            val warningPattern = Regex("\\bwarning(?:\\s+\\d+)?:", RegexOption.IGNORE_CASE)
            while (!operation.completed) {
                SdccNativeBridge.poll(handle)?.let { event ->
                    operation.callback.onEvent(eventBundle(event))
                }
                if (logFile.isFile) {
                    val lines = runCatching { logFile.readLines(Charsets.UTF_8) }
                        .getOrDefault(emptyList())
                    for (index in deliveredLines until lines.size) {
                        val line = lines[index]
                        val internalNoise = isInternalCompilerNoise(line)
                        if (warningPattern.containsMatchIn(line) && !internalNoise) {
                            observedWarnings++
                        }
                        if (internalNoise) continue
                        operation.callback.onEvent(Bundle().apply {
                            putInt("stage", if (request.getInt("operationKind") == 2) 4 else 2)
                            putInt(
                                "level",
                                when {
                                    line.contains("error", true) -> 2
                                    warningPattern.containsMatchIn(line) -> 1
                                    else -> 0
                                },
                            )
                            putString("message", line)
                            putInt("workerPid", Process.myPid())
                            putString("workerNonce", processNonce)
                        })
                    }
                    deliveredLines = lines.size
                }
                SdccNativeBridge.result(handle)?.let { result ->
                    operation.completed = true
                    operation.callback.onFinished(resultBundle(result, observedWarnings))
                }
                if (!operation.completed) Thread.sleep(20)
            }
        } catch (error: Throwable) {
            operation.completed = true
            operation.callback.onFinished(Bundle().apply {
                putBoolean("success", false)
                putString("errorCode", "worker_failed")
                putString("message", error.message ?: "编译 Worker 异常退出")
                putInt("workerPid", Process.myPid())
                putString("workerNonce", processNonce)
                putString("fingerprint", runCatching {
                    SdccNativeBridge.fingerprint()
                }.getOrDefault("unavailable"))
            })
        } finally {
            if (operation.nativeHandle != 0L) {
                SdccNativeBridge.destroy(operation.nativeHandle)
                operation.nativeHandle = 0
            }
            if (operation.completed) terminate(30_000)
        }
    }

    private fun validateRequest(request: Bundle): Map<String, String> {
        val kind = request.getInt("operationKind")
        require(kind == 1 || kind == 2) { "未知 Worker 操作" }
        val working = canonical(request.getString("workingDirectory"))
        val resource = canonical(request.getString("resourceDirectory"))
        require(listOf(cacheDir.canonicalFile, filesDir.canonicalFile).any { working.isInside(it) }) {
            "构建目录不在应用私有目录"
        }
        require(resource.isInside(File(filesDir, "pieblock_sdcc").canonicalFile)) {
            "资源目录不在受控根目录"
        }
        val marker = File(resource, ".ready")
        require(marker.isFile && marker.readText().trim() == resource.name) { "资源指纹无效" }
        fun controlled(key: String, required: Boolean): String? {
            val raw = request.getString(key)
            if (raw.isNullOrBlank()) {
                require(!required) { "$key 为空" }
                return null
            }
            val file = canonical(raw)
            require(file.isInside(working) || file.isInside(resource)) { "$key 路径越界" }
            return file.path
        }
        val source = controlled("sourcePath", kind == 1)
        val objectOutput = controlled("objectOutputPath", kind == 1)
        val objects = request.getStringArray("objects") ?: emptyArray()
        val libraryObjects = request.getStringArray("libraryObjects") ?: emptyArray()
        if (kind == 1) {
            require(objects.isEmpty() && libraryObjects.isEmpty()) { "编译阶段不接受对象列表" }
            require(File(requireNotNull(source)).isFile) { "源码不存在" }
        } else {
            require(source == null && objectOutput == null && objects.isNotEmpty()) {
                "链接阶段输入不完整"
            }
            (objects + libraryObjects).forEach {
                val file = canonical(it)
                require(file.isInside(working) && file.isFile) { "对象文件无效" }
            }
        }
        val allowed = Regex("^[A-Za-z0-9_./:+,=\\\\-]+$")
        (request.getStringArray("arguments") ?: emptyArray()).forEach {
            require(allowed.matches(it) || it == "-Wl-b GSINIT0=0xfe0000") {
                "阶段参数包含非法字符"
            }
            require(!it.contains("..")) { "阶段参数包含越界路径" }
        }
        return mapOf(
            "working" to working.path,
            "resource" to resource.path,
            "project" to requireNotNull(request.getString("projectKind")),
            "log" to requireNotNull(controlled("logOutputPath", true)),
        ) + listOfNotNull(
            source?.let { "source" to it },
            objectOutput?.let { "object" to it },
            controlled("hexOutputPath", kind == 2)?.let { "hex" to it },
            controlled("mapOutputPath", kind == 2)?.let { "map" to it },
        )
    }

    private fun canonical(path: String?): File {
        require(!path.isNullOrBlank()) { "请求路径为空" }
        return File(path).canonicalFile
    }

    private fun File.isInside(root: File): Boolean =
        path == root.path || path.startsWith(root.path + File.separator)

    private fun isInternalCompilerNoise(line: String): Boolean =
        line.contains("__has_builtin") ||
            line.contains("__STDC_HOSTED__") ||
            line.contains("<built-in>: note:") ||
            line.startsWith("DPTR no-match:") ||
            line.contains("warning 110:") ||
            line.contains("warning 126:")

    private fun eventBundle(values: Array<String>) = Bundle().apply {
        putInt("stage", values.getOrNull(0)?.toIntOrNull() ?: 0)
        putInt("level", values.getOrNull(1)?.toIntOrNull() ?: 0)
        putInt("current", values.getOrNull(2)?.toIntOrNull() ?: 0)
        putInt("total", values.getOrNull(3)?.toIntOrNull() ?: 0)
        putString("fileName", values.getOrNull(4).orEmpty())
        putString("message", values.getOrNull(5).orEmpty())
        putInt("workerPid", Process.myPid())
        putString("workerNonce", processNonce)
    }

    private fun resultBundle(values: Array<String>, observedWarnings: Int) = Bundle().apply {
        putBoolean("success", values.getOrNull(0) == "0")
        putBoolean("canceled", values.getOrNull(0) == "5")
        putInt("exitCode", values.getOrNull(1)?.toIntOrNull() ?: -1)
        putInt("errorCount", values.getOrNull(2)?.toIntOrNull() ?: 1)
        putInt(
            "warningCount",
            maxOf(values.getOrNull(3)?.toIntOrNull() ?: 0, observedWarnings),
        )
        putString("hexPath", values.getOrNull(4).orEmpty())
        putString("mapPath", values.getOrNull(5).orEmpty())
        putString("logPath", values.getOrNull(6).orEmpty())
        putString("errorCode", values.getOrNull(7).orEmpty())
        putString("message", values.getOrNull(8).orEmpty())
        putInt("workerPid", Process.myPid())
        putString("workerNonce", processNonce)
        putString("fingerprint", SdccNativeBridge.fingerprint())
    }

    private fun terminate(delayMillis: Long) {
        Thread {
            if (delayMillis > 0) Thread.sleep(delayMillis)
            stopSelf()
            Process.killProcess(Process.myPid())
        }.start()
    }

    companion object {
        const val PROTOCOL_VERSION = 1
    }
}
