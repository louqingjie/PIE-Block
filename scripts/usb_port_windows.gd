class_name UsbPortWindows
extends RefCounted

## Windows 桌面 USB-HID 端口适配：把 PieBlockHidWindows GDExtension 单例
## 包装成 HidFlasher.flash() 期望的 UsbPort 鸭子接口（find_device/open/write/read/close）。
##
## 与 Android 侧 usb_port_android.gd 结构一致，差异：
##   - Windows 的 HID 是系统免驱类，无权限申请流程，ensure_permission 恒 true；
##   - 插件缺失（老版本导出/未部署）时所有方法安全返回失败，由 toolchain.gd
##     降级到 Python 兜底路径。

var _plugin = null


func _init() -> void:
	if Engine.has_singleton("PieBlockHidWindows"):
		_plugin = Engine.get_singleton("PieBlockHidWindows")


## 插件 singleton 是否存在（dll 未部署/加载失败时为 false）。
static func is_available() -> bool:
	return Engine.has_singleton("PieBlockHidWindows")


func has_usb_host() -> bool:
	# Windows 桌面没有 OTG 概念，恒可用。
	return true


func find_device() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.find_stc_device())


## Windows HID 免驱动，无授权流程，恒 true。
func ensure_permission() -> bool:
	return true


func open() -> bool:
	if _plugin == null:
		return false
	return bool(_plugin.open())


func write(bytes: PackedByteArray) -> bool:
	if _plugin == null:
		return false
	if not bool(_plugin.write_report(bytes)):
		# 插件侧记录最近一次 Win32 错误，写失败时打出来便于真机排查。
		var err_text: String = str(_plugin.get_last_error())
		if not err_text.is_empty():
			printerr("[PieBlockHidWindows] write_report 失败: %s" % err_text)
		return false
	return true


## 读一个 HID 报告；超时/失败返回空数组。
func read(timeout_ms: int) -> PackedByteArray:
	if _plugin == null:
		return PackedByteArray()
	var resp = _plugin.read_report(timeout_ms)
	if resp == null:
		return PackedByteArray()
	return resp


func close() -> void:
	if _plugin != null:
		_plugin.close()
