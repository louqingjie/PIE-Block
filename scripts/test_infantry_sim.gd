extends SceneTree

## 步兵 3D 仿真冒烟测试：场景可载入、四种驱动组合可跑、云台限幅、
## 单发拨弹出弹、底盘位姿变化、gimbal_params 与生成的 C 常量一致。
## 运行方式：godot --headless --path . --script scripts/test_infantry_sim.gd

const CG = preload("res://scripts/codegen/codegen_infantry.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _cfg(yaw_drive: String, pitch_drive: String, yaw_mid: String = "0",
		pitch_mid: String = "0") -> Dictionary:
	return {
		"channel": "36", "deadzone": "10",
		"l1_io": "P74 P24", "l1_dir": "正向",
		"l2_io": "P75 P25", "l2_dir": "正向",
		"r1_io": "P76 P26", "r1_dir": "正向",
		"r2_io": "P77 P27", "r2_dir": "正向",
		"normal_speed": "4000", "sprint_speed": "8000", "sprint_enabled": true,
		"booster_io": "P60 P61", "booster_dir": "正向",
		"yaw_drive": yaw_drive, "yaw_io": "MP74", "yaw_dir": "正向",
		"pitch_drive": pitch_drive, "pitch_io": "MP03", "pitch_dir": "正向",
		"yaw_mid_offset": yaw_mid, "pitch_mid_offset": pitch_mid,
		"arrow_key": "移动", "trigger_key": "E",
		"trigger_speed": "10000", "trigger_time": "250",
		"booster_key": "A", "friction_max_duty": "1100", "zero_enabled": true,
	}


func _initialize() -> void:
	print("=== 步兵 3D 仿真冒烟测试 ===\n")
	_test_gimbal_params_consistency()
	var packed: PackedScene = load("res://scenes/infantry_sim.tscn") as PackedScene
	_check("infantry_sim.tscn 可加载", packed != null)
	if packed == null:
		quit(1)
		return
	for case in [["舵机", "舵机"], ["电机", "舵机"], ["舵机", "电机"], ["电机", "电机"]]:
		await _test_drive_combo(packed, case[0], case[1])
	await _test_gimbal_clamp(packed)
	await _test_gimbal_geometry(packed)
	await _test_friction_geometry(packed)
	await _test_friction_color(packed)
	await _test_audio(packed)
	await _test_friction_switch(packed)
	await _test_fire(packed)
	await _test_visual_feed(packed)
	await _test_bullet_visual(packed)
	await _test_chassis(packed)
	await _test_turn_direction(packed)
	await _test_gimbal_direction(packed)
	await _test_c_turn_sign_consistency()
	await _test_camera_follow(packed)
	await _test_calib_writeback(packed)
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


## gimbal_params 抽出来后，生成的 C 里的限幅常量必须与它一致
func _test_gimbal_params_consistency() -> void:
	var cg = CG.new()
	for pair in [["0", "0"], ["30", "-45"], ["-90", "90"], ["90", "-90"]]:
		var cfg: Dictionary = _cfg("舵机", "舵机", pair[0], pair[1])
		var gp: Dictionary = cg.gimbal_params(cfg)
		var code: String = cg.generate(cfg)
		var tag: String = "归中角 %s/%s" % [pair[0], pair[1]]
		_check("%s: 生成的 Yaw 限幅与 gimbal_params 一致" % tag,
			code.contains("LIMIT_VALUE(floatDutyOfServo[0], %d, %d);"
				% [gp["yaw_lo"], gp["yaw_hi"]]),
			"期望 %d~%d" % [gp["yaw_lo"], gp["yaw_hi"]])
		_check("%s: 生成的 Pitch 限幅与 gimbal_params 一致" % tag,
			code.contains("LIMIT_VALUE(floatDutyOfServo[1], %d, %d);"
				% [gp["pitch_lo"], gp["pitch_hi"]]),
			"期望 %d~%d" % [gp["pitch_lo"], gp["pitch_hi"]])
		_check("%s: 生成的 midDutyOfServo 与 gimbal_params 一致" % tag,
			code.contains("midDutyOfServo[2] = {%d, %d}" % [gp["yaw_mid"], gp["pitch_mid"]]),
			"期望 %d, %d" % [gp["yaw_mid"], gp["pitch_mid"]])
		# 限幅边界必须落在舵机物理行程内
		_check("%s: 限幅边界不越出舵机行程" % tag,
			int(gp["yaw_lo"]) >= CodeGenBase.SERVO_DUTY_MIN
				and int(gp["yaw_hi"]) <= CodeGenBase.SERVO_DUTY_MAX
				and int(gp["pitch_lo"]) >= CodeGenBase.SERVO_DUTY_MIN
				and int(gp["pitch_hi"]) <= CodeGenBase.SERVO_DUTY_MAX)


