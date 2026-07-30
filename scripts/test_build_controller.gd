extends SceneTree

const BC = preload("res://scripts/build_controller.gd")

var _fail: int = 0
var _lines: Array[String] = []
var _clear_count: int = 0


class FakeToolchain extends RefCounted:
	var deployed: bool = true
	var wrote: bool = true
	var uv4: String = "C:/fake/uVision.com"
	var tools_ini: bool = true

	func ensure_deployed() -> bool:
		return deployed

	func write_main_c(_project_dst: String, _code: String) -> bool:
		return wrote

	func find_uv4() -> String:
		return uv4

	func generate_tools_ini() -> bool:
		return tools_ini

	func build_sync(_uv4_abs: String, _project_dst: String) -> Dictionary:
		return {"ok": true, "exit": 0, "log": "0 Error(s), 2 Warning(s)"}


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _initialize() -> void:
	print("=== BuildController 测试 ===")
	var toolchain := FakeToolchain.new()
	var controller = BC.new()
	root.add_child(controller)
	controller.configure(toolchain, _clear, _append)

	_lines = ["旧日志"]
	_check("空代码不启动", not controller.start("project", ""))
	_check("每次编译先清空旧日志", _clear_count == 1 and not "旧日志" in _lines)
	_check("空代码给出提示", _contains("没有可编译的代码"))

	toolchain.deployed = false
	_lines.clear()
	_check("部署失败不启动", not controller.start("project", "code"))
	_check("部署失败给出提示", _contains("工具链初始化失败"))
	toolchain.deployed = true

	toolchain.wrote = false
	_lines.clear()
	_check("写盘失败不启动", not controller.start("project", "code"))
	_check("写盘失败给出提示", _contains("写入 main.c 失败"))
	toolchain.wrote = true

	toolchain.uv4 = ""
	_lines.clear()
	_check("缺编译器不启动", not controller.start("project", "code"))
	_check("缺编译器给出提示", _contains("未找到 uVision.com"))
	toolchain.uv4 = "C:/fake/uVision.com"
	toolchain.tools_ini = false
	_lines.clear()
	var succeeded_count: Array[int] = [0]
	controller.succeeded.connect(func() -> void: succeeded_count[0] += 1)
	_check("假后台编译成功启动", controller.start("project", "code"))
	await controller.finished
	_check("TOOLS.INI 失败显示警告", _contains("TOOLS.INI 生成失败"))
	_check("成功结果发出 succeeded", succeeded_count[0] == 1)
	_check("成功日志完整展示", _contains("编译成功") and _contains("0 Error(s)"))
	toolchain.tools_ini = true

	_lines.clear()
	controller._on_worker_finished({"ok": false, "exit": 1, "log": "error C123"})
	_check("失败结果显示退出码", _contains("退出码 1"))
	_check("失败日志完整展示", _contains("error C123"))

	await process_frame
	root.remove_child(controller)
	controller.free()
	print("=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _clear() -> void:
	_clear_count += 1
	_lines.clear()


func _append(line: String) -> void:
	_lines.append(line)


func _contains(text: String) -> bool:
	for line in _lines:
		if line.contains(text):
			return true
	return false
