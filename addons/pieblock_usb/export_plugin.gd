@tool
extends EditorPlugin

## PieBlockUsb 插件导出配置（v2 Android 插件打包规范）。
## 构建时由 android/plugins/pieblock_usb 的 exportPlugin 任务把
## export_scripts_template + release AAR 复制到 addons/pieblock_usb/。

var export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name = "pieblock_usb"

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform, debug) -> PackedStringArray:
		if debug:
			return PackedStringArray(["res://addons/pieblock_usb/bin/pieblock_usb-release.aar"])
		return PackedStringArray(["res://addons/pieblock_usb/bin/pieblock_usb-release.aar"])

	func _get_name() -> String:
		return _plugin_name
