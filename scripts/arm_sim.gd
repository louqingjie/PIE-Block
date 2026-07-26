extends Control
## 机械臂逆解 3D 仿真视图。
##
## 全部运动学都走 CodeGenEngineerIK 里的公开函数（joint_frames /
## forward_kinematics_angles / solve_ik_checked / clamp_angles_to_limits），
## 不在本文件重推公式，避免仿真与生成的 C 代码脱节。
##
## 坐标系约定（机器人坐标 -> Godot 坐标）：
##   - 2 轴构型：(x, y) 是竖直平面，y 是高度   -> Godot (x, y, 0)
##   - 3/4 轴构型：(x, y) 是水平面，z 是高度   -> Godot (x, z, -y)
## 单位：机器人侧 mm，Godot 侧 mm * MM_TO_UNIT。

# ------------------------------------------------------------------ 节点路径
const P_VIEWPORT: NodePath = "Sim/SubViewport"
const P_WORLD: NodePath = "Sim/SubViewport/World"
const P_CAMERA: NodePath = "Sim/SubViewport/World/Camera3D"
const P_GRID: NodePath = "Sim/SubViewport/World/Grid"
const P_AXES: NodePath = "Sim/SubViewport/World/Axes"
const P_ARM_ROOT: NodePath = "Sim/SubViewport/World/ArmRoot"
const P_TRAIL: NodePath = "Sim/SubViewport/World/Trail"
const P_GHOST: NodePath = "Sim/SubViewport/World/TargetGhost"
const P_PARAMS: NodePath = "SidePanel/Scroll/Params"
const P_STATUS: NodePath = "StatusPanel/Status"
const P_MODE: NodePath = "TopPanel/HBox/Mode"
const P_BACK: NodePath = "TopPanel/HBox/Back"
const P_CHASSIS: NodePath = "Sim/SubViewport/World/Chassis"
const P_GRIPPER: NodePath = "Sim/SubViewport/World/Gripper"
const P_CHASSIS_TOGGLE: NodePath = "TopPanel/HBox/ChassisToggle"
const P_TRAIL_TOGGLE: NodePath = "TopPanel/HBox/TrailToggle"
const P_TRAIL_CLEAR: NodePath = "TopPanel/HBox/TrailClear"
const P_RESET_VIEW: NodePath = "TopPanel/HBox/ResetView"
const P_CONFIG_LABEL: NodePath = "TopPanel/HBox/ConfigLabel"
const P_HINT: NodePath = "HintLabel"

# ------------------------------------------------------------------ 常量
## mm -> Godot 单位。臂长通常 100~300mm，缩到 1~3 单位便于相机取景
const MM_TO_UNIT: float = 0.01
## 连杆圆柱半径（mm）
const LINK_RADIUS_MM: float = 7.0
## 关节球半径（mm）
const JOINT_RADIUS_MM: float = 11.0
## 末端球半径（mm），比关节球大一点以便辨认
const TIP_RADIUS_MM: float = 14.0
## 轨迹点数上限（环形缓冲）
const TRAIL_MAX_POINTS: int = 300
## 相机俯仰角限制（弧度），避免翻越极点
const CAM_PITCH_LIMIT: float = 1.45
## 模拟手柄的固定步进周期（ms），与生成的 C 主循环 LOOP_PERIOD_MS 一致
const SIM_STEP_MS: float = 10.0
## 摇杆满偏值（与 C 端 valueOfRoker 量程一致）
const ROKER_FULL: float = 2047.0
## 底盘默认尺寸（mm）。本车是两轮车（两轮同轴装在底盘中间），
## 故前后尺寸是「底盘板长度」而不是轴距。
const CHASSIS_DECK_LEN_MM: float = 300.0
const CHASSIS_TRACK_MM: float = 260.0
const CHASSIS_DECK_MM: float = 90.0
## 轮子与底盘板的默认垂直间隙（mm）
const WHEEL_GAP_MM: float = 26.0
## 默认底盘高度（mm）：地面到底盘板顶面的距离。
## = 轮径 + 悬挂间隙 + 板厚，与下面三个常量保持一致
const CHASSIS_HEIGHT_MM: float = 50.0 + 26.0 + 16.0
## 轮轴直径（mm），把两轮与底盘连起来
const AXLE_DIA_MM: float = 14.0
## 夹爪尺寸（mm）：掌座长度、指长、指厚、最大张开半距。
## 比真机夹爪略大，因为它的作用是把末端朝向看清，太小就失去意义。
const GRIP_PALM_MM: float = 26.0
const GRIP_FINGER_MM: float = 48.0
const GRIP_THICK_MM: float = 10.0
const GRIP_OPEN_MM: float = 30.0
## 底盘板厚度（mm），真机是一块薄板，画厚了会挡住机械臂
const CHASSIS_DECK_THICK_MM: float = 16.0
## 车轮尺寸（mm）：直径固定 50，不随车高变。
## 改车高时只动悬挂间隙，轮子本身尺寸不变。
const WHEEL_RADIUS_MM: float = 25.0
const WHEEL_WIDTH_MM: float = 30.0
## 逆解模式键盘移动默认速度（mm/s）
const KEY_MOVE_MM_PER_SEC: float = 120.0
## 逆解模式键盘调姿态角默认速度（°/s）
const KEY_ROT_DEG_PER_SEC: float = 60.0
## 手柄按键 -> 仿真里代替它的键盘按键。
## 手柄的 A/B/C/D 故意不映射到同名字母键，否则会和摇杆的 WASD 撞车。
const HANDLE_KEY_TO_KEYBOARD: Dictionary = {
	"↑": KEY_UP, "↓": KEY_DOWN, "←": KEY_LEFT, "→": KEY_RIGHT, "->": KEY_RIGHT,
	"A": KEY_1, "B": KEY_2, "C": KEY_3, "D": KEY_4, "R": KEY_R,
}
## 模式枚举
enum Mode {IK = 0, FK = 1, PRESET = 2, CONTROLLER = 3}

# ------------------------------------------------------------------ 运动学求解器
var _cg: CodeGenEngineerIK = CodeGenEngineerIK.new()

# ------------------------------------------------------------------ 配置状态
var _cfg: Dictionary = {}
var _config_type: int = 0
var _jc: int = 2
var _l1: float = 100.0
var _l2: float = 100.0
var _l3: float = 0.0
var _elbow: float = 1.0
var _joints: Array = []
var _presets: Array = []

# ------------------------------------------------------------------ 运行状态
var _mode: int = Mode.IK
## 末端目标 [x, y, z, phi]（机器人坐标 mm / 度）
var _target: Array = [0.0, 0.0, 0.0, 0.0]
## 当前各关节角度（度），已过限位
var _angles: Array = []
## 上一帧逆解是否可达（模拟手柄模式的回退逻辑需要）
var _reachable: bool = true
## 被限位钳住的关节掩码
var _clamped: Array = []
## FK 模式下由滑块直接给出的关节角
var _fk_angles: Array = [0.0, 0.0, 0.0, 0.0]
## 逆解模式键盘移动速度（mm/s 与 °/s）
var _ik_move_speed: float = KEY_MOVE_MM_PER_SEC
var _ik_rot_speed: float = KEY_ROT_DEG_PER_SEC
## 模拟手柄：右摇杆归一化值 [-1, 1]，由键盘推出
var _joy: Vector2 = Vector2.ZERO
## 模拟手柄：本周期被按住的手柄按键（"轴:方向" -> true）
var _keys_down: Dictionary = {}
## 模拟手柄的时间累加器（把不定 delta 切成固定 10ms 步）
var _sim_accum: float = 0.0
## 预设点位巡航：>=0 表示正在播放第 N 个点位
var _play_idx: int = -1
var _play_t: float = 0.0
var _play_from: Array = []

# ------------------------------------------------------------------ 视图状态
var _cam_yaw: float = -0.7
var _cam_pitch: float = 0.5
var _cam_dist: float = 5.0
var _cam_pivot: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var _panning: bool = false

# ------------------------------------------------------------------ 场景对象
var _link_nodes: Array = [] # MeshInstance3D，每段连杆
var _joint_nodes: Array = [] # MeshInstance3D，每个关节球
var _tip_node: MeshInstance3D = null
var _trail_points: Array = [] # Vector3（Godot 坐标）
var _trail_enabled: bool = true
var _chassis_visible: bool = true
## 夹爪张开度 [0, 1]（1=张最大）。纯可视化，不进逆解。
var _grip_open: float = 0.6
## 夹爪各构件（掌座 + 两指）
var _grip_nodes: Array = []

# 底盘尺寸与机械臂安装位置（mm，机器人坐标）。
# 底盘只是视觉参照，不参与逆解；它的作用是看清机械臂装在车上哪里。
var _chassis_deck_len: float = CHASSIS_DECK_LEN_MM
var _chassis_track: float = CHASSIS_TRACK_MM
## 底盘高度：地面到底盘板顶面的距离（mm）。
## 轮径固定为 WHEEL_RADIUS_MM，改车高只影响悬挂间隙，见 _wheel_gap()。
var _chassis_height: float = CHASSIS_HEIGHT_MM
var _chassis_deck: float = CHASSIS_DECK_MM
## 机械臂底座相对底盘中心的偏移 [前后, 左右, 高度]
var _mount: Vector3 = Vector3(0.0, 0.0, CHASSIS_DECK_MM)

# 材质（在 _ready 里建好复用，避免每帧新建）
var _mat_link: StandardMaterial3D = null
var _mat_link_bad: StandardMaterial3D = null
var _mat_joint: StandardMaterial3D = null
var _mat_joint_clamped: StandardMaterial3D = null
var _mat_tip: StandardMaterial3D = null
var _mat_ghost: StandardMaterial3D = null
var _mat_deck: StandardMaterial3D = null
var _mat_wheel: StandardMaterial3D = null
var _mat_mount: StandardMaterial3D = null
var _mat_grip: StandardMaterial3D = null

# 参数面板控件（按模式重建）
var _sliders: Dictionary = {} # key -> HSlider
var _spins: Dictionary = {} # key -> SpinBox
var _syncing: bool = false # 滑块 <-> 数值框互相赋值时抑制回环


# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	_build_materials()
	_connect_ui()
	# set_config 可能在 _ready 之前被调用（外部先 instantiate 再赋配置），
	# 那时 _cfg 已有内容，直接沿用；否则用一份可跑的默认配置
	if _cfg.is_empty():
		set_config({})
	else:
		_apply_config()


