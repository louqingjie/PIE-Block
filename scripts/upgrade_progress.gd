class_name UpgradeProgress
extends Control

signal closed
signal cancel_requested


static func compile_error_hint(project_stage: int) -> String:
	if project_stage < 2:
		return "请联系项目负责人，并附带项目文件。\n现在也可以考虑使用 AI 修复编译错误。"
	return "请用 AI 修复错误，或重新进入配置阶段。"

@onready var _title: Label = get_node("Dim/Center/Panel/Content/Title")
@onready var _stage: Label = get_node("Dim/Center/Panel/Content/Stage")
@onready var _progress: ProgressBar = get_node("Dim/Center/Panel/Content/Progress")
@onready var _detail: Label = get_node("Dim/Center/Panel/Content/Detail")
@onready var _close: Button = get_node("Dim/Center/Panel/Content/Close")
@onready var _cancel: Button = get_node("Dim/Center/Panel/Content/Cancel")


func _ready() -> void:
	_close.pressed.connect(_on_close_pressed)
	_cancel.pressed.connect(_on_cancel_pressed)
	hide()


func begin() -> void:
	_title.text = "升级主控板"
	_close.hide()
	_cancel.show()
	_cancel.disabled = true
	set_progress("准备升级", 2.0, "正在保存当前程序…")
	_show_on_top()


## 求解器烧录专用：显示进度面板（标题与提示面向"编译并烧录 MCU 求解器"）。
## 此前该路径只调 set_progress 未 show，导致 3D 页面点击后无任何进度反馈。
func begin_solver() -> void:
	_title.text = "编译并烧录 MCU 求解器"
	_close.hide()
	_cancel.show()
	_cancel.disabled = true
	set_progress("准备编译求解器", 2.0, "仿真固件不会初始化或输出任何执行器 IO。")
	_show_on_top()


## 确保面板在节点树中排最后（z_index 对运行时动态添加的同级兄弟不可靠），
## 否则后添加的 3D 仿真视图（SubViewportContainer 全屏拦截鼠标）会挡住面板按钮。
func _show_on_top() -> void:
	show()
	move_to_front()


func set_progress(stage_text: String, value: float, detail_text: String = "") -> void:
	_stage.text = stage_text
	_progress.value = clampf(value, 0.0, 100.0)
	_detail.text = detail_text


func complete() -> void:
	_title.text = "升级完成"
	_cancel.hide()
	set_progress("主控板已运行新程序", 100.0)
	_close.text = "完成"
	_show_close_on_top()


func fail(stage_text: String, detail_text: String) -> void:
	_title.text = "升级未完成"
	_cancel.hide()
	_stage.text = stage_text
	_detail.text = detail_text
	_close.text = "关闭"
	_show_close_on_top()


## 用户取消或硬超时自动取消后调用：显示「已取消」状态与关闭按钮。
func canceled(detail_text: String = "已取消烧录，串口已释放，可以重新升级。") -> void:
	_title.text = "升级已取消"
	_stage.text = "已取消"
	_detail.text = detail_text
	_cancel.hide()
	_close.text = "关闭"
	_show_close_on_top()


## 下载阶段开始（busy 变化）时启用/禁用取消按钮。
## 编译阶段不可中断，保持禁用；进入烧录阶段后启用。
func set_cancel_enabled(enabled: bool) -> void:
	_cancel.disabled = not enabled


func _on_cancel_pressed() -> void:
	if _cancel.disabled:
		return
	cancel_requested.emit()


## 显示关闭按钮并确保面板在最前（可接收鼠标与键盘）。
func _show_close_on_top() -> void:
	move_to_front()
	_close.show()
	_close.grab_focus()


func _on_close_pressed() -> void:
	hide()
	closed.emit()