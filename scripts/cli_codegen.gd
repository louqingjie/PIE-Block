extends SceneTree

## ====================================================================
## Pie-Block 代码生成器 CLI
## ====================================================================
## 在不启动 GUI 的情况下复用全部图形化代码生成器与静态检查器。
##
## 用法:
##   godot --headless --path <项目根> --script scripts/cli_codegen.gd -- <命令> [参数]
##
## 命令:
##   generate  --kind <infantry|engineer|debug> --config <json文件或-> [--out <文件>]
##   generate  --project <.pieproj文件> [--out <文件>]
##   check     --kind <infantry|engineer|debug> --config <json文件或->
##   check     --project <.pieproj文件>
##   build     --kind <infantry|engineer|debug> --config <json文件或->
##   build     --code <c文件>   （直接编译已有 C 代码，--kind 指定模板）
##   build     --project <.pieproj文件>
##   schema    --kind <infantry|engineer|debug>
##   profiles
##
## 所有命令均输出 JSON 到 stdout（generate 的 --out 除外，见下文）。
## 退出码: 0=成功 1=参数错误 2=生成/检查/编译失败 3=IO 错误
## ====================================================================

# headless 下 class_name 全局类名缓存可能未建立，用 preload
const CG_INFANTRY = preload("res://scripts/codegen/codegen_infantry.gd")
const CG_DEBUG = preload("res://scripts/codegen/codegen_debug.gd")
const CG_ENGINEER = preload("res://scripts/codegen/codegen_engineer.gd")
const SC = preload("res://scripts/static_checker.gd")
const PF = preload("res://scripts/project_file.gd")
const TC = preload("res://scripts/toolchain.gd")

# ---- 颜色码（纯文本终端用，不用 ANSI，方便脚本解析） ----
const TAG_OK := "[OK]"
const TAG_ERR := "[ERR]"
const TAG_WARN := "[WARN]"

# ---- 退出码 ----
const EXIT_OK := 0
const EXIT_ARG := 1
const EXIT_RUN := 2
const EXIT_IO := 3


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_print_usage_error()
		quit(EXIT_ARG)
		return
	var cmd: String = args[0]
	var rest: PackedStringArray = args.slice(1)
	match cmd:
		"generate":
			_cmd_generate(rest)
		"check":
			_cmd_check(rest)
		"build":
			_cmd_build(rest)
		"schema":
			_cmd_schema(rest)
		"profiles":
			_cmd_profiles(rest)
		"help", "--help", "-h":
			_print_usage()
			quit(EXIT_OK)
		_:
			_print_error("未知命令: %s" % cmd)
			_print_usage_error()
			quit(EXIT_ARG)


# ====================================================================
# generate
# ====================================================================
func _cmd_generate(args: PackedStringArray) -> void:
	var parsed: Dictionary = _parse_args(args, ["--kind", "--config", "--project", "--out"])
	if parsed.has("error"):
		_print_error(parsed["error"])
		quit(EXIT_ARG)
		return
	var out_path: String = parsed.get("--out", "")
	var kind: String = ""
	var cfg: Dictionary = {}
	var issues: Array = []

	if parsed.has("--project"):
		# 从 .pieproj 加载
		var proj_path: String = parsed["--project"]
		if proj_path.is_empty():
			_print_error("--project 需要指定文件路径")
			quit(EXIT_ARG)
			return
		var res: Dictionary = PF.load_from(proj_path)
		if not res["ok"]:
			_print_error("无法读取项目文件: %s" % res["err"])
			quit(EXIT_IO)
			return
		var data: Dictionary = res["data"]
		kind = data.get("kind", "infantry")
		cfg = _config_from_project(data, kind)
		# 顺便跑一次检查，让调用方知道有没有 Error
		issues = _run_check(kind, cfg)
	elif parsed.has("--config"):
		kind = parsed.get("--kind", "infantry")
		if not PF.is_valid_kind(kind):
			_print_error("未知项目类型: %s（合法值: infantry/engineer/debug）" % kind)
			quit(EXIT_ARG)
			return
		var config_text: String = _read_config_source(parsed["--config"])
		if config_text.is_empty() and parsed["--config"] != "-":
			_print_error("无法读取配置文件: %s" % parsed["--config"])
			quit(EXIT_IO)
			return
		cfg = _parse_config_json(config_text, kind)
		issues = _run_check(kind, cfg)
	else:
		_print_error("generate 需要 --config 或 --project")
		quit(EXIT_ARG)
		return

	# 检查是否有 Error，有则仍然生成代码但标记
	var has_error: bool = false
	for issue in issues:
		if str(issue.get("type", "")) == "Error":
			has_error = true
			break

	# 生成代码
	var code: String = _generate_code(kind, cfg)
	if code.is_empty():
		_print_error("代码生成失败")
		quit(EXIT_RUN)
		return

	if out_path.is_empty():
		# 输出 JSON 到 stdout
		var result: Dictionary = {
			"ok": true,
			"kind": kind,
			"code": code,
			"has_error": has_error,
			"issues": issues,
		}
		print(JSON.stringify(result, "\t"))
	else:
		# 写到文件，stdout 只输出简短结果
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			_print_error("无法写入输出文件: %s" % out_path)
			quit(EXIT_IO)
			return
		f.store_string(code)
		f.close()
		var result: Dictionary = {
			"ok": true,
			"kind": kind,
			"out": out_path,
			"has_error": has_error,
			"issues": issues,
		}
		print(JSON.stringify(result, "\t"))
	quit(EXIT_OK)


