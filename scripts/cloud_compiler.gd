class_name CloudCompiler
extends RefCounted

## 云端编译核心：把工程打包成自包含 zip，通过 Base URL + API Key 上传到
## keil_server 编译服务，轮询任务、下载 hex、拉取日志。
##
## 异步流程在独立 Thread 中跑（同步 HTTPClient，支持二进制 body），与
## BuildController 的线程编译模式一致；完成后 call_deferred 回主线程发 finished。
##
## 打包用 ZIPPacker（Godot 4 内置），产物结构保持与 keil_server.find_uvproj
## 兼容的 Projects/ROBOMASTER_<kind> + Libraries（uvproj 用 ..\..\..\Libraries\）。

signal finished(result: Dictionary)

const POLL_INTERVAL_MS: int = 500
const MAX_POLL_SEC: int = 600
const HTTP_TIMEOUT_MS: int = 30000
const BOUNDARY: String = "----PieBlockBoundary7f3a"

var _toolchain
var _log: Callable
var _thread: Thread = null
var _joined: bool = false
var _busy: bool = false
var _base_url: String = ""
var _api_key: String = ""


func _init(toolchain, log_sink: Callable = Callable()) -> void:
	_toolchain = toolchain
	_log = log_sink


func _emit(line_text: String) -> void:
	if _log.is_valid():
		_log.call(line_text)


func is_busy() -> bool:
	return _busy


## 云端编译入口。project_dst 为已部署的工程目录（user://stc32g/Projects/...）。
## 返回是否成功启动（busy 时返回 false）。
func compile(project_dst: String, code: String, base_url: String, api_key: String) -> bool:
	if _busy or _thread != null:
		return false
	_base_url = base_url.strip_edges().trim_suffix("/")
	_api_key = api_key
	_set_busy(true)
	_thread = Thread.new()
	var err: Error = _thread.start(_worker.bind(project_dst, code))
	if err != OK:
		_thread = null
		_set_busy(false)
		return false
	return true


func _set_busy(value: bool) -> void:
	_busy = value


## 等待后台线程结束（只 join 一次）。场景退出/重启时调用。
func shutdown() -> void:
	_join_thread()


func _join_thread() -> void:
	if _thread and not _joined:
		_thread.wait_to_finish()
		_thread = null
		_joined = true


# ------------------------------------------------------------------ worker（线程内）
func _worker(project_dst: String, code: String) -> void:
	var result: Dictionary = _run_cloud_build(project_dst, code)
	call_deferred("_on_worker_finished", result)


