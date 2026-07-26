extends SceneTree

## 3D 仿真视图冒烟测试：实例化场景、切换四种模式、拖拽换算往返。
## 运行方式：godot --headless --path . --script scripts/test_arm_sim.gd

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _cfg(config_type: int, jc: int) -> Dictionary:
	var joints: Array = []
	for i in range(jc):
		joints.append({"io": "P60", "dir": "正向", "zero": "20", "min": "-80", "max": "80"})
	return {
		"config_type": config_type, "joint_count": jc,
		"L1": "120", "L2": "90", "L3": "40",
		"joints": joints,
		"presets": [
			{"key": "A", "x": "100", "y": "20", "z": "50", "phi": "10", "enabled": true},
			{"key": "B", "x": "80", "y": "-30", "z": "30", "phi": "0", "enabled": true},
			{"key": "C", "x": "", "y": "", "z": "", "phi": "", "enabled": false},
		],
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
		"joy_scale": "5", "keymove_speed": "2",
		"keymove": [
			{"plus": "↑", "minus": "↓"},
			{"plus": "←", "minus": "->"},
			{"plus": "A", "minus": "B"},
			{"plus": "C", "minus": "D"},
		],
	}


func _initialize() -> void:
	print("=== 3D 仿真视图冒烟测试 ===\n")
	var packed: PackedScene = load("res://scenes/arm_sim.tscn") as PackedScene
	_check("arm_sim.tscn 可加载", packed != null)
	if packed == null:
		quit(1)
		return
	for case in [[0, 2], [1, 3], [2, 4]]:
		await _test_config(packed, case[0], case[1])
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _test_config(packed: PackedScene, config_type: int, jc: int) -> void:
	var tag: String = "构型%d(%d轴)" % [config_type, jc]
	var sim: Node = packed.instantiate()
	_check("%s 实例化" % tag, sim is Control)
	if not sim is Control:
		return
	sim.set_config(_cfg(config_type, jc))
	# 必须挂进树并等一帧才会触发 _ready 与几何构建
	# （--script 模式下 _initialize 期间 root 还没进树，_ready 不会立刻跑）
	root.add_child(sim)
	await process_frame
	# 连杆段数：2/3 轴两段，4 轴三段
	var want_links: int = 3 if config_type >= 2 else 2
	var arm_root: Node = sim.get_node_or_null("Sim/SubViewport/World/ArmRoot")
	_check("%s ArmRoot 存在" % tag, arm_root != null)
	if arm_root != null:
		# 连杆 + 关节球 + 末端球
		var want_children: int = want_links * 2 + 1
		_check("%s ArmRoot 子节点数 %d" % [tag, want_children],
			arm_root.get_child_count() == want_children,
			"实际 %d" % arm_root.get_child_count())
	# 网格与坐标轴已生成
	for path in ["Sim/SubViewport/World/Grid", "Sim/SubViewport/World/Axes"]:
		var n: Node = sim.get_node_or_null(path)
		_check("%s %s 有 mesh" % [tag, path.get_file()], n is MeshInstance3D and n.mesh != null)
	# 初始姿态：末端球位置应等于初始角的 FK 结果（经坐标映射）
	var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
	var home_ang: Array = []
	for i in range(jc):
		home_ang.append(20.0)
	var fk: Array = cg.forward_kinematics_angles(home_ang, 120.0, 90.0, 40.0, config_type)
	var tip_node: Node = arm_root.get_child(arm_root.get_child_count() - 1)
	var want_pos: Vector3 = sim._robot_to_godot(fk[0], fk[1], fk[2])
	_check("%s 末端球位置 == FK" % tag,
		tip_node is MeshInstance3D and tip_node.position.distance_to(want_pos) < 1e-4,
		"实际 %s 期望 %s" % [str(tip_node.position), str(want_pos)])
	# 坐标映射往返：_robot_to_godot -> _target_from_godot 应还原
	sim._target = [77.0, -33.0, 51.0, 0.0]
	var g: Vector3 = sim._robot_to_godot(77.0, -33.0, 51.0)
	sim._target_from_godot(g)
	var ok_rt: bool = abs(sim._target[0] - 77.0) < 1e-3
	if config_type == 0:
		# 2 轴无 Z，Y 即高度
		ok_rt = ok_rt and abs(sim._target[1] - (-33.0)) < 1e-3
	else:
		ok_rt = ok_rt and abs(sim._target[1] - (-33.0)) < 1e-3 and abs(sim._target[2] - 51.0) < 1e-3
	_check("%s 坐标映射往返一致" % tag, ok_rt, "实际 %s" % str(sim._target))
	# 四种模式切换都不应报错，且状态行有内容
	for m in [0, 1, 2, 3]:
		sim._on_mode_selected(m)
		var status: Node = sim.get_node_or_null("StatusPanel/Status")
		_check("%s 模式%d 状态行非空" % [tag, m], status is Label and status.text.length() > 0)
	# 越界目标：reachable 必须为 false，且连杆材质换成告警色
	sim._on_mode_selected(0)
	sim._target = [9999.0, 0.0, 0.0, 0.0]
	sim._recompute()
	_check("%s 越界 -> reachable=false" % tag, sim._reachable == false)
	var link0: Node = arm_root.get_child(0)
	_check("%s 越界 -> 连杆用告警材质" % tag,
		link0 is MeshInstance3D and link0.material_override == sim._mat_link_bad)
	# 回到可达目标后材质恢复
	sim._target = [120.0, 0.0, 30.0, 0.0]
	sim._recompute()
	_check("%s 恢复可达 -> 连杆用常规材质" % tag,
		link0 is MeshInstance3D and link0.material_override == sim._mat_link)
	# 轨迹缓冲不超上限
	for i in range(400):
		sim._push_trail(Vector3(float(i) * 0.001, 0, 0))
	_check("%s 轨迹点数 <= 300" % tag, sim._trail_points.size() <= 300,
		"实际 %d" % sim._trail_points.size())
	# 模拟手柄：推满摇杆后目标应发生移动且不产生 NaN
	sim._on_mode_selected(3)
	var before: float = sim._target[0]
	sim._joy = Vector2(1.0, 0.0)
	sim._step_joystick(0.1) # 100ms -> 10 步
	_check("%s 摇杆推满后目标变化" % tag, abs(sim._target[0] - before) > 1e-6)
	var finite: bool = true
	for v in sim._target:
		if not is_finite(v):
			finite = false
	_check("%s 摇杆步进后目标有限" % tag, finite, "实际 %s" % str(sim._target))
	# 预设点位巡航不炸
	sim._on_mode_selected(2)
	sim._start_play()
	for i in range(30):
		sim._step_play(0.1)
	_check("%s 巡航后角度有限" % tag,
		sim._angles.size() == jc and is_finite(sim._angles[0]))
	root.remove_child(sim)
	sim.free()
