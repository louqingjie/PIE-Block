class_name AgentTerminal
extends Node

## 在程序内嵌入真实终端，跑 AI Agent 的 TUI。
##
## 架构：用 Godot 原生 TerminalControl（XTerm.NET + ConPTY）在进程内渲染
## opencode 的 TUI，不再依赖 ttyd + WRY WebView。
##   - TerminalControl 内置 VT 引擎（XTerm.NET）：alternate screen、
##     光标定位、真彩 ANSI 与键盘输入回传全部在 Godot 内完成
##   - ConPTY 由 Porta.Pty 提供，opencode 作为子进程直接跑在工作区目录
##   - 本类负责：部署 PIEBlock 内置的固定版 opencode、按构型准备 AI 工作区
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

const OPENCODE_RUNTIME = preload("res://scripts/opencode_runtime.gd")

# ------------------------------------------------------------------ 状态
## 原生终端控件（TerminalControl），由宿主场景注入
var terminal_control: Control = null
var _agent_path: String = ""
var _agent_version: String = ""
var _is_ready: bool = false
## AI 工作区（user:// 虚拟路径）
var _workspace: String = ""
## 当前构型（infantry / engineer / debug / music），用于生成构型专属的 AGENTS.md 与 .gitignore
var _kind: String = ""


func _exit_tree() -> void:
	stop()

# 注：NOTIFICATION_WM_CLOSE_REQUEST 只发给主窗口根节点，不会传到子节点，
# 因此这里监听不到。窗口关闭的清理由场景根节点负责（见 code_edit.gd）。


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
	# opencode.json：权限全放行（工作区已限制在 user:// 沙盒内），禁止运行时自更新。
	# 已有配置由用户维护，不在这里覆盖；启动时还会注入环境变量强制禁用更新检查。
	var cfg_path: String = ws_abs.path_join("opencode.json")
	if not FileAccess.file_exists(cfg_path):
		var cf: FileAccess = FileAccess.open(cfg_path, FileAccess.WRITE)
		if cf:
			cf.store_string(JSON.stringify({
				"$schema": "https://opencode.ai/config.json",
				"autoupdate": false,
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
		"music":
			return "音乐"
		_:
			return "步兵"


## 当前构型唯一可改的 main.c 路径（相对工作区根）
func _kind_main_c_path(kind: String) -> String:
	return "Projects/%s/USER/src/main.c" % _kind_project_dir(kind)


## 需要从 AI 视野隐藏的其他构型项目目录
func _kind_hidden_dirs(kind: String) -> Array:
	var current: String = _kind_project_dir(kind)
	var all: Array = ["ROBOMASTER_INFANTRY", "ROBOMASTER_ENGINEER"]
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
	_workspace = workspace
	_kind = kind
	if terminal_control != null and terminal_control.IsRunning:
		return true # 已在运行
	var runtime = OPENCODE_RUNTIME.new(_emit_log)
	var deployed: Dictionary = runtime.ensure_deployed()
	if not bool(deployed.get("ok", false)):
		_set_status("内置 OpenCode 不可用")
		_emit_log("[Error] %s" % str(deployed.get("reason", "OpenCode 运行时部署失败")))
		return false
	_agent_path = str(deployed.get("executable", ""))
	_agent_version = str(deployed.get("version", ""))
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
	var runtime_home := ProjectSettings.globalize_path("user://opencode")
	for directory in ["config", "data", "cache", "state"]:
		if DirAccess.make_dir_recursive_absolute(runtime_home.path_join(directory)) != OK:
			_set_status("OpenCode 数据目录不可用")
			_emit_log("[Error] 无法创建 OpenCode %s 目录，请检查磁盘空间" % directory)
			return false
	terminal_control.EnvironmentOverrides = {
		"OPENCODE_DISABLE_AUTOUPDATE": "true",
		"XDG_CONFIG_HOME": runtime_home.path_join("config"),
		"XDG_DATA_HOME": runtime_home.path_join("data"),
		"XDG_CACHE_HOME": runtime_home.path_join("cache"),
		"XDG_STATE_HOME": runtime_home.path_join("state"),
	}
	terminal_control.Columns = 120
	terminal_control.Rows = 40
	_emit_log("正在启动内置 OpenCode %s…" % _agent_version)
	_set_status("正在启动…")
	terminal_control.Start()
	if not terminal_control.IsRunning:
		_set_status("启动失败")
		_emit_log("[Error] 无法启动 opencode 终端")
		return false
	_set_ready(true)
	_set_status("OpenCode %s · 由 PIEBlock 管理" % _agent_version)
	_emit_log("AI 终端已就绪（OpenCode %s，自动更新已关闭）" % _agent_version)
	return true


# ------------------------------------------------------------------ 关闭
## 关闭终端：停止 TerminalControl（ConPTY 进程树一并终止）。
func stop() -> void:
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
