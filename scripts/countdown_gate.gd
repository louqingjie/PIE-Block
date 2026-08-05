extends Control

signal confirmed
signal canceled

const DEFAULT_SECONDS: int = 10
const P_TITLE: NodePath = "VBoxContainer/HBoxContainer/Label"
const P_MESSAGE: NodePath = "VBoxContainer/Label"
const P_PRIMARY: NodePath = "VBoxContainer/HBoxContainer2/Button"
const P_SECONDARY: NodePath = "VBoxContainer/HBoxContainer2/Button2"
const P_ERROR_TEXT: NodePath = "VBoxContainer/TextEdit"

var _countdown_seconds: int = DEFAULT_SECONDS
var _remaining_seconds: int = DEFAULT_SECONDS
var _base_title_text: String = ""
var _base_message_text: String = ""
var _base_primary_text: String = ""
var _base_secondary_text: String = ""
var _body_text: String = ""
var _error_text: String = ""
var _timer: Timer = null


func _ready() -> void:
	_cache_base_texts()
	_ensure_timer()
	_connect_buttons()
	_refresh_texts()
	_start_countdown()


func configure(title_text: String = "", body_text: String = "", primary_text: String = "",
		secondary_text: String = "", countdown_seconds: int = DEFAULT_SECONDS,
		error_text: String = "") -> void:
	if countdown_seconds > 0:
		_countdown_seconds = countdown_seconds
		_remaining_seconds = countdown_seconds
	_body_text = body_text
	_error_text = error_text
	if not title_text.is_empty():
		_base_title_text = title_text
	if not primary_text.is_empty():
		_base_primary_text = primary_text
	if not secondary_text.is_empty():
		_base_secondary_text = secondary_text
	_refresh_texts()
	if is_inside_tree():
		_start_countdown()


func _cache_base_texts() -> void:
	var title: Node = get_node_or_null(P_TITLE)
	if title is Label and _base_title_text.is_empty():
		_base_title_text = title.text
	var message: Node = get_node_or_null(P_MESSAGE)
	if message is Label and _base_message_text.is_empty():
		_base_message_text = message.text
	var primary: Node = get_node_or_null(P_PRIMARY)
	if primary is BaseButton and _base_primary_text.is_empty():
		_base_primary_text = primary.text
	var secondary: Node = get_node_or_null(P_SECONDARY)
	if secondary is BaseButton and _base_secondary_text.is_empty():
		_base_secondary_text = secondary.text


func _ensure_timer() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_countdown_tick)
	add_child(_timer)


func _connect_buttons() -> void:
	var primary: Node = get_node_or_null(P_PRIMARY)
	if primary is BaseButton and not primary.pressed.is_connected(_on_primary_pressed):
		primary.pressed.connect(_on_primary_pressed)
	var secondary: Node = get_node_or_null(P_SECONDARY)
	if secondary is BaseButton and not secondary.pressed.is_connected(_on_secondary_pressed):
		secondary.pressed.connect(_on_secondary_pressed)


func _refresh_texts() -> void:
	var title: Node = get_node_or_null(P_TITLE)
	if title is Label and not _base_title_text.is_empty():
		title.text = _base_title_text
	var message: Node = get_node_or_null(P_MESSAGE)
	if message is Label:
		if not _body_text.is_empty():
			message.text = _body_text
		elif not _base_message_text.is_empty():
			message.text = _base_message_text
	var error_text: Node = get_node_or_null(P_ERROR_TEXT)
	if error_text is TextEdit:
		if not _error_text.is_empty():
			error_text.text = _error_text
		elif not _body_text.is_empty():
			error_text.text = _body_text
	var primary: Node = get_node_or_null(P_PRIMARY)
	if primary is BaseButton and not _base_primary_text.is_empty():
		primary.text = _countdown_label()
	var secondary: Node = get_node_or_null(P_SECONDARY)
	if secondary is BaseButton and not _base_secondary_text.is_empty():
		secondary.text = _base_secondary_text


func _start_countdown() -> void:
	_remaining_seconds = max(1, _countdown_seconds)
	var primary: Node = get_node_or_null(P_PRIMARY)
	if primary is BaseButton:
		primary.disabled = true
		primary.text = _countdown_label()
	if _timer != null:
		_timer.stop()
		_timer.start()


func _countdown_label() -> String:
	return "%s（%d秒）" % [_base_primary_text, _remaining_seconds]


func _on_countdown_tick() -> void:
	if _remaining_seconds > 0:
		_remaining_seconds -= 1
	var primary: Node = get_node_or_null(P_PRIMARY)
	if primary is BaseButton:
		if _remaining_seconds <= 0:
			primary.text = _base_primary_text
			primary.disabled = false
			if _timer != null:
				_timer.stop()
		else:
			primary.text = _countdown_label()


func _on_primary_pressed() -> void:
	if _remaining_seconds > 0:
		return
	emit_signal("confirmed")


func _on_secondary_pressed() -> void:
	emit_signal("canceled")
