extends SceneTree

## 向串口上的仿真求解器固件发送"变化目标"并观察 IK 收敛（验证固件求解能力）。
##
## 运行：godot --headless --path . --script scripts/dev_ik_move_test.gd -- --port=COM3
##
## 流程：HELLO -> 读取当前状态（末端/关节角）-> 发一个偏移后的 STEP_POSE
## 目标 -> 连续读状态观察 jointAngle 变化、末端移动、位置误差下降。
## 意义：验收脚本的 STEP_POSE 只发"保持当前"目标，这里补测真正的 IK 求解。

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
		push_error("Python runtime is unavailable")
		quit(2)
		return
	var link = LINK.new()
	root.add_child(link)
	link.state_received.connect(func(state: Dictionary) -> void: _states.append(state))
	link.connected.connect(func(info: Dictionary) -> void:
		if info.has("hello"): _hellos.append(info["hello"]))
	link.link_error.connect(func(message: String) -> void: _errors.append(message))
	if not link.start(port, python, "usb_serial"):
		_finish(link, false, "无法启动串口桥接")
		return
	# HELLO 握手（connected 信号，非 state_received）
	if not await _wait_hello(3000) or not _errors.is_empty():
		_finish(link, false, "HELLO timeout")
		return
	# 发 PING 获取初始状态（PING 返回 state）
	link.send_ping()
	if not await _wait_count(1, 3000) or not _errors.is_empty():
		_finish(link, false, "初始状态获取失败")
		return

	var s0: Dictionary = _states[-1]
	# 先归零，从 home 出发测 IK 收敛（避免残留状态干扰）
	link.send_home()
	if not await _wait_count(2, 3000):
		_finish(link, false, "HOME 失败")
		return
	s0 = _states[-1]
	var origin: Vector3 = s0.get("position", Vector3.ZERO)
	var rpy: Vector3 = s0.get("rpy", Vector3.ZERO)
	print("初始(home): angles=%s  末端=%s  rpy=%s  err=%.1fmm" % [
		_fmt_angles(s0["angles"]), origin, rpy, float(s0.get("position_error", 0.0))])

	# 可达目标：距原点 < 臂长 310mm，且不撞 ±90° 关节限位
	# （(200,100,50) 曾因 J3 需 >90° 撞限位停 15.7mm；(280,40,20) 小幅偏移）
	var target := Vector3(280.0, 40.0, 20.0)
	print("发送 STEP_POSE 可达目标: %s (距原点 %.0fmm < 臂长 310mm)" % [str(target), target.length()])
	link.send_pose(target, rpy)

	# 固件每次 STEP_POSE 调一次 ik_solve（每步限幅 4°，雅可比收敛慢），
	# 需连续重发同目标才能逐步收敛（GUI 即持续发目标）。80 步观察完整收敛。
	var converged: bool = false
	var last_err: float = -1.0
	for i in range(80):
		var before: int = _states.size()
		if not await _wait_count(before + 1, 800):
			print("step %d: 无新状态" % (i + 1))
			break
		var s: Dictionary = _states[-1]
		var p: Vector3 = s.get("position", Vector3.ZERO)
		var err: float = float(s.get("position_error", -1.0))
		if i % 5 == 0 or err < 5.0:
			print("step %d: angles=%s  末端=%.1f,%.1f,%.1f  err=%.1fmm  rtt=%.1fms" % [
				i + 1, _fmt_angles(s["angles"]), p.x, p.y, p.z, err, float(s.get("latency_ms", 0.0))])
		last_err = err
		if err >= 0.0 and err < 2.0:
			converged = true
			break
		# 重发同目标推进 IK 收敛
		link.send_pose(target, rpy)

	var p_end: Vector3 = _states[-1].get("position", Vector3.ZERO)
	var dist: float = p_end.distance_to(target)
	print("收敛判定: 末端距目标 %.1fmm  err<2mm=%s  (末次 err=%.1fmm)" % [
		dist, str(converged), last_err])
	print("关节角变化: 初始 %s -> 最终 %s" % [
		_fmt_angles(_states[0]["angles"]), _fmt_angles(_states[-1]["angles"])])
	_finish(link, converged, "IK move test")


func _fmt_angles(angles: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for a in angles:
		parts.append("%.1f" % float(a))
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


func _finish(link, ok: bool, message: String) -> void:
	print("RESULT ok=%s message=%s" % [str(ok), message])
	link.stop()
	root.remove_child(link)
	link.free()
	quit(0 if ok else 1)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result
