class_name BuildController
extends Node

signal busy_changed(is_busy: bool)
signal succeeded
signal finished(result: Dictionary)

var _toolchain = null
var _clear_output: Callable
var _append_output: Callable
var _thread: Thread = null
var _busy: bool = false


func configure(toolchain, clear_output: Callable, append_output: Callable) -> void:
	_toolchain = toolchain
	_clear_output = clear_output
	_append_output = append_output


func is_busy() -> bool:
	return _busy


## 启动编译。compiler 为 Toolchain.COMPILER_SDCC / COMPILER_KEIL。
func start(project_dst: String, code: String, kind: String = "infantry",
		compiler: String = "sdcc") -> bool:
	if _busy or _toolchain == null:
		return false
	_clear()
	if code.strip_edges().is_empty():
		_append("[Error] 没有可编译的代码，请先完成配置")
		return false
	if not _toolchain.ensure_deployed():
		_append("[Error] 工具链初始化失败，无法编译")
		return false
	var uv4_abs: String = ""
	if compiler == "keil":
		if not _toolchain.write_main_c(project_dst, code):
			_append("[Error] 写入 main.c 失败，请检查 user:// 目录权限")
			return false
		uv4_abs = _toolchain.find_uv4()
		if uv4_abs.is_empty():
			_append("[Error] 未找到 uVision.com / UV4.exe")
			_append("       请先配置 Keil 目录（编译时会弹出引导，或直接写 user://keil_settings.json）")
			return false
	elif compiler != "sdcc":
		_append("[Error] 未知编译器：%s" % compiler)
		return false
	_set_busy(true)
	_append("正在编译…（%s）" % ("内置 SDCC C251" if compiler == "sdcc" else "Keil C251"))
	_thread = Thread.new()
	var error: int = _thread.start(_worker.bind(compiler, kind, code, uv4_abs, project_dst))
	if error != OK:
		_thread = null
		_set_busy(false)
		_append("[Error] 无法启动编译线程（错误码 %d）" % error)
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


func _worker(compiler: String, kind: String, code: String,
		uv4_abs: String, project_dst: String) -> void:
	var result: Dictionary
	if compiler == "sdcc":
		result = _toolchain.build_sdcc_sync(kind, code, project_dst)
	else:
		result = _toolchain.build_sync(uv4_abs, project_dst)
	result["compiler"] = compiler
	call_deferred("_on_worker_finished", result)


func _on_worker_finished(result: Dictionary) -> void:
	if _thread:
		_thread.wait_to_finish()
	_thread = null
	_set_busy(false)

	var log_text: String = str(result.get("log", ""))
	var ok: bool = bool(result.get("ok", false))
	if ok:
		_append("✓ 编译成功")
	else:
		_append("✗ 编译失败（%s 退出码 %d，详见下方日志）"
			% ["SDCC" if str(result.get("compiler", "")) == "sdcc" else "Keil",
				int(result.get("exit", -1))])
	_append("")
	if log_text.is_empty():
		_append("[Warn] 未读取到编译日志")
	else:
		for line in log_text.split("\n", false):
			_append(line)
	# succeeded 会触发下载流程（_clear 清空输出再追加烧录日志），
	# 必须放在编译日志输出之后，否则编译日志的空行会混入烧录日志。
	if ok:
		succeeded.emit()
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
