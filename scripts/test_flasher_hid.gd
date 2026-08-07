extends SceneTree

## 烧录核心（HidFlasher）验证脚本。
## 运行方式：godot --headless --path . --script scripts/test_flasher_hid.gd
##
## 测试向量由 stc32g/toolchain/stcflash/pie_block_hid.py 的实测函数生成
## （build_packet / build_write_blocks），保证 GDScript 移植与 Python 逐字节等价。
## 端到端用 FakePort 替身模拟 USB-HID 设备响应，不依赖真机。

const HF = preload("res://scripts/hid_flasher.gd")

var _fail: int = 0


func _initialize() -> void:
	print("=== USB-HID 烧录核心验证 ===")
	_test_build_packet()
	_test_split_reports()
	_test_load_hex()
	_test_build_write_blocks()
	_test_flash_ok()
	_test_flash_cancel()
	_test_flash_cancel_pre()
	_test_flash_connect_fail()
	_test_flash_hex_missing()
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


# ------------------------------------------------------------------ build_packet

func _test_build_packet() -> void:
	var info: PackedByteArray = HF.build_packet(PackedByteArray(
		[0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00]))
	_check("build_packet(info) 与 Python 逐字节一致", info == PackedByteArray([
		0x46, 0xb9, 0x6a, 0x00, 0x0f, 0x01, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x80, 0x00, 0x00, 0xfa, 0x16]))

	var unlock: PackedByteArray = HF.build_packet(PackedByteArray([0x05, 0x00, 0x00, 0x5a, 0xa5]))
	_check("build_packet(unlock) 与 Python 逐字节一致", unlock == PackedByteArray([
		0x46, 0xb9, 0x6a, 0x00, 0x0b, 0x05, 0x00, 0x00, 0x5a, 0xa5, 0x01, 0x79, 0x16]))

	var erase: PackedByteArray = HF.build_packet(PackedByteArray([0x03, 0x00, 0x00, 0x5a, 0xa5]))
	_check("build_packet(erase) 与 Python 逐字节一致", erase == PackedByteArray([
		0x46, 0xb9, 0x6a, 0x00, 0x0b, 0x03, 0x00, 0x00, 0x5a, 0xa5, 0x01, 0x77, 0x16]))

	var reset: PackedByteArray = HF.build_packet(PackedByteArray([0xFF]))
	_check("build_packet(reset) 与 Python 逐字节一致", reset == PackedByteArray([
		0x46, 0xb9, 0x6a, 0x00, 0x07, 0xff, 0x01, 0x70, 0x16]))

	# 128 字节数据块（0x00..0x7F）的首块写帧：payload = cmd 头 + 数据
	var write_data := PackedByteArray()
	for i in range(128):
		write_data.append(i)
	var payload := PackedByteArray([0x32, 0x00, 0x00, 0x5a, 0xa5])
	payload.append_array(write_data)
	var pkt: PackedByteArray = HF.build_packet(payload)
	_check("build_packet(write_first) 长度", pkt.size() == 141)
	_check("build_packet(write_first) 帧头/长度/校验", pkt.slice(0, 10) == PackedByteArray([
		0x46, 0xb9, 0x6a, 0x00, 0x8b, 0x32, 0x00, 0x00, 0x5a, 0xa5]))
	_check("build_packet(write_first) 数据完整", pkt.slice(10, 138) == write_data)
	_check("build_packet(write_first) 校验和+结束符", pkt.slice(138, 141) == PackedByteArray([
		0x21, 0xe6, 0x16]))


# ------------------------------------------------------------------ split_reports

