extends SceneTree

## 工程多模式按键切换冲突静态检查回归测试。
## 运行：godot --headless --path . --script res://scripts/test_static_checker.gd

const SC = preload("res://scripts/static_checker.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s%s" % [label, ("：" + detail) if not detail.is_empty() else ""])
		_fail += 1


func _base_config(mode_count: int, strategy: String) -> Dictionary:
	var modes: Array = []
	for _i in range(4):
		modes.append({"rows": []})
	return {
		"channel": "36",
		"deadzone": "10",
		"normal_speed": "4000",
		"sprint_speed": "8000",
		"sprint_enabled": false,
		"l1_io": "P74 P24",
		"l2_io": "P75 P25",
		"r1_io": "P76 P26",
		"r2_io": "P77 P27",
		"l1_dir": "正向",
		"l2_dir": "正向",
		"r1_dir": "正向",
		"r2_dir": "正向",
		"io_init": {
			"P74": "电机", "P75": "电机", "P76": "电机", "P77": "电机",
			"P60": "舵机", "P62": "舵机", "P64": "舵机", "P66": "舵机",
			"MP03": "舵机", "MP74": "舵机",
		},
		"io_mid": {},
		"mode_count": mode_count,
		"switch_strategy": strategy,
		"mode_switch_key": "E",
		"mode_keys": ["A", "B", "C", "D"],
		"modes": modes,
	}


func _with_row(cfg: Dictionary, mode_index: int, key: String) -> Dictionary:
	var result: Dictionary = cfg.duplicate(true)
	result["modes"][mode_index]["rows"] = [{
		"key": key,
		"dir": "正",
		"mode": "直接",
		"param": "10",
		"io": "MP03",
	}]
	return result


func _issues(cfg: Dictionary) -> Array:
	return SC.check_engineer(cfg)


func _has_error(issues: Array, text: String) -> bool:
	for issue in issues:
		if str(issue.get("type", "")) == "Error" \
				and str(issue.get("msg", "")).contains(text):
			return true
	return false


func _has_mode_switch_error(issues: Array) -> bool:
	return _has_error(issues, "切换键")


func _initialize() -> void:
	var click_same_mode: Dictionary = _with_row(
		_base_config(2, "单击切换"), 0, "E")
	_check("单击切换键与同模式映射冲突",
		_has_mode_switch_error(_issues(click_same_mode)))

	var click_other_mode: Dictionary = _with_row(
		_base_config(2, "单击切换"), 1, "E")
	_check("单击切换键与其他模式映射冲突",
		_has_mode_switch_error(_issues(click_other_mode)))

	var reused_action: Dictionary = _with_row(
		_with_row(_base_config(2, "单击切换"), 0, "A"), 1, "A")
	_check("普通按键可在不同模式复用",
		not _has_mode_switch_error(_issues(reused_action)))

	var one_to_one_duplicate: Dictionary = _base_config(2, "一一对应")
	one_to_one_duplicate["mode_keys"] = ["A", "A", "C", "D"]
	_check("一一对应模式键重复会报错",
		_has_error(_issues(one_to_one_duplicate), "同一个模式键"))

	var one_to_one_row_conflict: Dictionary = _with_row(
		_base_config(2, "一一对应"), 1, "A")
	_check("一一对应模式键与任意模式映射冲突",
		_has_mode_switch_error(_issues(one_to_one_row_conflict)))

	var single_click_unused: Dictionary = _with_row(
		_base_config(1, "单击切换"), 0, "E")
	_check("单模式不检查未生效的单击切换键",
		not _has_mode_switch_error(_issues(single_click_unused)))

	var one_to_one_unused: Dictionary = _with_row(
		_base_config(1, "一一对应"), 0, "A")
	_check("单模式不检查未生效的一一对应模式键",
		not _has_mode_switch_error(_issues(one_to_one_unused)))

	var servo_direct_negative: Dictionary = _with_row(
		_base_config(1, "单击切换"), 0, "A")
	servo_direct_negative["modes"][0]["rows"][0]["param"] = "-10"
	_check("舵机直接模式拒绝负数角度参数",
		_has_error(_issues(servo_direct_negative), "舵机角度参数"))

	var debug_servo_negative: Array = SC.check_debug([{
		"pin": "P60", "drive_type": "舵机", "value": -10, "enabled": true,
	}])
	_check("调试舵机拒绝负数角度参数",
		_has_error(debug_servo_negative, "舵机角度参数"))

	if _fail > 0:
		print("失败 %d 项" % _fail)
		quit(1)
	else:
		print("全部通过")
		quit(0)
