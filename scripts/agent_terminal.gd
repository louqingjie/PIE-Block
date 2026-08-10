class_name AgentTerminal
extends Node

## 在程序内嵌入真实终端，跑 AI Agent 的 TUI。
##
## 架构：Godot 没有 PTY 能力，无法自行渲染 TUI（alternate screen / 光标定位 /
## 真彩 ANSI）。解法是用 `ttyd` —— 它把 PTY 和终端模拟都放到浏览器侧
## （前端 xterm.js），我们只用 WRY 的 WebView 节点提供网页容器。
##
## 为什么不用 `opencode web` 的 Web UI（实测放弃）：
##   1. 「新建会话」按钮在项目列表为空时静默失效
##      （upstream #37606 / #38411，修复 PR #37607 未合并）
##   2. 更致命：UI 会在工作区路径后拼接一段随机内存垃圾当子目录，
##      导致服务端 `realPath` ENOENT、`prompt_async` 整个失败。
##      该垃圾每次不同，清 localStorage 也会重新产生，我们无法在外部规避。
##   3. Windows 上项目目录选择器不可用（`/find/file` 空查询返回 0 条）
## TUI 走完全不同的代码路径，以上问题一个都不存在。
##
## ttyd 相比 `opencode serve` 的优势：
##   - `-w <dir>` 直接设工作目录，不必为 Godot 无法设 cwd 而套 cmd 包装
##     （连带避开了 `set VAR=value &&` 把空格并入变量值的坑）
##   - `-o` / `-q` 让进程生命周期自管理

# ------------------------------------------------------------------ 信号
## 终端服务就绪，携带可直接 load_url 的地址
signal ready_changed(is_ready: bool, url: String)
## 状态文本变化（供 UI 显示）
signal status_changed(text: String)
## 日志行（接到 Output 框）
signal log_line(text: String)

# ------------------------------------------------------------------ 常量
## ttyd 二进制（随项目分发，MIT 许可）
const TTYD_SRC: String = "res://tools/ttyd/ttyd.exe"
## 导出后 res:// 在 PCK 内不可执行，需先复制到 user://
const TTYD_DST: String = "user://tools/ttyd.exe"
## 就绪探测轮询间隔与上限（ttyd 本身启动很快，Agent 冷启动才是瓶颈）
const READY_POLL_INTERVAL: float = 0.4
const READY_POLL_MAX: int = 40
## 首次进入 AI 编辑时自动安装 opencode：轮询间隔与上限。
## 上限要覆盖「先静默安装包管理器再装 opencode」的两段式流程
const INSTALL_POLL_INTERVAL: float = 2.0
const INSTALL_POLL_MAX: int = 300 # 约 10 分钟
## npm 安装输出重定向到该日志（user://），供轮询取进度/排错
const INSTALL_LOG_NAME: String = "opencode_install.log"
## 传给 xterm.js 前端的选项
const TERM_FONT_SIZE: int = 14

# ------------------------------------------------------------------ 状态
var _ttyd_path: String = ""
var _agent_path: String = ""
var _port: int = 0
var _pid: int = -1
var _is_ready: bool = false
var _tries: int = 0
var _timer: Timer = null
## AI 工作区（user:// 虚拟路径），start() 记录、装完 opencode 后继续用
var _workspace: String = ""
## opencode 自动安装状态
var _installing: bool = false
var _install_pid: int = -1
var _install_tries: int = 0
var _install_log_path: String = ""
var _install_timer: Timer = null
## 安装方式队列（依次尝试，失败自动回退到下一种）
var _install_methods: Array = []
var _install_idx: int = -1


func _ready() -> void:
	_ensure_nodes()


