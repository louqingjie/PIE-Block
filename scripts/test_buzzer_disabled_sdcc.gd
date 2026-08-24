extends SceneTree

## 使用内置 SDCC 实际编译、链接蜂鸣器启用/禁用的步兵与工程固件。
## 运行：godot --headless --path . --script res://scripts/test_buzzer_disabled_sdcc.gd

const Sdcc = preload("res://scripts/sdcc_toolchain.gd")
const Infantry = preload("res://scripts/codegen/codegen_infantry.gd")
const Engineer = preload("res://scripts/codegen/codegen_engineer.gd")

var _fail: int = 0


func _engineer_cfg(disabled: bool) -> Dictionary:
	return {
		"buzzer_disabled": disabled,
		"mode_count": 2,
		"switch_strategy": "单击切换",
		"mode_switch_key": "E",
		"io_role": {"P60": "舵机", "P62": "舵机"},
		"io_init": {"P60": "舵机", "P62": "舵机", "MP03": "舵机", "MP74": "舵机"},
		"modes": [
			{"rows": [
				{"key": "A", "dir": "正", "mode": "增量", "param": "2", "io": "MP03"},
				{"key": "B", "dir": "反", "mode": "增量", "param": "2", "io": "MP74"},
			]},
			{"rows": [{"key": "C", "dir": "正", "mode": "增量", "param": "2", "io": "P60"}]},
		],
	}


func _build(label: String, kind: String, code: String) -> void:
	var output: String = "user://buzzer-disabled-test/%s.hex" % label
	var result: Dictionary = Sdcc.new(func(line: String) -> void: print(line)).build(kind, code, output)
	if bool(result.get("ok", false)) and FileAccess.file_exists(output):
		print("[PASS] %s" % label)
	else:
		printerr("[FAIL] %s：%s" % [label, str(result.get("log", "未生成 HEX"))])
		_fail += 1


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"user://buzzer-disabled-test"))
	var infantry = Infantry.new()
	var engineer = Engineer.new()
	_build("infantry-buzzer-on", "infantry", infantry.generate({"buzzer_disabled": false}))
	_build("infantry-buzzer-off", "infantry", infantry.generate({"buzzer_disabled": true}))
	_build("engineer-buzzer-on", "engineer", engineer.generate(_engineer_cfg(false)))
	_build("engineer-buzzer-off", "engineer", engineer.generate(_engineer_cfg(true)))
	print("失败数: %d" % _fail)
	quit(_fail)
