class_name AgentTerminal
extends Node

## 在程序内嵌入真实终端，跑 AI Agent 的 TUI。
##
## 架构：用 Godot 原生 TerminalControl（XTerm.NET + ConPTY）在进程内渲染
## opencode 的 TUI，不依赖浏览器容器或额外的原生扩展。
##   - TerminalControl 内置 VT 引擎（XTerm.NET）：alternate screen、
##     光标定位、真彩 ANSI 与键盘输入回传全部在 Godot 内完成
##   - ConPTY 由 Porta.Pty 提供，opencode 作为子进程直接跑在工作区目录
##   - 本类负责：探测/自动安装 opencode、按构型准备 AI 工作区
##     （AGENTS.md / .gitignore / git 仓库）、驱动 TerminalControl 启停
##
## 为什么不用 `opencode web` 的 Web UI（实测放弃）：
##   1. 「新建会话」按钮在项目列表为空时静默失效
##      （upstream #37606 / #38411，修复 PR #37607 未合并）
##   2. 更致命：UI 会在工作区路径后拼接一段随机内存垃圾当子目录，
##      导致服务端 `realPath` ENOENT、`prompt_async` 整个失败。
##      该垃圾每次不同，清 localStorage 也会重新产生，我们无法在外部规避。
##   3. Windows 上项目目录选择器不可用（`/find/file` 空查询返回 0 条）
## TUI 走完全不同的代码路径，以上问题一个都不存在。

# ------------------------------------------------------------------ 信号
## 终端就绪状态变化（TerminalControl 启动成功即视为就绪）
signal ready_changed(is_ready: bool)
## 状态文本变化（供 UI 显示）
signal status_changed(text: String)
## 日志行（接到 Output 框）
signal log_line(text: String)

# ------------------------------------------------------------------ 常量
## 首次进入 AI 编辑时自动安装 opencode：轮询间隔与上限。
## 上限要覆盖「先静默安装包管理器再装 opencode」的两段式流程
const INSTALL_POLL_INTERVAL: float = 2.0
const INSTALL_POLL_MAX: int = 300 # 约 10 分钟
## npm 安装输出重定向到该日志（user://），供轮询取进度/排错
const INSTALL_LOG_NAME: String = "opencode_install.log"

# ------------------------------------------------------------------ 状态
## 原生终端控件（TerminalControl），由宿主场景注入
var terminal_control: Control = null
var _agent_path: String = ""
var _is_ready: bool = false
## AI 工作区（user:// 虚拟路径），start() 记录、装完 opencode 后继续用
var _workspace: String = ""
## 当前构型（infantry / engineer / debug），用于生成构型专属的 AGENTS.md 与 .gitignore
var _kind: String = ""
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


# ------------------------------------------------------------------ 工作区
## 在工作区根写入 AGENTS.md 和 opencode.json。
## AGENTS.md 每次覆盖（模板可能随版本更新）；
## opencode.json 已存在则保留（用户可能改过模型等设置）。
func ensure_workspace(workspace: String, kind: String = "") -> bool:
	var ws_abs: String = ProjectSettings.globalize_path(workspace)
	if not DirAccess.dir_exists_absolute(ws_abs):
		if DirAccess.make_dir_recursive_absolute(ws_abs) != OK:
			_emit_log("[Error] 无法创建 AI 工作区目录: %s" % ws_abs)
			return false
	# AGENTS.md：硬件约束 + 当前构型。不写 AI 必然产出编译不过的代码；
	# 不指明构型则 AI 面对多个 main.c 不知道改哪个。
	var agents_abs: String = ProjectSettings.globalize_path(
		"res://assets/templates/AGENTS_hardware.md")
	if FileAccess.file_exists(agents_abs):
		var content: String = FileAccess.get_file_as_string(agents_abs)
		content = content.replace("{{KIND_LABEL}}", _kind_label(kind))
		content = content.replace("{{MAIN_C_PATH}}", _kind_main_c_path(kind))
		content = content.replace("{{FORBIDDEN_PROJECTS}}", _forbidden_section(kind))
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
	_ensure_git_repo(ws_abs, kind)
	return true


# ------------------------------------------------------------------ 构型映射
## 构型 -> 项目目录名（infantry / debug 共用步兵模板）
func _kind_project_dir(kind: String) -> String:
	if kind == "engineer":
		return "ROBOMASTER_ENGINEER"
	return "ROBOMASTER_INFANTRY"


## 构型 -> 中文名
func _kind_label(kind: String) -> String:
	match kind:
		"engineer":
			return "工程"
		"debug":
			return "调试"
		_:
			return "步兵"


## 当前构型唯一可改的 main.c 路径（相对工作区根）
func _kind_main_c_path(kind: String) -> String:
	return "Projects/%s/USER/src/main.c" % _kind_project_dir(kind)


## 需要从 AI 视野隐藏的其他构型项目目录
func _kind_hidden_dirs(kind: String) -> Array:
	var current: String = _kind_project_dir(kind)
	var all: Array = ["ROBOMASTER_INFANTRY", "ROBOMASTER_ENGINEER", "ROBOMASTER_ENGINEER_SIM"]
	var hidden: Array = []
	for d in all:
		if d != current:
			hidden.append(d)
	return hidden