# ====================================================================
# check
# ====================================================================
func _cmd_check(args: PackedStringArray) -> void:
	var parsed: Dictionary = _parse_args(args, ["--kind", "--config", "--project"])
	if parsed.has("error"):
		_print_error(parsed["error"])
		quit(EXIT_ARG)
		return
	var kind: String = ""
	var cfg: Dictionary = {}
	if parsed.has("--project"):
		var proj_path: String = parsed["--project"]
		if proj_path.is_empty():
			_print_error("--project 需要指定文件路径")
			quit(EXIT_ARG)
			return
		var res: Dictionary = PF.load_from(proj_path)
		if not res["ok"]:
			_print_error("无法读取项目文件: %s" % res["err"])
			quit(EXIT_IO)
			return
		var data: Dictionary = res["data"]
		kind = data.get("kind", "infantry")
		cfg = _config_from_project(data, kind)
	elif parsed.has("--config"):
		kind = parsed.get("--kind", "infantry")
		if not PF.is_valid_kind(kind):
			_print_error("未知项目类型: %s" % kind)
			quit(EXIT_ARG)
			return
		var config_text: String = _read_config_source(parsed["--config"])
		cfg = _parse_config_json(config_text, kind)
	else:
		_print_error("check 需要 --config 或 --project")
		quit(EXIT_ARG)
		return

	var issues: Array = _run_check(kind, cfg)
	var has_error: bool = false
	var has_warn: bool = false
	for issue in issues:
		match str(issue.get("type", "")):
			"Error":
				has_error = true
			"Warn":
				has_warn = true
	var result: Dictionary = {
		"ok": not has_error,
		"kind": kind,
		"issues": issues,
		"error_count": issues.filter(func(i): return str(i.get("type", "")) == "Error").size(),
		"warn_count": issues.filter(func(i): return str(i.get("type", "")) == "Warn").size(),
	}
	print(JSON.stringify(result, "\t"))
	quit(EXIT_OK)


# ====================================================================
# schema -- 输出指定类型的配置 JSON Schema
# ====================================================================
func _cmd_schema(args: PackedStringArray) -> void:
	var parsed: Dictionary = _parse_args(args, ["--kind"])
	if parsed.has("error"):
		_print_error(parsed["error"])
		quit(EXIT_ARG)
		return
	var kind: String = parsed.get("--kind", "infantry")
	if not PF.is_valid_kind(kind):
		_print_error("未知项目类型: %s" % kind)
		quit(EXIT_ARG)
		return
	var schema: Dictionary = _build_schema(kind)
	print(JSON.stringify(schema, "\t"))
	quit(EXIT_OK)


# ====================================================================
# profiles -- 列出所有项目类型及其概要
# ====================================================================
func _cmd_profiles(_args: PackedStringArray) -> void:
	var profiles: Array = []
	for kind in PF.KINDS:
		profiles.append({
			"kind": kind,
			"label": PF.KIND_LABELS[kind],
			"tabs": PF.kind_tabs(kind),
			"description": _kind_description(kind),
		})
	print(JSON.stringify({"profiles": profiles}, "\t"))
	quit(EXIT_OK)


# ====================================================================
# build -- 用 Keil C251 编译为 hex 固件
# ====================================================================
## 复用 Toolchain.build_project()（作者已预留为 MCP 等非 UI 调用方设计）。
## 先部署项目模板与库 -> 写 main.c -> 调用外置 Keil 同步编译。
## 成功判据：Keil 日志含 "0 Error(s)"。编译通常耗时 10~60 秒（首次更久）。
func _cmd_build(args: PackedStringArray) -> void:
	var parsed: Dictionary = _parse_args(args, ["--kind", "--config", "--code", "--project", "--remote"])
	if parsed.has("error"):
		_print_error(parsed["error"])
		quit(EXIT_ARG)
		return
	var kind: String = parsed.get("--kind", "infantry")
	if not PF.is_valid_kind(kind):
		_print_error("未知项目类型: %s（合法值: infantry/engineer/debug）" % kind)
		quit(EXIT_ARG)
		return

	var code: String = ""
	if parsed.has("--code"):
		# 直接编译已有 C 代码文件
		var f: FileAccess = FileAccess.open(parsed["--code"], FileAccess.READ)
		if f == null:
			_print_error("无法读取代码文件: %s" % parsed["--code"])
			quit(EXIT_IO)
			return
		code = f.get_as_text()
		f.close()
	elif parsed.has("--config"):
		# 先生成代码再编译
		var config_text: String = _read_config_source(parsed["--config"])
		if config_text.is_empty() and parsed["--config"] != "-":
			_print_error("无法读取配置文件: %s" % parsed["--config"])
			quit(EXIT_IO)
			return
		var cfg: Dictionary = _parse_config_json(config_text, kind)
		code = _generate_code(kind, cfg)
	elif parsed.has("--project"):
		# 优先用项目里已保存的代码，其次重新生成
		var res: Dictionary = PF.load_from(parsed["--project"])
		if not res["ok"]:
			_print_error("无法读取项目文件: %s" % res["err"])
			quit(EXIT_IO)
			return
		var data: Dictionary = res["data"]
		kind = data.get("kind", "infantry")
		code = str(data.get("main_c_ai", ""))
		if code.strip_edges().is_empty():
			code = str(data.get("main_c_stage1", ""))
		if code.strip_edges().is_empty():
			code = _generate_code(kind, _config_from_project(data, kind))
	else:
		_print_error("build 需要 --config / --code / --project 之一")
		quit(EXIT_ARG)
		return

	if code.strip_edges().is_empty():
		_print_error("没有可编译的代码（配置可能不完整）")
		quit(EXIT_RUN)
		return

	# 编译（同步阻塞）。本地用 Toolchain.build_project；--remote 走云端编译服务。
	var out: Dictionary = {}
	if parsed.has("--remote"):
		out = _remote_build(kind, code, str(parsed["--remote"]))
	else:
		var tc = TC.new()
		var dst: String = _project_dst_for_kind(kind)
		var result: Dictionary = tc.build_project(dst, code)
		out = {
			"ok": bool(result.get("ok", false)),
			"exit": result.get("exit", -1),
			"kind": kind,
			"log": str(result.get("log", "")),
			"hex": tc.get_hex_path(dst),
			"hex_exists": tc.hex_exists(dst),
		}
	print(JSON.stringify(out, "\t"))
	quit(EXIT_OK)


