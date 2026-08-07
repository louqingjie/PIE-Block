class_name SettingPanel
extends Control

## 设置面板（scenes/setting_panel.tscn 的驱动脚本）。
##
## 负责三块设置的读写：
##   1. 云端编译：Base URL + API Key（user://cloud_settings.json，Toolchain 读写）
##   2. 本地编译：Keil 路径（user://keil_settings.json，Toolchain 读写）
##   3. 烧录串口：占位（本面板当前不采集，字段保留给后续版本）
##
## 约定：所有 UI 节点都固化在 tscn 里，本脚本只读取、绝不动态创建。

signal closed

# 场景内节点路径（全部来自 setting_panel.tscn，禁止动态创建）
const P_BASE_URL_EDIT: NodePath = "Panel/VBoxContainer/HBoxContainer/VBoxContainer/BaseURL/LineEdit"
const P_API_KEY_EDIT: NodePath = "Panel/VBoxContainer/HBoxContainer/VBoxContainer/API/LineEdit"
const P_KEIL_EDIT: NodePath = "Panel/VBoxContainer/HBoxContainer/VBoxContainer/Keil/LineEdit"
const P_KEIL_PICK: NodePath = "Panel/VBoxContainer/HBoxContainer/VBoxContainer/Keil/Button"
const P_KEIL_DIALOG: NodePath = "Panel/KeilDirDialog"
const P_INVALID_DIALOG: NodePath = "Panel/InvalidDialog"
const P_CLOSE_BTN: NodePath = "Panel/CloseButton"

var _toolchain = null

func configure(toolchain) -> void:
	_toolchain = toolchain


func _ready() -> void:
	_load_existing()
	_connect_signals()


## 打开时预填当前已保存的配置
func _load_existing() -> void:
	var url_edit: LineEdit = get_node_or_null(P_BASE_URL_EDIT)
	var key_edit: LineEdit = get_node_or_null(P_API_KEY_EDIT)
	var keil_edit: LineEdit = get_node_or_null(P_KEIL_EDIT)
	if _toolchain == null:
		return
	var cfg: Dictionary = _toolchain.get_cloud_config()
	if url_edit and cfg.has("base_url"):
		url_edit.text = str(cfg.get("base_url", ""))
	if key_edit and cfg.has("api_key"):
		key_edit.text = str(cfg.get("api_key", ""))
	if keil_edit:
		keil_edit.text = _toolchain.get_configured_keil_path()


## 只连接场景里已固化的节点；缺失节点只告警，不回退到动态创建
func _connect_signals() -> void:
	var url_edit: LineEdit = get_node_or_null(P_BASE_URL_EDIT)
	var key_edit: LineEdit = get_node_or_null(P_API_KEY_EDIT)
	var keil_edit: LineEdit = get_node_or_null(P_KEIL_EDIT)
	var pick_btn: Button = get_node_or_null(P_KEIL_PICK)
	var keil_dlg: FileDialog = get_node_or_null(P_KEIL_DIALOG)
	var close_btn: Button = get_node_or_null(P_CLOSE_BTN)

	if url_edit == null or key_edit == null:
		push_error("设置面板缺少云端输入框（%s / %s）" % [P_BASE_URL_EDIT, P_API_KEY_EDIT])
		return
	url_edit.text_changed.connect(_on_cloud_edited)
	key_edit.text_changed.connect(_on_cloud_edited)

	if keil_edit != null:
		keil_edit.text_changed.connect(_on_keil_edited)
	else:
		push_error("设置面板缺少 Keil 输入框（%s）" % P_KEIL_EDIT)

	if pick_btn != null and keil_dlg != null:
		pick_btn.pressed.connect(func() -> void:
			keil_dlg.popup_centered(Vector2i(720, 520)))
		keil_dlg.dir_selected.connect(_on_keil_dir_selected)
	else:
		push_error("设置面板缺少 Keil 选择按钮或目录对话框")

	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	else:
		push_error("设置面板缺少关闭按钮（%s）" % P_CLOSE_BTN)


## 云端 Base URL / API Key 任一变化即持久化（不设保存按钮，改动即存）
func _on_cloud_edited(_new_text: String) -> void:
	if _toolchain == null:
		return
	var url_edit: LineEdit = get_node_or_null(P_BASE_URL_EDIT)
	var key_edit: LineEdit = get_node_or_null(P_API_KEY_EDIT)
	if url_edit == null or key_edit == null:
		return
	_toolchain.set_cloud_config(url_edit.text.strip_edges(), key_edit.text.strip_edges())


## Keil 路径变化即持久化
func _on_keil_edited(new_text: String) -> void:
	if _toolchain == null:
		return
	_toolchain.set_configured_keil_path(new_text.strip_edges())


## 通过目录对话框选择 Keil 目录：校验通过才写入并回填
func _on_keil_dir_selected(path: String) -> void:
	if _toolchain == null:
		return
	var check: Dictionary = _toolchain.validate_keil_dir(path)
	if not check.ok:
		var dlg: AcceptDialog = get_node_or_null(P_INVALID_DIALOG)
		if dlg != null:
			dlg.dialog_text = "所选目录不是有效的 Keil C251 安装：\n%s" % str(check.reason)
			dlg.popup_centered()
		return
	_toolchain.set_configured_keil_path(path)
	var keil_edit: LineEdit = get_node_or_null(P_KEIL_EDIT)
	if keil_edit != null:
		keil_edit.text = path


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
