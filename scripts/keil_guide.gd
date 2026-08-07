class_name KeilGuide
extends RefCounted

## 编译前的 Keil 目录引导（静态工具）。
##
## 背景：编译只使用用户指定的外部 Keil 安装。
## 在编译入口用 `KeilGuide.ensure_keil(...)` 包一层：
##   - 已配置且有效的外部 Keil -> 直接调用 retry（正常编译）
##   - 未配置 / 已失效 -> 弹引导对话框让用户选目录
##        选中并通过校验 -> 持久化配置（user://keil_settings.json）-> 调用 retry 重跑原编译逻辑
##        取消 -> 调用 on_cancel（场景侧提示「编译已中止」）
##
## 设计成静态工具，让 code_edit.gd 与 ui.gd 复用同一套逻辑；
## 用户取消时不偷偷回退任何内置工具链。


## 编译前置门控。就绪 -> retry.call()；否则弹引导，成功后 retry.call()，取消时 on_cancel.call()。
## parent：场景节点（用于挂对话框）；toolchain：Toolchain 实例；retry/on_cancel：Callable。
static func ensure_keil(parent: Node, toolchain, retry: Callable, on_cancel: Callable = Callable()) -> void:
	var check: Dictionary = toolchain.ensure_external_keil_ready()
	if check.ok:
		retry.call()
		return
	_show_guide(parent, toolchain, str(check.reason), retry, on_cancel)


static func _show_guide(
	parent: Node, toolchain, reason: String, retry: Callable, on_cancel: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "需要指定 Keil 目录"
	dlg.dialog_text = "编译需要 Keil C251 编译器，但当前没有可用的 Keil 目录。\n\n" \
		+ "原因：%s\n\n" % reason \
		+ "请点击「选择目录…」指定已安装 Keil 的目录\n" \
		+ "（需包含 UV4\\uVision.com 与 C251\\BIN\\C251.EXE，例如 C:\\Keil_v5）。"
	dlg.ok_button_text = "选择目录…"
	dlg.cancel_button_text = "取消"
	parent.add_child(dlg)
	dlg.popup_centered(Vector2i(600, 320))

	dlg.confirmed.connect(func() -> void:
		_open_picker(parent, toolchain, reason, retry, on_cancel, dlg))
	dlg.canceled.connect(func() -> void:
		dlg.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	dlg.close_requested.connect(func() -> void:
		dlg.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())


static func _open_picker(
	parent: Node, toolchain, reason: String, retry: Callable, on_cancel: Callable,
	guide_dlg: ConfirmationDialog) -> void:
	var fd := FileDialog.new()
	fd.title = "选择 Keil 安装目录"
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.use_native_dialog = true
	fd.dir_selected.connect(func(path: String) -> void:
		var check: Dictionary = toolchain.validate_keil_dir(path)
		if check.ok:
			guide_dlg.queue_free()
			fd.queue_free()
			if toolchain.set_configured_keil_path(path):
				retry.call()
			elif on_cancel.is_valid():
				on_cancel.call()
		else:
			fd.queue_free()
			_show_invalid_warning(parent, toolchain, str(check.reason), retry, on_cancel, guide_dlg))
	fd.close_requested.connect(func() -> void:
		fd.queue_free()
		guide_dlg.popup_centered())
	parent.add_child(fd)
	fd.popup_centered(Vector2i(720, 520))


static func _show_invalid_warning(
	parent: Node, toolchain, reason: String, retry: Callable, on_cancel: Callable,
	guide_dlg: ConfirmationDialog) -> void:
	var warn := AcceptDialog.new()
	warn.title = "目录无效"
	warn.dialog_text = "所选目录不是有效的 Keil C251 安装：\n%s\n\n请重新选择。" % reason
	warn.ok_button_text = "重新选择"
	parent.add_child(warn)
	warn.popup_centered()
	warn.confirmed.connect(func() -> void:
		warn.queue_free()
		_open_picker(parent, toolchain, reason, retry, on_cancel, guide_dlg))
	warn.close_requested.connect(warn.queue_free)