## 云端编译：把 main.c 写到临时文件，调 `python <root>/keil_server/client.py build` 上传到
## 编译服务（服务器端 Keil C251 编译），本机不需要装 Keil。
## 直接以脚本方式运行 client.py（而非 -m），不依赖当前工作目录。
## 需要：项目根有 .venv（或用 PIEBLOCK_PYTHON 指定解释器），服务器在监听 --server 地址。
func _remote_build(kind: String, code: String, server: String) -> Dictionary:
	var tmp_c: String = "user://.remote_main_tmp.c"
	var f := FileAccess.open(tmp_c, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "exit": 1, "kind": kind, "log": "",
				"hex": "", "hex_exists": false, "error": "无法写临时 main.c"}
	f.store_string(code)
	f.close()
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_c)
	var py: String = OS.get_environment("PIEBLOCK_PYTHON")
	if py.is_empty():
		py = "python"
	var root_abs: String = ProjectSettings.globalize_path("res://")
	var client_script: String = root_abs.path_join("keil_server").path_join("client.py")
	var args := PackedStringArray([
		client_script, "build",
		"--kind", kind, "--code", abs_tmp, "--server", server, "--quiet",
	])
	var output: Array = []
	var exit_code: int = OS.execute(py, args, output, true, false)
	var text: String = "\n".join(output)
	# 解析 stdout 里第一个 { 起的 JSON（--quiet 输出单行 JSON）
	var result: Dictionary = {}
	var idx: int = text.find("{")
	if idx >= 0:
		var parsed: Variant = JSON.parse_string(text.substr(idx))
		if parsed is Dictionary:
			result = parsed
	if result.is_empty():
		result = {"ok": false, "exit": 1, "kind": kind, "log": text,
				"hex": "", "hex_exists": false,
				"error": "云端编译客户端未返回 JSON（python 退出码 %d）" % exit_code}
	return result


## 项目类型 -> Toolchain 项目模板路径（与 app_state.gd 的 project_dst_for_kind 一致）
func _project_dst_for_kind(kind: String) -> String:
	if kind == PF.KIND_ENGINEER:
		return TC.PROJECT_ENGINEER_DST
	return TC.PROJECT_DST


# ====================================================================
# 核心：代码生成
# ====================================================================
func _generate_code(kind: String, cfg: Dictionary) -> String:
	match kind:
		PF.KIND_INFANTRY:
			return CG_INFANTRY.new().generate(cfg)
		PF.KIND_ENGINEER:
			return CG_ENGINEER.new().generate(cfg)
		PF.KIND_DEBUG:
			# debug_rows 可能是 null/字符串等畸形输入，非数组一律按空处理，避免生成器崩
			var dr2: Variant = cfg.get("debug_rows", [])
			return CG_DEBUG.new().generate({"debug_rows": dr2 if dr2 is Array else []})
		_:
			return CG_INFANTRY.new().generate(cfg)


# ====================================================================
# 核心：静态检查
# ====================================================================
func _run_check(kind: String, cfg: Dictionary) -> Array:
	match kind:
		PF.KIND_INFANTRY:
			return SC.check_infantry(cfg)
		PF.KIND_ENGINEER:
			return SC.check_engineer(cfg)
		PF.KIND_DEBUG:
			# debug_rows 可能是 null/字符串等畸形输入，非数组一律按空处理，避免 check_debug 崩
			var dr: Variant = cfg.get("debug_rows", cfg.get("rows", []))
			return SC.check_debug(dr if dr is Array else [])
		_:
			return SC.check_infantry(cfg)


# ====================================================================
# 从 .pieproj 提取配置字典
# ====================================================================
## .pieproj 的 config 快照 key 是节点路径（相对 HSplitContainer 或 EditZone），
## 生成器需要扁平字段字典。这里用与 ui.gd 常量一致的精确路径还原。
##
## 前缀约定（来自 ui.gd）：
##   FirstRow 下节点  key = "FirstRow/..."（相对 HSplitContainer）
##   EditZone  下节点  key = "Infantry/..."、"Engineer/..."、"Debug/..."（相对 EditZone）
## 与 ui.gd 完整路径常量的关系：
##   ui 路径 = "VBoxContainer/HBoxContainer/HSplitContainer/" + FirstRow key
##   ui 路径 = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/" + EditZone key
func _config_from_project(data: Dictionary, kind: String) -> Dictionary:
	var config: Dictionary = data.get("config", {})
	match kind:
		PF.KIND_INFANTRY:
			return _flatten_infantry_config(config)
		PF.KIND_ENGINEER:
			return _flatten_engineer_config(config)
		PF.KIND_DEBUG:
			return {"debug_rows": _flatten_debug_config(config)}
		_:
			return _flatten_infantry_config(config)


## 从 config 快照取某节点的值。value 是 {t/s/b}，LineEdit=t，OptionButton=s，CheckBox=b
## 缺失返回空串（而非 null），这样 str() 后是 "" 而不是 GDScript 的 "<null>"
func _config_val(config: Dictionary, key: String) -> Variant:
	if not config.has(key):
		return ""
	var d: Variant = config[key]
	if not d is Dictionary:
		return ""
	var dd: Dictionary = d
	if dd.has("t"):
		return str(dd["t"])
	if dd.has("s"):
		return str(dd["s"])
	if dd.has("b"):
		return bool(dd["b"])
	if dd.has("i"):
		return int(dd["i"])
	return ""


