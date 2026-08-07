class_name HidFlasher
extends RefCounted

## STC32G USB-HID 烧录核心（GDScript 移植，与 pie_block_hid.py 逐字节等价）。
##
## 使用场景：Android 端没有 Python / hidapi，烧录走 Godot 插件提供的
## 裸 HID 读写原语（UsbPort），本类负责协议层：帧封装、64 字节报告拆分、
## Intel HEX 解析、写块分段与 info/unlock/erase/write/reset 状态机。
##
## 日志行格式与 pie_block_hid.py 完全一致（"info OK"、"  block x/y @0x…"、
## "烧录成功（N bytes, M blocks）"），因此 download_controller.gd 的
## 进度解析（_progress_from_log_line）与失败提示（hid_failure_hint）可零改动复用。
##
## UsbPort 鸭子类型接口（由 Android 插件或测试替身实现）：
##   find_device() -> bool          是否枚举到 STC HID 设备（VID 0x34BF/PID 0x1001）
##   open() -> bool                 打开并 claim 接口
##   read(timeout_ms) -> PackedByteArray   读一个报告；超时/失败返回空数组
##   write(bytes) -> bool           写一个报告（64 字节，含报告 ID 前缀）
##   close()                        关闭并释放

const VID: int = 0x34BF
const PID: int = 0x1001

const PACKET_START_A: int = 0x46
const PACKET_START_B: int = 0xB9
const PACKET_END: int = 0x16
const PACKET_HOST: int = 0x6A
const PACKET_MCU: int = 0x68

const BLOCK_SIZE: int = 128
## STC32G 用户代码区基址：ISP 写地址 = hex地址 - CODE_BASE（用 cmd 0x32/0x12）
const CODE_BASE: int = 0xFE0000
## 0xFF0000 区（bootloader/保留数据）：用 cmd 0x02 写，地址 = hex地址 - 0xFF0000
const HIGH_BASE: int = 0xFF0000

const CMD_WRITE_USER: int = 0x12
const CMD_WRITE_USER_FIRST: int = 0x32
const CMD_WRITE_HIGH: int = 0x02


## 日志输出回调（worker 线程内调用，与 Toolchain 的 _emit 模式一致）。
var _log: Callable = Callable()


func _init(log_sink: Callable = Callable()) -> void:
	_log = log_sink


func _emit(line_text: String) -> void:
	if _log.is_valid():
		_log.call(line_text)


# ------------------------------------------------------------------ 帧封装

## 组装一帧：0x46 0xB9 6A + 2字节长度 + payload + 2字节和校验 + 0x16。
## 与 pie_block_hid.py build_packet 逐字节一致（校验和 = sum(自 0x6A 起) & 0xFFFF，大端）。
static func build_packet(payload: PackedByteArray) -> PackedByteArray:
	var p := PackedByteArray()
	p.append(PACKET_START_A)
	p.append(PACKET_START_B)
	p.append(PACKET_HOST)
	var total_len: int = payload.size() + 6
	p.append((total_len >> 8) & 0xFF)
	p.append(total_len & 0xFF)
	p.append_array(payload)
	var checksum: int = 0
	for i in range(2, p.size()):
		checksum += p[i]
	p.append((checksum >> 8) & 0xFF)
	p.append(checksum & 0xFF)
	p.append(PACKET_END)
	return p


## 把完整帧拆成 64 字节 HID 报告（前置报告 ID 0x00，不足补 0x00）。
## 与 pie_block_hid.py send_frame 的拆包逻辑一致；注意：满 64 字节块
## 在 Python 侧会变成 65 字节（0x00 + 64），这是实测验证过的线上行为，
## 保持等价。完整 64 字节块的截断/填充细节在真机联调时确认。
static func split_reports(pkt: PackedByteArray) -> Array:
	var reports: Array = []
	var n_reports: int = (pkt.size() + 63) / 64
	for i in range(n_reports):
		var chunk: PackedByteArray = pkt.slice(i * 64, i * 64 + 64)
		var wire := PackedByteArray([0x00])
		wire.append_array(chunk)
		while wire.size() < 64:
			wire.append(0x00)
		reports.append(wire)
	return reports


# ------------------------------------------------------------------ Intel HEX

