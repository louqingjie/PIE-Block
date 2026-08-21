class_name MidiParser
extends RefCounted

## Standard MIDI File 解析器。
##
## 首版只接受 SMF Format 0/1 + PPQ 时间分辨率，解析音符、轨道名和 tempo
## 事件。每条轨道同时保留可用于多轨合并的绝对微秒音符区间；普通轨道摘要
## 仍输出单音片段，note=0 表示休止。merge_tracks() 输出最多四声部的 notes 数组。

const DEFAULT_TEMPO_US_PER_QUARTER: int = 500000 # 120 BPM
const MAX_SEGMENTS: int = 8192
const MAX_DURATION_MS: int = 20 * 60 * 1000
const MAX_VOICES: int = 4


static func parse_file(path: String) -> Dictionary:
	if path.is_empty():
		return _error("MIDI 文件路径为空")
	if not FileAccess.file_exists(path):
		return _error("MIDI 文件不存在：%s" % path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _error("无法读取 MIDI 文件：%s" % path)
	var result: Dictionary = parse_bytes(bytes, path.get_file())
	result["path"] = path
	return result


static func parse_bytes(bytes: PackedByteArray, source_name: String = "") -> Dictionary:
	if bytes.size() < 14:
		return _error("MIDI 文件头不完整")
	if _ascii(bytes, 0, 4) != "MThd":
		return _error("不是标准 MIDI 文件（缺少 MThd 文件头）")
	var header_length: int = _u32(bytes, 4)
	if header_length < 6 or 8 + header_length > bytes.size():
		return _error("MIDI 文件头长度无效")
	var format: int = _u16(bytes, 8)
	var track_count: int = _u16(bytes, 10)
	var division: int = _u16(bytes, 12)
	if format != 0 and format != 1:
		return _error("暂不支持 MIDI 格式 %d，仅支持格式 0/1" % format)
	if track_count <= 0:
		return _error("MIDI 文件没有轨道")
	# 最高位为 1 时是 SMPTE 帧率，不是 PPQ。
	if (division & 0x8000) != 0 or division == 0:
		return _error("暂不支持 SMPTE 或无效的 MIDI 时间分辨率，请使用 PPQ MIDI")

	var pos: int = 8 + header_length
	var raw_tracks: Array = []
	var tempo_events: Array = [{"tick": 0, "tempo": DEFAULT_TEMPO_US_PER_QUARTER, "order": -1}]
	var tempo_order: int = 0
	for track_index in range(track_count):
		if pos + 8 > bytes.size():
			return _error("第 %d 条 MIDI 轨道头不完整" % (track_index + 1))
		if _ascii(bytes, pos, 4) != "MTrk":
			return _error("第 %d 条轨道缺少 MTrk 文件头" % (track_index + 1))
		var length: int = _u32(bytes, pos + 4)
		var start: int = pos + 8
		var end: int = start + length
		if end > bytes.size():
			return _error("第 %d 条 MIDI 轨道数据不完整" % (track_index + 1))
		var parsed_track: Dictionary = _parse_track(bytes, start, end, track_index)
		if not parsed_track["ok"]:
			return _error(str(parsed_track["err"]))
		raw_tracks.append(parsed_track)
		for tempo in parsed_track["tempos"]:
			var tempo_item: Dictionary = tempo.duplicate()
			tempo_item["order"] = tempo_order
			tempo_order += 1
			tempo_events.append(tempo_item)
		pos = end

	_tempo_sort(tempo_events)
	var tracks: Array = []
	var playable_track_count: int = 0
	for raw in raw_tracks:
		var intervals_result: Dictionary = _build_intervals(
			raw["events"], int(raw["end_tick"]), tempo_events, division)
		var segments_result: Dictionary = _build_segments(
			raw["events"], int(raw["end_tick"]), tempo_events, division)
		var track: Dictionary = {
			"index": int(raw["index"]),
			"name": str(raw["name"]),
			"note_count": int(raw["note_count"]),
			"duration_ms": int(segments_result.get("duration_ms", 0)),
			"segments": segments_result.get("segments", []),
			"intervals": intervals_result.get("intervals", []),
			"error": str(segments_result.get("err", "")),
		}
		if track["error"].is_empty() and not (track["segments"] as Array).is_empty():
			playable_track_count += 1
		tracks.append(track)

	return {
		"ok": true,
		"err": "",
		"source_name": source_name,
		"format": format,
		"track_count": track_count,
		"ppq": division,
		"tracks": tracks,
		"has_playable_track": playable_track_count > 0,
	}


## 将解析结果中的多条轨道合并成单个蜂鸣器可播放的片段序列。
## 每个片段使用 {notes: [最高音, ...], duration_ms}，notes=[] 表示休止。
static func merge_tracks(parsed: Dictionary, track_indices: Array,
		max_voices: int = MAX_VOICES) -> Dictionary:
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "segments": [], "duration_ms": 0,
			"err": str(parsed.get("err", "MIDI 解析结果无效"))}
	var tracks: Array = parsed.get("tracks", [])
	var selected: Array[int] = []
	var seen: Dictionary = {}
	for raw_index in track_indices:
		var index: int = int(raw_index)
		if index < 0 or index >= tracks.size():
			return {"ok": false, "segments": [], "duration_ms": 0,
				"err": "MIDI 轨道索引无效：%d" % index}
		if seen.has(index):
			continue
		seen[index] = true
		var track: Dictionary = tracks[index]
		if not str(track.get("error", "")).is_empty():
			return {"ok": false, "segments": [], "duration_ms": 0,
				"err": "轨道 %d 不可播放：%s" % [index + 1, str(track["error"])]}
		var intervals: Array = track.get("intervals", [])
		if intervals.is_empty():
			return {"ok": false, "segments": [], "duration_ms": 0,
				"err": "轨道 %d 没有可播放的音符" % (index + 1)}
		selected.append(index)
	if selected.is_empty():
		return {"ok": false, "segments": [], "duration_ms": 0,
			"err": "至少选择一条可播放轨道"}
	var voices: int = clampi(max_voices, 1, MAX_VOICES)
	var all_intervals: Array = []
	for index in selected:
		all_intervals.append_array((tracks[index].get("intervals", []) as Array))
	return _segments_from_intervals(all_intervals, voices, true)