## AGENTS.md 里「禁止修改的其他构型」段落
func _forbidden_section(kind: String) -> String:
	var hidden: Array = _kind_hidden_dirs(kind)
	if hidden.is_empty():
		return ""
	var lines: Array = ["**以下目录是其他机器人构型的代码，与本项目无关，绝对禁止修改：**"]
	for d in hidden:
		lines.append("- `Projects/%s/`" % d)
	lines.append("")
	return "\n".join(lines)


## 按当前构型生成 .gitignore：隐藏其他构型项目，避免 AI 的视野/搜索/diff 被干扰
func _gitignore_content(kind: String) -> String:
	var lines: Array = [
		"# Keil 编译产物",
		"Objects/",
		"Listings/",
		"*.lst",
		"*.map",
		"*.obj",
		"*.o",
		"*.hex",
		"*.bin",
		"*.plg",
		"*.uvgui.*",
		"*.dep",
		"*.build_log.htm",
		"pie_block_build.log",
		"",
		"# 其他构型的项目（当前构型：%s）—— 从 AI 视野中隐藏，禁止修改" % _kind_label(kind),
	]
	for d in _kind_hidden_dirs(kind):
		lines.append("Projects/%s/" % d)
	return "\n".join(lines) + "\n"


## 把工作区初始化成 git 仓库。
## opencode 用 VCS 根判定「项目」，非 git 目录会被归到兜底项目里，
## 底栏不显示分支且部分功能受限。顺带写 .gitignore 排除编译产物，
## 避免 AI 的 diff 视图被 obj/lst 噪音淹没。
func _ensure_git_repo(ws_abs: String, kind: String) -> void:
	# 每次按当前构型重写 .gitignore：构型切换后旧规则会残留，必须覆盖
	var gitignore: String = ws_abs.path_join(".gitignore")
	var gi: FileAccess = FileAccess.open(gitignore, FileAccess.WRITE)
	if gi:
		gi.store_string(_gitignore_content(kind))
		gi.close()
	if DirAccess.dir_exists_absolute(ws_abs.path_join(".git")):
		return
	# OS.execute 不能设工作目录，故用 cmd 包一层 cd
	var out: Array = []
	var inner: String = 'cd /d "%s" && git init -q' % ws_abs.replace("/", "\\")
	if OS.execute("cmd.exe", ["/c", inner], out, true) == 0:
		_emit_log("已将 AI 工作区初始化为 git 仓库")
	else:
		_emit_log("[Warn] git init 失败（AI 仍可用，但看不到分支/diff）")


# ------------------------------------------------------------------ 启动
## 启动原生终端并在其中运行 Agent 的 TUI。workspace 为 user:// 虚拟路径。
## 返回 true 仅表示已拉起；就绪状态通过 ready_changed 通知。
func start(workspace: String, kind: String = "") -> bool:
	_ensure_nodes()
	_workspace = workspace
	_kind = kind
	if terminal_control != null and terminal_control.IsRunning:
		return true # 已在运行
	if _agent_path.is_empty() and detect_agent().is_empty():
		# 首次进入 AI 编辑：自动安装 opencode（异步，装好后经 _continue_start 继续）
		return _begin_opencode_install()
	return _continue_start()


## opencode 已就绪时的启动后半段：准备工作区 -> 配置并启动 TerminalControl。
func _continue_start() -> bool:
	if terminal_control != null and terminal_control.IsRunning:
		return true # 已在运行
	if not ensure_workspace(_workspace, _kind):
		return false
	if terminal_control == null:
		_set_status("缺少终端控件")
		_emit_log("[Error] 缺少 TerminalControl 节点，AI 面板不可用")
		return false
	terminal_control.Command = _agent_path.replace("/", "\\")
	terminal_control.Arguments = []
	terminal_control.WorkingDirectory = ProjectSettings.globalize_path(_workspace)
	terminal_control.Columns = 120
	terminal_control.Rows = 40
	_emit_log("正在启动 AI 终端…")
	_set_status("正在启动…")
	terminal_control.Start()
	if not terminal_control.IsRunning:
		_set_status("启动失败")
		_emit_log("[Error] 无法启动 opencode 终端")
		return false
	_set_ready(true)
	_set_status("终端已就绪")
	_emit_log("AI 终端已就绪")
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


# ------------------------------------------------------------------ 关闭
## 关闭终端：停止 TerminalControl（ConPTY 进程树一并终止）。
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
	if terminal_control != null and terminal_control.IsRunning:
		terminal_control.Stop()
	_set_ready(false)


# ------------------------------------------------------------------ 查询
func is_ready() -> bool:
	return _is_ready


func agent_path() -> String:
	return _agent_path


# ------------------------------------------------------------------ 内部
func _set_ready(v: bool) -> void:
	if _is_ready == v:
		return
	_is_ready = v
	ready_changed.emit(v)


func _set_status(text: String) -> void:
	status_changed.emit(text)


func _emit_log(text: String) -> void:
	log_line.emit(text)
