extends SceneTree

## 测试 ik_sim_protocol.read_float32 的字节序（大端 vs 小端）。
## 固件 C251 发送大端 float（42 f6 00 00 = 123.0），若 read_float32 小端解析则错。

func _initialize() -> void:
	var P = preload("res://scripts/ik_sim_protocol.gd")
	var big := PackedByteArray([0x42, 0xf6, 0x00, 0x00])  # 大端 123.0
	var v_big: float = P.read_float32(big, 0)
	print("read_float32(42 f6 00 00) 大端解读应为 123.0 -> 实际 %.6f" % v_big)
	var little := PackedByteArray([0x00, 0x00, 0xf6, 0x42])  # 小端 123.0
	var v_lit: float = P.read_float32(little, 0)
	print("read_float32(00 00 f6 42) 小端解读应为 123.0 -> 实际 %.6f" % v_lit)
	print("结论: 若第一行非 123.0，则 read_float32 不是大端，与固件大端 float 不匹配")
	quit(0)
