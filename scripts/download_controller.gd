class_name DownloadController
extends Node

signal busy_changed(is_busy: bool)
signal succeeded
signal finished(result: Dictionary)
signal progress_changed(stage: String, percent: float, detail: String)

## 跨线程取消令牌（worker 线程读、主线程写）。
const CT = preload("res://scripts/cancel_token.gd")

## 整体烧录硬超时（秒）。无论 Python 侧是否挂死，超过时限就树杀进程、
## 释放串口并按「超时已取消」收尾 —— 防止任何未知挂起永久卡死程序。
const DOWNLOAD_HARD_TIMEOUT_SEC: float = 90.0

var _toolchain = null
var _clear_output: Callable
var _append_output: Callable
var _thread: Thread = null
var _busy: bool = false
var _cancel_token = null


func configure(toolchain, clear_output: Callable, append_output: Callable) -> void:
	_toolchain = toolchain
	_clear_output = clear_output
	_append_output = append_output


func is_busy() -> bool:
	return _busy


func start(project_dst: String) -> bool:
	if _busy or _toolchain == null:
		return false
	_clear()

	var hex_path: String = _toolchain.get_hex_path(project_dst)
	if not _toolchain.hex_exists(project_dst):
		_append("[Error] 没有找到编译好的程序，请先点「编译」")
		_append("       期望路径: %s" % hex_path)
		return false

	if not _toolchain.detect_hid_device():
		_append("[Error] 未检测到 USB-HID 设备（板子不在 ISP 模式）")
		_append("       请确认：")
		_append("       1. 板子已通过 USB 线连接到电脑")
		_append("       2. 板子处于 ISP 模式（拔下 USB 再插上，冷启动进入）")
		return false

	_set_busy(true)
	_append("检测到 USB-HID 设备，开始烧录…")
	progress_changed.emit("连接主控板", 30.0, "正在启动烧录程序…")
	_cancel_token = CT.new()
	_thread = Thread.new()
	var error: int = _thread.start(_worker.bind(hex_path, _cancel_token))
	if error != OK:
		_thread = null
		_set_busy(false)
		_append("[Error] 无法启动烧录线程（错误码 %d）" % error)
		return false
	return true


func shutdown() -> void:
	# 先请求取消并树杀烧录进程，再等线程结束：
	# 否则 worker 卡死在死循环的 Python 进程上时，wait_to_finish 会永远
	# 阻塞主线程（关窗口/退出场景会直接卡死整个程序）。
	cancel()
	if _thread:
		_thread.wait_to_finish()
	_thread = null
	if _busy:
		_set_busy(false)


func _exit_tree() -> void:
	shutdown()


## 请求取消当前烧录：置取消标志并立即树杀烧录进程（释放串口）。
## 线程本身由 worker 收尾（进程被杀后很快结束），这里不 wait_to_finish。
func cancel() -> void:
	if _cancel_token == null:
		return
	_cancel_token.request_cancel()
	if _toolchain != null and _toolchain.has_method("kill_process_tree"):
		_toolchain.kill_process_tree(_cancel_token.get_pid())


func _worker(hex_path: String, token) -> void:
	# 用户在烧录途中取消：直接收尾。
	if token != null and token.is_canceled():
		call_deferred("_on_worker_finished", {
			"ok": false, "stage": "canceled", "log": "", "streamed": true,
			"canceled": true,
		})
		return
	var result: Dictionary = _toolchain.flash_hid(
		hex_path, _on_download_line_from_worker, token, DOWNLOAD_HARD_TIMEOUT_SEC)
	if bool(result.get("canceled", false)):
		result["canceled"] = true
	call_deferred("_on_worker_finished", result)


func _on_download_line_from_worker(line: String) -> void:
	call_deferred("_handle_download_line", line)


func _handle_download_line(line: String) -> void:
	_append(line)
	var progress: Dictionary = _progress_from_log_line(line)
	if not progress.is_empty():
		progress_changed.emit(
			str(progress["stage"]), float(progress["percent"]), line.strip_edges())


func _progress_from_log_line(line: String) -> Dictionary:
	var text: String = line.strip_edges()
	if text.begins_with("info OK"):
		return {"stage": "正在连接引导程序", "percent": 35.0}
	if text.begins_with("unlock OK"):
		return {"stage": "引导程序已连接", "percent": 40.0}
	if text.begins_with("erase OK"):
		return {"stage": "正在准备存储空间", "percent": 44.0}
	if text.begins_with("Writing ") and text.contains(" blocks"):
		return {"stage": "正在写入程序", "percent": 48.0}
	if text.begins_with("  block ") and text.contains("/"):
		# 形如 "  block 25/199 @0x0C00 (cmd=0x12)"
		var parts: PackedStringArray = text.split("/")
		if parts.size() == 2:
			var done: int = parts[0].get_slice(" ", -1).to_int()
			var total: int = parts[1].get_slice(" ", 0).to_int()
			if total > 0:
				return {"stage": "正在写入程序",
					"percent": 48.0 + float(done) / float(total) * 0.34}
	if text.contains("烧录成功"):
		return {"stage": "写入完成", "percent": 99.0}
	return {}


func _on_worker_finished(result: Dictionary) -> void:
	if _thread:
		_thread.wait_to_finish()
	_thread = null
	_cancel_token = null
	_set_busy(false)

	# 用户取消 / 硬超时：不是真正的失败，不发 succeeded、不弹排查建议。
	if bool(result.get("canceled", false)):
		if str(result.get("stage", "")) == "timeout":
			_append("✗ 烧录超时，已自动取消并释放串口。可以重新点「升级主控板」。")
		else:
			_append("✗ 已取消烧录，串口已释放。")
		finished.emit(result)
		return

	var ok: bool = bool(result.get("ok", false))
	var log_text: String = str(result.get("log", ""))
	var streamed: bool = bool(result.get("streamed", false))
	if ok:
		_append("✓ 烧录完成，板子已经在运行新程序")
		if not streamed:
			_append_download_log(log_text, true)
		succeeded.emit()
	else:
		_append("✗ 烧录失败")
		for line in _toolchain.hid_failure_hint(str(result.get("stage", "unknown"))):
			_append("  %s" % line)
		if not streamed:
			_append_download_log(log_text, false)
	finished.emit(result)


func _set_busy(value: bool) -> void:
	_busy = value
	busy_changed.emit(value)


func _clear() -> void:
	if _clear_output.is_valid():
		_clear_output.call()


func _append(text: String) -> void:
	if _append_output.is_valid():
		_append_output.call(text)


func _append_download_log(log_text: String, collapse: bool) -> void:
	if log_text.is_empty():
		return
	var lines: PackedStringArray = log_text.split("\n", false)
	if not collapse:
		for line in lines:
			_append(line)
		return
	var skipped: int = 0
	for line in lines:
		if line.contains("字节 (") and line.ends_with("%)"):
			skipped += 1
			continue
		_append(line)
	if skipped > 0:
		_append("  （省略 %d 行进度）" % skipped)
