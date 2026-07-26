extends SceneTree

## 端到端验证：场景加载、OpenCodeClient 探测/工作区、AI 改文件闭环

const TC = preload("res://scripts/toolchain.gd")
const OCC = preload("res://scripts/opencode_client.gd")

var _fail: int = 0
var _client = null
var _tc = null


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓] %s" % label)
	else:
		print("[✗] %s  %s" % [label, detail])
		_fail += 1


func _initialize() -> void:
	print("=== 端到端验证 ===")
	_test_scenes()
	_test_detect()
	_test_workspace()
	# 延到下一帧：root 窗口在 _initialize 期间尚未完全就绪，
	# 而 OpenCodeClient 的健康轮询依赖 Timer，Timer 必须在场景树内才能计时
	var t := Timer.new()
	t.wait_time = 0.1
	t.one_shot = true
	root.add_child(t)
	t.timeout.connect(_test_ai_roundtrip)
	t.start()


# --- 场景与脚本 ---
func _test_scenes() -> void:
	print("\n--- 场景加载 ---")
	var ui = load("res://scenes/ui.tscn")
	_check("ui.tscn 可加载", ui != null)
	var ce = load("res://scenes/code_edit.tscn")
	_check("code_edit.tscn 可加载", ce != null)
	if ce:
		var inst = ce.instantiate()
		_check("code_edit 实例化成功", inst != null)
		if inst:
			# 核对脚本里写的节点路径与场景实际结构一致
			var paths := [
				"VBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Code/CodeEdit",
				"VBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Output/Output",
				"VBoxContainer/HSplitContainer/AIPanel/Header/Status",
				"VBoxContainer/HSplitContainer/AIPanel/Scroll/Messages",
				"VBoxContainer/HSplitContainer/AIPanel/Input",
				"VBoxContainer/HSplitContainer/AIPanel/Actions/Send",
				"VBoxContainer/HSplitContainer/AIPanel/Actions/Abort",
				"VBoxContainer/TopPanel/Build",
				"VBoxContainer/TopPanel/Button",
				"VBoxContainer/TopPanel/Save",
				"VBoxContainer/TopPanel/Label",
			]
			for p in paths:
				_check("  节点存在 %s" % p.get_file(),
					inst.get_node_or_null(NodePath(p)) != null, p)
			inst.free()
	# ui.tscn 的 AI 编辑按钮
	if ui:
		var uinst = ui.instantiate()
		_check("ui.tscn AIEdit 按钮存在",
			uinst.get_node_or_null(NodePath("VBoxContainer/TopPanel/AIEdit")) != null)
		uinst.free()


# --- 探测 ---
func _test_detect() -> void:
	print("\n--- opencode 探测 ---")
	_client = OCC.new()
	root.add_child(_client)
	_check("client 已在场景树内", _client.is_inside_tree())
	var exe: String = _client.detect()
	_check("找到 opencode 可执行文件", not exe.is_empty(), exe)
	print("    路径: %s" % exe)
	_check("是原生 exe（非 shim）", exe.to_lower().ends_with(".exe"), exe)


# --- 工作区 ---
func _test_workspace() -> void:
	print("\n--- 工作区准备 ---")
	_tc = TC.new(func(l): print("    [log] ", l))
	_check("ensure_deployed", _tc.ensure_deployed())
	_check("ensure_workspace", _client.ensure_workspace(TC.WORKSPACE_DST))
	var ws: String = ProjectSettings.globalize_path(TC.WORKSPACE_DST)
	_check("AGENTS.md 已写入", FileAccess.file_exists(ws.path_join("AGENTS.md")))
	_check("opencode.json 已写入", FileAccess.file_exists(ws.path_join("opencode.json")))
	# AGENTS.md 必须包含关键硬件约束
	if FileAccess.file_exists(ws.path_join("AGENTS.md")):
		var a: String = FileAccess.get_file_as_string(ws.path_join("AGENTS.md"))
		_check("  含 ExpansionBoradControl 约束", a.find("ExpansionBoradControl") >= 0)
		_check("  含 16 位乘法溢出警告", a.find("MUL WR6,WR2") >= 0)
		_check("  含舵机 250/1250", a.find("1250") >= 0)
		_check("  含摩擦轮赔偿条款", a.find("赔偿") >= 0)
	# Libraries 可见（AI 需要读头文件）
	_check("Libraries/ 在工作区内",
		DirAccess.dir_exists_absolute(ws.path_join("Libraries")))


