extends SceneTree

const DC = preload("res://scripts/download_controller.gd")

var _fail: int = 0
var _lines: Array[String] = []
var _clear_count: int = 0


class FakeToolchain extends RefCounted:
	const DEFAULT_APP_BAUD: int = 230400
	const DEFAULT_BOOT_BAUD: int = 230400

	var has_hex: bool = false
	var candidates: Array = []
	var attempts: Array = []
	var per_port_result: Dictionary = {}

	func get_hex_path(_project_dst: String) -> String:
		return "C:/fake/app.hex"

	func hex_exists(_project_dst: String) -> bool:
		return has_hex

	func ordered_candidate_ports() -> Array:
		return candidates

	func bluetooth_baud_note() -> PackedStringArray:
		return PackedStringArray(["蓝牙提示"])

	func iap_failure_hint(stage: String, port_kind: String = "") -> PackedStringArray:
		return PackedStringArray(["阶段提示: %s (%s)" % [stage, port_kind]])

	func download_hex_iap(_hex_path: String, _com_port: String, _app_baud: int,
			_boot_baud: int, on_log_line: Callable) -> Dictionary:
		attempts.append(_com_port)
		if per_port_result.has(_com_port):
			var r: Dictionary = per_port_result[_com_port]
			if bool(r.get("streamed", false)):
				on_log_line.call(str(r.get("log", "")))
			return r
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
	_check("无串口显示原因", _contains("未检测到可用串口"))

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

	toolchain.candidates = [ {"device": "COM11", "kind": "usb_serial", "label": "COM11 test"}]
	toolchain.attempts.clear()
	_lines.clear()
	var finished_seen: Array[bool] = [false]
	controller.finished.connect(func(_result: Dictionary) -> void: finished_seen[0] = true, CONNECT_ONE_SHOT)
	_check("异步流式下载成功启动", controller.start("project"))
	while controller.is_busy():
		await process_frame
	_check("worker 流式行在完成结果中保留", _contains("实时进度 50%"))
	_check("异步下载发出 finished", finished_seen[0])
	_check("单候选直接使用", toolchain.attempts == ["COM11"])

	# --- 多个候选（如蓝牙传入/传出两个口）：逐个尝试，连上为止 ---
	toolchain.candidates = [
		{"device": "COM5", "kind": "bluetooth", "label": "COM5 bluetooth"},
		{"device": "COM6", "kind": "bluetooth", "label": "COM6 bluetooth"},
	]
	toolchain.attempts.clear()
	toolchain.per_port_result = {
		"COM5": {"ok": false, "stage": "connect", "log": "bootloader 没有响应", "streamed": true},
	}
	_lines.clear()
	var finished_multi: Array[Dictionary] = []
	controller.finished.connect(
		func(r: Dictionary) -> void: finished_multi.append(r), CONNECT_ONE_SHOT)
	_check("多候选逐个尝试启动", controller.start("project"))
	while controller.is_busy():
		await process_frame
	_check("失败口跳过、第二个口成功", toolchain.attempts == ["COM5", "COM6"])
	_check("逐个尝试成功发出 finished",
		finished_multi.size() == 1 and bool(finished_multi[0].get("ok", false)))
	_check("显示尝试提示", _contains("尝试串口 COM5"))

	# --- 全部失败：汇总报错，且逐口给出阶段提示 ---
	toolchain.per_port_result = {
		"COM5": {"ok": false, "stage": "connect", "log": "bootloader 没有响应", "streamed": true},
		"COM6": {"ok": false, "stage": "connect", "log": "bootloader 没有响应", "streamed": true},
	}
	toolchain.attempts.clear()
	_lines.clear()
	var finished_allfail: Array[Dictionary] = []
	controller.finished.connect(
		func(r: Dictionary) -> void: finished_allfail.append(r), CONNECT_ONE_SHOT)
	_check("多候选全失败启动", controller.start("project"))
	while controller.is_busy():
		await process_frame
	_check("全失败时两个口都试过", toolchain.attempts == ["COM5", "COM6"])
	_check("全失败发出 finished 且 ok=false",
		finished_allfail.size() == 1 and not bool(finished_allfail[0].get("ok", false)))
	_check("全失败显示汇总提示", _contains("都没能连上主控板"))
	_check("全失败仍给出阶段提示", _contains("阶段提示: connect (bluetooth)"))

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