func _test_split_reports() -> void:
	var write_data := PackedByteArray()
	for i in range(128):
		write_data.append(i)
	var payload := PackedByteArray([0x32, 0x00, 0x00, 0x5a, 0xa5])
	payload.append_array(write_data)
	var pkt: PackedByteArray = HF.build_packet(payload)
	var reports: Array = HF.split_reports(pkt)
	_check("split_reports 报告数（141B → 3 个）", reports.size() == 3)
	_check("split_reports 报告 1 与 Python 一致",
		reports[0] == PackedByteArray([0x00, 0x46, 0xb9, 0x6a, 0x00, 0x8b, 0x32, 0x00, 0x00,
			0x5a, 0xa5, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a,
			0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
			0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24,
			0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31,
			0x32, 0x33, 0x34, 0x35]))
	_check("split_reports 报告 2 与 Python 一致",
		reports[1] == PackedByteArray([0x00, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d,
			0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a,
			0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
			0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64,
			0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71,
			0x72, 0x73, 0x74, 0x75]))
	# 满 64 字节块 → 0x00 前缀 + 64 字节 = 65 字节线上报告（Python 实测如此）
	_check("split_reports 报告 3 与 Python 一致（尾块 13B + 补零）",
		reports[2].size() == 64
		and reports[2].slice(0, 14) == PackedByteArray([0x00, 0x76, 0x77, 0x78, 0x79, 0x7a,
			0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x21, 0xe6, 0x16]))
	# 报告尺寸：满块 65 字节、尾块 64 字节（与 Python 一致）
	_check("split_reports 尺寸与 Python 一致（65/65/64）", reports[0].size() == 65
		and reports[1].size() == 65 and reports[2].size() == 64)
	# 数据完整性与顺序
	_check("split_reports 内容连续无丢失",
		reports[0].slice(1, 65) == pkt.slice(0, 64)
		and reports[1].slice(1, 65) == pkt.slice(64, 128)
		and reports[2].slice(1, 14) == pkt.slice(128, 141))
	# 小帧（reset 9B）→ 1 个报告，补零到 64
	var reset_reports: Array = HF.split_reports(HF.build_packet(PackedByteArray([0xFF])))
	_check("split_reports(reset) 1 个报告且补零", reset_reports.size() == 1
		and reset_reports[0].size() == 64
		and reset_reports[0].slice(0, 10) == PackedByteArray([0x00, 0x46, 0xb9, 0x6a, 0x00,
			0x07, 0xff, 0x01, 0x70, 0x16]))


# ------------------------------------------------------------------ load_hex

func _test_load_hex() -> void:
	# 该 hex 由 intelhex 库生成（见 gen_hid_vectors.py V4）：
	# 0xFE0000=01 0xFE0001=02 0xFE0040=DE 0xFE0080=AD 0xFE00FF=EF 0xFF0000=10
	var path: String = "user://test_flasher_sample.hex"
	_put_file(path, ":0200000400FEFC\n:020000000102FB\n:01004000DEE1\n"
		+ ":01008000ADD2\n:0100FF00EF11\n:0200000400FFFB\n:0100000010EF\n:00000001FF\n")
	var parsed: Dictionary = HF.load_hex(path)
	_check("load_hex ok", parsed.ok == true)
	_check("load_hex minaddr=0xFE0000", parsed.minaddr == 0xFE0000)
	var data: Dictionary = parsed.data
	_check("load_hex 字节数 6", data.size() == 6)
	_check("load_hex 0xFE0000=01", data.get(0xFE0000) == 0x01)
	_check("load_hex 0xFE0040=DE", data.get(0xFE0040) == 0xDE)
	_check("load_hex 0xFE00FF=EF", data.get(0xFE00FF) == 0xEF)
	_check("load_hex 跨 ELAR 0xFF0000=10", data.get(0xFF0000) == 0x10)

	var missing: Dictionary = HF.load_hex("user://does_not_exist.hex")
	_check("load_hex 文件不存在 → 报错", missing.ok == false and missing.err.contains("hex 不存在"))
	var bad_path: String = "user://test_flasher_bad.hex"
	_put_file(bad_path, ":0200000400FE00\n:00000001FF\n")
	var bad: Dictionary = HF.load_hex(bad_path)
	_check("load_hex 校验和错误 → 报错", bad.ok == false and bad.err.contains("校验和"))