## 步兵：还原 _collect_config() 的扁平字段
func _flatten_infantry_config(config: Dictionary) -> Dictionary:
	var flat: Dictionary = {}
	# FirstRow 共享参数
	flat["channel"] = str(_config_val(config, "FirstRow/RemoteSetting/Channel/LineEdit"))
	flat["deadzone"] = str(_config_val(config, "FirstRow/RemoteSetting/DeadZone/LineEdit"))
	flat["normal_speed"] = str(_config_val(config, "FirstRow/Chassis/Speed/LineEdit"))
	flat["sprint_speed"] = str(_config_val(config, "FirstRow/Chassis/SprintSpeed/LineEdit"))
	flat["sprint_enabled"] = bool(_config_val(config, "FirstRow/Chassis/Sprint/CheckBox"))
	flat["l1_io"] = str(_config_val(config, "FirstRow/Chassis/L1/OptionButton"))
	flat["l1_dir"] = str(_config_val(config, "FirstRow/Chassis/L1/OptionButton2"))
	flat["l2_io"] = str(_config_val(config, "FirstRow/Chassis/L2/OptionButton"))
	flat["l2_dir"] = str(_config_val(config, "FirstRow/Chassis/L2/OptionButton2"))
	flat["r1_io"] = str(_config_val(config, "FirstRow/Chassis/R1/OptionButton"))
	flat["r1_dir"] = str(_config_val(config, "FirstRow/Chassis/R1/OptionButton2"))
	flat["r2_io"] = str(_config_val(config, "FirstRow/Chassis/R2/OptionButton"))
	flat["r2_dir"] = str(_config_val(config, "FirstRow/Chassis/R2/OptionButton2"))
	# 云台（EditZone 下）
	var gimbal: String = "Infantry/GimbalSetting"
	flat["booster_io"] = str(_config_val(config, gimbal + "/Booster/OptionButton"))
	flat["booster_dir"] = str(_config_val(config, gimbal + "/Booster/OptionButton2"))
	# 摩擦轮方向 UI 已删除：Dir 固定发 0（实测协议方向位 1 导致摩擦轮不转）
	flat["yaw_drive"] = str(_config_val(config, gimbal + "/Yaw/OptionButton"))
	flat["yaw_io"] = str(_config_val(config, gimbal + "/Yaw/OptionButton2"))
	flat["yaw_dir"] = str(_config_val(config, gimbal + "/Yaw/OptionButton3"))
	flat["yaw_mid_offset"] = str(_config_val(config, gimbal + "/Yaw/LineEdit"))
	flat["pitch_drive"] = str(_config_val(config, gimbal + "/Pitch/OptionButton"))
	flat["pitch_io"] = str(_config_val(config, gimbal + "/Pitch/OptionButton2"))
	flat["pitch_dir"] = str(_config_val(config, gimbal + "/Pitch/OptionButton3"))
	flat["pitch_mid_offset"] = str(_config_val(config, gimbal + "/Pitch/LineEdit"))
	# 按键映射
	var keyset: String = "Infantry/KeySetting"
	flat["arrow_key"] = str(_config_val(config, keyset + "/ArrowKey/OptionButton"))
	flat["feed_mode"] = str(_config_val(config, keyset + "/FeedMode/OptionButton"))
	flat["trigger_key"] = str(_config_val(config, keyset + "/Trigger/OptionButton"))
	flat["trigger_speed"] = str(_config_val(config, keyset + "/Trigger/Speed"))
	flat["trigger_time"] = str(_config_val(config, keyset + "/Trigger/Time"))
	flat["friction_type"] = str(_config_val(config, keyset + "/FrictionType/OptionButton"))
	flat["booster_key"] = str(_config_val(config, keyset + "/Booster/OptionButton"))
	var max_duty_value: Variant = _config_val(config, keyset + "/BoosterSpeed/MaxDuty")
	if max_duty_value == null or str(max_duty_value).is_empty():
		max_duty_value = _config_val(config, keyset + "/Booster/MaxDuty")
	flat["friction_max_duty"] = str(max_duty_value)
	flat["friction_speed_up_key"] = str(_config_val(config,
		keyset + "/BoosterSpeedControl/OptionButton"))
	flat["friction_speed_down_key"] = str(_config_val(config,
		keyset + "/BoosterSpeedControl/OptionButton2"))
	flat["friction_speed_step"] = str(_config_val(config,
		keyset + "/BoosterSpeedControl/MaxDuty"))
	flat["zero_enabled"] = bool(_config_val(config, keyset + "/Zero/CheckBox"))
	return _merge_defaults(flat, "infantry")


## 工程：还原 _collect_engineer_config() 的扁平字段
func _flatten_engineer_config(config: Dictionary) -> Dictionary:
	var flat: Dictionary = {}
	# FirstRow 共享参数（与步兵相同路径）
	flat["channel"] = str(_config_val(config, "FirstRow/RemoteSetting/Channel/LineEdit"))
	flat["deadzone"] = str(_config_val(config, "FirstRow/RemoteSetting/DeadZone/LineEdit"))
	flat["normal_speed"] = str(_config_val(config, "FirstRow/Chassis/Speed/LineEdit"))
	flat["sprint_speed"] = str(_config_val(config, "FirstRow/Chassis/SprintSpeed/LineEdit"))
	flat["sprint_enabled"] = bool(_config_val(config, "FirstRow/Chassis/Sprint/CheckBox"))
	flat["l1_io"] = str(_config_val(config, "FirstRow/Chassis/L1/OptionButton"))
	flat["l1_dir"] = str(_config_val(config, "FirstRow/Chassis/L1/OptionButton2"))
	flat["l2_io"] = str(_config_val(config, "FirstRow/Chassis/L2/OptionButton"))
	flat["l2_dir"] = str(_config_val(config, "FirstRow/Chassis/L2/OptionButton2"))
	flat["r1_io"] = str(_config_val(config, "FirstRow/Chassis/R1/OptionButton"))
	flat["r1_dir"] = str(_config_val(config, "FirstRow/Chassis/R1/OptionButton2"))
	flat["r2_io"] = str(_config_val(config, "FirstRow/Chassis/R2/OptionButton"))
	flat["r2_dir"] = str(_config_val(config, "FirstRow/Chassis/R2/OptionButton2"))
	# 共享 IO/模式/按键映射（工程页：Engineer TabContainer 的第 0 个 tab）
	flat.merge(_flatten_shared_eng_config(config, "Engineer/Engineer"))
	return _merge_defaults(flat, "engineer")


