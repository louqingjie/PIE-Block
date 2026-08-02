class_name IkSimProtocol
extends RefCounted

## MCU IK 仿真链路协议。
## 线上姿态顺序固定为 X,Y,Z,Yaw,Pitch,Roll；内部调用使用命名字段。

const VERSION: int = 1
const DELIMITER: int = 0x7e
const ESCAPE: int = 0x7d
const ESCAPE_XOR: int = 0x20
const MAX_PAYLOAD: int = 240

const CMD_HELLO: int = 0x01
const CMD_STEP_POSE: int = 0x02
const CMD_SET_JOINTS: int = 0x03
const CMD_HOME: int = 0x04
const CMD_PING: int = 0x05

const RESP_HELLO: int = 0x81
const RESP_STATE: int = 0x82
const RESP_ERROR: int = 0xff

const STATUS_OK: int = 1
const STATUS_REACHED: int = 2
const STATUS_CLAMPED: int = 4
const STATUS_STALLED: int = 8
const STATUS_SINGULAR: int = 16
const STATUS_NUMERIC_ERROR: int = 32

static func crc16(data: PackedByteArray) -> int:

	var crc: int = 0xffff
	for value in data:
		crc ^= int(value) << 8
		for _i in range(8):
			crc = ((crc << 1) ^ 0x1021) & 0xffff if (crc & 0x8000) else (crc << 1) & 0xffff
	return crc

static func _needs_escape(value: int) -> bool:
	# Also escape extension-board header bytes and every byte in @PIEIAP#.
	return value in [DELIMITER, ESCAPE, 0xab, 0xbc, 0x40, 0x50, 0x49, 0x45, 0x41, 0x23]

static func _escape(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	for value in data:
		if _needs_escape(value):
			out.append(ESCAPE)
			out.append(value ^ ESCAPE_XOR)
		else:
			out.append(value)
	return out

static func _unescape(data: PackedByteArray) -> Variant:
	var out := PackedByteArray()
	var escaped := false
	for value in data:
		if escaped:
			out.append(value ^ ESCAPE_XOR)
			escaped = false
		elif value == ESCAPE:
			escaped = true
		else:
			out.append(value)
	if escaped:
		return null
	return out

static func _u16(value: int) -> PackedByteArray:
	return PackedByteArray([value & 0xff, (value >> 8) & 0xff])

static func _read_u16(data: PackedByteArray, at: int) -> int:
	if at + 1 >= data.size():
		return -1
	return int(data[at]) | (int(data[at + 1]) << 8)

static func pack_frame(kind: int, sequence: int, payload: PackedByteArray) -> PackedByteArray:
	if payload.size() > MAX_PAYLOAD:
		return PackedByteArray()
	var body := PackedByteArray([VERSION, kind, sequence & 0xff, (sequence >> 8) & 0xff, payload.size()])
	body.append_array(payload)
	var checksum := _u16(crc16(body))
	body.append_array(checksum)
	var frame := PackedByteArray([DELIMITER])
	frame.append_array(_escape(body))
	frame.append(DELIMITER)
	return frame

static func parse_frame(encoded: PackedByteArray) -> Dictionary:
	if encoded.size() < 2 or encoded[0] != DELIMITER or encoded[encoded.size() - 1] != DELIMITER:
		return {"ok": false, "error": "delimiter"}
	var raw_variant: Variant = _unescape(encoded.slice(1, encoded.size() - 1))
	if raw_variant == null:
		return {"ok": false, "error": "escape"}
	var raw: PackedByteArray = raw_variant
	if raw.size() < 7:
		return {"ok": false, "error": "short"}
	if raw[0] != VERSION:
		return {"ok": false, "error": "version"}
	var payload_len := int(raw[4])
	if payload_len > MAX_PAYLOAD or raw.size() != payload_len + 7:
		return {"ok": false, "error": "length"}
	var expected := _read_u16(raw, raw.size() - 2)
	var actual := crc16(raw.slice(0, raw.size() - 2))
	if expected < 0 or expected != actual:
		return {"ok": false, "error": "crc"}
	return {"ok": true, "version": int(raw[0]), "type": int(raw[1]),
		"sequence": _read_u16(raw, 2), "payload": raw.slice(5, 5 + payload_len)}

static func pack_float32(value: float) -> PackedByteArray:
	# 固件 C251 的 float 是 IEEE754 大端存储（实测 hex 42 c8 00 00 = 100.0），
	# 线上必须用大端，否则固件解析目标错（踩过：曾小端导致 STEP_POSE 目标失真）。
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.put_float(value)
	return stream.data_array

static func read_float32(data: PackedByteArray, at: int) -> float:
	if at + 4 > data.size():
		return NAN
	# 与 pack_float32 对称：按大端读取固件发送的 float。
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.data_array = data.slice(at, at + 4)
	stream.seek(0)
	return stream.get_float()

static func pose_payload(position: Vector3, rpy: Vector3) -> PackedByteArray:
	# Explicit wire order: X,Y,Z,Yaw,Pitch,Roll.
	var out := PackedByteArray()
	for value in [position.x, position.y, position.z, rpy.z, rpy.y, rpy.x]:
		out.append_array(pack_float32(float(value)))
	return out

static func joints_payload(angles: Array, joint_count: int) -> PackedByteArray:
	var out := PackedByteArray([clampi(joint_count, 0, 6)])
	for i in range(6):
		out.append_array(pack_float32(float(angles[i]) if i < joint_count and i < angles.size() else 0.0))
	return out
