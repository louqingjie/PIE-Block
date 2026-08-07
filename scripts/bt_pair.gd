class_name BtPairPanel
extends Control

## 蓝牙配对引导面板：
##   扫描 → 选择设备 → 配对（静默 PIN，失败回退系统对话框）→ 等待虚拟串口 → 重试烧录。
## 由 ui.gd 在「烧录连不上主控板」或用户点「蓝牙」按钮时打开。
##
## 注意：扫描 / 配对各约 10s，必须走 BtCtl 的后台线程（本面板已用 scan_async /
## pair_async）。面板被关闭时，在途的 BtCtl 线程由 RefCounted 自持引用保住，不会崩溃。

signal closed
signal retry_flash_requested

const BtCtl = preload("res://scripts/bt_scan.gd")
const DEFAULT_PIN: String = "1234"
const COM_POLL_SEC: float = 1.0
const COM_POLL_MAX: int = 20

var _toolchain = null
var _scan = null
var _pair = null
var _poll_timer: Timer = null
var _poll_left: int = COM_POLL_MAX
var _found_port: Dictionary = {}

@onready var _status: Label = get_node("Dim/Center/Panel/Content/Status")
@onready var _device_list: ItemList = get_node("Dim/Center/Panel/Content/DeviceList")
@onready var _scan_btn: Button = get_node("Dim/Center/Panel/Content/Buttons/ScanBtn")
@onready var _pair_btn: Button = get_node("Dim/Center/Panel/Content/Buttons/PairBtn")
@onready var _retry_btn: Button = get_node("Dim/Center/Panel/Content/Buttons/RetryBtn")
@onready var _close_btn: Button = get_node("Dim/Center/Panel/Content/CloseBtn")


func configure(toolchain) -> void:
	_toolchain = toolchain


func open_guide(hint: String) -> void:
	_show_on_top()
	_set_status(hint)
	start_scan()


func _ready() -> void:
	_scan_btn.pressed.connect(_on_scan_pressed)
	_pair_btn.pressed.connect(_on_pair_pressed)
	_retry_btn.pressed.connect(_on_retry_pressed)
	_close_btn.pressed.connect(_on_close_pressed)
	_device_list.item_activated.connect(_on_pair_pressed)
	_poll_timer = Timer.new()
	_poll_timer.one_shot = true
	_poll_timer.timeout.connect(_on_poll_timeout)
	add_child(_poll_timer)
	hide()


func _show_on_top() -> void:
	show()
	move_to_front()


func _set_status(text: String) -> void:
	_status.text = text


# ------------------------------------------------------------------ 扫描

func start_scan() -> void:
	if _scan != null:
		return
	_device_list.clear()
	_pair_btn.disabled = true
	_scan_btn.disabled = true
	_retry_btn.visible = false
	_retry_btn.disabled = true
	_set_status("正在扫描蓝牙设备（约 10 秒）…\n请确认模块已通电且处于可发现状态。")
	_scan = BtCtl.new()
	_scan.finished.connect(_on_scan_finished)
	_scan.failed.connect(_on_scan_failed)
	_scan.scan_async(8)


func _on_scan_finished(result: Dictionary) -> void:
	_scan = null
	_scan_btn.disabled = false
	var data: Dictionary = result.get("data", {})
	var scan: Dictionary = data.get("scan", {})
	if not bool(scan.get("radio_ready", false)):
		_set_status("未检测到开启的蓝牙适配器。\n请先在系统设置里打开蓝牙，再点「扫描蓝牙设备」。")
		return
	var devices := _merge_devices(scan)
	if devices.is_empty():
		_set_status("没有发现蓝牙模块。请确认：\n· 模块已通电；\n· HC-05 按住按钮进入配对模式（HC-06 常开）；\n· 然后点「扫描蓝牙设备」。")
		return
	for d in devices:
		var tag := "  [已配对]" if bool(d.get("Paired", false)) else ""
		_device_list.add_item("%s  %s%s" % [str(d.get("Name", "")), str(d.get("Address", "")), tag])
		_device_list.set_item_metadata(_device_list.item_count - 1, str(d.get("Address", "")))
	_set_status("发现 %d 个设备，请选择你的蓝牙模块。\nHC-06 默认 PIN 1234。" % devices.size())
	_pair_btn.disabled = false


