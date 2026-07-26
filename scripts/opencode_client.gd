class_name OpenCodeClient
extends Node

## OpenCode 服务端进程管理 + HTTP 客户端。
##
## 架构说明：不内嵌 OpenCode 的 TUI —— Godot 没有 PTY 能力，无法渲染
## alternate screen / 光标定位 / 真彩 ANSI。改为启动 `opencode serve`
## （官方支持的无头 HTTP 服务端，IDE 插件和 Web 客户端都走它），
## 聊天界面用 Godot 原生控件绘制。
##
## Windows 上的两个硬约束：
##   1. `opencode serve` 没有 `--dir` 参数（只有 run/attach 有），
##      项目根靠继承 cwd 决定；
##   2. Godot 的 OS.create_process 既不能设工作目录也不能设环境变量。
## 两者相加 => 必须用 `cmd.exe /c cd /d <dir> && set VAR=x && opencode serve`
## 包一层。副作用是 OS.kill 只能杀掉 cmd，因此关闭时用 taskkill /T 树杀。

# ------------------------------------------------------------------ 信号
## 服务就绪，可以开始对话
signal ready_changed(is_ready: bool)
## 状态文本变化（供 UI 显示）
signal status_changed(text: String)
## 日志行（接到 Output 框）
signal log_line(text: String)
## 收到 AI 回复。parts 为响应中的 parts 数组
signal reply_received(parts: Array)
## 请求出错
signal request_failed(message: String)

# ------------------------------------------------------------------ 常量
## 健康检查轮询间隔与上限（opencode 冷启动实测约 5 秒）
const HEALTH_POLL_INTERVAL: float = 0.7
const HEALTH_POLL_MAX: int = 40
## 对话请求超时（秒）。AI 带工具调用时可能跑很久
const CHAT_TIMEOUT: float = 300.0
## Basic 认证的固定用户名（OPENCODE_SERVER_USERNAME 的默认值）
const AUTH_USER: String = "opencode"

# ------------------------------------------------------------------ 状态
var _exe_path: String = ""
var _port: int = 0
var _token: String = ""
var _pid: int = -1
var _session_id: String = ""
var _is_ready: bool = false
var _busy: bool = false
var _health_tries: int = 0

var _health_req: HTTPRequest = null
var _chat_req: HTTPRequest = null
var _health_timer: Timer = null


func _ready() -> void:
	_ensure_nodes()


## 惰性创建子节点。不在 _ready 里一次性建完，因为本类可能在
## 场景树就绪前就被实例化并调用（例如 headless 测试脚本），
## 那种情况下 _ready 未必已执行。
func _ensure_nodes() -> void:
	if _health_req != null:
		return
	_health_req = HTTPRequest.new()
	add_child(_health_req)
	_health_req.request_completed.connect(_on_health_completed)

	_chat_req = HTTPRequest.new()
	_chat_req.timeout = CHAT_TIMEOUT
	add_child(_chat_req)
	_chat_req.request_completed.connect(_on_chat_completed)

	_health_timer = Timer.new()
	_health_timer.wait_time = HEALTH_POLL_INTERVAL
	_health_timer.one_shot = true
	add_child(_health_timer)
	_health_timer.timeout.connect(_poll_health)


func _exit_tree() -> void:
	stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()


# ------------------------------------------------------------------ 探测
## 定位 opencode 可执行文件。
## Windows 上 npm 全局安装会生成三个入口：无扩展名的 shell shim、
## `.cmd`、`.ps1`。前两者 CreateProcess 起不来或需要 cmd 解释，
## 真正的原生 exe 藏在 node_modules 里，优先用它。
## 找不到返回空串。
func detect() -> String:
	# 1) 优先直接命中 npm 全局安装的原生 exe
	var appdata: String = OS.get_environment("APPDATA")
	if not appdata.is_empty():
		var npm_exe: String = appdata.replace("\\", "/").path_join(
			"npm/node_modules/opencode-ai/bin/opencode.exe")
		if FileAccess.file_exists(npm_exe):
			_exe_path = npm_exe
			return _exe_path
	# 2) 回退：where.exe 查 PATH，挑出 .exe 或 .cmd
	var out: Array = []
	var code: int = OS.execute("where.exe", ["opencode"], out, false)
	if code == 0 and out.size() > 0:
		var lines: PackedStringArray = str(out[0]).split("\n", false)
		var cmd_fallback: String = ""
		for raw in lines:
			var line: String = raw.strip_edges()
			if line.is_empty():
				continue
			if line.to_lower().ends_with(".exe"):
				_exe_path = line.replace("\\", "/")
				return _exe_path
			if line.to_lower().ends_with(".cmd") and cmd_fallback.is_empty():
				cmd_fallback = line.replace("\\", "/")
		if not cmd_fallback.is_empty():
			_exe_path = cmd_fallback
			return _exe_path
	return ""


