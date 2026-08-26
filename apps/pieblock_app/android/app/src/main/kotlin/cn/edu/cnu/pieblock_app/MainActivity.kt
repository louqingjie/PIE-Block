package cn.edu.cnu.pieblock_app

import android.app.Activity
import android.content.Intent
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.ServiceConnection
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.os.Debug
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var pendingExport: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var pendingDocument: MethodChannel.Result? = null
    private var pendingDocumentBytes: ByteArray? = null
    private var compilerService: ISdccCompilerService? = null
    private var compilerEventSink: EventChannel.EventSink? = null
    private var pendingCompilerStart: Pair<MethodCall, MethodChannel.Result>? = null
    private var pendingCompilerProbe: MethodChannel.Result? = null
    private var activeCompilerOperationId: String? = null
    private var usbHidBridge: UsbHidBridge? = null
    private val compilerConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            compilerService = ISdccCompilerService.Stub.asInterface(binder)
            pendingCompilerStart?.let { (call, result) ->
                pendingCompilerStart = null
                startCompilerOperation(call, result)
            }
            pendingCompilerProbe?.let { result ->
                pendingCompilerProbe = null
                try {
                    result.success(
                        requireNotNull(compilerService)
                            .capabilities()
                            .toFlutterMap("capabilities"),
                    )
                } catch (error: Exception) {
                    result.error("compiler_probe_failed", error.message, null)
                } finally {
                    runCatching { unbindService(this) }
                    compilerService = null
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            compilerService = null
            activeCompilerOperationId?.let {
                compilerEventSink?.error(
                    "compiler_process_exited",
                    "编译器进程异常退出",
                    mapOf("operationId" to it),
                )
            }
            activeCompilerOperationId = null
        }
    }

    override fun onDestroy() {
        usbHidBridge?.dispose()
        usbHidBridge = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOCUMENT_CHANNEL,
        ).setMethodCallHandler(::handleDocumentMethod)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            COMPILER_METHOD_CHANNEL,
        ).setMethodCallHandler(::handleCompilerMethod)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            COMPILER_EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                compilerEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                compilerEventSink = null
            }
        })
        usbHidBridge = UsbHidBridge(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HID_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            usbHidBridge?.handle(call, result)
                ?: result.error("hid_unavailable", "USB-HID 桥未初始化", null)
        }
    }

    private fun handleCompilerMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (activeCompilerOperationId != null || pendingCompilerStart != null) {
                    result.error("compiler_busy", "已有编译任务正在运行", null)
                    return
                }
                val service = compilerService
                if (service != null) {
                    startCompilerOperation(call, result)
                } else {
                    pendingCompilerStart = call to result
                    val intent = Intent(this, SdccCompilerService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    if (!bindService(intent, compilerConnection, Context.BIND_AUTO_CREATE)) {
                        pendingCompilerStart = null
                        result.error("compiler_bind_failed", "无法连接编译服务", null)
                    }
                }
            }
            "cancel" -> {
                val id = call.argument<String>("operationId")
                if (id != null) compilerService?.cancel(id)
                result.success(null)
            }
            "acknowledge" -> {
                val id = call.argument<String>("operationId")
                if (id != null) compilerService?.acknowledge(id)
                activeCompilerOperationId = null
                runCatching { unbindService(compilerConnection) }
                compilerService = null
                Handler(Looper.getMainLooper()).postDelayed(
                    { result.success(null) },
                    250,
                )
            }
            "protocolVersion" -> result.success(
                compilerService?.protocolVersion() ?: SdccCompilerService.PROTOCOL_VERSION,
            )
            "probe" -> {
                if (pendingCompilerProbe != null || pendingCompilerStart != null) {
                    result.error("compiler_busy", "编译服务正在连接", null)
                    return
                }
                compilerService?.let { service ->
                    result.success(service.capabilities().toFlutterMap("capabilities"))
                    return
                }
                pendingCompilerProbe = result
                val intent = Intent(this, SdccCompilerService::class.java)
                if (!bindService(intent, compilerConnection, Context.BIND_AUTO_CREATE)) {
                    pendingCompilerProbe = null
                    result.error("compiler_bind_failed", "无法连接编译服务", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startCompilerOperation(call: MethodCall, result: MethodChannel.Result) {
        try {
            val arguments = call.arguments as? Map<*, *>
                ?: error("编译请求为空")
            val request = Bundle().apply {
                fun text(key: String) = arguments[key] as? String
                    ?: error("编译请求缺少 $key")
                fun strings(key: String) =
                    (arguments[key] as? List<*>)?.map { "$it" }?.toTypedArray()
                        ?: emptyArray()
                putString("workingDirectory", text("workingDirectory"))
                putString("resourceDirectory", text("resourceDirectory"))
                putString("projectKind", text("projectKind"))
                putString("mainSourcePath", text("mainSourcePath"))
                putString("interruptHeaderPath", text("interruptHeaderPath"))
                putStringArray("sources", strings("sourcePaths"))
                putStringArray("librarySources", strings("librarySourcePaths"))
                putStringArray("compileArguments", strings("compileArguments"))
                putStringArray("linkArguments", strings("linkArguments"))
                putString("hexOutputPath", text("hexOutputPath"))
                putString("mapOutputPath", text("mapOutputPath"))
                putString("logOutputPath", text("logOutputPath"))
                if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                    (arguments["testFault"] as? String)?.let {
                        putString("testFault", it)
                    }
                    (arguments["testFaultPhase"] as? Int)?.let {
                        putInt("testFaultPhase", it)
                    }
                }
            }
            val callback = object : ISdccCompilerCallback.Stub() {
                override fun onEvent(event: Bundle) {
                    runOnUiThread {
                        compilerEventSink?.success(event.toFlutterMap("event"))
                    }
                }

                override fun onFinished(buildResult: Bundle) {
                    runOnUiThread {
                        compilerEventSink?.success(buildResult.toFlutterMap("result"))
                    }
                }
            }
            val id = requireNotNull(compilerService).start(request, callback)
            activeCompilerOperationId = id
            result.success(id)
        } catch (error: Exception) {
            result.error("compiler_start_failed", error.message, null)
        }
    }

    private fun Bundle.toFlutterMap(type: String): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>("type" to type)
        keySet().forEach { key -> result[key] = get(key) }
        result["operationId"] = activeCompilerOperationId
        return result
    }

    private fun handleDocumentMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openDocument" -> openDocument(call, result)
            "createDocument" -> createDocument(call, result)
            "readDocument" -> readDocument(call, result)
            "writeDocument" -> writeDocument(call, result)
            "saveHex" -> saveHex(call, result)
            "prepareSdccResources" -> prepareSdccResources(result)
            "getSdccNativeInfo" -> getSdccNativeInfo(result)
            "getProcessId" -> result.success(android.os.Process.myPid())
            "getProcessMetrics" -> result.success(
                mapOf(
                    "pid" to android.os.Process.myPid(),
                    "pssKb" to Debug.getPss(),
                    "openFdCount" to (File("/proc/self/fd").list()?.size ?: -1),
                ),
            )
            "debugMoveTaskToBackground" -> {
                if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                    result.error("debug_only", "仅可调试构建支持后台测试", null)
                } else {
                    result.success(moveTaskToBack(true))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        if (pendingDocument != null || pendingExport != null) {
            result.error("document_busy", "另一个文件选择任务尚未结束", null)
            return
        }
        pendingDocument = result
        val mimeTypes = call.argument<List<String>>("mimeTypes").orEmpty()
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            if (mimeTypes.isNotEmpty()) {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, OPEN_DOCUMENT_REQUEST)
    }

    private fun createDocument(call: MethodCall, result: MethodChannel.Result) {
        if (pendingDocument != null || pendingExport != null) {
            result.error("document_busy", "另一个文件选择任务尚未结束", null)
            return
        }
        pendingDocument = result
        pendingDocumentBytes = call.argument<ByteArray>("bytes")
        val suggestedName = call.argument<String>("suggestedName") ?: "document"
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, CREATE_DOCUMENT_REQUEST)
    }

    private fun readDocument(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        if (uri == null) {
            result.error("invalid_uri", "文档地址为空", null)
            return
        }
        Thread {
            try {
                val bytes = contentResolver.openInputStream(android.net.Uri.parse(uri)).use {
                    requireNotNull(it) { "无法打开文档" }.readBytes()
                }
                runOnUiThread { result.success(bytes) }
            } catch (error: Exception) {
                runOnUiThread { result.error("read_failed", error.message, null) }
            }
        }.start()
    }

    private fun writeDocument(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val bytes = call.argument<ByteArray>("bytes")
        if (uri == null || bytes == null) {
            result.error("invalid_document", "文档地址或内容为空", null)
            return
        }
        Thread {
            try {
                writeDocumentBytes(android.net.Uri.parse(uri), bytes)
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread { result.error("write_failed", error.message, null) }
            }
        }.start()
    }

    private fun writeDocumentBytes(uri: android.net.Uri, bytes: ByteArray) {
        val output = runCatching {
            contentResolver.openOutputStream(uri, "rwt")
        }.getOrNull() ?: contentResolver.openOutputStream(uri, "wt")
        output.use { stream ->
            requireNotNull(stream) { "无法打开目标文档" }
            stream.write(bytes)
            stream.flush()
        }
    }

    private fun documentName(uri: android.net.Uri): String {
        return contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment.orEmpty()
    }

    private fun saveHex(call: MethodCall, result: MethodChannel.Result) {
        if (pendingExport != null || pendingDocument != null) {
            result.error("export_busy", "另一个 HEX 导出任务尚未结束", null)
            return
        }
        val bytes = call.argument<ByteArray>("bytes")
        val suggestedName = call.argument<String>("suggestedName") ?: "firmware.hex"
        if (bytes == null) {
            result.error("invalid_bytes", "HEX 内容为空", null)
            return
        }
        pendingExport = result
        pendingBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        startActivityForResult(intent, EXPORT_HEX_REQUEST)
    }

    private fun getSdccNativeInfo(result: MethodChannel.Result) {
        try {
            val (abi, hash) = findSdccNativeLibrary()
            result.success(
                mapOf(
                    "abi" to abi,
                    "sha256" to hash,
                ),
            )
        } catch (error: Exception) {
            result.error("sdcc_native_error", error.message, null)
        }
    }

    private fun findSdccNativeLibrary(): Pair<String, String> {
        val extracted = File(
            applicationInfo.nativeLibraryDir,
            "libpieblock_sdcc_native.so",
        )
        if (extracted.isFile) {
            return Build.SUPPORTED_ABIS.firstOrNull().orEmpty() to sha256(extracted)
        }

        val apkPaths = buildList {
            add(applicationInfo.sourceDir)
            applicationInfo.splitSourceDirs?.let(::addAll)
        }
        for (apkPath in apkPaths) {
            ZipFile(apkPath).use { apk ->
                for (abi in Build.SUPPORTED_ABIS) {
                    val entry = apk.getEntry("lib/$abi/libpieblock_sdcc_native.so")
                        ?: continue
                    return abi to apk.getInputStream(entry).use(::sha256)
                }
            }
        }
        error("安装包缺少 Android SDCC 原生库")
    }

    private fun prepareSdccResources(result: MethodChannel.Result) {
        Thread {
            try {
                val manifestText = assets.open("pieblock_sdcc/bundle_manifest.json")
                    .bufferedReader(Charsets.UTF_8)
                    .use { it.readText() }
                val manifest = JSONObject(manifestText)
                require(manifest.getInt("format_version") == 1) {
                    "不支持的 SDCC 资源包格式"
                }
                val fingerprint = manifest.getString("fingerprint")
                require(fingerprint.matches(Regex("[0-9a-f]{64}"))) {
                    "非法的 SDCC 资源包指纹"
                }
                val destination = File(filesDir, "pieblock_sdcc/$fingerprint")
                val marker = File(destination, ".ready")
                val files = manifest.getJSONObject("files")
                val names = files.keys().asSequence().toList().sorted()
                val fingerprintInput = names.joinToString("\n") { relative ->
                    "$relative:${files.getString(relative)}"
                }
                require(
                    sha256(fingerprintInput.toByteArray(Charsets.UTF_8)) == fingerprint,
                ) { "SDCC 资源清单指纹不匹配" }
                val resourceParent = File(filesDir, "pieblock_sdcc")
                resourceParent.mkdirs()
                resourceParent.listFiles()
                    ?.filter { it.isDirectory && it.name.endsWith(".pending") }
                    ?.forEach { it.deleteRecursively() }
                if (
                    marker.isFile &&
                    marker.readText() == fingerprint &&
                    validateResources(destination, names, files)
                ) {
                    runOnUiThread { result.success(destination.absolutePath) }
                    return@Thread
                }
                val pending = File(resourceParent, "$fingerprint.pending")
                pending.deleteRecursively()
                require(pending.mkdirs()) { "无法创建 SDCC 资源临时目录" }
                for (relative in names) {
                    val output = File(pending, relative).canonicalFile
                    require(output.path.startsWith(pending.canonicalPath + File.separator)) {
                        "SDCC 资源路径越界：$relative"
                    }
                    output.parentFile?.mkdirs()
                    assets.open("pieblock_sdcc/$relative").use { input ->
                        output.outputStream().use { stream -> input.copyTo(stream) }
                    }
                    val actual = sha256(output)
                    require(actual == files.getString(relative)) {
                        "SDCC 资源校验失败：$relative"
                    }
                }
                marker.parentFile?.mkdirs()
                File(pending, ".ready").writeText(fingerprint)
                destination.deleteRecursively()
                require(pending.renameTo(destination)) { "无法原子部署 SDCC 资源包" }
                runOnUiThread { result.success(destination.absolutePath) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("sdcc_resource_error", error.message, null)
                }
            }
        }.start()
    }

    private fun sha256(file: File): String {
        return file.inputStream().use(::sha256)
    }

    private fun sha256(input: java.io.InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        input.use {
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun sha256(bytes: ByteArray): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
    }

    private fun validateResources(
        root: File,
        names: List<String>,
        files: JSONObject,
    ): Boolean {
        return names.all { relative ->
            val file = File(root, relative)
            file.isFile && sha256(file) == files.getString(relative)
        }
    }

    @Deprecated("Deprecated in Android, retained for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            OPEN_DOCUMENT_REQUEST, CREATE_DOCUMENT_REQUEST -> {
                val result = pendingDocument ?: return
                val bytes = pendingDocumentBytes
                pendingDocument = null
                pendingDocumentBytes = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                val permissionFlags = data.flags and (
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                runCatching {
                    contentResolver.takePersistableUriPermission(uri, permissionFlags)
                }
                Thread {
                    try {
                        if (requestCode == CREATE_DOCUMENT_REQUEST) {
                            if (bytes != null) writeDocumentBytes(uri, bytes)
                            runOnUiThread {
                                result.success(
                                    mapOf("uri" to uri.toString(), "name" to documentName(uri)),
                                )
                            }
                        } else {
                            val contents = contentResolver.openInputStream(uri).use {
                                requireNotNull(it) { "无法打开所选文档" }.readBytes()
                            }
                            runOnUiThread {
                                result.success(
                                    mapOf(
                                        "uri" to uri.toString(),
                                        "name" to documentName(uri),
                                        "bytes" to contents,
                                    ),
                                )
                            }
                        }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("document_access_failed", error.message, null)
                        }
                    }
                }.start()
            }
            EXPORT_HEX_REQUEST -> {
                val result = pendingExport ?: return
                val bytes = pendingBytes
                pendingExport = null
                pendingBytes = null
                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result.success(false)
                    return
                }
                try {
                    writeDocumentBytes(data.data!!, requireNotNull(bytes))
                    result.success(true)
                } catch (error: Exception) {
                    result.error("export_failed", error.message, null)
                }
            }
        }
    }

    companion object {
        private const val DOCUMENT_CHANNEL = "cn.edu.cnu.pieblock/documents"
        private const val COMPILER_METHOD_CHANNEL = "cn.edu.cnu.pieblock/sdcc_compiler"
        private const val COMPILER_EVENT_CHANNEL = "cn.edu.cnu.pieblock/sdcc_compiler_events"
        private const val HID_METHOD_CHANNEL = "cn.edu.cnu.pieblock/hid"
        private const val EXPORT_HEX_REQUEST = 0x5042
        private const val OPEN_DOCUMENT_REQUEST = 0x5043
        private const val CREATE_DOCUMENT_REQUEST = 0x5044
    }
}