func _on_scan_failed(message: String) -> void:
	_scan = null
	_scan_btn.disabled = false
	_set_status("扫描失败：%s" % message)


func _merge_devices(scan: Dictionary) -> Array:
	var seen := {}
	var out := []
	for key in ["discoverable", "paired"]:
		for d in scan.get(key, []):
			var addr := str(d.get("Address", ""))
			if addr.is_empty() or seen.has(addr):
				continue
			seen[addr] = true
			out.append(d)
	return out


func _on_scan_pressed() -> void:
	start_scan()


# ------------------------------------------------------------------ 配对

func _on_pair_pressed() -> void:
	if _pair != null:
		return
	var sel := _device_list.get_selected_items()
	if sel.is_empty():
		_set_status("请先在列表里选择你的蓝牙模块。")
		return
	var address: String = str(_device_list.get_item_metadata(sel[0]))
	_pair_btn.disabled = true
	_scan_btn.disabled = true
	_set_status("正在配对 %s …\n先尝试静默 PIN（%s）；若弹出系统窗口，请输入 PIN 并确认。" % [address, DEFAULT_PIN])
	_pair = BtCtl.new()
	_pair.finished.connect(_on_pair_finished)
	_pair.failed.connect(_on_pair_failed)
	_pair.pair_async(address, DEFAULT_PIN, false, true)


func _on_pair_finished(result: Dictionary) -> void:
	_pair = null
	var data: Dictionary = result.get("data", {})
	if not bool(data.get("paired", false)):
		_on_pair_failed(str(data.get("error", "配对未完成")))
		return
	_pair_btn.disabled = true
	_set_status("配对成功（方式：%s）。正在等待虚拟串口出现…" % str(data.get("method", "")))
	_poll_left = COM_POLL_MAX
	_start_poll()


func _on_pair_failed(message: String) -> void:
	_pair = null
	_pair_btn.disabled = false
	_scan_btn.disabled = false
	_set_status("配对失败：%s\n可以重新点「配对选中设备」，或换 USB 线连接。" % message)


# ------------------------------------------------------------------ 等待虚拟串口

func _start_poll() -> void:
	_poll_timer.start(COM_POLL_SEC)


func _on_poll_timeout() -> void:
	_poll_left -= 1
	if _find_bt_port():
		_retry_btn.visible = true
		_retry_btn.disabled = false
		_set_status("已连接虚拟串口：%s\n可以点「重试烧录」继续，或直接关掉本面板。" % _last_port_label())
		return
	if _poll_left <= 0:
		_pair_btn.disabled = false
		_scan_btn.disabled = false
		_set_status("暂未检测到虚拟串口。\n请确认模块已通电、处于可发现状态，可再点「配对」重试；也可以换 USB 线烧录。")
		return
	_start_poll()


func _find_bt_port() -> bool:
	if _toolchain == null or not _toolchain.has_method("ordered_candidate_ports"):
		return false
	for info in _toolchain.ordered_candidate_ports():
		if str(info.get("kind", "")) == "bluetooth":
			_found_port = info
			return true
	return false


func _last_port_label() -> String:
	return str(_found_port.get("label", str(_found_port.get("device", ""))))


# ------------------------------------------------------------------ 关闭

func _on_retry_pressed() -> void:
	close_quiet()
	retry_flash_requested.emit()


func _on_close_pressed() -> void:
	close_quiet()


## 关闭面板（停轮询、隐藏、发 closed）。UI 侧负责 queue_free。
func close_quiet() -> void:
	if _poll_timer:
		_poll_timer.stop()
	hide()
	closed.emit()