func _run_cloud_build(project_dst: String, code: String) -> Dictionary:
	var log_lines: Array[String] = []
	# 0) 云端配置（Base URL + API Key）——统一以 Toolchain 持久化配置为准
	var cfg: Dictionary = _toolchain.get_cloud_config()
	if not cfg.ok or str(cfg.get("base_url", "")).is_empty() \
			or str(cfg.get("api_key", "")).is_empty():
		return _make_result(false, ["[Error] 云端编译配置不完整（Base URL / API Key）"], "", "", "")
	_base_url = str(cfg.base_url).trim_suffix("/")
	_api_key = str(cfg.api_key)
	# 1) 部署 + 写盘（复用 Toolchain，与本地编译一致）
	if not _toolchain.ensure_deployed():
		return _make_result(false, ["[Error] 项目部署失败"], "", "", "")
	if not _toolchain.write_main_c(project_dst, code):
		return _make_result(false, ["[Error] 写入 main.c 失败"], "", "", "")
	# 2) 打包自包含 zip
	var zip_path: String = "user://cloud_build_%d.zip" % Time.get_ticks_msec()
	var abs_zip: String = ProjectSettings.globalize_path(zip_path)
	if not _pack_project_zip(project_dst, abs_zip):
		return _make_result(false, ["[Error] 打包工程 zip 失败"], "", "", "")
	# 3) 上传
	log_lines.append("正在上传工程到 %s/compile …" % _base_url)
	var upload: Dictionary = _http_request(
		HTTPClient.METHOD_POST, "/compile_base64", _json_headers(), _zip_base64_json_body(abs_zip))
	if not upload.ok:
		return _make_result(false, log_lines + ["[Error] %s" % upload.error], "", "", "")
	if upload.status == 401 or upload.status == 403:
		return _make_result(false, log_lines + ["[Error] 云端鉴权失败（HTTP %d）：请检查 API Key" % upload.status], "", "", "")
	if upload.status != 200:
		return _make_result(false, log_lines + ["[Error] 上传编译失败（HTTP %d）" % upload.status], "", "", "")
	var task_id: String = _json_get(upload.body_text, "task_id", "")
	if task_id.is_empty():
		return _make_result(false, log_lines + ["[Error] 上传成功但未返回 task_id"], "", "", "")
	log_lines.append("已提交编译任务：%s" % task_id)
	# 4) 轮询
	log_lines.append("正在等待云端编译…（轮询 %s）" % "/tasks/%s" % task_id)
	var poll_sec: int = 0
	var task_status: String = ""
	var task_error: String = ""
	while poll_sec <= MAX_POLL_SEC:
		var resp: Dictionary = _http_request(
			HTTPClient.METHOD_GET, "/tasks/%s" % task_id, _auth_headers(), "")
		if resp.ok and resp.status == 200:
			task_status = _json_get(resp.body_text, "status", "")
			task_error = _json_get(resp.body_text, "error", "")
			if task_status == "success" or task_status == "failed":
				break
		OS.delay_msec(POLL_INTERVAL_MS)
		poll_sec += 1
	if task_status != "success":
		var fail_lines: Array[String] = log_lines.duplicate()
		fail_lines.append("[Error] 云端编译未成功（status=%s）%s" % [task_status, task_error])
		fail_lines.append("")
		# 尽力拉日志
		var log_resp: Dictionary = _http_request(
			HTTPClient.METHOD_GET, "/tasks/%s/log" % task_id, _auth_headers(), "")
		if log_resp.ok and log_resp.status == 200 and not log_resp.body_text.is_empty():
			fail_lines.append(log_resp.body_text)
		return _make_result(false, fail_lines, task_id, "", "")
	# 5) 下载 hex 到与本地编译相同的路径（供下载/OTA/导出复用）
	var hex_abs: String = ProjectSettings.globalize_path(_toolchain.get_hex_path(project_dst))
	DirAccess.make_dir_recursive_absolute(hex_abs.get_base_dir())
	var hex_resp: Dictionary = _http_request(
		HTTPClient.METHOD_GET, "/tasks/%s/hex" % task_id, _auth_headers(), "")
	if not hex_resp.ok or hex_resp.status != 200:
		return _make_result(false, log_lines + ["[Error] hex 下载失败（HTTP %d）" % hex_resp.get("status", 0)], task_id, "", "")
	var f: FileAccess = FileAccess.open(hex_abs, FileAccess.WRITE)
	if f == null:
		return _make_result(false, log_lines + ["[Error] 无法写入 hex：%s" % hex_abs], task_id, "", "")
	f.store_buffer(hex_resp.body_bytes)
	f.close()
	# 6) 拉编译日志（成功日志）
	var success_log: String = ""
	var slog: Dictionary = _http_request(
		HTTPClient.METHOD_GET, "/tasks/%s/log" % task_id, _auth_headers(), "")
	if slog.ok and slog.status == 200:
		success_log = slog.body_text
	var ok_lines: Array[String] = log_lines.duplicate()
	ok_lines.append("✓ 云端编译成功，hex 已保存")
	ok_lines.append("")
	if not success_log.is_empty():
		for line in success_log.split("\n", false):
			ok_lines.append(line)
	return _make_result(true, ok_lines, task_id, hex_abs, str(hex_resp.body_bytes.size()))


func _make_result(ok: bool, log_lines: Array, task_id: String, hex_path: String, hex_size: String) -> Dictionary:
	return {
		"ok": ok,
		"log": "\n".join(log_lines),
		"task_id": task_id,
		"hex": hex_path,
		"hex_size": hex_size,
		"hex_exists": ok and not hex_path.is_empty() and FileAccess.file_exists(hex_path),
	}


func _on_worker_finished(result: Dictionary) -> void:
	_join_thread()
	_set_busy(false)
	var log_text: String = str(result.get("log", ""))
	if not log_text.is_empty():
		for line in log_text.split("\n", false):
			_emit(line)
	if bool(result.get("ok", false)):
		_emit("✓ 云端编译成功（hex: %s）" % result.get("hex", ""))
	finished.emit(result)


# ------------------------------------------------------------------ 打包
## 把 user:// 部署好的工程 + Libraries 打成自包含 zip。
## zip 内结构：Projects/ROBOMASTER_<kind>/... 与 Libraries/...（与 keil_server 一致）。
func _pack_project_zip(project_dst: String, abs_zip: String) -> bool:
	var packer := ZIPPacker.new()
	if packer.open(abs_zip) != OK:
		return false
	var ok: bool = true
	var proj_abs: String = ProjectSettings.globalize_path(project_dst)
	var arc_base: String = "Projects/" + project_dst.get_file()
	ok = ok and _zip_dir(packer, proj_abs, arc_base)
	var libs_abs: String = ProjectSettings.globalize_path(_toolchain.LIBRARIES_DST)
	ok = ok and _zip_dir(packer, libs_abs, "Libraries")
	packer.close()
	return ok