## 惰性创建子节点：本类可能在场景树就绪前被实例化并调用
## （例如 headless 测试脚本），那种情况下 _ready 未必已执行。
func _ensure_nodes() -> void:
	if _timer == null:
		_timer = Timer.new()
		_timer.wait_time = READY_POLL_INTERVAL
		_timer.one_shot = true
		add_child(_timer)
		_timer.timeout.connect(_poll_ready)
	if _install_timer == null:
		_install_timer = Timer.new()
		_install_timer.wait_time = INSTALL_POLL_INTERVAL
		_install_timer.one_shot = true
		add_child(_install_timer)
		_install_timer.timeout.connect(_poll_install)


func _exit_tree() -> void:
	stop()

# 注：NOTIFICATION_WM_CLOSE_REQUEST 只发给主窗口根节点，不会传到子节点，
# 因此这里监听不到。窗口关闭的清理由场景根节点负责（见 code_edit.gd）。


# ------------------------------------------------------------------ 依赖检查
## 检查 Windows 上的 WebView2 Runtime。WRY 用系统原生 webview，
## 缺少 Runtime 时会静默失败（上游明确说明不做依赖检查）。
## 返回版本号；未安装返回空串。非 Windows 返回 "n/a"。
static func webview2_version() -> String:
	if OS.get_name() != "Windows":
		return "n/a"
	const GUID: String = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
	var keys: Array = [
		"HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\" + GUID,
		"HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\" + GUID,
	]
	for k in keys:
		var out: Array = []
		var code: int = OS.execute("reg.exe", ["query", k, "/v", "pv"], out, false)
		if code == 0 and out.size() > 0:
			for raw in str(out[0]).split("\n", false):
				var line: String = raw.strip_edges()
				if line.begins_with("pv"):
					var parts: PackedStringArray = line.split(" ", false)
					if parts.size() > 0:
						return parts[parts.size() - 1].strip_edges()
	return ""


# ------------------------------------------------------------------ 探测
## 定位 AI Agent 可执行文件。
## 各安装方式产生的路径各不相同，按固定位置逐一检查：
##   npm 全局  -> %APPDATA%\npm\node_modules\opencode-ai\bin\opencode.exe
##   Scoop     -> %USERPROFILE%\scoop\apps\opencode\current\opencode.exe
##   Mise      -> %USERPROFILE%\.local\bin\opencode.exe
##   Chocolatey-> C:\ProgramData\chocolatey\bin\opencode.exe
## 找不到再退回 where.exe 扫 PATH（shim 可能在进程启动后才加入 PATH，
## 而本进程的 PATH 是启动时的快照，因此固定路径检查必须优先）。
## 找不到返回空串。
func detect_agent() -> String:
	var appdata: String = OS.get_environment("APPDATA")
	var userprofile: String = OS.get_environment("USERPROFILE")
	var candidates: PackedStringArray = PackedStringArray()
	if not appdata.is_empty():
		candidates.append(appdata.replace("\\", "/").path_join(
			"npm/node_modules/opencode-ai/bin/opencode.exe"))
	if not userprofile.is_empty():
		candidates.append(userprofile.replace("\\", "/").path_join(
			"scoop/apps/opencode/current/opencode.exe"))
		candidates.append(userprofile.replace("\\", "/").path_join(
			".local/bin/opencode.exe"))
	candidates.append("C:/ProgramData/chocolatey/bin/opencode.exe")
	for c in candidates:
		if FileAccess.file_exists(c):
			_agent_path = c
			return _agent_path
	# 回退：where.exe 查 PATH，优先 .exe
	var out: Array = []
	var code: int = OS.execute("where.exe", ["opencode"], out, false)
	if code == 0 and out.size() > 0:
		var cmd_fallback: String = ""
		for raw in str(out[0]).split("\n", false):
			var line: String = raw.strip_edges()
			if line.is_empty():
				continue
			if line.to_lower().ends_with(".exe"):
				_agent_path = line.replace("\\", "/")
				return _agent_path
			if line.to_lower().ends_with(".cmd") and cmd_fallback.is_empty():
				cmd_fallback = line.replace("\\", "/")
		if not cmd_fallback.is_empty():
			_agent_path = cmd_fallback
			return _agent_path
	return ""