static func _parse_track(bytes: PackedByteArray, start: int, end: int,
		track_index: int) -> Dictionary:
	var pos: int = start
	var tick: int = 0
	var running_status: int = 0
	var order: int = 0
	var events: Array = []
	var tempos: Array = []
	var track_name: String = ""
	var note_count: int = 0
	while pos < end:
		var delta: Dictionary = _read_vlq(bytes, pos, end)
		if not delta["ok"]:
			return {"ok": false, "err": "第 %d 条轨道的变长节拍无效" % (track_index + 1)}
		tick += int(delta["value"])
		pos = int(delta["next"])
		if pos >= end:
			return {"ok": false, "err": "第 %d 条轨道事件不完整" % (track_index + 1)}

		var status: int = int(bytes[pos])
		if status < 0x80:
			if running_status == 0:
				return {"ok": false, "err": "第 %d 条轨道缺少 running status" % (track_index + 1)}
			status = running_status
		else:
			pos += 1

		if status == 0xff:
			if pos >= end:
				return {"ok": false, "err": "第 %d 条轨道 Meta 事件不完整" % (track_index + 1)}
			var meta_type: int = int(bytes[pos])
			pos += 1
			var meta_length: Dictionary = _read_vlq(bytes, pos, end)
			if not meta_length["ok"]:
				return {"ok": false, "err": "第 %d 条轨道 Meta 事件长度无效" % (track_index + 1)}
			pos = int(meta_length["next"])
			var payload_end: int = pos + int(meta_length["value"])
			if payload_end > end:
				return {"ok": false, "err": "第 %d 条轨道 Meta 事件数据不完整" % (track_index + 1)}
			if meta_type == 0x03:
				track_name = _decode_text(bytes.slice(pos, payload_end))
			elif meta_type == 0x51 and int(meta_length["value"]) == 3:
				var tempo: int = (int(bytes[pos]) << 16) | (int(bytes[pos + 1]) << 8) | int(bytes[pos + 2])
				if tempo > 0:
					tempos.append({"tick": tick, "tempo": tempo})
			pos = payload_end
			if meta_type == 0x2f:
				break
			running_status = 0
			order += 1
			continue

		if status == 0xf0 or status == 0xf7:
			var sysex_length: Dictionary = _read_vlq(bytes, pos, end)
			if not sysex_length["ok"]:
				return {"ok": false, "err": "第 %d 条轨道 SysEx 事件长度无效" % (track_index + 1)}
			pos = int(sysex_length["next"]) + int(sysex_length["value"])
			if pos > end:
				return {"ok": false, "err": "第 %d 条轨道 SysEx 数据不完整" % (track_index + 1)}
			running_status = 0
			order += 1
			continue

		if status < 0x80 or status > 0xef:
			var system_size: int = _system_event_size(status)
			if system_size < 0 or pos + system_size > end:
				return {"ok": false, "err": "第 %d 条轨道系统事件无效" % (track_index + 1)}
			pos += system_size
			order += 1
			continue

		var event_type: int = status & 0xf0
		var data_size: int = 1 if event_type == 0xc0 or event_type == 0xd0 else 2
		if pos + data_size > end:
			return {"ok": false, "err": "第 %d 条轨道通道事件不完整" % (track_index + 1)}
		var data_1: int = int(bytes[pos])
		var data_2: int = int(bytes[pos + 1]) if data_size == 2 else 0
		pos += data_size
		if event_type == 0x90 and data_2 > 0:
			events.append({"tick": tick, "type": "on", "note": data_1, "order": order})
			note_count += 1
		elif event_type == 0x80 or (event_type == 0x90 and data_2 == 0):
			events.append({"tick": tick, "type": "off", "note": data_1, "order": order})
		running_status = status
		order += 1

	return {
		"ok": true,
		"index": track_index,
		"name": track_name,
		"events": events,
		"tempos": tempos,
		"note_count": note_count,
		"end_tick": tick,
	}


