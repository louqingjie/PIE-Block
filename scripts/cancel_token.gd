class_name CancelToken
extends RefCounted

## 跨线程共享的取消令牌 + 子进程 pid 槽。
##
## 背景：烧录 worker 跑在独立 Thread 里，主线程点「取消」后必须能
## 终止卡死的 Python 进程并让 worker 尽快退出。Godot 里跨线程直接
## 读写普通 bool 不安全，这里统一用 Mutex 保护，读写都加锁。

var _mutex: Mutex
var _canceled: bool = false
var _pid: int = -1


func _init() -> void:
	_mutex = Mutex.new()


## 请求取消。可被多次调用，幂等。
func request_cancel() -> void:
	_mutex.lock()
	_canceled = true
	_mutex.unlock()


## 是否已请求取消。
func is_canceled() -> bool:
	_mutex.lock()
	var v: bool = _canceled
	_mutex.unlock()
	return v


## worker 创建子进程后写入 pid（供取消时树杀）。尚未启动时为 -1。
func set_pid(pid: int) -> void:
	_mutex.lock()
	_pid = pid
	_mutex.unlock()


## 读取当前子进程 pid；尚未启动时返回 -1。
func get_pid() -> int:
	_mutex.lock()
	var v: int = _pid
	_mutex.unlock()
	return v
