extends SceneTree

func _initialize() -> void:
	var tc = load("res://scripts/toolchain.gd").new()
	if tc.ensure_deployed():
		print("Toolchain deployed OK")
	else:
		print("Toolchain deployment FAILED")
	quit(0)
