class_name CodeGenMusic
extends CodeGenBase

## MIDI 音乐代码生成器。
## 生成只使用主控板 P33 被动蜂鸣器的独立固件，不启动遥控器或拓展板通信。
## 多声部按固件可控的最小 1ms 时间片轮换，是伪复音，不是真正的同时波形叠加。

const BUZZER_PWM_CH: String = "PWMB_CH3_P33"
const MAX_VOICES: int = 4
const VOICE_SWITCH_MS: int = 1
const DEFAULT_DURATION_MS: int = 1


func generate(cfg: Dictionary) -> String:
	var music: Dictionary = cfg.get("music", cfg) if cfg.get("music", cfg) is Dictionary else {}
	var raw_segments: Variant = music.get("segments", [])
	var segments: Array = _safe_segments(raw_segments if raw_segments is Array else [])
	if segments.is_empty():
		# C251 不允许零长数组；非法配置仍生成可编译的静音固件，
		# 具体错误由 StaticChecker.check_music() 展示。
		segments = [{"notes": [], "duration_ms": DEFAULT_DURATION_MS}]

	var code: String = ""
	code += "// MIDI 音乐代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "// 模板仍链接 nrf24l01.c，保留其所需的通道符号；音乐模式不启动遥控器。\n"
	code += "uint8_t Channal = 36;\n\n"
	code += "#define MUSIC_BUZZER_CH %s\n" % BUZZER_PWM_CH
	code += "#define MUSIC_DUTY_ON  5000\n"
	code += "#define MUSIC_DUTY_OFF 0\n"
	code += "#define MUSIC_MAX_VOICES %d\n" % MAX_VOICES
	code += "#define MUSIC_VOICE_SWITCH_MS %dUL\n\n" % VOICE_SWITCH_MS
	code += "typedef struct\n"
	code += "{\n"
	code += "    uint32_t duration_ms;\n"
	code += "    uint8_t voice_count;\n"
	code += "    uint8_t notes[MUSIC_MAX_VOICES];\n"
	code += "} MusicSegment;\n\n"
	code += "// MIDI 音符编号 -> PWM 整数频率，索引 0 仅作安全占位，不播放频率 0。\n"
	code += "static const uint16_t musicFrequencies[128] =\n"
	code += "{\n"
	var frequencies: Array = []
	for note in range(128):
		frequencies.append(_midi_note_to_frequency(note))
	for row in range(16):
		var values: Array = []
		for column in range(8):
			values.append(str(frequencies[row * 8 + column]))
		code += "    %s%s\n" % [", ".join(values), "," if row < 15 else ""]
	code += "};\n\n"

	code += "static const MusicSegment musicSegments[%d] =\n" % segments.size()
	code += "{\n"
	for segment in segments:
		var notes: Array = segment["notes"] as Array
		var note_bytes: Array = []
		for index in range(MAX_VOICES):
			note_bytes.append(str(int(notes[index])) if index < notes.size() else "0")
		code += "    {%dUL, %d, {%s}},\n" % [
			int(segment["duration_ms"]), notes.size(), ", ".join(note_bytes)]
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

	code += "static void Music_PlaySegment(const MusicSegment *segment)\n"
	code += "{\n"
	code += "    uint32_t remaining_ms = segment->duration_ms;\n"
	code += "    uint8_t voice = 0;\n"
	code += "    uint32_t slice_ms;\n"
	code += "    if (segment->voice_count == 0)\n"
	code += "    {\n"
	code += "        Music_Stop();\n"
	code += "        Music_Wait(remaining_ms);\n"
	code += "        return;\n"
	code += "    }\n"
	code += "    if (segment->voice_count == 1)\n"
	code += "    {\n"
	code += "        PWM_SET_Frequency(MUSIC_BUZZER_CH,\n"
	code += "            musicFrequencies[segment->notes[0]], MUSIC_DUTY_ON);\n"
	code += "        Music_Wait(remaining_ms);\n"
	code += "        return;\n"
	code += "    }\n"
	code += "    // 伪复音：以最小 1ms 时间片轮换声部；最后不足 1ms 的时间片不延长节奏。\n"
	code += "    while (remaining_ms > 0UL)\n"
	code += "    {\n"
	code += "        slice_ms = remaining_ms > MUSIC_VOICE_SWITCH_MS\n"
	code += "            ? MUSIC_VOICE_SWITCH_MS : remaining_ms;\n"
	code += "        PWM_SET_Frequency(MUSIC_BUZZER_CH,\n"
	code += "            musicFrequencies[segment->notes[voice]], MUSIC_DUTY_ON);\n"
	code += "        Music_Wait(slice_ms);\n"
	code += "        remaining_ms -= slice_ms;\n"
	code += "        voice++;\n"
	code += "        if (voice >= segment->voice_count)\n"
	code += "            voice = 0;\n"
	code += "    }\n"
	code += "}\n\n"

	code += "static void Music_PlayOnce(void)\n"
	code += "{\n"
	code += "    uint16_t i;\n"
	code += "    for (i = 0; i < MUSIC_SEGMENT_COUNT; i++)\n"
	code += "        Music_PlaySegment(&musicSegments[i]);\n"
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
		var notes: Array = []
		var raw_notes: Variant = segment.get("notes", null)
		if raw_notes is Array:
			for value in raw_notes:
				var note: int = int(value)
				if note >= 1 and note <= 127 and note not in notes:
					notes.append(note)
		elif segment.has("note"):
			var old_note: int = int(segment.get("note", 0))
			if old_note >= 1 and old_note <= 127:
				notes = [old_note]
		notes.sort()
		notes.reverse()
		if notes.size() > MAX_VOICES:
			notes = notes.slice(0, MAX_VOICES)
		var duration_ms: int = int(segment.get("duration_ms", DEFAULT_DURATION_MS))
		if duration_ms < 1:
			duration_ms = DEFAULT_DURATION_MS
		result.append({"notes": notes, "duration_ms": duration_ms})
	return result


static func _midi_note_to_frequency(note: int) -> int:
	if note <= 0 or note > 127:
		return 1000
	return int(round(440.0 * pow(2.0, float(note - 69) / 12.0)))
