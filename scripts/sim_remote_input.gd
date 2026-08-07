class_name SimRemoteInput
extends RefCounted

## 步兵与工程 3D 仿真共用的 PC 遥控器输入层。
## 输出沿用真机命名：valueOfRoker[2][2] 与 valueOfKey[3][4]。

const ROKER_FULL: float = 2047.0
const PAD_TRIGGER_THRESHOLD: float = 0.5

const KEY_ROWS: Array = [
	["UP", "DOWN", "LEFT", "RIGHT"],
	["A", "B", "C", "D"],
	["ROCKER1", "ROCKER2", "", ""],
]

const CONFIG_KEY_TO_ID: Dictionary = {
	"E": "E", "R": "E", # R 是旧名别名
	"↑": "UP", "↓": "DOWN", "←": "LEFT", "→": "RIGHT", "->": "RIGHT",
	"A": "A", "B": "B", "C": "C", "D": "D",
}

const KEYBOARD_BUTTONS: Dictionary = {
	KEY_UP: "UP", KEY_DOWN: "DOWN", KEY_LEFT: "LEFT", KEY_RIGHT: "RIGHT",
	KEY_1: "A", KEY_2: "B", KEY_3: "C", KEY_4: "D",
	KEY_SHIFT: "ROCKER1", KEY_Z: "ROCKER2",
}

const PAD_BUTTONS: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "C", JOY_BUTTON_Y: "D",
	JOY_BUTTON_DPAD_UP: "UP", JOY_BUTTON_DPAD_DOWN: "DOWN",
	JOY_BUTTON_DPAD_LEFT: "LEFT", JOY_BUTTON_DPAD_RIGHT: "RIGHT",
	JOY_BUTTON_LEFT_STICK: "ROCKER1", JOY_BUTTON_RIGHT_STICK: "ROCKER2",
}


## 从当前 Godot Input 状态采样。keyboard_enabled=false 时仍保留真实手柄输入。
static func sample(left_deadzone: int, right_deadzone: int,
		keyboard_enabled: bool = true, pointer_r_enabled: bool = true) -> Dictionary:
	var axes: Dictionary = {"lx": 0.0, "ly": 0.0, "rx": 0.0, "ry": 0.0}
	var pressed: Dictionary = {}
	var pad_id: int = -1
	var pad_name: String = ""
	var pads: Array = Input.get_connected_joypads()
	if not pads.is_empty():
		pad_id = int(pads[0])
		pad_name = Input.get_joy_name(pad_id)
		axes["lx"] = Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X)
		axes["ly"] = -Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y)
		axes["rx"] = Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_X)
		axes["ry"] = -Input.get_joy_axis(pad_id, JOY_AXIS_RIGHT_Y)
		for button in PAD_BUTTONS:
			if Input.is_joy_button_pressed(pad_id, button):
				pressed[PAD_BUTTONS[button]] = true
		if trigger_pressed(Input.get_joy_axis(pad_id, JOY_AXIS_TRIGGER_RIGHT)):
			pressed["E"] = true
	if keyboard_enabled:
		axes["lx"] += _axis_pair(KEY_D, KEY_A)
		axes["ly"] += _axis_pair(KEY_W, KEY_S)
		axes["rx"] += _axis_pair(KEY_L, KEY_J)
		axes["ry"] += _axis_pair(KEY_I, KEY_K)
		for code in KEYBOARD_BUTTONS:
			if Input.is_key_pressed(code):
				pressed[KEYBOARD_BUTTONS[code]] = true
		if pointer_r_enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			pressed["E"] = true
	return compose(axes, pressed, left_deadzone, right_deadzone, pad_id, pad_name)


## 纯数据入口，供测试和回放使用。轴值允许叠加后超过 1，量化前统一钳制。
static func compose(axes: Dictionary, pressed: Dictionary,
		left_deadzone: int = 0, right_deadzone: int = 0,
		pad_id: int = -1, pad_name: String = "") -> Dictionary:
	var roker: Array = [
		[_quantize(float(axes.get("lx", 0.0))), _quantize(float(axes.get("ly", 0.0)))],
		[_quantize(float(axes.get("rx", 0.0))), _quantize(float(axes.get("ry", 0.0)))],
	]
	for axis in range(2):
		var deadzone: int = left_deadzone if axis == 0 else right_deadzone
		for component in range(2):
			if absi(int(roker[axis][component])) <= deadzone:
				roker[axis][component] = 0
	var keys: Array = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
	for row in range(KEY_ROWS.size()):
		for column in range(4):
			var id: String = KEY_ROWS[row][column]
			keys[row][column] = 1 if not id.is_empty() and pressed.has(id) else 0
	return {
		"valueOfRoker": roker,
		"valueOfKey": keys,
		"pressed": pressed.duplicate(true),
		"pad_id": pad_id,
		"pad_name": pad_name,
	}


static func is_pressed(snapshot: Dictionary, config_key: String) -> bool:
	var id: String = str(CONFIG_KEY_TO_ID.get(config_key, config_key))
	return (snapshot.get("pressed", {}) as Dictionary).has(id)


static func pressed_names(snapshot: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in (snapshot.get("pressed", {}) as Dictionary).keys():
		out.append(str(id))
	out.sort()
	return out


static func trigger_pressed(value: float) -> bool:
	return value > PAD_TRIGGER_THRESHOLD


static func _axis_pair(positive: int, negative: int) -> float:
	return (1.0 if Input.is_key_pressed(positive) else 0.0) \
		- (1.0 if Input.is_key_pressed(negative) else 0.0)


static func _quantize(value: float) -> int:
	return int(round(clampf(value, -1.0, 1.0) * ROKER_FULL))
