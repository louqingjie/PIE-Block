class_name PhonePoseReceiver
extends Node

## 手机传感器位姿接收器。
## 启动 WebSocket 服务端，接收 Android APP 发来的位姿数据，
## 通过信号传递给 arm_sim 注入 _target。
##
## 协议（JSON，UTF-8 文本帧）：
##   手机 -> Godot:
##     {"type":"pose","position":{"x":0,"y":0,"z":0},"rpy":{"roll":0,"pitch":0,"yaw":0},"ts":12345}
##     {"type":"reset_origin"}  -- 请求 Godot 重新标定原点
##     {"type":"hello","app":"PieBlockRemote","version":1}
##   Godot -> 手机:
##     {"type":"welcome","server":"pie-block","version":1}
##     {"type":"clamp_warning","axes":["x","pitch"]}
##     {"type":"reset_ack"}
##     {"type":"status","message":"..."}

signal pose_received(position: Vector3, rpy: Vector3)
signal phone_connected
signal phone_disconnected
signal reset_requested

const DEFAULT_PORT: int = 19821
const POSITION_LIMIT_MM: float = 5000.0
const PITCH_LIMIT_DEG: float = 90.0
const YAW_ROLL_LIMIT_DEG: float = 180.0
## 二维码生成脚本（项目 .venv 环境）
const GEN_QR_SCRIPT: String = "res://tools/gen_qr.py"

## 是否正在监听
var _listening: bool = false
var _port: int = DEFAULT_PORT
## 当前连接的 WebSocket peer
var _peers: Array[WebSocketPeer] = []
## TCP 服务端（用于接受新连接）
var _server: TCPServer = null
## 位置映射比例：手机移动 1mm × 比例 = 末端移动量
var position_scale: float = 1.0
## RPY 灵敏度：手机旋转角度 × 灵敏度 = 末端目标角度
var rpy_scale: float = 1.0
## 各轴使能开关
var axis_enable: Dictionary = {
	"x": true, "y": true, "z": true,
	"roll": true, "pitch": true, "yaw": true,
}
## ARCore 坐标系翻转开关（联调用）
var flip_x: bool = false
var flip_y: bool = true
var flip_z: bool = true
## ARCore 原点偏移（手机在原点重置时记录）
var _origin_position: Vector3 = Vector3.ZERO
## RPY 参考姿态（"回中"时记录当前手机姿态为零点）
var _origin_rpy: Vector3 = Vector3.ZERO
## 是否已收到过第一帧（用于初始化原点）
var _first_pose: bool = true
## 最近一帧手机原始数据（供 UI 显示）
var last_phone_position: Vector3 = Vector3.ZERO
var last_phone_rpy: Vector3 = Vector3.ZERO
## 连接的客户端信息
var client_info: String = ""


func start_listening(port: int = DEFAULT_PORT) -> bool:
	stop_listening()
	_port = port
	_server = TCPServer.new()
	var err: int = _server.listen(_port, "0.0.0.0")
	if err != OK:
		push_error("PhonePoseReceiver: 无法监听端口 %d (错误 %d)" % [_port, err])
		_listening = false
		return false
	_listening = true
	_first_pose = true
	print("PhonePoseReceiver: 监听 ws://0.0.0.0:%d" % _port)
	return true


func stop_listening() -> void:
	for peer in _peers:
		peer.close()
	_peers.clear()
	if _server != null:
		_server.stop()
		_server = null
	_listening = false
	client_info = ""
	_first_pose = true


func is_listening() -> bool:
	return _listening


func has_phone() -> bool:
	return not _peers.is_empty()


## 简单 IPv4 校验（Godot 4 已移除 IP.is_valid_ipv4）
static func _is_ipv4(s: String) -> bool:
	var parts := s.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
		var n: int = part.to_int()
		if n < 0 or n > 255:
			return false
	return true


## 判断是否为局域网 IP，返回优先级（数值越大越优先）。
## 0=不是局域网；1=172.16-31/10 段（可能是虚拟网卡/VPN）；2=192.168（家用路由器，最可能被手机直连）
static func _lan_priority(s: String) -> int:
	if not _is_ipv4(s):
		return 0
	var parts := s.split(".")
	var a: int = parts[0].to_int()
	var b: int = parts[1].to_int()
	if a == 192 and b == 168:
		return 2
	if a == 10:
		return 1
	if a == 172 and b >= 16 and b <= 31:
		return 1
	return 0


