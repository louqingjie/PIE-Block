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
	# 坐标映射：2 轴 (x,y) 是竖直平面，3/4 轴 (x,y) 水平、z 高度
	var g: Vector3 = sim._robot_to_godot(77.0, -33.0, 51.0)
	var want_g: Vector3 = (Vector3(77.0, -33.0, 0.0) if config_type == 0 \
		else Vector3(77.0, 51.0, 33.0)) * 0.01
	_check("%s 坐标映射正确" % tag, g.distance_to(want_g) < 1e-6,
		"实际 %s 期望 %s" % [str(g), str(want_g)])
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
	# 逆解模式的键盘轴映射（不依赖真实按键，直接验证方向向量组装）
	sim._on_mode_selected(0)
	_check("%s 无按键时方向为零" % tag, sim._key_move_axis() == Vector3.ZERO)
	# 速度滑块写入后只影响后续步进，不应改变当前姿态
	var ang_before: Array = sim._angles.duplicate()
	sim._on_param_changed(200.0, "movespd", null)
	_check("%s 速度滑块写入" % tag, abs(sim._ik_move_speed - 200.0) < 1e-6)
	_check("%s 改速度不动姿态" % tag, sim._angles == ang_before)
	# 模拟手柄：推满摇杆后目标应发生移动且不产生 NaN
	sim._on_mode_selected(3)
	var before: float = sim._target[0]
	sim._joy = Vector2(1.0, 0.0)
	sim._step_controller(0.1) # 100ms -> 10 步
	_check("%s 摇杆推满后目标变化" % tag, abs(sim._target[0] - before) > 1e-6)
	var finite: bool = true
	for v in sim._target:
		if not is_finite(v):
			finite = false
	_check("%s 摇杆步进后目标有限" % tag, finite, "实际 %s" % str(sim._target))
	# 手柄按键 -> 键盘绑定表：每条都得有可用的键码且不与 WASD 撞车
	var rows: Array = sim._controller_key_rows()
	_check("%s 按键绑定表非空" % tag, rows.size() > 0)
	var wasd: Array = [KEY_W, KEY_A, KEY_S, KEY_D]
	var no_clash: bool = true
	var named: bool = true
	for row in rows:
		if row["kb_code"] in wasd:
			no_clash = false
		if str(row["kb_name"]).is_empty():
			named = false
	_check("%s 按键绑定不与 WASD 撞车" % tag, no_clash)
	_check("%s 按键绑定有可读名" % tag, named)
	# 构型裁剪：2 轴不应出现 Z 轴（4 轴才有 φ）
	var max_axis: int = 0
	for row in rows:
		max_axis = max(max_axis, int(row["axis"]))
	_check("%s 按键绑定轴不越构型" % tag, max_axis < jc,
		"最大轴 %d, jc=%d" % [max_axis, jc])
	# 预设点位巡航不炸
	sim._on_mode_selected(2)
	sim._start_play()
	for i in range(30):
		sim._step_play(0.1)
	_check("%s 巡航后角度有限" % tag,
		sim._angles.size() == jc and is_finite(sim._angles[0]))
	await _test_calibration(sim, config_type, jc, tag)
	root.remove_child(sim)
	sim.free()