## 工程 IO 初始化区 + 模式配置 + 每模式动态按键映射行
func _flatten_shared_eng_config(config: Dictionary, root: String) -> Dictionary:
	var flat: Dictionary = {}
	# IO 初始化区（10 引脚：类型 + 初始角）
	var io_init: Dictionary = {}
	var io_mid: Dictionary = {}
	var eng_pins: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]
	for pin in eng_pins:
		io_init[pin] = str(_config_val(config, root + "/" + _eng_io_rel(pin)))
		io_mid[pin] = str(_config_val(config, root + "/" + _eng_io_rel(pin).replace("/OptionButton", "/MidDegree2")))
	flat["io_init"] = io_init
	flat["io_mid"] = io_mid
	# 模式配置
	flat["mode_count"] = str(_config_val(config, root + "/Mode/OptionButton"))
	var mode_tab: String = root + "/Mode/TabContainer"
	flat["switch_strategy"] = "一一对应" if int(_config_val(config, mode_tab)) == 1 else "单击切换"
	flat["mode_switch_key"] = str(_config_val(config, root + "/Mode/TabContainer/Change/OptionButton2"))
	var mode_keys: Array = []
	for kname in ["Key", "Key2", "Key3", "Key4"]:
		mode_keys.append(str(_config_val(config, root + "/Mode/TabContainer/Select/" + kname)))
	flat["mode_keys"] = mode_keys
	# 每模式动态按键映射行（行名 RowNN，按键路径按数字排序）
	var modes: Array = []
	for mi in range(4):
		var rows: Array = []
		var row_keys: Dictionary = {}
		for key in config.keys():
			# Engineer/Engineer/TabContainer/M2/ScrollContainer/VBoxContainer/Row03/Key
			var prefix: String = root + "/TabContainer/M%d/ScrollContainer/VBoxContainer/" % (mi + 1)
			if not str(key).begins_with(prefix):
				continue
			var rest: String = str(key).substr(prefix.length())
			var parts: PackedStringArray = rest.split("/")
			if parts.size() != 2:
				continue
			var row_name: String = parts[0]
			var ctrl: String = parts[1]
			if not row_name.begins_with("Row"):
				continue
			if not row_keys.has(row_name):
				row_keys[row_name] = {}
			row_keys[row_name][ctrl] = _config_val(config, key)
		var order: Array = row_keys.keys()
		order.sort_custom(func(a: String, b: String) -> bool:
			return a.substr(3).to_int() < b.substr(3).to_int())
		for rn in order:
			var rv: Dictionary = row_keys[rn]
			rows.append({
				"key": str(rv.get("Key", "")),
				"dir": str(rv.get("Dir", "")),
				"mode": str(rv.get("Option", "")),
				"param": str(rv.get("Para", "")),
				"io": str(rv.get("IO", "")),
			})
		modes.append({"rows": rows})
	flat["modes"] = modes
	return flat


## 工程 IO 引脚 -> 初始化区相对路径（与 ui.gd ENG_IO_REL 对应）
func _eng_io_rel(pin: String) -> String:
	var map: Dictionary = {
		"P60": "IOs/Row1/P60/OptionButton",
		"P62": "IOs/Row1/P62/OptionButton",
		"P64": "IOs/Row1/P64/OptionButton",
		"P66": "IOs/Row1/P66/OptionButton",
		"P74": "IOs/Row1/P74/OptionButton",
		"P75": "IOs/Row2/P75/OptionButton",
		"P76": "IOs/Row2/P76/OptionButton",
		"P77": "IOs/Row2/P77/OptionButton",
		"MP03": "IOs/Row2/MP03/OptionButton",
		"MP74": "IOs/Row2/MP74/OptionButton",
	}
	return str(map.get(pin, ""))


## 调试：还原 _collect_debug_config() 的行数组
func _flatten_debug_config(config: Dictionary) -> Array:
	var rows: Array = []
	var debug: String = "Debug"
	# DEBUG_ROWS: HBoxContainer..HBoxContainer10，对应 P60/P62/P64/P66/P74/P75/P76/P77/MP03/MP74
	var pin_names: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]
	for i in range(pin_names.size()):
		var row_name: String = "HBoxContainer" if i == 0 else "HBoxContainer%d" % (i + 1)
		var row_path: String = debug + "/" + row_name
		var drive_type: String = str(_config_val(config, row_path + "/OptionButton"))
		var dir_text: String = str(_config_val(config, row_path + "/OptionButton2"))
		var dir_val: int = 1 if dir_text == "正" else 0
		var text: String = str(_config_val(config, row_path + "/LineEdit"))
		var enabled: bool = not text.strip_edges().is_empty()
		var value: int = text.to_int() if text.is_valid_int() else 0
		rows.append({
			"pin": str(pin_names[i]),
			"drive_type": drive_type,
			"dir": dir_val,
			"value": value,
			"enabled": enabled,
		})
	return rows