func _connect_ui() -> void:
	var back: Node = get_node_or_null(P_BACK)
	if back is BaseButton:
		back.pressed.connect(_on_back_pressed)
	var mode: Node = get_node_or_null(P_MODE)
	if mode is OptionButton:
		mode.item_selected.connect(_on_mode_selected)
	var tt: Node = get_node_or_null(P_TRAIL_TOGGLE)
	if tt is BaseButton:
		tt.toggled.connect(_on_trail_toggled)
	var ct: Node = get_node_or_null(P_CHASSIS_TOGGLE)
	if ct is BaseButton:
		ct.toggled.connect(_on_chassis_toggled)
	var tc: Node = get_node_or_null(P_TRAIL_CLEAR)
	if tc is BaseButton:
		tc.pressed.connect(_clear_trail)
	var rv: Node = get_node_or_null(P_RESET_VIEW)
	if rv is BaseButton:
		rv.pressed.connect(_reset_view)


# ------------------------------------------------------------------ 外部接口
## 由 ui.gd 传入 _collect_ik_config() 的结果
func set_config(cfg: Dictionary) -> void:
	_cfg = cfg.duplicate(true)
	if is_inside_tree():
		_apply_config()


## 返回配置界面时发出（由 ui.gd 连接）
signal closed
## 在仿真里改了臂长/中位朝向/初始角/预设点位时发出，携带完整 cfg 供 ui.gd 回填
signal config_changed(cfg: Dictionary)


func _on_back_pressed() -> void:
	closed.emit()


## 把仿真里的编辑结果同步回 _cfg 并通知 ui.gd。
## 只写用户能在这里改的字段，IO/方向/摇杆映射等仍归配置界面管。
func _emit_config_changed() -> void:
	_cfg["L1"] = "%.2f" % _l1
	_cfg["L2"] = "%.2f" % _l2
	_cfg["L3"] = "%.2f" % _l3
	_cfg["joints"] = _joints.duplicate(true)
	_cfg["presets"] = _presets.duplicate(true)
	config_changed.emit(_cfg.duplicate(true))


# ------------------------------------------------------------------ 配置解析
func _apply_config() -> void:
	_config_type = int(_cfg.get("config_type", 0))
	_jc = int(_cfg.get("joint_count", _jc_from_type(_config_type)))
	_l1 = _cfg_float("L1", 100.0)
	_l2 = _cfg_float("L2", 100.0)
	_l3 = _cfg_float("L3", 0.0)
	# 连杆长度必须为正，否则余弦定理除零
	if _l1 <= 0.0:
		_l1 = 100.0
	if _l2 <= 0.0:
		_l2 = 100.0
	if _l3 < 0.0:
		_l3 = 0.0
	_joints = _cfg.get("joints", [])
	if _joints.is_empty():
		# 无配置时造一份中位关节，保证界面可用
		_joints = []
		for i in range(_jc):
			_joints.append({"offset": "0", "zero": "0", "min": "-90", "max": "90"})
	# 关节数不足时补齐，避免标定时索引越界
	while _joints.size() < _jc:
		_joints.append({"offset": "0", "zero": "0", "min": "-90", "max": "90"})
	_presets = _cfg.get("presets", [])
	# 预设点位表补齐到 4 项，便于「存为预设 N」直接写入
	while _presets.size() < 4:
		_presets.append({"key": "A", "x": "", "y": "", "z": "", "phi": "", "enabled": false})
	_elbow = _cg._elbow_sign(_joints, _config_type)
	# 初始姿态：与生成的 C 代码上电起点一致
	_fk_angles = _cg._joint_home_angles(_joints)
	var home: Array = _cg.forward_kinematics_angles(_fk_angles, _l1, _l2, _l3, _config_type)
	_target = [home[0], home[1], home[2], home[3]]
	_clear_trail()
	_rebuild_arm()
	_rebuild_static_geometry()
	_rebuild_params()
	_reset_view()
	_update_config_label()
	_update_hint()
	_recompute()


func _cfg_float(key: String, default_val: float) -> float:
	var s: String = str(_cfg.get(key, ""))
	s = s.strip_edges()
	if s.is_valid_float():
		return s.to_float()
	return default_val


func _jc_from_type(t: int) -> int:
	match t:
		0: return 2
		1: return 3
		2: return 4
	return 2


func _update_config_label() -> void:
	var label: Node = get_node_or_null(P_CONFIG_LABEL)
	if label is Label:
		var names: Array = ["2轴平面", "3轴", "4轴"]
		var n: String = names[_config_type] if _config_type < names.size() else "未知"
		var txt: String = "构型 %s ｜ L1=%.0f L2=%.0f" % [n, _l1, _l2]
		if _jc >= 4:
			txt += " L3=%.0f" % _l3
		label.text = txt + " (mm)"


# ------------------------------------------------------------------ 坐标映射
## 机器人坐标 (mm) -> Godot 坐标（已缩放）
## 2 轴：XY 竖直平面 -> Godot XY；3/4 轴：XY 水平面 + Z 高度 -> Godot (x, z, -y)
func _robot_to_godot(x: float, y: float, z: float) -> Vector3:
	if _config_type == 0:
		return Vector3(x, y, 0.0) * MM_TO_UNIT
	return Vector3(x, z, -y) * MM_TO_UNIT


func _vec_to_godot(v: Vector3) -> Vector3:
	return _robot_to_godot(v.x, v.y, v.z)


# ------------------------------------------------------------------ 材质
func _build_materials() -> void:
	_mat_link = _make_material(Color(0.42, 0.55, 0.72), 0.35, 0.45)
	_mat_link_bad = _make_material(Color(0.85, 0.24, 0.24), 0.3, 0.5)
	_mat_joint = _make_material(Color(0.83, 0.85, 0.88), 0.15, 0.7)
	_mat_joint_clamped = _make_material(Color(0.95, 0.6, 0.15), 0.2, 0.6)
	_mat_tip = _make_material(Color(0.35, 0.82, 0.55), 0.2, 0.6)
	_mat_ghost = _make_material(Color(0.95, 0.85, 0.35, 0.35), 0.4, 0.3)
	_mat_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 底盘用低饱和色，避免抢机械臂的视觉重点
	_mat_deck = _make_material(Color(0.28, 0.32, 0.38), 0.6, 0.2)
	_mat_wheel = _make_material(Color(0.13, 0.14, 0.16), 0.85, 0.05)
	_mat_mount = _make_material(Color(0.55, 0.48, 0.30), 0.5, 0.35)
	# 夹爪用比末端球更亮的绿，一眼能认出这是"手"
	_mat_grip = _make_material(Color(0.30, 0.72, 0.48), 0.3, 0.5)


