extends SceneTree

const SCENE = preload("res://scenes/arm_sim.tscn")

var _fail: int = 0


class McuCommandProbe extends IkSimLink:
	var ping_count: int = 0
	var joints_count: int = 0

	func send_ping() -> void:
		ping_count += 1

	func send_joints(_angles: Array, _joint_count: int) -> void:
		joints_count += 1


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s %s" % [label, detail])
		_fail += 1


func _cfg(jc: int) -> Dictionary:
	var ios: Array = ["P60", "P62", "P64", "P66", "P74", "P75"]
	var axes: Array = ["Yaw", "Pitch", "Pitch", "Roll", "Pitch", "Roll"]
	var lens: Array = [0, 120, 90, 0, 40, 25]
	if jc == 2:
		axes = ["Yaw", "Pitch"]
		lens = [120, 90]
	var joints: Array = []
	for i in range(jc):
		joints.append({
			"io": ios[i], "dir": "正向", "axis": axes[i], "len": str(lens[i]),
			"offset": "0", "zero": str(10 + i * 5), "min": "-90", "max": "90",
		})
	return {
		"joint_count": jc, "joints": joints, "presets": [],
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y",
		"joy_z": "右X->末端Z", "joy_scale": "5",
		"keymove_speed": "2", "orientation_key_speed": "1",
		"rocker2_home_enabled": false, "keymove": [],
	}


func _fingerprint_bytes(sim: Node) -> PackedByteArray:
	var fingerprint_hex: String = sim._cg.solver_fingerprint(sim._cfg)
	var fingerprint := PackedByteArray()
	for i in range(0, fingerprint_hex.length(), 2):
		fingerprint.append(fingerprint_hex.substr(i, 2).hex_to_int())
	return fingerprint


func _initialize() -> void:
	for jc in [2, 4, 6]:
		await _test_joint_count(jc)
	await _test_config_editing()
	await _test_mcu_handshake_and_stale_gate()
	await _test_solver_stale_field_gates()
	await _test_responsive_overlays()
	await _test_remote_control()
	print("Result: %s" % ("PASS" if _fail == 0 else "%d failed" % _fail))
	quit(0 if _fail == 0 else 1)


func _test_joint_count(jc: int) -> void:
	var sim = SCENE.instantiate()
	sim.set_config({"ik": _cfg(jc), "engineer": _engineer(), "editable": true})
	root.add_child(sim)
	await process_frame
	var tag: String = "%d joints" % jc
	_check(tag + " config count", sim._jc == jc, str(sim._jc))
	_check(tag + " one link per joint", sim._link_nodes.size() == jc,
		str(sim._link_nodes.size()))
	_check(tag + " one joint marker per joint", sim._joint_nodes.size() == jc,
		str(sim._joint_nodes.size()))
	_check(tag + " angle count", sim._angles.size() == jc, str(sim._angles.size()))

	var chain: Dictionary = sim._cg.fk_chain(sim._angles, sim._joints, jc)
	var points: Array = chain["points"]
	_check(tag + " renders canonical FK point count", points.size() == jc + 1)
	var tip: Vector3 = points[jc]
	var targets: Dictionary = sim._tip_target(sim._angles)
	_check(tag + " target equals FK tip", tip.distance_to(targets["position"]) < 1.0e-4)
	_check(tag + " finite RPY", (targets["rpy"] as Vector3).is_finite())

	# Without a matching MCU, changing the target must not run a local IK fallback.
	var goal_angles: Array = []
	for i in range(jc):
		goal_angles.append(-15.0 + i * 7.0)
	var goal: Dictionary = sim._tip_target(goal_angles)
	sim._target = goal.duplicate(true)
	sim._angles.fill(0.0)
	sim._recompute()
	_check(tag + " arm freezes without MCU instead of local IK",
		sim._angles == _filled(jc, 0.0), str(sim._angles))
	# Rendering then follows an authoritative MCU response.
	sim._mcu_ready = true
	sim._on_mcu_state({"joint_count": jc, "angles": goal_angles,
		"position": goal["position"], "rpy": goal["rpy"], "status": 1,
		"orientation_mask_bits": 7, "fingerprint": _fingerprint_bytes(sim)})
	_check(tag + " MCU response updates joint state", sim._angles == goal_angles)
	var wrong_render_rpy: Vector3 = goal["rpy"] + Vector3(10.0, 0.0, 0.0)
	sim._on_mcu_state({"joint_count": jc, "angles": goal_angles,
		"position": goal["position"], "rpy": wrong_render_rpy, "status": 1,
		"orientation_mask_bits": 7, "fingerprint": _fingerprint_bytes(sim)})
	_check(tag + " rendering consistency check includes orientation",
		sim._render_model_mismatch)
	sim._on_mcu_state({"joint_count": jc, "angles": goal_angles,
		"position": goal["position"], "rpy": goal["rpy"], "status": 1,
		"orientation_mask_bits": 7, "fingerprint": _fingerprint_bytes(sim)})

	# Editing a length writes the canonical joint field and rebuilds the same number of links.
	var changed_index: int = jc - 1
	sim._on_param_changed(33.0, "len%d" % changed_index, null)
	_check(tag + " length edit writes joint config",
		absf(str(sim._joints[changed_index]["len"]).to_float() - 33.0) < 1.0e-4)
	_check(tag + " length slider marks MCU solver stale",
		sim._solver_stale and not sim._mcu_ready)
	_check(tag + " length edit preserves link count", sim._link_nodes.size() == jc)

	# Generic coordinate mapping always preserves all three robot coordinates.
	var mapped: Vector3 = sim._robot_to_godot(10.0, 20.0, 30.0)
	_check(tag + " XYZ mapping", mapped.distance_to(Vector3(0.1, 0.3, -0.2)) < 1.0e-5,
		str(mapped))
	_check(tag + " gripper exists", sim._grip_nodes.size() == 3)
	var vehicle: Node3D = sim.get_node(sim.P_VEHICLE)
	var arm_mount: Node3D = sim.get_node(sim.P_ARM_MOUNT)
	_check(tag + " arm hierarchy follows vehicle",
		sim.get_node(sim.P_ARM_ROOT).get_parent() == arm_mount
		and sim.get_node(sim.P_CHASSIS).get_parent() == vehicle)
	_check(tag + " target follows arm mount", sim.get_node(sim.P_GHOST).get_parent() == arm_mount)
	_check(tag + " trail remains in world", sim.get_node(sim.P_TRAIL).get_parent() == sim.get_node(sim.P_WORLD))

	root.remove_child(sim)
	sim.free()


