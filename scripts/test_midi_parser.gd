extends SceneTree

## MIDI 解析器离线测试，不读取外部 MIDI 文件。

const Midi = preload("res://scripts/midi_parser.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _be16(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 8) & 0xff, value & 0xff])


func _be32(value: int) -> PackedByteArray:
	return PackedByteArray([
		(value >> 24) & 0xff, (value >> 16) & 0xff,
		(value >> 8) & 0xff, value & 0xff,
	])


func _vlq(value: int) -> PackedByteArray:
	var remaining: int = maxi(0, value)
	var raw: Array[int] = [remaining & 0x7f]
	remaining >>= 7
	while remaining > 0:
		raw.push_front((remaining & 0x7f) | 0x80)
		remaining >>= 7
	return PackedByteArray(raw)


func _event(delta: int, payload: Array[int]) -> PackedByteArray:
	var result: PackedByteArray = _vlq(delta)
	for value in payload:
		result.append(value)
	return result


func _track(payload: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray([0x4d, 0x54, 0x72, 0x6b])
	result.append_array(_be32(payload.size()))
	result.append_array(payload)
	return result


func _file(format: int, tracks: Array[PackedByteArray], division: int = 480) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray([0x4d, 0x54, 0x68, 0x64])
	result.append_array(_be32(6))
	result.append_array(_be16(format))
	result.append_array(_be16(tracks.size()))
	result.append_array(_be16(division))
	for track in tracks:
		result.append_array(track)
	return result


func _end() -> PackedByteArray:
	return _event(0, [0xff, 0x2f, 0x00])


func _format0_track() -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(_event(0, [0xff, 0x03, 0x04, 0x54, 0x65, 0x73, 0x74]))
	payload.append_array(_event(0, [0xff, 0x51, 0x03, 0x07, 0xa1, 0x20]))
	payload.append_array(_event(0, [0x90, 60, 64]))
	payload.append_array(_event(480, [0x80, 60, 64]))
	# Running status：沿用 note-on，velocity=0 作为 note-off。
	payload.append_array(_event(0, [0x90, 64, 64]))
	payload.append_array(_event(240, [64, 0]))
	payload.append_array(_end())
	return _track(payload)


func _tempo_track() -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	# 0.5 秒/四分音符，480 tick 后改成 0.25 秒/四分音符。
	payload.append_array(_event(0, [0xff, 0x51, 0x03, 0x07, 0xa1, 0x20]))
	payload.append_array(_event(480, [0xff, 0x51, 0x03, 0x03, 0xd0, 0x90]))
	payload.append_array(_end())
	return _track(payload)


func _format1_melody_track() -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(_event(0, [0xff, 0x03, 0x05, 0x4d, 0x65, 0x6c, 0x6f, 0x64]))
	payload.append_array(_event(0, [0x90, 69, 80]))
	payload.append_array(_event(480, [0x80, 69, 80]))
	payload.append_array(_event(480, [0x90, 70, 80]))
	payload.append_array(_event(480, [0x80, 70, 80]))
	payload.append_array(_end())
	return _track(payload)


func _overlap_track() -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(_event(0, [0x90, 60, 64]))
	payload.append_array(_event(0, [0x90, 64, 64]))
	payload.append_array(_event(240, [0x80, 64, 64]))
	payload.append_array(_event(240, [0x80, 60, 64]))
	payload.append_array(_end())
	return _track(payload)


func _track_with_many_segments(count: int) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	for index in range(count):
		var note: int = 60 if index % 2 == 0 else 61
		payload.append_array(_event(0, [0x90, note, 64]))
		payload.append_array(_event(1, [0x80, note, 64]))
	payload.append_array(_end())
	return _track(payload)


func _track_with_duration(ticks: int) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(_event(0, [0x90, 60, 64]))
	payload.append_array(_event(ticks, [0x80, 60, 64]))
	payload.append_array(_end())
	return _track(payload)


func _track_at_tempo_only() -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(_event(0, [0xff, 0x51, 0x03, 0x07, 0xa1, 0x20]))
	payload.append_array(_end())
	return _track(payload)


func _notes_track(track_name: String, notes: Array[int], duration: int = 480) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	var name_bytes: PackedByteArray = track_name.to_utf8_buffer()
	payload.append_array(_event(0, [0xff, 0x03, name_bytes.size()]))
	payload.append_array(name_bytes)
	for note in notes:
		payload.append_array(_event(0, [0x90, note, 64]))
	for index in range(notes.size()):
		payload.append_array(_event(duration if index == 0 else 0,
			[0x80, notes[index], 64]))
	payload.append_array(_end())
	return _track(payload)


func _initialize() -> void:
	print("=== MIDI 解析器测试 ===\n")
	var format0: Dictionary = Midi.parse_bytes(_file(0, [_format0_track()]), "format0.mid")
	_check("格式 0 解析成功", bool(format0.get("ok", false)), str(format0.get("err", "")))
	_check("格式 0 轨道摘要与名称", format0.get("track_count", 0) == 1
		and format0["tracks"][0]["name"] == "Test")
	var segments0: Array = format0["tracks"][0]["segments"]
	_check("running status 与 velocity=0 可解析", segments0 == [
		{"note": 60, "duration_ms": 500},
		{"note": 64, "duration_ms": 250},
	], JSON.stringify(segments0))
	_check("格式 0 标记为可播放", bool(format0["has_playable_track"]))

	var format1: Dictionary = Midi.parse_bytes(_file(1, [_tempo_track(), _format1_melody_track()]))
	_check("格式 1 tempo 轨与旋律轨解析", bool(format1.get("ok", false)))
	_check("全局 tempo map 精确换算", format1["tracks"][1]["segments"] == [
		{"note": 69, "duration_ms": 500},
		{"note": 0, "duration_ms": 250},
		{"note": 70, "duration_ms": 250},
	], JSON.stringify(format1["tracks"][1]["segments"]))
	_check("轨道名保留", format1["tracks"][1]["name"] == "Melod")
	var merged_tempo: Dictionary = Midi.merge_tracks(format1, [1])
	_check("多轨接口沿用全局 tempo map", bool(merged_tempo.get("ok", false))
		and merged_tempo["segments"] == [
			{"notes": [69], "duration_ms": 500},
			{"notes": [], "duration_ms": 250},
			{"notes": [70], "duration_ms": 250},
		], JSON.stringify(merged_tempo))

	var overlap: Dictionary = Midi.parse_bytes(_file(0, [_overlap_track()]))
	_check("重叠音符取最高音", overlap["tracks"][0]["segments"] == [
		{"note": 64, "duration_ms": 250},
		{"note": 60, "duration_ms": 250},
	])

	var multi: Dictionary = Midi.parse_bytes(_file(1, [
		_tempo_track(), _notes_track("上声部", [60, 64]), _notes_track("重复声部", [60, 67]),
	]))
	var merged: Dictionary = Midi.merge_tracks(multi, [1, 2])
	_check("多轨重叠合并为音符集合", bool(merged.get("ok", false))
		and merged["segments"] == [{"notes": [67, 64, 60], "duration_ms": 500}],
		JSON.stringify(merged))
	var duplicate_merged: Dictionary = Midi.merge_tracks(multi, [1, 1, 2])
	_check("多轨同音符去重", bool(duplicate_merged.get("ok", false))
		and (duplicate_merged["segments"][0]["notes"] as Array).size() == 3)
	var five_tracks: Array[PackedByteArray] = [_tempo_track()]
	for note in [60, 62, 64, 65, 67]:
		five_tracks.append(_notes_track("声部", [note]))
	var four: Dictionary = Midi.merge_tracks(Midi.parse_bytes(_file(1, five_tracks)), [1, 2, 3, 4, 5])
	_check("超过四声部时保留最高四音", bool(four.get("ok", false))
		and four["segments"][0]["notes"] == [67, 65, 64, 62], JSON.stringify(four))
	var invalid_track: Dictionary = Midi.merge_tracks(multi, [99])
	_check("多轨索引越界返回错误", not bool(invalid_track.get("ok", false)))
	var empty_selection: Dictionary = Midi.merge_tracks(multi, [])
	_check("多轨空选择返回错误", not bool(empty_selection.get("ok", false)))

	var invalid: Dictionary = Midi.parse_bytes(PackedByteArray([0x00, 0x01]))
	_check("截断文件返回错误", not bool(invalid.get("ok", false)))
	var bad_chunk: PackedByteArray = _file(0, [_format0_track()])
	bad_chunk[14] = 0x58
	_check("非法 MTrk chunk 返回错误", not bool(Midi.parse_bytes(bad_chunk).get("ok", false)))
	var format2: PackedByteArray = _file(2, [_format0_track()])
	_check("不支持格式返回错误", not bool(Midi.parse_bytes(format2).get("ok", false)))
	var smpte: PackedByteArray = _file(0, [_format0_track()], 0xe728)
	_check("不支持 SMPTE 分辨率返回错误", not bool(Midi.parse_bytes(smpte).get("ok", false)))
	var no_notes: Dictionary = Midi.parse_bytes(_file(0, [_track_at_tempo_only()]))
	_check("无音符轨道不标记为可播放", bool(no_notes.get("ok", false))
		and not bool(no_notes.get("has_playable_track", true)))

	var too_many: Dictionary = Midi.parse_bytes(_file(0, [_track_with_many_segments(Midi.MAX_SEGMENTS + 1)]))
	_check("片段数超过 8192 时阻止生成", not str(too_many["tracks"][0]["error"]).is_empty())
	var too_long: Dictionary = Midi.parse_bytes(_file(0, [_track_with_duration(1200001)]))
	_check("时长超过 20 分钟时阻止生成", not str(too_long["tracks"][0]["error"]).is_empty())

	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)
