class_name MusicPage
extends VBoxContainer

## 音乐项目配置页：导入 MIDI、选择一条或多条轨道，并保存合并后的播放片段。
## 多轨模式是明确开启的时间片伪复音：生成器最多轮换四个最高音符。

const MIDI = preload("res://scripts/midi_parser.gd")
const WEB = preload("res://scripts/web_support.gd")
const MAX_VOICES: int = 4

signal music_changed

var _parse_result: Dictionary = {}
var _music: Dictionary = _empty_music()
var _parse_error: String = ""
var _updating_tracks: bool = false


func _ready() -> void:
	var open_button: Node = get_node_or_null("Open")
	if open_button is BaseButton:
		open_button.pressed.connect(_on_open_pressed)
	var polyphonic_button: Node = get_node_or_null("Polyphonic")
	if polyphonic_button is BaseButton:
		polyphonic_button.toggled.connect(_on_polyphonic_toggled)
	var dialog: Node = get_node_or_null("MidiDialog")
	if dialog is FileDialog:
		dialog.file_selected.connect(_on_file_selected)
	_refresh_view()


func get_music_data() -> Dictionary:
	return _music.duplicate(true)


func get_parse_error() -> String:
	return _parse_error


func set_music_data(data: Dictionary) -> void:
	_music = _canonical_music(data)
	_parse_result = {}
	_parse_error = ""
	_refresh_view()


func _on_open_pressed() -> void:
	# MIDI 导入依赖 Windows 原生文件对话框；其他平台仍可打开、检查和生成
	# 已保存了解析结果的音乐项目。
	if not WEB.is_desktop() or not OS.has_feature("windows"):
		WEB.popup_desktop_only(self, "MIDI 导入")
		return
	var dialog: Node = get_node_or_null("MidiDialog")
	if dialog is FileDialog:
		dialog.popup_centered(Vector2i(760, 520))


func _on_file_selected(path: String) -> void:
	var result: Dictionary = MIDI.parse_file(path)
	if not result.get("ok", false):
		_parse_result = {}
		_parse_error = str(result.get("err", "MIDI 解析失败"))
		_music = _empty_music()
		_refresh_view()
		music_changed.emit()
		return
	_parse_result = result
	_parse_error = ""
	var first_playable: int = -1
	for track in result.get("tracks", []):
		if str(track.get("error", "")).is_empty() \
			and not (track.get("intervals", []) as Array).is_empty():
			first_playable = int(track.get("index", -1))
			break
	if first_playable < 0:
		_parse_error = "MIDI 文件中没有包含可播放音符的轨道"
		_music = _empty_music()
	else:
		_music = _empty_music()
		_music["source_name"] = str(result.get("source_name", ""))
		_music["track_count"] = int(result.get("track_count", 0))
		_music["polyphonic"] = false
		_apply_selection([first_playable])
	_refresh_view()
	music_changed.emit()


func _on_polyphonic_toggled(enabled: bool) -> void:
	if _updating_tracks:
		return
	_music["polyphonic"] = enabled
	var selected: Array = _selected_track_indices()
	if not enabled and selected.size() > 1:
		selected = [selected[0]]
		_set_track_buttons(selected)
	_apply_selection(selected)
	_refresh_view()
	music_changed.emit()


func _on_track_toggled(track_index: int, pressed: bool) -> void:
	if _updating_tracks:
		return
	var selected: Array = _selected_track_indices()
	if not bool(_music.get("polyphonic", false)) and pressed:
		selected = [track_index]
		_set_track_buttons(selected)
	_apply_selection(selected)
	_refresh_view()
	music_changed.emit()
	return
	_apply_selection(selected)
	_refresh_view()
	music_changed.emit()


func _selected_track_indices() -> Array:
	var selected: Array = []
	var list: Node = get_node_or_null("TrackScroll/TrackList")
	if list == null:
		return selected
	for child in list.get_children():
		if child is CheckButton and child.button_pressed:
			selected.append(int(child.get_meta("track_index", -1)))
	return selected


