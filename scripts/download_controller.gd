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
var _port_kind: String = ""
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

	var candidates: Array = _toolchain.ordered_candidate_ports()
	if candidates.is_empty():
		_append("[Error] 未检测到可用串口，请确认板子已通过 USB 线或蓝牙连接到电脑")
		_append("       若用蓝牙，请先在系统设置里配对好模块")
		return false

	# 候选里有蓝牙口时提示波特率限制
	for info in candidates:
		if str(info.get("kind", "")) == "bluetooth":
			for line in _toolchain.bluetooth_baud_note():
				_append("  %s" % line)
			break

	_set_busy(true)
	if candidates.size() == 1:
		_append("开始烧录，不需要断电或按复位键…")
	else:
		_append("检测到 %d 个串口，将逐个尝试直到连上主控板：" % candidates.size())
		for info in candidates:
			_append("  · %s" % str(info.get("label", str(info.get("device", "")))))
		_append("开始烧录，不需要断电或按复位键…")
	progress_changed.emit("连接主控板", 30.0, "正在启动烧录程序…")
	_cancel_token = CT.new()
	_thread = Thread.new()
	var error: int = _thread.start(_worker.bind(hex_path, candidates, _cancel_token))
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


func _worker(hex_path: String, candidates: Array, token) -> void:
	var total: int = candidates.size()
	var failed: Array = []
	for i in total:
		# 用户在候选之间取消了：不再尝试下一个端口，直接收尾。
		if token != null and token.is_canceled():
			call_deferred("_on_worker_finished", {
				"ok": false, "stage": "canceled", "log": "", "streamed": true,
				"canceled": true,
			})
			return
		var info: Dictionary = candidates[i]
		var com_port: String = str(info.get("device", ""))
		var kind: String = str(info.get("kind", ""))
		if total > 1:
			_on_download_line_from_worker("— 尝试串口 %s（%d/%d）—" % [com_port, i + 1, total])
		var result: Dictionary = _toolchain.download_hex_iap(
			hex_path, com_port, _toolchain.DEFAULT_APP_BAUD, _toolchain.DEFAULT_BOOT_BAUD,
			_on_download_line_from_worker, token, DOWNLOAD_HARD_TIMEOUT_SEC)
		if bool(result.get("ok", false)):
			call_deferred("_on_worker_finished", result)
			return
		var stage: String = str(result.get("stage", "unknown"))
		# 用户取消 / 硬超时：不再试别的口（超时往往意味着链路整体卡死），
		# 直接按取消收尾，让串口立刻释放。
		if stage in ["canceled", "timeout"]:
			call_deferred("_on_worker_finished", {
				"ok": false, "stage": stage, "log": "", "streamed": true,
				"canceled": true,
			})
			return
		# 连上了但中途失败（擦除/写入/校验）或固件问题：这个口就是板子所在的
		# 口，换别的口没有意义（板子已停在下载模式等这个口），直接按单次失败收尾。
		if stage in ["erase", "program", "verify", "bootloader_upgrade", "hex"]:
			result["port_kind"] = kind
			call_deferred("_on_worker_finished", result)
			return
		# 没连上板子（口打不开 / bootloader 无响应）：记下并试下一个
		failed.append({"port": com_port, "stage": stage, "kind": kind})
		if total > 1:
			_on_download_line_from_worker("      %s 不行（%s），试下一个"
				% [com_port, _stage_name(stage)])

	# 全部尝试都失败：把汇总摘要走日志流输出（用户能看到），
	# result 里的 log 置空避免与流式输出重复。提示按最后试的端口给。
	var last: Dictionary = failed.back() if not failed.is_empty() else {}
	_on_download_line_from_worker("烧录失败：%d 个串口都没能连上主控板。" % failed.size())
	for f in failed:
		_on_download_line_from_worker("  %s：%s" % [f["port"], _stage_name(f["stage"])])
	call_deferred("_on_worker_finished", {
		"ok": false,
		"stage": str(last.get("stage", "connect")),
		"log": "",
		"streamed": true,
		"port_kind": str(last.get("kind", "")),
	})


## 把失败阶段翻成一句简短说明（用于逐个尝试时的中间提示）。
func _stage_name(stage: String) -> String:
	match stage:
		"port":
			return "串口打不开"
		"connect":
			return "联系不上板子"
		"erase":
			return "擦除失败"
		"program":
			return "写入失败"
		"verify":
			return "校验失败"
		"hex":
			return "固件文件问题"
		"env":
			return "环境问题"
		"bootloader_upgrade":
			return "旧版引导程序"
		"canceled":
			return "已取消"
		"timeout":
			return "超时"
		_:
			return "未知原因"


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
		for line in _toolchain.iap_failure_hint(
				str(result.get("stage", "unknown")),
				str(result.get("port_kind", _port_kind))):
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