## 标定台：臂长编辑、中位朝向标定、预设点位捕获、配置回写
func _test_calibration(sim: Node, config_type: int, jc: int, tag: String) -> void:
	# --- 配置变更信号 ---
	var emitted: Array = []
	sim.config_changed.connect(func(c: Dictionary) -> void: emitted.append(c))
	# --- 臂长编辑：几何须跟着重建 ---
	sim._on_mode_selected(1) # 标定模式
	var arm_root: Node = sim.get_node("Sim/SubViewport/World/ArmRoot")
	sim._on_param_changed(200.0, "L1", null)
	_check("%s 改 L1 写入" % tag, abs(sim._l1 - 200.0) < 1e-6)
	_check("%s 改 L1 触发 config_changed" % tag, emitted.size() > 0)
	if emitted.size() > 0:
		_check("%s config_changed 带新 L1" % tag,
			str(emitted[-1].get("L1", "")).to_float() == 200.0,
			"实际 %s" % str(emitted[-1].get("L1", "")))
	# 第一段连杆长度应等于新 L1（经坐标缩放）
	var link0: Node = arm_root.get_child(0)
	var j0: Node = arm_root.get_child(jc if config_type >= 2 else 2)
	_check("%s 改 L1 后连杆几何更新" % tag,
		link0 is MeshInstance3D and j0 != null)
	var frames: Array = sim._cg.joint_frames(sim._angles, sim._l1, sim._l2, sim._l3, config_type)
	_check("%s 改 L1 后首段长度 == 200" % tag,
		abs(frames[1].distance_to(frames[0]) - 200.0) < 1e-3,
		"实际 %.3f" % frames[1].distance_to(frames[0]))
	# L1 不允许为 0（余弦定理会除零）
	sim._on_param_changed(0.0, "L1", null)
	_check("%s L1 被夹到正值" % tag, sim._l1 > 0.0)
	sim._on_param_changed(120.0, "L1", null)
	# --- 中位朝向标定 ---
	sim._fk_angles = [15.0, 25.0, 35.0, 45.0]
	sim._recompute()
	var before_ang: Array = sim._angles.duplicate()
	sim._calibrate_offset_from_current()
	var ok_off: bool = true
	for i in range(jc):
		if abs(sim._joint_offset(i) - before_ang[i]) > 0.01:
			ok_off = false
	_check("%s 标定中位朝向写入各关节" % tag, ok_off,
		"offset=%s 期望=%s" % [str(sim._cg.joint_offsets(sim._joints, jc)), str(before_ang)])
	# 标定完当前姿态的舵机指令角应全为 0（舵机正处中位）
	var sv: Dictionary = sim._cg.servo_angles(sim._angles, sim._joints)
	var all_zero: bool = true
	for a in sv["angles"]:
		if abs(a) > 0.01:
			all_zero = false
	_check("%s 标定后舵机指令角归零" % tag, all_zero, "实际 %s" % str(sv["angles"]))
	_check("%s 标定后无超程" % tag, not (true in sv["over_travel"]))
	# 滑块范围应随中位朝向平移
	var rng: Array = sim._joint_slider_range(0)
	_check("%s 滑块范围随中位朝向平移" % tag,
		rng[0] >= sim._joint_offset(0) - 90.001 and rng[1] <= sim._joint_offset(0) + 90.001,
		"范围 %s offset=%.1f" % [str(rng), sim._joint_offset(0)])
	# --- 初始角标定 ---
	sim._calibrate_home_from_current()
	var ok_home: bool = true
	for i in range(jc):
		if abs(str(sim._joints[i].get("zero", "")).to_float() - sim._angles[i]) > 0.01:
			ok_home = false
	_check("%s 标定初始角写入各关节" % tag, ok_home)
	# --- 中位朝向归零 ---
	sim._reset_offsets()
	var all_reset: bool = true
	for i in range(jc):
		if abs(sim._joint_offset(i)) > 1e-6:
			all_reset = false
	_check("%s 中位朝向归零" % tag, all_reset)
	# --- 预设点位捕获 ---
	sim._on_mode_selected(2)
	sim._target = [100.0, 20.0, 30.0, 0.0]
	sim._recompute()
	var tip: Array = sim._cg.forward_kinematics_angles(
		sim._angles, sim._l1, sim._l2, sim._l3, config_type)
	sim._save_preset(2)
	var p: Dictionary = sim._presets[2]
	_check("%s 存预设后 enabled" % tag, p.get("enabled", false) == true)
	_check("%s 预设存的是实际末端 X" % tag,
		abs(str(p.get("x", "")).to_float() - tip[0]) < 0.02,
		"存了 %s 期望 %.2f" % [str(p.get("x", "")), tip[0]])
	# 2 轴构型不该写 Z（配置界面会把 0 当成已填）
	if config_type == 0:
		_check("%s 2轴预设不写 Z" % tag, str(p.get("z", "")).is_empty())
	else:
		_check("%s 预设存的是实际末端 Z" % tag,
			abs(str(p.get("z", "")).to_float() - tip[2]) < 0.02)
	# 非 4 轴不该写 φ
	if jc < 4:
		_check("%s 非4轴预设不写 φ" % tag, str(p.get("phi", "")).is_empty())
	_check("%s 存预设自动给按键" % tag, not str(p.get("key", "")).is_empty())
	# 跳回该预设，末端应回到存的位置
	sim._target = [10.0, 0.0, 0.0, 0.0]
	sim._recompute()
	sim._goto_preset(2)
	_check("%s 跳转预设还原目标" % tag,
		abs(sim._target[0] - str(p.get("x", "")).to_float()) < 0.02)
	# --- 清空预设 ---
	sim._clear_presets()
	var any_on: bool = false
	for pp in sim._presets:
		if pp.get("enabled", false):
			any_on = true
	_check("%s 清空预设" % tag, not any_on)
	_test_gripper(sim, config_type, jc, tag)
	_test_chassis(sim, config_type, jc, tag)