func _apply_selection(selected: Array) -> void:
	var valid: Array = []
	var seen: Dictionary = {}
	for raw_index in selected:
		var index: int = int(raw_index)
		if index < 0 or seen.has(index):
			continue
		seen[index] = true
		valid.append(index)
	if not bool(_music.get("polyphonic", false)) and valid.size() > 1:
		valid = [valid[0]]
	if _parse_result.is_empty():
		_music["track_indices"] = valid
		_music["track_index"] = int(valid[0]) if not valid.is_empty() else -1
		var names: Array = []
		var stored_names: Array = _music.get("track_names", []) as Array
		for index in range(valid.size()):
			names.append(str(stored_names[index]) if index < stored_names.size() else "")
		_music["track_names"] = names
		_music["track_name"] = str(names[0]) if not names.is_empty() else ""
		if valid.is_empty():
			_music["segments"] = []
			_music["duration_ms"] = 0
		return
	var merged: Dictionary = MIDI.merge_tracks(_parse_result, valid,
		4 if bool(_music.get("polyphonic", false)) else 1)
	if not merged.get("ok", true) and not str(merged.get("err", "")).is_empty():
		_parse_error = str(merged.get("err", "轨道合并失败"))
		_music["segments"] = []
		_music["duration_ms"] = 0
		return
	var names_from_result: Array = []
	for index in valid:
		for track in _parse_result.get("tracks", []):
			if int(track.get("index", -1)) == index:
				names_from_result.append(str(track.get("name", "")))
				break
	_music["source_name"] = str(_parse_result.get("source_name", ""))
	_music["track_count"] = int(_parse_result.get("track_count", 0))
	_music["track_indices"] = valid
	_music["track_index"] = int(valid[0]) if not valid.is_empty() else -1
	_music["track_names"] = names_from_result
	_music["track_name"] = str(names_from_result[0]) if not names_from_result.is_empty() else ""
	_music["segments"] = (merged.get("segments", []) as Array).duplicate(true)
	_music["duration_ms"] = int(merged.get("duration_ms", 0))
	_parse_error = ""


func _refresh_view() -> void:
	var source_label: Node = get_node_or_null("Source")
	if source_label is Label:
		source_label.text = "未选择 MIDI 文件" if str(_music.get("source_name", "")).is_empty() \
			else "文件：%s" % str(_music.get("source_name", ""))
	var polyphonic_button: Node = get_node_or_null("Polyphonic")
	if polyphonic_button is BaseButton:
		_updating_tracks = true
		polyphonic_button.button_pressed = bool(_music.get("polyphonic", false))
		_updating_tracks = false
	_populate_track_list()
	var status: Node = get_node_or_null("Status")
	if status is Label:
		if not _parse_error.is_empty():
			status.text = "解析失败：%s" % _parse_error
		elif int(_music.get("track_index", -1)) < 0 \
			or (_music.get("segments", []) as Array).is_empty():
			status.text = "请选择至少一条包含音符的轨道"
		else:
			var selected_count: int = (_music.get("track_indices", []) as Array).size()
			var mode: String = "四声部伪复音" if bool(_music.get("polyphonic", false)) else "单音"
			status.text = "%s · 已选 %d 条轨道 · %d 个片段 · %s · 最多 4 声部，每声部 5ms 轮换" % [
				mode, selected_count, (_music.get("segments", []) as Array).size(),
				_format_duration(int(_music.get("duration_ms", 0))),
			]


func _populate_track_list() -> void:
	var list: Node = get_node_or_null("TrackScroll/TrackList")
	if list == null:
		return
	_updating_tracks = true
	for child in list.get_children():
		child.free()
	var selected: Array = _music.get("track_indices", []) as Array
	if not _parse_result.is_empty():
		for track in _parse_result.get("tracks", []):
			_add_track_button(track, selected)
	else:
		var names: Array = _music.get("track_names", []) as Array
		for index in range(int(_music.get("track_count", 0))):
			var name: String = str(names[index]) if index < names.size() else ""
			_add_track_button({
				"index": index, "name": name, "note_count": 0,
				"duration_ms": int(_music.get("duration_ms", 0)) if index == int(_music.get("track_index", -1)) else 0,
				"error": "",
			}, selected)
	_updating_tracks = false