func _engineer() -> Dictionary:
	return {
		"l1_io": "P60 P61", "l2_io": "P62 P63",
		"r1_io": "P64 P65", "r2_io": "P66 P67",
		"io_init": {"P60": "电机", "P62": "电机", "P64": "电机", "P66": "电机",
			"P74": "舵机", "P75": "舵机", "P76": "舵机", "P77": "舵机"},
		"key_map": [],
	}


func _test_config_editing() -> void:
	var sim = SCENE.instantiate()
	var cfg: Dictionary = _cfg(6)
	cfg["joints"][5]["len"] = "77"
	sim.set_config({"ik": cfg, "engineer": _engineer(), "editable": true})
	root.add_child(sim)
	await process_frame
	var mode_picker: OptionButton = sim.get_node(sim.P_MODE)
	var mode_names: String = " ".join([
		mode_picker.get_item_text(0), mode_picker.get_item_text(1), mode_picker.get_item_text(2)])
	_check("calibration top-level mode is removed", mode_picker.item_count == 3
		and mode_picker.get_item_text(0).contains("逆解编辑")
		and not mode_names.contains("标定"))
	_check("IK editor contains direct joint controls", sim._sliders.has("j0"))
	sim._on_param_changed(-30.0, "j0", null)
	_check("joint editing freezes without MCU", not is_equal_approx(float(sim._angles[0]), -30.0))
	_check("joint editing does not synthesize an actual pose", sim._solver_stale)
	var emitted: Array = []
	sim.config_changed.connect(func(payload: Dictionary) -> void: emitted.append(payload))
	sim._on_joint_count_config_changed("2")
	sim._on_joint_count_config_changed("6")
	_check("hidden joint slots survive count changes", str(sim._joints[5]["len"]) == "77")
	sim._on_mode_selected(1)
	_check("preset editor keeps diagnostics when no presets are enabled",
		not sim._diagnostic_labels.is_empty()
		and is_instance_valid(sim._diagnostic_labels[0])
		and not sim._diagnostic_labels[0].text.is_empty())
	sim._on_joint_option_changed(0, "io", "P76")
	_check("config edit emits structured ik", not emitted.is_empty()
		and emitted[emitted.size() - 1].has("ik"))
	_check("expansion joint requests servo init", emitted[emitted.size() - 1]["io_init"].get("P76", "") == "舵机")
	sim._on_gripper_field_changed("enabled", true)
	sim._on_gripper_field_changed("io", "P77")
	_check("gripper edit emits structured config",
		bool(emitted[emitted.size() - 1]["ik"]["gripper"]["enabled"])
		and str(emitted[emitted.size() - 1]["ik"]["gripper"]["io"]) == "P77")
	_check("expansion gripper requests servo init",
		emitted[emitted.size() - 1]["io_init"].get("P77", "") == "舵机")
	root.remove_child(sim)
	sim.free()

	var locked = SCENE.instantiate()
	locked.set_config({"ik": _cfg(2), "engineer": _engineer(), "editable": false})
	root.add_child(locked)
	await process_frame
	var before: String = str(locked._joints[0]["axis"])
	locked._on_joint_option_changed(0, "axis", "Roll")
	_check("stage two simulation is read only", str(locked._joints[0]["axis"]) == before)
	root.remove_child(locked)
	locked.free()