func _make_material(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# ------------------------------------------------------------------ 机械臂几何（程序化）
## 按 L1/L2/L3 与构型重建连杆与关节，参数改变即重新生成
func _rebuild_arm() -> void:
	var root: Node3D = get_node_or_null(P_ARM_ROOT)
	if root == null:
		return
	# 立即移除而非 queue_free：拖臂长滑块时一帧内会重建多次，
	# 延迟释放会让旧连杆堆积，_link_nodes 也会指向已失效的节点
	for c in root.get_children():
		root.remove_child(c)
		c.free()
	_link_nodes.clear()
	_joint_nodes.clear()
	# 段数：2/3 轴 = 2 段（大臂 + 小臂），4 轴 = 3 段（再加腕部）
	var seg_count: int = 3 if _config_type >= 2 else 2
	for i in range(seg_count):
		var link: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = LINK_RADIUS_MM * MM_TO_UNIT
		cyl.bottom_radius = LINK_RADIUS_MM * MM_TO_UNIT
		cyl.height = 1.0 # 每帧按实际段长缩放
		cyl.radial_segments = 16
		cyl.rings = 1
		link.mesh = cyl
		link.material_override = _mat_link
		root.add_child(link)
		_link_nodes.append(link)
	# 关节球：段数 + 1 个点，最后一个是末端（单独用 _tip_node）
	for i in range(seg_count):
		var j: MeshInstance3D = MeshInstance3D.new()
		var sph: SphereMesh = SphereMesh.new()
		sph.radius = JOINT_RADIUS_MM * MM_TO_UNIT
		sph.height = JOINT_RADIUS_MM * 2.0 * MM_TO_UNIT
		sph.radial_segments = 20
		sph.rings = 10
		j.mesh = sph
		j.material_override = _mat_joint
		root.add_child(j)
		_joint_nodes.append(j)
	# 末端球（可拖拽）
	_tip_node = MeshInstance3D.new()
	var tip_mesh: SphereMesh = SphereMesh.new()
	tip_mesh.radius = TIP_RADIUS_MM * MM_TO_UNIT
	tip_mesh.height = TIP_RADIUS_MM * 2.0 * MM_TO_UNIT
	tip_mesh.radial_segments = 20
	tip_mesh.rings = 10
	_tip_node.mesh = tip_mesh
	_tip_node.material_override = _mat_tip
	root.add_child(_tip_node)
	# 目标幽灵球：钳位时与实际末端分离，直观显示误差
	var ghost: MeshInstance3D = get_node_or_null(P_GHOST)
	if ghost is MeshInstance3D:
		var gm: SphereMesh = SphereMesh.new()
		gm.radius = TIP_RADIUS_MM * 1.15 * MM_TO_UNIT
		gm.height = TIP_RADIUS_MM * 2.3 * MM_TO_UNIT
		gm.radial_segments = 16
		gm.rings = 8
		ghost.mesh = gm
		ghost.material_override = _mat_ghost
	_rebuild_gripper()


# ------------------------------------------------------------------ 夹爪
## 夹爪 = 掌座 + 两根手指。它的朝向就是末端姿态角的可视化：
## 掌座沿末端连杆方向伸出，两指在臂的工作平面内对开。
## 纯可视化，不参与逆解（真机的夹爪开合另有舵机，不在本构型的关节里）。
func _rebuild_gripper() -> void:
	var root: Node3D = get_node_or_null(P_GRIPPER)
	if root == null:
		return
	# 与 _rebuild_arm 同理：立即释放，避免同帧多次重建时堆积
	for c in root.get_children():
		root.remove_child(c)
		c.free()
	_grip_nodes.clear()
	# 掌座（沿 approach 方向的短方块）+ 两根手指
	var palm: MeshInstance3D = MeshInstance3D.new()
	var pb: BoxMesh = BoxMesh.new()
	pb.size = Vector3(GRIP_PALM_MM, GRIP_OPEN_MM * 2.0, GRIP_THICK_MM) * MM_TO_UNIT
	palm.mesh = pb
	palm.material_override = _mat_grip
	root.add_child(palm)
	_grip_nodes.append(palm)
	for _i in range(2):
		var finger: MeshInstance3D = MeshInstance3D.new()
		var fb: BoxMesh = BoxMesh.new()
		fb.size = Vector3(GRIP_FINGER_MM, GRIP_THICK_MM, GRIP_THICK_MM) * MM_TO_UNIT
		finger.mesh = fb
		finger.material_override = _mat_grip
		root.add_child(finger)
		_grip_nodes.append(finger)


## 按当前姿态摆放夹爪。pts 是 _render_arm already 算好的关节点链（Godot 坐标）。
func _render_gripper(pts: Array) -> void:
	if _grip_nodes.size() < 3 or pts.size() < 2:
		return
	var tip: Vector3 = pts[pts.size() - 1]
	var prev: Vector3 = pts[pts.size() - 2]
	var seg: Vector3 = tip - prev
	# approach = 末端朝向。正常取末段连杆方向；末段长度为 0 时
	# （4 轴 L3 留空即 L3=0，腕心与末端重合）改由关节角直接算，
	# 否则夹爪会整个消失——姿态角本身是有定义的，不该因 L3=0 就不画。
	var approach: Vector3 = seg.normalized() if seg.length() > 1e-6 \
		else _approach_from_angles()
	if approach.length() < 1e-6:
		# 兜底：连关节角都算不出方向时才隐藏
		for n in _grip_nodes:
			n.visible = false
		return
	var normal: Vector3 = _arm_plane_normal()
	var open_dir: Vector3 = normal.cross(approach)
	if open_dir.length() < 1e-6:
		# approach 与平面法向平行（理论上不该发生），换个参考轴兜底
		open_dir = approach.cross(Vector3.UP)
		if open_dir.length() < 1e-6:
			open_dir = approach.cross(Vector3.RIGHT)
	open_dir = open_dir.normalized()
	# 重算 normal 保证三轴严格正交（approach 与原 normal 可能有微小非正交）
	var n2: Vector3 = approach.cross(open_dir).normalized()
	var basis: Basis = Basis(approach, open_dir, n2)
	var bad: bool = not _reachable
	var mat: StandardMaterial3D = _mat_link_bad if bad else _mat_grip
	# 掌座：紧贴末端球外侧
	var palm_center: Vector3 = tip + approach * (GRIP_PALM_MM * 0.5 * MM_TO_UNIT)
	_grip_nodes[0].visible = true
	_grip_nodes[0].material_override = mat
	_grip_nodes[0].transform = Transform3D(basis, palm_center)
	# 两指：从掌座外沿伸出，间距随张开度变化
	var half_span: float = lerpf(GRIP_THICK_MM * 0.6, GRIP_OPEN_MM, clampf(_grip_open, 0.0, 1.0))
	var finger_center_x: float = (GRIP_PALM_MM + GRIP_FINGER_MM * 0.5) * MM_TO_UNIT
	for k in range(2):
		var side: float = 1.0 if k == 0 else -1.0
		var node: MeshInstance3D = _grip_nodes[k + 1]
		node.visible = true
		node.material_override = mat
		node.transform = Transform3D(basis, tip
			+ approach * finger_center_x
			+ open_dir * (side * half_span * MM_TO_UNIT))


## 由关节角直接算末端朝向（Godot 坐标，单位向量）。
## 用于末段连杆长度为 0 的情形：此时点链最后两点重合，减不出方向，
## 但姿态角依然明确 —— 它就是工作平面内各关节角之和。
func _approach_from_angles() -> Vector3:
	if _config_type == 0:
		# 2 轴：工作平面即 Godot XY，朝向角 = θ1 + θ2
		var a: float = deg_to_rad(_sum_planar_angles())
		return Vector3(cos(a), sin(a), 0.0)
	# 3/4 轴：先在 (r, z) 平面内算朝向，再绕底座转 θ1
	var phi: float = deg_to_rad(_sum_planar_angles())
	var t0: float = deg_to_rad(_angles[0] if _angles.size() > 0 else 0.0)
	# (r, z) 分量 -> 机器人坐标 -> Godot 坐标
	var r_comp: float = cos(phi)
	var z_comp: float = sin(phi)
	return _robot_to_godot(r_comp * cos(t0), r_comp * sin(t0), z_comp).normalized()


## 工作平面内各关节角之和（度）。2 轴是 θ1+θ2；3/4 轴跳过底座关节，取其余之和。
func _sum_planar_angles() -> float:
	var s: float = 0.0
	var start: int = 0 if _config_type == 0 else 1
	for i in range(start, _angles.size()):
		s += float(_angles[i])
	return s


## 臂所在工作平面的法向（Godot 坐标，单位向量）。
## 2 轴：臂在 Godot XY 平面内，法向是 Z。
## 3/4 轴：臂在过底座的竖直平面内，法向 = 该平面的水平法线（随底座转角 θ1 变）。
func _arm_plane_normal() -> Vector3:
	if _config_type == 0:
		return Vector3(0.0, 0.0, 1.0)
	var t0: float = deg_to_rad(_angles[0] if _angles.size() > 0 else 0.0)
	# 机器人水平径向方向经 _robot_to_godot 映射后的单位向量
	var radial: Vector3 = _robot_to_godot(cos(t0), sin(t0), 0.0).normalized()
	var n: Vector3 = radial.cross(Vector3.UP)
	if n.length() < 1e-6:
		return Vector3(0.0, 0.0, 1.0)
	return n.normalized()


# ------------------------------------------------------------------ 静态辅助几何
## 网格地面 + 坐标轴 + 底盘。2 轴构型的"地面"是竖直工作平面，故网格朝向随构型变
func _rebuild_static_geometry() -> void:
	_build_grid()
	_build_axes()
	_build_chassis()


# ------------------------------------------------------------------ 底盘（视觉参照）
## 画一块底盘板 + 两个同轴轮（摩托车式，轮子在底盘前后中点）+ 连接轮轴。
## 底盘不参与任何运算：逆解的原点永远是机械臂底座，
## 所以底盘整体按 -_mount 平移，使底座落在正确的车上位置。
func _build_chassis() -> void:
	var root: Node3D = get_node_or_null(P_CHASSIS)
	if root == null:
		return
	# 必须立即移除：queue_free 要等到帧末，同一帧内多次重建（拖滑块时很常见）
	# 会让旧底盘持续堆积
	for c in root.get_children():
		root.remove_child(c)
		c.free()
	root.visible = _chassis_visible
	if not _chassis_visible:
		return
	var half_len: float = _chassis_deck_len * 0.5
	var half_tr: float = _chassis_track * 0.5
	var wheel_r: float = WHEEL_RADIUS_MM
	# 高度基准：底盘板顶面在机械臂底座下方 _mount.z 处（_chassis_point 已处理）
	# 轮心：从地面往上一个轮半径。地面在板顶面下方 _chassis_height 处，
	# 故轮心局部高度 = -(车高 - 轮半径)。这样车高降到贴地时轮子也跟着沉，
	# 而不是固定挂在板下某个深度、把自己埋到地面以下。
	var axle_up: float = -(_chassis_height - wheel_r)
	# 前后两根轮轴的位置：让轮子外缘刚好落在板的前后范围内
	var half_wb: float = maxf(half_len - wheel_r, half_len * 0.25)
	# 底盘板：左右比轮距窄一些，让四个轮子明确外露。
	# 否则轮子几乎完全藏在板下，俯视时看不出有几个
	var deck_w: float = maxf(_chassis_track - WHEEL_WIDTH_MM * 2.0, 20.0)
	var deck: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = _chassis_box_size(deck_w, CHASSIS_DECK_THICK_MM, _chassis_deck_len)
	deck.mesh = box
	deck.material_override = _mat_deck
	deck.position = _chassis_point(0.0, 0.0, -CHASSIS_DECK_THICK_MM * 0.5)
	root.add_child(deck)
	# 四个轮子：前后各一对，左右对称
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cyl: CylinderMesh = CylinderMesh.new()
			cyl.top_radius = wheel_r * MM_TO_UNIT
			cyl.bottom_radius = wheel_r * MM_TO_UNIT
			cyl.height = WHEEL_WIDTH_MM * MM_TO_UNIT
			cyl.radial_segments = 20
			cyl.rings = 1
			wheel.mesh = cyl
			wheel.material_override = _mat_wheel
			# CylinderMesh 默认沿 +Y，需把它转到机器人左右轴方向。
			# 轮心 = 板半宽 + 半个轮宽，使轮子内侧面与板侧面**重合无缝**。
			# 注意 deck_w 必须与这里同源，否则板和轮之间会出现横向空隙。
			wheel.transform = Transform3D(_wheel_basis(), _chassis_point(
				sx * half_wb, sy * (deck_w * 0.5 + WHEEL_WIDTH_MM * 0.5), axle_up))
			root.add_child(wheel)
	# 注：不画横贯左右的轮轴。底盘只是示意，轮子怎么连到车上无需深究，
	# 而那两根长杆比底盘板本身还抢眼，反而干扰对机械臂的观察。
	# 支臂：只在有悬挂间隙时才画（间隙为 0 说明轮子已贴着板底，无需连接件）。
	# 长度 = 悬挂间隙 + 一个轮半径，即从板底面一直伸到轮心（而非只到轮顶）。
	# 左右位置必须落在**板内**（贴着板侧边缘），不能取轮子的位置——
	# 板宽比轮距窄，那样支臂会悬在板外并穿透板面（踩过）。
	var strut_h: float = _wheel_gap() + wheel_r
	var strut_side: float = maxf(deck_w * 0.5 - AXLE_DIA_MM * 0.5, 0.0)
	# 判据用间隙而非支臂总长：支臂含轮半径，贴地时总长仍有一个轮半径，
	# 但那时轮子已顶着板底，不需要连接件
	if _wheel_gap() > 0.5:
		for sx in [1.0, -1.0]:
			for sy in [1.0, -1.0]:
				var strut: MeshInstance3D = MeshInstance3D.new()
				var sbox: BoxMesh = BoxMesh.new()
				sbox.size = _chassis_box_size(AXLE_DIA_MM, strut_h, AXLE_DIA_MM)
				strut.mesh = sbox
				strut.material_override = _mat_mount
				strut.position = _chassis_point(sx * half_wb, sy * strut_side,
					-CHASSIS_DECK_THICK_MM - strut_h * 0.5)
				root.add_child(strut)
	# 安装座：从底盘板顶面接到机械臂底座，让"装在哪、垫多高"一眼可见
	if _mount.z > 1.0:
		var post: MeshInstance3D = MeshInstance3D.new()
		var pbox: BoxMesh = BoxMesh.new()
		var side: float = maxf(wheel_r * 0.5, 6.0)
		pbox.size = _chassis_box_size(side, _mount.z, side)
		post.mesh = pbox
		post.material_override = _mat_mount
		# 柱子从板顶面(局部 up=0)向上接到底座(局部 up=_mount.z)，柱心取中点。
		# 注意用底座所在的前后/左右位置（局部坐标即 _mount.x/_mount.y）
		post.position = _chassis_point(_mount.x, _mount.y, _mount.z * 0.5)
		root.add_child(post)
	# 车头指示：底盘前沿一个三角，避免前后装反看不出来
	var nose: MeshInstance3D = MeshInstance3D.new()
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var tipx: float = half_len + wheel_r * 0.9
	# 画在板顶面上方一点，避免与板面共面产生 z-fighting
	var nose_up: float = 2.0
	for p in [Vector2(half_len, half_tr * 0.55), Vector2(tipx, 0.0),
			Vector2(half_len, -half_tr * 0.55)]:
		im.surface_set_color(Color(0.95, 0.72, 0.28, 0.95))
		im.surface_add_vertex(_chassis_point(p.x, p.y, nose_up))
	im.surface_end()
	nose.mesh = im
	root.add_child(nose)


## 底盘局部坐标 (前后, 左右, 板顶面为 0 的高度) -> Godot 坐标。
## 已含 -_mount 全部三个分量的平移：机械臂底座在机器人原点，
## 底盘中心在它后方 _mount.x、侧方 _mount.y、下方 _mount.z 处。
func _chassis_point(fwd: float, side: float, up: float) -> Vector3:
	if _config_type == 0:
		# 2 轴构型里机械臂的工作平面是 Godot XY，高度轴是 Y。
		# 但底盘仍然是个三维物体：左右方向直接用 Godot Z，
		# 否则四个轮子会全叠在一起（踩过：看起来只剩一个轮）。
		return Vector3(fwd - _mount.x, up - _mount.z, -(side - _mount.y)) * MM_TO_UNIT
	return _robot_to_godot(fwd - _mount.x, side - _mount.y, up - _mount.z)


## BoxMesh 尺寸：把「左右/高/前后」换算到 Godot 轴。
## 两种构型下底盘都是 (x=前后, y=高, z=左右)，故无需分支。
func _chassis_box_size(side: float, up: float, fwd: float) -> Vector3:
	return Vector3(fwd, up, side) * MM_TO_UNIT


## 轮子朝向：把 CylinderMesh 的 +Y 轴转到机器人左右轴。
## 两种构型下机器人左右轴在 Godot 里都是 Z 方向，故朝向一致。
func _wheel_basis() -> Basis:
	return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.UP)


