extends SceneTree

const REMOTE = preload("res://scripts/sim_remote_input.gd")

var _fail: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s %s" % [label, detail])
		_fail += 1


func _initialize() -> void:
	var state: Dictionary = REMOTE.compose(
		{"lx": 0.25, "ly": -0.5, "rx": 2.0, "ry": -2.0},
		{"UP": true, "A": true, "ROCKER1": true, "E": true}, 10, 10, 7, "Test Pad")
	_check("axes quantize and clamp", state["valueOfRoker"] == [
		[512, -1024], [2047, -2047]], str(state["valueOfRoker"]))
	_check("logical buttons fill valueOfKey", state["valueOfKey"][0][0] == 1
		and state["valueOfKey"][1][0] == 1 and state["valueOfKey"][2][0] == 1)
	_check("E remains available outside valueOfKey", REMOTE.is_pressed(state, "E"))
	_check("pad metadata survives", state["pad_id"] == 7 and state["pad_name"] == "Test Pad")

	var dead: Dictionary = REMOTE.compose({"lx": 10.0 / 2047.0, "rx": 11.0 / 2047.0}, {}, 10, 10)
	_check("deadzone is inclusive", dead["valueOfRoker"][0][0] == 0)
	_check("value above deadzone survives", dead["valueOfRoker"][1][0] == 11)
	_check("right arrow spellings normalize", REMOTE.is_pressed(
		REMOTE.compose({}, {"RIGHT": true}), "->") and REMOTE.is_pressed(
		REMOTE.compose({}, {"RIGHT": true}), "→"))
	_check("RT threshold is strict", not REMOTE.trigger_pressed(0.5)
		and REMOTE.trigger_pressed(0.5001))
	_check("keyboard layout matches infantry", REMOTE.KEYBOARD_BUTTONS[KEY_1] == "A"
		and REMOTE.KEYBOARD_BUTTONS[KEY_Z] == "ROCKER2")
	_check("gamepad layout matches infantry", REMOTE.PAD_BUTTONS[JOY_BUTTON_X] == "C"
		and REMOTE.PAD_BUTTONS[JOY_BUTTON_RIGHT_STICK] == "ROCKER2")

	print("Result: %s" % ("PASS" if _fail == 0 else "%d failed" % _fail))
	quit(0 if _fail == 0 else 1)
