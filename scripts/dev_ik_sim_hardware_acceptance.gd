extends SceneTree

## Hardware acceptance runner for the MCU-backed arm simulator.
##
## Example:
## godot --headless --path . --script scripts/dev_ik_sim_hardware_acceptance.gd -- \
##   --port=COM11 --link=usb_serial --samples=100 --fingerprint=0011223344556677

const LINK = preload("res://scripts/ik_sim_link.gd")
const PROTOCOL = preload("res://scripts/ik_sim_protocol.gd")
const TOOLCHAIN = preload("res://scripts/toolchain.gd")

var _hellos: Array[Dictionary] = []
var _states: Array[Dictionary] = []
var _errors: Array[String] = []
var _warnings: Array[String] = []


func _initialize() -> void:
	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	var port: String = str(options.get("port", ""))
	if port.is_empty():
		push_error("missing --port=COMx")
		quit(2)
		return
	var python: String = TOOLCHAIN.new().find_python()
	if python.is_empty():
		push_error("Python runtime is unavailable")
		quit(2)
		return
	var link = LINK.new()
	root.add_child(link)
	link.connected.connect(func(info: Dictionary) -> void:
		if info.has("hello"):
			_hellos.append(info["hello"]))
	link.state_received.connect(func(state: Dictionary) -> void: _states.append(state))
	link.link_error.connect(func(message: String) -> void: _errors.append(message))
	link.link_warning.connect(func(message: String) -> void: _warnings.append(message))
	var bridge: String = str(options.get("bridge", LINK.BRIDGE_SCRIPT))
	var started: bool = link.start(port, python, str(options.get("link", "unknown")), bridge)
	if not started or not await _wait_for_count(_hellos, 1, 3000):
		_finish(link, options, false, "HELLO timeout")
		return
	var hello: Dictionary = _hellos[0]
	var expected: String = str(options.get("fingerprint", "")).to_lower()
	var actual: String = (hello.get("fingerprint", PackedByteArray()) as PackedByteArray).hex_encode()
	if int(hello.get("firmware_type", 0)) != 1 \
			or int(hello.get("protocol_version", -1)) != PROTOCOL.VERSION:
		_finish(link, options, false, "firmware type or protocol version mismatch")
		return
	if not expected.is_empty() and expected != actual:
		_finish(link, options, false, "solver fingerprint mismatch")
		return
	var samples: int = clampi(int(options.get("samples", 100)), 1, 10000)
	for _i in range(samples):
		var before: int = _states.size()
		link.send_ping()
		if not await _wait_for_count(_states, before + 1, 1000):
			_finish(link, options, false, "PING timeout")
			return
	var latest: Dictionary = _states[-1]
	var before: int = _states.size()
	link.send_pose(latest.get("position", Vector3.ZERO), latest.get("rpy", Vector3.ZERO))
	if not await _wait_for_count(_states, before + 1, 1000):
		_finish(link, options, false, "STEP_POSE timeout")
		return
	latest = _states[-1]
	before = _states.size()
	link.send_joints(latest.get("angles", []), int(latest.get("joint_count", 0)))
	if not await _wait_for_count(_states, before + 1, 1000):
		_finish(link, options, false, "SET_JOINTS timeout")
		return
	before = _states.size()
	link.send_home()
	if not await _wait_for_count(_states, before + 1, 1000):
		_finish(link, options, false, "HOME timeout")
		return
	_finish(link, options, true, "all commands completed")


func _wait_for_count(items: Array, count: int, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while items.size() < count and _errors.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
	return items.size() >= count


func _finish(link, options: Dictionary, ok: bool, message: String) -> void:
	var latencies: Array[float] = []
	for state in _states:
		latencies.append(float(state.get("latency_ms", 0)))
	var latest: Dictionary = _states[-1] if not _states.is_empty() else {}
	var hello: Dictionary = _hellos[0] if not _hellos.is_empty() else {}
	var report: Dictionary = {
		"ok": ok and _errors.is_empty(),
		"message": message,
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"port": str(options.get("port", "")),
		"link_type": str(options.get("link", "unknown")),
		"samples_requested": int(options.get("samples", 100)),
		"state_responses": _states.size(),
		"rtt_ms_min": latencies.min() if not latencies.is_empty() else 0,
		"rtt_ms_avg": _average(latencies),
		"rtt_ms_max": latencies.max() if not latencies.is_empty() else 0,
		"crc_errors": int(latest.get("crc_errors", 0)),
		"dropped_sequences": int(latest.get("dropped_sequences", 0)),
		"timeouts": int(latest.get("timeouts", 0)),
		"protocol_version": int(hello.get("protocol_version", -1)),
		"algorithm_version": int(hello.get("algorithm_version", -1)),
		"firmware_type": int(hello.get("firmware_type", -1)),
		"joint_count": int(hello.get("joint_count", 0)),
		"orientation_mask": int(hello.get("orientation_mask", 0)),
		"position_dof": int(hello.get("position_dof", 0)),
		"orientation_dof": int(hello.get("orientation_dof", 0)),
		"fingerprint": (hello.get("fingerprint", PackedByteArray()) as PackedByteArray).hex_encode(),
		"warnings": _warnings.duplicate(),
		"errors": _errors.duplicate(),
	}
	var report_path: String = str(options.get("report", "user://ik_sim_hardware_acceptance.json"))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print(JSON.stringify(report, "  "))
	link.stop()
	root.remove_child(link)
	link.free()
	quit(0 if bool(report["ok"]) else 1)


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value in values:
		total += value
	return total / values.size()


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"samples": 100, "link": "unknown"}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1].to_int() if pair[0] == "samples" else pair[1]
	return result
