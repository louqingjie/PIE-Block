extends PanelContainer

signal step_pressed(step: int)

const EXPANDED_WIDTH: float = 250.0
const COLLAPSED_WIDTH: float = 40.0

const P_TITLE: NodePath = "Margin/Content/Header/Title"
const P_TOGGLE: NodePath = "Margin/Content/Header/Toggle"
const P_PROGRESS: NodePath = "Margin/Content/Progress"
const P_STATUS: NodePath = "Margin/Content/Status"
const P_STEPS: NodePath = "Margin/Content/Steps"
const P_HINT: NodePath = "Margin/Content/Hint"

var _buttons: Array[Button] = []
var _titles: Array[String] = []
var _hints: Array[String] = []
var _done: Array[bool] = []
var _collapsed: bool = false


func _ready() -> void:
	var toggle: Node = get_node_or_null(P_TOGGLE)
	if toggle is BaseButton:
		toggle.pressed.connect(_toggle_collapsed)


func setup(titles: Array[String], hints: Array[String], done: Array[bool]) -> void:
	_titles = titles.duplicate()
	_hints = hints.duplicate()
	_done = done.duplicate()
	_rebuild_buttons()
	_update_display()


func set_state(titles: Array[String], hints: Array[String], done: Array[bool]) -> void:
	_titles = titles.duplicate()
	_hints = hints.duplicate()
	_done = done.duplicate()
	if _buttons.size() != _titles.size():
		_rebuild_buttons()
	_update_display()


func get_step_count() -> int:
	return _buttons.size()


func _rebuild_buttons() -> void:
	var steps: Node = get_node_or_null(P_STEPS)
	if not steps is VBoxContainer:
		return
	for child in steps.get_children():
		child.queue_free()
	_buttons.clear()
	for i in range(_titles.size()):
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 38)
		button.pressed.connect(_on_step_pressed.bind(i))
		steps.add_child(button)
		_buttons.append(button)


func _update_display() -> void:
	var completed: int = 0
	for i in range(_buttons.size()):
		var is_done: bool = i < _done.size() and _done[i]
		if is_done:
			completed += 1
		_buttons[i].text = "%s %d  %s" % [
			"🟢" if is_done else "🔴", i + 1, _titles[i]]
	var progress: Node = get_node_or_null(P_PROGRESS)
	if progress is ProgressBar:
		progress.max_value = _titles.size()
		progress.value = completed
	var status: Node = get_node_or_null(P_STATUS)
	if status is Label:
		status.text = "%d / %d 步完成" % [completed, _titles.size()]


func _on_step_pressed(step: int) -> void:
	var hint: Node = get_node_or_null(P_HINT)
	if hint is Label and step < _hints.size():
		hint.text = _hints[step]
	step_pressed.emit(step)


func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	custom_minimum_size.x = COLLAPSED_WIDTH if _collapsed else EXPANDED_WIDTH
	for path in [P_TITLE, P_PROGRESS, P_STATUS, P_STEPS, P_HINT]:
		var node: Node = get_node_or_null(path)
		if node is CanvasItem:
			node.visible = not _collapsed
	var toggle: Node = get_node_or_null(P_TOGGLE)
	if toggle is Button:
		toggle.text = ">" if _collapsed else "<"
		toggle.tooltip_text = "展开项目引导" if _collapsed else "收起项目引导"