## 生成的 C 代码里，摇杆与方向键给 turnSpeed 的符号约定必须一致。
## 这是本次修的 bug 根源：摇杆多了一个取反，导致推杆向右与按右方向键转向相反。
## 约定：turnSpeed > 0 = 向右转。
func _test_c_turn_sign_consistency() -> void:
	var cg = CG.new()
	for arrow in ["移动", "冲刺"]:
		for sprint in [true, false]:
			var cfg: Dictionary = _cfg("舵机", "舵机")
			cfg["arrow_key"] = arrow
			cfg["sprint_enabled"] = sprint
			var code: String = cg.generate(cfg)
			var tag: String = "方向键=%s 冲刺=%s" % [arrow, str(sprint)]
			# 摇杆水平轴不得取反
			_check("%s：摇杆不给 turnSpeed 取反" % tag,
				not code.contains("turnSpeed = -(int)((float)valueOfRoker[0][0]"),
				"生成的代码里仍有 turnSpeed = -(int)(...valueOfRoker[0][0]...)")
			_check("%s：摇杆水平轴正向映射到 turnSpeed" % tag,
				code.contains("turnSpeed = (int)((float)valueOfRoker[0][0]"))
			# 右方向键给正值、左方向键给负值，与摇杆同一约定
			var speed_var: String = "ultraSpeed" if arrow == "冲刺" else "maxSpeed"
			_check("%s：右方向键给 turnSpeed 正值" % tag,
				code.contains("valueOfKey[0][3] == 1)\n        turnSpeed = %s;" % speed_var))
			_check("%s：左方向键给 turnSpeed 负值" % tag,
				code.contains("valueOfKey[0][2] == 1)\n        turnSpeed = -%s;" % speed_var))


## 实例化并进树，返回已 _ready 的仿真节点。
## --script 模式下 add_child 不会立刻触发 _ready，必须等一帧。
func _spawn(packed: PackedScene, cfg: Dictionary) -> Node:
	var sim: Node = packed.instantiate()
	sim.set_config(cfg)
	root.add_child(sim)
	await process_frame
	return sim


func _despawn(sim: Node) -> void:
	root.remove_child(sim)
	sim.free()


func _test_drive_combo(packed: PackedScene, yaw: String, pitch: String) -> void:
	var tag: String = "Yaw=%s Pitch=%s" % [yaw, pitch]
	var sim: Node = await _spawn(packed, _cfg(yaw, pitch))
	_check("%s 实例化" % tag, sim is Control)
	if not sim is Control:
		return
	var robot: Node = sim.get_node_or_null("Sim/SubViewport/World/Robot")
	_check("%s 车体已生成" % tag, robot != null and robot.get_child_count() > 0,
		"子节点数 %d" % (robot.get_child_count() if robot != null else -1))
	_check("%s 枪口节点存在" % tag, sim._muzzle != null)
	# 空推 50 步：不该崩，云台占空比要留在合法范围
	for i in range(50):
		sim._step_once()
	_check("%s 空跑 50 步后云台 duty 合法" % tag,
		sim._duty_servo[0] >= CodeGenBase.SERVO_DUTY_MIN
			and sim._duty_servo[0] <= CodeGenBase.SERVO_DUTY_MAX
			and sim._duty_servo[1] >= CodeGenBase.SERVO_DUTY_MIN
			and sim._duty_servo[1] <= CodeGenBase.SERVO_DUTY_MAX,
		"duty=%s" % str(sim._duty_servo))
	_check("%s 静止时车没有自己动" % tag, sim._pos.length() < 1e-6,
		"pos=%s" % str(sim._pos))
	_despawn(sim)


## 摩擦轮稳态只能是 0/最大值，启停期间每 20ms 阻塞增减 1；B/C 不再调档
func _test_friction_switch(packed: PackedScene) -> void:
	var cfg: Dictionary = _cfg("舵机", "舵机")
	cfg["friction_max_duty"] = "800"
	var sim: Node = await _spawn(packed, cfg)
	sim._booster_key = 1
	sim._last_booster_key = 0
	sim._calculate_booster_control()
	_check("摩擦轮开启先输出 500", sim._duty_booster == 500)
	_check("摩擦轮开启进入 20ms 平滑阻塞序列", absf(sim._friction_ramp_ms - 20.0) < 1e-6)
	# 500→800 共 300 个 20ms 步进，再在 800 保持一个完整周期，共 6020ms。
	for i in range(602):
		sim._tick()
	_check("摩擦轮按 1 duty/20ms 平滑阻塞增速至 800", sim._duty_booster == 800,
		"实际 %d" % sim._duty_booster)
	_check("到达用户最大值后退出阻塞", sim._friction_ramp_ms <= 0.0)
	# 松开开关键后按 B/C，稳态不得改变。
	sim._booster_key = 0
	sim._calculate_booster_control()
	sim._key[1][1] = 1
	sim._key[1][2] = 1
	sim._calculate_booster_control()
	_check("B/C 不再控制摩擦轮占空比", sim._duty_booster == 800)
	# 再次按下开关键不能高速直接断电，必须逐级关闭。
	sim._booster_key = 1
	sim._last_booster_key = 0
	sim._calculate_booster_control()
	_check("摩擦轮关闭时先保持当前高速", sim._duty_booster == 800 and sim._status_booster == 0)
	for i in range(2):
		sim._tick()
	_check("关闭 20ms 后从 800 平滑降到 799", sim._duty_booster == 799)
	# 继续逐 duty 降至 500，再跳过 0~5% 区间归零，并在 0 保持一个周期。
	for i in range(602):
		sim._tick()
	_check("摩擦轮逐级关闭后归零", sim._duty_booster == 0 and sim._friction_ramp_direction == 0)
	_despawn(sim)


