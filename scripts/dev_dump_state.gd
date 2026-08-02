extends SceneTree

## 诊断：打印固件返回的完整 state 字段（PING/SET_JOINTS/STEP_POSE/HOME）。
##
## 运行：godot --headless --path . --script scripts/dev_dump_state.gd -- --port=COM3

const LINK = preload("res://scripts/ik_sim_link.gd")
const TOOLCHAIN = preload("res://scripts/toolchain.gd")

var _states: Array = []
var _hellos: Array = []
var _errors: Array = []


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var port: String = str(options.get("port", "COM3"))
	var python: String = TOOLCHAIN.new().find_python()
	if python.is_empty():
		quit(2)
		return
	var link = LINK.new()
	root.add_child(link)
	link.state_received.connect(func(state: Dictionary) -> void: _states.append(state))
	link.connected.connect(func(info: Dictionary) -> void:
		if info.has("hello"): _hellos.append(info["hello"]))
	link.link_error.connect(func(message: String) -> void: _errors.append(message))
	link.link_warning.connect(func(message: String) -> void: print("[warn] %s" % message))
	if not link.start(port, python, "usb_serial"):
		quit(1)
		return
	if not await _wait_hello(3000) or not _errors.is_empty():
		print("HELLO timeout")
		quit(1)
		return
	var hello: Dictionary = _hellos[0]
	print("HELLO: protocol=%d algo=%d firmware=%d joint_count=%d mask=%d pos_dof=%d ori_dof=%d" % [
		int(hello.get("protocol_version", 0)), int(hello.get("algorithm_version", 0)),
		int(hello.get("firmware_type", 0)), int(hello.get("joint_count", 0)),
		int(hello.get("orientation_mask", 0)), int(hello.get("position_dof", 0)),
		int(hello.get("orientation_dof", 0))])

	link.send_ping()
	await _wait_count(1, 2000)
	_dump("PING 初始", _states[-1])

	link.send_joints([30.0, -20.0, 10.0, 5.0, 0.0, 0.0], 4)
	await _wait_count(2, 2000)
	_dump("SET_JOINTS(30,-20,10,5)", _states[-1])

	link.send_home()
	await _wait_count(3, 2000)
	_dump("HOME", _states[-1])
	link.stop()
	root.remove_child(link)
	link.free()
	quit(0)


func _dump(tag: String, s: Dictionary) -> void:
	var fp: PackedByteArray = s.get("fingerprint", PackedByteArray())
	print("--- %s ---" % tag)
	print("  status=%d joint_count=%d pos_dof=%d ori_dof=%d mask_bits=%d" % [
		int(s.get("status", 0)), int(s.get("joint_count", 0)),
		int(s.get("position_dof", 0)), int(s.get("orientation_dof", 0)),
		int(s.get("orientation_mask_bits", 0))])
	print("  fingerprint=%s" % fp.hex_encode())
	print("  angles=%s" % _fmt(s.get("angles", [])))
	print("  position=%s rpy=%s" % [str(s.get("position", Vector3.ZERO)), str(s.get("rpy", Vector3.ZERO))])
	print("  pos_err=%.1f ori_err=%s latency=%.1fms" % [
		float(s.get("position_error", 0.0)), str(s.get("orientation_error", Vector3.ZERO)),
		float(s.get("latency_ms", 0.0))])


func _fmt(values: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for v in values:
		parts.append("%.2f" % float(v))
	return "[%s]" % ", ".join(parts)


func _wait_count(count: int, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while _states.size() < count and _errors.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return _states.size() >= count


func _wait_hello(timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while _hellos.is_empty() and _errors.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return not _hellos.is_empty()


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result
