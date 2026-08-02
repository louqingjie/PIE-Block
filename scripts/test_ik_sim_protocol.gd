extends SceneTree

const P = preload("res://scripts/ik_sim_protocol.gd")

var failures: int = 0

func _init() -> void:
	_test_pose_wire_order_and_sequence()
	_test_reserved_bytes_are_escaped()
	_test_crc_rejection()
	_test_malformed_and_oversize_frames()
	print("IK simulator protocol: %d failure(s)" % failures)
	quit(failures)

func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _test_pose_wire_order_and_sequence() -> void:
	var payload: PackedByteArray = P.pose_payload(Vector3(1.0, 2.0, 3.0),
		Vector3(4.0, 5.0, 6.0))
	var parsed: Dictionary = P.parse_frame(P.pack_frame(P.CMD_STEP_POSE, 0xbeef, payload))
	_check("pose frame parses", bool(parsed.get("ok", false)))
	_check("sequence remains uint16", int(parsed.get("sequence", -1)) == 0xbeef)
	var raw: PackedByteArray = parsed.get("payload", PackedByteArray())
	var values: Array[float] = []
	for i in range(6):
		values.append(P.read_float32(raw, i * 4))
	_check("wire pose order is XYZ Yaw Pitch Roll", values == [1.0, 2.0, 3.0, 6.0, 5.0, 4.0])

func _test_reserved_bytes_are_escaped() -> void:
	var payload := PackedByteArray([0xab, 0xbc, 0x40, 0x50, 0x49, 0x45, 0x49, 0x41, 0x50, 0x23])
	var frame: PackedByteArray = P.pack_frame(P.CMD_PING, 7, payload)
	var inner: PackedByteArray = frame.slice(1, frame.size() - 1)
	_check("extension header is never naked", not _contains(inner, PackedByteArray([0xab, 0xbc])))
	_check("IAP trigger is never naked", not _contains(inner, "@PIEIAP#".to_ascii_buffer()))
	_check("escaped payload round trips", P.parse_frame(frame).get("payload", PackedByteArray()) == payload)

func _test_crc_rejection() -> void:
	var frame: PackedByteArray = P.pack_frame(P.CMD_HOME, 9, PackedByteArray())
	frame[2] ^= 0x01
	_check("corrupt frame is rejected", not bool(P.parse_frame(frame).get("ok", false)))


func _test_malformed_and_oversize_frames() -> void:
	var oversize := PackedByteArray()
	oversize.resize(P.MAX_PAYLOAD + 1)
	_check("payload above protocol limit is rejected",
		P.pack_frame(P.CMD_PING, 1, oversize).is_empty())
	_check("missing delimiters are rejected",
		str(P.parse_frame(PackedByteArray([1, 2, 3])).get("error", "")) == "delimiter")
	_check("dangling escape is rejected",
		str(P.parse_frame(PackedByteArray([P.DELIMITER, P.ESCAPE, P.DELIMITER]))
			.get("error", "")) == "escape")

func _contains(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty() or needle.size() > haystack.size():
		return false
	for start in range(haystack.size() - needle.size() + 1):
		var equal: bool = true
		for i in range(needle.size()):
			if haystack[start + i] != needle[i]:
				equal = false
				break
		if equal:
			return true
	return false