func _test_mcu_handshake_and_stale_gate() -> void:
	var sim = SCENE.instantiate()
	sim.set_config({"ik": _cfg(4), "engineer": _engineer(), "editable": true})
	root.add_child(sim)
	await process_frame
	var old_link: Node = sim._mcu_link
	sim.remove_child(old_link)
	old_link.free()
	var command_probe := McuCommandProbe.new()
	sim.add_child(command_probe)
	sim._mcu_link = command_probe
	var fingerprint: PackedByteArray = _fingerprint_bytes(sim)
	var hello: Dictionary = {"protocol_version": sim.IK_SIM_PROTOCOL.VERSION,
		"algorithm_version": sim._cg.SOLVER_ALGORITHM_WIRE_VERSION,
		"firmware_type": 1, "fingerprint": PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]),
		"orientation_mask": 1, "position_dof": 3, "orientation_dof": 1}
	sim._on_mcu_connected({"hello": hello})
	_check("mismatched MCU fingerprint keeps arm controls frozen", not sim._mcu_ready)
	hello["fingerprint"] = fingerprint
	hello["protocol_version"] = sim.IK_SIM_PROTOCOL.VERSION + 1
	sim._on_mcu_connected({"hello": hello})
	_check("unsupported MCU protocol keeps arm controls frozen", not sim._mcu_ready)
	hello["protocol_version"] = sim.IK_SIM_PROTOCOL.VERSION
	hello["algorithm_version"] = sim._cg.SOLVER_ALGORITHM_WIRE_VERSION + 1
	sim._on_mcu_connected({"hello": hello})
	_check("unsupported MCU algorithm keeps arm controls frozen", not sim._mcu_ready)
	hello["algorithm_version"] = sim._cg.SOLVER_ALGORITHM_WIRE_VERSION
	hello["firmware_type"] = 0
	sim._on_mcu_connected({"hello": hello})
	_check("production firmware cannot drive the simulator", not sim._mcu_ready)
	hello["firmware_type"] = 1
	hello["fingerprint"] = fingerprint
	sim._on_mcu_connected({"hello": hello})
	_check("matching HELLO keeps arm frozen until initial MCU state",
		not sim._mcu_ready and sim._mcu_hello_validated)
	_check("matching HELLO reads MCU state instead of overwriting its joints",
		command_probe.ping_count == 1 and command_probe.joints_count == 0)
	_check("matching HELLO exposes simulator firmware and fingerprint status",
		sim._mcu_firmware_type == "仿真" and sim._mcu_fingerprint_ok
		and sim._mcu_fingerprint == fingerprint.hex_encode())
	var home_angles: Array = sim._cg._joint_home_angles(sim._joints)
	var home_tip: Dictionary = sim._tip_target(home_angles)
	var initial_state := {"joint_count": 4, "angles": home_angles,
		"position": home_tip["position"], "rpy": home_tip["rpy"], "status": 1,
		"request_kind": sim.IK_SIM_PROTOCOL.CMD_PING,
		"orientation_mask_bits": 1, "fingerprint": fingerprint}
	sim._target = {"position": Vector3(999, 999, 999), "rpy": Vector3(90, 90, 90)}
	sim._on_mcu_state(initial_state)
	_check("initial MCU state enables control and owns the displayed target",
		sim._mcu_ready and not sim._solver_stale and sim._target == home_tip)
	sim._on_mcu_warning("recoverable frame warning")
	_check("recoverable protocol warnings do not freeze arm control", sim._mcu_ready)
	var angles_before: Array = sim._angles.duplicate()
	var bad_state := {"joint_count": 4, "angles": [NAN, 0.0, 0.0, 0.0],
		"position": Vector3.ZERO, "rpy": Vector3.ZERO, "status": 1,
		"orientation_mask_bits": 1, "fingerprint": fingerprint}
	sim._on_mcu_state(bad_state)
	_check("invalid MCU numbers freeze control and preserve the last pose",
		not sim._mcu_ready and sim._angles == angles_before)
	sim._on_mcu_connected({"hello": hello})
	var wrong_fingerprint: PackedByteArray = fingerprint.duplicate()
	wrong_fingerprint[0] ^= 0xff
	bad_state["angles"] = [0.0, 0.0, 0.0, 0.0]
	bad_state["fingerprint"] = wrong_fingerprint
	sim._on_mcu_state(bad_state)
	_check("state fingerprint changes freeze control and preserve the last pose",
		not sim._mcu_ready and sim._angles == angles_before)
	sim._on_mcu_connected({"hello": hello})
	sim._on_mcu_state(initial_state)
	_check("MCU HELLO owns the orientation mask",
		bool(sim._orientation_mask["roll"]) and not bool(sim._orientation_mask["pitch"])
		and not bool(sim._orientation_mask["yaw"]))
	_check("MCU status flags are decoded for students",
		sim._mcu_status_flags_text(sim.IK_SIM_PROTOCOL.STATUS_CLAMPED
			| sim.IK_SIM_PROTOCOL.STATUS_SINGULAR).contains("触及限位")
		and sim._mcu_status_flags_text(sim.IK_SIM_PROTOCOL.STATUS_CLAMPED
			| sim.IK_SIM_PROTOCOL.STATUS_SINGULAR).contains("奇异"))
	sim._on_joint_option_changed(0, "dir", "反向")
	_check("non-kinematic direction edit does not stale the MCU solver",
		not sim._solver_stale and sim._mcu_ready)
	sim._on_joint_option_changed(0, "axis", "Roll")
	_check("kinematic axis edit freezes control until reflashed",
		sim._solver_stale and not sim._mcu_ready)
	root.remove_child(sim)
	sim.free()