## 右摇杆推到底，云台必须停在 gimbal_params 给的边界上，不能越界
func _test_gimbal_clamp(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机", "30", "-20"))
	var gp: Dictionary = sim._gp
	# 直接灌摇杆值绕过输入采集，推足够多步确保撞到限幅
	for sign_v in [1, -1]:
		for i in range(400):
			sim._roker[1][0] = sign_v * 2047
			sim._roker[1][1] = sign_v * 2047
			sim._calculate_gimbal_controls()
			sim._limit_servo()
		var expect_yaw: int = int(gp["yaw_hi"]) if sign_v > 0 else int(gp["yaw_lo"])
		var expect_pitch: int = int(gp["pitch_hi"]) if sign_v > 0 else int(gp["pitch_lo"])
		_check("右摇杆推到%s Yaw 停在限幅 %d" % ["+" if sign_v > 0 else "-", expect_yaw],
			sim._duty_servo[0] == expect_yaw, "实际 %d" % sim._duty_servo[0])
		_check("右摇杆推到%s Pitch 停在限幅 %d" % ["+" if sign_v > 0 else "-", expect_pitch],
			sim._duty_servo[1] == expect_pitch, "实际 %d" % sim._duty_servo[1])
	# 归中：按下右摇杆应回到归中占空比
	sim._roker[1][0] = 0
	sim._roker[1][1] = 0
	sim._key[2][1] = 1
	sim._calculate_gimbal_controls()
	_check("按下右摇杆云台归中", sim._duty_servo[0] == int(gp["yaw_mid"])
		and sim._duty_servo[1] == int(gp["pitch_mid"]),
		"duty=%s 期望 %d/%d" % [str(sim._duty_servo), gp["yaw_mid"], gp["pitch_mid"]])
	_despawn(sim)


## 云台角度 -> 枪口朝向的几何断言。
## 目视截图判断俯仰角很不可靠（透视投影会缩短），故用向量核对。
func _test_gimbal_geometry(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	# 归中：枪口应水平朝车头方向（-Z），且高于底盘板
	sim._yaw_deg = 0.0
	sim._pitch_deg = 0.0
	sim._render_robot()
	var dir: Vector3 = - sim._muzzle.global_transform.basis.z.normalized()
	_check("归中时枪口朝车头（-Z）", dir.z < -0.999, "dir=%s" % str(dir))
	_check("枪口在底盘板之上",
		sim._muzzle.global_position.y > 0.06 and sim._muzzle.global_position.y < 0.2,
		"y=%.3f" % sim._muzzle.global_position.y)
	# Pitch 正角度应抬头
	sim._pitch_deg = 30.0
	sim._render_robot()
	dir = - sim._muzzle.global_transform.basis.z.normalized()
	_check("Pitch +30° 抬头", dir.y > 0.4, "dir=%s" % str(dir))
	_check("Pitch +30° 仰角约 30°", absf(rad_to_deg(asin(dir.y)) - 30.0) < 0.5,
		"仰角 %.1f°" % rad_to_deg(asin(dir.y)))
	sim._pitch_deg = -30.0
	sim._render_robot()
	dir = - sim._muzzle.global_transform.basis.z.normalized()
	_check("Pitch -30° 低头", dir.y < -0.4, "dir=%s" % str(dir))
	# Yaw 正角度应向右（+X）
	sim._pitch_deg = 0.0
	sim._yaw_deg = 45.0
	sim._render_robot()
	dir = - sim._muzzle.global_transform.basis.z.normalized()
	_check("Yaw +45° 云台向右（+X）", dir.x > 0.4, "dir=%s" % str(dir))
	_check("Yaw +45° 偏角约 45°",
		absf(rad_to_deg(atan2(dir.x, -dir.z)) - 45.0) < 0.5,
		"偏角 %.1f°" % rad_to_deg(atan2(dir.x, -dir.z)))
	# 车身转向后枪口朝向应跟着整体旋转
	sim._yaw_deg = 0.0
	sim._heading = deg_to_rad(90.0)
	sim._render_robot()
	dir = - sim._muzzle.global_transform.basis.z.normalized()
	_check("车身左转 90° 后枪口朝 -X", dir.x < -0.999, "dir=%s" % str(dir))
	_despawn(sim)

## 摩擦轮几何：转轴竖直（Pitch 水平时垂直地面），圆柱面与枪管相切
func _test_friction_geometry(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	sim._yaw_deg = 0.0
	sim._pitch_deg = 0.0
	sim._render_robot()
	_check("摩擦轮有两个", sim._friction_nodes.size() == 2,
		"实际 %d" % sim._friction_nodes.size())
	if sim._friction_nodes.size() != 2:
		_despawn(sim)
		return
	for i in range(2):
		var fw: MeshInstance3D = sim._friction_nodes[i]
		# CylinderMesh 的轴是局部 +Y；Pitch 水平时它在世界系里应竖直向上
		var axis: Vector3 = fw.global_transform.basis.y.normalized()
		_check("摩擦轮%d 转轴垂直于地面" % (i + 1), absf(axis.y) > 0.999,
			"axis=%s" % str(axis))
		# 轮心离枪管轴的距离 = 摩擦轮半径 + 枪管半径（圆柱面相切）
		var d: float = absf(fw.position.x)
		var expect: float = fw.mesh.top_radius + 0.012
		_check("摩擦轮%d 圆柱面与枪管相切" % (i + 1), absf(d - expect) < 1e-6,
			"轮心距 %.4f 期望 %.4f" % [d, expect])
		# 两轮应在枪管两侧
		_check("摩擦轮%d 在枪管侧面（不在轴线上）" % (i + 1), absf(fw.position.x) > 0.01,
			"x=%.4f" % fw.position.x)
	_check("两个摩擦轮在枪管两侧对称",
		absf(sim._friction_nodes[0].position.x + sim._friction_nodes[1].position.x) < 1e-6)
	# 轮子不能埋进云台盒子里（盒子半宽比轮心距还大，挡得死死的）。
	# 判据：轮子后缘要越过盒子前壁
	var fw0: MeshInstance3D = sim._friction_nodes[0]
	var wheel_back: float = fw0.position.z + fw0.mesh.top_radius
	var box_front: float = -0.06 * 1.2 * 0.5 # GIMBAL_SIZE * 1.2 / 2
	_check("摩擦轮露在云台盒子之外（不被埋住）", wheel_back < box_front,
		"轮后缘 %.4f 盒前壁 %.4f" % [wheel_back, box_front])
	# Pitch 抬起 30° 后转轴应随之倾斜 30°（跟着云台走，不再垂直地面）
	sim._pitch_deg = 30.0
	sim._render_robot()
	var tilted: Vector3 = sim._friction_nodes[0].global_transform.basis.y.normalized()
	_check("Pitch +30° 时摩擦轮转轴随云台倾斜 30°",
		absf(rad_to_deg(acos(clampf(tilted.y, -1.0, 1.0))) - 30.0) < 0.5,
		"倾角 %.1f°" % rad_to_deg(acos(clampf(tilted.y, -1.0, 1.0))))
	_despawn(sim)


## 音效：摩擦轮音高等于占空比数值，开火音效能起播
func _test_audio(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	var fp: AudioStreamPlayer = sim.get_node("FrictionAudio")
	var sp: AudioStreamPlayer = sim.get_node("ShotAudio")
	_check("摩擦轮播放器已装 AudioStreamGenerator", fp.stream is AudioStreamGenerator)
	_check("开火播放器已装 AudioStreamGenerator", sp.stream is AudioStreamGenerator)
	# 目标频率 = 占空比数值
	sim._duty_booster = 0
	_check("未启动时目标频率为 0（静音）", sim._friction_target_freq() == 0.0,
		"实际 %.1f" % sim._friction_target_freq())
	for duty in [500, 700, 900, 1100]:
		sim._duty_booster = duty
		_check("占空比 %d 对应 %dHz" % [duty, duty],
			absf(sim._friction_target_freq() - float(duty)) < 0.01,
			"实际 %.1f" % sim._friction_target_freq())
	# 低于 500 不发声（摩擦轮没启动）
	sim._duty_booster = 499
	_check("占空比 499 仍静音", sim._friction_target_freq() == 0.0)
	# 关掉音效后不应起播
	sim._audio_enabled = false
	sim._duty_booster = 1100
	sim._update_friction_audio(0.016)
	_check("关掉音效后摩擦轮不发声", not fp.playing)
	sim._play_shot_sound()
	_check("关掉音效后开火不发声", sim._shot_remain == 0)
	# 开火音效应排入待填样本
	sim._audio_enabled = true
	sim._play_shot_sound()
	_check("开火音效已排入待填样本", sim._shot_remain > 0,
		"remain=%d" % sim._shot_remain)
	_check("开火音效时长约 %.0fms" % (sim.SHOT_DURATION * 1000.0),
		sim._shot_remain == int(sim.SHOT_DURATION * sim.AUDIO_SAMPLE_RATE))
	# 停声应清干净
	sim._stop_audio()
	_check("停声后播放器停止且缓冲清空",
		not fp.playing and not sp.playing and sim._shot_remain == 0)
	# 正弦相位必须留在 [0, TAU)，否则长时间运行会丢精度
	sim._audio_enabled = true
	sim._duty_booster = 800
	for i in range(5):
		sim._update_friction_audio(0.016)
	_check("正弦相位保持归一化", sim._friction_phase >= 0.0 and sim._friction_phase < TAU,
		"phase=%.3f" % sim._friction_phase)
	sim._stop_audio()
	_despawn(sim)


## 摩擦轮颜色随占空比连续渐变：未启动冷色，500 橙色，1100 橙红色
func _test_friction_color(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	var mat: StandardMaterial3D = sim._mat_friction_wheels[0]
	# 未启动：冷色、不发光
	sim._duty_booster = 0
	sim._update_friction_color()
	_check("摩擦轮未启动时是冷色", mat.albedo_color.is_equal_approx(sim.FRICTION_COLD),
		"色 %s" % str(mat.albedo_color))
	_check("摩擦轮未启动时不发光", not mat.emission_enabled)
	# 500：橙色
	sim._duty_booster = 500
	sim._update_friction_color()
	var c500: Color = mat.albedo_color
	_check("占空比 500 时为橙色", c500.is_equal_approx(sim.FRICTION_HOT_LO),
		"色 %s" % str(c500))
	_check("占空比 500 时开始发光", mat.emission_enabled)
	# 1100：橙红色
	sim._duty_booster = 1100
	sim._update_friction_color()
	var c1100: Color = mat.albedo_color
	_check("占空比 1100 时为橙红色", c1100.is_equal_approx(sim.FRICTION_HOT_HI),
		"色 %s" % str(c1100))
	# 橙红比橙色更红：绿通道更低
	_check("1100 比 500 更偏红", c1100.g < c500.g,
		"g: %.2f -> %.2f" % [c500.g, c1100.g])
	# 中间值应落在两端之间，且单调
	var last_g: float = c500.g
	var monotonic: bool = true
	for duty in [600, 700, 800, 900, 1000, 1100]:
		sim._duty_booster = duty
		sim._update_friction_color()
		var g: float = mat.albedo_color.g
		if g > last_g + 1e-6:
			monotonic = false
		last_g = g
	_check("500->1100 颜色单调渐变（不跳变）", monotonic)
	sim._duty_booster = 800
	sim._update_friction_color()
	var c800: Color = mat.albedo_color
	_check("占空比 800 的颜色落在橙与橙红之间",
		c800.g < c500.g and c800.g > c1100.g, "g=%.3f" % c800.g)
	# 发光强度也应随占空比递增
	sim._duty_booster = 500
	sim._update_friction_color()
	var e_lo: float = mat.emission_energy_multiplier
	sim._duty_booster = 1100
	sim._update_friction_color()
	_check("发光强度随占空比递增", mat.emission_energy_multiplier > e_lo,
		"%.2f -> %.2f" % [e_lo, mat.emission_energy_multiplier])
	# 两个轮子都应被上色
	_check("两个摩擦轮都有材质",
		sim._friction_nodes[0].material_override != null
			and sim._friction_nodes[1].material_override != null)
	_despawn(sim)

## 扳机上升沿应产出 1 发弹丸，且主循环被阻塞 trigger_time
func _test_fire(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	# 先把摩擦轮置于用户设定的最大值，否则只是掉弹
	sim._status_booster = 1
	sim._duty_booster = sim._friction_max_duty
	var v_hot: float = sim._muzzle_speed()
	_check("摩擦轮满档时出膛速度接近上限", absf(v_hot - sim._muzzle_v_hi) < 0.01,
		"实际 %.2f 期望 %.2f" % [v_hot, sim._muzzle_v_hi])
	var before: int = sim._bullets.size()
	sim._trigger_key = 1
	sim._last_trigger_key = 0
	sim._fire()
	_check("扳机触发产出 1 发弹丸", sim._bullets.size() == before + 1,
		"%d -> %d" % [before, sim._bullets.size()])
	if sim._bullets.size() > 0:
		var b: Dictionary = sim._bullets[sim._bullets.size() - 1]
		var body: RigidBody3D = b["body"]
		_check("弹丸质量为 17mm 弹丸标称值", absf(body.mass - 0.0032) < 1e-6)
		_check("弹丸开启连续碰撞检测（防高速穿地）", body.continuous_cd)
		_check("弹丸初速方向朝枪口前方且大小正确",
			absf(body.linear_velocity.length() - v_hot) < 0.01,
			"速度 %.2f" % body.linear_velocity.length())
	# 阻塞语义：走一趟后应设上 _block_ms
	sim._block_ms = 0.0
	sim._trigger_key = 1
	sim._last_trigger_key = 0
	sim._step_once()
	_check("单发拨弹阻塞主循环 trigger_time", absf(sim._block_ms - 250.0) < 1e-6,
		"block=%.1f" % sim._block_ms)
	# 阻塞期间整个周期都不该推进（云台不动、占空比不变）
	var duty_before: int = sim._duty_servo[0]
	var booster_before: int = sim._duty_booster
	sim._roker[1][0] = 2047
	sim._tick()
	_check("阻塞期间云台停摆", sim._duty_servo[0] == duty_before,
		"%d -> %d" % [duty_before, sim._duty_servo[0]])
	_check("阻塞期间摩擦轮不渐变", sim._duty_booster == booster_before,
		"%d -> %d" % [booster_before, sim._duty_booster])
	_check("阻塞计时递减", absf(sim._block_ms - 240.0) < 1e-6, "block=%.1f" % sim._block_ms)
	# 摩擦轮未启动时应只掉弹
	sim._duty_booster = 0
	_check("摩擦轮未启动时只掉弹", absf(sim._muzzle_speed() - 2.0) < 0.01,
		"实际 %.2f" % sim._muzzle_speed())
	# 默认（无 feed_mode 字段）必须是阻塞开环，旧存档行为不变
	_check("默认拨弹模式为阻塞开环", not sim._visual_feed)
	_despawn(sim)


## 目视闭环模式：按住持续拨弹、松开即停，不阻塞主循环，按住期间按固定间隔连续出弹
func _test_visual_feed(packed: PackedScene) -> void:
	var cfg: Dictionary = _cfg("舵机", "舵机")
	cfg["feed_mode"] = "目视闭环"
	var sim: Node = await _spawn(packed, cfg)
	_check("目视闭环模式被解析", sim._visual_feed)
	# 按住：拨弹电机占空比 = 拨弹速度，且不阻塞主循环
	var before: int = sim._bullets.size()
	sim._trigger_key = 1
	sim._last_trigger_key = 0
	sim._feed_tick_ms = 0.0
	sim._step_once()
	_check("目视闭环按住时拨弹电机占空比 = 拨弹速度",
		sim._duty_motor[4] == 10000, "duty=%d" % sim._duty_motor[4])
	_check("目视闭环不阻塞主循环", sim._block_ms == 0.0, "block=%.1f" % sim._block_ms)
	# 按住期间主循环照常推进：云台跟随摇杆
	var servo_before: int = sim._duty_servo[0]
	sim._roker[1][0] = 2047
	sim._step_once()
	sim._roker[1][0] = 0
	_check("按住期间云台照常响应摇杆", sim._duty_servo[0] != servo_before,
		"%d -> %d" % [servo_before, sim._duty_servo[0]])
	# 按住 200ms（20 步）：应累计出弹（间隔 100ms，含最后一发不足整间隔的不出）
	for _i in range(19):
		sim._step_once()
	var fired: int = sim._bullets.size() - before
	_check("按住 200ms 出弹约 2 发（间隔 %.0f ms）" % sim.FEED_INTERVAL_MS,
		fired == 2, "实际 %d 发" % fired)
	_check("拨弹电机持续转动中", sim._duty_motor[4] == 10000,
		"duty=%d" % sim._duty_motor[4])
	# 松开：立即停转，不再出弹
	var before_release: int = sim._bullets.size()
	sim._trigger_key = 0
	sim._step_once()
	_check("目视闭环松开后拨弹电机停转", sim._duty_motor[4] == 0,
		"duty=%d" % sim._duty_motor[4])
	_check("目视闭环松开后不再出弹", sim._bullets.size() == before_release,
		"%d -> %d" % [before_release, sim._bullets.size()])
	_check("目视闭环松开后不阻塞", sim._block_ms == 0.0, "block=%.1f" % sim._block_ms)
	_despawn(sim)


## 弹丸应是绿色自发光，弹道最多同时显示五条
func _test_bullet_visual(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	var mat: StandardMaterial3D = sim._mat_bullet
	_check("弹丸材质开启自发光", mat.emission_enabled)
	_check("弹丸是绿色（绿通道最强）",
		mat.albedo_color.g > mat.albedo_color.r and mat.albedo_color.g > mat.albedo_color.b,
		"色 %s" % str(mat.albedo_color))
	_check("自发光颜色也是绿色",
		mat.emission.g > mat.emission.r and mat.emission.g > mat.emission.b,
		"emission %s" % str(mat.emission))
	_check("自发光强度大于 1（看得出发光）", mat.emission_energy_multiplier > 1.0,
		"强度 %.2f" % mat.emission_energy_multiplier)
	# 连打 12 发并全部回收，弹道折线不得超过 5 条
	sim._status_booster = 1
	sim._duty_booster = 1100
	for i in range(12):
		sim._fire()
		# 造两个采样点，否则 trail 太短会被 _retire_bullet 丢弃
		var b: Dictionary = sim._bullets[sim._bullets.size() - 1]
		var trail: PackedVector3Array = b["trail"]
		trail.append(trail[0] + Vector3(0.0, 0.0, -1.0))
		b["trail"] = trail
		sim._retire_bullet(sim._bullets.size() - 1)
	_check("弹道只保留最近 5 条", sim._tracers.size() == 5,
		"实际 %d 条" % sim._tracers.size())
	# 再算上在飞的，画出来的总条数仍不超过 5
	for i in range(3):
		sim._fire()
	sim._redraw_tracers()
	var node: MeshInstance3D = sim.get_node("Sim/SubViewport/World/Tracers")
	_check("含在飞弹丸时画出的弹道也不超过 5 条",
		node.mesh == null or node.mesh.get_surface_count() <= 5,
		"实际 %d 条" % (node.mesh.get_surface_count() if node.mesh != null else 0))
	_despawn(sim)


## 左摇杆推前后 / 左右，底盘位姿应相应变化
func _test_chassis(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	# 前进：左摇杆竖直推满
	for i in range(100):
		sim._roker[0][0] = 0
		sim._roker[0][1] = 2047
		sim._calculate_motor_controls()
		sim._integrate_chassis()
	_check("左摇杆前推后车向前走（-Z）", sim._pos.z < -0.01,
		"pos=%s" % str(sim._pos))
	_check("前进时航向不变", absf(sim._heading) < 1e-6, "heading=%f" % sim._heading)
	# 原地转向：竖直归零，水平推满
	sim._pos = Vector3.ZERO
	var h0: float = sim._heading
	for i in range(100):
		sim._roker[0][0] = 2047
		sim._roker[0][1] = 0
		sim._calculate_motor_controls()
		sim._integrate_chassis()
	_check("左摇杆横推后车原地转向", absf(sim._heading - h0) > 0.01,
		"heading %f -> %f" % [h0, sim._heading])
	_check("原地转向时几乎不平移", sim._pos.length() < 1e-3,
		"pos=%s" % str(sim._pos))
	# 冲刺：按下左摇杆后 baseSpeed 应用冲刺速度
	sim._roker[0][0] = 0
	sim._roker[0][1] = 2047
	sim._key[2][0] = 0
	sim._calculate_motor_controls()
	var normal: int = sim._base_speed
	sim._key[2][0] = 1
	sim._calculate_motor_controls()
	_check("按下左摇杆进入冲刺速度", sim._base_speed > normal,
		"%d -> %d" % [normal, sim._base_speed])
	# 归位
	sim._reset_pose()
	_check("车归位后位姿清零", sim._pos.length() < 1e-6 and absf(sim._heading) < 1e-6)
	_despawn(sim)


## 摇杆推右 / 按右方向键都必须向右转，且与接线方向配置无关。
## 用户的操作逻辑是固定的，改接线方向是硬件层面的事，不得反过来影响操作方向。
func _test_turn_direction(packed: PackedScene) -> void:
	# 四种接线配置：全正、全反、左右各反一个、混合
	var wiring: Array = [
		["正向", "正向", "正向", "正向"],
		["反向", "反向", "反向", "反向"],
		["反向", "正向", "反向", "正向"],
		["正向", "反向", "正向", "正向"],
	]
	for w in wiring:
		var cfg: Dictionary = _cfg("舵机", "舵机")
		cfg["l1_dir"] = w[0]
		cfg["l2_dir"] = w[1]
		cfg["r1_dir"] = w[2]
		cfg["r2_dir"] = w[3]
		var tag: String = "接线 %s" % "/".join(w)
		var sim: Node = await _spawn(packed, cfg)
		# 摇杆推右 -> 向右转（heading 减小，因为 heading 正值 = 向左）
		for i in range(60):
			sim._roker[0][0] = 2047
			sim._roker[0][1] = 0
			sim._calculate_motor_controls()
			sim._integrate_chassis()
		_check("%s：摇杆推右 = 向右转" % tag, sim._heading < -0.01,
			"heading=%.3f" % sim._heading)
		# 摇杆推左 -> 向左转
		sim._reset_pose()
		for i in range(60):
			sim._roker[0][0] = -2047
			sim._roker[0][1] = 0
			sim._calculate_motor_controls()
			sim._integrate_chassis()
		_check("%s：摇杆推左 = 向左转" % tag, sim._heading > 0.01,
			"heading=%.3f" % sim._heading)
		# 右方向键 -> 向右转（必须与摇杆同向）
		sim._reset_pose()
		sim._roker[0][0] = 0
		sim._roker[0][1] = 0
		for i in range(60):
			sim._key[0][2] = 0
			sim._key[0][3] = 1
			sim._calculate_motor_controls()
			sim._integrate_chassis()
		_check("%s：右方向键 = 向右转（与摇杆同向）" % tag, sim._heading < -0.01,
			"heading=%.3f" % sim._heading)
		# 左方向键 -> 向左转
		sim._reset_pose()
		for i in range(60):
			sim._key[0][2] = 1
			sim._key[0][3] = 0
			sim._calculate_motor_controls()
			sim._integrate_chassis()
		_check("%s：左方向键 = 向左转" % tag, sim._heading > 0.01,
			"heading=%.3f" % sim._heading)
		# 摇杆推前 -> 前进（-Z），同样与接线无关
		sim._reset_pose()
		for i in range(60):
			sim._key[0][2] = 0
			sim._key[0][3] = 0
			sim._roker[0][1] = 2047
			sim._calculate_motor_controls()
			sim._integrate_chassis()
		_check("%s：摇杆推前 = 前进" % tag, sim._pos.z < -0.01, "pos=%s" % str(sim._pos))
		_despawn(sim)


## 云台推杆方向也必须与接线配置无关
func _test_gimbal_direction(packed: PackedScene) -> void:
	for yd in ["正向", "反向"]:
		for pd in ["正向", "反向"]:
			var cfg: Dictionary = _cfg("舵机", "舵机")
			cfg["yaw_dir"] = yd
			cfg["pitch_dir"] = pd
			var tag: String = "云台接线 Yaw=%s Pitch=%s" % [yd, pd]
			var sim: Node = await _spawn(packed, cfg)
			for i in range(60):
				sim._roker[1][0] = 2047
				sim._roker[1][1] = 2047
				sim._calculate_gimbal_controls()
				sim._limit_servo()
				sim._sync_gimbal_from_duty()
			_check("%s：右摇杆推右 = 云台向右" % tag, sim._yaw_deg > 0.5,
				"yaw=%.2f" % sim._yaw_deg)
			_check("%s：右摇杆推上 = 云台抬头" % tag, sim._pitch_deg > 0.5,
				"pitch=%.2f" % sim._pitch_deg)
			_despawn(sim)


## 跟随模式下相机朝向应对齐车头；关掉跟随后相机朝向固定不再跟车转
func _test_camera_follow(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	var cam: Camera3D = sim.get_node("Sim/SubViewport/World/Camera3D")
	# 相机看向车身的水平方向（从相机指向枢轴）
	var look_dir := func() -> Vector2:
		var d: Vector3 = sim._cam_pivot - cam.position
		return Vector2(d.x, d.z).normalized()
	sim._reset_pose()
	sim._reset_view()
	var d0: Vector2 = look_dir.call()
	# 车头朝 -Z，相机正在车尾，故视线水平分量应严格朝 -Z（不带侧偏）
	_check("跟随模式初始视线沿车头正前方（-Z）", d0.y < -0.999,
		"look=%s（y 应接近 -1，偏离即说明相机有侧偏角）" % str(d0))
	# 车原地左转 90°，相机朝向应跟着转到正朝 -X
	sim._heading = deg_to_rad(90.0)
	sim._update_camera() # delta=0 表示立即对齐
	var d1: Vector2 = look_dir.call()
	_check("跟随模式下车转 90° 后视线正朝 -X", d1.x < -0.999,
		"look=%s" % str(d1))
	# 车转了多少度，视线就该转多少度（相机与车头的相对角恒定）
	_check("相机视线随车头等量旋转",
		absf(absf(d0.angle_to(d1)) - deg_to_rad(90.0)) < 0.02,
		"视线转过 %.2f°" % rad_to_deg(absf(d0.angle_to(d1))))
	# 平滑：delta 很小时不应立刻跳到目标
	sim._reset_pose()
	sim._reset_view()
	sim._heading = deg_to_rad(90.0)
	sim._update_camera(0.001)
	_check("相机朝向平滑跟随（不瞬移）",
		absf(sim._cam_heading) < deg_to_rad(5.0),
		"cam_heading=%.2f°" % rad_to_deg(sim._cam_heading))
	# 关掉跟随后车再转，相机朝向不变
	sim._reset_pose()
	sim._reset_view()
	sim._on_follow_toggled(false)
	var d2: Vector2 = look_dir.call()
	sim._heading = deg_to_rad(120.0)
	sim._update_camera(1.0)
	var d3: Vector2 = look_dir.call()
	_check("关掉跟随后相机朝向不跟车转", d2.distance_to(d3) < 1e-4,
		"%s -> %s" % [str(d2), str(d3)])
	# 切换跟随时视角应连续（不突变）
	sim._reset_pose()
	sim._reset_view()
	sim._heading = deg_to_rad(60.0)
	sim._update_camera()
	var d4: Vector2 = look_dir.call()
	sim._on_follow_toggled(false)
	var d5: Vector2 = look_dir.call()
	_check("关跟随瞬间视角连续", d4.distance_to(d5) < 1e-4,
		"%s -> %s" % [str(d4), str(d5)])
	sim._on_follow_toggled(true)
	var d6: Vector2 = look_dir.call()
	_check("开跟随瞬间视角连续", d4.distance_to(d6) < 1e-4,
		"%s -> %s" % [str(d4), str(d6)])
	_despawn(sim)


## 标定模式改归中角，应通过 config_changed 把新值发出去
func _test_calib_writeback(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	var got: Array = []
	sim.config_changed.connect(func(cfg: Dictionary) -> void: got.append(cfg))
	sim._on_mode_selected(1) # 云台标定
	sim._on_param_changed(25.0, "yawmid", null)
	_check("改归中角发出 config_changed", got.size() >= 1)
	if got.size() >= 1:
		_check("回填的 yaw_mid_offset 正确",
			str(got[got.size() - 1].get("yaw_mid_offset", "")) == "25",
			"实际 %s" % str(got[got.size() - 1].get("yaw_mid_offset", "")))
	# 改了归中角，限幅边界应随之平移
	var gp: Dictionary = sim._gp
	_check("归中角 25° 对应的限幅边界已重算",
		int(gp["yaw_mid_deg"]) == 25 and int(gp["yaw_mid"]) != CodeGenBase.SERVO_DUTY_MID,
		"mid_deg=%d mid=%d" % [gp["yaw_mid_deg"], gp["yaw_mid"]])
	_check("标定模式下云台停在新中位",
		sim._duty_servo[0] == int(gp["yaw_mid"]),
		"duty=%d 期望 %d" % [sim._duty_servo[0], gp["yaw_mid"]])
	_despawn(sim)