## 自定义底盘高度：轮径固定，只有悬挂间隙与地面跟着变，且不影响机械臂
func _test_chassis_height(sim: Node, config_type: int, tag: String) -> void:
	var U: float = sim.MM_TO_UNIT
	var chassis: Node = sim.get_node("Sim/SubViewport/World/Chassis")
	var wr: float = sim.WHEEL_RADIUS_MM
	# 车高下限只受板厚限制：机械上离地可以几乎为 0，
	# 轮子只是示意，不应反向约束车高
	var min_h: float = sim.CHASSIS_DECK_THICK_MM
	# 先把安装偏移归零，便于直接核对绝对高度
	sim._mount = Vector3(0.0, 0.0, 0.0)
	for h in [min_h, 152.0, 300.0]:
		sim._on_chassis_param_changed("chh", h)
		_check("%s 车高%.0f 写入" % [tag, h], abs(sim._chassis_height - h) < 1e-6)
		# 地面 = -车高（mount.z 已归零）
		_check("%s 车高%.0f 地面 == -车高" % [tag, h],
			abs(sim._ground_level() - (-h)) < 0.01,
			"ground %.2f 期望 %.2f" % [sim._ground_level(), -h])
		# 车高足够时恒等式成立：轮径 + 间隙 + 板厚 == 车高。
		# 车高低于「轮径 + 板厚」时轮子跟着板一起沉，间隙钳在 0，恒等式不再适用。
		var suspended: bool = h >= wr * 2.0 + sim.CHASSIS_DECK_THICK_MM
		if suspended:
			var total: float = wr * 2.0 + sim._wheel_gap() + sim.CHASSIS_DECK_THICK_MM
			_check("%s 车高%.0f 轮径+间隙+板厚 == 车高" % [tag, h], abs(total - h) < 0.01,
				"实际 %.2f 期望 %.2f" % [total, h])
		else:
			_check("%s 车高%.0f 贴地时间隙为 0" % [tag, h], abs(sim._wheel_gap()) < 0.01,
				"间隙 %.3f" % sim._wheel_gap())
		_check("%s 车高%.0f 间隙非负" % [tag, h], sim._wheel_gap() >= 0.0)
		# 轮子实际渲染半径必须始终是固定值，不随车高变
		var wheels: Array = []
		for c in chassis.get_children():
			if c is MeshInstance3D and c.mesh is CylinderMesh \
					and abs(c.mesh.top_radius / U - wr) < 0.01:
				wheels.append(c)
		_check("%s 车高%.0f 四轮半径均为固定值" % [tag, h], wheels.size() == 4,
			"半径为 %.1f 的轮子有 %d 个" % [wr, wheels.size()])
		if wheels.is_empty():
			continue
		# 轮下沿必须落在地面上
		var wbot: float = wheels[0].position.y / U - wheels[0].mesh.top_radius / U
		_check("%s 车高%.0f 轮下沿落在地面" % [tag, h],
			abs(wbot - sim._ground_level()) < 0.01,
			"轮下沿 %.2f ground %.2f" % [wbot, sim._ground_level()])
		# 轮径固定后前后轮永不相交，但仍守一道防线
		var fwds: Dictionary = {}
		for ww in wheels:
			fwds["%.3f" % (ww.position.x / U)] = true
		var keys: Array = fwds.keys()
		_check("%s 车高%.0f 仍是前后两组轮" % [tag, h], keys.size() == 2,
			"实际 %d 组" % keys.size())
		if keys.size() == 2:
			var gap: float = absf(str(keys[0]).to_float() - str(keys[1]).to_float())
			_check("%s 车高%.0f 前后轮不相交" % [tag, h], gap > wr * 2.0,
				"轮心间距 %.1f 轮直径 %.1f" % [gap, wr * 2.0])
	# 车高降到贴地：只夹到板厚，且悬挂支臂应完全消失（示意件没必要硬留着）
	sim._on_chassis_param_changed("chh", 0.0)
	_check("%s 车高可降到板厚" % tag, abs(sim._chassis_height - min_h) < 1e-6,
		"实际 %.2f 期望 %.2f" % [sim._chassis_height, min_h])
	_check("%s 贴地时间隙为 0" % tag, abs(sim._wheel_gap()) < 0.01,
		"间隙 %.3f" % sim._wheel_gap())
	_check("%s 贴地时不产生 NaN" % tag,
		is_finite(sim._ground_level()) and is_finite(sim._wheel_gap()))
	# 贴地时 Box 只剩底盘板（+ 可能的安装柱），四根支臂不该再画
	var low_boxes: int = 0
	for c in chassis.get_children():
		if c is MeshInstance3D and c.mesh is BoxMesh:
			low_boxes += 1
	_check("%s 贴地时支臂已消失" % tag, low_boxes <= 2,
		"Box 数 %d（板 + 最多一个安装柱）" % low_boxes)
	# 轮下沿仍须贴着地面，不能沉到地面以下
	var low_wheel: Node = null
	for c in chassis.get_children():
		if c is MeshInstance3D and c.mesh is CylinderMesh \
				and abs(c.mesh.top_radius / U - wr) < 0.01:
			low_wheel = c
			break
	if low_wheel != null:
		var lb: float = low_wheel.position.y / U - low_wheel.mesh.top_radius / U
		_check("%s 贴地时轮下沿仍在地面" % tag,
			abs(lb - sim._ground_level()) < 0.01,
			"轮下沿 %.2f ground %.2f" % [lb, sim._ground_level()])
	# 改车高不应动关节角与臂长
	var ang_before: Array = sim._angles.duplicate()
	var l1_before: float = sim._l1
	sim._on_chassis_param_changed("chh", 152.0)
	_check("%s 改车高不动关节角" % tag, sim._angles == ang_before)
	_check("%s 改车高不动臂长" % tag, abs(sim._l1 - l1_before) < 1e-6)
	# 车高变化后网格（地面）须跟着下移
	var grid: Node = sim.get_node_or_null("Sim/SubViewport/World/Grid")
	_check("%s 改车高后网格已重建" % tag, grid is MeshInstance3D and grid.mesh != null)