static func _build_segments(events: Array, end_tick: int, tempos: Array, ppq: int) -> Dictionary:
	var interval_result: Dictionary = _build_intervals(events, end_tick, tempos, ppq)
	if not str(interval_result.get("err", "")).is_empty():
		return {"segments": [], "duration_ms": 0, "err": str(interval_result["err"])}
	return _segments_from_intervals(interval_result.get("intervals", []), 1, false)


static func _build_intervals(events: Array, end_tick: int, tempos: Array, ppq: int) -> Dictionary:
	var active: Dictionary = {}
	var notes: Array = []
	for event in events:
		var note: int = int(event["note"])
		if str(event["type"]) == "on":
			var starts: Array = active.get(note, [])
			starts.append({"tick": int(event["tick"]), "order": int(event["order"])})
			active[note] = starts
		else:
			var open_notes: Array = active.get(note, [])
			if open_notes.is_empty():
				continue
			var opening: Dictionary = open_notes.pop_back()
			active[note] = open_notes
			var start_tick: int = int(opening["tick"])
			var stop_tick: int = int(event["tick"])
			if stop_tick > start_tick:
				notes.append({"start": start_tick, "end": stop_tick, "note": note,
					"order": int(opening["order"])})

	# 没有 note-off 的文件按轨道末尾结束，避免生成无限长音符。
	for note_key in active.keys():
		var open_notes: Array = active[note_key]
		for opening in open_notes:
			var start_tick: int = int(opening["tick"])
			if end_tick > start_tick:
				notes.append({"start": start_tick, "end": end_tick, "note": int(note_key),
					"order": int(opening["order"])})
	if notes.is_empty():
		return {"intervals": [], "err": "该轨道没有可播放的音符"}
	var intervals: Array = []
	for note in notes:
		intervals.append({
			"start_us": _tick_to_us(int(note["start"]), tempos, ppq),
			"end_us": _tick_to_us(int(note["end"]), tempos, ppq),
			"note": int(note["note"]),
		})
	return {"intervals": intervals, "err": ""}