# ------------------------------------------------------------------ 端口
## 让操作系统分配一个空闲端口：绑 0 号端口拿到真实端口后立即释放。
## 存在极小的竞态窗口（释放到 opencode 绑定之间），实践中可接受。
func _pick_port() -> int:
	var server: TCPServer = TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		return 0
	var port: int = server.get_local_port()
	server.stop()
	return port


# ------------------------------------------------------------------ 工作区
## 在工作区根写入 AGENTS.md 和 opencode.json。
## AGENTS.md 每次覆盖（模板可能随版本更新）；
## opencode.json 已存在则保留（用户可能手工改过模型等设置）。
func ensure_workspace(workspace: String) -> bool:
	var ws_abs: String = ProjectSettings.globalize_path(workspace)
	if not DirAccess.dir_exists_absolute(ws_abs):
		if DirAccess.make_dir_recursive_absolute(ws_abs) != OK:
			_emit_log("[Error] 无法创建 AI 工作区目录: %s" % ws_abs)
			return false
	# AGENTS.md：硬件约束，不写 AI 必然产出编译不过的代码
	var agents_src: String = "res://assets/templates/AGENTS_hardware.md"
	var agents_abs: String = ProjectSettings.globalize_path(agents_src)
	if FileAccess.file_exists(agents_abs):
		var content: String = FileAccess.get_file_as_string(agents_abs)
		var dst: FileAccess = FileAccess.open(
			ws_abs.path_join("AGENTS.md"), FileAccess.WRITE)
		if dst:
			dst.store_string(content)
			dst.close()
	else:
		_emit_log("[Warn] 未找到硬件约束模板，AI 可能产出无法编译的代码")
	# opencode.json：权限全放行（工作区已限制在 user:// 沙盒内）
	var cfg_path: String = ws_abs.path_join("opencode.json")
	if not FileAccess.file_exists(cfg_path):
		var cfg: Dictionary = {
			"$schema": "https://opencode.ai/config.json",
			"permission": {
				"edit": "allow",
				"bash": "allow",
				"webfetch": "allow",
			},
		}
		var cf: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
		if cf:
			cf.store_string(JSON.stringify(cfg, "  "))
			cf.close()
	return true


# ------------------------------------------------------------------ 启动
## 启动 opencode serve。workspace 为 user:// 虚拟路径。
## 成功返回 true（仅表示进程已拉起，就绪状态通过 ready_changed 通知）。
func start(workspace: String) -> bool:
	_ensure_nodes()
	if _pid != -1:
		return true # 已在运行
	if _exe_path.is_empty() and detect().is_empty():
		_set_status("未检测到 opencode，请先安装：npm i -g opencode-ai")
		_emit_log("[Error] 未找到 opencode 可执行文件")
		_emit_log("       安装后重启本程序即可。安装命令：npm i -g opencode-ai")
		return false
	if not ensure_workspace(workspace):
		return false
	_port = _pick_port()
	if _port == 0:
		_emit_log("[Error] 无法分配本地端口")
		return false
	# 随机 token 作为 Basic 认证密码。虽然只监听 127.0.0.1，
	# 但同机其他进程也能连，不做认证等于裸奔。
	_token = _make_token()

	var ws_abs: String = ProjectSettings.globalize_path(workspace).replace("/", "\\")
	var exe_win: String = _exe_path.replace("/", "\\")
	# cd /d 切盘符+目录；set 注入密码；&& 串联。
	# 关键：set 必须写成 set "VAR=value" 形式。
	# 若写 `set VAR=value && ...`，cmd 会把 && 前的空格并入变量值，
	# 服务端密码变成 "<token> " 而客户端算的是 "<token>"，导致每个请求都 401。
	var inner: String = 'cd /d "%s" && set "OPENCODE_SERVER_PASSWORD=%s" && "%s" serve --port %d --hostname 127.0.0.1' % [
		ws_abs, _token, exe_win, _port]
	_pid = OS.create_process("cmd.exe", ["/c", inner], false)
	if _pid == -1:
		_emit_log("[Error] 无法启动 opencode serve")
		return false
	_emit_log("正在启动 AI 服务（端口 %d）…" % _port)
	_set_status("正在启动 AI 服务…")
	_health_tries = 0
	_start_health_poll()
	return true


## 启动健康轮询。Timer 只有在场景树内才会计时，若此刻还没入树
## （例如刚 add_child 尚未生效），先等入树信号再启动，
## 否则轮询永不触发、进度会静默卡在“正在启动”。
func _start_health_poll() -> void:
	if _health_timer.is_inside_tree():
		_health_timer.start()
	else:
		_health_timer.tree_entered.connect(
			func() -> void: _health_timer.start(), CONNECT_ONE_SHOT)


func _make_token() -> String:
	var chars: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var s: String = ""
	for _i in range(24):
		s += chars[randi() % chars.length()]
	return s