## 解析 Intel HEX 文件。
## 返回 {ok: bool, err: String, data: {addr: byte}, minaddr: int}。
## 支持 00 数据 / 01 EOF / 02 段地址 / 04 扩展线性地址 / 03 05 忽略。
static func load_hex(path: String) -> Dictionary:
	var empty: Dictionary = {"ok": false, "err": "", "data": {}, "minaddr": 0}
	if not FileAccess.file_exists(path):
		empty["err"] = "hex 不存在: %s" % path
		return empty
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		empty["err"] = "无法打开 hex: %s" % path
		return empty
	var text: String = f.get_as_text()
	f.close()

	var data: Dictionary = {}
	var minaddr: int = -1
	var upper16: int = 0
	for raw_line in text.split("\n", false):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		if not line.begins_with(":"):
			empty["err"] = "非法行（不以冒号开头）: %s" % line.substr(0, 32)
			return empty
		var body: String = line.substr(1)
		if body.length() < 10 or body.length() % 2 != 0:
			empty["err"] = "非法行长度: %s" % line.substr(0, 32)
			return empty
		var byte_count: int = body.substr(0, 2).hex_to_int()
		if body.length() != 8 + byte_count * 2 + 2:
			empty["err"] = "记录长度不符: %s" % line.substr(0, 32)
			return empty
		var record_addr: int = body.substr(2, 4).hex_to_int()
		var record_type: int = body.substr(6, 2).hex_to_int()
		# 校验和：全部字节（含校验和自身）和为 0
		var check: int = 0
		for i in range(0, body.length(), 2):
			check += body.substr(i, 2).hex_to_int()
		if check & 0xFF != 0:
			empty["err"] = "记录校验和错误: %s" % line.substr(0, 32)
			return empty
		match record_type:
			0x00:
				var base_addr: int = (upper16 << 16) | record_addr
				for i in range(byte_count):
					var b: int = body.substr(8 + i * 2, 2).hex_to_int()
					data[base_addr + i] = b
					if minaddr < 0 or (base_addr + i) < minaddr:
						minaddr = base_addr + i
			0x01:
				break
			0x02:
				upper16 = body.substr(8, 4).hex_to_int()
			0x04:
				upper16 = body.substr(8, 4).hex_to_int()
			0x03, 0x05:
				pass
			_:
				empty["err"] = "未知记录类型 0x%02X" % record_type
				return empty
	empty["ok"] = true
	empty["data"] = data
	empty["minaddr"] = maxi(minaddr, 0)
	return empty


# ------------------------------------------------------------------ 写块分段

## 根据 hex 地址生成 (isp_addr, data128, cmd) 写块列表。
## 与 pie_block_hid.py build_write_blocks 等价，包括块内空缺补 0x00
## （Python bytearray 初值即 0x00，实测行为如此，保持等价）：
##   0xFE0000 段（用户代码）→ cmd 0x32(首块)/0x12(后续)，isp_addr = addr - CODE_BASE
##   0xFF0000 段 → cmd 0x02，isp_addr = addr - HIGH_BASE
##   0x0000 基址 hex（如 pie_bootloader.hex）→ 直接用原地址 cmd 0x32/0x12
## 返回 {ok: bool, err: String, blocks: Array, total: int}
## blocks 每项为 {isp_addr: int, data: PackedByteArray(128), cmd: int}
static func build_write_blocks(data: Dictionary, minaddr: int) -> Dictionary:
	var empty: Dictionary = {"ok": false, "err": "", "blocks": [], "total": 0}
	var user_blocks: Dictionary = {}
	var high_blocks: Dictionary = {}
	if minaddr >= CODE_BASE:
		for addr in data:
			if CODE_BASE <= addr and addr < HIGH_BASE:
				var isp: int = addr - CODE_BASE
				var blk: int = isp / BLOCK_SIZE
				if not user_blocks.has(blk):
					user_blocks[blk] = PackedByteArray()
					user_blocks[blk].resize(BLOCK_SIZE)
				user_blocks[blk][isp % BLOCK_SIZE] = data[addr]
			elif addr >= HIGH_BASE:
				var isp_h: int = addr - HIGH_BASE
				var blk_h: int = isp_h / BLOCK_SIZE
				if not high_blocks.has(blk_h):
					high_blocks[blk_h] = PackedByteArray()
					high_blocks[blk_h].resize(BLOCK_SIZE)
				high_blocks[blk_h][isp_h % BLOCK_SIZE] = data[addr]
		var blocks: Array = []
		var user_list: Array = user_blocks.keys()
		user_list.sort()
		for i in range(user_list.size()):
			var cmd: int = CMD_WRITE_USER_FIRST if i == 0 else CMD_WRITE_USER
			blocks.append({
				"isp_addr": user_list[i] * BLOCK_SIZE,
				"data": user_blocks[user_list[i]],
				"cmd": cmd,
			})
		var high_list: Array = high_blocks.keys()
		high_list.sort()
		for blk_h in high_list:
			blocks.append({
				"isp_addr": blk_h * BLOCK_SIZE,
				"data": high_blocks[blk_h],
				"cmd": CMD_WRITE_HIGH,
			})
		var total: int = 0
		for b in blocks:
			total += b["data"].size()
		empty["ok"] = true
		empty["blocks"] = blocks
		empty["total"] = total
		return empty

	# 0x0000 基址 hex：直接顺序填块 cmd 0x32/0x12
	var blkmap: Dictionary = {}
	for addr in data:
		var blk0: int = addr / BLOCK_SIZE
		if not blkmap.has(blk0):
			blkmap[blk0] = PackedByteArray()
			blkmap[blk0].resize(BLOCK_SIZE)
		blkmap[blk0][addr % BLOCK_SIZE] = data[addr]
	var blocks0: Array = []
	var list0: Array = blkmap.keys()
	list0.sort()
	for i in range(list0.size()):
		var cmd0: int = CMD_WRITE_USER_FIRST if i == 0 else CMD_WRITE_USER
		blocks0.append({
			"isp_addr": list0[i] * BLOCK_SIZE,
			"data": blkmap[list0[i]],
			"cmd": cmd0,
		})
	var total0: int = 0
	for b in blocks0:
		total0 += b["data"].size()
	empty["ok"] = true
	empty["blocks"] = blocks0
	empty["total"] = total0
	return empty


