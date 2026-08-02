extends SceneTree

const DC = preload("res://scripts/download_controller.gd")

var _fail: int = 0
var _lines: Array[String] = []
var _clear_count: int = 0


class FakeToolchain extends RefCounted:
	const DEFAULT_APP_BAUD: int = 230400
	const DEFAULT_BOOT_BAUD: int = 230400

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

	func iap_failure_hint(stage: String, port_kind: String = "") -> PackedStringArray:
		return PackedStringArray(["阶段提示: %s (%s)" % [stage, port_kind]])

	func download_hex_iap(_hex_path: String, _com_port: String, _app_baud: int,
			_boot_baud: int, on_log_line: Callable) -> Dictionary:
		on_log_line.call("实时进度 50%")
		return {"ok": true, "stage": "done", "log": "实时进度 50%", "streamed": true}


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
	_check("失败结果使用工具链提示", _contains("阶段提示: verify ()"))
	_check("失败日志完整保留", _contains("校验失败"))

	_lines.clear()
	controller._on_download_line_from_worker("实时进度 50%")
	await process_frame
	controller._on_worker_finished({
		"ok": true,
		"stage": "done",
		"log": "实时进度 50%",
		"streamed": true,
	})
	var progress_count: int = 0
	for line in _lines:
		if line.contains("实时进度 50%"):
			progress_count += 1
	_check("流式日志实时追加且完成后不重复", progress_count == 1)

	toolchain.pick = {
		"ok": true,
		"device": "COM11",
		"reason": "测试串口",
		"candidates": [ {"device": "COM11", "kind": "usb_serial"}],
	}
	_lines.clear()
	var finished_seen: Array[bool] = [false]
	controller.finished.connect(func(_result: Dictionary) -> void: finished_seen[0] = true, CONNECT_ONE_SHOT)
	_check("异步流式下载成功启动", controller.start("project"))
	while controller.is_busy():
		await process_frame
	_check("worker 流式行在完成结果中保留", _contains("实时进度 50%"))
	_check("异步下载发出 finished", finished_seen[0])

	var write_progress: Dictionary = controller._progress_from_log_line(
		"  14848/29566 字节 (50%)")
	_check("写入进度映射到升级中段",
		str(write_progress.get("stage", "")) == "正在写入程序"
		and is_equal_approx(float(write_progress.get("percent", 0.0)), 65.0))
	var verify_progress: Dictionary = controller._progress_from_log_line(
		"  119/238 个块 (50%)")
	_check("校验进度映射到升级后段",
		str(verify_progress.get("stage", "")) == "正在校验程序"
		and is_equal_approx(float(verify_progress.get("percent", 0.0)), 91.0))
	var verified: Dictionary = controller._progress_from_log_line("读回校验通过")
	_check("校验通过显示 99%",
		str(verified.get("stage", "")) == "校验完成"
		and is_equal_approx(float(verified.get("percent", 0.0)), 99.0))

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