## 清掉夹爪子节点，避免 free() 时泄漏
func _cleanup_gripper(sim: Node) -> void:
	var grip_root: Node = sim.get_node_or_null("Sim/SubViewport/World/Gripper")
	if grip_root == null:
		return
	for c in grip_root.get_children():
		grip_root.remove_child(c)
		c.free()


## 夹爪：朝向必须跟着末端连杆走，两指在工作平面内对开
func _test_gripper(sim: Node, config_type: int, jc: int, tag: String) -> void:
	var U: float = sim.MM_TO_UNIT
	var root: Node = sim.get_node_or_null("Sim/SubViewport/World/Gripper")
	_check("%s Gripper 节点存在" % tag, root != null)
	if root == null:
		return
	_check("%s 夹爪 = 掌座 + 两指" % tag, root.get_child_count() == 3,
		"实际 %d" % root.get_child_count())
	# 摆一个明确姿态再核对
	sim._on_mode_selected(1)
	for i in range(jc):
		sim._fk_angles[i] = 0.0
	sim._recompute()
	var frames: Array = sim._cg.joint_frames(
		sim._angles, sim._l1, sim._l2, sim._l3, config_type)
	var tip: Vector3 = sim._vec_to_godot(frames[frames.size() - 1])
	var prev: Vector3 = sim._vec_to_godot(frames[frames.size() - 2])
	var approach: Vector3 = (tip - prev).normalized()
	var palm: Node = root.get_child(0)
	var f1: Node = root.get_child(1)
	var f2: Node = root.get_child(2)
	_check("%s 夹爪全部可见" % tag, palm.visible and f1.visible and f2.visible)
	# 掌座应在末端球外侧、沿 approach 方向
	var palm_off: Vector3 = palm.position - tip
	_check("%s 掌座在末端外侧沿 approach" % tag,
		palm_off.normalized().dot(approach) > 0.999,
		"dot=%.4f" % palm_off.normalized().dot(approach))
	# 掌座局部 X 轴必须对齐 approach（这就是"夹爪显示末端角度"的核心）
	_check("%s 掌座 X 轴对齐 approach" % tag,
		palm.transform.basis.x.normalized().dot(approach) > 0.999,
		"dot=%.4f" % palm.transform.basis.x.normalized().dot(approach))
	# 两指应对称分布在 approach 两侧，连线垂直于 approach
	var span: Vector3 = f1.position - f2.position
	_check("%s 两指连线垂直 approach" % tag, absf(span.normalized().dot(approach)) < 1e-3,
		"dot=%.5f" % span.normalized().dot(approach))
	# 两指连线必须落在臂的工作平面内（即垂直于平面法向）
	var normal: Vector3 = sim._arm_plane_normal()
	_check("%s 两指在工作平面内" % tag, absf(span.normalized().dot(normal)) < 1e-3,
		"dot=%.5f" % span.normalized().dot(normal))
	# 张开度：加大应让两指间距变大
	sim._on_param_changed(0.0, "grip", null)
	var span_closed: float = (root.get_child(1).position - root.get_child(2).position).length()
	sim._on_param_changed(1.0, "grip", null)
	var span_open: float = (root.get_child(1).position - root.get_child(2).position).length()
	_check("%s 张开度加大则两指分开" % tag, span_open > span_closed + 1e-6,
		"闭=%.4f 开=%.4f" % [span_closed, span_open])
	_check("%s 最大张开 == GRIP_OPEN_MM*2" % tag,
		abs(span_open / U - sim.GRIP_OPEN_MM * 2.0) < 0.01,
		"实际 %.2f" % (span_open / U))
	# 改张开度不应动关节角（纯可视化）
	var ang_before: Array = sim._angles.duplicate()
	sim._on_param_changed(0.5, "grip", null)
	_check("%s 改张开度不动关节角" % tag, sim._angles == ang_before)
	# 越界时夹爪也应换告警材质，与连杆保持一致
	sim._on_mode_selected(0)
	sim._target = [9999.0, 0.0, 0.0, 0.0]
	sim._recompute()
	_check("%s 越界时夹爪用告警材质" % tag,
		root.get_child(0).material_override == sim._mat_link_bad)
	sim._target = [120.0, 0.0, 30.0, 0.0]
	sim._recompute()
	_check("%s 恢复后夹爪用常规材质" % tag,
		root.get_child(0).material_override == sim._mat_grip)
	# 4 轴：改姿态角 φ 必须让夹爪朝向跟着转
	if jc >= 4:
		sim._target = [120.0, 0.0, 30.0, 0.0]
		sim._recompute()
		var ap_a: Vector3 = root.get_child(0).transform.basis.x
		sim._target[3] = 60.0
		sim._recompute()
		var ap_b: Vector3 = root.get_child(0).transform.basis.x
		_check("%s 改 φ 夹爪朝向随之变" % tag, ap_a.angle_to(ap_b) > 0.05,
			"夹角 %.4f rad" % ap_a.angle_to(ap_b))
	# 状态行须给出夹爪读数
	var status: Node = sim.get_node_or_null("StatusPanel/Status")
	_check("%s 状态行含夹爪读数" % tag,
		status is Label and status.text.contains("夹爪"))
	_test_gripper_zero_l3(sim, config_type, jc, tag)


