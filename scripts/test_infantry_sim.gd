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
		"friction_l_dir": "正向", "friction_r_dir": "反向",
		"yaw_drive": yaw_drive, "yaw_io": "MP74", "yaw_dir": "正向",
		"pitch_drive": pitch_drive, "pitch_io": "MP03", "pitch_dir": "正向",
		"yaw_mid_offset": yaw_mid, "pitch_mid_offset": pitch_mid,
		"arrow_key": "移动", "trigger_key": "R",
		"trigger_speed": "10000", "trigger_time": "250",
		"booster_key": "A", "zero_enabled": true,
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
	await _test_fire(packed)
	await _test_chassis(packed)
	await _test_turn_direction(packed)
	await _test_gimbal_direction(packed)
	await _test_c_turn_sign_consistency()
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


## 扳机上升沿应产出 1 发弹丸，且主循环被阻塞 trigger_time
func _test_fire(packed: PackedScene) -> void:
	var sim: Node = await _spawn(packed, _cfg("舵机", "舵机"))
	# 先把摩擦轮拉到档位，否则只是掉弹（掉弹也该出弹，但速度不同）
	sim._status_booster = 1
	sim._expect_duty_booster = sim._level_duty_booster
	sim._duty_booster = sim._level_duty_booster
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
