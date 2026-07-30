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


func start(project_dst: String, code: String) -> bool:
	if _busy or _toolchain == null:
		return false
	_clear()
	if code.strip_edges().is_empty():
		_append("[Error] 没有可编译的代码，请先完成配置")
		return false
	if not _toolchain.ensure_deployed():
		_append("[Error] 工具链初始化失败，无法编译")
		return false
	if not _toolchain.write_main_c(project_dst, code):
		_append("[Error] 写入 main.c 失败，请检查 user:// 目录权限")
		return false
	var uv4_abs: String = _toolchain.find_uv4()
	if uv4_abs.is_empty():
		_append("[Error] 未找到 uVision.com / UV4.exe")
		_append("       请尝试删除 user://keil/ 后重新编译（触发重新解压）")
		return false
	if not _toolchain.generate_tools_ini():
		_append("[Warn] TOOLS.INI 生成失败，编译可能报错")

	_set_busy(true)
	_append("正在编译…（已写入 main.c，调用 Keil 编译器）")
	_thread = Thread.new()
	var error: int = _thread.start(_worker.bind(uv4_abs, project_dst))
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


func _worker(uv4_abs: String, project_dst: String) -> void:
	var result: Dictionary = _toolchain.build_sync(uv4_abs, project_dst)
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
		succeeded.emit()
	else:
		_append("✗ 编译失败（UV4 退出码 %d，详见下方日志）"
			% int(result.get("exit", -1)))
	_append("")
	if log_text.is_empty():
		_append("[Warn] 未读取到编译日志")
	else:
		for line in log_text.split("\n", false):
			_append(line)
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
