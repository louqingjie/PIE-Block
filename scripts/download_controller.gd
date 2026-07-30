class_name DownloadController
extends Node

signal busy_changed(is_busy: bool)
signal succeeded
signal finished(result: Dictionary)
signal progress_changed(stage: String, percent: float, detail: String)

var _toolchain = null
var _clear_output: Callable
var _append_output: Callable
var _thread: Thread = null
var _busy: bool = false
var _port_kind: String = ""


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

	var pick: Dictionary = _toolchain.pick_download_port()
	var candidates: Array = pick.get("candidates", [])
	if not bool(pick.get("ok", false)):
		_append("[Error] %s" % str(pick.get("reason", "无法确定串口")))
		if candidates.is_empty():
			_append("       请确认板子已通过 USB 线或蓝牙连接到电脑")
		else:
			_append("       检测到这些端口：")
			for info in candidates:
				_append("         %s" % str(info.get("label", "")))
			_append("       请拔掉不相关的串口设备后重试")
		return false

	var com_port: String = str(pick.get("device", ""))
	_append("串口: %s" % str(pick.get("reason", com_port)))
	_port_kind = ""
	for info in candidates:
		if str(info.get("device", "")) == com_port:
			_port_kind = str(info.get("kind", ""))
			if _port_kind == "bluetooth":
				for line in _toolchain.bluetooth_baud_note():
					_append("  %s" % line)
			break

	_set_busy(true)
	_append("开始烧录，不需要断电或按复位键…")
	progress_changed.emit("连接主控板", 30.0, "正在启动烧录程序…")
	_thread = Thread.new()
	var error: int = _thread.start(_worker.bind(hex_path, com_port))
	if error != OK:
		_thread = null
		_set_busy(false)
		_append("[Error] 无法启动烧录线程（错误码 %d）" % error)
		return false
	return true


func shutdown() -> void:
	if _thread:
		_thread.wait_to_finish()
	_thread = null
	if _busy:
		_set_busy(false)


func _exit_tree() -> void:
	shutdown()


func _worker(hex_path: String, com_port: String) -> void:
	var result: Dictionary = _toolchain.download_hex_iap(
		hex_path, com_port, _toolchain.DEFAULT_APP_BAUD, _toolchain.DEFAULT_BOOT_BAUD,
		_on_download_line_from_worker)
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
	if text.begins_with("发送触发命令"):
		return {"stage": "正在进入升级模式", "percent": 32.0}
	if text.begins_with("等待 bootloader"):
		return {"stage": "正在连接引导程序", "percent": 35.0}
	if text.begins_with("bootloader 就绪"):
		return {"stage": "引导程序已连接", "percent": 40.0}
	if text.begins_with("擦除 App 区"):
		return {"stage": "正在准备存储空间", "percent": 44.0}
	if text.begins_with("写入 "):
		return {"stage": "正在写入程序", "percent": 48.0}
	if text.contains("字节 (") and text.ends_with("%)"):
		var pct: int = _extract_parenthesized_percent(text)
		return {"stage": "正在写入程序", "percent": 48.0 + float(pct) * 0.34}
	if text.begins_with("读回校验通过"):
		return {"stage": "校验完成", "percent": 99.0}
	if text.begins_with("读回校验"):
		return {"stage": "正在校验程序", "percent": 83.0}
	if text.contains("个块 (") and text.ends_with("%)"):
		var verify_pct: int = _extract_parenthesized_percent(text)
		return {"stage": "正在校验程序", "percent": 83.0 + float(verify_pct) * 0.16}
	if text.begins_with("重启到新固件"):
		return {"stage": "正在启动新程序", "percent": 99.0}
	return {}


func _extract_parenthesized_percent(text: String) -> int:
	var left: int = text.rfind("(")
	var right: int = text.rfind("%)")
	if left < 0 or right <= left:
		return 0
	return clampi(text.substr(left + 1, right - left - 1).to_int(), 0, 100)


func _on_worker_finished(result: Dictionary) -> void:
	if _thread:
		_thread.wait_to_finish()
	_thread = null
	_set_busy(false)

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
		for line in _toolchain.iap_failure_hint(
				str(result.get("stage", "unknown")), _port_kind):
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