func _add_track_button(track: Dictionary, selected: Array) -> void:
	var list: Node = get_node_or_null("TrackScroll/TrackList")
	if list == null:
		return
	var index: int = int(track.get("index", -1))
	var name: String = str(track.get("name", ""))
	if name.is_empty():
		name = "未命名轨道"
	var button := CheckButton.new()
	button.text = "轨道 %d · %s · %d 音符 · %s" % [
		index + 1, name, int(track.get("note_count", 0)),
		_format_duration(int(track.get("duration_ms", 0))),
	]
	button.set_meta("track_index", index)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.button_pressed = index in selected
	var unavailable: bool = not str(track.get("error", "")).is_empty() \
		or (not _parse_result.is_empty() and (track.get("intervals", []) as Array).is_empty())
	button.disabled = unavailable
	button.toggled.connect(_on_track_toggled.bind(index))
	list.add_child(button)


func _set_track_buttons(selected: Array) -> void:
	var list: Node = get_node_or_null("TrackScroll/TrackList")
	if list == null:
		return
	_updating_tracks = true
	for child in list.get_children():
		if child is CheckButton:
			child.button_pressed = int(child.get_meta("track_index", -1)) in selected
	_updating_tracks = false


func _format_duration(duration_ms: int) -> String:
	if duration_ms <= 0:
		return "0 秒"
	var seconds: int = int(round(float(duration_ms) / 1000.0))
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _canonical_music(data: Dictionary) -> Dictionary:
	var result: Dictionary = _empty_music()
	for key in result.keys():
		if data.has(key):
			result[key] = data[key]
	result["source_name"] = str(result.get("source_name", ""))
	result["polyphonic"] = bool(result.get("polyphonic", false))
	result["track_count"] = maxi(0, int(result.get("track_count", 0)))
	var indices: Array = []
	var raw_indices: Variant = data.get("track_indices", [])
	if raw_indices is Array and not (raw_indices as Array).is_empty():
		indices = raw_indices.duplicate()
	elif data.has("track_index"):
		indices = [data.get("track_index", -1)]
	var valid: Array = []
	for value in indices:
		var index: int = int(value)
		if index >= 0 and index < int(result["track_count"]) and index not in valid:
			valid.append(index)
	if not bool(result["polyphonic"]) and valid.size() > 1:
		valid = [valid[0]]
	result["track_indices"] = valid
	result["track_index"] = int(valid[0]) if not valid.is_empty() else -1
	var names: Array = []
	var raw_names: Variant = data.get("track_names", [])
	for index in range(valid.size()):
		if raw_names is Array and index < (raw_names as Array).size():
			names.append(str(raw_names[index]))
		elif index == 0:
			names.append(str(data.get("track_name", "")))
		else:
			names.append("")
	result["track_names"] = names
	result["track_name"] = str(names[0]) if not names.is_empty() else ""
	var canonical_segments: Array = []
	var raw_segments: Variant = data.get("segments", [])
	if raw_segments is Array:
		for raw_segment in raw_segments:
			if not raw_segment is Dictionary:
				continue
			var segment: Dictionary = raw_segment
			var duration: int = int(segment.get("duration_ms", 0))
			if duration < 1:
				continue
			var notes: Array = []
			if segment.has("notes") and segment["notes"] is Array:
				notes = segment["notes"].duplicate()
			elif segment.has("note"):
				var old_note: int = int(segment.get("note", 0))
				if old_note > 0:
					notes = [old_note]
			var filtered: Array = []
			for value in notes:
				var note: int = int(value)
				if note >= 1 and note <= 127 and note not in filtered:
					filtered.append(note)
			filtered.sort()
			filtered.reverse()
			if filtered.size() > MAX_VOICES:
				filtered = filtered.slice(0, MAX_VOICES)
			canonical_segments.append({"notes": filtered, "duration_ms": duration})
	result["segments"] = canonical_segments
	var total: int = 0
	for segment in canonical_segments:
		total += int(segment["duration_ms"])
	result["duration_ms"] = total
	if result["track_index"] < 0:
		result["segments"] = []
		result["duration_ms"] = 0
	return result


func _empty_music() -> Dictionary:
	return {
		"source_name": "", "polyphonic": false,
		"track_index": -1, "track_indices": [],
		"track_name": "", "track_names": [],
		"track_count": 0, "duration_ms": 0, "segments": [],
	}
