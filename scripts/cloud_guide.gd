class_name CloudGuide
extends RefCounted

## 云端编译配置引导（静态工具）。
##
## 在「云端编译」入口用 CloudGuide.ensure_cloud(...) 包一层：
##   - 已配置且校验通过 -> 直接 retry.call()（正常云端编译）
##   - 未配置 / 已失效   -> 打开设置场景（scenes/setting_panel.tscn）让用户填写
##        填写完成并关闭 -> 若配置已就绪则 retry.call()；否则 on_cancel.call()
##
## 配置持久化由 SettingPanel 脚本负责（user://cloud_settings.json 与
## user://keil_settings.json，Toolchain 读写）。
## 所有 UI 节点都固化在 setting_panel.tscn，本脚本只实例化场景、不创建任何节点。

const SETTING_PANEL_SCENE: PackedScene = preload("res://scenes/setting_panel.tscn")


## 云端编译前置门控。就绪 -> retry.call()；否则打开设置场景，
## 关闭时若配置已就绪 retry.call()，否则 on_cancel.call()。
## parent：场景节点（用于挂设置面板）；toolchain：Toolchain 实例；retry/on_cancel：Callable。
static func ensure_cloud(parent: Node, toolchain, retry: Callable, on_cancel: Callable = Callable()) -> void:
	var check: Dictionary = toolchain.ensure_cloud_ready()
	if check.ok:
		retry.call()
		return
	_open_panel(parent, toolchain, func() -> void:
		if toolchain.ensure_cloud_ready().ok:
			retry.call()
		elif on_cancel.is_valid():
			on_cancel.call())


## 独立打开设置面板（不触发编译）。面板关闭时回调 on_saved。
static func open_settings(parent: Node, toolchain, on_saved: Callable = Callable()) -> void:
	_open_panel(parent, toolchain, on_saved)


static func _open_panel(parent: Node, toolchain, on_closed: Callable = Callable()) -> void:
	var panel: Control = SETTING_PANEL_SCENE.instantiate()
	panel.configure(toolchain)
	parent.add_child(panel)
	panel.closed.connect(func() -> void:
		if on_closed.is_valid():
			on_closed.call())