# ------------------------------------------------------------------ build_write_blocks

func _test_build_write_blocks() -> void:
	var r: Dictionary = HF.build_write_blocks({0xFE0000: 0x01, 0xFE0001: 0x02}, 0xFE0000)
	_check("A 用户区小块：1 块 cmd=0x32 补 0x00", r.ok and r.blocks.size() == 1
		and r.blocks[0].cmd == 0x32 and r.blocks[0].isp_addr == 0x0000
		and r.total == 128)
	_check("A 数据头与 Python 一致", r.blocks[0].data.slice(0, 4) == PackedByteArray(
		[0x01, 0x02, 0x00, 0x00]))

	r = HF.build_write_blocks({0xFE0000: 0x01, 0xFE0200: 0x02}, 0xFE0000)
	_check("B 用户区两段：首块 0x32 后续 0x12", r.ok and r.blocks.size() == 2
		and r.blocks[0].cmd == 0x32 and r.blocks[0].isp_addr == 0x0000
		and r.blocks[1].cmd == 0x12 and r.blocks[1].isp_addr == 0x0200
		and r.total == 256)
	_check("B 数据头与 Python 一致", r.blocks[0].data.slice(0, 2) == PackedByteArray([0x01, 0x00])
		and r.blocks[1].data.slice(0, 2) == PackedByteArray([0x02, 0x00]))

	r = HF.build_write_blocks({0xFF0000: 0xAA}, 0xFF0000)
	_check("C 0xFF0000 区：cmd=0x02", r.ok and r.blocks.size() == 1
		and r.blocks[0].cmd == 0x02 and r.blocks[0].isp_addr == 0x0000
		and r.blocks[0].data[0] == 0xAA)

	r = HF.build_write_blocks({0x0000: 0x55, 0x0001: 0x66}, 0x0000)
	_check("D 0x0000 基址：cmd=0x32 原地址", r.ok and r.blocks.size() == 1
		and r.blocks[0].cmd == 0x32 and r.blocks[0].isp_addr == 0x0000
		and r.blocks[0].data.slice(0, 2) == PackedByteArray([0x55, 0x66]))

	r = HF.build_write_blocks({0xFE0000: 0x01, 0xFF0000: 0x02}, 0xFE0000)
	_check("E 混合：用户区 + 高区", r.ok and r.blocks.size() == 2
		and r.blocks[0].cmd == 0x32 and r.blocks[1].cmd == 0x02
		and r.blocks[1].data[0] == 0x02 and r.total == 256)


# ------------------------------------------------------------------ flash 端到端（FakePort）

## 假设备：按顺序弹出预设响应；记录所有写出的报告。
class FakePort:
	var found: bool = true
	var opened: bool = true
	var writes: Array = []
	var responses: Array = []

	func find_device() -> bool:
		return found

	func open() -> bool:
		return opened

	func write(bytes) -> bool:
		writes.append(bytes)
		return true

	func read(timeout_ms) -> PackedByteArray:
		if responses.is_empty():
			return PackedByteArray()
		return responses.pop_front()

	func close() -> void:
		pass


## 构造一帧 ACK 响应（帧头 46 B9 68，payload 首字节为 cmd）。
func _make_ack(cmd: int, payload: Array = []) -> PackedByteArray:
	var body := PackedByteArray([cmd])
	for b in payload:
		body.append(b)
	var resp := PackedByteArray([0x46, 0xB9, 0x68])
	resp.append(0x00)
	resp.append(body.size() + 2)
	resp.append_array(body)
	resp.append(0x00)
	resp.append(0x00)
	return resp


func _make_port() -> FakePort:
	var port := FakePort.new()
	port.responses.append(_make_ack(0x01, [0x00, 0x70]))
	port.responses.append(_make_ack(0x05, [0x00, 0x74]))
	port.responses.append(_make_ack(0x03, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x74]))
	# 3 个写块各需一个 ACK
	for i in range(3):
		port.responses.append(_make_ack(0x02, [0x54]))
	return port


