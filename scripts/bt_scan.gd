class_name BtScan
extends RefCounted

## btctl 封装：Godot 侧调用经典蓝牙 (SPP) 扫描 / 配对。
##
## 源码在 tools/btctl/，编译产物 tools/btctl/out/btctl.exe（开发机），
## 或部署到 user://btctl/btctl.exe（应用打包时）。
## 结果走 btctl 的 --out UTF-8 JSON 文件读取，避免中文 Windows 下
## OS.execute 的 stdout 数组按系统代码页解码乱码的问题。
##
## 扫描真实查询约 multiplier * 1.28s（默认 8 ≈ 10s），务必在后台线程跑，
## 别在主线程直接调 run_scan()（会卡 UI）。

signal finished(result: Dictionary)
signal failed(message: String)

const EXE_DEV: String = "res://tools/btctl/out/btctl.exe"
const EXE_DEPLOYED: String = "user://btctl/btctl.exe"
const DEFAULT_MULTIPLIER: int = 8

var _thread: Thread = null
var _result: Dictionary = {}


## 定位 btctl.exe：优先已部署版本，其次开发产物。
static func find_exe() -> String:
	if FileAccess.file_exists(EXE_DEPLOYED):
		return ProjectSettings.globalize_path(EXE_DEPLOYED)
	if FileAccess.file_exists(EXE_DEV):
		return ProjectSettings.globalize_path(EXE_DEV)
	return ""


## 同步扫描（阻塞，约 multiplier*1.28s）。供无头测试 / 命令行使用。
## 返回 {"ok": bool, "exit": int, "data": <btctl JSON 里的对象>}。
static func run_scan(multiplier: int = DEFAULT_MULTIPLIER) -> Dictionary:
	var exe := find_exe()
	if exe.is_empty():
		return {"ok": false, "exit": -1, "error":
			"未找到 btctl.exe（先跑 tools/btctl/build.ps1，或部署到 user://btctl/）"}

	var out_path := "user://btctl_scan_%d.json" % Time.get_ticks_usec()
	var out_abs := ProjectSettings.globalize_path(out_path)
	var output: Array = []
	var exit_code := OS.execute(exe, ["--scan", "--multiplier", str(multiplier), "--out", out_abs], output, true)
	var data: Dictionary = _read_json(out_path)
	DirAccess.remove_absolute(out_abs)

	var result: Dictionary = {"ok": exit_code == 0, "exit": exit_code, "data": data}
	if exit_code != 0:
		result["error"] = "btctl 退出码 %d" % exit_code
	return result


## 异步扫描：后台线程跑，完成发 finished(result)，失败发 failed(message)。
func scan_async(multiplier: int = DEFAULT_MULTIPLIER) -> void:
	if _thread != null:
		return
	var exe := find_exe()
	if exe.is_empty():
		failed.emit("未找到 btctl.exe（先跑 tools/btctl/build.ps1，或部署到 user://btctl/）")
		return
	_result = {}
	_thread = Thread.new()
	_thread.start(_worker.bind(exe, multiplier))


func _worker(exe: String, multiplier: int) -> void:
	_result = run_scan(multiplier)
	call_deferred("_on_worker_done")


func _on_worker_done() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	if _result.get("ok", false):
		finished.emit(_result)
	else:
		failed.emit(str(_result.get("error", "操作失败")))


## 同步配对（阻塞直到静默 PIN 完成或系统对话框关闭）。
## pin 非空时先尝试静默配对（HC-05/06 固定 1234），失败自动回退系统对话框。
## 返回 {"ok": bool, "exit": int, "data": <btctl JSON 对象>, "error": String?}。
static func run_pair(address: String, pin: String = "", system_dialog := false, enable_spp := true) -> Dictionary:
	var exe := find_exe()
	if exe.is_empty():
		return {"ok": false, "exit": -1, "error":
			"未找到 btctl.exe（先跑 tools/btctl/build.ps1，或部署到 user://btctl/）"}

	var args: Array = ["--pair", address, "--enable-spp"]
	if system_dialog:
		args.append("--system-dialog")
	elif not pin.is_empty():
		args.append("--pin")
		args.append(pin)
	var out_path := "user://btctl_pair_%d.json" % Time.get_ticks_usec()
	var out_abs := ProjectSettings.globalize_path(out_path)
	args.append("--out")
	args.append(out_abs)
	var output: Array = []
	var exit_code := OS.execute(exe, args, output, true)
	var data: Dictionary = _read_json(out_path)
	DirAccess.remove_absolute(out_abs)

	var result: Dictionary = {
		"ok": exit_code == 0 and bool(data.get("ok", false)),
		"exit": exit_code,
		"data": data,
	}
	if not result["ok"]:
		result["error"] = str(data.get("error",
			"配对失败（btctl 退出码 %d）" % exit_code))
	return result


## 异步配对：后台线程跑，完成发 finished(result)，失败发 failed(message)。
func pair_async(address: String, pin: String = "", system_dialog := false, enable_spp := true) -> void:
	if _thread != null:
		return
	var exe := find_exe()
	if exe.is_empty():
		failed.emit("未找到 btctl.exe（先跑 tools/btctl/build.ps1，或部署到 user://btctl/）")
		return
	_result = {}
	_thread = Thread.new()
	_thread.start(_pair_worker.bind(address, pin, system_dialog, enable_spp))


func _pair_worker(address: String, pin: String, system_dialog: bool, enable_spp: bool) -> void:
	_result = run_pair(address, pin, system_dialog, enable_spp)
	call_deferred("_on_worker_done")


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	if typeof(j.data) != TYPE_DICTIONARY:
		return {}
	return j.data
