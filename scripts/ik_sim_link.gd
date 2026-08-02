class_name IkSimLink
extends Node

## Godot side of the MCU IK simulator connection.
## The Python process is deliberately a byte-only serial transport.

const PROTOCOL = preload("res://scripts/ik_sim_protocol.gd")
const BRIDGE_SCRIPT: String = "res://tools/ik_sim_serial_bridge.py"
const BAUD: int = 230400
const RESPONSE_TIMEOUT_MS: int = 200
const MAX_TIMEOUTS: int = 3
const IPC_CONNECT_TIMEOUT_MS: int = 2000
const IPC_RETRY_MS: int = 25

signal connected(info: Dictionary)
signal state_received(state: Dictionary)
signal link_error(message: String)
signal link_warning(message: String)
signal disconnected

var _pid: int = -1
var _ipc: StreamPeerTCP = null
var _ipc_port: int = 0
var _ipc_rx := PackedByteArray()
var _ipc_connect_deadline: int = 0
var _ipc_retry_after: int = 0
var _bridge_connected: bool = false
var _open_sent: bool = false
var _rx := PackedByteArray()
var _sequence: int = 0
var _pending_sequence: int = -1
var _pending_kind: int = 0
var _pending_payload := PackedByteArray()
var _pending_since: int = 0
var _timeouts: int = 0
var _pending_latest: Dictionary = {}
var _port: String = ""
var _link_type: String = "unknown"
var _crc_errors: int = 0
var _dropped_sequences: int = 0

func start(port: String, python_path: String = "python", link_type: String = "unknown",
		bridge_script: String = BRIDGE_SCRIPT) -> bool:
	stop()
	_port = port
	_link_type = link_type
	_crc_errors = 0
	_dropped_sequences = 0
	_timeouts = 0
	var deployed_bridge: String = _deploy_bridge(bridge_script)
	if deployed_bridge.is_empty():
		link_error.emit("无法释放串口桥接脚本")
		return false
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") != OK:
		link_error.emit("无法为串口桥接分配本机通信端口")
		return false
	_ipc_port = probe.get_local_port()
	probe.stop()
	_pid = OS.create_process(python_path,
		[deployed_bridge, "--ipc-port", str(_ipc_port)], false)
	if _pid <= 0:
		link_error.emit("无法启动串口桥接进程")
		return false
	_ipc_connect_deadline = Time.get_ticks_msec() + IPC_CONNECT_TIMEOUT_MS
	_begin_ipc_connect()
	return true


func _deploy_bridge(source_path: String) -> String:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return ""
	var data: PackedByteArray = source.get_buffer(source.get_length())
	source.close()
	var file_name: String = source_path.get_file()
	var target_path: String = "user://%s" % file_name
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return ""
	target.store_buffer(data)
	target.close()
	return ProjectSettings.globalize_path(target_path)

func stop() -> void:
	var pid := _pid
	var ipc := _ipc
	var was_active: bool = ipc != null or pid > 0
	# Detach first so signal handlers and _process cannot reuse a closing socket.
	_ipc = null
	_pid = -1
	_bridge_connected = false
	_open_sent = false
	_ipc_connect_deadline = 0
	_ipc_retry_after = 0
	if ipc != null and ipc.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var close_line := (JSON.stringify({"op": "close"}) + "\n").to_utf8_buffer()
		ipc.put_data(close_line)
		for _i in range(10):
			if pid <= 0 or not OS.is_process_running(pid):
				break
			ipc.poll()
			OS.delay_msec(10)
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	if ipc != null:
		ipc.disconnect_from_host()
	_pending_sequence = -1
	_pending_kind = 0
	_pending_payload.clear()
	_pending_latest.clear()
	_rx.clear()
	_ipc_rx.clear()
	if was_active:
		disconnected.emit()

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	_poll_bridge()
	if _pending_sequence >= 0 and Time.get_ticks_msec() - _pending_since > RESPONSE_TIMEOUT_MS:
		var timed_out_kind: int = _pending_kind
		var timed_out_payload: PackedByteArray = _pending_payload.duplicate()
		_pending_sequence = -1
		_pending_kind = 0
		_pending_payload.clear()
		_timeouts += 1
		if _timeouts >= MAX_TIMEOUTS:
			link_error.emit("MCU 求解器连续超时")
			stop()
		elif not _pending_latest.is_empty():
			_send_latest()
		else:
			# HELLO/PING and idle commands have no newer target waiting behind them.
			# Retry the same request so three consecutive 200 ms timeouts really
			# terminate the link instead of leaving it half-open forever.
			_send_request(timed_out_kind, timed_out_payload)

func send_hello() -> void:
	_send_request(PROTOCOL.CMD_HELLO, PackedByteArray())

func send_pose(position: Vector3, rpy: Vector3) -> void:
	_pending_latest = {"kind": PROTOCOL.CMD_STEP_POSE,
		"payload": PROTOCOL.pose_payload(position, rpy)}
	if _pending_sequence < 0:
		_send_latest()

