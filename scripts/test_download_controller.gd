extends SceneTree

const DC = preload("res://scripts/download_controller.gd")

var _fail: int = 0
var _lines: Array[String] = []
var _clear_count: int = 0


class FakeToolchain extends RefCounted:
	var has_hex: bool = false
	var pick: Dictionary = {"ok": false, "reason": "没有串口", "candidates": []}

	func get_hex_path(_project_dst: String) -> String:
		return "C:/fake/app.hex"

	func hex_exists(_project_dst: String) -> bool:
		return has_hex

	func pick_download_port() -> Dictionary:
		return pick

	func bluetooth_baud_note() -> PackedStringArray:
		return PackedStringArray(["蓝牙提示"])

	func iap_failure_hint(stage: String) -> PackedStringArray:
		return PackedStringArray(["阶段提示: " + stage])


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _initialize() -> void:
	print("=== DownloadController 测试 ===")
	var toolchain := FakeToolchain.new()
	var controller = DC.new()
	root.add_child(controller)
	controller.configure(toolchain, _clear, _append)

	_lines = ["旧日志"]
	_check("缺 hex 时不启动", not controller.start("project"))
	_check("每次尝试先清空旧日志", _clear_count == 1 and not "旧日志" in _lines)
	_check("缺 hex 给出可执行提示", _contains("没有找到编译好的程序"))

	toolchain.has_hex = true
	_lines.clear()
	_check("无串口时不启动", not controller.start("project"))
	_check("无串口显示原因", _contains("没有串口"))

	var succeeded_count: Array[int] = [0]
	controller.succeeded.connect(func() -> void: succeeded_count[0] += 1)
	_lines.clear()
	controller._on_worker_finished({
		"ok": true,
		"stage": "done",
		"log": "烧录成功\n  12/100 字节 (12%)\n完成",
	})
	_check("成功结果发出 succeeded", succeeded_count[0] == 1)
	_check("成功日志折叠进度行", not _contains("12/100") and _contains("省略 1 行进度"))

	_lines.clear()
	controller._on_worker_finished({"ok": false, "stage": "verify", "log": "校验失败"})
	_check("失败结果使用工具链提示", _contains("阶段提示: verify"))
	_check("失败日志完整保留", _contains("校验失败"))

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