## L3=0（4 轴腕部连杆留空）时夹爪必须照样可见。
## 曾经的 bug：末段长度为 0 导致 approach 算不出来，夹爪被整个隐藏。
func _test_gripper_zero_l3(sim: Node, config_type: int, jc: int, tag: String) -> void:
	if jc < 4:
		return
	var root: Node = sim.get_node("Sim/SubViewport/World/Gripper")
	var l3_before: float = sim._l3
	# L3 置 0：腕心与末端重合，点链最后两点相同
	sim._on_param_changed(0.0, "L3", null)
	_check("%s L3=0 已生效" % tag, abs(sim._l3) < 1e-6, "实际 %.3f" % sim._l3)
	var frames: Array = sim._cg.joint_frames(
		sim._angles, sim._l1, sim._l2, sim._l3, config_type)
	var last_seg: float = frames[frames.size() - 1].distance_to(frames[frames.size() - 2])
	_check("%s L3=0 时末段长度为 0" % tag, last_seg < 1e-6, "实际 %.4f" % last_seg)
	# 夹爪三个构件都必须仍然可见
	var all_vis: bool = true
	for c in root.get_children():
		if not c.visible:
			all_vis = false
	_check("%s L3=0 夹爪仍可见" % tag, all_vis)
	# 朝向必须仍然有效（不能是零向量或 NaN）
	var ax: Vector3 = root.get_child(0).transform.basis.x
	_check("%s L3=0 夹爪朝向有效" % tag,
		ax.length() > 0.5 and is_finite(ax.x) and is_finite(ax.y) and is_finite(ax.z),
		"basis.x = %s" % str(ax))
	# 改姿态角 φ 时朝向须随之转动（证明用的是关节角而非退化的末段）
	sim._on_mode_selected(0)
	sim._target = [150.0, 0.0, 40.0, 0.0]
	sim._recompute()
	var a1: Vector3 = root.get_child(0).transform.basis.x
	sim._target[3] = 70.0
	sim._recompute()
	var a2: Vector3 = root.get_child(0).transform.basis.x
	_check("%s L3=0 改 φ 夹爪朝向随之变" % tag, a1.angle_to(a2) > 0.05,
		"夹角 %.4f rad" % a1.angle_to(a2))
	# 两指仍须垂直于 approach 且在工作平面内
	var span: Vector3 = root.get_child(1).position - root.get_child(2).position
	_check("%s L3=0 两指垂直 approach" % tag,
		absf(span.normalized().dot(a2.normalized())) < 1e-3,
		"dot=%.5f" % span.normalized().dot(a2.normalized()))
	# 还原 L3，避免影响后续断言
	sim._on_param_changed(l3_before, "L3", null)
	sim._on_mode_selected(1)


