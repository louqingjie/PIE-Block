extends SceneTree

## 验证 _run_python_logged 的取消令牌与硬超时：进程挂死时能被树杀并返回哨兵退出码。
## 运行：godot --headless --path . --script scripts/test_toolchain_cancel.gd

const TC = preload("res://scripts/toolchain.gd")
const CT = preload("res://scripts/cancel_token.gd")

var _fail: int = 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _hang_script() -> String:
	# 无限 sleep 的 python 脚本，模拟烧录进程挂死
	var script := "user://cancel_hang.py"
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string("import time\nwhile True:\n    time.sleep(1)\n")
	f.close()
	return ProjectSettings.globalize_path(script)


func _initialize() -> void:
	print("=== Toolchain 取消/超时测试 ===")
	var tc = TC.new(Callable())
	var py: String = tc.find_python()
	_check("找到 Python", not py.is_empty())
	if py.is_empty():
		quit(1)
		return

	var hang: String = _hang_script()
	var log_abs: String = ProjectSettings.globalize_path("user://cancel_test.log")

	# --- 硬超时：进程无限 sleep，2 秒后应被树杀并返回 EXIT_TIMEOUT ---
	var t0: int = Time.get_ticks_msec()
	var exit_code: int = tc._run_python_logged(
		py, [hang], log_abs, Callable(), null, 2.0)
	var elapsed: float = (Time.get_ticks_msec() - t0) / 1000.0
	_check("硬超时返回哨兵 EXIT_TIMEOUT", exit_code == tc.EXIT_TIMEOUT)
	_check("硬超时按时返回（1.5~8s）", elapsed > 1.5 and elapsed < 8.0)

	# --- 取消令牌：主线程主动取消，应树杀并返回 EXIT_CANCELED ---
	var token = CT.new()
	var holder: Array = [-1]
	var th := Thread.new()
	th.start(func() -> void:
		holder[0] = tc._run_python_logged(
			py, [hang], log_abs, Callable(), token, 0.0))
	# 等子进程启动、pid 被写进令牌后再取消（有界轮询，避免线程调度竞态）
	var pid_deadline: int = Time.get_ticks_msec() + 3000
	while token.get_pid() <= 0 and Time.get_ticks_msec() < pid_deadline:
		await process_frame
	_check("取消前 pid 已设置", token.get_pid() > 0)
	token.request_cancel()
	th.wait_to_finish()
	_check("取消返回哨兵 EXIT_CANCELED", holder[0] == tc.EXIT_CANCELED)

	DirAccess.remove_absolute(hang)
	DirAccess.remove_absolute(log_abs)
	print("=== 结果: %s ===" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	quit(0 if _fail == 0 else 1)