## 返回本机所有 IPv4 地址（供 UI 显示二维码 / IP 列表）
func get_local_ips() -> Array[String]:
	var ips: Array[String] = []
	# Godot 4: IP.get_local_addresses() 返回本机所有 IPv4/IPv6 地址
	for addr in IP.get_local_addresses():
		var s: String = str(addr)
		if _is_ipv4(s) and s != "127.0.0.1" and s != "0.0.0.0":
			ips.append(s)
	# 兜底：尝试解析主机名
	var hostname: String = OS.get_environment("COMPUTERNAME") if OS.has_feature("windows") else OS.get_environment("HOSTNAME")
	if not hostname.is_empty():
		var resolved: String = IP.resolve_hostname(hostname, IP.TYPE_IPV4)
		if not resolved.is_empty() and _is_ipv4(resolved) and not ips.has(resolved):
			ips.append(resolved)
	# 去重
	var seen: Dictionary = {}
	var unique: Array[String] = []
	for ip in ips:
		if not seen.has(ip):
			seen[ip] = true
			unique.append(ip)
	return unique


func get_connection_url(ip: String = "") -> String:
	var addr: String = ip
	if addr.is_empty():
		var all_ips := get_local_ips()
		# 按优先级选：192.168 > 10/172.16-31 > 其他；同级取第一个
		var best_priority: int = -1
		for candidate in all_ips:
			var prio: int = _lan_priority(candidate)
			if prio > best_priority:
				best_priority = prio
				addr = candidate
		if addr.is_empty() and not all_ips.is_empty():
			addr = all_ips[0]
	return "ws://%s:%d" % [addr, _port]


## 找到可用的 Python 解释器（优先项目 .venv）
func _python_path() -> String:
	var candidates: Array[String] = []
	if OS.has_feature("windows"):
		candidates.append(ProjectSettings.globalize_path("res://.venv/Scripts/python.exe"))
		candidates.append("python")
	else:
		candidates.append(ProjectSettings.globalize_path("res://.venv/bin/python3"))
		candidates.append("python3")
		candidates.append("python")
	for py in candidates:
		if py.is_empty():
			continue
		if py == "python" or py == "python3" or FileAccess.file_exists(py):
			return py
	return ""


## 生成二维码 PNG（连接地址），返回 user:// 路径；失败返回空串。
## 依赖项目 .venv 里的 qrcode 库（tools/gen_qr.py）。
func generate_qr_png(url: String) -> String:
	var out_path: String = "user://phone_qr.png"
	var abs_out: String = ProjectSettings.globalize_path(out_path)
	var script_path: String = ProjectSettings.globalize_path(GEN_QR_SCRIPT)
	var py: String = _python_path()
	if py.is_empty():
		push_warning("PhonePoseReceiver: 未找到 Python，无法生成二维码")
		return ""
	var args := ["--text", url, "--out", abs_out]
	var stdout: Array = []
	var exit_code: int = OS.execute(py, [script_path] + args, stdout, true)
	if exit_code != 0:
		push_warning("PhonePoseReceiver: 二维码生成失败 (exit=%d)" % exit_code)
		return ""
	if not FileAccess.file_exists(out_path):
		push_warning("PhonePoseReceiver: 二维码文件未生成")
		return ""
	return out_path


## 重置原点（"回中"按钮调用）
func reset_origin() -> void:
	_origin_position = last_phone_position
	_origin_rpy = last_phone_rpy
	_first_pose = false
	_send_to_all({"type": "reset_ack"})
	print("PhonePoseReceiver: 原点已重置 position=%s rpy=%s" % [str(_origin_position), str(_origin_rpy)])


## 向所有连接的手机发送 JSON 消息
func send_message(msg: Dictionary) -> void:
	_send_to_all(msg)


func _send_to_all(msg: Dictionary) -> void:
	if _peers.is_empty():
		return
	var text: String = JSON.stringify(msg)
	for peer in _peers:
		peer.send_text(text)


func _process(_delta: float) -> void:
	if not _listening:
		return
	# 接受新 TCP 连接并升级为 WebSocket
	while _server != null and _server.is_connection_available():
		var tcp: StreamPeerTCP = _server.take_connection()
		if tcp != null:
			var ws := WebSocketPeer.new()
			ws.accept_stream(tcp)
			_peers.append(ws)
			print("PhonePoseReceiver: 新连接，等待 WebSocket 握手")
	# 轮询所有 WebSocket peer
	var alive: Array[WebSocketPeer] = []
	for peer in _peers:
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			# 读取所有可用消息
			while peer.get_available_packet_count() > 0:
				var pkt: PackedByteArray = peer.get_packet()
				var text: String = pkt.get_string_from_utf8()
				_handle_message(peer, text)
			alive.append(peer)
		elif state == WebSocketPeer.STATE_CLOSED:
			var code: int = peer.get_close_code()
			var reason: String = peer.get_close_reason()
			print("PhonePoseReceiver: 手机断开 code=%d reason=%s" % [code, reason])
			phone_disconnected.emit()
			# 不加入 alive，自然移除
		else:
			# STATE_CONNECTING / STATE_CLOSING
			alive.append(peer)
	_peers = alive