func _build_grid() -> void:
	var grid: MeshInstance3D = get_node_or_null(P_GRID)
	if not grid is MeshInstance3D:
		return
	# 网格要盖住臂的可达范围与整个车身，并向外多留一圈，
	# 否则地面只在车身边缘露出一角，看不出是地面
	var span: float = _l1 + _l2 + _l3
	if _chassis_visible:
		span = maxf(span, maxf(
			_chassis_deck_len * 0.5,
			_chassis_track * 0.5 + WHEEL_WIDTH_MM) * 1.6)
	# 步长对齐到 10mm 的整数倍，读数更好认
	var half: int = 5
	var step_mm: float = max(10.0, round(span / float(half) / 10.0) * 10.0)
	var lim: float = float(half) * step_mm
	# 网格代表地面，显示底盘时下移到轮下沿，否则会横穿车身
	var plane: float = _ground_level()
	# 网格中心跟着车走：臂装在偏离底盘中心处时，以底座为中心画会看着歪
	var cx: float = 0.0
	var cy: float = 0.0
	if _chassis_visible:
		cx = -_mount.x
		cy = -_mount.y
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var minor: Color = Color(1, 1, 1, 0.12)
	for i in range(-half, half + 1):
		var t: float = float(i) * step_mm
		# 统一铺在水平地面上（用 _grid_point 而非 _robot_to_godot，
		# 后者在 2 轴构型会把左右分量丢掉）
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(cx + t, cy - lim, plane))
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(cx + t, cy + lim, plane))
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(cx - lim, cy + t, plane))
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(cx + lim, cy + t, plane))
	im.surface_end()
	grid.mesh = im


## 悬挂间隙（mm）：车高扣掉固定轮径与板厚后剩下的那段。
## 车高 >= 轮径+板厚 时有悬挂；更低时间隙为 0（支臂消失），
## 轮子跟着板一起下沉，一直可以降到板贴地。
func _wheel_gap() -> float:
	return maxf(_chassis_height - CHASSIS_DECK_THICK_MM - WHEEL_RADIUS_MM * 2.0, 0.0)


## 地面网格顶点：(前后, 左右, 高度) -> Godot 坐标。
## 与 _chassis_point 同一套映射（但不含 _mount 平移），
## 保证 2 轴构型下网格也是水平地面而不是竖直工作平面。
func _grid_point(fwd: float, side: float, up: float) -> Vector3:
	if _config_type == 0:
		return Vector3(fwd, up, -side) * MM_TO_UNIT
	return _robot_to_godot(fwd, side, up)


## 地面高度（机器人 Z，mm）：显示底盘时取轮下沿，否则就是底座平面。
## 轮子悬在底盘板下方，故轮下沿 = 板顶面 - 板厚 - 间隙 - 2×轮半径。
func _ground_level() -> float:
	if not _chassis_visible:
		return 0.0
	# 底盘高度就是地面到板顶面的距离，故直接用它
	return -(_mount.z + _chassis_height)


func _build_axes() -> void:
	var axes: MeshInstance3D = get_node_or_null(P_AXES)
	if not axes is MeshInstance3D:
		return
	var len_mm: float = (_l1 + _l2 + _l3) * 0.45
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	# 机器人 X / Y / Z 三轴，颜色沿用工程惯例 红/绿/蓝
	var axis_defs: Array = [
		[Vector3(len_mm, 0, 0), Color(0.9, 0.3, 0.3)],
		[Vector3(0, len_mm, 0), Color(0.3, 0.85, 0.35)],
		[Vector3(0, 0, len_mm), Color(0.35, 0.55, 0.95)],
	]
	for d in axis_defs:
		# 2 轴构型没有机器人 Z 轴，跳过以免误导
		if _config_type == 0 and d[0].z > 0.0:
			continue
		im.surface_set_color(d[1])
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_set_color(d[1])
		im.surface_add_vertex(_vec_to_godot(d[0]))
	im.surface_end()
	axes.mesh = im


# ------------------------------------------------------------------ 求解 & 渲染
## 依据当前模式算出关节角，钳位，然后更新 3D
func _recompute() -> void:
	if _mode == Mode.FK:
		# 正解模式：滑块直接给关节角，仍走限位钳位以复现真机
		var lim: Dictionary = _cg.clamp_angles_to_limits(_fk_angles.slice(0, _jc), _joints)
		_angles = lim["angles"]
		_clamped = lim["clamped"]
		_reachable = true
		var fk: Array = _cg.forward_kinematics_angles(_angles, _l1, _l2, _l3, _config_type)
		_target = [fk[0], fk[1], fk[2], fk[3]]
	else:
		var res: Dictionary = _cg.solve_ik_checked(_target[0], _target[1], _target[2], _target[3],
			_l1, _l2, _l3, _config_type, _jc, _elbow)
		_reachable = res["reachable"]
		var lim2: Dictionary = _cg.clamp_angles_to_limits(res["angles"], _joints)
		_angles = lim2["angles"]
		_clamped = lim2["clamped"]
		# FK 滑块跟着走，切模式时姿态连续
		for i in range(min(_angles.size(), 4)):
			_fk_angles[i] = _angles[i]
	_render_arm()
	_sync_param_widgets()
	_update_status()


## 按 _angles 更新连杆/关节的 Transform3D
func _render_arm() -> void:
	var frames: Array = _cg.joint_frames(_angles, _l1, _l2, _l3, _config_type)
	var pts: Array = []
	for f in frames:
		pts.append(_vec_to_godot(f))
	# 连杆：CylinderMesh 默认沿 +Y、以中心为原点，故平移到中点并把 +Y 转到段方向
	var bad: bool = not _reachable
	for i in range(_link_nodes.size()):
		var link: MeshInstance3D = _link_nodes[i]
		if i + 1 >= pts.size():
			link.visible = false
			continue
		link.visible = true
		link.material_override = _mat_link_bad if bad else _mat_link
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		link.transform = _segment_transform(a, b)
	# 关节球
	for i in range(_joint_nodes.size()):
		var jn: MeshInstance3D = _joint_nodes[i]
		if i >= pts.size():
			jn.visible = false
			continue
		jn.visible = true
		jn.position = pts[i]
		var is_clamped: bool = i < _clamped.size() and _clamped[i]
		jn.material_override = _mat_joint_clamped if is_clamped else _mat_joint
	# 末端球
	if _tip_node != null:
		_tip_node.position = pts[pts.size() - 1]
	# 目标幽灵球：仅当目标与实际末端有可见差距时显示
	var ghost: MeshInstance3D = get_node_or_null(P_GHOST)
	if ghost is MeshInstance3D:
		var tgt: Vector3 = _robot_to_godot(_target[0], _target[1], _target[2])
		ghost.position = tgt
		ghost.visible = _mode != Mode.FK \
			and tgt.distance_to(pts[pts.size() - 1]) > TIP_RADIUS_MM * MM_TO_UNIT * 0.6
	_render_gripper(pts)
	_push_trail(pts[pts.size() - 1])