func send_joints(angles: Array, joint_count: int) -> void:
	_pending_latest = {"kind": PROTOCOL.CMD_SET_JOINTS,
		"payload": PROTOCOL.joints_payload(angles, joint_count)}
	if _pending_sequence < 0:
		_send_latest()

func send_home() -> void:
	_pending_latest = {"kind": PROTOCOL.CMD_HOME, "payload": PackedByteArray()}
	if _pending_sequence < 0:
		_send_latest()

func send_ping() -> void:
	_pending_latest = {"kind": PROTOCOL.CMD_PING, "payload": PackedByteArray()}
	if _pending_sequence < 0:
		_send_latest()

func _send_latest() -> void:
	if _pending_latest.is_empty():
		return
	var request: Dictionary = _pending_latest.duplicate(true)
	_pending_latest.clear()
	_send_request(int(request["kind"]), request["payload"])

func _send_request(kind: int, payload: PackedByteArray) -> void:
	if not _bridge_connected or _pending_sequence >= 0:
		return
	var sequence: int = _next_sequence()
	var frame := PROTOCOL.pack_frame(kind, sequence, payload)
	if frame.is_empty():
		link_error.emit("求解器协议负载过大")
		return
	_send_bridge({"op": "write", "data": Marshalls.raw_to_base64(frame)})
	_pending_kind = kind
	_pending_payload = payload.duplicate()
	_pending_sequence = sequence
	_pending_since = Time.get_ticks_msec()


func _next_sequence() -> int:
	_sequence = (_sequence + 1) & 0xffff
	return _sequence

func _send_bridge(command: Dictionary) -> void:
	if _ipc == null or _ipc.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	_ipc.put_data((JSON.stringify(command) + "\n").to_utf8_buffer())


func _begin_ipc_connect() -> void:
	if _pid <= 0:
		return
	_ipc = StreamPeerTCP.new()
	_ipc.connect_to_host("127.0.0.1", _ipc_port)
	_ipc_retry_after = Time.get_ticks_msec() + IPC_RETRY_MS


func _poll_bridge() -> void:
	if _ipc == null:
		return
	_ipc.poll()
	var status: int = _ipc.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_bridge_connected = true
		if not _open_sent:
			_open_sent = true
			_send_bridge({"op": "open", "port": _port, "baud": BAUD})
		var available: int = _ipc.get_available_bytes()
		if available > 0:
			var read_result: Array = _ipc.get_data(available)
			if int(read_result[0]) == OK:
				_ipc_rx.append_array(read_result[1])
		_parse_bridge_lines()
		return
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	var now: int = Time.get_ticks_msec()
	if now < _ipc_connect_deadline and now >= _ipc_retry_after \
			and _pid > 0 and OS.is_process_running(_pid):
		_begin_ipc_connect()
		return
	if _ipc_connect_deadline > 0 and now >= _ipc_connect_deadline:
		link_error.emit("串口桥接本机通信连接超时")
		stop()


func _parse_bridge_lines() -> void:
	while true:
		var newline: int = _ipc_rx.find(10)
		if newline < 0:
			return
		var line_bytes: PackedByteArray = _ipc_rx.slice(0, newline)
		_ipc_rx = _ipc_rx.slice(newline + 1)
		var value: Variant = JSON.parse_string(line_bytes.get_string_from_utf8())
		if value is Dictionary:
			_handle_bridge(value)

func _handle_bridge(event: Dictionary) -> void:
	var kind: String = str(event.get("event", ""))
	if kind == "opened":
		connected.emit({"port": _port, "baud": BAUD, "link_type": _link_type})
		send_hello()
	elif kind == "data":
		var bytes: PackedByteArray = Marshalls.base64_to_raw(str(event.get("data", "")))
		_rx.append_array(bytes)
		_parse_frames()
	elif kind == "error":
		link_error.emit(str(event.get("message", "串口桥接错误")))
		stop()

func _parse_frames() -> void:
	while true:
		var start: int = _rx.find(PROTOCOL.DELIMITER)
		if start < 0:
			_rx.clear()
			return
		if start > 0:
			_rx = _rx.slice(start)
		# 每帧既有尾分隔符又有头分隔符，粘包时中间会出现 0x7e 0x7e。
		# 丢掉前一个帧尾，保留后一个帧头，不能把空帧连同真实起点一起吞掉。
		while _rx.size() > 1 and _rx[0] == PROTOCOL.DELIMITER \
				and _rx[1] == PROTOCOL.DELIMITER:
			_rx = _rx.slice(1)
		var end: int = _rx.find(PROTOCOL.DELIMITER, 1)
		if end < 0:
			return
		var frame: PackedByteArray = _rx.slice(0, end + 1)
		_rx = _rx.slice(end + 1)
		var parsed: Dictionary = PROTOCOL.parse_frame(frame)
		if not bool(parsed.get("ok", false)):
			if str(parsed.get("error", "")) == "crc":
				_crc_errors += 1
			link_warning.emit("MCU frame rejected: " + str(parsed.get("error", "unknown")))
			continue
		if int(parsed.get("sequence", -1)) != _pending_sequence:
			_dropped_sequences += 1
			continue
		parsed["request_kind"] = _pending_kind
		if not _handle_response(parsed):
			continue
		_pending_sequence = -1
		_pending_kind = 0
		_pending_payload.clear()
		_timeouts = 0
		if not _pending_latest.is_empty():
			_send_latest()