func _handle_message(peer: WebSocketPeer, text: String) -> void:
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return
	var msg: Dictionary = parsed
	var msg_type: String = str(msg.get("type", ""))
	match msg_type:
		"hello":
			client_info = str(msg.get("app", "unknown")) + " v" + str(msg.get("version", "?"))
			peer.send_text(JSON.stringify({"type": "welcome", "server": "pie-block", "version": 1}))
			print("PhonePoseReceiver: 手机已连接 %s" % client_info)
			phone_connected.emit()
		"pose":
			_handle_pose(msg)
		"reset_origin":
			reset_origin()
			reset_requested.emit()
		_:
			pass # 忽略未知消息类型


func _handle_pose(msg: Dictionary) -> void:
	var pos_dict: Dictionary = msg.get("position", {})
	var rpy_dict: Dictionary = msg.get("rpy", {})
	# 手机原始数据
	var raw_pos := Vector3(
		float(pos_dict.get("x", 0.0)),
		float(pos_dict.get("y", 0.0)),
		float(pos_dict.get("z", 0.0))
	)
	var raw_rpy := Vector3(
		float(rpy_dict.get("roll", 0.0)),
		float(rpy_dict.get("pitch", 0.0)),
		float(rpy_dict.get("yaw", 0.0))
	)
	last_phone_position = raw_pos
	last_phone_rpy = raw_rpy
	# 首帧自动设为原点
	if _first_pose:
		_origin_position = raw_pos
		_origin_rpy = raw_rpy
		_first_pose = false
	# 计算相对位移并应用坐标轴翻转
	# ARCore 坐标系: X=右, Y=上(重力反方向), Z=后(朝向用户)
	# 机器人坐标系: X=前, Y=左, Z=上
	# 默认映射: ARCore X -> 机器人 -X (flip_x=false 时为正)
	#          ARCore Y -> 机器人 Z  (Y轴向上对应机器人Z向上)
	#          ARCore Z -> 机器人 Y  (Z向后对应Y向左，需翻转)
	var rel := raw_pos - _origin_position
	var mapped := Vector3.ZERO
	mapped.x = rel.x * position_scale * (1.0 if flip_x else -1.0) if axis_enable.get("x", true) else 0.0
	mapped.y = rel.z * position_scale * (1.0 if flip_y else -1.0) if axis_enable.get("y", true) else 0.0
	mapped.z = rel.y * position_scale * (1.0 if flip_z else -1.0) if axis_enable.get("z", true) else 0.0
	# RPY 绝对映射：手机当前姿态 - 参考姿态 = 相对角度
	var rel_rpy := raw_rpy - _origin_rpy
	var mapped_rpy := Vector3.ZERO
	mapped_rpy.x = clampf(rel_rpy.x * rpy_scale, -YAW_ROLL_LIMIT_DEG, YAW_ROLL_LIMIT_DEG) if axis_enable.get("roll", true) else 0.0
	mapped_rpy.y = clampf(rel_rpy.y * rpy_scale, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG) if axis_enable.get("pitch", true) else 0.0
	mapped_rpy.z = wrapf(rel_rpy.z * rpy_scale, -YAW_ROLL_LIMIT_DEG, YAW_ROLL_LIMIT_DEG) if axis_enable.get("yaw", true) else 0.0
	pose_received.emit(mapped, mapped_rpy)


## 返回被钳位的轴名列表（供 arm_sim 判断是否需要发 clamp_warning）
func check_clamp(position: Vector3, rpy: Vector3, orientation_mask: Dictionary) -> Dictionary:
	var clamped_axes: Array[String] = []
	var clamped_pos := Vector3(position)
	var clamped_rpy := Vector3(rpy)
	# 位置钳位
	for axis_name in ["x", "y", "z"]:
		var idx: int = {"x": 0, "y": 1, "z": 2}[axis_name]
		if absf(position[idx]) > POSITION_LIMIT_MM:
			clamped_axes.append(axis_name)
			clamped_pos[idx] = clampf(position[idx], -POSITION_LIMIT_MM, POSITION_LIMIT_MM)
	# 姿态钳位（只检查 MCU 支持的轴）
	if bool(orientation_mask.get("roll", false)):
		if absf(rpy.x) > YAW_ROLL_LIMIT_DEG:
			clamped_axes.append("roll")
			clamped_rpy.x = clampf(rpy.x, -YAW_ROLL_LIMIT_DEG, YAW_ROLL_LIMIT_DEG)
	if bool(orientation_mask.get("pitch", false)):
		if absf(rpy.y) > PITCH_LIMIT_DEG:
			clamped_axes.append("pitch")
			clamped_rpy.y = clampf(rpy.y, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	if bool(orientation_mask.get("yaw", false)):
		if absf(rpy.z) > YAW_ROLL_LIMIT_DEG:
			clamped_axes.append("yaw")
			clamped_rpy.z = clampf(rpy.z, -YAW_ROLL_LIMIT_DEG, YAW_ROLL_LIMIT_DEG)
	return {"position": clamped_pos, "rpy": clamped_rpy, "clamped_axes": clamped_axes}
