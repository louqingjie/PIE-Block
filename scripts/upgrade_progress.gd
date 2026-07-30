class_name UpgradeProgress
extends Control

signal closed


static func compile_error_hint(project_stage: int) -> String:
	if project_stage < 2:
		return "请联系项目负责人，并附带项目文件。\n现在也可以考虑使用 AI 修复编译错误。"
	return "请用 AI 修复错误，或重新进入配置阶段。"

@onready var _title: Label = get_node("Dim/Center/Panel/Content/Title")
@onready var _stage: Label = get_node("Dim/Center/Panel/Content/Stage")
@onready var _progress: ProgressBar = get_node("Dim/Center/Panel/Content/Progress")
@onready var _detail: Label = get_node("Dim/Center/Panel/Content/Detail")
@onready var _close: Button = get_node("Dim/Center/Panel/Content/Close")


func _ready() -> void:
	_close.pressed.connect(_on_close_pressed)
	hide()


func begin() -> void:
	_title.text = "升级主控板"
	_close.hide()
	set_progress("准备升级", 2.0, "正在保存当前程序…")
	show()


func set_progress(stage_text: String, value: float, detail_text: String = "") -> void:
	_stage.text = stage_text
	_progress.value = clampf(value, 0.0, 100.0)
	_detail.text = detail_text


func complete() -> void:
	_title.text = "升级完成"
	set_progress("主控板已运行新程序", 100.0)
	_close.text = "完成"
	_close.show()


func fail(stage_text: String, detail_text: String) -> void:
	_title.text = "升级未完成"
	_stage.text = stage_text
	_detail.text = detail_text
	_close.text = "关闭"
	_close.show()


func _on_close_pressed() -> void:
	hide()
	closed.emit()