func _test_responsive_overlays() -> void:
	var sim = SCENE.instantiate()
	sim.set_config({"ik": _cfg(6), "engineer": _engineer(), "editable": true})
	root.add_child(sim)
	await process_frame
	for viewport_size in [Vector2(1280, 720), Vector2(1600, 900)]:
		sim.size = viewport_size
		await process_frame
		var side: Control = sim.get_node("SidePanel")
		var status: Control = sim.get_node("StatusPanel")
		var hint: Control = sim.get_node("HintLabel")
		var toolbar: Control = sim.get_node("TopPanel/HBox")
		_check("%s status stays on screen" % str(viewport_size),
			status.position.x >= 0.0 and status.position.y >= 0.0
			and status.position.x + status.size.x <= viewport_size.x
			and status.position.y + status.size.y <= viewport_size.y)
		_check("%s status does not overlap config sidebar" % str(viewport_size),
			status.position.x + status.size.x <= side.position.x)
		_check("%s hint stays below toolbar" % str(viewport_size),
			hint.position.y >= 44.0 and hint.position.y + hint.size.y <= viewport_size.y)
		_check("%s hint does not overlap config sidebar" % str(viewport_size),
			hint.position.x + hint.size.x <= side.position.x)
		_check("%s vehicle controls fit toolbar" % str(viewport_size),
			toolbar.size.x <= viewport_size.x)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.global_position = side.get_global_rect().get_center()
		var distance_before_ui_wheel: float = sim._cam_dist
		sim._handle_mouse_button(wheel)
		_check("%s sidebar wheel does not zoom camera" % str(viewport_size),
			is_equal_approx(sim._cam_dist, distance_before_ui_wheel))
		wheel.global_position = Vector2(80.0, viewport_size.y * 0.5)
		sim._handle_mouse_button(wheel)
		_check("%s viewport wheel still zooms camera" % str(viewport_size),
			sim._cam_dist > distance_before_ui_wheel)
	root.remove_child(sim)
	sim.free()


