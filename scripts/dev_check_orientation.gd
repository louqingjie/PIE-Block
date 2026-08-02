extends SceneTree
## 临时诊断：读取工程构形，输出 orientation_mask（哪些姿态轴可独立控制）。
## 运行：godot --headless --path . --script scripts/dev_check_orientation.gd

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const DIAG = preload("res://scripts/arm_diagnosis.gd")


func _initialize() -> void:
	var loaded: Dictionary = PF.load_from("工程项目.pieproj")
	if not bool(loaded.get("ok", false)):
		push_error("读取工程失败: %s" % str(loaded.get("err", "")))
		quit(2)
		return
	var ik: Dictionary = IK_CONFIG.normalize((loaded["data"] as Dictionary).get("ik_config", {}))
	var joints: Array = ik.get("joints", [])
	var jc: int = int(ik.get("joint_count", 0))
	print("关节数: %d" % jc)
	var axes: Array = []
	for j in joints:
		axes.append(str(j.get("axis", "")))
	print("转轴序列: %s" % ", ".join(axes))
	var diag: Dictionary = DIAG.new().analyze(joints, jc)
	print("position_dof: %d" % int(diag.get("position_dof", 0)))
	print("orientation_dof: %d" % int(diag.get("orientation_dof", 0)))
	var mask: Dictionary = diag.get("orientation_mask", {})
	print("orientation_mask: roll=%s pitch=%s yaw=%s" % [
		str(bool(mask.get("roll", false))),
		str(bool(mask.get("pitch", false))),
		str(bool(mask.get("yaw", false)))])
	for name in ["roll", "pitch", "yaw"]:
		if not bool(mask.get(name, false)):
			var reason: Dictionary = diag.get("orientation_reason", {})
			print("  %s 不可独立控制: %s" % [name, str(reason.get(name, "?"))])
	quit(0)