## 底盘几何：高度基准必须自洽，否则"机械臂装在车上哪"就是错的
func _test_chassis(sim: Node, config_type: int, jc: int, tag: String) -> void:
	var U: float = sim.MM_TO_UNIT
	var chassis: Node = sim.get_node_or_null("Sim/SubViewport/World/Chassis")
	_check("%s Chassis 节点存在" % tag, chassis != null)
	if chassis == null:
		return
	# 装到底盘偏前、垫高 90mm 的位置
	sim._mount = Vector3(60.0, 0.0, 90.0)
	sim._build_chassis()
	sim._build_grid()
	_check("%s 底盘有子节点" % tag, chassis.get_child_count() > 0)
	# 收集各类构件
	var boxes: Array = []
	var cyls: Array = []
	for c in chassis.get_children():
		if c is MeshInstance3D and c.mesh is BoxMesh:
			boxes.append(c)
		elif c is MeshInstance3D and c.mesh is CylinderMesh:
			cyls.append(c)
	# Box 构件：底盘板 + 前后两根支臂 + 安装柱 = 4
	_check("%s 底盘板/4支臂/安装柱共 6 个 Box" % tag, boxes.size() == 6,
		"实际 %d" % boxes.size())
	# 轮半径是固定常量。不再画轮轴，故所有 Cylinder 都应是轮子
	var wheel_r: float = sim.WHEEL_RADIUS_MM
	var wheels: Array = []
	for c in cyls:
		if abs(c.mesh.top_radius / U - wheel_r) < 0.01:
			wheels.append(c)
	# 四轮车：任何构型都是 4 个轮子（2 轴构型的底盘同样有左右维度）
	_check("%s 轮子数 == 4" % tag, wheels.size() == 4, "实际 %d" % wheels.size())
	_check("%s 不再画轮轴（Cylinder 全是轮子）" % tag, cyls.size() == 4,
		"Cylinder 共 %d 个" % cyls.size())
	if wheels.size() != 4:
		return
	# 底盘板顶面必须正好在机械臂底座下方 mount.z 处
	var deck: Node = boxes[0]
	var deck_top: float = deck.position.y / U + deck.mesh.size.y / U * 0.5
	_check("%s 底盘板顶面 == -mount.z" % tag, abs(deck_top - (-90.0)) < 0.01,
		"实际 %.2f 期望 -90" % deck_top)
	# 安装柱须从板顶面接到底座（顶=0，底=-mount.z）；它是最后一个 Box
	var post: Node = boxes[boxes.size() - 1]
	var post_top: float = post.position.y / U + post.mesh.size.y / U * 0.5
	var post_bot: float = post.position.y / U - post.mesh.size.y / U * 0.5
	_check("%s 安装柱顶端接底座(0)" % tag, abs(post_top) < 0.01, "实际 %.2f" % post_top)
	_check("%s 安装柱底端接板顶面(-90)" % tag, abs(post_bot - (-90.0)) < 0.01,
		"实际 %.2f" % post_bot)
	var w: Node = wheels[0]
	var wheel_top: float = w.position.y / U + w.mesh.top_radius / U
	var wheel_bot: float = w.position.y / U - w.mesh.top_radius / U
	# 四轮必须等高（同一个地面上）
	var same_height: bool = true
	for ww in wheels:
		if abs(ww.position.y - w.position.y) > 1e-6:
			same_height = false
	_check("%s 四轮等高" % tag, same_height)
	# 轮子悬在底盘板下方，与板底面之间必须留出间隙
	var deck_bot: float = deck.position.y / U - deck.mesh.size.y / U * 0.5
	_check("%s 轮上沿与板底面留有间隙" % tag,
		wheel_top < deck_bot - 0.01,
		"轮上沿 %.1f 板底面 %.1f" % [wheel_top, deck_bot])
	_check("%s 间隙 == _wheel_gap()" % tag,
		abs((deck_bot - wheel_top) - sim._wheel_gap()) < 0.01,
		"实际间隙 %.2f 期望 %.2f" % [deck_bot - wheel_top, sim._wheel_gap()])
	# 四轮须分布在四个角上：前后各两个、左右各两个，且整体以板心对称
	var sum_x: float = 0.0
	var sum_z: float = 0.0
	var fwd_set: Dictionary = {}
	var side_set: Dictionary = {}
	for ww in wheels:
		sum_x += ww.position.x
		sum_z += ww.position.z
		fwd_set["%.2f" % (ww.position.x / U)] = true
		side_set["%.2f" % (ww.position.z / U)] = true
	_check("%s 四轮前后各两组" % tag, fwd_set.size() == 2,
		"不同前后位置 %d 个" % fwd_set.size())
	_check("%s 四轮左右各两组" % tag, side_set.size() == 2,
		"不同左右位置 %d 个" % side_set.size())
	_check("%s 四轮以板心对称" % tag,
		abs(sum_x / 4.0 - deck.position.x) < 1e-6
			and abs(sum_z / 4.0 - deck.position.z) < 1e-6)
	# 轮子的**外缘**（而非轮心）必须落在板的前后范围内，
	# 否则轮子会探出车头车尾（之前只查轮心，漏掉过这个）
	var deck_half_len: float = deck.mesh.size.x / U * 0.5
	var wheel_outer: float = absf(w.position.x - deck.position.x) / U + wheel_r
	_check("%s 轮子外缘在板前后范围内" % tag, wheel_outer <= deck_half_len + 0.01,
		"轮外缘距板心 %.1f 板半长 %.1f" % [wheel_outer, deck_half_len])
	# 前后两轮不得相交：轮心间距必须大于轮直径。
	# 车高调大时轮径会变大，若不设上限前后轮会叠成一团（踩过）
	var fwd_positions: Array = []
	for k in fwd_set.keys():
		fwd_positions.append(str(k).to_float())
	var center_gap: float = absf(fwd_positions[0] - fwd_positions[1])
	_check("%s 前后轮不相交" % tag, center_gap > wheel_r * 2.0,
		"轮心间距 %.1f 轮直径 %.1f" % [center_gap, wheel_r * 2.0])
	# 轮子必须露出板的左右侧，否则俯视时被板遮住数不出个数
	var deck_half_w: float = deck.mesh.size.z / U * 0.5
	var wheel_inner: float = absf(w.position.z - deck.position.z) / U \
		-w.mesh.height / U * 0.5
	_check("%s 轮子露出板侧" % tag, wheel_inner >= deck_half_w - 0.01,
		"轮内沿距板心 %.1f 板半宽 %.1f" % [wheel_inner, deck_half_w])

	# 支臂：每个轮子各一根，从板底面接到轮心高度。
	# 关键是支臂必须**整根落在板的水平范围内**，否则会悬在板外并穿透板面（踩过）。
	for si in [1, 2, 3, 4]:
		var strut: Node = boxes[si]
		var strut_top: float = strut.position.y / U + strut.mesh.size.y / U * 0.5
		var strut_bot: float = strut.position.y / U - strut.mesh.size.y / U * 0.5
		_check("%s 支臂%d 顶端接板底面" % [tag, si], abs(strut_top - deck_bot) < 0.01,
			"支臂顶 %.2f 板底 %.2f" % [strut_top, deck_bot])
		# 支臂从板底面一直伸到轮心（不是只到轮上沿）
		_check("%s 支臂%d 底端到达轮心" % [tag, si],
			abs(strut_bot - w.position.y / U) < 0.01,
			"支臂底 %.2f 轮心 %.2f" % [strut_bot, w.position.y / U])
		# 支臂的左右外缘不得超出板的左右范围
		var s_side: float = absf(strut.position.z - deck.position.z) / U \
			+ strut.mesh.size.z / U * 0.5
		_check("%s 支臂%d 左右在板内" % [tag, si], s_side <= deck_half_w + 0.01,
			"支臂外缘 %.1f 板半宽 %.1f" % [s_side, deck_half_w])
		# 前后同理
		var s_fwd: float = absf(strut.position.x - deck.position.x) / U \
			+ strut.mesh.size.x / U * 0.5
		_check("%s 支臂%d 前后在板内" % [tag, si], s_fwd <= deck_half_len + 0.01,
			"支臂外缘 %.1f 板半长 %.1f" % [s_fwd, deck_half_len])
	# 轮下沿即地面，须与 _ground_level() 一致（碰地判定依赖这个）
	_check("%s 轮下沿 == _ground_level()" % tag,
		abs(wheel_bot - sim._ground_level()) < 0.01,
		"轮下沿 %.2f ground %.2f" % [wheel_bot, sim._ground_level()])
	# 安装偏移应让底盘中心落在底座后方 mount.x 处
	var deck_fwd: float = deck.position.x / U
	_check("%s 底盘中心在底座后方 mount.x" % tag, abs(deck_fwd - (-60.0)) < 0.01,
		"实际 %.2f 期望 -60" % deck_fwd)
	# 隐藏底盘：子节点清空，地面回到底座平面
	sim._on_chassis_toggled(false)
	_check("%s 隐藏底盘后无子节点" % tag, chassis.get_child_count() == 0,
		"实际 %d" % chassis.get_child_count())
	_check("%s 隐藏底盘后地面回到 0" % tag, abs(sim._ground_level()) < 1e-6)
	sim._on_chassis_toggled(true)
	_check("%s 重新显示底盘" % tag, chassis.get_child_count() > 0)
	# 碰地提示：末端压到地面以下时状态行须警告
	sim._on_mode_selected(1)
	for i in range(jc):
		sim._fk_angles[i] = 0.0
	# 把第二关节折到最下，尽量让末端低于地面
	sim._fk_angles[1] = -90.0
	sim._recompute()
	var status: Node = sim.get_node_or_null("StatusPanel/Status")
	_check("%s 状态行含底盘相对位置" % tag,
		status is Label and status.text.contains("末端相对底盘"))
	# 安装位置改动不应影响关节角（底盘纯视觉）
	var ang_before: Array = sim._angles.duplicate()
	sim._on_chassis_param_changed("mx", -120.0)
	sim._on_chassis_param_changed("mz", 200.0)
	_check("%s 改安装位置不动关节角" % tag, sim._angles == ang_before)
	_check("%s 改安装位置不动臂长" % tag, abs(sim._l1 - 120.0) < 1e-6)
	_test_chassis_height(sim, config_type, tag)
	# 收尾：清掉底盘子节点，避免 sim.free() 时留下未释放的 Mesh 实例
	sim._on_chassis_toggled(false)
	_cleanup_gripper(sim)
