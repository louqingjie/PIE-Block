extends SceneTree

## 端到端验证：在真实 UI 控件里填逐关节连杆长度，确认它一路传到生成的 C 代码。
##
## 之前 UI 已迁移到逐关节 len，但下游仍读 cfg["L1"]，用户填的长度被静默忽略、
## 回退到默认 100mm。已有单元断言覆盖了折算逻辑与 generate()，但没覆盖
## 「UI 控件 -> _collect_ik_config()」这一段，这里补上。
##
## 运行：godot --headless --path . --script scripts/test_ui_ik_e2e.gd

const IK: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/EngineerAdvanced"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
    if ok:
        print("[PASS] %s" % label)
    else:
        print("[FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
        _fail += 1


func _initialize() -> void:
    print("=== UI -> 代码生成 端到端验证 ===")
    var packed := load("res://scenes/ui.tscn") as PackedScene
    if packed == null:
        print("ui.tscn 加载失败")
        quit(1)
        return
    var ui: Node = packed.instantiate()
    root.add_child(ui)
    # --script 模式下 root 尚未进树，须等一帧才会跑 _ready
    await process_frame
    await _test_lengths(ui)
    await _test_joint_rows(ui)
    await _test_axis(ui)
    await _test_diagnosis_reaches_output(ui)
    print("=== 结果: %s ===" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
    ui.free()
    quit(0 if _fail == 0 else 1)


func _set_joint_count(ui: Node, n: int) -> void:
    var btn: Node = ui.get_node(IK + "/ConfigType/OptionButton")
    btn.selected = n - 2
    btn.item_selected.emit(n - 2)


## 设各关节转轴
func _set_axes(ui: Node, axes: Array) -> void:
    # Axis 下拉项序：Pitch=0 / Roll=1 / Yaw=2
    var idx: Dictionary = {"Pitch": 0, "Roll": 1, "Yaw": 2}
    for i in range(axes.size()):
        ui.get_node(IK + "/Joint%d/Axis" % (i + 1)).selected = idx[axes[i]]


## 跑一次静态检查，返回所有消息文本
func _messages(ui: Node) -> Array:
    var issues: Array = []
    ui._check_ik_params(issues)
    var out: Array = []
    for it in issues:
        out.append("[%s] %s" % [str(it.get("type", "")), str(it.get("msg", ""))])
    return out


## 消息里是否包含关键词
func _has_msg(msgs: Array, keyword: String) -> bool:
    for m in msgs:
        if str(m).contains(keyword):
            return true
    return false


## 构形诊断必须真的流到静态检查结果里（再由 _run_check 送进 Output 面板）。
## 诊断模块自己的单元测试再绿，没接进 UI 就等于学生看不到。
func _test_diagnosis_reaches_output(ui: Node) -> void:
    # --- 全 Roll：末端完全动不了，必须报 Error ---
    _set_joint_count(ui, 3)
    await process_frame
    for i in range(3):
        _fill_row(ui, i, "80", i + 4)
    _set_axes(ui, ["Roll", "Roll", "Roll"])
    await process_frame
    var m_roll: Array = _messages(ui)
    _check("全Roll 报末端动不了", _has_msg(m_roll, "末端完全动不了"),
        "\n      " + "\n      ".join(m_roll))
    _check("诊断消息带「机构臂构形」前缀", _has_msg(m_roll, "机械臂构形："),
        "\n      " + "\n      ".join(m_roll))
    # --- 全 Pitch：只能在一个曲面内运动 ---
    _set_axes(ui, ["Pitch", "Pitch", "Pitch"])
    await process_frame
    var m_flat: Array = _messages(ui)
    _check("全Pitch 报只能在曲面内", _has_msg(m_flat, "只能在一个曲面内"),
        "\n      " + "\n      ".join(m_flat))
    # --- 健康 3 关节：不应有构形 Error，但俯仰角不可控 ---
    _set_axes(ui, ["Yaw", "Pitch", "Pitch"])
    await process_frame
    var m3: Array = _messages(ui)
    var has_cfg_err: bool = false
    for s in m3:
        if str(s).begins_with("[Error] 机械臂构形："):
            has_cfg_err = true
    _check("健康3关节 无构形 Error", not has_cfg_err,
        "\n      " + "\n      ".join(m3))
    _check("3关节 俯仰角不可控", ui._ik_pitch_dof == false, str(ui._ik_pitch_dof))
    _check("3关节 给出不可控理由", not str(ui._ik_pitch_reason).is_empty(),
        str(ui._ik_pitch_reason))
    # --- 4 关节 Yaw+3Pitch：俯仰角可控 ---
    _set_joint_count(ui, 4)
    await process_frame
    for i in range(4):
        _fill_row(ui, i, "80", i + 4)
    _set_axes(ui, ["Yaw", "Pitch", "Pitch", "Pitch"])
    await process_frame
    var m4: Array = _messages(ui)
    _check("4关节 俯仰角可控", ui._ik_pitch_dof == true, str(ui._ik_pitch_dof))
    _check("4关节 提示俯仰角可单独调", _has_msg(m4, "俯仰角可以单独调"),
        "\n      " + "\n      ".join(m4))
    # --- 连杆长度全空：只报一条长度错，不重复报诊断那条 ---
    for i in range(4):
        ui.get_node(IK + "/Joint%d/Len" % (i + 1)).text = ""
    await process_frame
    var m_empty: Array = _messages(ui)
    var len_errs: int = 0
    for s in m_empty:
        if str(s).contains("连杆长度未设置") or str(s).contains("连杆长度都是 0"):
            len_errs += 1
    _check("长度全空只报一条", len_errs == 1,
        "共 %d 条\n      %s" % [len_errs, "\n      ".join(m_empty)])
    _check("长度非法时俯仰标志重置", ui._ik_pitch_dof == false,
        str(ui._ik_pitch_dof))


func _fill_row(ui: Node, idx: int, len_mm: String, io_sel: int) -> void:
    var row: String = IK + "/Joint%d" % (idx + 1)
    ui.get_node(row + "/Len").text = len_mm
    ui.get_node(row + "/Min").text = "-90"
    ui.get_node(row + "/Max").text = "90"
    ui.get_node(row + "/Zero").text = "10"
    # IO 逐个错开，避免静态检查报 IO 复用
    ui.get_node(row + "/IO").selected = io_sel


## 4 关节：UI 里填的长度必须一路传到 C 代码
func _test_lengths(ui: Node) -> void:
    _set_joint_count(ui, 4)
    await process_frame
    var lens: Array = ["0", "175", "95", "45"]
    for i in range(4):
        _fill_row(ui, i, lens[i], i + 4)
    await process_frame
    var cfg: Dictionary = ui._collect_ik_config()
    _check("关节数 == 4", int(cfg["joint_count"]) == 4, str(cfg["joint_count"]))
    var joints: Array = cfg["joints"]
    _check("收集到 4 个关节", joints.size() == 4, str(joints.size()))
    var got: Array = []
    for j in joints:
        got.append(str(j.get("len", "")))
    _check("逐关节 len 被收集", got == lens, str(got))
    var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
    var pl: Array = cg.legacy_link_lengths(cfg)
    _check("折算为 [175, 95, 45]", pl == [175.0, 95.0, 45.0], str(pl))
    # 生成的 C 代码必须含这三个值 —— 断链的最终检验
    var code: String = cg.generate(cfg)
    # 连杆长度由 jointLen[] 表提供（L1/L2/L3 宏已随旧解析解删除）。
    # 精确匹配整行而非只查数字：单查 "175" 会命中代码里任何巧合出现的数值。
    var jl: String = "const float jointLen[4] = {0.00f, 175.00f, 95.00f, 45.00f};"
    _check("C 代码 jointLen 表含各段长度", code.contains(jl),
        "未找到该行：" + jl)
    # 反向断言：默认 100 不该出现，否则说明仍在走 fallback
    _check("C 代码不含默认 100 连杆", not code.contains("100.00f, 100.00f"),
        "连杆仍是默认 100，断链未修好")
    # 静态检查不应误报连杆未设置
    var issues: Array = []
    ui._check_ik_params(issues)
    var bogus: String = ""
    for it in issues:
        var m: String = str(it)
        if m.contains("连杆长度未设置") or m.contains("L1 未设置"):
            bogus = m
    _check("静态检查不误报连杆未设置", bogus.is_empty(), bogus)
    # 改一个值，C 代码必须跟着变（证明不是巧合命中默认值）
    ui.get_node(IK + "/Joint2/Len").text = "233"
    await process_frame
    var code2: String = cg.generate(ui._collect_ik_config())
    _check("改 len 后 C 代码跟着变",
        code2.contains("233.00f") and not code2.contains("175.00f"),
        "jointLen 表未跟着改")


## 关节数变化时多余行须隐藏，且已填内容不丢
func _test_joint_rows(ui: Node) -> void:
    _set_joint_count(ui, 6)
    await process_frame
    var vis6: int = 0
    for i in range(6):
        if (ui.get_node(IK + "/Joint%d" % (i + 1)) as Control).visible:
            vis6 += 1
    _check("6 关节时 6 行全可见", vis6 == 6, "可见 %d 行" % vis6)
    _fill_row(ui, 4, "60", 8)
    _fill_row(ui, 5, "35", 9)
    await process_frame
    var cfg6: Dictionary = ui._collect_ik_config()
    _check("6 关节收集 6 项", (cfg6["joints"] as Array).size() == 6,
        str((cfg6["joints"] as Array).size()))
    _set_joint_count(ui, 3)
    await process_frame
    var vis3: int = 0
    for i in range(6):
        if (ui.get_node(IK + "/Joint%d" % (i + 1)) as Control).visible:
            vis3 += 1
    _check("3 关节时只 3 行可见", vis3 == 3, "可见 %d 行" % vis3)
    var cfg3: Dictionary = ui._collect_ik_config()
    _check("3 关节只收集 3 项", (cfg3["joints"] as Array).size() == 3,
        str((cfg3["joints"] as Array).size()))
    # 隐藏行内容不应被清掉（用户切回来还在）
    _check("隐藏行内容保留", ui.get_node(IK + "/Joint5/Len").text == "60",
        ui.get_node(IK + "/Joint5/Len").text)


## 转轴类型能收集，且默认值符合历史构型
func _test_axis(ui: Node) -> void:
    _set_joint_count(ui, 4)
    await process_frame
    var cfg: Dictionary = ui._collect_ik_config()
    var axes: Array = []
    for j in cfg["joints"]:
        axes.append(str(j.get("axis", "")))
    _check("默认转轴 = [Yaw, Pitch, Pitch, Pitch]",
        axes == ["Yaw", "Pitch", "Pitch", "Pitch"], str(axes))
    ui.get_node(IK + "/Joint4/Axis").selected = 1
    await process_frame
    var cfg2: Dictionary = ui._collect_ik_config()
    var j4: Dictionary = (cfg2["joints"] as Array)[3]
    _check("改转轴能被收集", str(j4.get("axis", "")) == "Roll", str(j4.get("axis", "")))
    # fk_chain 与诊断都要能吃下 UI 收集的构形
    var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
    var chain: Dictionary = cg.fk_chain([10.0, 10.0, 10.0, 10.0],
        cfg2["joints"], 4, 2, 0.0, 0.0, 0.0)
    var pts: Array = chain["points"]
    _check("fk_chain 接受该构形", pts.size() == 5, str(pts.size()))
    var tip: Vector3 = pts[4]
    _check("末端位置有效",
        is_finite(tip.x) and is_finite(tip.y) and is_finite(tip.z) and tip.length() > 1.0,
        str(tip))
    var diag = preload("res://scripts/arm_diagnosis.gd").new()
    var res: Dictionary = diag.analyze(cfg2["joints"], 4, 2, 0.0, 0.0, 0.0)
    _check("诊断接受该构形", int(res["dof"]) >= 1, str(res["dof"]))