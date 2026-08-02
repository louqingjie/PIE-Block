extends SceneTree

## 验证下载连接层：串口分类、挑选策略、失败阶段分类与排查建议。
##
## 不需要板子也不需要串口 —— 这些逻辑是纯函数，值得留着做回归。
## 若系统上恰好插着串口设备，末尾会顺带打印一次真实枚举结果供人工核对。
##
## 运行：godot --headless --path . --script scripts/test_download_conn.gd

const TC = preload("res://scripts/toolchain.gd")
const CODEGEN_BASE = preload("res://scripts/codegen/codegen_base.gd")


func _initialize() -> void:
	var fails: Array = []

	var tc = TC.new(func(s): pass )

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
	var r: Dictionary = tc.pick_download_port([ {"device": "", "kind": "x"}])
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
		{"log": "读回校验 238 个块…\n烧录失败: 串口设备断开", "want": "verify"},
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
	var usb_connect_hint: String = "\n".join(tc.iap_failure_hint("connect", "usb_serial"))
	if usb_connect_hint.contains("蓝牙"):
		fails.append("USB 串口的连接提示不应提蓝牙")
	var bluetooth_connect_hint: String = "\n".join(tc.iap_failure_hint("connect", "bluetooth"))
	if not bluetooth_connect_hint.contains("蓝牙模块波特率"):
		fails.append("蓝牙连接提示应检查模块波特率")

	# --- 波特率常量
	# boot 侧必须与 PIE_BOOTLOADER/USER/inc/config.h 的 BAUD 一致
	if TC.DEFAULT_BOOT_BAUD != 230400:
		fails.append("boot 波特率应为 230400（与 config.h 一致）")
	# App 侧必须与四个生成器的 UART_Init 一致，否则触发字发不进去。
	# 曾经把它改成 115200 想统一，结果 App 收不到触发字，
	# 下载全部失败且报错是"bootloader 没有响应"，离真因很远。
	if TC.DEFAULT_APP_BAUD != 230400:
		fails.append("App 波特率应为 230400（与生成器的 UART_Init 一致）")
	# 两者不同意味着下载中途要切波特率，蓝牙链路做不到，必须有提示
	if TC.DEFAULT_APP_BAUD != TC.DEFAULT_BOOT_BAUD:
		if tc.bluetooth_baud_note().is_empty():
			fails.append("两段波特率不同时必须给蓝牙用户提示")
	var iap_src: String = FileAccess.get_file_as_string(
		"res://stc32g/toolchain/stcflash/pie_block_iap.py")
	if not iap_src.contains("TRIGGER_SETTLE_MIN") \
			or not iap_src.contains("time.sleep(max(TRIGGER_SETTLE_MIN"):
		fails.append("发送触发字后必须等待 CH340 发完再切换波特率")

	# --- 跨文件约束：共享生成器写进 C 代码的波特率必须与工具链一致，
	# 四个具体生成器则必须调用共享初始化函数。
	if CODEGEN_BASE.APP_BAUD != TC.DEFAULT_APP_BAUD:
		fails.append("CodeGenBase.APP_BAUD 与 DEFAULT_APP_BAUD 不一致")
	var base_src: String = FileAccess.get_file_as_string(
		"res://scripts/codegen/codegen_base.gd")
	if not base_src.contains('code += "void iapEnterDownload(void)'):
		fails.append("iapEnterDownload 必须可供 UART ISR 调用，不能是 static")
	var gen_paths: Array = [
		"res://scripts/codegen/codegen_infantry.gd",
		"res://scripts/codegen/codegen_engineer.gd",
		"res://scripts/codegen/codegen_engineer_ik.gd",
		"res://scripts/codegen/codegen_debug.gd",
	]
	for p in gen_paths:
		var src: String = FileAccess.get_file_as_string(p)
		if src.is_empty():
			fails.append("读不到 %s" % p)
			continue
		if not src.contains("_gen_uart_init_first()"):
			fails.append("%s 没有调用共享串口初始化函数" % p.get_file())

	# 外设初始化可能永久等待硬件，不能只在主循环检查下载请求。
	# UART ISR 收齐触发字后必须直接进入 bootloader。
	for p in [
		"res://stc32g/Projects/ROBOMASTER_INFANTRY/USER/src/isr.c",
		"res://stc32g/Projects/ROBOMASTER_ENGINEER/USER/src/isr.c",
	]:
		var isr_src: String = FileAccess.get_file_as_string(p)
		if not isr_src.contains("extern void iapEnterDownload(void);") \
				or not isr_src.contains("iapEnterDownload();"):
			fails.append("%s 没有在 UART ISR 内立即进入 bootloader" % p)

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
