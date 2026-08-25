extends SceneTree

const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var root := OS.get_environment("PIE_BLOCK_DART_SMOKE_DIR")
	if root.is_empty():
		printerr("缺少 PIE_BLOCK_DART_SMOKE_DIR")
		quit(2)
		return
	var toolchain = TC.new(func(line: String) -> void: print(line))
	for name in ["infantry", "engineer"]:
		var path := root.path_join(name + ".c")
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			printerr("无法读取：" + path)
			quit(2)
			return
		var result: Dictionary = toolchain.build_project(TC.PROJECT_DST, file.get_as_text())
		if not bool(result.get("ok", false)):
			printerr("Dart %s 代表代码编译失败\n%s" % [name, result.get("log", "")])
			quit(1)
			return
		print("=== Dart %s C251 编译：通过 ===" % name)
	quit(0)
