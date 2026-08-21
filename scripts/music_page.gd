class_name MusicPage
extends VBoxContainer

## 音乐项目配置页：导入 MIDI、选择单轨并保存解析后的播放片段。

const MIDI = preload("res://scripts/midi_parser.gd")
const WEB = preload("res://scripts/web_support.gd")

signal music_changed

var _parse_result: Dictionary = {}
var _music: Dictionary = {
	"source_name": "",
	"track_index": -1,
	"track_name": "",
	"track_count": 0,
	"duration_ms": 0,
	"segments": [],
}
var _parse_error: String = ""


func _ready() -> void:
	var open_button: Node = get_node_or_null("Open")
	if open_button is BaseButton:
		open_button.pressed.connect(_on_open_pressed)
	var track_button: Node = get_node_or_null("Track")
	if track_button is OptionButton:
		track_button.item_selected.connect(_on_track_selected)
	var dialog: Node = get_node_or_null("MidiDialog")
	if dialog is FileDialog:
		dialog.file_selected.connect(_on_file_selected)
	_refresh_view()


func get_music_data() -> Dictionary:
	return _music.duplicate(true)


func get_parse_error() -> String:
	return _parse_error


func set_music_data(data: Dictionary) -> void:
	_music = {
		"source_name": str(data.get("source_name", "")),
		"track_index": int(data.get("track_index", -1)),
		"track_name": str(data.get("track_name", "")),
		"track_count": int(data.get("track_count", 0)),
		"duration_ms": int(data.get("duration_ms", 0)),
		"segments": (data.get("segments", []) as Array).duplicate(true)
			if data.get("segments", []) is Array else [],
	}
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
	var tracks: Array = result.get("tracks", [])
	var first_playable: int = -1
	for track in tracks:
		if str(track.get("error", "")).is_empty() and not (track.get("segments", []) as Array).is_empty():
			first_playable = int(track.get("index", -1))
			break
	if first_playable < 0:
		_parse_error = "MIDI 文件中没有包含可播放音符的轨道"
		_music = _empty_music()
	else:
		_select_parsed_track(first_playable)
	_refresh_view()
	music_changed.emit()


func _on_track_selected(selected: int) -> void:
	var track_button: Node = get_node_or_null("Track")
	if not track_button is OptionButton or selected < 0 or selected >= track_button.item_count:
		return
	var track_index: int = int(track_button.get_item_metadata(selected))
	_select_parsed_track(track_index)
	_refresh_view()
	music_changed.emit()


func _select_parsed_track(track_index: int) -> void:
	for track in _parse_result.get("tracks", []):
		if int(track.get("index", -1)) != track_index:
			continue
		_music = {
			"source_name": str(_parse_result.get("source_name", "")),
			"track_index": track_index,
			"track_name": str(track.get("name", "")),
			"track_count": int(_parse_result.get("track_count", 0)),
			"duration_ms": int(track.get("duration_ms", 0)),
			"segments": (track.get("segments", []) as Array).duplicate(true),
		}
		return


func _refresh_view() -> void:
	var source_label: Node = get_node_or_null("Source")
	if source_label is Label:
		source_label.text = "未选择 MIDI 文件" if str(_music.get("source_name", "")).is_empty() \
			else "文件：%s" % str(_music.get("source_name", ""))
	var status: Node = get_node_or_null("Status")
	if status is Label:
		if not _parse_error.is_empty():
			status.text = "解析失败：%s" % _parse_error
		elif int(_music.get("track_index", -1)) < 0:
			status.text = "请选择一个包含音符的轨道"
		else:
			status.text = "轨道 %d：%s · %d 个片段 · %s" % [
				int(_music.get("track_index", -1)) + 1,
				str(_music.get("track_name", "未命名轨道")),
				(_music.get("segments", []) as Array).size(),
				_format_duration(int(_music.get("duration_ms", 0))),
			]
		_populate_track_button()


func _populate_track_button() -> void:
	var track_button: Node = get_node_or_null("Track")
	if not track_button is OptionButton:
		return
	track_button.clear()
	if _parse_result.is_empty():
		if int(_music.get("track_index", -1)) >= 0:
			track_button.add_item("已保存轨道 %d · %s" % [
				int(_music.get("track_index", -1)) + 1,
				str(_music.get("track_name", "未命名轨道"))])
			track_button.set_item_metadata(0, int(_music.get("track_index", -1)))
			track_button.select(0)
		return
	var selected_item: int = -1
	for track in _parse_result.get("tracks", []):
		var label: String = "轨道 %d · %s · %d 音符 · %s" % [
			int(track.get("index", 0)) + 1,
			str(track.get("name", "未命名轨道")) if not str(track.get("name", "")).is_empty() else "未命名轨道",
			int(track.get("note_count", 0)),
			_format_duration(int(track.get("duration_ms", 0))),
		]
		var item: int = track_button.item_count
		track_button.add_item(label)
		track_button.set_item_metadata(item, int(track.get("index", -1)))
		var unavailable: bool = not str(track.get("error", "")).is_empty() \
			or (track.get("segments", []) as Array).is_empty()
		track_button.set_item_disabled(item, unavailable)
		if int(track.get("index", -1)) == int(_music.get("track_index", -1)):
			selected_item = item
	if selected_item >= 0:
		track_button.select(selected_item)


func _format_duration(duration_ms: int) -> String:
	if duration_ms <= 0:
		return "0 秒"
	var seconds: int = int(round(float(duration_ms) / 1000.0))
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _empty_music() -> Dictionary:
	return {
		"source_name": "",
		"track_index": -1,
		"track_name": "",
		"track_count": 0,
		"duration_ms": 0,
		"segments": [],
	}
