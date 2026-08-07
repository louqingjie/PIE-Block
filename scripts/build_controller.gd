class_name BuildController
extends Node

signal busy_changed(is_busy: bool)
signal succeeded
signal finished(result: Dictionary)

var _toolchain = null
var _cloud = null          # CloudCompiler（云端编译模式，可为 null）
var _clear_output: Callable
var _append_output: Callable
var _thread: Thread = null
var _busy: bool = false


func configure(toolchain, clear_output: Callable, append_output: Callable) -> void:
	_toolchain = toolchain
	_clear_output = clear_output
	_append_output = append_output


## 注入云端编译器（CloudCompiler 实例）。日志走同一 append_output。
func configure_cloud(cloud) -> void:
	_cloud = cloud


func is_busy() -> bool:
	return _busy


## 启动编译。mode："local"（本机 Keil）或 "cloud"（云端编译服务器）。
func start(project_dst: String, code: String, mode: String = "local") -> bool:
	if _busy or _toolchain == null:
		return false
	if mode == "cloud":
		return _start_cloud(project_dst, code)
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
		_append("       请先配置 Keil 目录（编译时会弹出引导，或直接写 user://keil_settings.json）")
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
	if _cloud:
		_cloud.shutdown()
	if _busy:
		_set_busy(false)


# ------------------------------------------------------------------ 云端编译
## 云端编译启动：校验配置 -> 交给 CloudCompiler（其内部线程上传/轮询/下载 hex）。
func _start_cloud(project_dst: String, code: String) -> bool:
	if _cloud == null:
		_append("[Error] 云端编译未初始化（CloudCompiler 缺失）")
		return false
	_clear()
	if code.strip_edges().is_empty():
		_append("[Error] 没有可编译的代码，请先完成配置")
		return false
	var cfg: Dictionary = _toolchain.get_cloud_config()
	if not cfg.ok or str(cfg.get("base_url", "")).is_empty() \
			or str(cfg.get("api_key", "")).is_empty():
		_append("[Error] 云端编译配置不完整（Base URL / API Key）")
		return false
	if not _cloud.finished.is_connected(_on_cloud_finished):
		_cloud.finished.connect(_on_cloud_finished)
	_set_busy(true)
	_append("正在云端编译…（上传工程到 %s）" % str(cfg.base_url))
	if not _cloud.compile(project_dst, code, str(cfg.base_url), str(cfg.api_key)):
		_set_busy(false)
		_append("[Error] 无法启动云端编译（可能正忙）")
		return false
	return true


## 云端编译完成（CloudCompiler 已把日志写入输出，hex 已下载到本地同路径）。
func _on_cloud_finished(result: Dictionary) -> void:
	_set_busy(false)
	var ok: bool = bool(result.get("ok", false))
	if ok:
		# 复用本地成功后的下载/OTA/hex导出流程
		succeeded.emit()
	finished.emit(result)


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
	else:
		_append("✗ 编译失败（UV4 退出码 %d，详见下方日志）"
			% int(result.get("exit", -1)))
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