## 把单位长度沿 +Y 的圆柱摆到 a->b 段上
func _segment_transform(a: Vector3, b: Vector3) -> Transform3D:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	if length < 1e-6:
		# 零长段（例如 L3=0 的腕部）退化为不可见的极小段，避免 basis 退化
		return Transform3D(Basis().scaled(Vector3(1, 1e-6, 1)), a)
	var up: Vector3 = dir / length
	# 取一个与 up 不平行的参考轴构造正交基
	var ref: Vector3 = Vector3.RIGHT if abs(up.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var right: Vector3 = ref.cross(up).normalized()
	var fwd: Vector3 = up.cross(right)
	var basis: Basis = Basis(right, up * length, fwd)
	return Transform3D(basis, (a + b) * 0.5)


# ------------------------------------------------------------------ 轨迹
func _push_trail(p: Vector3) -> void:
	if not _trail_enabled:
		return
	if _trail_points.size() > 0 and _trail_points[_trail_points.size() - 1].distance_to(p) < 1e-4:
		return
	_trail_points.append(p)
	# 环形缓冲：超出上限丢弃最旧的点
	while _trail_points.size() > TRAIL_MAX_POINTS:
		_trail_points.pop_front()
	_redraw_trail()


func _redraw_trail() -> void:
	var trail: MeshInstance3D = get_node_or_null(P_TRAIL)
	if not trail is MeshInstance3D:
		return
	if _trail_points.size() < 2:
		trail.mesh = null
		return
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var n: int = _trail_points.size()
	for i in range(n):
		# 越旧越淡，形成残影观感
		var alpha: float = 0.15 + 0.75 * (float(i) / float(n - 1))
		im.surface_set_color(Color(0.4, 0.9, 0.65, alpha))
		im.surface_add_vertex(_trail_points[i])
	im.surface_end()
	trail.mesh = im


func _clear_trail() -> void:
	_trail_points.clear()
	_redraw_trail()


func _on_trail_toggled(on: bool) -> void:
	_trail_enabled = on
	if not on:
		_clear_trail()


func _on_chassis_toggled(on: bool) -> void:
	_chassis_visible = on
	_build_chassis()
	# 网格代表地面，高度随底盘显隐而变
	_build_grid()
	_update_status()


# ------------------------------------------------------------------ 状态提示
func _update_status() -> void:
	var label: Node = get_node_or_null(P_STATUS)
	if not label is Label:
		return
	var lines: Array = []
	var tip: Array = _cg.forward_kinematics_angles(_angles, _l1, _l2, _l3, _config_type)
	if _config_type == 0:
		lines.append("末端 X=%.1f Y=%.1f mm" % [tip[0], tip[1]])
	elif _config_type == 1:
		lines.append("末端 X=%.1f Y=%.1f Z=%.1f mm" % [tip[0], tip[1], tip[2]])
	else:
		lines.append("末端 X=%.1f Y=%.1f Z=%.1f mm  φ=%.1f°" % [tip[0], tip[1], tip[2], tip[3]])
	var ang_parts: Array = []
	for i in range(_angles.size()):
		ang_parts.append("θ%d=%.1f°" % [i + 1, _angles[i]])
	lines.append("运动学角 " + "  ".join(ang_parts))
	# 舵机指令角 = 运动学角 - 中位朝向，这才是真正发给舵机的值
	var sv: Dictionary = _cg.servo_angles(_angles, _joints)
	var sv_parts: Array = []
	for i in range(sv["angles"].size()):
		var mark: String = " ✗超程" if sv["over_travel"][i] else ""
		sv_parts.append("s%d=%.1f°%s" % [i + 1, sv["angles"][i], mark])
	lines.append("舵机指令角 " + "  ".join(sv_parts))
	# 可达性：与生成的 C 代码里的 ik_reachable 同义
	if _mode == Mode.FK:
		lines.append("标定模式：由关节角推算末端，不做逆解")
	elif _reachable:
		lines.append("ik_reachable = 1  目标可达")
	else:
		lines.append("ik_reachable = 0  目标不可达，已钳位到 [%.0f, %.0f] mm 半径边界"
			% [abs(_l1 - _l2), _l1 + _l2])
	var over: Array = []
	for i in range(_clamped.size()):
		if _clamped[i]:
			over.append("关节%d 超限位 [%s, %s]"
				% [i + 1, _joint_limit_str(i, "min"), _joint_limit_str(i, "max")])
	for i in range(sv["over_travel"].size()):
		if sv["over_travel"][i]:
			over.append("关节%d 舵机超程（指令角 %.1f° 超出 ±90°，中位朝向 %.1f°）"
				% [i + 1, sv["angles"][i], _joint_offset(i)])
	if over.size() > 0:
		lines.append(", ".join(over))
	# 夹爪朝向：与状态行里的 φ 互为印证，也覆盖 2/3 轴（它们没有 φ 字段）
	lines.append(_gripper_text())
	# 末端相对底盘中心的位置，判断有没有伸出车外
	if _chassis_visible:
		lines.append(_chassis_relation_text(tip))
	label.text = "\n".join(lines)


## 夹爪朝向描述：末端连杆相对水平面的仰角，正=朝上
func _gripper_text() -> String:
	var frames: Array = _cg.joint_frames(_angles, _l1, _l2, _l3, _config_type)
	if frames.size() < 2:
		return "夹爪 朝向未定义"
	var seg: Vector3 = frames[frames.size() - 1] - frames[frames.size() - 2]
	if seg.length() < 1e-6:
		return "夹爪 末段长度为 0，朝向未定义"
	# 末段在工作平面内的仰角：2 轴高度是 y，3/4 轴是 z
	var rise: float = seg.y if _config_type == 0 else seg.z
	var run: float = sqrt(seg.x * seg.x + seg.y * seg.y) if _config_type != 0 else absf(seg.x)
	var pitch: float = rad_to_deg(atan2(rise, run))
	return "夹爪 仰角%+.1f°  张开%.0f%%" % [pitch, _grip_open * 100.0]


## 末端相对底盘的位置描述：伸出车外多少、是否低于轮下沿
func _chassis_relation_text(tip: Array) -> String:
	# 末端在底盘坐标系里的位置 = 机器人坐标 + 安装偏移（高度以板顶面为 0）
	var fwd: float = tip[0] + _mount.x
	var side: float = (tip[1] if _config_type != 0 else 0.0) + _mount.y
	var up: float = (tip[2] if _config_type != 0 else tip[1]) + _mount.z
	var half_wb: float = _chassis_deck_len * 0.5
	var half_tr: float = _chassis_track * 0.5
	var parts: Array = ["末端相对底盘 前后%+.0f 高%+.0f mm" % [fwd, up]]
	if _config_type != 0:
		parts[0] = "末端相对底盘 前后%+.0f 左右%+.0f 高%+.0f mm" % [fwd, side, up]
	var out_of: Array = []
	if absf(fwd) > half_wb:
		out_of.append("前后伸出 %.0f" % (absf(fwd) - half_wb))
	if _config_type != 0 and absf(side) > half_tr:
		out_of.append("左右伸出 %.0f" % (absf(side) - half_tr))
	if out_of.size() > 0:
		parts.append("（超出底盘 " + " / ".join(out_of) + " mm）")
	# 地面相对板顶面的高度（up 已以板顶面为 0）
	var ground: float = -_chassis_height
	if up < ground:
		parts.append("⚠ 末端低于地面 %.0f mm（会碰地）" % (ground - up))
	return "  ".join(parts)


func _joint_limit_str(idx: int, key: String) -> String:
	if idx < _joints.size():
		var s: String = str(_joints[idx].get(key, "")).strip_edges()
		if s.is_valid_float():
			return "%.0f" % s.to_float()
	return "-90" if key == "min" else "90"


# ------------------------------------------------------------------ 模式切换
func _on_mode_selected(idx: int) -> void:
	_mode = idx
	_joy = Vector2.ZERO
	_keys_down.clear()
	_play_idx = -1
	_sim_accum = 0.0
	_rebuild_params()
	_update_hint()
	_recompute()


## 底部提示条：相机操作固定，后半段随模式换
func _update_hint() -> void:
	var label: Node = get_node_or_null(P_HINT)
	if not label is Label:
		return
	var base: String = "右键旋转视角 · 滚轮缩放 · 中键平移"
	match _mode:
		Mode.IK:
			label.text = "%s · %s · Shift 加速 / Alt 减速" % [base, _key_hint_text()]
		Mode.CONTROLLER:
			label.text = "%s · WASD 代打右摇杆 · 手柄 A/B/C/D 代打为 1/2/3/4" % base
		_:
			label.text = base


# ------------------------------------------------------------------ 参数面板
## 按当前模式重建右侧参数控件。所有模式共用 _recompute() 做渲染更新。
func _rebuild_params() -> void:
	var params: Node = get_node_or_null(P_PARAMS)
	if params == null:
		return
	for c in params.get_children():
		c.queue_free()
	_sliders.clear()
	_spins.clear()
	match _mode:
		Mode.IK:
			_build_ik_params(params)
		Mode.FK:
			_build_fk_params(params)
		Mode.PRESET:
			_build_preset_params(params)
		Mode.CONTROLLER:
			_build_controller_params(params)


func _add_section(parent: Node, text: String) -> void:
	var sep: HSeparator = HSeparator.new()
	parent.add_child(sep)
	var l: Label = Label.new()
	l.text = text
	parent.add_child(l)


## 一行「标签 + 滑块 + 数值框」，双向同步
func _add_slider_row(parent: Node, key: String, label_text: String,
		lo: float, hi: float, value: float, step: float) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	parent.add_child(box)
	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	var l: Label = Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = clamp(value, lo, hi)
	spin.custom_minimum_size = Vector2(96, 0)
	head.add_child(spin)
	var slider: HSlider = HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = clamp(value, lo, hi)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slider)
	_sliders[key] = slider
	_spins[key] = spin
	slider.value_changed.connect(_on_param_changed.bind(key, spin))
	spin.value_changed.connect(_on_param_changed.bind(key, slider))


## 滑块或数值框变动：先把对端同步过去（抑制回环），再按 key 写入状态
func _on_param_changed(value: float, key: String, peer: Node) -> void:
	if _syncing:
		return
	_syncing = true
	if peer is Range:
		peer.value = value
	_syncing = false
	match key:
		"x": _target[0] = value
		"y": _target[1] = value
		"z": _target[2] = value
		"phi": _target[3] = value
		"j0": _fk_angles[0] = value
		"j1": _fk_angles[1] = value
		"j2": _fk_angles[2] = value
		"j3": _fk_angles[3] = value
		"movespd":
			# 速度只影响下一帧的键盘步进，不改当前姿态
			_ik_move_speed = value
			return
		"rotspd":
			_ik_rot_speed = value
			return
		"L1", "L2", "L3":
			_on_link_length_changed(key, value)
			return
		"cwb", "ctr", "chh", "mx", "my", "mz":
			_on_chassis_param_changed(key, value)
			return
		"grip":
			# 夹爪开合纯可视化，姿态不变，只需重摆夹爪
			_grip_open = value
			_render_arm()
			return
	_recompute()