func _handle_response(parsed: Dictionary) -> bool:
	var kind: int = int(parsed.get("type", 0))
	var request_kind: int = int(parsed.get("request_kind", 0))
	var payload: PackedByteArray = parsed.get("payload", PackedByteArray())
	if kind == PROTOCOL.RESP_ERROR:
		link_error.emit("MCU solver rejected command 0x%02x" % request_kind)
		return true
	var expected_kind: int = PROTOCOL.RESP_HELLO \
		if request_kind == PROTOCOL.CMD_HELLO else PROTOCOL.RESP_STATE
	if kind != expected_kind:
		link_warning.emit("MCU response type does not match the pending command")
		return false
	if kind == PROTOCOL.RESP_HELLO:
		if payload.size() != 16 or int(payload[0]) != PROTOCOL.VERSION \
				or int(payload[3]) < 2 or int(payload[3]) > 6:
			link_warning.emit("MCU handshake response is invalid")
			return false
		var fingerprint := PackedByteArray()
		for i in range(8):
			fingerprint.append(payload[8 + i])
		connected.emit({"port": _port, "link_type": _link_type, "hello": {
			"protocol_version": int(payload[0]),
			"algorithm_version": int(payload[1]),
			"firmware_type": int(payload[2]),
			"joint_count": int(payload[3]),
			"orientation_mask": int(payload[4]),
			"position_dof": int(payload[5]),
			"orientation_dof": int(payload[6]),
			"fingerprint": fingerprint,
		}})
		return true
	if payload.size() != 5 + 8 + 24 + 24 + 16:
		link_warning.emit("MCU state response has an invalid payload length")
		return false
	var joint_count: int = int(payload[1])
	if joint_count < 2 or joint_count > 6:
		link_warning.emit("MCU state response has an invalid joint count")
		return false
	var state := {"status": int(payload[0]), "joint_count": int(payload[1]),
		"position_dof": int(payload[2]), "orientation_dof": int(payload[3]),
		"orientation_mask_bits": int(payload[4])}
	var at: int = 5
	var fingerprint := PackedByteArray()
	for _i in range(8):
		fingerprint.append(payload[at]); at += 1
	state["fingerprint"] = fingerprint
	var angles: Array = []
	for _i in range(6):
		angles.append(PROTOCOL.read_float32(payload, at)); at += 4
	state["angles"] = angles
	var position := Vector3(PROTOCOL.read_float32(payload, at),
		PROTOCOL.read_float32(payload, at + 4), PROTOCOL.read_float32(payload, at + 8))
	at += 12
	var rpy := Vector3(PROTOCOL.read_float32(payload, at + 8),
		PROTOCOL.read_float32(payload, at + 4), PROTOCOL.read_float32(payload, at))
	state["position"] = position
	state["rpy"] = rpy
	at += 12
	state["position_error"] = PROTOCOL.read_float32(payload, at)
	state["orientation_error"] = Vector3(
		PROTOCOL.read_float32(payload, at + 4),
		PROTOCOL.read_float32(payload, at + 8),
		PROTOCOL.read_float32(payload, at + 12))
	if not _state_numbers_are_finite(state):
		link_warning.emit("MCU state response contains NaN or infinity")
		return false
	state["latency_ms"] = Time.get_ticks_msec() - _pending_since
	state["request_kind"] = int(parsed.get("request_kind", 0))
	state["port"] = _port
	state["link_type"] = _link_type
	state["crc_errors"] = _crc_errors
	state["dropped_sequences"] = _dropped_sequences
	state["timeouts"] = _timeouts
	state_received.emit(state)
	return true


func _state_numbers_are_finite(state: Dictionary) -> bool:
	for value in state.get("angles", []):
		if not is_finite(float(value)):
			return false
	var position: Vector3 = state.get("position", Vector3(NAN, NAN, NAN))
	var rpy: Vector3 = state.get("rpy", Vector3(NAN, NAN, NAN))
	var orientation_error: Vector3 = state.get(
		"orientation_error", Vector3(NAN, NAN, NAN))
	return position.is_finite() and rpy.is_finite() and orientation_error.is_finite() \
		and is_finite(float(state.get("position_error", NAN)))