## 递归把 abs_dir 下文件写入 zip（arc_prefix 为 zip 内路径前缀）。
## 跳过点开头文件与编译产物目录（Objects / Listings）。
func _zip_dir(packer: ZIPPacker, abs_dir: String, arc_prefix: String) -> bool:
	var da := DirAccess.open(abs_dir)
	if da == null:
		return false
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = da.get_next()
			continue
		var abs_item: String = abs_dir.path_join(entry)
		var arc_item: String = arc_prefix + "/" + entry
		if da.current_is_dir():
			if entry == "Objects" or entry == "Listings":
				entry = da.get_next()
				continue
			if not _zip_dir(packer, abs_item, arc_item):
				da.list_dir_end()
				return false
		else:
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(abs_item)
			if packer.start_file(arc_item) != OK:
				da.list_dir_end()
				return false
			packer.write_file(bytes)
		entry = da.get_next()
	da.list_dir_end()
	return true


# ------------------------------------------------------------------ HTTP（线程内同步）
func _auth_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer %s" % _api_key])


func _json_headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % _api_key,
		"Content-Type: application/json",
	])


## zip 文件转 base64 JSON body（Godot HTTPClient 的 request body 是 String，不能直接发二进制）。
func _zip_base64_json_body(abs_zip: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(abs_zip)
	var b64: String = Marshalls.raw_to_base64(bytes)
	return JSON.stringify({"zip_base64": b64})


## 同步 HTTP 请求（线程内）。返回 {ok, status, body_text, body_bytes, error}。
func _http_request(method: HTTPClient.Method, path_query: String, headers: PackedStringArray, body: String) -> Dictionary:
	var full_url: String = _base_url + path_query
	var client := HTTPClient.new()
	var err := _http_connect(client, full_url)
	if err != OK:
		return {"ok": false, "status": 0, "body_text": "", "body_bytes": PackedByteArray(),
			"error": "无法连接 %s（%s）" % [full_url, error_string(err)]}
	err = client.request(method, full_url, headers, body)
	if err != OK:
		client.close()
		return {"ok": false, "status": 0, "body_text": "", "body_bytes": PackedByteArray(),
			"error": "请求失败: %s" % error_string(err)}
	# 阶段一：等待响应头（REQUESTING -> BODY）
	var deadline: int = Time.get_ticks_msec() + HTTP_TIMEOUT_MS
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			client.close()
			return {"ok": false, "status": 0, "body_text": "", "body_bytes": PackedByteArray(),
				"error": "请求超时（%s）" % full_url}
		OS.delay_msec(5)
	var status: int = client.get_response_code()
	# 阶段二：读取响应体（BODY），并持续 poll
	var body_bytes := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk: PackedByteArray = client.read_response_body_chunk()
		if chunk.is_empty():
			OS.delay_msec(5)
			continue
		body_bytes.append_array(chunk)
	client.close()
	return {"ok": true, "status": status, "body_text": body_bytes.get_string_from_utf8(),
		"body_bytes": body_bytes, "error": ""}


## 连接 host 并等待 TCP/TLS 握手完成（同步阻塞）。
func _http_connect(client: HTTPClient, url: String) -> Error:
	var host: String = ""
	var port: int = 80
	var use_tls: bool = false
	var u: String = url.trim_suffix("/")
	if u.begins_with("https://"):
		use_tls = true
		u = u.trim_prefix("https://")
		port = 443
	elif u.begins_with("http://"):
		u = u.trim_prefix("http://")
		port = 80
	else:
		return ERR_INVALID_PARAMETER
	var slash := u.find("/")
	if slash >= 0:
		host = u.substr(0, slash)
	else:
		host = u
	var colon := host.find(":")
	if colon >= 0:
		var p: int = int(host.substr(colon + 1))
		if p > 0:
			port = p
		host = host.substr(0, colon)
	if host.is_empty():
		return ERR_INVALID_PARAMETER
	var err: Error
	if use_tls:
		err = client.connect_to_host(host, port, TLSOptions.client())
	else:
		err = client.connect_to_host(host, port)
	if err != OK:
		return err
	# 等待 TCP/TLS 握手完成（poll 直到脱离 CONNECTING/RESOLVING）
	var deadline: int = Time.get_ticks_msec() + HTTP_TIMEOUT_MS
	while client.get_status() == HTTPClient.STATUS_CONNECTING \
			or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			client.close()
			return ERR_TIMEOUT
		OS.delay_msec(5)
	if client.get_status() == HTTPClient.STATUS_DISCONNECTED \
			or client.get_status() == HTTPClient.STATUS_CONNECTION_ERROR \
			or client.get_status() == HTTPClient.STATUS_CANT_CONNECT \
			or client.get_status() == HTTPClient.STATUS_CANT_RESOLVE:
		client.close()
		return FAILED
	return OK


func _path_only(url: String) -> String:
	var u: String = url
	if u.begins_with("https://"):
		u = u.trim_prefix("https://")
	elif u.begins_with("http://"):
		u = u.trim_prefix("http://")
	var slash := u.find("/")
	if slash < 0:
		return "/"
	var path := u.substr(slash)
	return path if path != "" else "/"


## 从 JSON 字符串取字段（尽力解析，取不到返回默认值）。
func _json_get(text: String, key: String, default: String) -> String:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return default
	return str(parsed.get(key, default))
