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

	# --- 波特率常量
	# boot 侧必须与 PIE_BOOTLOADER/USER/inc/config.h 的 BAUD 一致
	if TC.DEFAULT_BOOT_BAUD != 115200:
		fails.append("boot 波特率应为 115200（与 config.h 一致）")
	# App 侧必须与四个生成器的 UART_Init 一致，否则触发字发不进去。
	# 曾经把它改成 115200 想统一，结果 App 收不到触发字，
	# 下载全部失败且报错是"bootloader 没有响应"，离真因很远。
	if TC.DEFAULT_APP_BAUD != 230400:
		fails.append("App 波特率应为 230400（与生成器的 UART_Init 一致）")
	# 两者不同意味着下载中途要切波特率，蓝牙链路做不到，必须有提示
	if TC.DEFAULT_APP_BAUD != TC.DEFAULT_BOOT_BAUD:
		if tc.bluetooth_baud_note().is_empty():
			fails.append("两段波特率不同时必须给蓝牙用户提示")

	# --- 跨文件约束：生成器实际写进 C 代码的波特率必须与常量一致。
	# 这是 toolchain.gd 与四个生成器之间的隐式契约，改任一边都会静默失效，
	# 表现为下载时 App 收不到触发字。用断言把它固定住。
	var gen_paths: Array = [
		"res://scripts/codegen/codegen_infantry.gd",
		"res://scripts/codegen/codegen_engineer.gd",
		"res://scripts/codegen/codegen_engineer_ik.gd",
		"res://scripts/codegen/codegen_debug.gd",
	]
	var want_baud: String = str(TC.DEFAULT_APP_BAUD)
	for p in gen_paths:
		var src: String = FileAccess.get_file_as_string(p)
		if src.is_empty():
			fails.append("读不到 %s" % p)
			continue
		if not src.contains("UART_Init"):
			fails.append("%s 里没有 UART_Init" % p.get_file())
			continue
		if not src.contains(want_baud):
			fails.append("%s 的 UART_Init 波特率与 DEFAULT_APP_BAUD(%s) 不一致"
				% [p.get_file(), want_baud])

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
