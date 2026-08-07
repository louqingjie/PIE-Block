@tool
extends EditorScript
func _run() -> void:
	print("ICON=", ProjectSettings.get_setting("application/config/icon"))
	print("SPLASH=", ProjectSettings.get_setting("application/boot_splash/image"))