func _merge_defaults(flat: Dictionary, _kind: String) -> Dictionary:
	# 补默认值，让生成器总能跑。缺失或空串（含 GDScript 的 <null>）都回退
	if not flat.has("channel") or str(flat["channel"]) == "" or str(flat["channel"]) == "<null>":
		flat["channel"] = "36"
	if not flat.has("deadzone") or str(flat["deadzone"]) == "" or str(flat["deadzone"]) == "<null>":
		flat["deadzone"] = "10"
	if not flat.has("normal_speed") or str(flat["normal_speed"]) == "" or str(flat["normal_speed"]) == "<null>":
		flat["normal_speed"] = "4000"
	if not flat.has("sprint_speed") or str(flat["sprint_speed"]) == "" or str(flat["sprint_speed"]) == "<null>":
		flat["sprint_speed"] = "8000"
	if not flat.has("sprint_enabled"):
		flat["sprint_enabled"] = false
	if _kind == "infantry" and (not flat.has("friction_type") \
			or str(flat["friction_type"]) == "" or str(flat["friction_type"]) == "<null>"):
		flat["friction_type"] = "无刷电调"
	if _kind == "infantry":
		if not flat.has("friction_max_duty") or str(flat["friction_max_duty"]) in ["", "<null>"]:
			flat["friction_max_duty"] = "800"
		if not flat.has("friction_speed_up_key") or str(flat["friction_speed_up_key"]) in ["", "<null>"]:
			flat["friction_speed_up_key"] = "B"
		if not flat.has("friction_speed_down_key") or str(flat["friction_speed_down_key"]) in ["", "<null>"]:
			flat["friction_speed_down_key"] = "C"
		if not flat.has("friction_speed_step") or str(flat["friction_speed_step"]) in ["", "<null>"]:
			flat["friction_speed_step"] = "100"
	if not flat.has("l1_io") or str(flat["l1_io"]) == "" or str(flat["l1_io"]) == "<null>":
		flat["l1_io"] = "P74 P24"
	if not flat.has("l2_io") or str(flat["l2_io"]) == "" or str(flat["l2_io"]) == "<null>":
		flat["l2_io"] = "P75 P25"
	if not flat.has("r1_io") or str(flat["r1_io"]) == "" or str(flat["r1_io"]) == "<null>":
		flat["r1_io"] = "P76 P26"
	if not flat.has("r2_io") or str(flat["r2_io"]) == "" or str(flat["r2_io"]) == "<null>":
		flat["r2_io"] = "P77 P27"
	if not flat.has("l1_dir") or str(flat["l1_dir"]) == "" or str(flat["l1_dir"]) == "<null>":
		flat["l1_dir"] = "正向"
	if not flat.has("l2_dir") or str(flat["l2_dir"]) == "" or str(flat["l2_dir"]) == "<null>":
		flat["l2_dir"] = "正向"
	if not flat.has("r1_dir") or str(flat["r1_dir"]) == "" or str(flat["r1_dir"]) == "<null>":
		flat["r1_dir"] = "正向"
	if not flat.has("r2_dir") or str(flat["r2_dir"]) == "" or str(flat["r2_dir"]) == "<null>":
		flat["r2_dir"] = "正向"
	return flat


