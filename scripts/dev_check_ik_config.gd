extends SceneTree

## 验证工程项目.pieproj 的 IK 配置通过 validate（不报 offset/zero/min/max 未设置）。
## 运行：godot --headless --path . --script scripts/dev_check_ik_config.gd -- --proj=工程项目.pieproj

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", "工程项目.pieproj"))
	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("读取工程失败: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var ik: Dictionary = IK_CONFIG.normalize((loaded["data"] as Dictionary).get("ik_config", {}))
	# 模拟 GUI 场景的 engineer 配置（扩展板引脚初始化为舵机）
	var engineer := {
		"io_init": {"P60": "舵机", "P62": "舵机", "P64": "舵机", "P66": "舵机",
			"P74": "舵机", "P75": "舵机", "P76": "舵机", "P77": "舵机"},
		"key_map": [],
	}
	var validation: Dictionary = IK_CONFIG.validate(ik, engineer)
	var errors: Array = []
	var warnings: Array = []
	for issue in validation.get("issues", []):
		if str(issue.get("type", "")) == "Error":
			errors.append(str(issue.get("msg", "")))
		else:
			warnings.append(str(issue.get("msg", "")))
	print("关节数: %d" % int(ik.get("joint_count", 0)))
	print("Error 数: %d" % errors.size())
	for e in errors:
		print("  [E] %s" % e)
	print("Warning 数: %d" % warnings.size())
	for w in warnings:
		print("  [W] %s" % w)
	quit(0 if errors.is_empty() else 1)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result