# ------------------------------------------------------------------ 设备层辅助

## 把字节数组格式化成 "aa bb cc" 风格字符串（对照日志输出用）。
static func hexstr(b: PackedByteArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for x in b:
		parts.append("%02x" % x)
	return " ".join(parts)


# ------------------------------------------------------------------ 烧录状态机

## 把完整帧拆成报告并依次写入（对应 Python send_frame 的发送侧）。
## 报告间留 1ms 余量（USB HID 中断端点自带流控，1ms 节流只是保险）。
func _send_frame(port, pkt: PackedByteArray) -> bool:
	for wire in split_reports(pkt):
		if not port.write(wire):
			_emit("烧录失败: 写入报告失败")
			return false
		OS.delay_msec(1)
	return true


## 发送一帧并读取响应、校验帧头（46 B9 68）。失败返回空数组。
func _expect_ack(port, pkt: PackedByteArray, label: String, timeout_ms: int = 3000) -> PackedByteArray:
	if not _send_frame(port, pkt):
		return PackedByteArray()
	var resp: PackedByteArray = port.read(timeout_ms)
	if resp.is_empty():
		_emit("烧录失败: %s: 无响应（超时）" % label)
		return PackedByteArray()
	if resp.size() < 3 or resp[0] != PACKET_START_A or resp[1] != PACKET_START_B \
			or resp[2] != PACKET_MCU:
		_emit("烧录失败: %s: 帧头异常: %s" % [label, hexstr(resp.slice(0, 8))])
		return PackedByteArray()
	return resp


func _info(port) -> bool:
	var pkt: PackedByteArray = build_packet(PackedByteArray([0x01, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x80, 0x00]))
	var resp: PackedByteArray = _expect_ack(port, pkt, "info")
	if resp.is_empty() or resp.size() < 6 or resp[5] != 0x01:
		if not resp.is_empty():
			_emit("烧录失败: info 响应异常: %s" % hexstr(resp.slice(0, 12)))
		return false
	_emit("info OK")
	return true


func _unlock(port) -> bool:
	var pkt: PackedByteArray = build_packet(PackedByteArray([0x05, 0x00, 0x00, 0x5a, 0xa5]))
	var resp: PackedByteArray = _expect_ack(port, pkt, "unlock")
	if resp.is_empty() or resp.size() < 6 or resp[5] != 0x05:
		if not resp.is_empty():
			_emit("烧录失败: unlock 响应异常: %s" % hexstr(resp.slice(0, 12)))
		return false
	_emit("unlock OK")
	return true


func _erase(port) -> bool:
	var pkt: PackedByteArray = build_packet(PackedByteArray([0x03, 0x00, 0x00, 0x5a, 0xa5]))
	var resp: PackedByteArray = _expect_ack(port, pkt, "erase", 3000)
	if resp.is_empty() or resp.size() < 6 or resp[5] != 0x03:
		if not resp.is_empty():
			_emit("烧录失败: erase 响应异常: %s" % hexstr(resp.slice(0, 12)))
		return false
	# erase 响应 payload: 03 <UID 7B> <2B>；从第 6 字节起 7 字节是 UID
	var uid7: PackedByteArray = resp.slice(6, 13)
	_emit("erase OK, UID=%s" % hexstr(uid7))
	return true


## 写一个 128 字节块。cmd: 0x32=用户区首块, 0x12=用户区后续, 0x02=0xFF0000 区块。
func _write_block(port, isp_addr: int, chunk: PackedByteArray, cmd: int) -> bool:
	if isp_addr > 0xFFFF:
		_emit("烧录失败: 地址 0x%X 超出 2 字节范围" % isp_addr)
		return false
	if isp_addr + BLOCK_SIZE > 0x10000:
		_emit("烧录失败: 写地址 0x%X 超出 2 字节范围" % isp_addr)
		return false
	var payload := PackedByteArray([cmd, (isp_addr >> 8) & 0xFF, isp_addr & 0xFF,
		0x5a, 0xa5])
	payload.append_array(chunk.slice(0, BLOCK_SIZE))
	var pkt: PackedByteArray = build_packet(payload)
	var resp: PackedByteArray = _expect_ack(port, pkt, "写块 @0x%04X" % isp_addr)
	if resp.is_empty() or resp.size() < 7 or resp[5] != 0x02 or resp[6] != 0x54:
		if not resp.is_empty():
			_emit("烧录失败: 写块 @0x%04X 失败: %s" % [isp_addr, hexstr(resp.slice(0, 12))])
		return false
	return true


func _reset(port) -> void:
	## 复位设备（0xFF），让其运行新固件。无响应。
	var pkt: PackedByteArray = build_packet(PackedByteArray([0xFF]))
	for wire in split_reports(pkt):
		port.write(wire)
	# 复位后设备可能断开重枚举，不等待响应
	OS.delay_msec(200)


## 执行烧录。hex_path 为 Intel HEX 文件路径，port 为 UsbPort 鸭子类型。
## 全程同步阻塞，UI 侧必须放在 Thread 里跑。
## 返回 {ok: bool, stage: String, log: String, canceled: bool}
##   stage 取值（与 toolchain._classify_hid_failure 对齐）：
##   hex / connect / erase / program / done / canceled / unknown
func flash(hex_path: String, port, token = null, do_reset: bool = true,
		on_progress: Callable = Callable()) -> Dictionary:
	var err_result: Dictionary = {"ok": false, "stage": "unknown", "log": "", "canceled": false}

	if token != null and token.is_canceled():
		err_result["stage"] = "canceled"
		err_result["canceled"] = true
		_emit("✗ 已取消烧录")
		return err_result

	var parsed: Dictionary = load_hex(hex_path)
	if not parsed.ok:
		_emit("[Error] %s" % parsed.err)
		err_result["stage"] = "hex"
		return err_result
	var data: Dictionary = parsed.data
	var start_addr: int = parsed.minaddr
	_emit("Loading flash: %d bytes (Intel HEX, start=0x%X)" % [data.size(), start_addr])

	if not port.find_device():
		_emit("错误：未找到 STC USB-HID 设备 (VID=%04X PID=%04X)。请确认板子处于 ISP 模式（上电冷启动）。"
			% [VID, PID])
		err_result["stage"] = "connect"
		return err_result
	if not port.open():
		_emit("[Error] 无法打开 USB-HID 设备（权限或被占用）")
		err_result["stage"] = "connect"
		return err_result

	if not _info(port):
		port.close()
		return err_result
	if not _unlock(port):
		port.close()
		return err_result
	if token != null and token.is_canceled():
		port.close()
		err_result["stage"] = "canceled"
		err_result["canceled"] = true
		_emit("✗ 已取消烧录")
		return err_result
	if not _erase(port):
		port.close()
		err_result["stage"] = "erase"
		return err_result

	var segments: Dictionary = build_write_blocks(data, start_addr)
	var blocks: Array = segments.blocks
	var total: int = segments.total
	_emit("Writing %d bytes in %d blocks..." % [total, blocks.size()])
	if on_progress.is_valid():
		on_progress.call("blocks", blocks.size(), 0, total)
	for idx in range(blocks.size()):
		if token != null and token.is_canceled():
			port.close()
			err_result["stage"] = "canceled"
			err_result["canceled"] = true
			_emit("✗ 已取消烧录")
			return err_result
		var b: Dictionary = blocks[idx]
		if not _write_block(port, b.isp_addr, b.data, b.cmd):
			port.close()
			err_result["stage"] = "program"
			return err_result
		if (idx + 1) % 25 == 0 or idx + 1 == blocks.size():
			_emit("  block %d/%d @0x%04X (cmd=0x%02x)"
				% [idx + 1, blocks.size(), b.isp_addr, b.cmd])
		if on_progress.is_valid():
			on_progress.call("blocks", blocks.size(), idx + 1, total)
	_emit("烧录成功（%d bytes, %d blocks）" % [total, blocks.size()])
	if do_reset:
		_emit("resetting...")
		_reset(port)
		_emit("已复位，设备应运行新固件")
	port.close()
	return {"ok": true, "stage": "done", "log": "", "canceled": false}
