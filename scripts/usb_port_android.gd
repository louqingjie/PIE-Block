class_name UsbPortAndroid
extends RefCounted

## Android USB-HID 端口适配：把 PieBlockUsb 插件 singleton 包装成
## HidFlasher.flash() 期望的 UsbPort 鸭子接口（find_device/open/write/read/close），
## 并负责 USB 权限的申请与等待（弹系统授权框，轮询结果）。
##
## 插件方法名是 camelCase（Godot v2 插件不做 snake_case 转换），且
## @UsedByGodot 的 byte[] 参数/返回值在 GDScript 侧映射为 PackedByteArray。

const PERMISSION_TIMEOUT_MS: int = 30000
const POLL_MS: int = 200

var _plugin = null


func _init() -> void:
	if Engine.has_singleton("PieBlockUsb"):
		_plugin = Engine.get_singleton("PieBlockUsb")


## 插件 singleton 是否存在（只在带插件导出的 Android 包内为 true）。
static func is_available() -> bool:
	return Engine.has_singleton("PieBlockUsb")


func has_usb_host() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.isUsbHostSupported())


func find_device() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.findStcDevice())


## 请求授权并阻塞等待结果。返回 true 表示已授权，false 表示被拒绝/超时/无设备。
func ensure_permission() -> bool:
	if _plugin == null:
		return false
	if bool(_plugin.hasPermission()):
		return true
	if not bool(_plugin.requestPermission()):
		return false
	var deadline: int = Time.get_ticks_msec() + PERMISSION_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var state: int = int(_plugin.getPermissionState())
		if state == 1:
			return true
		if state == 2:
			return false
		OS.delay_msec(POLL_MS)
	return false


func open() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.open())


func write(bytes: PackedByteArray) -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.writeReport(bytes))


## 读一个 HID 报告；超时/失败返回空数组。
func read(timeout_ms: int) -> PackedByteArray:
	if _plugin == null:
		return PackedByteArray()
	var resp = _plugin.readReport(timeout_ms)
	if resp == null:
		return PackedByteArray()
	return resp


func close() -> void:
	if _plugin != null:
		_plugin.close()
