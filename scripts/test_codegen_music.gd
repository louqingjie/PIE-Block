extends SceneTree

## 音乐代码生成器与静态检查测试。

const Music = preload("res://scripts/codegen/codegen_music.gd")
const Checker = preload("res://scripts/static_checker.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _initialize() -> void:
	print("=== 音乐代码生成器测试 ===\n")
	var cfg: Dictionary = {
		"music": {
			"polyphonic": true,
			"track_index": 0,
			"track_indices": [0, 1],
			"track_count": 2,
			"segments": [
				{"notes": [69, 64], "duration_ms": 70000},
				{"notes": [], "duration_ms": 120},
				{"notes": [72], "duration_ms": 200},
			],
		},
	}
	var code: String = Music.new().generate(cfg)
	_check("使用 P33 PWM 通道", code.contains("PWMB_CH3_P33"))
	_check("包含 PWM 初始化与停止", code.contains("PWM_Init(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF)")
		and code.contains("PWM_SET_Frequency(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF)"))
	_check("静态 MIDI 频率表包含离线换算结果",
		code.contains("static const uint16_t musicFrequencies[128]")
		and code.contains("440") and code.contains("523"))
	_check("休止使用 0 占空比而不调用频率 0",
		code.contains("if (segment->voice_count == 0)")
		and code.contains("MUSIC_DUTY_OFF")
		and not code.contains("PWM_SET_Frequency(MUSIC_BUZZER_CH, 0,"))
	_check("四声部使用 5ms 时间片轮换", code.contains("MUSIC_MAX_VOICES 4")
		and code.contains("MUSIC_VOICE_SLICE_MS 5UL")
		and code.contains("remaining_ms -= slice_ms"))
	_check("片段表保存音符编号而不是频率", code.contains("uint8_t notes[MUSIC_MAX_VOICES]")
		and code.contains("{70000UL, 2, {69, 64, 0, 0}}"))
	_check("长延时拆分为 16 位 Ms_Delay", code.contains("while (duration_ms > 65535UL)")
		and code.contains("Ms_Delay((uint16_t)65535)"))
	_check("上电后自动循环播放", code.contains("while (1)\n        Music_PlayOnce();"))
	_check("不生成遥控器和拓展板控制代码",
		not code.contains("ExpansionBoradControl")
		and not code.contains("NRF24L01_Init")
		and not code.contains("nrf_handler"))

	var issues: Array = Checker.check_music(cfg)
	_check("合法音乐配置通过静态检查", issues.is_empty(), JSON.stringify(issues))
	var invalid_cfg: Dictionary = {"music": {"track_index": -1, "track_count": 0, "segments": []}}
	var invalid_issues: Array = Checker.check_music(invalid_cfg)
	_check("空音乐配置由静态检查报错", invalid_issues.size() >= 2)
	var safe_code: String = Music.new().generate(invalid_cfg)
	_check("非法配置生成安全静音数组", safe_code.contains("{1UL, 0, {0, 0, 0, 0}}")
		and safe_code.contains("Music_Stop();"))

	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)