func _test_solver_stale_field_gates() -> void:
	var sim = SCENE.instantiate()
	sim.set_config({"ik": _cfg(4), "engineer": _engineer(), "editable": true})
	root.add_child(sim)
	await process_frame
	var all_kinematic_fields_stale := true
	for mutation in [["len", 121.0], ["zero", 11.0], ["min", -80.0], ["max", 80.0]]:
		sim._solver_stale = false
		sim._mcu_ready = true
		sim._on_joint_number_changed(0, mutation[0], mutation[1])
		all_kinematic_fields_stale = all_kinematic_fields_stale \
			and sim._solver_stale and not sim._mcu_ready
	_check("length, home and limits all stale the MCU solver", all_kinematic_fields_stale)
	sim._solver_stale = false
	sim._mcu_ready = true
	sim._calibrate_home_from_current()
	_check("calibrate-current-as-home also stales the MCU solver",
		sim._solver_stale and not sim._mcu_ready)
	sim._solver_stale = false
	sim._mcu_ready = true
	sim._on_joint_count_config_changed("3")
	_check("joint count changes stale the MCU solver", sim._solver_stale and not sim._mcu_ready)
	var stale_target: Dictionary = sim._target.duplicate(true)
	sim._inverse_mode = true
	sim._remote_snapshot = _remote([[0, 0], [2047, 0]])
	sim._controller_tick()
	_check("stale solver blocks inverse target input",
		sim._target == stale_target and not sim._mcu_ready)
	var all_non_kinematic_fields_remain_ready := true
	for mutation in [["io", "P77"], ["dir", "反向"]]:
		sim._solver_stale = false
		sim._mcu_ready = true
		sim._on_joint_option_changed(0, mutation[0], mutation[1])
		all_non_kinematic_fields_remain_ready = all_non_kinematic_fields_remain_ready \
			and not sim._solver_stale and sim._mcu_ready
	sim._solver_stale = false
	sim._mcu_ready = true
	sim._on_joint_number_changed(0, "offset", 12.0)
	all_non_kinematic_fields_remain_ready = all_non_kinematic_fields_remain_ready \
		and not sim._solver_stale and sim._mcu_ready
	sim._on_gripper_field_changed("enabled", true)
	all_non_kinematic_fields_remain_ready = all_non_kinematic_fields_remain_ready \
		and not sim._solver_stale and sim._mcu_ready
	_check("IO, direction, offset and gripper do not stale the MCU solver",
		all_non_kinematic_fields_remain_ready)
	root.remove_child(sim)
	sim.free()