## 底盘尺寸 / 安装位置改动：只需重画底盘，机械臂本身不受影响
func _on_chassis_param_changed(key: String, value: float) -> void:
	match key:
		"cwb": _chassis_deck_len = value
		"ctr": _chassis_track = value
		"mx": _mount.x = value
		"my": _mount.y = value
		# 低于板厚就没意义了（板本身就那么厚），其余一律允许
		"chh": _chassis_height = maxf(value, CHASSIS_DECK_THICK_MM)
		"mz": _mount.z = value
	_build_chassis()
	# 安装高度与底盘高都会改变地面位置，网格要跟着重画
	if key == "mz" or key == "chh":
		_build_grid()
	# 提示文字里印着轮径与间隙的推算结果，改完要刷新
	if key == "chh":
		_refresh_chassis_hint()
	_update_status()


## 刷新底盘提示里的轮径/间隙读数（不重建整个面板，避免打断拖动）
func _refresh_chassis_hint() -> void:
	var params: Node = get_node_or_null(P_PARAMS)
	if params == null:
		return
	var label: Node = params.get_node_or_null("ChassisHint")
	if label is Label:
		label.text = "底盘高 = 地面到底盘板顶面；轮径固定 %.0f mm，改车高只动悬挂间隙（当前 %.0f mm）。" \
			% [WHEEL_RADIUS_MM * 2.0, _wheel_gap()]
		label.text += "\n底盘只是视觉参照，不参与逆解算：逆解的原点永远是机械臂底座。"
		label.text += "\n改安装位置就是挪底盘，用来核对臂能不能伸到车外、会不会撞到自己的轮子。"


## 臂长改动：几何要重建，可达域也跟着变
func _on_link_length_changed(key: String, value: float) -> void:
	match key:
		"L1": _l1 = maxf(value, 1.0)
		"L2": _l2 = maxf(value, 1.0)
		"L3": _l3 = maxf(value, 0.0)
	_rebuild_arm()
	_rebuild_static_geometry()
	_update_config_label()
	_clear_trail()
	_emit_config_changed()
	_recompute()


## 求解结果回写到控件（IK 模式下 FK 值会变，反之亦然）
func _sync_param_widgets() -> void:
	_syncing = true
	var vals: Dictionary = {}
	if _mode == Mode.FK:
		for i in range(_angles.size()):
			vals["j%d" % i] = _angles[i]
	else:
		vals = {"x": _target[0], "y": _target[1], "z": _target[2], "phi": _target[3]}
	for key in vals.keys():
		if _sliders.has(key):
			_sliders[key].set_value_no_signal(clamp(vals[key],
				_sliders[key].min_value, _sliders[key].max_value))
		if _spins.has(key):
			_spins[key].set_value_no_signal(clamp(vals[key],
				_spins[key].min_value, _spins[key].max_value))
	_syncing = false


# --- IK 模式参数
func _build_ik_params(parent: Node) -> void:
	_build_link_length_rows(parent)
	_add_section(parent, "末端目标（逆解）")
	# 滑块范围按最大可达半径取整，留 20% 余量便于试探越界行为
	var reach: float = (_l1 + _l2 + _l3) * 1.2
	_add_slider_row(parent, "x", "X (mm)", -reach, reach, _target[0], 1.0)
	if _config_type == 0:
		# 2 轴构型 Y 是高度
		_add_slider_row(parent, "y", "Y (mm，竖直)", -reach, reach, _target[1], 1.0)
	else:
		_add_slider_row(parent, "y", "Y (mm)", -reach, reach, _target[1], 1.0)
		_add_slider_row(parent, "z", "Z (mm，高度)", -reach, reach, _target[2], 1.0)
	if _jc >= 4:
		_add_slider_row(parent, "phi", "末端姿态角 φ (°)", -180.0, 180.0, _target[3], 1.0)
	_add_section(parent, "键盘移动速度")
	_add_slider_row(parent, "movespd", "位移 (mm/s)", 10.0, 500.0, _ik_move_speed, 5.0)
	if _jc >= 4:
		_add_slider_row(parent, "rotspd", "姿态角 (°/s)", 5.0, 240.0, _ik_rot_speed, 5.0)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "键盘控制末端：" + _key_hint_text()
	hint.text += "\nShift 加速一倍，Alt 减速到 1/4。"
	hint.text += "\n黄色半透明球是目标位置，与末端分离即表示被钳位。"
	parent.add_child(hint)
	_build_gripper_rows(parent)


## 当前构型的键盘映射说明（顶栏提示与侧欄共用）
func _key_hint_text() -> String:
	if _config_type == 0:
		return "A/D 走 X，W/S 或 ↑↓ 走 Y（高度）"
	var s: String = "W/S 走 X，A/D 走 Y（水平面），↑↓ 走 Z（高度）"
	if _jc >= 4:
		s += "，Q/E 调姿态角 φ"
	return s


# --- FK / 标定模式参数
func _build_fk_params(parent: Node) -> void:
	_build_link_length_rows(parent)
	_add_section(parent, "关节角度（运动学角）")
	for i in range(_jc):
		var rng: Array = _joint_slider_range(i)
		_add_slider_row(parent, "j%d" % i, "关节%d θ (°) 可调 [%.0f, %.0f]" % [i + 1, rng[0], rng[1]],
			rng[0], rng[1], _fk_angles[i], 0.5)
	_add_section(parent, "安装标定")
	var set_off: Button = Button.new()
	set_off.text = "当前姿态设为中位朝向"
	set_off.tooltip_text = "舵机盘装歪时用：把滑块摆到「舵机处于中位时臂的实际朝向」再点这里"
	set_off.pressed.connect(_calibrate_offset_from_current)
	parent.add_child(set_off)
	var set_home: Button = Button.new()
	set_home.text = "当前姿态设为初始角"
	set_home.tooltip_text = "上电后机械臂应停在的姿态"
	set_home.pressed.connect(_calibrate_home_from_current)
	parent.add_child(set_home)
	var reset_off: Button = Button.new()
	reset_off.text = "中位朝向归零"
	reset_off.pressed.connect(_reset_offsets)
	parent.add_child(reset_off)
	# 当前各关节的中位朝向读数，标定完能立刻核对
	var off_label: Label = Label.new()
	off_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	off_label.text = _offset_summary()
	off_label.name = "OffsetSummary"
	parent.add_child(off_label)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "滑块是运动学角（连杆实际朝向）。舵机指令角 = 运动学角 - 中位朝向，"
	hint.text += "行程 ±90°，超出会被钳到端点（状态行会提示）。"
	parent.add_child(hint)
	_build_gripper_rows(parent)
	_build_chassis_rows(parent)


## 臂长编辑行（标定与预设模式共用）
func _build_link_length_rows(parent: Node) -> void:
	_add_section(parent, "连杆长度 (mm)")
	_add_slider_row(parent, "L1", "L1 大臂", 10.0, 600.0, _l1, 1.0)
	_add_slider_row(parent, "L2", "L2 小臂", 10.0, 600.0, _l2, 1.0)
	if _jc >= 4:
		_add_slider_row(parent, "L3", "L3 腕部", 0.0, 600.0, _l3, 1.0)


## 夹爪开合（纯视觉，真机夹爪另有舵机，不在本构型的关节里）
func _build_gripper_rows(parent: Node) -> void:
	_add_section(parent, "夹爪")
	_add_slider_row(parent, "grip", "张开度", 0.0, 1.0, _grip_open, 0.05)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "夹爪的伸出方向就是末端姿态角，两指在臂的工作平面内对开。"
	hint.text += "\n开合只是示意，不占关节、不进逆解。"
	parent.add_child(hint)


## 底盘尺寸与机械臂安装位置（纯视觉参照，不进逆解）
func _build_chassis_rows(parent: Node) -> void:
	_add_section(parent, "底盘尺寸 (mm)")
	_add_slider_row(parent, "cwb", "底盘板长（前后）", 100.0, 800.0, _chassis_deck_len, 5.0)
	# 下限取板厚：再低就是板贴地了（机械上确实能做到离地几乎为 0）。
	# 上限压到轮径的 3 倍：轮子只有 50mm，再高支臂就细长得像桌腿了
	_add_slider_row(parent, "chh", "底盘高（地面到板面）",
		CHASSIS_DECK_THICK_MM,
		WHEEL_RADIUS_MM * 6.0 + CHASSIS_DECK_THICK_MM, _chassis_height, 5.0)
	if _config_type != 0:
		_add_slider_row(parent, "ctr", "轮距（左右）", 100.0, 800.0, _chassis_track, 5.0)
	_add_section(parent, "机械臂安装位置（相对底盘中心）")
	_add_slider_row(parent, "mx", "前后偏移（+前）", -400.0, 400.0, _mount.x, 5.0)
	if _config_type != 0:
		_add_slider_row(parent, "my", "左右偏移（+左）", -400.0, 400.0, _mount.y, 5.0)
	_add_slider_row(parent, "mz", "底座离底盘板高", 0.0, 400.0, _mount.z, 5.0)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.name = "ChassisHint"
	hint.text = "底盘高 = 地面到底盘板顶面；轮径固定 %.0f mm，改车高只动悬挂间隙（当前 %.0f mm）。" \
		% [WHEEL_RADIUS_MM * 2.0, _wheel_gap()]
	hint.text += "\n底盘只是视觉参照，不参与逆解算：逆解的原点永远是机械臂底座。"
	hint.text += "\n改安装位置就是挪底盘，用来核对臂能不能伸到车外、会不会撞到自己的轮子。"
	parent.add_child(hint)


## 关节滑块范围：限位配置与舵机可达行程（中位朝向 ±90°）的交集
func _joint_slider_range(i: int) -> Array:
	var off: float = _joint_offset(i)
	var lo: float = off - 90.0
	var hi: float = off + 90.0
	if i < _joints.size():
		var mn: String = str(_joints[i].get("min", "")).strip_edges()
		var mx: String = str(_joints[i].get("max", "")).strip_edges()
		if mn.is_valid_float():
			lo = maxf(lo, mn.to_float())
		if mx.is_valid_float():
			hi = minf(hi, mx.to_float())
	if lo >= hi:
		# 限位与行程无交集（配置有问题），退回舵机全行程以免滑块不可用
		lo = off - 90.0
		hi = off + 90.0
	return [lo, hi]