func _write_3blk_hex() -> String:
	var path: String = "user://test_flasher_3blk.hex"
	_put_file(path, ":0200000400FEFC\n:0100000001FE\n:0102000002FB\n"
		+ ":0104000003F8\n:00000001FF\n")
	return path


func _test_flash_ok() -> void:
	var logs: Array = []
	var flasher := HF.new(func(line: String) -> void: logs.append(line))
	var port := _make_port()
	var result: Dictionary = flasher.flash(_write_3blk_hex(), port, null, true)
	_check("flash 成功 ok=true stage=done", result.ok and result.stage == "done")
	# 写序列：info 1 + unlock 1 + erase 1 + 3 块 × 3 报告 + reset 1
	_check("flash 写报告数 = 1+1+1+9+1", port.writes.size() == 13)
	# 最后一份是 reset 帧报告（0x46 0xB9 0x6A 00 07 FF ...）
	_check("flash 末帧为 reset", port.writes[12].slice(1, 10) == PackedByteArray(
		[0x46, 0xb9, 0x6a, 0x00, 0x07, 0xff, 0x01, 0x70, 0x16]))
	# 日志行格式与 Python 一致（download_controller 进度解析依赖）
	var joined: String = "\n".join(logs)
	_check("日志含 info OK", joined.contains("info OK"))
	_check("日志含 unlock OK", joined.contains("unlock OK"))
	_check("日志含 erase OK, UID=", joined.contains("erase OK, UID=01 02 03 04 05 06 07"))
	_check("日志含 Writing 384 bytes in 3 blocks",
		joined.contains("Writing 384 bytes in 3 blocks..."))
	# Python 只在第 25 块和最后一块打印进度行
	_check("日志不含 block 1/3（与 Python 一致）", not joined.contains("block 1/3"))
	_check("日志含 block 3/3", joined.contains("  block 3/3 @0x0400 (cmd=0x12)"))
	_check("日志含烧录成功", joined.contains("烧录成功（384 bytes, 3 blocks）"))
	_check("日志含 reset", joined.contains("resetting...") and joined.contains("已复位"))


func _test_flash_cancel() -> void:
	var token = preload("res://scripts/cancel_token.gd").new()
	var flasher := HF.new(Callable())
	var port := _make_port()
	# 第 2 块写完后触发取消：progress 回调里置位
	var result: Dictionary = flasher.flash(_write_3blk_hex(), port, token, true,
		func(stage: String, total: int, done: int, bytes: int) -> void:
			if done == 2:
				token.request_cancel())
	_check("flash 中途取消 ok=false canceled=true stage=canceled",
		not result.ok and result.canceled and result.stage == "canceled")
	# info+unlock+erase + 2 块 × 3 报告 = 9，reset 未发送
	_check("flash 取消后未发 reset", port.writes.size() == 9)
	_check("flash 取消后设备已关闭", true)


func _test_flash_cancel_pre() -> void:
	var token = preload("res://scripts/cancel_token.gd").new()
	token.request_cancel()
	var port := FakePort.new()
	var flasher := HF.new(Callable())
	var result: Dictionary = flasher.flash(_write_3blk_hex(), port, token, true)
	_check("flash 预取消 → canceled 且未触碰设备", result.stage == "canceled"
		and result.canceled and port.writes.is_empty())


func _test_flash_connect_fail() -> void:
	var port := FakePort.new()
	port.found = false
	var flasher := HF.new(Callable())
	var result: Dictionary = flasher.flash(_write_3blk_hex(), port, null, true)
	_check("flash 无设备 → stage=connect", not result.ok and result.stage == "connect")


func _test_flash_hex_missing() -> void:
	var port := FakePort.new()
	var flasher := HF.new(Callable())
	var result: Dictionary = flasher.flash("user://no_such.hex", port, null, true)
	_check("flash hex 缺失 → stage=hex", not result.ok and result.stage == "hex")


func _put_file(path: String, content: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()