# ------------------------------------------------------------------ 关闭
## 终止服务进程。
## cmd 包装导致 OS.kill 只能杀掉 cmd 本身，opencode 会变成孤儿，
## 因此用 taskkill /T 连整棵进程树一起杀。
func stop() -> void:
	if _pid == -1:
		return
	var out: Array = []
	OS.execute("taskkill.exe", ["/T", "/F", "/PID", str(_pid)], out, false)
	_pid = -1
	_session_id = ""
	_set_ready(false)


# ------------------------------------------------------------------ 健康检查
func _poll_health() -> void:
	if _pid == -1:
		return
	_health_tries += 1
	if _health_tries > HEALTH_POLL_MAX:
		_emit_log("[Error] AI 服务启动超时，请检查 opencode 是否可正常运行")
		_set_status("AI 服务启动失败")
		return
	var err: int = _health_req.request(
		_url("/global/health"), _headers(), HTTPClient.METHOD_GET)
	if err != OK:
		_health_timer.start()


func _on_health_completed(_result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if code == 200:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		var ver: String = ""
		if data is Dictionary:
			ver = str(data.get("version", ""))
		_emit_log("AI 服务已就绪（opencode %s）" % ver)
		_create_session()
		return
	# 401 说明服务已起来但认证不通过，再轮询也不会变好，直接报错止损
	if code == 401:
		_emit_log("[Error] AI 服务认证失败（401），无法连接")
		_set_status("认证失败")
		return
	# 未就绪或连接失败，继续轮询
	_health_timer.start()


# ------------------------------------------------------------------ 会话
func _create_session() -> void:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(_r: int, c: int, _h: PackedStringArray, b: PackedByteArray) -> void:
			if c == 200:
				var d: Variant = JSON.parse_string(b.get_string_from_utf8())
				if d is Dictionary:
					_session_id = str(d.get("id", ""))
			if _session_id.is_empty():
				_emit_log("[Error] 创建 AI 会话失败（HTTP %d）" % c)
				_set_status("会话创建失败")
			else:
				_set_ready(true)
				_set_status("AI 已就绪")
			req.queue_free()
	)
	var body: String = JSON.stringify({"title": "pie-block"})
	var err: int = req.request(
		_url("/session"), _headers(true), HTTPClient.METHOD_POST, body)
	if err != OK:
		_emit_log("[Error] 创建会话请求发送失败（错误码 %d）" % err)
		req.queue_free()


# ------------------------------------------------------------------ 对话
## 发送一条消息。第一期用同步请求（等完整响应），不做 SSE 流式。
## 返回 false 表示未发出（未就绪或正忙）。
func send_message(text: String) -> bool:
	if not _is_ready or _session_id.is_empty():
		_emit_log("[Warn] AI 服务尚未就绪")
		return false
	if _busy:
		_emit_log("[Warn] 上一条消息还在处理中")
		return false
	var body: String = JSON.stringify({
		"parts": [{"type": "text", "text": text}],
	})
	var err: int = _chat_req.request(
		_url("/session/%s/message" % _session_id),
		_headers(true), HTTPClient.METHOD_POST, body)
	if err != OK:
		request_failed.emit("请求发送失败（错误码 %d）" % err)
		return false
	_busy = true
	_set_status("AI 思考中…")
	return true


func _on_chat_completed(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_busy = false
	_set_status("AI 已就绪")
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("网络请求失败（result %d）" % result)
		return
	if code < 200 or code >= 300:
		request_failed.emit("AI 服务返回 HTTP %d：%s"
			% [code, body.get_string_from_utf8().left(300)])
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		request_failed.emit("无法解析 AI 响应")
		return
	var parts: Array = []
	var raw_parts: Variant = (data as Dictionary).get("parts", [])
	if raw_parts is Array:
		parts = raw_parts
	reply_received.emit(parts)


## 中断当前请求
func abort() -> void:
	if not _busy:
		return
	_chat_req.cancel_request()
	_busy = false
	_set_status("已中断")
	if not _session_id.is_empty():
		var req: HTTPRequest = HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(
			func(_r, _c, _h, _b) -> void: req.queue_free())
		req.request(_url("/session/%s/abort" % _session_id),
			_headers(true), HTTPClient.METHOD_POST, "{}")


# ------------------------------------------------------------------ 查询
func is_ready() -> bool:
	return _is_ready


func is_busy() -> bool:
	return _busy


func port() -> int:
	return _port


func exe_path() -> String:
	return _exe_path


# ------------------------------------------------------------------ 内部
func _url(path: String) -> String:
	return "http://127.0.0.1:%d%s" % [_port, path]


func _headers(with_json: bool = false) -> PackedStringArray:
	var auth: String = Marshalls.utf8_to_base64("%s:%s" % [AUTH_USER, _token])
	var h: PackedStringArray = PackedStringArray([
		"Authorization: Basic " + auth,
	])
	if with_json:
		h.append("Content-Type: application/json")
	return h


func _set_ready(v: bool) -> void:
	if _is_ready == v:
		return
	_is_ready = v
	ready_changed.emit(v)


func _set_status(text: String) -> void:
	status_changed.emit(text)


func _emit_log(text: String) -> void:
	log_line.emit(text)
