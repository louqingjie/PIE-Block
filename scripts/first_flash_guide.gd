class_name FirstFlashGuide
extends Control

signal confirmed
signal canceled

## 首次烧录指引（全屏模态覆盖层，结构参照 upgrade_progress.tscn）。
##
## 烧录时必须先断开板上的供电开关，否则可能因电流过大损坏主控板：
##   主控板：SERVO、POWER；扩展板：POWER、BOOSTER。
## 场景 scenes/first_flash_guide.tscn 中的两个 TextureRect 是图片占位，
## 后续补充实拍图说明开关位置。
##
## 「不再显示」持久化到 user://first_flash_guide.json（与 keil_settings.json
## 同一 user:// 惯例），勾选后 ensure_guide 直接放行不再弹窗。

const SETTINGS_PATH: String = "user://first_flash_guide.json"

const P_CHECKBOX: NodePath = "Dim/Center/Panel/Content/SkipCheck"
const P_CONFIRM: NodePath = "Dim/Center/Panel/Content/Buttons/Confirm"
const P_CANCEL: NodePath = "Dim/Center/Panel/Content/Buttons/Cancel"


# ------------------------------------------------------------------ 持久化

static func is_suppressed() -> bool:
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed is Dictionary and bool(parsed.get("skip", false))


static func suppress_forever() -> void:
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"skip": true}))
	f.close()


# ------------------------------------------------------------------ 门控入口

## 烧录入口门控（与 KeilGuide.ensure_keil 同一模式）：
##   已勾选「不再显示」-> 直接 retry.call()；
##   否则弹指引，用户确认开关已断开后 retry.call()，取消时 on_cancel.call()。
static func ensure_guide(parent: Node, retry: Callable, on_cancel: Callable = Callable()) -> void:
	if is_suppressed():
		retry.call()
		return
	# 已有指引打开时不再叠一层（连点按钮）
	for child in parent.get_children():
		if child is FirstFlashGuide:
			return
	var packed: PackedScene = load("res://scenes/first_flash_guide.tscn")
	if packed == null:
		# 场景缺失不应阻塞烧录，直接放行
		retry.call()
		return
	var guide: FirstFlashGuide = packed.instantiate()
	parent.add_child(guide)
	guide.confirmed.connect(func() -> void:
		if guide.is_skip_checked():
			suppress_forever()
		guide.queue_free()
		retry.call())
	guide.canceled.connect(func() -> void:
		guide.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())


func is_skip_checked() -> bool:
	var box: Node = get_node_or_null(P_CHECKBOX)
	return box is CheckBox and box.button_pressed


func _ready() -> void:
	var confirm: Node = get_node_or_null(P_CONFIRM)
	if confirm is BaseButton:
		confirm.pressed.connect(func() -> void: confirmed.emit())
	var cancel: Node = get_node_or_null(P_CANCEL)
	if cancel is BaseButton:
		cancel.pressed.connect(func() -> void: canceled.emit())