# --- AI 闭环 ---
func _test_ai_roundtrip() -> void:
	print("\n--- AI 对话闭环 ---")
	# 先放一个已知内容的 main.c
	var cg = preload("res://scripts/codegen/codegen_infantry.gd").new()
	var cfg := {
		"channel": "36", "deadzone": "10",
		"normal_speed": "4000", "sprint_speed": "8000", "sprint_enabled": true,
		"l1_io": "P74 P24", "l2_io": "P75 P25",
		"r1_io": "P76 P26", "r2_io": "P77 P27",
		"l1_dir": "正向", "l2_dir": "正向", "r1_dir": "正向", "r2_dir": "正向",
		"booster_io": "P60 P20", "booster_dir": "正向",
		"friction_l_dir": "正向", "friction_r_dir": "正向",
		"yaw_drive": "舵机", "yaw_io": "P62", "yaw_dir": "正向",
		"pitch_drive": "舵机", "pitch_io": "MP74", "pitch_dir": "正向",
		"yaw_mid_offset": "0", "pitch_mid_offset": "0",
		"trigger_key": "A", "trigger_speed": "10000", "trigger_time": "500",
		"booster_key": "D", "zero_enabled": true, "arrow_key": "移动",
	}
	_tc.write_main_c(TC.PROJECT_DST, cg.generate(cfg))
	var mtime_before: int = _tc.main_c_mtime(TC.PROJECT_DST)
	print("    改动前 mtime: %d" % mtime_before)

	_client.ready_changed.connect(_on_ready)
	_client.log_line.connect(func(l): print("    [ai] ", l))
	_client.status_changed.connect(func(s): print("    [status] ", s))
	_client.reply_received.connect(_on_reply.bind(mtime_before))
	_client.request_failed.connect(func(m):
		_check("AI 请求成功", false, m)
		_finish()
	)
	if not _client.start(TC.WORKSPACE_DST):
		_check("启动 AI 服务", false)
		_finish()
		return
	print("    等待服务就绪…")


func _on_ready(is_ready: bool) -> void:
	if not is_ready:
		return
	_check("AI 服务就绪", true)
	print("    端口: %d" % _client.port())
	var prompt := "把 main.c 主循环里的 Ms_Delay(10) 改成 Ms_Delay(20)。只改这一处，不要动别的。"
	_check("发送消息", _client.send_message(prompt))


func _on_reply(parts: Array, mtime_before: int) -> void:
	print("    收到 %d 个 part" % parts.size())
	var types: PackedStringArray = PackedStringArray()
	var has_text := false
	for p in parts:
		if p is Dictionary:
			types.append(str(p.get("type", "?")))
			if str(p.get("type", "")) == "text":
				has_text = true
	print("    part 类型: %s" % ", ".join(types))
	_check("响应含 text part", has_text)
	# 检查文件是否真被改动
	var mtime_after: int = _tc.main_c_mtime(TC.PROJECT_DST)
	_check("main.c mtime 已变化", mtime_after != mtime_before,
		"before=%d after=%d" % [mtime_before, mtime_after])
	var code: String = _tc.read_main_c(TC.PROJECT_DST)
	_check("main.c 含 Ms_Delay(20)", code.find("Ms_Delay(20)") >= 0)
	# 改完还能编译
	var r = _tc.build_project(TC.PROJECT_DST)
	_check("AI 改动后仍能编译", bool(r["ok"]),
		"exit=%s" % str(r["exit"]))
	for line in str(r["log"]).split("\n", false):
		if "Error(s)" in line:
			print("    %s" % line.strip_edges())
	_finish()


func _finish() -> void:
	if _client:
		_client.stop()
	print("\n=== %s ===" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	quit(0 if _fail == 0 else 1)
