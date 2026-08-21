class_name CodeGenMusic
extends CodeGenBase

## MIDI 音乐代码生成器。
## 生成只使用主控板 P33 被动蜂鸣器的独立固件，不启动遥控器或拓展板通信。

const BUZZER_PWM_CH: String = "PWMB_CH3_P33"
const DEFAULT_NOTE: int = 0
const DEFAULT_DURATION_MS: int = 1


func generate(cfg: Dictionary) -> String:
	var music: Dictionary = cfg.get("music", cfg) if cfg.get("music", cfg) is Dictionary else {}
	var raw_segments: Variant = music.get("segments", [])
	var segments: Array = _safe_segments(raw_segments if raw_segments is Array else [])
	if segments.is_empty():
		# C251 不允许零长数组；非法配置仍生成可编译的静音固件，
		# 具体错误由 StaticChecker.check_music() 展示。
		segments = [{"frequency": 0, "duration_ms": DEFAULT_DURATION_MS}]

	var code: String = ""
	code += "// MIDI 音乐代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "// 模板仍链接 nrf24l01.c，保留其所需的通道符号；音乐模式不启动遥控器。\n"
	code += "uint8_t Channal = 36;\n\n"
	code += "#define MUSIC_BUZZER_CH %s\n" % BUZZER_PWM_CH
	code += "#define MUSIC_DUTY_ON  5000\n"
	code += "#define MUSIC_DUTY_OFF 0\n\n"
	code += "typedef struct\n"
	code += "{\n"
	code += "    uint16_t frequency;\n"
	code += "    uint32_t duration_ms;\n"
	code += "} MusicSegment;\n\n"
	code += "static const MusicSegment musicSegments[%d] =\n" % segments.size()
	code += "{\n"
	for segment in segments:
		code += "    {%d, %dUL},\n" % [int(segment["frequency"]), int(segment["duration_ms"])]
	code += "};\n"
	code += "#define MUSIC_SEGMENT_COUNT %d\n\n" % segments.size()

	code += "// Ms_Delay 的参数是 uint16_t，长音符拆成多个安全延时。\n"
	code += "static void Music_Wait(uint32_t duration_ms)\n"
	code += "{\n"
	code += "    while (duration_ms > 65535UL)\n"
	code += "    {\n"
	code += "        Ms_Delay((uint16_t)65535);\n"
	code += "        duration_ms -= 65535UL;\n"
	code += "    }\n"
	code += "    if (duration_ms > 0UL)\n"
	code += "        Ms_Delay((uint16_t)duration_ms);\n"
	code += "}\n\n"

	code += "static void Music_Stop(void)\n"
	code += "{\n"
	code += "    // 关闭时仍传入有效频率，避免 PWM_SET_Frequency 除零。\n"
	code += "    PWM_SET_Frequency(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);\n"
	code += "}\n\n"

	code += "static void Music_PlayOnce(void)\n"
	code += "{\n"
	code += "    uint16_t i;\n"
	code += "    for (i = 0; i < MUSIC_SEGMENT_COUNT; i++)\n"
	code += "    {\n"
	code += "        if (musicSegments[i].frequency == 0)\n"
	code += "            Music_Stop();\n"
	code += "        else\n"
	code += "            PWM_SET_Frequency(MUSIC_BUZZER_CH, musicSegments[i].frequency, MUSIC_DUTY_ON);\n"
	code += "        Music_Wait(musicSegments[i].duration_ms);\n"
	code += "    }\n"
	code += "    Music_Stop();\n"
	code += "}\n\n"

	code += "static void All_Init(void)\n"
	code += "{\n"
	code += "    Board_Init();\n"
	code += "    // P33 蜂鸣器必须先 PWM_Init，再通过 PWM_SET_Frequency 改音高。\n"
	code += "    PWM_Init(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);\n"
	code += "    Music_Stop();\n"
	code += "}\n\n"

	code += "void main(void)\n"
	code += "{\n"
	code += "    All_Init();\n"
	code += "    while (1)\n"
	code += "        Music_PlayOnce();\n"
	code += "}\n"
	return code


func _safe_segments(raw: Array) -> Array:
	var result: Array = []
	for item in raw:
		if not item is Dictionary:
			continue
		var segment: Dictionary = item
		var frequency: int = int(segment.get("frequency", 0))
		if frequency == 0 and segment.has("note"):
			var note: int = int(segment.get("note", 0))
			frequency = _midi_note_to_frequency(note)
		var duration_ms: int = int(segment.get("duration_ms", DEFAULT_DURATION_MS))
		if frequency < 0 or frequency > 65535:
			frequency = 0
		if duration_ms < 1:
			duration_ms = DEFAULT_DURATION_MS
		result.append({"frequency": frequency, "duration_ms": duration_ms})
	return result


static func _midi_note_to_frequency(note: int) -> int:
	if note <= 0 or note > 127:
		return 0
	return int(round(440.0 * pow(2.0, float(note - 69) / 12.0)))