func _joint_offset(i: int) -> float:
	if i >= _joints.size():
		return 0.0
	var s: String = str(_joints[i].get("offset", "")).strip_edges()
	return s.to_float() if s.is_valid_float() else 0.0


func _offset_summary() -> String:
	var parts: Array = []
	for i in range(_jc):
		parts.append("θ%d=%.1f°" % [i + 1, _joint_offset(i)])
	return "当前中位朝向： " + "  ".join(parts)


## 把当前姿态写成各关节的安装中位朝向
func _calibrate_offset_from_current() -> void:
	for i in range(_jc):
		_joints[i]["offset"] = "%.2f" % _angles[i]
	# 中位朝向变了，滑块可调范围随之平移，必须重建面板
	_rebuild_params()
	_emit_config_changed()
	_recompute()


## 把当前姿态写成上电初始角
func _calibrate_home_from_current() -> void:
	for i in range(_jc):
		_joints[i]["zero"] = "%.2f" % _angles[i]
	# 肘部分支由初始角符号决定，改了要重算，否则逆解会跳到镜像姿态
	_elbow = _cg._elbow_sign(_joints, _config_type)
	_emit_config_changed()
	_recompute()


func _reset_offsets() -> void:
	for i in range(_jc):
		_joints[i]["offset"] = "0"
	_rebuild_params()
	_emit_config_changed()
	_recompute()


# --- 预设点位模式
func _build_preset_params(parent: Node) -> void:
	_build_link_length_rows(parent)
	_add_section(parent, "预设点位（点按钮跳转）")
	var active: Array = _active_presets()
	if active.is_empty():
		var l: Label = Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "尚无启用的预设点位。用下面的「存为预设」把当前末端位置存进去。"
		parent.add_child(l)
	for entry in active:
		var p: Dictionary = entry["preset"]
		var btn: Button = Button.new()
		btn.text = "P%d [键 %s]  %s" % [
			entry["index"] + 1, p.get("key", "?"), _preset_coord_text(p)]
		btn.pressed.connect(_goto_preset.bind(entry["index"]))
		parent.add_child(btn)
	# 捕获当前末端位置为预设点位（4 个槽位固定，与配置界面 Preset1~4 一一对应）
	_add_section(parent, "存为预设（写入当前末端位置）")
	for i in range(4):
		var save: Button = Button.new()
		var occupied: bool = i < _presets.size() and _presets[i].get("enabled", false)
		save.text = "存为预设 %d%s" % [i + 1, "（覆盖）" if occupied else ""]
		save.pressed.connect(_save_preset.bind(i))
		parent.add_child(save)
	if not active.is_empty():
		var clear_row: Button = Button.new()
		clear_row.text = "清空全部预设"
		clear_row.pressed.connect(_clear_presets)
		parent.add_child(clear_row)
	if active.is_empty():
		return
	_add_section(parent, "巡航")
	var play: Button = Button.new()
	play.text = "依次播放"
	play.pressed.connect(_start_play)
	parent.add_child(play)
	var stop: Button = Button.new()
	stop.text = "停止"
	stop.pressed.connect(func() -> void: _play_idx = -1)
	parent.add_child(stop)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "真机按键是瞬时跳转目标，这里的插值仅为便于观察运动路径。"
	parent.add_child(hint)


## 启用的预设点位，附原始序号（按钮标号要与配置界面 Preset N 对得上）
func _active_presets() -> Array:
	var out: Array = []
	for i in range(_presets.size()):
		if _presets[i].get("enabled", false):
			out.append({"index": i, "preset": _presets[i]})
	return out


func _p_float(p: Dictionary, key: String) -> float:
	var s: String = str(p.get(key, "")).strip_edges()
	return s.to_float() if s.is_valid_float() else 0.0


func _goto_preset(idx: int) -> void:
	if idx >= _presets.size():
		return
	var p: Dictionary = _presets[idx]
	_play_idx = -1
	_target = [_p_float(p, "x"), _p_float(p, "y"), _p_float(p, "z"), _p_float(p, "phi")]
	_recompute()


## 预设点位坐标的显示文本（按构型裁剪，2 轴无 Z、非 4 轴无 φ）
func _preset_coord_text(p: Dictionary) -> String:
	var s: String = "X=%.0f Y=%.0f" % [_p_float(p, "x"), _p_float(p, "y")]
	if _config_type != 0:
		s += " Z=%.0f" % _p_float(p, "z")
	if _jc >= 4:
		s += " φ=%.0f°" % _p_float(p, "phi")
	return s


## 把当前末端实际位置存为第 idx 个预设点位。
## 存实际末端（经限位钳位后的 FK 结果）而非目标值，否则存进去的点位本身就不可达。
func _save_preset(idx: int) -> void:
	while _presets.size() <= idx:
		_presets.append({"key": "A", "x": "", "y": "", "z": "", "phi": "", "enabled": false})
	var tip: Array = _cg.forward_kinematics_angles(_angles, _l1, _l2, _l3, _config_type)
	var p: Dictionary = _presets[idx]
	p["x"] = "%.2f" % tip[0]
	p["y"] = "%.2f" % tip[1]
	# 2 轴构型没有 Z 轴，写空避免配置界面出现无意义的 0
	p["z"] = "%.2f" % tip[2] if _config_type != 0 else ""
	p["phi"] = "%.2f" % tip[3] if _jc >= 4 else ""
	p["enabled"] = true
	# 按键未选过时给个默认，避免生成的 C 里 presetKey 落到回退值
	if not p.has("key") or str(p.get("key", "")).is_empty():
		p["key"] = ["A", "B", "C", "D"][idx % 4]
	_presets[idx] = p
	_play_idx = -1
	_rebuild_params()
	_emit_config_changed()


func _clear_presets() -> void:
	for i in range(_presets.size()):
		_presets[i]["x"] = ""
		_presets[i]["y"] = ""
		_presets[i]["z"] = ""
		_presets[i]["phi"] = ""
		_presets[i]["enabled"] = false
	_play_idx = -1
	_rebuild_params()
	_emit_config_changed()


func _start_play() -> void:
	var active: Array = _active_presets()
	if active.is_empty():
		return
	_play_idx = 0
	_play_t = 0.0
	_play_from = _target.duplicate()


# --- 模拟手柄模式（键盘代打手柄）
func _build_controller_params(parent: Node) -> void:
	_add_section(parent, "右摇杆（键盘代打）")
	var joy_scale: float = _cfg_float("joy_scale", 5.0)
	var jl: Label = Label.new()
	jl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jl.text = "WASD = 摇杆推向四个方向（W/S 竖直，A/D 水平），松开即回中。"
	jl.text += "\n映射：%s / %s" % [_cfg.get("joy_x", "右X->末端X"), _cfg.get("joy_y", "右Y->末端Y")]
	if _jc >= 3:
		jl.text += " / %s" % _cfg.get("joy_z", "右X->末端Z")
	jl.text += "\n满偏步长 JOY_SCALE = %.2f mm/周期（%dms）" % [joy_scale, int(SIM_STEP_MS)]
	parent.add_child(jl)
	_add_section(parent, "手柄按键（长按持续移动）")
	var rows: Array = _controller_key_rows()
	if rows.is_empty():
		var l2: Label = Label.new()
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.text = "未配置按键移动。回到配置界面的「按键控制末端移动」再选。"
		parent.add_child(l2)
	for row in rows:
		var l: Label = Label.new()
		l.text = "手柄 %s  →  键盘 %s   (%s %s)" % [
			row["handle"], row["kb_name"], row["label"], row["sign_text"]]
		parent.add_child(l)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "复现 C 端 CalculateIK：增量累加 -> 逆解 -> 越界且上次可达时回退本周期增量。"
	hint.text += "\n手柄 A/B/C/D 在这里代打为数字键 1/2/3/4，避免与摇杆的 WASD 冲突。"
	parent.add_child(hint)


## 手柄按键映射表 -> 仿真里可用的键盘绑定行
## 返回 [{axis, sign, handle, kb_code, kb_name, label, sign_text}]
func _controller_key_rows() -> Array:
	var keymove: Array = _cfg.get("keymove", [])
	var labels: Array = ["末端X", "末端Y", "末端Z", "姿态角φ"]
	var out: Array = []
	for i in range(min(keymove.size(), 4)):
		# 2 轴无 Z 轴；仅 4 轴有腕部姿态角（与生成器的裁剪规则一致）
		if _jc < 3 and i == 2:
			continue
		if _jc < 4 and i == 3:
			continue
		for sign_key in ["plus", "minus"]:
			var kname: String = str(keymove[i].get(sign_key, "不使用"))
			if kname == "不使用" or not HANDLE_KEY_TO_KEYBOARD.has(kname):
				continue
			var code: int = HANDLE_KEY_TO_KEYBOARD[kname]
			out.append({
				"axis": i,
				"sign": 1.0 if sign_key == "plus" else -1.0,
				"handle": kname,
				"kb_code": code,
				"kb_name": OS.get_keycode_string(code),
				"label": labels[i],
				"sign_text": "+" if sign_key == "plus" else "-",
			})
	return out


# ------------------------------------------------------------------ 每帧推进
func _process(delta: float) -> void:
	if _mode == Mode.PRESET:
		if _play_idx >= 0:
			_step_play(delta)
		return
	# 焦点在数值框里时不吃键盘，否则输入 W/S 会同时推动末端
	if _text_field_focused():
		return
	if _mode == Mode.CONTROLLER:
		_poll_controller_keys()
		_step_controller(delta)
	elif _mode == Mode.IK:
		_step_key_move(delta)


## 当前焦点是否落在可输入文本的控件上
func _text_field_focused() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var f: Control = vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## 采样键盘，推出等效的摇杆偏移与手柄按键状态
func _poll_controller_keys() -> void:
	# WASD 代打右摇杆：满偏 = 键按下，松开立即回中（真机摇杆也是自动回中的）
	_joy = Vector2(_axis_pair(KEY_D, KEY_A), _axis_pair(KEY_W, KEY_S))
	_keys_down.clear()
	for row in _controller_key_rows():
		if Input.is_key_pressed(row["kb_code"]):
			_keys_down["%d:%d" % [row["axis"], int(row["sign"])]] = true


