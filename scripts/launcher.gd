extends Control

## 启动页（欢迎页）。项目的新建 / 打开都在这里完成。
##
## 这一层存在的意义是把「项目管理」和「图形化配置」彻底分开：
## 主界面 ui.tscn 只负责编辑一个**已经存在**的项目，
## 项目从哪来、什么类型、处在哪个阶段，全由本场景决定。
## 所以主界面直接单跑时行为不变（没有项目上下文 = 老的自由编辑模式）。

const PF = preload("res://scripts/project_file.gd")

const P_CREATE: NodePath = "Center/Panel/Actions/Create"
const P_OPEN: NodePath = "Center/Panel/Actions/Open"
const P_RECENT_LIST: NodePath = "Center/Panel/RecentList"
const P_STATUS: NodePath = "Center/Panel/Status"
const P_KIND_DIALOG: NodePath = "KindDialog"
const P_SAVE_DIALOG: NodePath = "SaveDialog"
const P_OPEN_DIALOG: NodePath = "OpenDialog"

## 类型选择对话框里三个按钮的节点名，与 PF.KINDS 一一对应
const KIND_BUTTONS: Array = ["Infantry", "Engineer", "Debug"]

const UI_SCENE: String = "res://scenes/ui.tscn"

## 待创建项目的类型（选完类型、还没选保存路径时暂存在这里）
var _pending_kind: String = ""


func _ready() -> void:
	# 从主界面返回启动页时，上一个项目的上下文必须清干净，
	# 否则 ui.tscn 下次进来会以为项目还开着
	AppState.reset()
	_connect_signals()
	_rebuild_recent_list()


func _connect_signals() -> void:
	var create: Node = get_node_or_null(P_CREATE)
	if create is BaseButton:
		create.pressed.connect(_on_create_pressed)
	var open: Node = get_node_or_null(P_OPEN)
	if open is BaseButton:
		open.pressed.connect(_on_open_pressed)
	var kind_dlg: Node = get_node_or_null(P_KIND_DIALOG)
	if kind_dlg is AcceptDialog:
		for i in range(KIND_BUTTONS.size()):
			var btn: Node = kind_dlg.get_node_or_null(
				NodePath("KindBox/"+ str(KIND_BUTTONS[i])))
			if btn is BaseButton:
				btn.pressed.connect(_on_kind_chosen.bind(str(PF.KINDS[i])))
	var save_dlg: Node = get_node_or_null(P_SAVE_DIALOG)
	if save_dlg is FileDialog:
		save_dlg.file_selected.connect(_on_save_path_chosen)
	var open_dlg: Node = get_node_or_null(P_OPEN_DIALOG)
	if open_dlg is FileDialog:
		open_dlg.file_selected.connect(_open_project)


# ------------------------------------------------------------------ 新建
func _on_create_pressed() -> void:
	_set_status("")
	var dlg: Node = get_node_or_null(P_KIND_DIALOG)
	if dlg is AcceptDialog:
		# 显式给尺寸：AcceptDialog 不给的话会撑到视口高度
		dlg.popup_centered(Vector2i(420, 260))


## 选定类型后立刻要求选保存位置：落盘成功才算新建完成，
## 不存在「未保存的新项目」这种中间态
func _on_kind_chosen(kind: String) -> void:
	_pending_kind = kind
	var kind_dlg: Node = get_node_or_null(P_KIND_DIALOG)
	if kind_dlg is AcceptDialog:
		kind_dlg.hide()
	var dlg: Node = get_node_or_null(P_SAVE_DIALOG)
	if dlg is FileDialog:
		dlg.current_file = "%s项目.%s" % [PF.kind_label(kind), PF.EXT]
		dlg.popup_centered()


func _on_save_path_chosen(raw_path: String) -> void:
	if _pending_kind.is_empty():
		return
	# 原生对话框不一定补扩展名
	var path: String = PF.ensure_ext(raw_path)
	var res: Dictionary = PF.create_new(path, _pending_kind)
	if not res["ok"]:
		_set_status("新建失败：%s" % res["err"])
		return
	var kind: String = _pending_kind
	_pending_kind = ""
	_enter_project(path, res["data"], "已新建%s项目" % PF.kind_label(kind))


# ------------------------------------------------------------------ 打开
func _on_open_pressed() -> void:
	_set_status("")
	var dlg: Node = get_node_or_null(P_OPEN_DIALOG)
	if dlg is FileDialog:
		dlg.popup_centered()


func _open_project(path: String) -> void:
	var res: Dictionary = PF.load_from(path)
	if not res["ok"]:
		# 打不开的项目从最近列表里摘掉，别一直摆着
		PF.recent_remove(path)
		_rebuild_recent_list()
		_set_status("无法打开项目：%s" % res["err"])
		return
	_enter_project(path, res["data"], "")


# ------------------------------------------------------------------ 进入主界面
## 写好 AppState 再切场景。ui.tscn 的 _ready 只认 AppState，
## 看到 project_path 非空就会加载该项目并按其类型 / 阶段布置界面。
func _enter_project(path: String, data: Dictionary, _note: String) -> void:
	PF.recent_add(path)
	AppState.reset()
	AppState.project_path = path
	AppState.project_kind = str(data["kind"])
	AppState.stage = int(data["stage"])
	AppState.source_tab = int(data["active_tab"])
	AppState.project_dst = AppState.project_dst_for_kind(str(data["kind"]))
	get_tree().change_scene_to_file(UI_SCENE)


# ------------------------------------------------------------------ 最近打开
func _rebuild_recent_list() -> void:
	var list_box: Node = get_node_or_null(P_RECENT_LIST)
	if list_box == null:
		return
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.free()
	var recent: Array = PF.recent_list()
	if recent.is_empty():
		var empty := Label.new()
		empty.text = "还没有项目"
		empty.modulate = Color(0.6, 0.6, 0.6)
		list_box.add_child(empty)
		return
	for path in recent:
		list_box.add_child(_make_recent_row(str(path)))


## 一行最近项目：主按钮打开，右侧小按钮从列表移除。
## 类型与阶段直接读文件里的，让用户点之前就知道这项目是什么状态。
func _make_recent_row(path: String) -> Control:
	var row := HBoxContainer.new()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	var info: Dictionary = PF.load_from(path)
	if info["ok"]:
		var data: Dictionary = info["data"]
		btn.text = "%s    [%s · %s]" % [
			PF.display_name(path),
			PF.kind_label(str(data["kind"])),
			PF.stage_label(int(data["stage"])),
		]
	else:
		btn.text = "%s    [无法读取]" % PF.display_name(path)
	btn.tooltip_text = path
	btn.pressed.connect(_open_project.bind(path))
	row.add_child(btn)
	var remove := Button.new()
	remove.text = "移除"
	remove.tooltip_text = "只从最近列表移除，不删除文件"
	remove.pressed.connect(func() -> void:
		PF.recent_remove(path)
		_rebuild_recent_list())
	row.add_child(remove)
	return row


func _set_status(text: String) -> void:
	var label: Node = get_node_or_null(P_STATUS)
	if label is Label:
		label.text = text