## 定位 npm 可执行文件（Windows 上是 npm.cmd，CreateProcess 起不了 .ps1/无扩展名 shim）。
## 找不到返回空串。
func _find_npm() -> String:
	var appdata: String = OS.get_environment("APPDATA")
	if not appdata.is_empty():
		var npm_cmd: String = appdata.replace("\\", "/").path_join("npm/npm.cmd")
		if FileAccess.file_exists(npm_cmd):
			return npm_cmd
	var out: Array = []
	var code: int = OS.execute("where.exe", ["npm"], out, false)
	if code == 0 and out.size() > 0:
		for raw in str(out[0]).split("\n", false):
			var line: String = raw.strip_edges()
			if line.is_empty():
				continue
			if line.to_lower().ends_with(".cmd") or line.to_lower().ends_with(".exe"):
				return line.replace("\\", "/")
	return ""


## 把 ttyd 从 res:// 部署到 user://（PCK 内的文件不能直接执行）。
## 返回可执行文件的绝对路径；失败返回空串。
func _deploy_ttyd() -> String:
	var dst_abs: String = ProjectSettings.globalize_path(TTYD_DST)
	if FileAccess.file_exists(dst_abs):
		return dst_abs
	var src_abs: String = ProjectSettings.globalize_path(TTYD_SRC)
	if not FileAccess.file_exists(src_abs):
		_emit_log("[Error] 缺少 ttyd 二进制: %s" % TTYD_SRC)
		return ""
	var dir: String = dst_abs.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			_emit_log("[Error] 无法创建目录: %s" % dir)
			return ""
	var src: FileAccess = FileAccess.open(src_abs, FileAccess.READ)
	if src == null:
		_emit_log("[Error] 无法读取 ttyd 二进制")
		return ""
	var dst: FileAccess = FileAccess.open(dst_abs, FileAccess.WRITE)
	if dst == null:
		src.close()
		_emit_log("[Error] 无法写入 ttyd 到 user://")
		return ""
	dst.store_buffer(src.get_buffer(src.get_length()))
	src.close()
	dst.close()
	return dst_abs


# ------------------------------------------------------------------ 端口
## 让操作系统分配空闲端口：绑 0 号端口取到真实端口后立即释放。
## 存在极小竞态窗口（释放到 ttyd 绑定之间），实践中可接受。
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
## opencode.json 已存在则保留（用户可能改过模型等设置）。
func ensure_workspace(workspace: String) -> bool:
	var ws_abs: String = ProjectSettings.globalize_path(workspace)
	if not DirAccess.dir_exists_absolute(ws_abs):
		if DirAccess.make_dir_recursive_absolute(ws_abs) != OK:
			_emit_log("[Error] 无法创建 AI 工作区目录: %s" % ws_abs)
			return false
	# AGENTS.md：硬件约束。不写 AI 必然产出编译不过的代码
	var agents_abs: String = ProjectSettings.globalize_path(
		"res://assets/templates/AGENTS_hardware.md")
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
		var cf: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
		if cf:
			cf.store_string(JSON.stringify({
				"$schema": "https://opencode.ai/config.json",
				"permission": {"edit": "allow", "bash": "allow", "webfetch": "allow"},
			}, "  "))
			cf.close()
	_ensure_git_repo(ws_abs)
	return true