## 复现生成的 C 主循环：固定 10ms 一步，把不定 delta 切成整数步，
## 保证仿真里的移动速度与真机一致
func _step_controller(delta: float) -> void:
	_sim_accum += delta * 1000.0
	var steps: int = int(_sim_accum / SIM_STEP_MS)
	if steps <= 0:
		return
	_sim_accum -= float(steps) * SIM_STEP_MS
	# 一帧内最多补 20 步，避免掉帧后一次跳很远
	steps = min(steps, 20)
	var joy_scale: float = _cfg_float("joy_scale", 5.0)
	var key_speed: float = _cfg_float("keymove_speed", 2.0)
	var moved: bool = false
	for _s in range(steps):
		var last: Array = _target.duplicate()
		var last_reachable: bool = _reachable
		# 摇杆增量：与 C 端 valueOfRoker[..]/2047 * JOY_SCALE 等价
		var joy_vals: Array = [
			_joy_axis_value(str(_cfg.get("joy_x", "右X->末端X"))),
			_joy_axis_value(str(_cfg.get("joy_y", "右Y->末端Y"))),
			_joy_axis_value(str(_cfg.get("joy_z", "右X->末端Z"))),
		]
		_target[0] += joy_vals[0] * joy_scale
		_target[1] += joy_vals[1] * joy_scale
		if _jc >= 3:
			_target[2] += joy_vals[2] * joy_scale
		# 按键增量
		var keymove: Array = _cfg.get("keymove", [])
		for i in range(min(keymove.size(), 4)):
			for sv in [1.0, -1.0]:
				if _keys_down.has("%d:%d" % [i, int(sv)]):
					# φ 用 KEYMOVE_PHI_SPEED，生成器里其数值等于 keymove_speed
					_target[i] += sv * key_speed
		var res: Dictionary = _cg.solve_ik_checked(_target[0], _target[1], _target[2], _target[3],
			_l1, _l2, _l3, _config_type, _jc, _elbow)
		# 越界回退：仅当上次目标可达时才退，否则不可达的起点会把目标永久卡死
		if not res["reachable"] and last_reachable:
			_target = last
		moved = true
	if moved:
		_recompute()


## 摇杆选项文本 -> 该轴当前归一化值。左摇杆固定给底盘，末端只用右摇杆。
## 只看 "->" 左侧的源轴，与 codegen 的 parse_joy_axis 同规则
func _joy_axis_value(text: String) -> float:
	var src: String = text
	var arrow: int = text.find("->")
	if arrow >= 0:
		src = text.substr(0, arrow)
	# 摇杆竖直方向在 C 端是 valueOfRoker[1][1]，此处 _joy.y 已是归一化值
	var raw: float = _joy.y if "Y" in src else _joy.x
	# 走一遍 -2047~2047 的量化，与真机的整数摇杆读数一致
	return round(raw * ROKER_FULL) / ROKER_FULL


## 预设点位巡航：在目标空间线性插值，走完一个点位停 0.4s 再去下一个
func _step_play(delta: float) -> void:
	var active: Array = _active_presets()
	if active.is_empty():
		_play_idx = -1
		return
	var idx: int = _play_idx % active.size()
	var p: Dictionary = active[idx]["preset"]
	var to: Array = [_p_float(p, "x"), _p_float(p, "y"), _p_float(p, "z"), _p_float(p, "phi")]
	_play_t += delta / 1.2
	if _play_t >= 1.0:
		_play_t = 0.0
		_target = to
		_play_from = to.duplicate()
		_play_idx = (_play_idx + 1) % active.size()
	else:
		for i in range(4):
			var from_v: float = _play_from[i] if i < _play_from.size() else 0.0
			_target[i] = lerp(from_v, to[i], _play_t)
	_recompute()


# ------------------------------------------------------------------ 相机
func _reset_view() -> void:
	# 显式算出「臂 + 车」的竖直范围与水平半宽，再让取景距离同时满足两者。
	# 之前只用一个"包围半径"，车高一变就会把臂裁出画面顶部（踩过）。
	var arm_reach: float = _l1 + _l2 + _l3
	# 竖直方向：上界是臂完全举起的高度，下界是地面
	var top_mm: float = arm_reach
	var bottom_mm: float = 0.0
	# 水平方向：臂的可达半径与车身半尺寸取大者
	var half_w_mm: float = arm_reach
	if _chassis_visible:
		bottom_mm = _ground_level()
		half_w_mm = maxf(half_w_mm, maxf(
			_chassis_deck_len * 0.5 + absf(_mount.x),
			_chassis_track * 0.5 + WHEEL_WIDTH_MM + absf(_mount.y)))
	# 取景中心放在竖直范围的正中，上下都不会被裁
	var mid_y: float = (top_mm + bottom_mm) * 0.5 * MM_TO_UNIT
	# 需要装下的半高与半宽（相对取景中心）
	var half_h: float = (top_mm - bottom_mm) * 0.5 * MM_TO_UNIT
	var half_w: float = half_w_mm * MM_TO_UNIT
	# 按相机实际 fov 的竖直半角反推距离；水平方向按视口宽高比换算。
	# 1.25 留一点余量，避免贴边。
	var cam_node: Node = get_node_or_null(P_CAMERA)
	var fov_deg: float = cam_node.fov if cam_node is Camera3D else 75.0
	var vfov: float = deg_to_rad(fov_deg) * 0.5
	var need_v: float = half_h / tan(vfov)
	var aspect: float = 1.78
	var vp: Node = get_node_or_null(P_VIEWPORT)
	if vp is SubViewport and vp.size.y > 0:
		aspect = float(vp.size.x) / float(vp.size.y)
	var need_h: float = half_w / tan(vfov) / aspect
	_cam_dist = max(0.5, maxf(need_v, need_h) * 1.25)
	if _config_type == 0:
		# 2 轴：臂在 Godot XY 平面内，但底盘是三维的。
		# 略微侧转 + 小俯角，既看清臂的工作平面又能数出四个轮子
		_cam_yaw = -0.35
		_cam_pitch = 0.20
	else:
		_cam_yaw = -0.85
		# 俯角不能太大，否则底盘板会把下面的轮子与轮轴挡住
		_cam_pitch = 0.26
	# 水平方向：取景中心落在「底座」与「底盘中心」之间，两者都不至于贴边
	var pivot: Vector3 = Vector3(0.0, mid_y, 0.0)
	if _chassis_visible:
		var deck_center: Vector3 = _chassis_point(0.0, 0.0, 0.0)
		pivot.x = deck_center.x * 0.5
		pivot.z = deck_center.z * 0.5
	_cam_pivot = pivot
	_update_camera()


func _update_camera() -> void:
	var cam: Node = get_node_or_null(P_CAMERA)
	if not cam is Camera3D:
		return
	var offset: Vector3 = Vector3(
		_cam_dist * cos(_cam_pitch) * sin(_cam_yaw),
		_cam_dist * sin(_cam_pitch),
		_cam_dist * cos(_cam_pitch) * cos(_cam_yaw))
	cam.position = _cam_pivot + offset
	cam.look_at(_cam_pivot, Vector3.UP)


# ------------------------------------------------------------------ 输入
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_RIGHT:
			_orbiting = e.pressed
			accept_event()
		MOUSE_BUTTON_MIDDLE:
			_panning = e.pressed
			accept_event()
		MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = max(0.2, _cam_dist * 0.9)
			_update_camera()
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = min(200.0, _cam_dist * 1.1)
			_update_camera()
			accept_event()


func _handle_mouse_motion(e: InputEventMouseMotion) -> void:
	if _orbiting:
		_cam_yaw -= e.relative.x * 0.008
		_cam_pitch = clamp(_cam_pitch + e.relative.y * 0.008, -CAM_PITCH_LIMIT, CAM_PITCH_LIMIT)
		_update_camera()
		accept_event()
	elif _panning:
		var cam: Node = get_node_or_null(P_CAMERA)
		if cam is Camera3D:
			var scale: float = _cam_dist * 0.0015
			var basis: Basis = cam.global_transform.basis
			_cam_pivot -= basis.x * e.relative.x * scale
			_cam_pivot += basis.y * e.relative.y * scale
			_update_camera()
		accept_event()


# ------------------------------------------------------------------ 键盘控制末端
## 逆解模式下由键盘直接推末端目标。
## 3/4 轴：WASD 走水平面（W/S 是机器人 +X/-X，A/D 是 +Y/-Y），↑↓ 走 Z 高度。
## 2 轴：只有一个竖直工作平面，A/D 走 X，W/S 与 ↑↓ 都走 Y（高度）。
## 按住 Shift 加速一倍，按住 Alt 减速到 1/4，便于粗调后微调。
func _step_key_move(delta: float) -> void:
	var d: Vector3 = _key_move_axis()
	var dphi: float = _key_phi_axis()
	if d == Vector3.ZERO and is_zero_approx(dphi):
		return
	var mul: float = 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		mul = 2.0
	elif Input.is_key_pressed(KEY_ALT):
		mul = 0.25
	var step: float = _ik_move_speed * mul * delta
	_target[0] += d.x * step
	_target[1] += d.y * step
	if _jc >= 3:
		_target[2] += d.z * step
	if _jc >= 4:
		_target[3] += dphi * _ik_rot_speed * mul * delta
	_recompute()


## 当前按键组合对应的移动方向（机器人坐标，各分量 -1/0/1）
func _key_move_axis() -> Vector3:
	var v: Vector3 = Vector3.ZERO
	if _config_type == 0:
		# 2 轴：X 用 A/D，高度（机器人 Y）用 W/S 与 ↑↓
		v.x += _axis_pair(KEY_D, KEY_A)
		v.y += _axis_pair(KEY_W, KEY_S)
		v.y += _axis_pair(KEY_UP, KEY_DOWN)
		v.y = clampf(v.y, -1.0, 1.0)
		return v
	# 3/4 轴：WASD 在水平面，↑↓ 管高度
	v.x = _axis_pair(KEY_W, KEY_S)
	v.y = _axis_pair(KEY_A, KEY_D)
	v.z = _axis_pair(KEY_UP, KEY_DOWN)
	return v


## 4 轴腕部姿态角：Q/E
func _key_phi_axis() -> float:
	return _axis_pair(KEY_E, KEY_Q)


## 一对按键 -> -1/0/1
func _axis_pair(pos_key: int, neg_key: int) -> float:
	var v: float = 0.0
	if Input.is_key_pressed(pos_key):
		v += 1.0
	if Input.is_key_pressed(neg_key):
		v -= 1.0
	return v
