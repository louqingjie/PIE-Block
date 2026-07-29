extends SceneTree

## 验证下载连接层：串口分类、挑选策略、失败阶段分类与排查建议。
##
## 不需要板子也不需要串口 —— 这些逻辑是纯函数，值得留着做回归。
## 若系统上恰好插着串口设备，末尾会顺带打印一次真实枚举结果供人工核对。
##
## 运行：godot --headless --path . --script scripts/test_download_conn.gd

const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var fails: Array = []

	var tc = TC.new(func(s): pass)

	# --- 端口分类
	var cases: Array = [
		{"desc": "USB-SERIAL CH340 (COM11)", "hwid": "USB VID:PID=1A86:7523", "want": "usb_serial"},
		{"desc": "USB Serial Port (COM3)", "hwid": "USB VID:PID=0403:6001", "want": "usb_serial"},
		{"desc": "Silicon Labs CP210x", "hwid": "USB VID:PID=10C4:EA60", "want": "usb_serial"},
		{"desc": "Prolific USB-to-Serial", "hwid": "USB VID:PID=067B:2303", "want": "usb_serial"},
		{"desc": "标准串行over蓝牙链接 (COM5)", "hwid": "BTHENUM\\{0000110", "want": "bluetooth"},
		{"desc": "Bluetooth Serial Port", "hwid": "BTHENUM", "want": "bluetooth"},
		{"desc": "通信端口", "hwid": "ACPI\\PNP0501", "want": "unknown"},
		{"desc": "Communications Port (COM1)", "hwid": "ACPI\\PNP0501", "want": "virtual"},
		{"desc": "", "hwid": "", "want": "unknown"},
	]
	for c in cases:
		var got: String = tc._classify_port(c["desc"], c["hwid"], "")
		if got != c["want"]:
			fails.append("分类 [%s] 得到 %s 期望 %s" % [c["desc"], got, c["want"]])

	# --- 挑选逻辑
	var mk := func(dev: String, kind: String) -> Dictionary:
		return {"device": dev, "kind": kind, "label": dev + " test"}

	# 空列表
	var r: Dictionary = tc.pick_download_port([{"device": "", "kind": "x"}])
	# 单个 USB 串口 -> 直接选中
	r = tc.pick_download_port([mk.call("COM11", "usb_serial")])
	if not r["ok"] or r["device"] != "COM11":
		fails.append("单个 USB 口应直接选中，得到 %s" % str(r))

	# USB + 蓝牙同时存在 -> 优先 USB
	r = tc.pick_download_port([mk.call("COM5", "bluetooth"), mk.call("COM11", "usb_serial")])
	if not r["ok"] or r["device"] != "COM11":
		fails.append("USB 应优先于蓝牙，得到 %s" % str(r))

	# 只有蓝牙 -> 选蓝牙
	r = tc.pick_download_port([mk.call("COM5", "bluetooth")])
	if not r["ok"] or r["device"] != "COM5":
		fails.append("只有蓝牙时应选它，得到 %s" % str(r))

	# 两个同类型 -> 不猜
	r = tc.pick_download_port([mk.call("COM11", "usb_serial"), mk.call("COM12", "usb_serial")])
	if r["ok"]:
		fails.append("同类型多个时不该自动选，得到 %s" % str(r))
	if r["candidates"].size() != 2:
		fails.append("应把两个候选都返回")

	# 只有虚拟口 -> 失败且说明原因
	r = tc.pick_download_port([mk.call("COM1", "virtual")])
	if r["ok"]:
		fails.append("只有虚拟口时不该选中")

	# 蓝牙多个也不猜
	r = tc.pick_download_port([mk.call("COM5", "bluetooth"), mk.call("COM6", "bluetooth")])
	if r["ok"]:
		fails.append("多个蓝牙口不该自动选")

	# --- 失败阶段分类
	var stage_cases: Array = [
		{"log": "打开串口 COM11 失败: 拒绝访问", "want": "port"},
		{"log": "bootloader 没有响应。可能原因：", "want": "connect"},
		{"log": "bootloader 就绪\nPROGRAM 连续 3 次失败", "want": "program"},
		{"log": "擦除 App 区…\nERASE 连续 3 次失败", "want": "erase"},
		{"log": "写入…\n读回校验失败：3 个块内容不符", "want": "verify"},
		{"log": "读取固件失败: hex 里没有数据", "want": "hex"},
		{"log": "什么都没有", "want": "unknown"},
	]
	for c in stage_cases:
		var got: String = tc._classify_iap_failure(c["log"])
		if got != c["want"]:
			fails.append("阶段分类 得到 %s 期望 %s（日志 %s）"
				% [got, c["want"], c["log"].substr(0, 30)])

	# 每个阶段都要有可执行的建议
	for st in ["port", "connect", "erase", "program", "verify", "hex", "env"]:
		var hint: PackedStringArray = tc.iap_failure_hint(st)
		if hint.is_empty():
			fails.append("阶段 %s 缺排查建议" % st)

	# --- 波特率常量一致性
	if TC.DEFAULT_BOOT_BAUD != 115200:
		fails.append("boot 波特率应为 115200（与 config.h 一致）")
	if TC.DEFAULT_APP_BAUD != TC.DEFAULT_BOOT_BAUD:
		fails.append("App 与 boot 波特率应相同，否则蓝牙链路中途切不了")

	# --- 真机：枚举当前串口
	print("--- 当前系统串口 ---")
	var ports: Array = tc.list_serial_ports_detailed()
	if ports.is_empty():
		print("  (无，或 pyserial 未安装)")
	for info in ports:
		print("  %-8s %-14s %s" % [info["device"], info["kind"], info["description"]])
	var real: Dictionary = tc.pick_download_port(ports)
	print("挑选结果: ok=%s device=%s" % [real["ok"], real["device"]])
	print("  理由: %s" % real["reason"])

	print("")
	if fails.is_empty():
		print("全部通过（%d 项）" % (cases.size() + stage_cases.size() + 9))
		quit(0)
	else:
		print("失败 %d 项:" % fails.size())
		for f in fails:
			print("  [FAIL] %s" % f)
		quit(1)