# ====================================================================
# 配置解析
# ====================================================================
func _read_config_source(source: String) -> String:
	if source == "-":
		# 从 stdin 读取
		return _read_stdin()
	var f: FileAccess = FileAccess.open(source, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _read_stdin() -> String:
	# Godot 没有直接的 stdin API，用 OS.execute 读取
	# 在 headless 模式下，stdin 可以通过管道传入
	# 但 Godot 的 _initialize 期间 stdin 可能还没准备好
	# 用 blocking read
	var buf: String = ""
	# Godot 4.x 没有 stdin.readline()，用 FileAccess.open("stdin://") 也不行
	# 用低级方式：通过 OS 读取
	# 实际上 Godot headless 模式下 print() 到 stdout 是可以的，
	# 但读 stdin 需要 hack。这里用临时文件替代。
	# 如果用户传 "-"，我们尝试从标准输入读
	var lines: PackedStringArray = []
	# 用 FileInput... Godot 没这个。用 OS.execute 也不行。
	# 最终方案：用 FileAccess 的特殊路径
	# 在 Windows 上可以用 "CON" 但不可靠
	# 这里改为：如果 source == "-"，报错提示用临时文件
	# （MCP server 端会直接写临时文件，不走 stdin）
	push_error("stdin 读取在 Godot headless 下不可靠，请用临时文件替代")
	return ""


func _parse_config_json(text: String, kind: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_print_error("配置不是合法 JSON")
		quit(EXIT_ARG)
		return {}
	var cfg: Dictionary = parsed
	if kind == PF.KIND_DEBUG:
		# debug 需要 debug_rows 数组
		if cfg.has("debug_rows"):
			return cfg
		# 如果直接传数组，包装一下
		return cfg
	return cfg


# ====================================================================
# JSON Schema 生成
# ====================================================================
func _build_schema(kind: String) -> Dictionary:
	var schema: Dictionary = {
		"$schema": "https://json-schema.org/draft/2020-12/schema",
		"title": "Pie-Block %s 配置" % PF.kind_label(kind),
		"type": "object",
		"kind": kind,
	}
	match kind:
		PF.KIND_INFANTRY:
			schema["properties"] = _infantry_schema()
		PF.KIND_ENGINEER:
			schema["properties"] = _engineer_schema()
		PF.KIND_DEBUG:
			schema["properties"] = _debug_schema()
	schema["description"] = _kind_description(kind)
	return schema


func _infantry_schema() -> Dictionary:
	return {
		"channel": {"type": "string", "description": "NRF24L01 通道号 (0-125)", "default": "36"},
		"deadzone": {"type": "string", "description": "摇杆死区 (0-2047)", "default": "10"},
		"normal_speed": {"type": "string", "description": "普通速度 (0-10000)", "default": "4000"},
		"sprint_speed": {"type": "string", "description": "冲刺速度 (0-10000)", "default": "8000"},
		"sprint_enabled": {"type": "boolean", "description": "按下左摇杆冲刺", "default": false},
		"l1_io": {"type": "string", "description": "左前轮 IO（扩展板通信脚+方向脚，如 'P74 P24'）", "default": "P74 P24"},
		"l2_io": {"type": "string", "description": "左后轮 IO", "default": "P75 P25"},
		"r1_io": {"type": "string", "description": "右前轮 IO", "default": "P76 P26"},
		"r2_io": {"type": "string", "description": "右后轮 IO", "default": "P77 P27"},
		"l1_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"l2_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"r1_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"r2_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"booster_io": {"type": "string", "description": "拨弹电机 IO（单引脚，扩展板）", "default": "P60"},
		"booster_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"yaw_drive": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
		"yaw_io": {"type": "string", "description": "Yaw 轴 IO"},
		"yaw_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"pitch_drive": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
		"pitch_io": {"type": "string", "description": "Pitch 轴 IO"},
		"pitch_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"yaw_mid_offset": {"type": "string", "description": "Yaw 归中角偏移 (-90~90)", "default": "0"},
		"pitch_mid_offset": {"type": "string", "description": "Pitch 归中角偏移 (-90~90)", "default": "0"},
		"arrow_key": {"type": "string", "enum": ["移动", "冲刺", "其他"], "default": "移动"},
		"feed_mode": {"type": "string", "enum": ["目视闭环", "阻塞开环"], "default": "阻塞开环",
			"description": "拨弹模式：目视闭环=按住持续拨弹松开即停（不阻塞）；阻塞开环=按一下拨弹固定时长（阻塞主循环）"},
		"trigger_key": {"type": "string", "description": "扳机键（拨弹触发键）"},
		"trigger_speed": {"type": "string", "description": "拨弹速度 (0-10000)"},
		"trigger_time": {"type": "string", "description": "拨弹时间 ms (0-65535)"},
		"friction_type": {"type": "string", "enum": ["无刷电调", "不使用"],
			"description": "摩擦轮类型；不使用时释放 P64/P66", "default": "无刷电调"},
		"booster_key": {"type": "string", "description": "摩擦轮开关键"},
		"friction_max_duty": {"type": "string", "enum": ["500", "600", "700", "800"],
			"description": "摩擦轮开启后的最大占空比（校内赛安全硬上限 800）", "default": "800"},
		"friction_speed_up_key": {"type": "string", "description": "摩擦轮增速键", "default": "B"},
		"friction_speed_down_key": {"type": "string", "description": "摩擦轮减速键", "default": "C"},
		"friction_speed_step": {"type": "string", "description": "摩擦轮目标 Duty 调整步长", "default": "100"},
		"zero_enabled": {"type": "boolean", "description": "松手归中", "default": false},
	}


func _engineer_schema() -> Dictionary:
	return _engineer_base_schema()


func _engineer_base_schema() -> Dictionary:
	return {
		"channel": {"type": "string", "description": "NRF24L01 通道号 (0-125)", "default": "36"},
		"deadzone": {"type": "string", "description": "摇杆死区 (0-2047)", "default": "10"},
		"normal_speed": {"type": "string", "description": "普通速度 (0-10000)", "default": "4000"},
		"sprint_speed": {"type": "string", "description": "冲刺速度 (0-10000)", "default": "8000"},
		"sprint_enabled": {"type": "boolean", "description": "按下左摇杆冲刺", "default": false},
		"l1_io": {"type": "string", "default": "P74 P24"},
		"l2_io": {"type": "string", "default": "P75 P25"},
		"r1_io": {"type": "string", "default": "P76 P26"},
		"r2_io": {"type": "string", "default": "P77 P27"},
		"l1_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"l2_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"r1_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"r2_dir": {"type": "string", "enum": ["正向", "反向"], "default": "正向"},
		"io_init": {
			"type": "object",
			"description": "扩展板各引脚初始化类型",
			"properties": {
				"P60": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P62": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P64": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P66": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P74": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P75": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P76": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"P77": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"MP03": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
				"MP74": {"type": "string", "enum": ["舵机", "电机"], "default": "舵机"},
			},
		},
		"io_mid": {
			"type": "object",
			"description": "各引脚舵机初始角（相对中位偏移角，-90~90，仅舵机有效）",
			"properties": {
				"P60": {"type": "string", "default": ""},
				"P62": {"type": "string", "default": ""},
				"P64": {"type": "string", "default": ""},
				"P66": {"type": "string", "default": ""},
				"P74": {"type": "string", "default": ""},
				"P75": {"type": "string", "default": ""},
				"P76": {"type": "string", "default": ""},
				"P77": {"type": "string", "default": ""},
				"MP03": {"type": "string", "default": ""},
				"MP74": {"type": "string", "default": ""},
			},
		},
		"mode_count": {"type": "integer", "minimum": 1, "maximum": 4, "default": 1,
			"description": "操作模式个数（1~4）"},
		"switch_strategy": {"type": "string", "enum": ["单击切换", "一一对应"], "default": "单击切换",
			"description": "模式切换方式：单击切换=一个键轮换；一一对应=每模式一个键"},
		"mode_switch_key": {"type": "string", "default": "E",
			"description": "单击切换时的模式切换键"},
		"mode_keys": {
			"type": "array",
			"description": "一一对应时各模式的切换键（模式1~4）",
			"items": {"type": "string"},
			"maxItems": 4,
		},
		"modes": {
			"type": "array",
			"description": "每模式一组动态按键映射行（最多 4 个模式）",
			"maxItems": 4,
			"items": {
				"type": "object",
				"properties": {
					"rows": {
						"type": "array",
						"items": {
							"type": "object",
							"properties": {
								"key": {"type": "string",
									"description": "E/↑/↓/←/→/A/B/C/D/LC/RC（按键）或 LX/LY/RX/RY（摇杆轴）"},
								"dir": {"type": "string", "enum": ["正", "反"], "default": "正"},
								"mode": {"type": "string", "enum": ["增量", "直接", "速度", "增速"],
									"description": "增量/直接（舵机），直接/速度/增速（电机）；摇杆行只能用 增量/速度/增速"},
								"param": {"type": "string", "description": "步长(°) / 角度(°) / 速度(0-10000)"},
								"io": {"type": "string",
									"description": "目标 IO（P60~P77/MP03/MP74）"},
							},
						},
					},
				},
			},
		},
	}


func _debug_schema() -> Dictionary:
	return {
		"debug_rows": {
			"type": "array",
			"description": "调试引脚配置，逐行执行测试命令",
			"items": {
				"type": "object",
				"properties": {
					"pin": {"type": "string", "enum": ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]},
					"drive_type": {"type": "string", "enum": ["舵机", "电机", "摩擦轮", "不使用"]},
					"dir": {"type": "integer", "enum": [0, 1], "description": "1=正向 0=反向"},
					"value": {"type": "integer", "description": "占空比/角度值"},
					"enabled": {"type": "boolean", "description": "是否启用该行"},
				},
			},
		},
	}


# ====================================================================
# 辅助
# ====================================================================
func _kind_description(kind: String) -> String:
	match kind:
		PF.KIND_INFANTRY:
			return "步兵机器人：底盘4电机+云台(Yaw/Pitch)+摩擦轮+拨弹。P64/P66固定用于摩擦轮。"
		PF.KIND_ENGINEER:
			return "工程机器人：底盘4电机、1～4个独立操作模式、两种切换策略和任意IO按键映射。支持舵机/电机混用。"
		PF.KIND_DEBUG:
			return "调试模式：逐行测试各引脚，每个命令持续3秒，蜂鸣器提示开始/结束。"
		_:
			return ""


func _parse_args(args: PackedStringArray, known_flags: Array) -> Dictionary:
	"""解析 --key value 形式的参数"""
	var result: Dictionary = {}
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg.begins_with("--"):
			if arg in known_flags:
				if i + 1 < args.size():
					result[arg] = args[i + 1]
					i += 2
				else:
					return {"error": "%s 需要参数值" % arg}
			else:
				return {"error": "未知参数: %s" % arg}
		else:
			# 位置参数暂不处理
			i += 1
	return result


func _print_usage() -> void:
	print("""
Pie-Block 代码生成器 CLI
========================

用法:
  godot --headless --path <项目根> --script scripts/cli_codegen.gd -- <命令> [参数]

命令:
  generate    生成 main.c 代码
  check       运行静态检查
  build       用 Keil C251 编译为 hex 固件
  schema      输出配置 JSON Schema
  profiles    列出所有项目类型
  help        显示此帮助

generate 参数:
  --kind <infantry|engineer|debug>   项目类型（与 --config 配合）
  --config <json文件>                配置 JSON 文件路径
  --project <.pieproj文件>           从项目文件加载（含配置和代码）
  --out <文件>                       输出到文件（不指定则输出 JSON 到 stdout）

check 参数:
  --kind <infantry|engineer|debug>   项目类型
  --config <json文件>                配置 JSON 文件路径
  --project <.pieproj文件>           从项目文件加载

build 参数:
  --kind <infantry|engineer|debug>   项目类型（决定用哪个项目模板编译）
  --config <json文件>                配置 JSON 文件路径（先生成再编译）
  --code <c文件>                     直接编译已有的 C 代码文件
  --project <.pieproj文件>           从项目文件编译（优先用已保存的代码）
  --remote <编译服务地址>            走云端编译（服务器端 Keil 编译，本机无需装 Keil）
                                     例如 --remote http://127.0.0.1:8000
                                     可用 PIEBLOCK_PYTHON 指定 python 解释器

schema 参数:
  --kind <infantry|engineer|debug>   项目类型

示例:
  # 用默认步兵配置生成代码
  godot --headless --path . --script scripts/cli_codegen.gd -- generate --kind infantry --config my_config.json --out main.c

  # 检查工程配置
  godot --headless --path . --script scripts/cli_codegen.gd -- check --kind engineer --config eng_config.json

  # 编译步兵配置为 hex 固件
  godot --headless --path . --script scripts/cli_codegen.gd -- build --kind infantry --config my_config.json

  # 输出步兵配置 Schema
  godot --headless --path . --script scripts/cli_codegen.gd -- schema --kind infantry

  # 列出所有项目类型
  godot --headless --path . --script scripts/cli_codegen.gd -- profiles

输出格式:
  generate（无 --out）: {"ok": true, "kind": "...", "code": "...", "issues": [...]}
  generate（有 --out）: {"ok": true, "kind": "...", "out": "...", "issues": [...]}
  check:               {"ok": true/false, "kind": "...", "issues": [...], "error_count": N, "warn_count": N}
  build:               {"ok": true/false, "exit": N, "kind": "...", "log": "...", "hex": "...", "hex_exists": true/false}
  schema:              JSON Schema 对象
  profiles:            {"profiles": [...]}

退出码:
  0 = 成功
  1 = 参数错误
  2 = 生成/检查失败
  3 = IO 错误
""")


func _print_usage_error() -> void:
	_print_error("缺少命令参数")
	print("用法: godot --headless --path <项目根> --script scripts/cli_codegen.gd -- <命令> [参数]")
	print("运行 help 命令查看完整用法")


func _print_error(msg: String) -> void:
	# 错误输出到 stderr（Godot headless 下 push_error 到 stderr）
	push_error("[ERR] %s" % msg)
