extends SceneTree

## 测试串口列举和 Python 探测功能
## 运行：godot --headless --path . --script scripts/dev_test_ports.gd

func _initialize() -> void:
	var tc = load("res://scripts/toolchain.gd").new()
	
	print("=== Python 探测 ===")
	var py = tc.find_python()
	print("Python: %s" % py)
	
	print("\n=== 串口列举 ===")
	var ports = tc.list_serial_ports()
	print("找到 %d 个端口:" % ports.size())
	for p in ports:
		print("  %s" % p)
	
	print("\n=== 烧录脚本部署 ===")
	var ok = tc.ensure_stcflash_deployed()
	print("部署: %s" % str(ok))
	
	print("\n=== hex 文件检查 ===")
	var hex_infantry = tc.hex_exists("user://stc32g/Projects/ROBOMASTER_INFANTRY")
	var hex_engineer = tc.hex_exists("user://stc32g/Projects/ROBOMASTER_ENGINEER")
	print("步兵 hex: %s" % str(hex_infantry))
	print("工程 hex: %s" % str(hex_engineer))
	
	quit(0)