## 把工作区初始化成 git 仓库。
## opencode 用 VCS 根判定「项目」，非 git 目录会被归到兜底项目里，
## 底栏不显示分支且部分功能受限。顺带写 .gitignore 排除编译产物，
## 避免 AI 的 diff 视图被 obj/lst 噪音淹没。
func _ensure_git_repo(ws_abs: String) -> void:
	if DirAccess.dir_exists_absolute(ws_abs.path_join(".git")):
		return
	var gitignore: String = ws_abs.path_join(".gitignore")
	if not FileAccess.file_exists(gitignore):
		var gi: FileAccess = FileAccess.open(gitignore, FileAccess.WRITE)
		if gi:
			gi.store_string("# Keil 编译产物\nObjects/\nListings/\n*.lst\n*.map\n*.obj\n*.o\n*.hex\n*.bin\n*.plg\n*.uvgui.*\n*.dep\n*.build_log.htm\npie_block_build.log\n")
			gi.close()
	# OS.execute 不能设工作目录，故用 cmd 包一层 cd
	var out: Array = []
	var inner: String = 'cd /d "%s" && git init -q' % ws_abs.replace("/", "\\")
	if OS.execute("cmd.exe", ["/c", inner], out, true) == 0:
		_emit_log("已将 AI 工作区初始化为 git 仓库")
	else:
		_emit_log("[Warn] git init 失败（AI 仍可用，但看不到分支/diff）")


# ------------------------------------------------------------------ 启动
## 启动 ttyd 并在其中运行 Agent 的 TUI。workspace 为 user:// 虚拟路径。
## 返回 true 仅表示进程已拉起；就绪状态通过 ready_changed 通知。
func start(workspace: String) -> bool:
	_ensure_nodes()
	_workspace = workspace
	if _pid != -1:
		return true # 已在运行
	if webview2_version().is_empty():
		_set_status("缺少 WebView2")
		_emit_log("[Error] 未检测到 WebView2 Runtime，终端面板无法显示")
		_emit_log("       请安装 Microsoft Edge WebView2 Runtime 后重启本程序")
		return false
	if _agent_path.is_empty() and detect_agent().is_empty():
		# 首次进入 AI 编辑：自动安装 opencode（异步，装好后经 _continue_start 继续）
		return _begin_opencode_install()
	return _continue_start()


## opencode 已就绪时的启动后半段：部署 ttyd -> 写工作区 -> 起 ttyd 跑 Agent TUI。
func _continue_start() -> bool:
	if _pid != -1:
		return true # 已在运行
	_ttyd_path = _deploy_ttyd()
	if _ttyd_path.is_empty():
		_set_status("终端组件缺失")
		return false
	if not ensure_workspace(_workspace):
		return false
	_port = _pick_port()
	if _port == 0:
		_emit_log("[Error] 无法分配本地端口")
		return false

	var ws_win: String = ProjectSettings.globalize_path(_workspace).replace("/", "\\")
	var args: PackedStringArray = PackedStringArray([
		"-p", str(_port),
		"-i", "127.0.0.1",      # 只绑回环，不对外暴露
		"-W",                    # 允许写入（默认只读，不加无法输入）
		"-w", ws_win,            # 工作目录 —— ttyd 原生支持，无需 cmd 包装
		"-m", "1",               # 最多一个客户端
		"-q",                    # 客户端全部断开即退出，避免孤儿进程
		"-t", "fontSize=%d" % TERM_FONT_SIZE,
		"-t", "disableLeaveAlert=true",
		_agent_path.replace("/", "\\"),
	])
	_pid = OS.create_process(_ttyd_path.replace("/", "\\"), args, false)
	if _pid == -1:
		_emit_log("[Error] 无法启动终端服务")
		return false
	_emit_log("正在启动 AI 终端（端口 %d）…" % _port)
	_set_status("正在启动…")
	_tries = 0
	_start_poll()
	return true


# ------------------------------------------------------------------ opencode 自动安装
## 未检测到 opencode 时按顺序尝试多种安装方式，装好后自动继续启动终端。
## 依次尝试：Chocolatey -> Scoop -> Mise -> npm。
## 前置不满足（如 choco 需要管理员）或安装失败（进程退出但 opencode 未出现）
## 时自动回退到下一种，全部失败才报错。
## 返回 false 表示连安装都无法开始（队列为空）。
func _begin_opencode_install() -> bool:
	if _installing:
		return true # 已在装
	_install_methods = _build_install_methods()
	if _install_methods.is_empty():
		_set_status("缺少可用的安装方式")
		_emit_log("[Error] 未找到任何可用的 opencode 安装方式")
		_emit_log("       请检查网络后重启本程序，或参考 https://opencode.ai/docs/")
		return false
	_installing = true
	_install_idx = -1
	_install_tries = 0
	_set_status("首次使用：正在安装 opencode（需联网，约 1~5 分钟）…")
	_emit_log("[Info] 首次使用 AI 编辑，未检测到 opencode，开始自动安装…")
	return _next_install_method()


