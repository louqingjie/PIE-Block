extends SceneTree

const LINK = preload("res://scripts/ik_sim_link.gd")
const P = preload("res://scripts/ik_sim_protocol.gd")
const TC = preload("res://scripts/toolchain.gd")

var failures: int = 0

func _initialize() -> void:
	var export_config: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("exported application includes the serial bridge",
		export_config.contains("tools/ik_sim_serial_bridge.py")
		and not export_config.contains("tools/test_ik_sim_fake_bridge.py"))
	var link = LINK.new()
	root.add_child(link)
	var hellos: Array = []
	var states: Array = []
	var errors: Array[String] = []
	var warnings: Array[String] = []
	link.connected.connect(func(info: Dictionary) -> void:
		if info.has("hello"): hellos.append(info))
	link.state_received.connect(func(state: Dictionary) -> void: states.append(state))
	link.link_error.connect(func(message: String) -> void: errors.append(message))
	link.link_warning.connect(func(message: String) -> void: warnings.append(message))
	var payload := PackedByteArray([1, 2, 1, 4, 1, 3, 1, 0,
		0, 1, 2, 3, 4, 5, 6, 7])
	var frame: PackedByteArray = P.pack_frame(P.RESP_HELLO, 42, payload)
	var split: int = frame.size() / 2
	link._pending_sequence = 42
	link._pending_kind = P.CMD_HELLO
	link._rx.append_array(frame.slice(0, split))
	link._parse_frames()
	_check("half frame waits for completion", hellos.is_empty())
	link._rx.append_array(frame.slice(split))
	link._parse_frames()
	_check("completed half frame is parsed", hellos.size() == 1)

	var old_frame: PackedByteArray = P.pack_frame(P.RESP_HELLO, 43, payload)
	var latest_frame: PackedByteArray = P.pack_frame(P.RESP_HELLO, 44, payload)
	link._pending_sequence = 44
	link._pending_kind = P.CMD_HELLO
	link._rx.append_array(old_frame)
	link._rx.append_array(latest_frame)
	link._parse_frames()
	_check("sticky frames preserve second delimiter and matching sequence", hellos.size() == 2)

	var state_payload := PackedByteArray([P.STATUS_OK | P.STATUS_REACHED, 4, 3, 1, 1])
	state_payload.append_array(PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7]))
	for angle in [10.0, 20.0, 30.0, 40.0, 0.0, 0.0]:
		state_payload.append_array(P.pack_float32(angle))
	# Wire order is XYZ/Yaw/Pitch/Roll; the state exposed to Godot is named RPY.
	for value in [100.0, 200.0, 300.0, 60.0, 50.0, 40.0]:
		state_payload.append_array(P.pack_float32(value))
	for value in [1.5, 4.0, 5.0, 6.0]:
		state_payload.append_array(P.pack_float32(value))
	link._pending_sequence = 45
	link._pending_kind = P.CMD_STEP_POSE
	link._pending_since = Time.get_ticks_msec()
	link._rx.append_array(P.pack_frame(P.RESP_STATE, 45, state_payload))
	link._parse_frames()
	_check("state response is emitted", states.size() == 1)
	if states.size() == 1:
		_check("state converts wire YPR to named RPY",
			(states[0]["rpy"] as Vector3).is_equal_approx(Vector3(40.0, 50.0, 60.0)))
		_check("state preserves MCU joint angles", is_equal_approx(float(states[0]["angles"][3]), 40.0))

	link._pending_sequence = 50
	link.send_pose(Vector3(1, 0, 0), Vector3.ZERO)
	link.send_pose(Vector3(2, 0, 0), Vector3.ZERO)
	_check("waiting request keeps only the latest pose",
		is_equal_approx(P.read_float32(link._pending_latest["payload"], 0), 2.0))
	link.send_home()
	_check("home replaces a queued pose instead of being dropped",
		int(link._pending_latest.get("kind", 0)) == P.CMD_HOME)
	link.send_ping()
	_check("PING queues behind HELLO/state instead of being dropped",
		int(link._pending_latest.get("kind", 0)) == P.CMD_PING)
	link._pending_latest.clear()
	link._sequence = 0xffff
	_check("request sequence wraps from 65535 to zero", link._next_sequence() == 0)
	link._pending_sequence = -1
	link.send_pose(Vector3(3, 0, 0), Vector3.ZERO)
	_check("immediate latest request is copied before its queue is cleared",
		link._pending_latest.is_empty())

	# A matching sequence is not enough: malformed data must not complete the request.
	var malformed_payload: PackedByteArray = state_payload.duplicate()
	malformed_payload.resize(malformed_payload.size() - 1)
	link._pending_sequence = 49
	link._pending_kind = P.CMD_STEP_POSE
	link._rx.append_array(P.pack_frame(P.RESP_STATE, 49, malformed_payload))
	link._parse_frames()
	_check("truncated state does not complete the pending request", link._pending_sequence == 49)
	_check("truncated state is not emitted", states.size() == 1)
	var nan_payload: PackedByteArray = state_payload.duplicate()
	var nan_bytes: PackedByteArray = P.pack_float32(NAN)
	for i in range(4):
		nan_payload[13 + i] = nan_bytes[i]
	link._rx.append_array(P.pack_frame(P.RESP_STATE, 49, nan_payload))
	link._parse_frames()
	_check("NaN joint state does not complete the pending request", link._pending_sequence == 49)
	_check("NaN joint state is not emitted", states.size() == 1)
	_check("recoverable malformed states report warnings, not fatal errors",
		warnings.size() == 2 and errors.is_empty())

	# A corrupt frame must not poison the byte stream. A later matching frame is
	# still accepted, while stale sequences are counted and ignored.
	var crc_before: int = link._crc_errors
	var dropped_before: int = link._dropped_sequences
	var corrupt_frame: PackedByteArray = P.pack_frame(P.RESP_STATE, 49, state_payload)
	corrupt_frame[3] ^= 0x01
	link._rx.append_array(corrupt_frame)
	link._rx.append_array(P.pack_frame(P.RESP_STATE, 48, state_payload))
	link._rx.append_array(P.pack_frame(P.RESP_STATE, 49, state_payload))
	link._parse_frames()
	_check("CRC error is counted without completing the request",
		link._crc_errors == crc_before + 1)
	_check("stale response sequence is counted and ignored",
		link._dropped_sequences == dropped_before + 1)
	_check("valid frame after CRC/stale frames completes the request",
		link._pending_sequence == -1 and states.size() == 2)

	# A response with the right sequence but wrong type is recoverable and keeps
	# the request in flight. RESP_ERROR is fatal to the command and completes it.
	link._pending_sequence = 60
	link._pending_kind = P.CMD_PING
	link._rx.append_array(P.pack_frame(P.RESP_HELLO, 60, payload))
	link._parse_frames()
	_check("wrong response type does not complete the request", link._pending_sequence == 60)
	_check("wrong response type emits a warning", warnings.size() == 4)
	link._rx.append_array(P.pack_frame(P.RESP_ERROR, 60, PackedByteArray()))
	link._parse_frames()
	_check("MCU error response completes the rejected command", link._pending_sequence == -1)
	_check("MCU error response reports a fatal link error", errors.size() == 1)

	# HELLO/PING do not naturally have a newer target queued behind them. Verify
	# that the same command is retried twice and the third timeout closes the link.
	var retry_link = LINK.new()
	root.add_child(retry_link)
	var retry_errors: Array[String] = []
	retry_link.link_error.connect(func(message: String) -> void: retry_errors.append(message))
	retry_link._bridge_connected = true
	retry_link._send_request(P.CMD_HELLO, PackedByteArray())
	var retry_sequences: Array[int] = [retry_link._pending_sequence]
	for _i in range(2):
		retry_link._pending_since = Time.get_ticks_msec() - LINK.RESPONSE_TIMEOUT_MS - 1
		retry_link._process(0.0)
		retry_sequences.append(retry_link._pending_sequence)
	_check("idle HELLO is resent after each of the first two timeouts",
		retry_sequences[0] >= 0 and retry_sequences[1] != retry_sequences[0]
		and retry_sequences[2] != retry_sequences[1])
	_check("HELLO retries preserve the command and empty payload",
		retry_link._pending_kind == P.CMD_HELLO and retry_link._pending_payload.is_empty())
	retry_link._pending_since = Time.get_ticks_msec() - LINK.RESPONSE_TIMEOUT_MS - 1
	retry_link._process(0.0)
	_check("third idle HELLO timeout reports a link error", retry_errors.size() == 1)
	_check("third idle HELLO timeout closes the request", retry_link._pending_sequence == -1)
	root.remove_child(retry_link)
	retry_link.free()

	errors.clear()
	for seq in [51, 52, 53]:
		link._pending_sequence = seq
		link._pending_since = Time.get_ticks_msec() - LINK.RESPONSE_TIMEOUT_MS - 1
		link._process(0.0)
	_check("three consecutive response timeouts report a link error", errors.size() == 1)
	_check("three consecutive response timeouts clear the in-flight request",
		link._pending_sequence == -1)
	root.remove_child(link)
	link.free()

	var python: String = TC.new().find_python()
	if not python.is_empty():
		var fake_link = LINK.new()
		root.add_child(fake_link)
		var fake_hellos: Array = []
		var fake_states: Array = []
		fake_link.connected.connect(func(info: Dictionary) -> void:
			if info.has("hello"): fake_hellos.append(info))
		fake_link.state_received.connect(func(state: Dictionary) -> void:
			fake_states.append(state))
		_check("fake MCU bridge pipe starts", fake_link.start("FAKE_MCU", python,
			"virtual", "res://tools/test_ik_sim_fake_bridge.py"))
		_check("bridge resource is deployed to a physical user-data file",
			FileAccess.file_exists("user://test_ik_sim_fake_bridge.py"))
		var fake_deadline: int = Time.get_ticks_msec() + 1500
		while fake_hellos.is_empty() and Time.get_ticks_msec() < fake_deadline:
			await create_timer(0.01).timeout
		_check("end-to-end fake MCU completes HELLO", fake_hellos.size() == 1)
		fake_link.send_pose(Vector3(1, 2, 3), Vector3(4, 5, 6))
		fake_deadline = Time.get_ticks_msec() + 1500
		while fake_states.is_empty() and Time.get_ticks_msec() < fake_deadline:
			await create_timer(0.01).timeout
		_check("end-to-end fake MCU completes STEP_POSE", fake_states.size() == 1)
		if fake_states.size() == 1:
			_check("fake MCU state crosses JSON/Base64 and preserves named RPY",
				(fake_states[0]["rpy"] as Vector3).is_equal_approx(Vector3(40, 50, 60)))
		fake_link.stop()
		root.remove_child(fake_link)
		fake_link.free()

		var live_link = LINK.new()
		root.add_child(live_link)
		var bridge_errors: Array[String] = []
		live_link.link_error.connect(func(message: String) -> void: bridge_errors.append(message))
		_check("serial bridge pipe process starts", live_link.start("COM_PIE_BLOCK_TEST_MISSING", python))
		var bridge_pid: int = live_link._pid
		var bridge_deadline: int = Time.get_ticks_msec() + 1500
		while (bridge_errors.is_empty() and live_link._pid > 0
				and Time.get_ticks_msec() < bridge_deadline):
			await create_timer(0.05).timeout
		_check("serial bridge reports a port-open error", not bridge_errors.is_empty())
		_check("port error stops the bridge process cleanly",
			bridge_pid > 0 and live_link._pid == -1 and not OS.is_process_running(bridge_pid))
		live_link.stop() # Idempotent after automatic error cleanup.
		root.remove_child(live_link)
		live_link.free()
	print("IK simulator link: %d failure(s)" % failures)
	quit(failures)

func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)