static func _segments_from_intervals(intervals: Array, max_voices: int,
		polyphonic: bool) -> Dictionary:
	if intervals.is_empty():
		return {"ok": false, "segments": [], "duration_ms": 0, "err": "该轨道没有可播放的音符"}

	var boundaries: Array[int] = [0]
	for interval in intervals:
		boundaries.append(int(interval["start_us"]))
		boundaries.append(int(interval["end_us"]))
	boundaries.sort()
	var unique_boundaries: Array[int] = []
	for boundary in boundaries:
		if unique_boundaries.is_empty() or unique_boundaries[-1] != boundary:
			unique_boundaries.append(boundary)

	var segments: Array = []
	for i in range(unique_boundaries.size() - 1):
		var left: int = unique_boundaries[i]
		var right: int = unique_boundaries[i + 1]
		if right <= left:
			continue
		var active_notes: Array[int] = []
		for interval in intervals:
			if int(interval["start_us"]) <= left and int(interval["end_us"]) > left:
				var note_value: int = int(interval["note"])
				if note_value > 0 and note_value not in active_notes:
					active_notes.append(note_value)
		active_notes.sort()
		active_notes.reverse()
		if active_notes.size() > max_voices:
			active_notes = active_notes.slice(0, max_voices)
		var duration_ms: int = maxi(1, int(round(
			float(right - left) / 1000.0)))
		var current_notes: Array = active_notes
		if not polyphonic:
			current_notes = [active_notes[0]] if not active_notes.is_empty() else []
		if not segments.is_empty() and segments[-1]["notes"] == current_notes:
			segments[-1]["duration_ms"] = int(segments[-1]["duration_ms"]) + duration_ms
		else:
			segments.append({"notes": current_notes, "duration_ms": duration_ms})

	# 曲尾静音不影响循环，去掉它；开头和音符间的休止保留。
	while not segments.is_empty() and (segments[-1]["notes"] as Array).is_empty():
		segments.pop_back()
	if segments.is_empty():
		return {"ok": false, "segments": [], "duration_ms": 0, "err": "该轨道没有可播放的音符"}
	var duration_ms: int = 0
	for segment in segments:
		duration_ms += int(segment["duration_ms"])
	if segments.size() > MAX_SEGMENTS:
		return {"ok": false, "segments": [], "duration_ms": duration_ms,
			"err": "该轨道解析后有 %d 个片段，超过上限 %d" % [segments.size(), MAX_SEGMENTS]}
	if duration_ms > MAX_DURATION_MS:
		return {"ok": false, "segments": [], "duration_ms": duration_ms,
			"err": "该轨道时长超过 20 分钟上限"}
	if not polyphonic:
		var single_segments: Array = []
		for segment in segments:
			var notes: Array = segment["notes"]
			single_segments.append({
				"note": int(notes[0]) if not notes.is_empty() else 0,
				"duration_ms": int(segment["duration_ms"]),
			})
		return {"ok": true, "segments": single_segments, "duration_ms": duration_ms, "err": ""}
	return {"ok": true, "segments": segments, "duration_ms": duration_ms, "err": ""}


static func _tick_to_us(tick: int, tempos: Array, ppq: int) -> int:
	var current_tick: int = 0
	var current_tempo: int = DEFAULT_TEMPO_US_PER_QUARTER
	var elapsed: float = 0.0
	for tempo_event in tempos:
		var tempo_tick: int = int(tempo_event["tick"])
		if tempo_tick > tick:
			break
		if tempo_tick > current_tick:
			elapsed += float(tempo_tick - current_tick) * float(current_tempo) / float(ppq)
			current_tick = tempo_tick
		current_tempo = int(tempo_event["tempo"])
	if tick > current_tick:
		elapsed += float(tick - current_tick) * float(current_tempo) / float(ppq)
	return int(round(elapsed))


static func _tempo_sort(tempos: Array) -> void:
	tempos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tick"]) == int(b["tick"]):
			return int(a["order"]) < int(b["order"])
		return int(a["tick"]) < int(b["tick"])
	)


static func _read_vlq(bytes: PackedByteArray, start: int, end: int) -> Dictionary:
	var value: int = 0
	var pos: int = start
	for _i in range(4):
		if pos >= end:
			return {"ok": false, "value": 0, "next": pos}
		var raw: int = int(bytes[pos])
		pos += 1
		value = (value << 7) | (raw & 0x7f)
		if (raw & 0x80) == 0:
			return {"ok": true, "value": value, "next": pos}
	return {"ok": false, "value": 0, "next": pos}


static func _system_event_size(status: int) -> int:
	match status:
		0xf1, 0xf3:
			return 1
		0xf2:
			return 2
		0xf6, 0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe:
			return 0
		_:
			return -1


static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 8) | int(bytes[offset + 1])


static func _u32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) \
		| (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


static func _ascii(bytes: PackedByteArray, offset: int, length: int) -> String:
	var text: String = ""
	for i in range(length):
		text += String.chr(int(bytes[offset + i]))
	return text


static func _decode_text(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	var text: String = bytes.get_string_from_utf8().strip_edges()
	return text if not text.is_empty() else "未命名轨道"


static func _error(message: String) -> Dictionary:
	return {"ok": false, "err": message, "tracks": []}
