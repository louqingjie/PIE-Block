extends SceneTree

const LINK = preload("res://scripts/ik_sim_link.gd")
const TC = preload("res://scripts/toolchain.gd")

var _failures: int = 0


func _initialize() -> void:
	var python: String = TC.new().find_python()
	if python.is_empty():
		push_error("Python runtime is unavailable")
		quit(1)
		return
	for iteration in range(30):
		var link = LINK.new()
		root.add_child(link)
		var state: Array[bool] = [false, false]
		link.connected.connect(func(info: Dictionary) -> void:
			if info.has("hello"):
				state[0] = true)
		link.link_error.connect(func(_message: String) -> void:
			state[1] = true)
		if not link.start("FAKE_MCU", python, "virtual",
				"res://tools/test_ik_sim_fake_bridge.py"):
			_failures += 1
		else:
			var deadline: int = Time.get_ticks_msec() + 1000
			while not state[0] and not state[1] \
					and Time.get_ticks_msec() < deadline:
				await create_timer(0.005).timeout
			if not state[0] or state[1]:
				_failures += 1
		link.stop()
		root.remove_child(link)
		link.free()
	print("IK simulator link lifecycle: %d failure(s)" % _failures)
	quit(_failures)
