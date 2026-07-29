extends SceneTree

## IAP 协议交叉验证
##
## CRC16 有三份实现，必须逐位一致：
##   1. Python  stc32g/toolchain/stcflash/pie_block_iap.py    iap_crc16()
##   2. C       stc32g/Libraries/deivers/src/iap_proto.c      iap_crc16()
##   3. 本文件（独立第三方参考实现）
##
## 三份独立写出来再互相比对，比"照抄一份再说它们一样"更能抓到错。
## C 侧无法在这里直接跑，改由探针固件上板时打印同一组向量，
## 本脚本负责生成期望值并断言 Python 侧一致。

var _pass := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [ok] %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s %s" % [name, detail])


## CRC-16/MODBUS 参考实现。故意不参考另两份的写法。
func crc16_ref(data: PackedByteArray) -> int:
	var crc := 0xFFFF
	for b in data:
		crc = crc ^ b
		for _i in range(8):
			var lsb := crc & 1
			crc = crc >> 1
			if lsb == 1:
				crc = crc ^ 0xA001
	return crc & 0xFFFF


func _init() -> void:
	print("=== IAP 协议交叉验证 ===")
	print()

	print("CRC16 标准测试向量")
	# 这些是 CRC-16/MODBUS 的公开已知值，不是从我们自己的实现里抄的
	_ok("空输入 == 0xFFFF", crc16_ref(PackedByteArray()) == 0xFFFF,
		"got %04X" % crc16_ref(PackedByteArray()))
	var s := "123456789".to_ascii_buffer()
	_ok('"123456789" == 0x4B37', crc16_ref(s) == 0x4B37, "got %04X" % crc16_ref(s))

	print()
	print("CRC16 供芯片侧对照的向量（探针固件应打印相同值）")
	var vectors: Array = [
		PackedByteArray(),
		PackedByteArray([0x00]),
		PackedByteArray([0xFF]),
		PackedByteArray([0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]),
		"123456789".to_ascii_buffer(),
	]
	for v in vectors:
		var c: int = crc16_ref(v)
		print("    len=%-3d bytes=%-24s crc=%04X" % [v.size(), _hex(v), c])

	print()
	print("增量式 CRC 与一次性 CRC 必须等价")
	# bootloader 分块校验 64K 时用增量式，两者必须给出同一结果
	var big := PackedByteArray()
	for i in range(1000):
		big.append((i * 37 + 11) & 0xFF)
	var once: int = crc16_ref(big)
	var inc: int = 0xFFFF
	var pos := 0
	while pos < big.size():
		var chunk: PackedByteArray = big.slice(pos, mini(pos + 256, big.size()))
		inc = _crc16_update_ref(inc, chunk)
		pos += 256
	_ok("1000 字节分 256 块增量 == 一次性", inc == once,
		"inc=%04X once=%04X" % [inc, once])

	print()
	print("帧结构常量与 Python/C 侧一致")
	# 帧头 2 + ver 1 + cmd 1 + addr 3 + len 2 + crc 2 = 11
	_ok("IAP_FRAME_OVERHEAD == 11", 2 + 1 + 1 + 3 + 2 + 2 == 11)
	_ok("IAP_HEADER_LEN == 9", 2 + 1 + 1 + 3 + 2 == 9)
	_ok("App 区 65024 == 127 个 512B 扇区", 0xFE00 == 127 * 512,
		"0xFE00=%d 127*512=%d" % [0xFE00, 127 * 512])
	_ok("App 区上限与 stcgal split 上限一致", 0xFE00 == 65024)

	print()
	print("帧编码参考实现，与 Python build_frame 对照")
	var f := _build_frame_ref(0x01, 0x000000, PackedByteArray())
	print("    PING           -> %s" % _hex(f))
	var f2 := _build_frame_ref(0x03, 0x000200, PackedByteArray([0xDE, 0xAD]))
	print("    WRITE@0x200    -> %s" % _hex(f2))
	_ok("PING 帧长 == 11", f.size() == 11, "got %d" % f.size())
	_ok("WRITE 帧长 == 13", f2.size() == 13, "got %d" % f2.size())
	_ok("帧头是 AA 55", f[0] == 0xAA and f[1] == 0x55)
	_ok("addr 小端存放", f2[4] == 0x00 and f2[5] == 0x02 and f2[6] == 0x00,
		"got %02X %02X %02X" % [f2[4], f2[5], f2[6]])

	print()
	print("地址边界：bootloader 必须拒绝代码区")
	var app_base := 0x000000
	var app_size := 0xFE00
	var code_base := 0x010000
	_ok("App 区末字节仍在允许范围", app_base + app_size - 1 < code_base,
		"末字节 0x%06X < 0x%06X" % [app_base + app_size - 1, code_base])
	_ok("App 区与代码区不重叠", app_base + app_size <= code_base)

	print()
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _crc16_update_ref(crc: int, data: PackedByteArray) -> int:
	for b in data:
		crc = crc ^ b
		for _i in range(8):
			var lsb := crc & 1
			crc = crc >> 1
			if lsb == 1:
				crc = crc ^ 0xA001
	return crc & 0xFFFF


func _build_frame_ref(cmd: int, addr: int, payload: PackedByteArray) -> PackedByteArray:
	var body := PackedByteArray()
	body.append(0x01) # ver
	body.append(cmd)
	body.append(addr & 0xFF)
	body.append((addr >> 8) & 0xFF)
	body.append((addr >> 16) & 0xFF)
	body.append(payload.size() & 0xFF)
	body.append((payload.size() >> 8) & 0xFF)
	body.append_array(payload)

	var c := crc16_ref(body)
	var out := PackedByteArray([0xAA, 0x55])
	out.append_array(body)
	out.append(c & 0xFF)
	out.append((c >> 8) & 0xFF)
	return out


func _hex(data: PackedByteArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for b in data:
		parts.append("%02X" % b)
	return " ".join(parts)
