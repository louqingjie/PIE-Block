package cn.edu.cnu.pieblock_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import androidx.core.app.NotificationCompat
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference

class SdccCompilerService : Service() {
    private data class Phase(
        val kind: Int,
        val index: Int,
        val source: String? = null,
        val objectOutput: String? = null,
        val logPath: String,
    )

    private data class ActiveBuild(
        val id: String,
        val callback: ISdccCompilerCallback,
        val request: Bundle,
        val phases: List<Phase>,
        val objects: List<String>,
        val libraryObjects: List<String>,
        val generatedFiles: List<String>,
        @Volatile var phaseIndex: Int = 0,
        @Volatile var warningCount: Int = 0,
        @Volatile var canceled: Boolean = false,
        @Volatile var completed: Boolean = false,
        @Volatile var workerOperationId: String? = null,
        @Volatile var workerPid: Int = 0,
        @Volatile var workerNonce: String? = null,
        val workerPids: ArrayList<Int> = arrayListOf(),
        val workerNonces: ArrayList<String> = arrayListOf(),
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val active = AtomicReference<ActiveBuild?>(null)
    private var worker: ISdccWorkerService? = null
    private var workerConnection: ServiceConnection? = null
    private var actionAfterWorkerDeath: (() -> Unit)? = null
    private var workerConnectTimeout: Runnable? = null
    private var workerStageTimeout: Runnable? = null

    private val binder = object : ISdccCompilerService.Stub() {
        override fun protocolVersion(): Int = PROTOCOL_VERSION

        override fun capabilities(): Bundle = Bundle().apply {
            putInt("protocolVersion", PROTOCOL_VERSION)
            putInt("workerProtocolVersion", SdccCompilerWorkerService.PROTOCOL_VERSION)
            putInt("apiVersion", SdccNativeBridge.apiVersion())
            putBoolean("available", SdccNativeBridge.isAvailable())
            putString("fingerprint", serviceFingerprint())
            putInt("compilerPid", Process.myPid())
        }

        override fun start(request: Bundle, callback: ISdccCompilerCallback): String {
            val build = createBuild(request, callback)
            check(active.compareAndSet(null, build)) { "已有编译任务正在运行" }
            callback.asBinder().linkToDeath({ cancelAndTerminate(build) }, 0)
            startForeground(NOTIFICATION_ID, notification("正在准备多进程固件编译…"))
            bindNextWorker(build)
            return build.id
        }

        override fun cancel(operationId: String) {
            active.get()?.takeIf { it.id == operationId }?.let { build ->
                build.canceled = true
                build.workerOperationId?.let { worker?.cancel(it) }
                mainHandler.postDelayed({
                    if (!build.completed && build.workerPid > 0) {
                        Process.killProcess(build.workerPid)
                    }
                }, 2_000)
            }
        }

        override fun acknowledge(operationId: String) {
            val build = active.get() ?: return
            if (build.id != operationId || !build.completed) return
            active.compareAndSet(build, null)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            Thread {
                Thread.sleep(100)
                Process.killProcess(Process.myPid())
            }.start()
        }
    }

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "固件编译", NotificationManager.IMPORTANCE_LOW),
        )
        cleanupInterruptedBuilds()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        active.get()?.let(::cancelAndTerminate)
        workerConnection?.let { runCatching { unbindService(it) } }
        super.onDestroy()
    }

    private fun createBuild(request: Bundle, callback: ISdccCompilerCallback): ActiveBuild {
        val values = validateBuildRequest(request)
        val requestedSources = request.getStringArray("sources")!!.toList()
        val librarySources = (request.getStringArray("librarySources") ?: emptyArray()).toSet()
        val output = File(values.getValue("hex")).parentFile!!.canonicalFile
        require(output.mkdirs() || output.isDirectory) { "无法创建构建输出目录" }
        val requestedMain = File(requireNotNull(request.getString("mainSourcePath"))).canonicalFile
        val androidMain = File(output, "generated_main_android.c")
        androidMain.writeText(
            requestedMain.readText().replace("\"MATH.H\"", "\"math.h\""),
        )
        val sources = requestedSources.map { source ->
            if (File(source).canonicalFile == requestedMain) androidMain.path else source
        }
        request.putStringArray("sources", sources.toTypedArray())
        val objects = requestedSources.mapIndexed { index, source ->
            val stem = File(source).nameWithoutExtension.replace(Regex("[^A-Za-z0-9_]"), "_")
            // 与 Windows 后端保持完全一致；索引同时解决同名源码碰撞。
            File(output, "${stem}_$index.rel").path
        }
        val phases = sources.mapIndexed { index, source ->
            Phase(
                kind = OP_COMPILE,
                index = index,
                source = source,
                objectOutput = objects[index],
                logPath = File(output, "phase_${index.toString().padStart(3, '0')}.log").path,
            )
        } + Phase(
            kind = OP_LINK,
            index = sources.size,
            logPath = File(output, "phase_link.log").path,
        )
        val libraryObjects = sources.mapIndexedNotNull { index, source ->
            objects[index].takeIf { source in librarySources }
        }
        val regularObjects = objects.filterNot { it in libraryObjects }
        request.putString("canonicalWorking", values.getValue("working"))
        request.putString("canonicalResource", values.getValue("resource"))
        request.putString("canonicalHex", values.getValue("hex"))
        request.putString("canonicalMap", values.getValue("map"))
        request.putString("canonicalLog", values.getValue("log"))
        request.putString("canonicalMainSource", androidMain.path)
        (objects + phases.map { it.logPath }).forEach { File(it).delete() }
        File(values.getValue("hex")).delete()
        File(values.getValue("map")).delete()
        File(values.getValue("log")).delete()
        File(values.getValue("working"), ".in_progress").writeText("${Process.myPid()}")
        return ActiveBuild(
            id = UUID.randomUUID().toString(),
            callback = callback,
            request = request,
            phases = phases,
            objects = regularObjects,
            libraryObjects = libraryObjects,
            generatedFiles = listOf(androidMain.path),
        )
    }

    private fun bindNextWorker(build: ActiveBuild) {
        if (build.canceled) {
            finish(build, false, true, -1, "构建已取消", "canceled")
            return
        }
        if (build.phaseIndex >= build.phases.size) {
            finish(build, true, false, 0, "Android SDCC 多进程构建完成", "")
            return
        }
        require(worker == null && workerConnection == null) { "上一 Worker 尚未销毁" }
        val phase = build.phases[build.phaseIndex]
        updateNotification(
            if (phase.kind == OP_LINK) "正在链接固件…"
            else "正在编译 ${File(phase.source!!).name}…",
        )
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                if (workerConnection !== this) return
                workerConnectTimeout?.let(mainHandler::removeCallbacks)
                workerConnectTimeout = null
                worker = ISdccWorkerService.Stub.asInterface(binder)
                try {
                    val capabilities = requireNotNull(worker).capabilities()
                    require(capabilities.getInt("protocolVersion") == 1) { "Worker 协议不匹配" }
                    require(capabilities.getInt("apiVersion") == 5) { "Worker C ABI 不匹配" }
                    require(capabilities.getBoolean("available")) { "Worker 安全门未通过" }
                    val pid = capabilities.getInt("workerPid")
                    val nonce = requireNotNull(capabilities.getString("workerNonce"))
                    require(nonce !in build.workerNonces) { "Worker 进程未刷新" }
                    build.workerPid = pid
                    build.workerNonce = nonce
                    build.workerPids.add(pid)
                    build.workerNonces.add(nonce)
                    startWorkerPhase(build, phase)
                } catch (error: Throwable) {
                    val failedWorker = worker
                    worker = null
                    workerConnection = null
                    runCatching { unbindService(this) }
                    runCatching { failedWorker?.shutdown() }
                    finish(
                        build,
                        false,
                        false,
                        -1,
                        error.message ?: "Worker 自检失败",
                        "worker_probe_failed",
                    )
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                if (workerConnection !== this) return
                workerConnectTimeout?.let(mainHandler::removeCallbacks)
                workerConnectTimeout = null
                workerStageTimeout?.let(mainHandler::removeCallbacks)
                workerStageTimeout = null
                worker = null
                build.workerOperationId = null
                build.workerPid = 0
                workerConnection?.let { runCatching { unbindService(it) } }
                workerConnection = null
                val action = actionAfterWorkerDeath
                actionAfterWorkerDeath = null
                if (action != null) action()
                else if (!build.completed) {
                    build.phases.getOrNull(build.phaseIndex)?.let { phase ->
                        appendPhaseLog(build, phase)
                    }
                    if (build.canceled) {
                        finish(build, false, true, -1, "构建已取消", "canceled")
                    } else {
                        finish(
                            build,
                            false,
                            false,
                            -1,
                            "编译 Worker 异常退出",
                            "worker_disconnected",
                        )
                    }
                }
            }
        }
        workerConnection = connection
        if (!bindService(
                Intent(this, SdccCompilerWorkerService::class.java),
                connection,
                Context.BIND_AUTO_CREATE,
            )) {
            workerConnection = null
            finish(build, false, false, -1, "无法启动编译 Worker", "worker_bind_failed")
            return
        }
        workerConnectTimeout = Runnable {
            if (workerConnection === connection && worker == null && !build.completed) {
                runCatching { unbindService(connection) }
                workerConnection = null
                finish(build, false, false, -1, "编译 Worker 连接超时", "worker_bind_timeout")
            }
        }.also { mainHandler.postDelayed(it, WORKER_CONNECT_TIMEOUT_MS) }
    }

    private fun startWorkerPhase(build: ActiveBuild, phase: Phase) {
        val request = workerRequest(build, phase)
        val callback = object : ISdccCompilerCallback.Stub() {
            override fun onEvent(event: Bundle) {
                event.putInt("current", phase.index + 1)
                event.putInt("total", build.phases.size)
                event.putInt("coordinatorPid", Process.myPid())
                build.callback.onEvent(event)
            }

            override fun onFinished(result: Bundle) {
                workerStageTimeout?.let(mainHandler::removeCallbacks)
                workerStageTimeout = null
                val completedWorkerPid = build.workerPid
                val completedWorkerNonce = build.workerNonce
                build.warningCount += result.getInt("warningCount")
                appendPhaseLog(build, phase)
                val phaseSucceeded = result.getBoolean("success") && phaseOutputExists(build, phase)
                val validationError = if (phase.kind == OP_LINK && phaseSucceeded) {
                    firmwareValidationError(build)
                } else {
                    null
                }
                val success = phaseSucceeded && validationError == null
                actionAfterWorkerDeath = {
                    if (success && !build.canceled) {
                        build.phaseIndex++
                        bindNextWorker(build)
                    } else {
                        finish(
                            build,
                            false,
                            build.canceled || result.getBoolean("canceled"),
                            result.getInt("exitCode", -1),
                            validationError ?: result.getString("message") ?: "编译阶段失败",
                            if (validationError == null) {
                                result.getString("errorCode") ?: "worker_stage_failed"
                            } else {
                                "firmware_validation_failed"
                            },
                        )
                    }
                }
                releaseCompletedWorker(
                    build,
                    requireNotNull(completedWorkerNonce),
                    completedWorkerPid,
                )
            }
        }
        build.workerOperationId = requireNotNull(worker).start(request, callback)
        workerStageTimeout = Runnable {
            if (!build.completed &&
                build.workerPid > 0 &&
                build.phaseIndex == phase.index
            ) {
                val timedOutPid = build.workerPid
                actionAfterWorkerDeath = {
                    appendPhaseLog(build, phase)
                    finish(build, false, false, -1, "编译阶段超时", "worker_stage_timeout")
                }
                Process.killProcess(timedOutPid)
            }
        }.also { mainHandler.postDelayed(it, WORKER_STAGE_TIMEOUT_MS) }
    }

    private fun releaseCompletedWorker(build: ActiveBuild, nonce: String, pid: Int) {
        val completedWorker = worker
        val completedConnection = workerConnection
        val completedBinder = completedWorker?.asBinder()
        requireNotNull(completedWorker)
        requireNotNull(completedConnection)
        requireNotNull(completedBinder)

        val deathRecipient = IBinder.DeathRecipient {
            mainHandler.post { finishExpectedWorkerExit(build, nonce, pid) }
        }
        val deathWatchInstalled = runCatching {
            completedBinder.linkToDeath(deathRecipient, 0)
        }.isSuccess

        // 先解除 BIND_AUTO_CREATE，避免杀死阶段进程后 Android 为仍存活的
        // 连接自动拉起一个没有新请求的幽灵 Worker。
        workerConnection = null
        worker = null
        runCatching { unbindService(completedConnection) }
        runCatching { completedWorker.acknowledge(requireNotNull(build.workerOperationId)) }
        if (!deathWatchInstalled) {
            finishExpectedWorkerExit(build, nonce, pid)
            return
        }

        mainHandler.postDelayed({
            if (!build.completed &&
                build.workerPid == pid &&
                build.workerNonce == nonce
            ) {
                Process.killProcess(pid)
            }
        }, WORKER_EXIT_GRACE_MS)
        mainHandler.postDelayed({
            if (!build.completed &&
                build.workerPid == pid &&
                build.workerNonce == nonce
            ) {
                actionAfterWorkerDeath = null
                finish(
                    build,
                    false,
                    false,
                    -1,
                    "编译 Worker 无法退出",
                    "worker_exit_timeout",
                )
            }
        }, WORKER_EXIT_TIMEOUT_MS)
    }

    private fun finishExpectedWorkerExit(build: ActiveBuild, nonce: String, pid: Int) {
        if (build.completed || build.workerPid != pid || build.workerNonce != nonce) return
        build.workerOperationId = null
        build.workerPid = 0
        build.workerNonce = null
        val action = actionAfterWorkerDeath
        actionAfterWorkerDeath = null
        action?.invoke()
    }

    private fun workerRequest(build: ActiveBuild, phase: Phase) = Bundle().apply {
        putInt("operationKind", phase.kind)
        putString("workingDirectory", build.request.getString("canonicalWorking"))
        putString("resourceDirectory", build.request.getString("canonicalResource"))
        putString("projectKind", build.request.getString("projectKind"))
        putString("sourcePath", phase.source)
        putString("objectOutputPath", phase.objectOutput)
        putStringArray("objects", if (phase.kind == OP_LINK) build.objects.toTypedArray() else emptyArray())
        putStringArray(
            "libraryObjects",
            if (phase.kind == OP_LINK) build.libraryObjects.toTypedArray() else emptyArray(),
        )
        var arguments = if (phase.kind == OP_LINK) {
            build.request.getStringArray("linkArguments") ?: emptyArray()
        } else {
            build.request.getStringArray("compileArguments") ?: emptyArray()
        }
        if (phase.kind == OP_COMPILE && phase.source == build.request.getString("canonicalMainSource")) {
            arguments += arrayOf("--include", requireNotNull(build.request.getString("interruptHeaderPath")))
        }
        putStringArray("arguments", arguments)
        putString("hexOutputPath", build.request.getString("canonicalHex").takeIf { phase.kind == OP_LINK })
        putString("mapOutputPath", build.request.getString("canonicalMap").takeIf { phase.kind == OP_LINK })
        putString("logOutputPath", phase.logPath)
    }

    private fun phaseOutputExists(build: ActiveBuild, phase: Phase): Boolean =
        if (phase.kind == OP_COMPILE) File(requireNotNull(phase.objectOutput)).isFile
        else File(requireNotNull(build.request.getString("canonicalHex"))).isFile &&
            File(requireNotNull(build.request.getString("canonicalMap"))).isFile

    private fun firmwareValidationError(build: ActiveBuild): String? {
        val hex = File(requireNotNull(build.request.getString("canonicalHex")))
        val map = File(requireNotNull(build.request.getString("canonicalMap")))
        val bytes = mutableMapOf<Int, Int>()
        var upper = 0
        try {
            hex.readLines().forEachIndexed { index, raw ->
                val line = raw.trim()
                if (line.isEmpty()) return@forEachIndexed
                if (!line.startsWith(':') || (line.length - 1) % 2 != 0) {
                    return "HEX 第 ${index + 1} 行格式无效"
                }
                val values = line.drop(1).chunked(2).map { it.toInt(16) }
                if (values.size < 5 || values.size != values.first() + 5) {
                    return "HEX 第 ${index + 1} 行长度错误"
                }
                if (values.sum().and(0xff) != 0) return "HEX 第 ${index + 1} 行校验和错误"
                val count = values[0]
                val address = (values[1] shl 8) or values[2]
                when (values[3]) {
                    0 -> repeat(count) { offset -> bytes[upper + address + offset] = values[4 + offset] }
                    1, 3, 5 -> Unit
                    2 -> upper = ((values[4] shl 8) or values[5]) shl 4
                    4 -> upper = ((values[4] shl 8) or values[5]) shl 16
                    else -> return "HEX 第 ${index + 1} 行记录类型不受支持"
                }
            }
        } catch (error: Throwable) {
            return "HEX 解析失败：${error.message}"
        }
        if (bytes.isEmpty()) return "HEX 中没有数据"
        val min = bytes.keys.min()
        val max = bytes.keys.max()
        if (min < APPLICATION_BASE || max > 0xffffff) return "HEX 地址超出主控板应用区"
        if (bytes.keys.none { it < VECTOR_BASE }) return "HEX 缺少 0xFE0000 用户代码区"
        if (bytes[VECTOR_BASE] != 0x02 ||
            !bytes.containsKey(VECTOR_BASE + 1) ||
            !bytes.containsKey(VECTOR_BASE + 2)
        ) return "HEX 缺少完整的 0xFF0000 LJMP 复位向量"
        if (bytes.keys.any { it >= VECTOR_LIMIT }) return "向量区数据越过 0xFF1000"

        val mapText = runCatching { map.readText() }.getOrElse {
            return "MAP 读取失败：${it.message}"
        }
        val pattern = Regex(
            """^\s*(HOME|GSINIT|GSFINAL|CSEG|CONST|XINIT|XISEG|DSEG|SSEG|PSEG|XSEG)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})\s+=""",
            setOf(RegexOption.MULTILINE),
        )
        for (match in pattern.findAll(mapText)) {
            val name = match.groupValues[1]
            val start = match.groupValues[2].toInt(16)
            val length = match.groupValues[3].toInt(16)
            val end = start + length
            val valid = when (name) {
                "HOME" -> start == VECTOR_BASE && end <= VECTOR_LIMIT
                "GSINIT", "GSFINAL", "CSEG", "CONST", "XINIT" ->
                    length == 0 || start in APPLICATION_BASE until VECTOR_BASE && end <= VECTOR_BASE
                "XSEG", "XISEG" ->
                    length == 0 || start in XRAM_BASE until XRAM_LIMIT && end <= XRAM_LIMIT
                else -> length == 0 || start >= 0 && end <= IRAM_LIMIT
            }
            if (!valid) return "$name 超出 STC32G 固件布局"
        }
        for (symbol in REQUIRED_MAP_SYMBOLS) {
            if (!mapText.contains(symbol)) return "MAP 缺少启动或向量符号：$symbol"
        }
        return null
    }

    private fun appendPhaseLog(build: ActiveBuild, phase: Phase) {
        val aggregate = File(requireNotNull(build.request.getString("canonicalLog")))
        aggregate.parentFile?.mkdirs()
        aggregate.appendText("\n=== phase ${phase.index + 1}/${build.phases.size} pid=${build.workerPid} nonce=${build.workerNonce} ===\n")
        val phaseLog = File(phase.logPath)
        if (phaseLog.isFile) aggregate.appendText(phaseLog.readText())
    }

    private fun finish(
        build: ActiveBuild,
        success: Boolean,
        canceled: Boolean,
        exitCode: Int,
        message: String,
        errorCode: String,
    ) {
        if (build.completed) return
        build.completed = true
        workerConnectTimeout?.let(mainHandler::removeCallbacks)
        workerConnectTimeout = null
        workerStageTimeout?.let(mainHandler::removeCallbacks)
        workerStageTimeout = null
        File(requireNotNull(build.request.getString("canonicalWorking")), ".in_progress").delete()
        cleanupIntermediateFiles(build)
        if (!success) {
            File(requireNotNull(build.request.getString("canonicalHex"))).delete()
            File(requireNotNull(build.request.getString("canonicalMap"))).delete()
        }
        build.callback.onFinished(Bundle().apply {
            putBoolean("success", success)
            putBoolean("canceled", canceled)
            putInt("exitCode", exitCode)
            putInt("warningCount", build.warningCount)
            putString("hexPath", build.request.getString("canonicalHex"))
            putString("mapPath", build.request.getString("canonicalMap"))
            putString("logPath", build.request.getString("canonicalLog"))
            putString(
                "hexSha256",
                if (success) sha256(File(requireNotNull(build.request.getString("canonicalHex"))))
                else "",
            )
            putString("errorCode", errorCode)
            putString("message", message)
            putInt("compilerPid", Process.myPid())
            putIntegerArrayList("workerPids", build.workerPids)
            putStringArrayList("workerNonces", build.workerNonces)
            putString("fingerprint", serviceFingerprint())
        })
    }

    private fun cleanupIntermediateFiles(build: ActiveBuild) {
        build.phases.forEach { File(it.logPath).delete() }
        (build.objects + build.libraryObjects).forEach { File(it).delete() }
        build.generatedFiles.forEach { File(it).delete() }
        val output = File(requireNotNull(build.request.getString("canonicalHex"))).parentFile
            ?: return
        val intermediateExtensions = setOf("asm", "lst", "sym", "rst", "lk", "mem", "rel")
        output.listFiles()?.forEach { file ->
            if (file.extension in intermediateExtensions || file.name == "stc32g_shared.lib"
            ) {
                file.delete()
            }
        }
    }

    private fun serviceFingerprint(): String =
        SdccNativeBridge.fingerprint() +
            ";coordinator:$PROTOCOL_VERSION" +
            ";worker:${SdccCompilerWorkerService.PROTOCOL_VERSION}" +
            ";scheduler:$SCHEDULER_VERSION" +
            ";source-normalization:$SOURCE_NORMALIZATION_VERSION"

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun validateBuildRequest(request: Bundle): Map<String, String> {
        val working = canonical(request.getString("workingDirectory"))
        val resource = canonical(request.getString("resourceDirectory"))
        require(listOf(cacheDir.canonicalFile, filesDir.canonicalFile).any { working.isInside(it) }) {
            "构建目录不在应用私有目录"
        }
        require(resource.isInside(File(filesDir, "pieblock_sdcc").canonicalFile)) { "资源目录越界" }
        val marker = File(resource, ".ready")
        require(marker.isFile && marker.readText().trim() == resource.name) { "资源指纹无效" }
        fun controlled(key: String): String {
            val file = canonical(request.getString(key))
            require(file.isInside(working)) { "$key 路径越界" }
            return file.path
        }
        val sources = request.getStringArray("sources") ?: emptyArray()
        require(sources.isNotEmpty()) { "源码列表为空" }
        sources.forEach {
            val file = canonical(it)
            require((file.isInside(working) || file.isInside(resource)) && file.isFile) { "源码无效" }
        }
        val sourceSet = sources.map { canonical(it).path }.toSet()
        (request.getStringArray("librarySources") ?: emptyArray()).forEach {
            require(canonical(it).path in sourceSet) { "库源码不在源码列表" }
        }
        val allowed = Regex("^[A-Za-z0-9_./:+,=\\\\-]+$")
        listOf("compileArguments", "linkArguments").forEach { key ->
            (request.getStringArray(key) ?: emptyArray()).forEach {
                require(allowed.matches(it) || it == "-Wl-b GSINIT0=0xfe0000") { "参数非法" }
                require(!it.contains("..")) { "参数路径越界" }
            }
        }
        controlled("mainSourcePath")
        controlled("interruptHeaderPath")
        return mapOf(
            "working" to working.path,
            "resource" to resource.path,
            "hex" to controlled("hexOutputPath"),
            "map" to controlled("mapOutputPath"),
            "log" to controlled("logOutputPath"),
        )
    }

    private fun cancelAndTerminate(build: ActiveBuild) {
        build.canceled = true
        build.workerOperationId?.let { runCatching { worker?.cancel(it) } }
        build.workerPid.takeIf { it > 0 }?.let(Process::killProcess)
        finish(build, false, true, -1, "构建已取消", "canceled")
        stopSelf()
    }

    private fun canonical(path: String?): File {
        require(!path.isNullOrBlank()) { "请求路径为空" }
        return File(path).canonicalFile
    }

    private fun File.isInside(root: File): Boolean =
        path == root.path || path.startsWith(root.path + File.separator)

    private fun cleanupInterruptedBuilds() {
        listOf(cacheDir, filesDir).forEach { root ->
            root.walkTopDown().filter { it.isFile && it.name == ".in_progress" }
                .mapNotNull { it.parentFile }.toList().forEach { directory ->
                    directory.listFiles()?.forEach { file ->
                        if (!file.name.endsWith(".log")) file.deleteRecursively()
                    }
                }
        }
    }

    private fun notification(text: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(applicationInfo.icon)
        .setContentTitle("PIE-Block")
        .setContentText(text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .build()

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(text))
    }

    companion object {
        const val PROTOCOL_VERSION = 2
        private const val OP_COMPILE = 1
        private const val OP_LINK = 2
        private const val CHANNEL_ID = "pieblock_firmware_build"
        private const val NOTIFICATION_ID = 0x5042
        private const val WORKER_CONNECT_TIMEOUT_MS = 15_000L
        private const val WORKER_STAGE_TIMEOUT_MS = 90_000L
        private const val WORKER_EXIT_GRACE_MS = 3_000L
        private const val WORKER_EXIT_TIMEOUT_MS = 10_000L
        private const val SCHEDULER_VERSION = 1
        private const val SOURCE_NORMALIZATION_VERSION = 1
        private const val APPLICATION_BASE = 0xfe0000
        private const val VECTOR_BASE = 0xff0000
        private const val VECTOR_LIMIT = 0xff1000
        private const val XRAM_BASE = 0x010000
        private const val XRAM_LIMIT = 0x012000
        private const val IRAM_LIMIT = 0x1000
        private val REQUIRED_MAP_SYMBOLS = listOf(
            "__sdcc_mcs251_reset_trampoline",
            "__sdcc_gsinit_startup",
            "_Default_Isr",
        )
    }
}