func _remote(roker: Array = [[0, 0], [0, 0]], pressed: Dictionary = {}) -> Dictionary:
	return {
		"valueOfRoker": roker.duplicate(true),
		"valueOfKey": [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
		"pressed": pressed.duplicate(true), "pad_id": -1, "pad_name": "",
	}


func _test_remote_control() -> void:
	var sim = SCENE.instantiate()
	var engineer: Dictionary = _engineer()
	engineer["normal_speed"] = "4000"
	engineer["sprint_speed"] = "8000"
	engineer["sprint_enabled"] = true
	engineer["io_init"]["P74"] = "舵机"
	engineer["io_init"]["P75"] = "电机"
	engineer["key_map"] = [
		{"input": "A", "dir": "正", "mode": "增量", "param": "5", "target": "P60"},
		{"input": "B", "dir": "正", "mode": "直接", "param": "30", "target": "P74"},
		{"input": "右摇杆X", "dir": "正", "mode": "速度", "param": "6000", "target": "P75"},
	]
	var cfg: Dictionary = _cfg(2)
	cfg["presets"] = [{"enabled": true, "key": "A", "x": "20", "y": "30", "z": "40",
		"roll": "0", "pitch": "0", "yaw": "0"}]
	cfg["gripper"] = {
		"enabled": true, "io": "MP03", "dir": "正向", "open_angle": "45",
		"closed_angle": "-45", "initial_open": true, "key": "D"}
	sim.set_config({"ik": cfg, "engineer": engineer, "editable": true})
	root.add_child(sim)
	await process_frame
	sim._on_mode_selected(2)
	_check("gripper starts from configured open state", sim._gripper_open and sim._grip_open == 1.0)
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"D": true})
	sim._update_remote_gripper()
	_check("gripper key edge closes gripper", not sim._gripper_open and sim._grip_open == 0.0)
	sim._update_remote_gripper()
	_check("held gripper key toggles only once", not sim._gripper_open)
	sim._remote_snapshot = _remote()
	sim._update_remote_gripper()
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"D": true})
	sim._update_remote_gripper()
	_check("second gripper edge opens after release", sim._gripper_open)
	sim._gripper["dir"] = "反向"
	_check("reverse gripper mirrors command angle and duty",
		is_equal_approx(sim._gripper_command_angle(), -45.0) and sim._gripper_duty() == 500)

	var vehicle: Node3D = sim.get_node(sim.P_VEHICLE)
	var chassis: Node3D = sim.get_node(sim.P_CHASSIS)
	var chassis_before: Transform3D = chassis.transform
	var target_local_before: Dictionary = sim._target.duplicate(true)
	sim._remote_snapshot = _remote([[0, 2047], [0, 0]], {"ROCKER1": true})
	sim._controller_tick()
	_check("left rocker computes sprint chassis duty", sim._duty_chassis == [-8000, -8000, 8000, 8000],
		str(sim._duty_chassis))
	_check("vehicle advances at sprint speed", absf(sim._vehicle_pos.x - 0.16) < 1.0e-4,
		str(sim._vehicle_pos))
	_check("chassis geometry stays local while vehicle moves", chassis.transform == chassis_before
		and vehicle.position == sim._vehicle_pos)
	_check("vehicle motion preserves local IK target", sim._target == target_local_before)
	_check("forward motion spins all wheels", absf(sim._wheel_spin[0]) > 0.0
		and absf(sim._wheel_spin[3]) > 0.0)

	# 接线方向只改变输出 duty，不改变物理运动方向。
	sim._reset_vehicle_pose()
	sim._engineer["l1_dir"] = "反向"
	sim._engineer["l2_dir"] = "反向"
	sim._engineer["r1_dir"] = "反向"
	sim._engineer["r2_dir"] = "反向"
	sim._remote_snapshot = _remote([[0, 2047], [0, 0]])
	sim._controller_tick()
	_check("reversed wiring changes duty signs", sim._duty_chassis == [4000, 4000, -4000, -4000],
		str(sim._duty_chassis))
	_check("reversed wiring still moves forward", sim._vehicle_pos.x > 0.0)
	sim._reset_vehicle_pose()
	sim._sim_accum = 0.0
	sim._remote_snapshot = _remote([[0, 2047], [0, 0]])
	sim._step_controller(0.05)
	_check("fixed 10ms stepping integrates five cycles", absf(sim._vehicle_pos.x - 0.4) < 1.0e-4,
		str(sim._vehicle_pos))
	sim._reset_vehicle_pose()
	sim._remote_snapshot = _remote([[0, -2047], [0, 0]])
	sim._controller_tick()
	_check("backward input moves opposite heading", sim._vehicle_pos.x < 0.0)
	sim._reset_vehicle_pose()
	sim._on_chassis_toggled(false)
	sim._remote_snapshot = _remote([[0, 2047], [0, 0]])
	sim._controller_tick()
	_check("hidden chassis does not stop vehicle", sim._vehicle_pos.x > 0.0)
	sim._on_chassis_toggled(true)

	# 非零安装偏移随底盘绕中心转，不会成为底盘旋转中心。
	sim._reset_vehicle_pose()
	sim._mount = Vector3(100.0, 50.0, 90.0)
	sim._update_arm_mount()
	var arm_mount: Node3D = sim.get_node(sim.P_ARM_MOUNT)
	var mount_radius: float = Vector2(arm_mount.position.x, arm_mount.position.z).length()
	sim._remote_snapshot = _remote([[2047, 0], [0, 0]])
	sim._controller_tick()
	_check("pure turn keeps vehicle center fixed", sim._vehicle_pos.length() < 1.0e-6)
	_check("right input turns heading right", sim._vehicle_heading < 0.0)
	_check("arm mount rotates around chassis center",
		absf(Vector2(arm_mount.global_position.x, arm_mount.global_position.z).length()
			- mount_radius) < 1.0e-4)
	_check("turn gives opposite left/right wheel spin", sim._wheel_spin[0] * sim._wheel_spin[2] < 0.0)

	# 轨迹点使用世界坐标，后续车体变换不会改写旧点。
	sim._clear_trail()
	sim._render_arm()
	var world_trail_point: Vector3 = sim._trail_points[0]
	sim._vehicle_pos = Vector3(3.0, 0.0, -2.0)
	sim._vehicle_heading = 0.4
	sim._render_vehicle()
	_check("old trail point remains world-fixed", sim._trail_points[0] == world_trail_point)
	var local_target_before_modes: Dictionary = sim._target.duplicate(true)
	sim._on_mode_selected(0)
	var stationary_pos: Vector3 = sim._vehicle_pos
	sim._process(0.05)
	_check("non-controller mode does not integrate chassis", sim._vehicle_pos == stationary_pos)
	_check("mode changes preserve local target", sim._target == local_target_before_modes)

	# 跟随开关保持相机位置连续；归位清零车体与轮角并清除轨迹。
	sim._on_mode_selected(2)
	sim._update_camera()
	var camera: Camera3D = sim.get_node(sim.P_CAMERA)
	var camera_before: Vector3 = camera.position
	sim._on_follow_toggled(false)
	_check("disabling follow keeps camera position continuous",
		camera.position.distance_to(camera_before) < 1.0e-4)
	var free_camera_before: Vector3 = camera.position
	sim._on_follow_toggled(true)
	_check("enabling follow keeps camera position continuous",
		camera.position.distance_to(free_camera_before) < 1.0e-4)
	sim._reset_vehicle_pose()
	_check("vehicle reset clears pose and wheels", sim._vehicle_pos == Vector3.ZERO
		and is_zero_approx(sim._vehicle_heading) and sim._wheel_spin == [0.0, 0.0, 0.0, 0.0])
	_check("vehicle reset clears world trail", sim._trail_points.is_empty())

	# 预设按键命中时，本周期不再叠加同一个 A 键的按键移动。
	sim._cfg["keymove"][0] = {"plus": "A", "minus": "不使用"}
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"A": true})
	var hit: bool = sim._apply_remote_preset()
	_check("preset key has inverse-mode priority", hit
		and (sim._target["position"] as Vector3).is_equal_approx(Vector3(20.0, 30.0, 40.0)),
		str(sim._target))
	_check("preset does not change gripper state", sim._gripper_open)
	var target_before: Dictionary = sim._target.duplicate(true)
	sim._remote_snapshot = _remote([[0, 0], [2047, 0]])
	sim._apply_remote_ik_inputs()
	_check("right rocker follows configured inverse mappings",
		absf(sim._target["position"].x - target_before["position"].x - 5.0) < 1.0e-4
		and absf(sim._target["position"].z - target_before["position"].z - 5.0) < 1.0e-4,
		str(sim._target))

	# PC 只维护并发送目标，不判断可达性。超出臂展的目标也必须交给 MCU，
	# 由 MCU 返回停滞、限位或不可达状态。
	var reach: float = sim._arm_reach()
	sim._target = {"position": Vector3(reach, 0.0, 0.0), "rpy": Vector3.ZERO}
	sim._cfg["joy_x"] = "右X->末端X"
	sim._cfg["joy_y"] = "右Y->末端Y"
	sim._cfg["joy_z"] = "右Y->末端Z"
	sim._remote_snapshot = _remote([[0, 0], [-2047, 0]])
	sim._apply_remote_ik_inputs()
	_check("fully extended target accepts inward controller input",
		float(sim._target["position"].x) < reach, str(sim._target))
	var inward_target: Dictionary = sim._target.duplicate(true)
	sim._remote_snapshot = _remote([[0, 0], [2047, 0]])
	sim._apply_remote_ik_inputs()
	_check("PC does not reject an outward target beyond arm reach",
		float(sim._target["position"].x) > float(inward_target["position"].x), str(sim._target))
	sim._target = inward_target.duplicate(true)
	sim._cfg["joy_x"] = "不使用"
	sim._remote_snapshot = _remote([[0, 0], [-2047, 0]])
	sim._apply_remote_ik_inputs()
	_check("disabled endpoint rocker mapping leaves that axis unchanged",
		is_equal_approx(float(sim._target["position"].x), float(inward_target["position"].x)), str(sim._target))

	# 六维姿态按键使用独立角度步长；Roll/Yaw 环绕，Pitch 钳制。
	sim._orientation_mask = {"roll": true, "pitch": true, "yaw": true}
	sim._cfg["orientation_key_speed"] = "5"
	sim._cfg["keymove"][3] = {"plus": "A", "minus": "不使用"}
	sim._cfg["keymove"][4] = {"plus": "B", "minus": "不使用"}
	sim._cfg["keymove"][5] = {"plus": "不使用", "minus": "C"}
	sim._target = {"position": Vector3.ZERO, "rpy": Vector3(179.0, 89.0, -179.0)}
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"A": true, "B": true, "C": true})
	sim._apply_remote_ik_inputs()
	var moved_rpy: Vector3 = sim._target["rpy"]
	_check("orientation keys wrap Roll/Yaw and clamp Pitch",
		moved_rpy.is_equal_approx(Vector3(-176.0, 90.0, 176.0)), str(moved_rpy))
	sim._target = {"position": Vector3(reach, 0.0, 0.0), "rpy": Vector3.ZERO}
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"B": true})
	sim._apply_remote_ik_inputs()
	_check("orientation input remains available for a target at full reach",
		is_equal_approx((sim._target["rpy"] as Vector3).y, 5.0))
	sim._orientation_mask["roll"] = false
	sim._target["rpy"] = Vector3.ZERO
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"A": true})
	sim._apply_remote_ik_inputs()
	_check("uncontrollable orientation input is ignored",
		is_zero_approx((sim._target["rpy"] as Vector3).x))

	# ROCKER2 回中在两种模式下共用上升沿，并且不重置夹爪、底盘或辅助 IO。
	sim._cfg["rocker2_home_enabled"] = true
	sim._angles.fill(35.0)
	var gripper_before_home: bool = sim._gripper_open
	var chassis_before_home: Array = sim._duty_chassis.duplicate()
	sim._duty_aux_motor[5] = 3210
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"ROCKER2": true})
	_check("ROCKER2 first edge returns arm home", sim._update_remote_home())
	var home_angles: Array = sim._cg._joint_home_angles(sim._joints)
	_check("home does not locally change joints without MCU", sim._angles != home_angles)
	_check("home preserves gripper chassis and auxiliary state",
		sim._gripper_open == gripper_before_home and sim._duty_chassis == chassis_before_home
		and sim._duty_aux_motor[5] == 3210)
	sim._angles.fill(20.0)
	_check("held ROCKER2 does not retrigger", not sim._update_remote_home()
		and sim._angles != home_angles)
	sim._remote_snapshot = _remote()
	sim._update_remote_home()
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"ROCKER2": true})
	_check("ROCKER2 retriggers after release", sim._update_remote_home()
		and sim._angles != home_angles)

	# 模式键按下边沿只翻转一次，释放后才允许下一次翻转。
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"R": true})
	sim._update_remote_mode()
	_check("mode key first edge enters forward mode", not sim._inverse_mode)
	sim._update_remote_mode()
	_check("held mode key does not toggle repeatedly", not sim._inverse_mode)
	sim._remote_snapshot = _remote()
	sim._update_remote_mode()
	sim._angles = [12.0, -8.0]
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"R": true})
	sim._update_remote_mode()
	_check("second mode-key edge returns to inverse mode", sim._inverse_mode)
	_check("returning to inverse does not synthesize MCU pose", not sim._mcu_ready)

	sim._inverse_mode = false
	sim._mode_key_held = false
	sim._requested_angles = sim._angles.duplicate()
	var angle_before: float = sim._angles[0]
	sim._remote_snapshot = _remote([[0, 0], [2047, 0]], {"A": true, "B": true})
	sim._apply_forward_mapping()
	_check("forward mapping updates only the requested joint angle",
		absf(sim._requested_angles[0] - angle_before - 5.0) < 1.0e-4
		and is_equal_approx(sim._angles[0], angle_before))
	_check("forward direct mapping updates auxiliary servo",
		int(sim._duty_aux_servo[4]) == sim._cg._servo_angle_to_duty(30))
	_check("forward speed mapping updates auxiliary motor", sim._duty_aux_motor[5] == 6000,
		str(sim._duty_aux_motor[5]))

	sim._angles[0] = 89.0
	sim._remote_snapshot = _remote([[0, 0], [0, 0]], {"A": true})
	sim._controller_tick()
	_check("forward controller freezes without MCU", absf(sim._angles[0] - 89.0) < 1.0e-4,
		str(sim._angles[0]))
	sim._inverse_mode = true
	sim._duty_aux_motor[5] = 4321
	sim._remote_snapshot = _remote()
	sim._controller_tick()
	_check("inverse mode clears forward-only auxiliary motors", sim._duty_aux_motor[5] == 0)

	root.remove_child(sim)
	sim.free()


func _filled(count: int, value: float) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append(value)
	return out