## 构建安装方式队列（按优先级排序）。
## 静态前置在这里检查：不满足的直接不进队列（跳过而非失败）。
## 注意：powershell 的安装命令一律写成临时 .ps1 用 -File 执行。
## 不能拼在 -Command 里 —— Windows 命令行解析会剥掉内层双引号
## （实测 `& "$env:USERPROFILE\..."` 会变成无引号版本导致命令找不到）。
func _build_install_methods() -> Array:
	var methods: Array = []
	var out: Array = []
	# 1. Chocolatey：需要已安装且当前进程有管理员权限（choco 必须装到 ProgramData）
	var is_admin: bool = OS.execute("net.exe", ["session"], out, false) == 0
	if is_admin and _command_exists("choco"):
		methods.append(_make_install_method("Chocolatey", "cmd.exe",
			['/c', '"choco" install opencode -y']))
	# 2. Scoop：未装则先静默安装本体（免管理员），同一脚本里再装 opencode。
	#    scoop 安装脚本会检测已装则跳过，因此该脚本幂等。
	if _command_exists("scoop"):
		methods.append(_make_install_method("Scoop", "cmd.exe",
			['/c', '"scoop" install opencode']))
	else:
		var scoop_ps1: String = _write_install_script("scoop", [
			"$ProgressPreference = 'SilentlyContinue'",
			"Start-Transcript -Path '%s' -Force" % _install_log_win(),
			"Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force",
			"irm get.scoop.sh -TimeoutSec 60 | iex",
			'& "$env:USERPROFILE\\scoop\\shims\\scoop.cmd" install opencode',
			"Stop-Transcript",
		])
		if not scoop_ps1.is_empty():
			methods.append(_make_install_method("Scoop(自动安装)", "powershell.exe",
				["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scoop_ps1]))
	# 3. Mise：同上，未装则先静默安装本体（免管理员）
	if _command_exists("mise"):
		methods.append(_make_install_method("Mise", "cmd.exe",
			['/c', '"mise" use -g github:anomalyco/opencode']))
	else:
		var mise_ps1: String = _write_install_script("mise", [
			"$ProgressPreference = 'SilentlyContinue'",
			"Start-Transcript -Path '%s' -Force" % _install_log_win(),
			"iwr https://mise.run -TimeoutSec 60 | iex",
			'& "$env:USERPROFILE\\.local\\bin\\mise.exe" use -g github:anomalyco/opencode',
			"Stop-Transcript",
		])
		if not mise_ps1.is_empty():
			methods.append(_make_install_method("Mise(自动安装)", "powershell.exe",
				["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", mise_ps1]))
	# 4. npm：机器已装 Node.js 时的最后兜底。
	#    用 npmmirror 镜像（国内直连官方源经常超时）
	var npm_path: String = _find_npm()
	if not npm_path.is_empty():
		methods.append(_make_install_method("npm", "cmd.exe",
			['/c', '"%s" i -g opencode-ai --registry=https://registry.npmmirror.com' % npm_path.replace("/", "\\")]))
	return methods


## 把安装脚本写成 user://install_<name>.ps1（UTF-8 带 BOM，兼容中文路径）。
## 脚本内部用 Start-Transcript 把全部输出（含错误）写进安装日志。
## 返回绝对路径；失败返回空串。
func _write_install_script(name: String, lines: Array) -> String:
	var dst_abs: String = ProjectSettings.globalize_path("user://install_" + name + ".ps1")
	var f: FileAccess = FileAccess.open(dst_abs, FileAccess.WRITE)
	if f == null:
		_emit_log("[Error] 无法写入安装脚本: %s" % dst_abs)
		return ""
	f.store_8(0xEF); f.store_8(0xBB); f.store_8(0xBF) # UTF-8 BOM，PS 5.1 必须
	f.store_string("\n".join(PackedStringArray(lines)) + "\n")
	f.close()
	return dst_abs.replace("/", "\\")


## 安装日志的 Windows 绝对路径（脚本内容里用）
func _install_log_win() -> String:
	return ProjectSettings.globalize_path("user://" + INSTALL_LOG_NAME).replace("/", "\\")


## 组装单个安装方法：{name, exec, args}。
## cmd.exe 方法的输出重定向在 _next_install_method 里追加；
## powershell.exe 方法走 -File 脚本，日志由脚本内 Start-Transcript 负责。
func _make_install_method(name: String, exec: String, args: Array) -> Dictionary:
	return {"name": name, "exec": exec, "args": PackedStringArray(args)}


## 启动下一种安装方式；队列用尽返回 false。
func _next_install_method() -> bool:
	_install_tries = 0
	_install_idx += 1
	if _install_idx >= _install_methods.size():
		return false
	var m: Dictionary = _install_methods[_install_idx]
	var log_abs: String = ProjectSettings.globalize_path("user://" + INSTALL_LOG_NAME)
	_install_log_path = log_abs
	var log_win: String = log_abs.replace("/", "\\")
	var args: PackedStringArray = PackedStringArray(m["args"])
	# cmd 包装的安装命令追加进程级输出重定向；
	# powershell -File 的安装脚本已在内部 Start-Transcript，不需要这里重定向
	if str(m["exec"]) == "cmd.exe":
		args[args.size() - 1] = args[args.size() - 1] + ' > "%s" 2>&1' % log_win
	_emit_log("[Info] 正在尝试安装方式：%s…" % str(m["name"]))
	_install_pid = OS.create_process(str(m["exec"]), args, false)
	if _install_pid == -1:
		_emit_log("[Warn] %s 启动失败，改用下一种方式…" % str(m["name"]))
		_install_pid = -1
		return _next_install_method()
	_start_install_poll()
	return true


## 当前安装方式的名称（日志用）
func _current_install_method_name() -> String:
	if _install_idx < 0 or _install_idx >= _install_methods.size():
		return "未知"
	return str(_install_methods[_install_idx]["name"])


## 检查 PATH 中是否存在指定命令
func _command_exists(cmd: String) -> bool:
	var out: Array = []
	return OS.execute("where.exe", [cmd], out, false) == 0


func _start_install_poll() -> void:
	if _install_timer.is_inside_tree():
		_install_timer.start()
	else:
		_install_timer.tree_entered.connect(
			func() -> void: _install_timer.start(), CONNECT_ONE_SHOT)


func _poll_install() -> void:
	if not _installing or _install_pid == -1:
		return
	_install_tries += 1
	# 装好了：重新探测 opencode，成功则继续启动终端
	if not _agent_path.is_empty() or not detect_agent().is_empty():
		_installing = false
		_install_pid = -1
		_install_methods = []
		_emit_log("[✓] opencode 安装完成（%s）" % _current_install_method_name())
		_continue_start()
		return
	# 每 5 次轮询吐一条安装日志，让用户看到进度
	if _install_tries % 5 == 0:
		var tail: PackedStringArray = _read_install_log_tail(1)
		if tail.size() > 0:
			_emit_log("    " + tail[0])
	# 进程已退出但 opencode 还没出现 = 本方法失败，回退到下一种
	if not OS.is_process_running(_install_pid):
		_install_pid = -1
		_emit_log("[Warn] %s 安装失败，日志尾部：" % _current_install_method_name())
		for line: String in _read_install_log_tail(10):
			_emit_log("    " + line)
		if _next_install_method():
			_emit_log("[Info] 自动改用下一种方式…")
			return
		_installing = false
		_install_methods = []
		_set_status("opencode 安装失败")
		_emit_log("[Error] 所有安装方式均已尝试，仍未成功")
		_emit_log("       可检查网络后点「重启」重试，或手动参考 https://opencode.ai/docs/")
		return
	if _install_tries > INSTALL_POLL_MAX:
		_installing = false
		_set_status("opencode 安装超时")
		_emit_log("[Error] opencode 安装超时（可能还在下载），请检查网络后点「重启」重试")
		return
	_install_timer.start()


## 读取 npm 安装日志末尾最多 max_lines 行（去空行）。
func _read_install_log_tail(max_lines: int) -> PackedStringArray:
	if _install_log_path.is_empty() or not FileAccess.file_exists(_install_log_path):
		return PackedStringArray()
	var lines: PackedStringArray = FileAccess.get_file_as_string(_install_log_path).split("\n", false)
	var out: PackedStringArray = PackedStringArray()
	var from: int = maxi(0, lines.size() - max_lines)
	for i in range(from, lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty():
			out.append(line)
	return out


## Timer 只有在场景树内才计时。若此刻还没入树（刚 add_child 未生效），
## 先等入树信号再启动，否则轮询永不触发、进度会静默卡住。
func _start_poll() -> void:
	if _timer.is_inside_tree():
		_timer.start()
	else:
		_timer.tree_entered.connect(
			func() -> void: _timer.start(), CONNECT_ONE_SHOT)


## 探测端口是否已监听。ttyd 是纯 WebSocket + 静态页，
## 用 TCP 连通性判断比发 HTTP 请求更直接。
func _poll_ready() -> void:
	if _pid == -1:
		return
	_tries += 1
	var peer: StreamPeerTCP = StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", _port) == OK:
		peer.poll()
		var st: int = peer.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			_set_ready(true)
			_set_status("终端已就绪")
			_emit_log("AI 终端已就绪")
			return
		peer.disconnect_from_host()
	if _tries > READY_POLL_MAX:
		_emit_log("[Error] AI 终端启动超时")
		_set_status("启动失败")
		return
	_timer.start()


# ------------------------------------------------------------------ 关闭
## 终止终端服务。ttyd 会带着子进程（Agent）一起退出，
## 但用 taskkill /T 树杀更保险，避免留下孤儿 Agent 进程。
func stop() -> void:
	# 清理进行中的 opencode 安装（包管理器/cmd/powershell 进程）
	if _install_pid != -1:
		OS.execute("taskkill.exe", ["/T", "/F", "/PID", str(_install_pid)], [], false)
		_install_pid = -1
	_installing = false
	_install_methods = []
	_install_idx = -1
	if _install_timer and _install_timer.is_inside_tree():
		_install_timer.stop()
	if _pid == -1:
		return
	var out: Array = []
	OS.execute("taskkill.exe", ["/T", "/F", "/PID", str(_pid)], out, false)
	_pid = -1
	_port = 0
	_tries = READY_POLL_MAX + 1 # 让在途轮询立刻放弃
	if _timer and _timer.is_inside_tree():
		_timer.stop()
	_set_ready(false)


# ------------------------------------------------------------------ 查询
func is_ready() -> bool:
	return _is_ready


func port() -> int:
	return _port


func agent_path() -> String:
	return _agent_path


## 供 WebView.load_url() 使用的地址；未启动时返回空串
func terminal_url() -> String:
	if _port == 0:
		return ""
	return "http://127.0.0.1:%d/" % _port


# ------------------------------------------------------------------ 内部
func _set_ready(v: bool) -> void:
	if _is_ready == v:
		return
	_is_ready = v
	ready_changed.emit(v, terminal_url())


func _set_status(text: String) -> void:
	status_changed.emit(text)


func _emit_log(text: String) -> void:
	log_line.emit(text)
