extends SceneTree

const DC = preload("res://scripts/download_controller.gd")

var _fail: int = 0
var _lines: Array[String] = []
var _clear_count: int = 0


class FakeToolchain extends RefCounted:
	const DEFAULT_APP_BAUD: int = 115200
	const DEFAULT_BOOT_BAUD: int = 115200

	var has_hex: bool = false
	var candidates: Array = []
	var attempts: Array = []
	var per_port_result: Dictionary = {}
	var last_token = null

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
			_boot_baud: int, on_log_line: Callable = Callable(),
			token = null, timeout_sec: float = 0.0) -> Dictionary:
		attempts.append(_com_port)
		last_token = token
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


## 模拟「卡死在触发阶段」的烧录：download_hex_iap 一直阻塞，
## 直到主线程请求取消（等价于真实场景里 Python 进程挂死）。
class FakeBlockingToolchain extends RefCounted:
	const DEFAULT_APP_BAUD: int = 115200
	const DEFAULT_BOOT_BAUD: int = 115200

	var cancel_seen: Array[bool] = [false]

	func get_hex_path(_project_dst: String) -> String:
		return "C:/fake/app.hex"

	func hex_exists(_project_dst: String) -> bool:
		return true

	func ordered_candidate_ports() -> Array:
		return [{"device": "COM9", "kind": "usb_serial", "label": "COM9 test"}]

	func bluetooth_baud_note() -> PackedStringArray:
		return PackedStringArray()

	func iap_failure_hint(stage: String, port_kind: String = "") -> PackedStringArray:
		return PackedStringArray(["hint " + stage])

	func kill_process_tree(_pid: int) -> void:
		pass

	func download_hex_iap(_hex_path: String, _com_port: String, _app_baud: int,
			_boot_baud: int, on_log_line: Callable = Callable(),
			token = null, timeout_sec: float = 0.0) -> Dictionary:
		# 阻塞直到收到取消标志（模拟触发阶段挂死）
		while token == null or not token.is_canceled():
			OS.delay_msec(10)
		cancel_seen[0] = true
		on_log_line.call("发送触发命令 @PIEIAP# @ 115200 baud")
		return {"ok": false, "stage": "canceled", "log": "", "streamed": true, "canceled": true}


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

	# --- 取消：卡在触发阶段时点取消，应终止并释放 busy，不发 succeeded ---
	var bt := FakeBlockingToolchain.new()
	var c2 = DC.new()
	root.add_child(c2)
	c2.configure(bt, _clear, _append)
	var finished_cancel: Array[Dictionary] = []
	c2.finished.connect(
		func(r: Dictionary) -> void: finished_cancel.append(r), CONNECT_ONE_SHOT)
	var succeeded_cancel: Array[int] = [0]
	c2.succeeded.connect(func() -> void: succeeded_cancel[0] += 1)
	_check("取消场景下载启动", c2.start("project"))
	# 等 worker 真正进入阻塞的 download_hex_iap（确保取消令牌已创建）
	await process_frame
	await process_frame
	c2.cancel()
	# cancel() 不 wait_to_finish，worker 收到标志后很快返回
	while c2.is_busy():
		await process_frame
	_check("取消后 worker 收到取消标志", bt.cancel_seen[0])
	_check("取消后 finished 带 canceled 字段",
		finished_cancel.size() == 1
		and bool(finished_cancel[0].get("canceled", false)))
	_check("取消后不发 succeeded", succeeded_cancel[0] == 0)
	_check("取消后 busy 复位", not c2.is_busy())
	_check("取消令牌透传给工具链", bt.cancel_seen[0])
	root.remove_child(c2)
	c2.free()

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
