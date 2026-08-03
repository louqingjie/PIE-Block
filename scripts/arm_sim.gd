extends Control
## 机械臂逆解 3D 仿真视图。
##
## MCU 是 FK、IK、构形诊断和关节限位的唯一权威。
## PC 侧 fk_chain 只把 MCU 返回的关节角转换为绘图 Transform，并校验渲染模型。
##
## 坐标系约定：机器人 X/Y 为水平面、Z 为高度，映射到 Godot (x, z, -y)。
## 单位：机器人侧 mm，Godot 侧 mm * MM_TO_UNIT。

# ------------------------------------------------------------------ 节点路径
const P_VIEWPORT: NodePath = "Sim/SubViewport"
const P_WORLD: NodePath = "Sim/SubViewport/World"
const P_CAMERA: NodePath = "Sim/SubViewport/World/Camera3D"
const P_GRID: NodePath = "Sim/SubViewport/World/Grid"
const P_VEHICLE: NodePath = "Sim/SubViewport/World/VehicleRoot"
const P_ARM_MOUNT: NodePath = "Sim/SubViewport/World/VehicleRoot/ArmMount"
const P_AXES: NodePath = "Sim/SubViewport/World/VehicleRoot/ArmMount/Axes"
const P_ARM_ROOT: NodePath = "Sim/SubViewport/World/VehicleRoot/ArmMount/ArmRoot"
const P_TRAIL: NodePath = "Sim/SubViewport/World/Trail"
const P_GHOST: NodePath = "Sim/SubViewport/World/VehicleRoot/ArmMount/TargetGhost"
const P_PARAMS: NodePath = "SidePanel/Scroll/Params"
const P_SIDE_PANEL: NodePath = "SidePanel"
const P_TOP_PANEL: NodePath = "TopPanel"
const P_STATUS: NodePath = "StatusPanel/Status"
const P_MODE: NodePath = "TopPanel/HBox/Mode"
const P_BACK: NodePath = "TopPanel/HBox/Back"
const P_CHASSIS: NodePath = "Sim/SubViewport/World/VehicleRoot/Chassis"
const P_GRIPPER: NodePath = "Sim/SubViewport/World/VehicleRoot/ArmMount/Gripper"
const P_CHASSIS_TOGGLE: NodePath = "TopPanel/HBox/ChassisToggle"
const P_TRAIL_TOGGLE: NodePath = "TopPanel/HBox/TrailToggle"
const P_TRAIL_CLEAR: NodePath = "TopPanel/HBox/TrailClear"
const P_RESET_VIEW: NodePath = "TopPanel/HBox/ResetView"
const P_FOLLOW_TOGGLE: NodePath = "TopPanel/HBox/FollowToggle"
const P_RESET_POSE: NodePath = "TopPanel/HBox/ResetPose"
const P_CONFIG_LABEL: NodePath = "TopPanel/HBox/ConfigLabel"
const P_HINT: NodePath = "HintLabel"
const P_PHONE_TOGGLE: NodePath = "TopPanel/HBox/PhoneToggle"
const P_REACH_MESH: NodePath = "Sim/SubViewport/World/VehicleRoot/ArmMount/ReachMesh"

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
## 操控模式的固定步进周期（ms），与生成的 C 主循环 LOOP_PERIOD_MS 一致
const SIM_STEP_MS: float = 10.0
## 摇杆满偏值（与 C 端 valueOfRoker 量程一致）
const ROKER_FULL: float = 2047.0
const SPEED_SCALE_DEFAULT: float = 2.0
const TURN_RATE_DEFAULT: float = 360.0
const CAM_FOLLOW_LERP: float = 6.0
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
## 顶层模式。关节标定已经并入 IK 编辑，不再单独占一个模式。
enum Mode {IK = 0, PRESET = 1, CONTROLLER = 2}

# ------------------------------------------------------------------ 运动学求解器
var _cg: CodeGenEngineerIK = CodeGenEngineerIK.new()
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const REMOTE_INPUT = preload("res://scripts/sim_remote_input.gd")
const IK_SIM_LINK = preload("res://scripts/ik_sim_link.gd")
const IK_SIM_PROTOCOL = preload("res://scripts/ik_sim_protocol.gd")
const TOOLCHAIN = preload("res://scripts/toolchain.gd")
const PHONE_RECEIVER = preload("res://scripts/phone_pose_receiver.gd")
const ARM_WORKSPACE = preload("res://scripts/arm_workspace.gd")

# ------------------------------------------------------------------ 配置状态
var _cfg: Dictionary = {}
var _engineer: Dictionary = {}
var _editable: bool = true
## 始终保留 6 个槽位，减少关节数后再次增加不会丢失隐藏配置。
var _joint_slots: Array = []
var _io_init_patch: Dictionary = {}
var _jc: int = 2
var _joints: Array = []
var _presets: Array = []
var _gripper: Dictionary = {}
## MCU HELLO 返回的独立姿态任务可控掩码。
var _orientation_mask: Dictionary = {"roll": false, "pitch": false, "yaw": false}
var _orientation_reason: Dictionary = {}
## 判定「末端到位」的容差(mm)。数值解不会精确命中，
## 超过这个距离才认为目标够不着（连杆染红 + 状态行提示）。
const IK_REACHED_TOL: float = 2.0

# ------------------------------------------------------------------ 运行状态
var _mode: int = Mode.IK
## 末端目标使用 ArmMount 局部坐标；姿态仅在 UI 边界表示为 RPY。
var _target: Dictionary = {"position": Vector3.ZERO, "rpy": Vector3.ZERO}
## 当前各关节角度（度），已过限位
var _angles: Array = []
## 正解模式准备发给 MCU 的角度；不得用于绘图或“实际状态”显示。
var _requested_angles: Array = []
## 上一帧逆解是否可达（操控模式的状态显示需要）
var _reachable: bool = true
## 连续 stalled 周期计数：达阈值后把目标吸到 MCU 实际末端，避免操作手调不回来。
var _stall_count: int = 0
## 被限位钳住的关节掩码
var _clamped: Array = []
## 逆解编辑页中关节调整滑块给出的姿态
var _fk_angles: Array = [0.0, 0.0, 0.0, 0.0]
## 逆解模式键盘移动速度（mm/s 与 °/s）
var _ik_move_speed: float = KEY_MOVE_MM_PER_SEC
var _ik_rot_speed: float = KEY_ROT_DEG_PER_SEC
## 操控模式的完整遥控器状态及双模式固件运行状态。
var _remote_snapshot: Dictionary = REMOTE_INPUT.compose({}, {})
var _inverse_mode: bool = true
var _mode_key_held: bool = false
var _home_key_held: bool = false
var _home_command_pending: bool = false
var _gripper_open: bool = true
var _gripper_key_held: bool = false
var _duty_chassis: Array = [0, 0, 0, 0]
var _base_speed: int = 0
var _turn_speed: int = 0
var _duty_aux_motor: Array = [0, 0, 0, 0, 0, 0, 0, 0]
var _duty_aux_servo: Array = [750.0, 750.0, 750.0, 750.0, 750.0, 750.0, 750.0, 750.0]
var _duty_aux_main_servo: Array = [750.0, 750.0]
## 操控模式的时间累加器（把不定 delta 切成固定 10ms 步）
var _sim_accum: float = 0.0
## 底盘世界位姿。位置使用 Godot 单位；航向绕 +Y，正值表示向机器人左侧转。
var _vehicle_pos: Vector3 = Vector3.ZERO
var _vehicle_heading: float = 0.0
var _wheel_spin: Array = [0.0, 0.0, 0.0, 0.0]
var _speed_scale: float = SPEED_SCALE_DEFAULT
var _turn_rate: float = TURN_RATE_DEFAULT
## 预设点位巡航：>=0 表示正在播放第 N 个点位
var _play_idx: int = -1
var _play_t: float = 0.0
var _play_from: Dictionary = {}
var _mcu_link: IkSimLink = null
var _mcu_ready: bool = false
var _mcu_hello_validated: bool = false
var _mcu_status: String = "未连接 MCU 求解器"
var _mcu_fingerprint: String = ""
var _mcu_firmware_type: String = "未知"
var _mcu_fingerprint_ok: bool = false
var _solver_stale: bool = true
var _solver_reconnect_deadline_ms: int = 0
var _solver_reconnect_generation: int = 0
var _mcu_actual: Dictionary = {"position": Vector3.ZERO, "rpy": Vector3.ZERO}
var _mcu_diagnostics: Dictionary = {}
var _render_model_mismatch: bool = false

# ------------------------------------------------------------------ 手机传感器
var _phone_receiver: PHONE_RECEIVER = null
var _phone_enabled: bool = false
var _phone_clamped_axes: Array[String] = []
var _phone_active: bool = false
var _phone_active_timer: int = 0

# ------------------------------------------------------------------ 视图状态
var _cam_yaw: float = -0.7
var _cam_pitch: float = 0.5
var _cam_dist: float = 5.0
var _cam_pivot: Vector3 = Vector3.ZERO
var _cam_focus_local: Vector3 = Vector3.ZERO
var _cam_heading: float = 0.0
var _follow: bool = true
var _orbiting: bool = false
var _panning: bool = false

# ------------------------------------------------------------------ 场景对象
var _link_nodes: Array = [] # MeshInstance3D，每段连杆
var _joint_nodes: Array = [] # MeshInstance3D，每个关节球
var _tip_node: MeshInstance3D = null
var _trail_points: Array = [] # Vector3（Godot 坐标）
var _trail_enabled: bool = true
var _chassis_visible: bool = true
## 夹爪几何张开度 [0, 1]（1=张开）。夹爪是独立舵机，不进逆解。
var _grip_open: float = 1.0
## 夹爪各构件（掌座 + 两指）
var _grip_nodes: Array = []
var _wheel_nodes: Array = []
var _wheel_centers: Array = []
var _grid_step_unit: float = 1.0

# ------------------------------------------------------------------ 可达区域缓存
## 上一次扫描的体素数据与配置指纹。配置未变时直接复用。
var _reach_dirty: bool = true
var _reach_voxels: PackedVector3Array = PackedVector3Array()
var _reach_bounds: AABB = AABB()
var _reach_voxel_size: float = 10.0
var _reach_fingerprint: String = ""
var _reach_thread: Thread = null
var _reach_busy: bool = false
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
var _mat_reach: StandardMaterial3D = null
var _reach_toggle_btn: CheckButton = null
var _reach_recompute_btn: Button = null

# 参数面板控件（按模式重建）
var _sliders: Dictionary = {} # key -> HSlider
var _spins: Dictionary = {} # key -> SpinBox
var _syncing: bool = false # 滑块 <-> 数值框互相赋值时抑制回环
var _diagnostic_labels: Array[Label] = []


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
	_mcu_link = IK_SIM_LINK.new()
	add_child(_mcu_link)
	_mcu_link.connected.connect(_on_mcu_connected)
	_mcu_link.state_received.connect(_on_mcu_state)
	_mcu_link.link_error.connect(_on_mcu_error)
	_mcu_link.link_warning.connect(_on_mcu_warning)
	_mcu_link.disconnected.connect(_on_mcu_disconnected)
	# 手机传感器接收器（默认不启动，用户点按钮后才开始监听）
	_phone_receiver = PHONE_RECEIVER.new()
	add_child(_phone_receiver)
	_phone_receiver.pose_received.connect(_on_phone_pose_received)
	_phone_receiver.phone_connected.connect(_on_phone_connected)
	_phone_receiver.phone_disconnected.connect(_on_phone_disconnected)
	_phone_receiver.reset_requested.connect(_on_phone_reset_requested)
	# The simulator build workflow reconnects after flashing. Entering controller
	# mode also reconnects, but opening the configuration page must not launch a
	# pipe process against an arbitrary serial device.


func _connect_ui() -> void:
	var back: Node = get_node_or_null(P_BACK)
	if back is BaseButton:
		back.pressed.connect(_on_back_pressed)
	var mode: Node = get_node_or_null(P_MODE)
	if mode is OptionButton:
		mode.item_selected.connect(_on_mode_selected)
	var solver_button := Button.new()
	solver_button.text = "编译并烧录 MCU 求解器"
	solver_button.tooltip_text = "构型变化后必须重新生成并烧录无 IO 求解器固件"
	solver_button.pressed.connect(func() -> void: solver_build_requested.emit())
	var reach_button := CheckButton.new()
	reach_button.text = "可达"
	reach_button.button_pressed = false
	reach_button.toggled.connect(_on_reach_toggled)
	_reach_toggle_btn = reach_button
	var reach_recompute_button := Button.new()
	reach_recompute_button.text = "重新计算可达"
	reach_recompute_button.tooltip_text = "参数变化后重新扫描机械臂可达区域"
	reach_recompute_button.pressed.connect(_on_reach_recompute_pressed)
	_reach_recompute_btn = reach_recompute_button
	var top: Node = get_node_or_null("TopPanel/HBox")
	if top is Container:
		top.add_child(solver_button)
		top.add_child(reach_button)
		top.add_child(reach_recompute_button)
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
	var ft: Node = get_node_or_null(P_FOLLOW_TOGGLE)
	if ft is BaseButton:
		ft.toggled.connect(_on_follow_toggled)
	var rp: Node = get_node_or_null(P_RESET_POSE)
	if rp is BaseButton:
		rp.pressed.connect(_reset_vehicle_pose)
	var pt: Node = get_node_or_null(P_PHONE_TOGGLE)
	if pt is BaseButton:
		pt.toggled.connect(_toggle_phone_sensor)
		pt.set_meta("created", false)

# ------------------------------------------------------------------ 外部接口
## context = {ik, engineer, editable}。工程配置只用于 IO 冲突与初始化联动。
func set_config(context: Dictionary) -> void:
	_cfg = IK_CONFIG.normalize(context.get("ik", {}))
	_engineer = (context.get("engineer", {}) as Dictionary).duplicate(true)
	_editable = bool(context.get("editable", true))
	if is_inside_tree():
		_apply_config()


## 返回配置界面时发出（由 ui.gd 连接）
signal closed
signal solver_build_requested
## 返回结构化逆解配置与需要写回工程页的扩展口初始化变更。
signal config_changed(payload: Dictionary)


func prepare_solver_build() -> void:
	_cancel_solver_reconnect()
	_mcu_ready = false
	_mcu_hello_validated = false
	_mcu_status = "正在编译并烧录 MCU 求解器，机械臂操控已冻结"
	if _mcu_link != null:
		_mcu_link.stop()
	_update_status()


func _on_back_pressed() -> void:
	closed.emit()


func _emit_config_changed() -> void:
	if not _editable:
		return
	_cfg["joint_count"] = _jc
	_cfg["joints"] = _joints.duplicate(true)
	_cfg["presets"] = _presets.duplicate(true)
	_cfg["gripper"] = _gripper.duplicate(true)
	_cfg = IK_CONFIG.normalize(_cfg)
	_gripper = (_cfg["gripper"] as Dictionary).duplicate(true)
	_refresh_diagnostics()
	config_changed.emit({
		"ik": _cfg.duplicate(true),
		"io_init": _io_init_patch.duplicate(true),
	})
	_io_init_patch.clear()


# ------------------------------------------------------------------ 配置解析
func _apply_config() -> void:
	_cfg = IK_CONFIG.normalize(_cfg)
	_jc = clampi(int(_cfg.get("joint_count", 2)), 2, _cg.MAX_JOINTS)
	_joint_slots.clear()
	for i in range(IK_CONFIG.MAX_JOINTS):
		if i < (_cfg["joints"] as Array).size():
			_joint_slots.append((_cfg["joints"][i] as Dictionary).duplicate(true))
		else:
			_joint_slots.append(IK_CONFIG.default_joint(i))
	_joints = _joint_slots.slice(0, _jc)
	_presets = _cfg.get("presets", [])
	_gripper = (_cfg.get("gripper", IK_CONFIG.default_gripper()) as Dictionary).duplicate(true)
	# 预设点位表补齐到 4 项，便于「存为预设 N」直接写入
	while _presets.size() < 4:
		_presets.append(IK_CONFIG.default_preset(_presets.size()))
	_orientation_mask = {"roll": false, "pitch": false, "yaw": false}
	_orientation_reason = {"roll": "等待 MCU 构形诊断", "pitch": "等待 MCU 构形诊断",
		"yaw": "等待 MCU 构形诊断"}
	_solver_stale = true
	_mcu_ready = false
	_mcu_hello_validated = false
	_home_command_pending = false
	_stall_count = 0
	_reach_dirty = true
	# 初始姿态：与生成的 C 代码上电起点一致
	_fk_angles = _cg._joint_home_angles(_joints)
	_target = _tip_target(_fk_angles.slice(0, _jc))
	_angles = _fk_angles.slice(0, _jc)
	_requested_angles = _angles.duplicate()
	_inverse_mode = true
	_mode_key_held = false
	_home_key_held = false
	_gripper_open = bool(_gripper.get("initial_open", true))
	_gripper_key_held = false
	_grip_open = 1.0 if _gripper_open else 0.0
	_duty_chassis = [0, 0, 0, 0]
	_base_speed = 0
	_turn_speed = 0
	_duty_aux_motor = [0, 0, 0, 0, 0, 0, 0, 0]
	_duty_aux_servo = [750.0, 750.0, 750.0, 750.0, 750.0, 750.0, 750.0, 750.0]
	_duty_aux_main_servo = [750.0, 750.0]
	_clear_trail()
	_update_arm_mount()
	_rebuild_arm()
	_rebuild_static_geometry()
	_rebuild_params()
	_reset_vehicle_pose(false)
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


func _update_config_label() -> void:
	var label: Node = get_node_or_null(P_CONFIG_LABEL)
	if label is Label:
		label.text = "%d 关节 ｜ 总臂长 %.0f mm" % [_jc, _arm_reach()]


# ------------------------------------------------------------------ 坐标映射
## 机器人坐标 (mm) -> Godot 坐标（已缩放）
func _robot_to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y) * MM_TO_UNIT


func _vec_to_godot(v: Vector3) -> Vector3:
	return _robot_to_godot(v.x, v.y, v.z)


func _arm_reach() -> float:
	var total: float = 0.0
	for value in _cg.joint_lengths(_joints, _jc):
		total += absf(float(value))
	return total


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
	_mat_reach = StandardMaterial3D.new()
	_mat_reach.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_reach.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_reach.vertex_color_use_as_albedo = true
	_mat_reach.no_depth_test = false


func _make_material(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# ------------------------------------------------------------------ 机械臂几何（程序化）
## 按逐关节连杆长度重建连杆与关节，参数改变即重新生成
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
	var seg_count: int = _jc
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
	# 非对称目标块同时显示目标位置和完整末端方向。
	var ghost: MeshInstance3D = get_node_or_null(P_GHOST)
	if ghost is MeshInstance3D:
		var gm: BoxMesh = BoxMesh.new()
		gm.size = Vector3(48.0, 22.0, 14.0) * MM_TO_UNIT
		ghost.mesh = gm
		ghost.material_override = _mat_ghost
	_rebuild_gripper()


# ------------------------------------------------------------------ 夹爪
## 夹爪 = 掌座 + 两根手指。它的朝向就是末端姿态角的可视化：
## 掌座沿末端连杆方向伸出，两指在臂的工作平面内对开。
## 开合由独立舵机状态驱动，但不参与逆解，也不计入本构型的关节数。
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


## 按通用 FK 返回的末端姿态摆放夹爪。
func _render_gripper(chain: Dictionary, pts: Array) -> void:
	if _grip_nodes.size() < 3 or pts.size() < 2:
		return
	var tip: Vector3 = pts[pts.size() - 1]
	var tip_basis: Basis = chain["tip_basis"]
	var approach: Vector3 = _vec_to_godot(tip_basis * Vector3.RIGHT).normalized()
	var open_dir: Vector3 = _vec_to_godot(tip_basis * Vector3.UP)
	open_dir -= approach * open_dir.dot(approach)
	if open_dir.length() < 1e-6:
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


# ------------------------------------------------------------------ 静态辅助几何
## 网格地面 + 坐标轴 + 底盘。
func _rebuild_static_geometry() -> void:
	_build_grid()
	_build_axes()
	_build_chassis()
	_render_vehicle()


# ------------------------------------------------------------------ 底盘
## 底盘以 VehicleRoot 为中心绘制；ArmMount 单独表达机械臂安装偏移。
func _build_chassis() -> void:
	var root: Node3D = get_node_or_null(P_CHASSIS)
	if root == null:
		return
	_wheel_nodes.clear()
	_wheel_centers.clear()
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
	# 高度基准：VehicleRoot 位于底盘板顶面中心，机械臂安装高度由 ArmMount 处理。
	# 轮心：从地面往上一个轮半径。地面在板顶面下方 _chassis_height 处，
	# 故轮心局部高度 = -(车高 - 轮半径)。这样车高降到贴地时轮子也跟着沉，
	# 而不是固定挂在板下某个深度、把自己埋到地面以下。
	var axle_up: float = - (_chassis_height - wheel_r)
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
	# 顺序固定为左前、左后、右前、右后，便于按左右轮组累计转角。
	for sy in [1.0, -1.0]:
		for sx in [1.0, -1.0]:
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
			var center: Vector3 = _chassis_point(
				sx * half_wb, sy * (deck_w * 0.5 + WHEEL_WIDTH_MM * 0.5), axle_up)
			wheel.transform = Transform3D(_wheel_basis(), center)
			root.add_child(wheel)
			_wheel_nodes.append(wheel)
			_wheel_centers.append(center)
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
					- CHASSIS_DECK_THICK_MM - strut_h * 0.5)
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
func _chassis_point(fwd: float, side: float, up: float) -> Vector3:
	return _robot_to_godot(fwd, side, up)


func _update_arm_mount() -> void:
	var arm_mount: Node3D = get_node_or_null(P_ARM_MOUNT)
	if arm_mount != null:
		arm_mount.position = _robot_to_godot(_mount.x, _mount.y, _mount.z)


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
	var span: float = _arm_reach()
	if _chassis_visible:
		span = maxf(span, maxf(
			_chassis_deck_len * 0.5,
			_chassis_track * 0.5 + WHEEL_WIDTH_MM) * 1.6)
	# 步长对齐到 10mm 的整数倍，读数更好认
	var half: int = 8
	var step_mm: float = max(10.0, round(span / float(half) / 10.0) * 10.0)
	_grid_step_unit = step_mm * MM_TO_UNIT
	var lim: float = float(half) * step_mm
	# 网格位于 VehicleRoot 的世界高度：显示底盘时在轮下沿，隐藏时在机械臂底座平面。
	var plane: float = - _chassis_height if _chassis_visible else _mount.z
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
		im.surface_add_vertex(_grid_point(t, -lim, plane))
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(t, lim, plane))
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(-lim, t, plane))
		im.surface_set_color(minor)
		im.surface_add_vertex(_grid_point(lim, t, plane))
	im.surface_end()
	grid.mesh = im
	_update_grid_origin()


## 悬挂间隙（mm）：车高扣掉固定轮径与板厚后剩下的那段。
## 车高 >= 轮径+板厚 时有悬挂；更低时间隙为 0（支臂消失），
## 轮子跟着板一起下沉，一直可以降到板贴地。
func _wheel_gap() -> float:
	return maxf(_chassis_height - CHASSIS_DECK_THICK_MM - WHEEL_RADIUS_MM * 2.0, 0.0)


## 地面网格顶点：(前后, 左右, 高度) -> Godot 坐标。
## 与 _chassis_point 同一套映射（但不含 _mount 平移）。
func _grid_point(fwd: float, side: float, up: float) -> Vector3:
	return _robot_to_godot(fwd, side, up)


## 地面高度（机器人 Z，mm）：显示底盘时取轮下沿，否则就是底座平面。
## 轮子悬在底盘板下方，故轮下沿 = 板顶面 - 板厚 - 间隙 - 2×轮半径。
func _ground_level() -> float:
	if not _chassis_visible:
		return 0.0
	# 底盘高度就是地面到板顶面的距离，故直接用它
	return - (_mount.z + _chassis_height)


func _build_axes() -> void:
	var axes: MeshInstance3D = get_node_or_null(P_AXES)
	if not axes is MeshInstance3D:
		return
	var len_mm: float = _arm_reach() * 0.45
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
		im.surface_set_color(d[1])
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_set_color(d[1])
		im.surface_add_vertex(_vec_to_godot(d[0]))
	im.surface_end()
	axes.mesh = im


# ------------------------------------------------------------------ 求解 & 渲染
func _tip_target(angles: Array) -> Dictionary:
	var chain: Dictionary = _cg.fk_chain(angles, _joints, _jc)
	var pts: Array = chain["points"]
	var tip: Vector3 = pts[pts.size() - 1]
	return {"position": tip, "rpy": _cg.tip_rpy_deg(chain)}


func _target_basis() -> Basis:
	return _cg.basis_from_rpy_deg(_target["rpy"])


## 依据当前模式算出关节角，钳位，然后更新 3D
func _recompute() -> void:
	if _mcu_ready:
		if _mode == Mode.CONTROLLER and not _inverse_mode:
			_mcu_link.send_joints(_requested_angles, _jc)
		elif not _home_command_pending:
			_mcu_link.send_pose(_target["position"], _target["rpy"])
	_render_arm()
	_sync_param_widgets()
	_update_status()


## 按 _angles 更新连杆/关节的 Transform3D
func _render_arm() -> void:
	var chain: Dictionary = _cg.fk_chain(_angles, _joints, _jc)
	var frames: Array = chain["points"]
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
	# 目标块始终显示；其长边沿目标夹爪 Roll 轴，完整反映目标 RPY。
	var ghost: MeshInstance3D = get_node_or_null(P_GHOST)
	if ghost is MeshInstance3D:
		var target_basis: Basis = _target_basis()
		var bx: Vector3 = _vec_to_godot(target_basis.x).normalized()
		var by: Vector3 = _vec_to_godot(target_basis.y).normalized()
		var bz: Vector3 = bx.cross(by).normalized()
		ghost.transform = Transform3D(Basis(bx, by, bz),
			_vec_to_godot(_target["position"]))
		ghost.visible = true
	_render_gripper(chain, pts)
	_push_trail(_arm_point_to_world(pts[pts.size() - 1]))


func _arm_point_to_world(point: Vector3) -> Vector3:
	var arm_mount: Node3D = get_node_or_null(P_ARM_MOUNT)
	return arm_mount.to_global(point) if arm_mount != null else point


## 把单位长度沿 +Y 的圆柱摆到 a->b 段上
func _segment_transform(a: Vector3, b: Vector3) -> Transform3D:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	if length < 1e-6:
		# 零长段退化为不可见的极小段，避免 basis 退化
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


# ------------------------------------------------------------------ 可达区域
func _on_reach_toggled(on: bool) -> void:
	var mesh: Node = get_node_or_null(P_REACH_MESH)
	if mesh is MultiMeshInstance3D:
		mesh.visible = on
	if not on:
		return
	if _reach_busy:
		return # 配置未变且有缓存 -> 直接渲染
	if not _reach_dirty and _reach_voxels.size() > 0:
		_render_reach_volume()
		return
	_start_reach_compute()


func _on_reach_recompute_pressed() -> void:
	if _reach_busy:
		return
	_reach_dirty = true
	_reach_voxels = PackedVector3Array()
	if _reach_toggle_btn != null:
		_reach_toggle_btn.set_pressed_no_signal(true)
	_on_reach_toggled(true)


## 在子线程中执行关节空间扫描，完成后回主线程渲染。
func _start_reach_compute() -> void:
	if _reach_busy:
		return
	_reach_busy = true
	if _reach_toggle_btn != null:
		_reach_toggle_btn.text = "计算中…"
		_reach_toggle_btn.disabled = true
	if _reach_recompute_btn != null:
		_reach_recompute_btn.disabled = true
	# 捕获配置快照，避免子线程读到主线程的并发修改
	var joints: Array = _joints.duplicate(true)
	var jc: int = _jc
	_reach_thread = Thread.new()
	_reach_thread.start(func() -> void:
		var ws := ARM_WORKSPACE.new()
		var result: Dictionary = ws.compute_workspace(joints, jc)
		_render_reach_volume.call_deferred(result, ws.fingerprint(joints, jc))
	)


## 子线程完成后在主线程调用：缓存结果并构建 MultiMesh。
func _render_reach_volume(result: Dictionary = {}, fp: String = "") -> void:
	if result.is_empty():
		# 从缓存渲染
		if _reach_voxels.is_empty():
			_finish_reach_toggle()
			return
	else:
		_reach_voxels = result["voxels"]
		_reach_bounds = result["bounds"]
		_reach_voxel_size = result["voxel_size"]
		_reach_fingerprint = fp
		_reach_dirty = false
	# 等待线程结束
	if _reach_thread != null:
		_reach_thread.wait_to_finish()
		_reach_thread = null
	_reach_busy = false
	var mesh: MultiMeshInstance3D = get_node_or_null(P_REACH_MESH) as MultiMeshInstance3D
	if mesh == null:
		return
	if _reach_voxels.is_empty():
		mesh.multimesh = null
		_finish_reach_toggle()
		return
	var mm := MultiMesh.new()
	# 用小球显示离散采样点，避免立方体体素沿视线重叠后形成实体色块。
	var point := SphereMesh.new()
	point.radius = 0.018
	point.height = 0.036
	point.radial_segments = 4
	point.rings = 2
	mm.mesh = point
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var n: int = _reach_voxels.size()
	mm.instance_count = n
	# 高度色阶：Z 最低=蓝，中间=绿，最高=红。分两段线性插值，避免 HSV 色相造成突兀色带。
	var z_min: float = _reach_bounds.position.z
	var z_range: float = maxf(_reach_bounds.size.z, 1.0)
	for i in range(n):
		var v: Vector3 = _reach_voxels[i]
		var t: float = clampf((v.z - z_min) / z_range, 0.0, 1.0)
		var color: Color
		if t < 0.5:
			color = Color(0.18, 0.42, 0.95).lerp(Color(0.18, 0.88, 0.38), t * 2.0)
		else:
			color = Color(0.18, 0.88, 0.38).lerp(Color(0.95, 0.22, 0.16), (t - 0.5) * 2.0)
		# 体素会沿视线重叠，透明度过高会让同色叠加饱和成大片纯蓝/纯红。
		color.a = 0.12
		mm.set_instance_color(i, color)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _robot_to_godot(v.x, v.y, v.z)))
	mesh.multimesh = mm
	mesh.material_override = _mat_reach
	_finish_reach_toggle()


func _finish_reach_toggle() -> void:
	if _reach_toggle_btn != null:
		_reach_toggle_btn.text = "可达"
		_reach_toggle_btn.disabled = false
	if _reach_recompute_btn != null:
		_reach_recompute_btn.disabled = false


func _on_chassis_toggled(on: bool) -> void:
	_chassis_visible = on
	_build_chassis()
	_render_vehicle()
	# 网格代表地面，高度随底盘显隐而变
	_build_grid()
	_refresh_camera_focus()
	_update_status()


# ------------------------------------------------------------------ 手机传感器注入
## 手机位姿到达：钳位 + orientation_mask 过滤后写入 _target
func _on_phone_pose_received(position: Vector3, rpy: Vector3) -> void:
	if not _mcu_ready:
		return
	# 标记手机活跃，200ms 内忽略键盘/手柄的位置与姿态输入
	_phone_active = true
	_phone_active_timer = 200
	# 用 receiver 的 check_clamp 做统一钳位
	var result: Dictionary = _phone_receiver.check_clamp(position, rpy, _orientation_mask)
	var clamped_pos: Vector3 = result["position"]
	var clamped_rpy: Vector3 = result["rpy"]
	var clamped_axes: Array[String] = result["clamped_axes"]
	# 过滤 MCU 不支持的姿态轴
	if not bool(_orientation_mask.get("roll", false)):
		clamped_rpy.x = _target["rpy"].x
	if not bool(_orientation_mask.get("pitch", false)):
		clamped_rpy.y = _target["rpy"].y
	if not bool(_orientation_mask.get("yaw", false)):
		clamped_rpy.z = _target["rpy"].z
	_phone_clamped_axes = clamped_axes
	if not clamped_axes.is_empty():
		# 通知手机震动
		_phone_receiver.send_message({"type": "clamp_warning", "axes": clamped_axes})
	_target = {"position": clamped_pos, "rpy": clamped_rpy}
	_recompute()


func _on_phone_connected() -> void:
	_update_status()


func _on_phone_disconnected() -> void:
	_phone_active = false
	_phone_active_timer = 0
	_update_status()


func _on_phone_reset_requested() -> void:
	# 重置原点时把当前末端位姿同步为目标，避免跳跃
	if _mcu_ready:
		_target = _mcu_actual.duplicate(true)
		_recompute()


## 启动/停止手机传感器监听
func _toggle_phone_sensor(enabled: bool) -> void:
	_phone_enabled = enabled
	if enabled:
		_phone_receiver.start_listening()
	else:
		_phone_receiver.stop_listening()
		_phone_active = false
		_phone_active_timer = 0
	_rebuild_params()
	_update_status()


# ------------------------------------------------------------------ 状态提示
func _update_status() -> void:
	var label: Node = get_node_or_null(P_STATUS)
	if not label is Label:
		return
	var lines: Array = []
	var tip: Dictionary = _mcu_actual if _mcu_ready else _tip_target(_angles)
	var tip_position: Vector3 = tip["position"]
	var tip_rpy: Vector3 = tip["rpy"]
	lines.append("实际末端 X=%.1f Y=%.1f Z=%.1f mm  R=%.1f° P=%.1f° Y=%.1f°" % [
		tip_position.x, tip_position.y, tip_position.z, tip_rpy.x, tip_rpy.y, tip_rpy.z])
	if (_mode == Mode.CONTROLLER and _inverse_mode) or _mode == Mode.IK:
		var target_position: Vector3 = _target["position"]
		var target_rpy: Vector3 = _target["rpy"]
		lines.append("逆解目标 X=%.1f Y=%.1f Z=%.1f mm  R=%.1f° P=%.1f° Y=%.1f°" % [
			target_position.x, target_position.y, target_position.z,
			target_rpy.x, target_rpy.y, target_rpy.z])
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
	lines.append(_gripper_control_text())
	if _mode == Mode.CONTROLLER or _mcu_ready or _solver_stale:
		lines.append("MCU 求解器: %s" % _mcu_status)
		lines.append("MCU 固件=%s  指纹=%s%s" % [_mcu_firmware_type,
			"匹配" if _mcu_fingerprint_ok else "未匹配",
			" (%s)" % _mcu_fingerprint if not _mcu_fingerprint.is_empty() else ""])
		if _mcu_ready:
			lines.append("MCU %s %s  DOF 位置=%d 姿态=%d  RTT=%d ms  CRC=%d 丢弃=%d  位置误差=%.2f mm%s" % [
				str(_mcu_diagnostics.get("port", "")),
				str(_mcu_diagnostics.get("link_type", "unknown")),
				int(_mcu_diagnostics.get("position_dof", 0)),
				int(_mcu_diagnostics.get("orientation_dof", 0)),
				int(_mcu_diagnostics.get("latency_ms", 0)),
				int(_mcu_diagnostics.get("crc_errors", 0)),
				int(_mcu_diagnostics.get("dropped_sequences", 0)),
				float(_mcu_diagnostics.get("position_error", 0.0)),
				"  渲染模型不一致" if _render_model_mismatch else ""])
			var orientation_error: Vector3 = _mcu_diagnostics.get(
				"orientation_error", Vector3.ZERO)
			lines.append("MCU 状态 [%s]  姿态误差 R=%.2f° P=%.2f° Y=%.2f°" % [
				_mcu_status_flags_text(int(_mcu_diagnostics.get("status", 0))),
				orientation_error.x, orientation_error.y, orientation_error.z])
	if _phone_enabled:
		if _phone_receiver.has_phone():
			lines.append("手机传感器 已连接 %s" % _phone_receiver.client_info)
			lines.append("手机原始 P=%s RPY=%s" % [
				str(_phone_receiver.last_phone_position.round()),
				str(_phone_receiver.last_phone_rpy.round())])
			if not _phone_clamped_axes.is_empty():
				lines.append("手机输入超界轴: %s" % ", ".join(_phone_clamped_axes))
		else:
			var url: String = _phone_receiver.get_connection_url()
			lines.append("手机传感器等待连接  %s" % url)
	if _mode == Mode.CONTROLLER:
		var roker: Array = _remote_snapshot.get("valueOfRoker", [[0, 0], [0, 0]])
		var pad_name: String = str(_remote_snapshot.get("pad_name", ""))
		lines.append("遥控 %s ｜ %s" % ["逆解" if _inverse_mode else "正解",
			"键盘" if pad_name.is_empty() else pad_name])
		lines.append("左摇杆 [%d, %d]  右摇杆 [%d, %d]  按键 [%s]" % [
			roker[0][0], roker[0][1], roker[1][0], roker[1][1],
			", ".join(REMOTE_INPUT.pressed_names(_remote_snapshot))])
		var enabled_orientation: Array[String] = []
		for name in ["roll", "pitch", "yaw"]:
			if bool(_orientation_mask.get(name, false)):
				enabled_orientation.append(name.capitalize())
		var active_orientation_inputs: Array[String] = _active_orientation_inputs()
		lines.append("姿态可控 [%s]  姿态输入 [%s]  回初始角 %s%s" % [
			", ".join(enabled_orientation) if not enabled_orientation.is_empty() else "无",
			", ".join(active_orientation_inputs) if not active_orientation_inputs.is_empty() else "无",
			"启用" if bool(_cfg.get("rocker2_home_enabled", false)) else "关闭",
			"（按下）" if _home_key_held else ""])
		lines.append("底盘占空比 L1=%d L2=%d R1=%d R2=%d" % _duty_chassis)
		var linear_mps: float = float(_base_speed) / 10000.0 * _speed_scale
		var omega_dps: float = - float(_turn_speed) / 10000.0 * _turn_rate
		lines.append("车体 X=%+.2f Y=%+.2f m  航向=%+.1f°  v=%+.2f m/s  ω=%+.1f°/s  %s" % [
			_vehicle_pos.x / (1000.0 * MM_TO_UNIT),
			- _vehicle_pos.z / (1000.0 * MM_TO_UNIT), rad_to_deg(_vehicle_heading),
			linear_mps, omega_dps, "相机跟随" if _follow else "自由视角"])
	# 可达性：与生成的 C 代码里的 ik_reachable 同义
	if _mode == Mode.CONTROLLER and not _inverse_mode:
		lines.append("遥控正解：按工程映射直接调整关节与 IO")
	elif _reachable:
		lines.append("ik_reachable = 1  目标可达")
	else:
		lines.append("ik_reachable = 0  目标无法在当前关节限位内收敛")
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
	# 夹爪朝向与状态行里的完整 RPY 互为印证。
	lines.append(_gripper_text())
	# 末端相对底盘中心的位置，判断有没有伸出车外
	if _chassis_visible:
		lines.append(_chassis_relation_text(tip_position))
	label.text = "\n".join(lines)


func _gripper_text() -> String:
	var chain: Dictionary = _cg.fk_chain(_angles, _joints, _jc)
	var rpy: Vector3 = _cg.tip_rpy_deg(chain)
	return "夹爪朝向 Roll=%+.1f° Pitch=%+.1f° Yaw=%+.1f°" % [rpy.x, rpy.y, rpy.z]


func _active_orientation_inputs() -> Array[String]:
	var active: Array[String] = []
	var keymove: Array = _cfg.get("keymove", [])
	var names: Array[String] = ["Roll", "Pitch", "Yaw"]
	for i in range(3):
		var slot: int = i + 3
		if slot >= keymove.size() or not bool(_orientation_mask.get(names[i].to_lower(), false)):
			continue
		for side in ["plus", "minus"]:
			if _remote_key(str(keymove[slot].get(side, "不使用"))):
				active.append("%s%s" % [names[i], "+" if side == "plus" else "-"])
	return active


func _gripper_control_text() -> String:
	if not bool(_gripper.get("enabled", false)):
		return "夹爪舵机 未启用（几何仅显示末端朝向）"
	var state: String = "张开" if _gripper_open else "闭合"
	return "夹爪舵机 %s  IO=%s  指令角=%+.1f°  duty=%d" % [
		state, str(_gripper.get("io", "")), _gripper_command_angle(), _gripper_duty()]


func _gripper_command_angle() -> float:
	var field: String = "open_angle" if _gripper_open else "closed_angle"
	var angle: float = _number_or(str(_gripper.get(field, "0")), 0.0)
	return -angle if str(_gripper.get("dir", "正向")) == "反向" else angle


func _gripper_duty() -> int:
	return _cg._servo_angle_to_duty(int(round(clampf(_gripper_command_angle(), -90.0, 90.0))))


## 末端相对底盘的位置描述：伸出车外多少、是否低于轮下沿
func _chassis_relation_text(tip: Vector3) -> String:
	# 末端在底盘坐标系里的位置 = 机器人坐标 + 安装偏移（高度以板顶面为 0）
	var fwd: float = tip.x + _mount.x
	var side: float = tip.y + _mount.y
	var up: float = tip.z + _mount.z
	var half_wb: float = _chassis_deck_len * 0.5
	var half_tr: float = _chassis_track * 0.5
	var parts: Array = ["末端相对底盘 前后%+.0f 左右%+.0f 高%+.0f mm" % [fwd, side, up]]
	var out_of: Array = []
	if absf(fwd) > half_wb:
		out_of.append("前后伸出 %.0f" % (absf(fwd) - half_wb))
	if absf(side) > half_tr:
		out_of.append("左右伸出 %.0f" % (absf(side) - half_tr))
	if out_of.size() > 0:
		parts.append("（超出底盘 " + " / ".join(out_of) + " mm）")
	# 地面相对板顶面的高度（up 已以板顶面为 0）
	var ground: float = - _chassis_height
	if up < ground:
		parts.append("⚠ 末端低于地面 %.0f mm（会碰地）" % (ground - up))
	return "  ".join(parts)


func _joint_limit_str(idx: int, key: String) -> String:
	if idx < _joints.size():
		var s: String = str(_joints[idx].get(key, "")).strip_edges()
		if s.is_valid_float():
			return "%.0f" % s.to_float()
	return "-90" if key == "min" else "90"


func _mcu_status_flags_text(status: int) -> String:
	var labels: Array[String] = []
	if status & IK_SIM_PROTOCOL.STATUS_REACHED:
		labels.append("已收敛")
	if status & IK_SIM_PROTOCOL.STATUS_CLAMPED:
		labels.append("触及限位")
	if status & IK_SIM_PROTOCOL.STATUS_STALLED:
		labels.append("停滞")
	if status & IK_SIM_PROTOCOL.STATUS_SINGULAR:
		labels.append("奇异")
	if status & IK_SIM_PROTOCOL.STATUS_NUMERIC_ERROR:
		labels.append("数值保护")
	if labels.is_empty() and status & IK_SIM_PROTOCOL.STATUS_OK:
		labels.append("迭代中")
	return " / ".join(labels) if not labels.is_empty() else "未知"


# ------------------------------------------------------------------ 模式切换
func _on_mode_selected(idx: int) -> void:
	_mode = idx
	if _mode == Mode.CONTROLLER and DisplayServer.get_name() != "headless":
		_connect_mcu_solver()
	_remote_snapshot = REMOTE_INPUT.compose({}, {})
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
	if _phone_enabled and _phone_receiver.has_phone():
		base += " · 手机传感器已激活"
	match _mode:
		Mode.IK:
			label.text = "%s · %s · Shift 加速 / Alt 减速" % [base, _key_hint_text()]
		Mode.CONTROLLER:
			var pad_name: String = str(_remote_snapshot.get("pad_name", ""))
			label.text = "%s · WASD 左摇杆 · IJKL 右摇杆 · 1/2/3/4 = A/B/C/D · %s" % [
				base, "未检测到手柄" if pad_name.is_empty() else pad_name]
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
	_diagnostic_labels.clear()
	match _mode:
		Mode.IK:
			_build_ik_params(params)
		Mode.PRESET:
			_build_preset_params(params)
		Mode.CONTROLLER:
			_build_controller_params(params)
	# 手机传感器面板在所有模式下都追加显示
	if _phone_enabled:
		_build_phone_params(params)


func _add_section(parent: Node, text: String) -> void:
	var sep: HSeparator = HSeparator.new()
	parent.add_child(sep)
	var l: Label = Label.new()
	l.text = text
	parent.add_child(l)


func _add_option_row(parent: Node, label_text: String, choices: Array,
		current: String, changed: Callable, disabled_values: Array = []) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(150, 0)
	for i in range(choices.size()):
		option.add_item(str(choices[i]))
		option.set_item_disabled(i, str(choices[i]) in disabled_values)
		if str(choices[i]) == current:
			option.selected = i
	option.disabled = not _editable
	option.item_selected.connect(func(index: int) -> void: changed.call(str(choices[index])))
	row.add_child(option)
	return option


func _add_config_spin(parent: Node, label_text: String, value_text: String,
		lo: float, hi: float, step: float, changed: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = clampf(value_text.to_float() if value_text.is_valid_float() else 0.0, lo, hi)
	spin.custom_minimum_size = Vector2(120, 0)
	spin.editable = _editable
	spin.value_changed.connect(func(value: float) -> void: changed.call(value))
	row.add_child(spin)
	return spin


func _add_toggle_row(parent: Node, text: String, pressed: bool, changed: Callable) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = text
	toggle.button_pressed = pressed
	toggle.disabled = not _editable
	toggle.toggled.connect(func(value: bool) -> void: changed.call(value))
	parent.add_child(toggle)
	return toggle


func _build_diagnostics(parent: Node) -> void:
	_add_section(parent, "配置检查")
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnostic_labels.append(label)
	parent.add_child(label)
	_refresh_diagnostics()
	if not _editable:
		var locked := Label.new()
		locked.text = "AI 编辑阶段：配置只读"
		parent.add_child(locked)


func _refresh_diagnostics() -> void:
	var result: Dictionary = IK_CONFIG.validate(_cfg, _engineer)
	var issues: Array = result.get("issues", [])
	var text: String = "配置有效"
	if issues.is_empty():
		text = "配置有效"
	else:
		var lines: Array[String] = []
		for issue in issues:
			lines.append("%s  %s" % ["错误" if issue.get("type", "") == "Error" else "警告",
				str(issue.get("msg", ""))])
		text = "\n".join(lines)
	for label in _diagnostic_labels:
		if is_instance_valid(label):
			label.text = text


func _build_structure_editor(parent: Node) -> void:
	_add_section(parent, "机械臂构型")
	var counts: Array = ["2", "3", "4", "5", "6"]
	_add_option_row(parent, "关节数", counts, str(_jc), _on_joint_count_config_changed)
	_add_option_row(parent, "正解/逆解切换键", IK_CONFIG.KEYS,
		str(_cfg.get("mode_switch_key", "R")), func(value: String) -> void:
			_cfg["mode_switch_key"] = value
			_emit_config_changed())
	var blocked: Array[String] = IK_CONFIG.blocked_chassis_ios(_engineer)
	for i in range(_jc):
		_add_section(parent, "关节 %d" % (i + 1))
		var used: Array[String] = blocked.duplicate()
		for j in range(_jc):
			if j != i:
				used.append(str(_joints[j].get("io", "")))
		if bool(_gripper.get("enabled", false)):
			used.append(str(_gripper.get("io", "")))
		_add_option_row(parent, "IO", IK_CONFIG.IOS, str(_joints[i].get("io", "P60")),
			func(value: String) -> void: _on_joint_option_changed(i, "io", value), used)
		_add_option_row(parent, "方向", ["正向", "反向"], str(_joints[i].get("dir", "正向")),
			func(value: String) -> void: _on_joint_option_changed(i, "dir", value))
		_add_option_row(parent, "转轴", IK_CONFIG.AXES, str(_joints[i].get("axis", "Pitch")),
			func(value: String) -> void: _on_joint_option_changed(i, "axis", value))
		for field in [
			["len", "连杆长度 mm", 0.0, 5000.0],
			["offset", "中位朝向 °", -360.0, 360.0],
			["zero", "初始角 °", -360.0, 360.0],
			["min", "最小限位 °", -360.0, 360.0],
			["max", "最大限位 °", -360.0, 360.0],
		]:
			_add_config_spin(parent, field[1], str(_joints[i].get(field[0], "")),
				field[2], field[3], 0.5,
				func(value: float) -> void: _on_joint_number_changed(i, field[0], value))
	_build_diagnostics(parent)


func _on_joint_count_config_changed(value: String) -> void:
	if not _editable:
		return
	for i in range(_joints.size()):
		_joint_slots[i] = _joints[i]
	_jc = clampi(value.to_int(), IK_CONFIG.MIN_JOINTS, IK_CONFIG.MAX_JOINTS)
	_joints = _joint_slots.slice(0, _jc)
	_cfg["joint_count"] = _jc
	_cfg["joints"] = _joints.duplicate(true)
	_mark_solver_stale()
	_refresh_after_structure_change()


func _on_joint_option_changed(index: int, field: String, value: String) -> void:
	if not _editable or index >= _joints.size():
		return
	_joints[index][field] = value
	_joint_slots[index] = _joints[index]
	if field == "io" and value in IK_CONFIG.EXPANSION_IOS:
		_io_init_patch[value] = "舵机"
		var init: Dictionary = _engineer.get("io_init", {}).duplicate(true)
		init[value] = "舵机"
		_engineer["io_init"] = init
	if field == "axis":
		_mark_solver_stale()
	_refresh_after_structure_change()


func _on_joint_number_changed(index: int, field: String, value: float) -> void:
	if not _editable or index >= _joints.size():
		return
	_joints[index][field] = str(value)
	_joint_slots[index] = _joints[index]
	if field in ["len", "zero", "min", "max"]:
		_mark_solver_stale()
	_refresh_after_structure_change()


func _refresh_after_structure_change() -> void:
	_cfg["joints"] = _joints.duplicate(true)
	_fk_angles = _cg._joint_home_angles(_joints)
	_angles = _fk_angles.slice(0, _jc)
	_requested_angles = _angles.duplicate()
	_target = _tip_target(_angles)
	_rebuild_arm()
	_rebuild_static_geometry()
	_update_config_label()
	_clear_trail()
	_emit_config_changed()
	_rebuild_params()
	_recompute()


func _mark_solver_stale() -> void:
	_cancel_solver_reconnect()
	_solver_stale = true
	_mcu_ready = false
	_mcu_hello_validated = false
	_home_command_pending = false
	_mcu_fingerprint = ""
	_mcu_firmware_type = "未知"
	_mcu_fingerprint_ok = false
	_orientation_mask = {"roll": false, "pitch": false, "yaw": false}
	_orientation_reason = {"roll": "构型已变化，请重新烧录 MCU 求解器",
		"pitch": "构型已变化，请重新烧录 MCU 求解器",
		"yaw": "构型已变化，请重新烧录 MCU 求解器"}
	_mcu_status = "构型已变化，机械臂操控已冻结；请编译并烧录 MCU 求解器"
	_stall_count = 0
	if _mcu_link != null:
		_mcu_link.stop()

func _connect_mcu_solver() -> bool:
	if _mcu_link == null or _mcu_ready:
		return false
	var tc = TOOLCHAIN.new()
	var pick: Dictionary = tc.pick_download_port()
	if not bool(pick.get("ok", false)):
		_mcu_status = "未找到 MCU 串口，请先烧录仿真求解器"
		_update_status()
		return false
	var python: String = tc.find_python()
	if python.is_empty() or not _mcu_link.start(str(pick.get("device", "")), python,
			str(pick.get("kind", "unknown"))):
		_mcu_status = "无法启动 MCU 串口桥接"
		_update_status()
		return false
	return true


## 烧录会让 USB/蓝牙串口短暂消失。限时重试端口发现与桥接启动，
## 直到 HELLO 完成固件类型、协议、算法和构型指纹校验。
func reconnect_mcu_solver_after_flash() -> void:
	_cancel_solver_reconnect()
	_solver_reconnect_deadline_ms = Time.get_ticks_msec() + 10000
	_solver_reconnect_generation += 1
	_mcu_ready = false
	_mcu_hello_validated = false
	_mcu_status = "求解器已烧录，正在等待主控板重启并重新连接"
	_update_status()
	_retry_solver_reconnect(_solver_reconnect_generation)


func _retry_solver_reconnect(generation: int) -> void:
	if generation != _solver_reconnect_generation or _solver_reconnect_deadline_ms <= 0 \
			or is_queued_for_deletion():
		return
	if Time.get_ticks_msec() >= _solver_reconnect_deadline_ms:
		_solver_reconnect_deadline_ms = 0
		_mcu_status = "主控板重启后未发现求解器串口，请检查连接后重试"
		_update_status()
		return
	if _connect_mcu_solver():
		return
	get_tree().create_timer(0.5).timeout.connect(
		_retry_solver_reconnect.bind(generation), CONNECT_ONE_SHOT)


func _schedule_solver_reconnect_retry() -> void:
	if _solver_reconnect_deadline_ms <= 0:
		return
	var generation: int = _solver_reconnect_generation
	get_tree().create_timer(0.5).timeout.connect(
		_retry_solver_reconnect.bind(generation), CONNECT_ONE_SHOT)


func _cancel_solver_reconnect() -> void:
	_solver_reconnect_deadline_ms = 0
	_solver_reconnect_generation += 1

func _on_mcu_connected(info: Dictionary) -> void:
	if not info.has("hello"):
		_mcu_status = "已连接，等待 MCU 求解器握手"
		_update_status()
		return
	var hello: Dictionary = info["hello"]
	var expected: String = _cg.solver_fingerprint(_cfg)
	var actual: String = ""
	var fingerprint: PackedByteArray = hello.get("fingerprint", PackedByteArray())
	for i in range(8):
		actual += "%02x" % int(fingerprint[i]) if i < fingerprint.size() else "??"
	_mcu_fingerprint = actual
	var firmware_type: int = int(hello.get("firmware_type", 0))
	_mcu_firmware_type = "仿真" if firmware_type == 1 else (
		"正式" if firmware_type == 0 else "未知")
	_mcu_fingerprint_ok = actual == expected
	if int(hello.get("protocol_version", -1)) != IK_SIM_PROTOCOL.VERSION \
			or int(hello.get("algorithm_version", -1)) \
				!= _cg.SOLVER_ALGORITHM_WIRE_VERSION \
			or firmware_type != 1 or not _mcu_fingerprint_ok:
		_mcu_ready = false
		_mcu_hello_validated = false
		_mcu_status = "MCU 固件类型、协议或构型指纹不匹配，请重新编译并烧录"
	else:
		_mcu_ready = false
		_mcu_hello_validated = true
		_apply_mcu_orientation_mask(int(hello.get("orientation_mask", 0)))
		_mcu_diagnostics = {"position_dof": int(hello.get("position_dof", 0)),
			"orientation_dof": int(hello.get("orientation_dof", 0))}
		_mcu_status = "MCU 求解器已握手，正在读取上电关节状态"
		# MCU owns joint state. PING obtains its jointHome/FK state after reboot;
		# never overwrite it with the PC's stale rendering cache.
		_mcu_link.send_ping()
		_rebuild_params()
	_update_status()

func _on_mcu_state(state: Dictionary) -> void:
	if not (_mcu_ready or _mcu_hello_validated) \
			or int(state.get("joint_count", -1)) != _jc:
		_mcu_status = "MCU state joint count does not match the current arm"
		_mcu_ready = false
		_mcu_hello_validated = false
		_update_status()
		return
	var fingerprint: PackedByteArray = state.get("fingerprint", PackedByteArray())
	var fingerprint_hex: String = fingerprint.hex_encode() if fingerprint.size() == 8 else ""
	if fingerprint_hex != _cg.solver_fingerprint(_cfg):
		_mcu_status = "MCU state fingerprint does not match the current arm"
		_mcu_fingerprint = fingerprint_hex
		_mcu_fingerprint_ok = false
		_mcu_ready = false
		_mcu_hello_validated = false
		_update_status()
		return
	var values: Array = state.get("angles", [])
	var position: Vector3 = state.get("position", Vector3(NAN, NAN, NAN))
	var rpy: Vector3 = state.get("rpy", Vector3(NAN, NAN, NAN))
	if values.size() < _jc or not position.is_finite() or not rpy.is_finite():
		_mcu_status = "MCU state is incomplete or contains invalid numbers"
		_mcu_ready = false
		_mcu_hello_validated = false
		_update_status()
		return
	for i in range(_jc):
		if not is_finite(float(values[i])):
			_mcu_status = "MCU joint state contains invalid numbers"
			_mcu_ready = false
			_mcu_hello_validated = false
			_update_status()
			return
	for i in range(_jc):
		_angles[i] = float(values[i])
	_fk_angles = _angles.duplicate()
	_apply_mcu_orientation_mask(int(state.get("orientation_mask_bits", 0)))
	_mcu_actual = {"position": position, "rpy": rpy}
	var request_kind: int = int(state.get("request_kind", 0))
	if request_kind == IK_SIM_PROTOCOL.CMD_HOME:
		_home_command_pending = false
	var initial_state: bool = _mcu_hello_validated
	if initial_state or request_kind in [IK_SIM_PROTOCOL.CMD_SET_JOINTS,
			IK_SIM_PROTOCOL.CMD_HOME]:
		_target = _mcu_actual.duplicate(true)
	_mcu_diagnostics = state.duplicate(true)
	var status: int = int(state.get("status", 0))
	if request_kind == IK_SIM_PROTOCOL.CMD_HOME or (status & (
			IK_SIM_PROTOCOL.STATUS_CLAMPED | IK_SIM_PROTOCOL.STATUS_NUMERIC_ERROR)) != 0:
		_requested_angles = _angles.duplicate()
	_reachable = (status & IK_SIM_PROTOCOL.STATUS_STALLED) == 0 \
		and (status & IK_SIM_PROTOCOL.STATUS_NUMERIC_ERROR) == 0
	if _reachable:
		_stall_count = 0
	elif _stall_count < 1000:
		_stall_count += 1
	# 持续停滞时把目标吸到 MCU 实际末端，让操作手从可达位置重新出发。
	if _stall_count >= _cg.IK_STALL_SNAP and request_kind not in [
			IK_SIM_PROTOCOL.CMD_SET_JOINTS, IK_SIM_PROTOCOL.CMD_HOME]:
		_target = _mcu_actual.duplicate(true)
		_stall_count = 0
	var rendered: Dictionary = _tip_target(_angles)
	var rendered_basis: Basis = _cg.basis_from_rpy_deg(rendered["rpy"])
	var mcu_basis: Basis = _cg.basis_from_rpy_deg(_mcu_actual["rpy"])
	var orientation_delta_deg: float = rad_to_deg(
		(rendered_basis.transposed() * mcu_basis).get_rotation_quaternion().get_angle())
	_render_model_mismatch = (rendered["position"] as Vector3).distance_to(
		_mcu_actual["position"] as Vector3) > 1.0 or orientation_delta_deg > 1.0
	if initial_state:
		_mcu_hello_validated = false
		_mcu_ready = true
		_solver_stale = false
		_mcu_status = "MCU 求解器已就绪"
		_cancel_solver_reconnect()
		_rebuild_params()
	_render_arm()
	_sync_param_widgets()
	_update_status()


func _apply_mcu_orientation_mask(bits: int) -> void:
	_orientation_mask = {"roll": bool(bits & 1), "pitch": bool(bits & 2),
		"yaw": bool(bits & 4)}
	_orientation_reason = {}
	for name in ["roll", "pitch", "yaw"]:
		if not bool(_orientation_mask[name]):
			_orientation_reason[name] = "MCU 诊断：该维度不能在保持 XYZ 时独立控制"

func _on_mcu_error(message: String) -> void:
	_mcu_ready = false
	_mcu_hello_validated = false
	_home_command_pending = false
	_mcu_status = message
	_update_status()
	_schedule_solver_reconnect_retry()


func _on_mcu_warning(message: String) -> void:
	_mcu_status = message
	_update_status()

func _on_mcu_disconnected() -> void:
	_mcu_ready = false
	_mcu_hello_validated = false
	_home_command_pending = false
	if not is_queued_for_deletion() and not _solver_stale:
		_mcu_status = "MCU 求解器已断开"


func _build_control_editor(parent: Node) -> void:
	_add_section(parent, "遥控映射")
	for row in [
		["joy_x", "末端 X 摇杆", IK_CONFIG.JOY_X_OPTIONS],
		["joy_y", "末端 Y 摇杆", IK_CONFIG.JOY_Y_OPTIONS],
		["joy_z", "末端 Z 摇杆", IK_CONFIG.JOY_Z_OPTIONS],
	]:
		_add_option_row(parent, row[1], row[2], str(_cfg[row[0]]),
			func(value: String) -> void:
				_cfg[row[0]] = value
				_emit_config_changed())
	_add_config_spin(parent, "摇杆步长 mm/周期", str(_cfg["joy_scale"]), 0.1, 1000.0, 0.1,
		func(value: float) -> void:
			_cfg["joy_scale"] = str(value)
			_emit_config_changed())
	_add_config_spin(parent, "位置按键步长 mm/周期", str(_cfg["keymove_speed"]), 0.1, 1000.0, 0.1,
		func(value: float) -> void:
			_cfg["keymove_speed"] = str(value)
			_emit_config_changed())
	_add_config_spin(parent, "姿态按键步长 °/周期", str(_cfg["orientation_key_speed"]),
		0.1, 90.0, 0.1, func(value: float) -> void:
			_cfg["orientation_key_speed"] = str(value)
			_emit_config_changed())
	_add_toggle_row(parent, "右摇杆按下回初始角（键盘 Z）",
		bool(_cfg.get("rocker2_home_enabled", false)), func(value: bool) -> void:
			_cfg["rocker2_home_enabled"] = value
			_emit_config_changed())
	var labels: Array[String] = ["末端 X", "末端 Y", "末端 Z",
		"姿态 Roll", "姿态 Pitch", "姿态 Yaw"]
	var orientation_names: Array[String] = ["roll", "pitch", "yaw"]
	for i in range(6):
		_add_section(parent, labels[i])
		var orientation_name: String = orientation_names[i - 3] if i >= 3 else ""
		var unavailable: bool = i >= 3 and not bool(_orientation_mask.get(orientation_name, false))
		for side in ["plus", "minus"]:
			var option := _add_option_row(parent, "+" if side == "plus" else "-",
				IK_CONFIG.MOVE_KEYS, str(_cfg["keymove"][i][side]),
				func(value: String) -> void:
					_cfg["keymove"][i][side] = value
					_emit_config_changed())
			option.disabled = option.disabled or unavailable
			if unavailable:
				option.tooltip_text = str(_orientation_reason.get(orientation_name,
					"当前构形无法独立控制该姿态维度"))
	_build_diagnostics(parent)


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
	if (key in ["x", "y", "z", "roll", "pitch", "yaw"] \
			or (key.begins_with("j") and key.substr(1).is_valid_int())) \
			and not _mcu_ready:
		_mcu_status = "机械臂控制已冻结，请先烧录并连接匹配的 MCU 求解器"
		_update_status()
		return
	_syncing = true
	if peer is Range:
		peer.value = value
	_syncing = false
	if key.begins_with("j") and key.substr(1).is_valid_int():
		var joint_idx: int = key.substr(1).to_int()
		if joint_idx < _fk_angles.size():
			_fk_angles[joint_idx] = value
			_apply_joint_pose_from_editor()
		return
	if key.begins_with("len") and key.substr(3).is_valid_int():
		_on_link_length_changed(key.substr(3).to_int(), value)
		return
	match key:
		"x", "y", "z":
			var position: Vector3 = _target["position"]
			position[ {"x": 0, "y": 1, "z": 2}[key]] = value
			_target["position"] = position
		"roll", "pitch", "yaw":
			var rpy: Vector3 = _target["rpy"]
			var component: int = {"roll": 0, "pitch": 1, "yaw": 2}[key]
			rpy[component] = clampf(value, -90.0, 90.0) if key == "pitch" \
				else wrapf(value, -180.0, 180.0)
			_target["rpy"] = rpy
		"movespd":
			# 速度只影响下一帧的键盘步进，不改当前姿态
			_ik_move_speed = value
			return
		"rotspd":
			_ik_rot_speed = value
			return
		"sim_speed":
			_speed_scale = value
			return
		"sim_turn":
			_turn_rate = value
			return
		"cwb", "ctr", "chh", "mx", "my", "mz":
			_on_chassis_param_changed(key, value)
			return
		"phone_pos_scale":
			_phone_receiver.position_scale = value
			return
		"phone_rpy_scale":
			_phone_receiver.rpy_scale = value
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
	_update_arm_mount()
	_build_chassis()
	_render_vehicle()
	# 安装高度与底盘高都会改变地面位置，网格要跟着重画
	if key == "mz" or key == "chh":
		_build_grid()
	_refresh_camera_focus()
	if key in ["mx", "my", "mz"]:
		_clear_trail()
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
		label.text += "\n底盘世界运动不参与逆解算：逆解原点始终是随车移动的机械臂底座。"
		label.text += "\n改安装位置会移动 ArmMount，用来核对臂能不能伸到车外、会不会撞到自己的轮子。"


## 臂长改动：几何要重建，可达域也跟着变
func _on_link_length_changed(index: int, value: float) -> void:
	if not _editable or index < 0 or index >= _joints.size():
		return
	_joints[index]["len"] = "%.2f" % maxf(value, 0.0)
	_joint_slots[index] = _joints[index]
	_mark_solver_stale()
	_rebuild_arm()
	_rebuild_static_geometry()
	_update_config_label()
	_clear_trail()
	_emit_config_changed()
	_recompute()


## 求解结果同时回写末端与关节控件，保证两种编辑方式始终描述同一姿态。
func _sync_param_widgets() -> void:
	_syncing = true
	var position: Vector3 = _target["position"]
	var rpy: Vector3 = _target["rpy"]
	var vals: Dictionary = {"x": position.x, "y": position.y, "z": position.z,
		"roll": rpy.x, "pitch": rpy.y, "yaw": rpy.z}
	if _mode == Mode.IK:
		for i in range(_angles.size()):
			vals["j%d" % i] = _angles[i]
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
	_build_structure_editor(parent)
	_add_section(parent, "末端目标（逆解）")
	# 滑块范围按最大可达半径取整，留 20% 余量便于试探越界行为
	var reach: float = maxf(_arm_reach() * 1.2, 1.0)
	var position: Vector3 = _target["position"]
	var rpy: Vector3 = _target["rpy"]
	_add_slider_row(parent, "x", "X (mm)", -reach, reach, position.x, 1.0)
	_add_slider_row(parent, "y", "Y (mm)", -reach, reach, position.y, 1.0)
	_add_slider_row(parent, "z", "Z (mm，高度)", -reach, reach, position.z, 1.0)
	for item in [["roll", "Roll（滚转）", rpy.x, -180.0, 180.0],
			["pitch", "Pitch（俯仰）", rpy.y, -90.0, 90.0],
			["yaw", "Yaw（偏航）", rpy.z, -180.0, 180.0]]:
		var name: String = item[0]
		var enabled: bool = bool(_orientation_mask.get(name, false))
		var label_text: String = item[1]
		if not enabled:
			label_text += "（不可独立控制）"
		_add_slider_row(parent, name, label_text, item[3], item[4], item[2], 1.0)
		_sliders[name].editable = enabled and _editable
		_spins[name].editable = enabled and _editable
		if not enabled:
			var reason: String = str(_orientation_reason.get(name, "构形自由度不足"))
			_sliders[name].tooltip_text = reason
			_spins[name].tooltip_text = reason
	_add_section(parent, "键盘移动速度")
	_add_slider_row(parent, "movespd", "位移 (mm/s)", 10.0, 500.0, _ik_move_speed, 5.0)
	if bool(_orientation_mask.get("pitch", false)):
		_add_slider_row(parent, "rotspd", "姿态角 (°/s)", 5.0, 240.0, _ik_rot_speed, 5.0)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "键盘控制末端：" + _key_hint_text()
	hint.text += "\nShift 加速一倍，Alt 减速到 1/4。"
	hint.text += "\n黄色半透明目标块同时显示目标位置和完整朝向。"
	parent.add_child(hint)
	_build_joint_calibration(parent)
	_build_gripper_rows(parent)
	_build_chassis_rows(parent)


## 当前构型的键盘映射说明（顶栏提示与侧欄共用）
func _key_hint_text() -> String:
	var s: String = "W/S 走 X，A/D 走 Y（水平面），↑↓ 走 Z（高度）"
	if bool(_orientation_mask.get("pitch", false)):
		s += "，Q/E 调 Pitch"
	return s


# --- 逆解编辑页内的关节调整与安装标定
func _build_joint_calibration(parent: Node) -> void:
	_add_section(parent, "关节调整与安装标定")
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "拖动关节角会向 MCU 发送正解目标；上方 XYZ/Roll/Pitch/Yaw 发送逆解目标。"
	parent.add_child(intro)
	for i in range(_jc):
		var rng: Array = _joint_slider_range(i)
		_add_slider_row(parent, "j%d" % i, "关节%d θ (°) 可调 [%.0f, %.0f]" % [i + 1, rng[0], rng[1]],
			rng[0], rng[1], _fk_angles[i], 0.5)
	_add_section(parent, "安装标定")
	var set_off: Button = Button.new()
	set_off.text = "当前姿态设为中位朝向"
	set_off.tooltip_text = "舵机盘装歪时用：把滑块摆到「舵机处于中位时臂的实际朝向」再点这里"
	set_off.pressed.connect(_calibrate_offset_from_current)
	set_off.disabled = not _editable
	parent.add_child(set_off)
	var set_home: Button = Button.new()
	set_home.text = "当前姿态设为初始角"
	set_home.tooltip_text = "上电后机械臂应停在的姿态"
	set_home.pressed.connect(_calibrate_home_from_current)
	set_home.disabled = not _editable
	parent.add_child(set_home)
	var reset_off: Button = Button.new()
	reset_off.text = "中位朝向归零"
	reset_off.pressed.connect(_reset_offsets)
	reset_off.disabled = not _editable
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


func _apply_joint_pose_from_editor() -> void:
	if _mcu_ready:
		_mcu_link.send_joints(_fk_angles.slice(0, _jc), _jc)
	else:
		_mcu_status = "未连接匹配的 MCU 求解器，关节命令未发送"
		_update_status()


## 臂长编辑行（标定与预设模式共用）
func _build_link_length_rows(parent: Node) -> void:
	_add_section(parent, "连杆长度 (mm)")
	var lens: Array = _cg.joint_lengths(_joints, _jc)
	for i in range(_jc):
		_add_slider_row(parent, "len%d" % i, "关节%d 后连杆" % (i + 1),
			0.0, 600.0, float(lens[i]), 1.0)


## 独立夹爪舵机配置。它不占逆解关节，但与关节、底盘和工程映射共享 IO。
func _build_gripper_rows(parent: Node) -> void:
	_add_section(parent, "夹爪舵机")
	_add_toggle_row(parent, "启用夹爪舵机", bool(_gripper.get("enabled", false)),
		func(value: bool) -> void: _on_gripper_field_changed("enabled", value))
	var used: Array[String] = IK_CONFIG.blocked_chassis_ios(_engineer)
	for joint in _joints:
		used.append(str(joint.get("io", "")))
	for row in _engineer.get("key_map", []):
		var target: String = str(row.get("target", ""))
		if not target.is_empty():
			used.append(target)
	_add_option_row(parent, "舵机 IO", IK_CONFIG.IOS, str(_gripper.get("io", "MP03")),
		func(value: String) -> void: _on_gripper_field_changed("io", value), used)
	_add_option_row(parent, "安装方向", ["正向", "反向"], str(_gripper.get("dir", "正向")),
		func(value: String) -> void: _on_gripper_field_changed("dir", value))
	_add_config_spin(parent, "张开角（相对中位）°", str(_gripper.get("open_angle", "45")),
		-90.0, 90.0, 0.5,
		func(value: float) -> void: _on_gripper_field_changed("open_angle", str(value)))
	_add_config_spin(parent, "闭合角（相对中位）°", str(_gripper.get("closed_angle", "-45")),
		-90.0, 90.0, 0.5,
		func(value: float) -> void: _on_gripper_field_changed("closed_angle", str(value)))
	_add_toggle_row(parent, "上电时张开", bool(_gripper.get("initial_open", true)),
		func(value: bool) -> void: _on_gripper_field_changed("initial_open", value))
	_add_option_row(parent, "开合触发键", IK_CONFIG.KEYS, str(_gripper.get("key", "D")),
		func(value: String) -> void: _on_gripper_field_changed("key", value))
	var preview := HBoxContainer.new()
	parent.add_child(preview)
	var open_button := Button.new()
	open_button.text = "预览张开"
	open_button.pressed.connect(_preview_gripper.bind(true))
	preview.add_child(open_button)
	var close_button := Button.new()
	close_button.text = "预览闭合"
	close_button.pressed.connect(_preview_gripper.bind(false))
	preview.add_child(close_button)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "角度是相对舵机中位的偏移。夹爪不计入关节数，也不参与正逆解。"
	hint.text += "\n操控模式中单击触发键切换开合；预设点位不会改变夹爪。"
	parent.add_child(hint)


func _on_gripper_field_changed(field: String, value: Variant) -> void:
	if not _editable:
		return
	_gripper[field] = value
	if field == "io" and str(value) in IK_CONFIG.EXPANSION_IOS:
		_io_init_patch[str(value)] = "舵机"
		var init: Dictionary = _engineer.get("io_init", {}).duplicate(true)
		init[str(value)] = "舵机"
		_engineer["io_init"] = init
	if field == "initial_open":
		_preview_gripper(bool(value))
	_cfg["gripper"] = _gripper.duplicate(true)
	_emit_config_changed()
	_rebuild_params()
	_render_arm()
	_update_status()


func _preview_gripper(opened: bool) -> void:
	_gripper_open = opened
	_grip_open = 1.0 if opened else 0.0
	_render_arm()
	_update_status()


## 底盘尺寸与机械臂安装位置（纯视觉参照，不进逆解）
func _build_chassis_rows(parent: Node) -> void:
	_add_section(parent, "底盘尺寸 (mm)")
	_add_slider_row(parent, "cwb", "底盘板长（前后）", 100.0, 800.0, _chassis_deck_len, 5.0)
	# 下限取板厚：再低就是板贴地了（机械上确实能做到离地几乎为 0）。
	# 上限压到轮径的 3 倍：轮子只有 50mm，再高支臂就细长得像桌腿了
	_add_slider_row(parent, "chh", "底盘高（地面到板面）",
		CHASSIS_DECK_THICK_MM,
		WHEEL_RADIUS_MM * 6.0 + CHASSIS_DECK_THICK_MM, _chassis_height, 5.0)
	_add_slider_row(parent, "ctr", "轮距（左右）", 100.0, 800.0, _chassis_track, 5.0)
	_add_section(parent, "机械臂安装位置（相对底盘中心）")
	_add_slider_row(parent, "mx", "前后偏移（+前）", -400.0, 400.0, _mount.x, 5.0)
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
	if not _editable:
		return
	for i in range(_jc):
		_joints[i]["offset"] = "%.2f" % _angles[i]
	# 中位朝向变了，滑块可调范围随之平移，必须重建面板
	_rebuild_params()
	_emit_config_changed()
	_recompute()


## 把当前姿态写成上电初始角
func _calibrate_home_from_current() -> void:
	if not _editable:
		return
	for i in range(_jc):
		_joints[i]["zero"] = "%.2f" % _angles[i]
		_joint_slots[i] = _joints[i]
	_mark_solver_stale()
	_emit_config_changed()
	_recompute()


func _reset_offsets() -> void:
	if not _editable:
		return
	for i in range(_jc):
		_joints[i]["offset"] = "0"
	_rebuild_params()
	_emit_config_changed()
	_recompute()


# --- 预设点位模式
func _build_preset_params(parent: Node) -> void:
	_add_section(parent, "预设配置")
	for i in range(IK_CONFIG.PRESET_COUNT):
		var preset: Dictionary = _presets[i]
		_add_section(parent, "预设 %d" % (i + 1))
		_add_toggle_row(parent, "启用", bool(preset.get("enabled", false)),
			func(value: bool) -> void: _on_preset_field_changed(i, "enabled", value))
		_add_option_row(parent, "触发键", IK_CONFIG.KEYS, str(preset.get("key", "A")),
			func(value: String) -> void: _on_preset_field_changed(i, "key", value))
		for field in [["x", "X mm", -5000.0, 5000.0], ["y", "Y mm", -5000.0, 5000.0],
			["z", "Z mm", -5000.0, 5000.0], ["roll", "Roll °", -180.0, 180.0],
			["pitch", "Pitch °", -90.0, 90.0], ["yaw", "Yaw °", -180.0, 180.0]]:
			var spin := _add_config_spin(parent, field[1], str(preset.get(field[0], "")),
				field[2], field[3], 0.5,
				func(value: float) -> void: _on_preset_field_changed(i, field[0], str(value)))
			if field[0] in ["roll", "pitch", "yaw"] \
					and not bool(_orientation_mask.get(field[0], false)):
				spin.editable = false
				spin.tooltip_text = str(_orientation_reason.get(field[0], "构形自由度不足"))
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
		save.disabled = not _editable
		parent.add_child(save)
	if not active.is_empty():
		var clear_row: Button = Button.new()
		clear_row.text = "清空全部预设"
		clear_row.pressed.connect(_clear_presets)
		clear_row.disabled = not _editable
		parent.add_child(clear_row)
	if not active.is_empty():
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
	_build_gripper_rows(parent)
	_build_diagnostics(parent)


func _on_preset_field_changed(index: int, field: String, value: Variant) -> void:
	if not _editable or index < 0 or index >= _presets.size():
		return
	_presets[index][field] = value
	_cfg["presets"] = _presets.duplicate(true)
	_emit_config_changed()
	_rebuild_params()


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
	if not _mcu_ready or idx >= _presets.size():
		return
	var p: Dictionary = _presets[idx]
	_play_idx = -1
	var rpy: Vector3 = _target["rpy"]
	for pair in [["roll", 0], ["pitch", 1], ["yaw", 2]]:
		if bool(_orientation_mask.get(pair[0], false)):
			rpy[pair[1]] = _p_float(p, pair[0])
	_target = {"position": Vector3(_p_float(p, "x"), _p_float(p, "y"), _p_float(p, "z")),
		"rpy": rpy}
	_recompute()


## 预设点位坐标的显示文本。
func _preset_coord_text(p: Dictionary) -> String:
	var s: String = "X=%.0f Y=%.0f Z=%.0f" % [
		_p_float(p, "x"), _p_float(p, "y"), _p_float(p, "z")]
	for pair in [["roll", "R"], ["pitch", "P"], ["yaw", "Y"]]:
		if bool(_orientation_mask.get(pair[0], false)):
			s += " %s=%.0f°" % [pair[1], _p_float(p, pair[0])]
	return s


## 把当前末端实际位置存为第 idx 个预设点位。
## 存实际末端（经限位钳位后的 FK 结果）而非目标值，否则存进去的点位本身就不可达。
func _save_preset(idx: int) -> void:
	if not _editable or not _mcu_ready:
		if not _mcu_ready:
			_mcu_status = "保存当前姿态需要已连接且指纹匹配的 MCU 求解器"
			_update_status()
		return
	while _presets.size() <= idx:
		_presets.append(IK_CONFIG.default_preset(_presets.size()))
	var tip: Dictionary = _mcu_actual
	var position: Vector3 = tip["position"]
	var rpy: Vector3 = tip["rpy"]
	var p: Dictionary = _presets[idx]
	p["x"] = "%.2f" % position.x
	p["y"] = "%.2f" % position.y
	p["z"] = "%.2f" % position.z
	for pair in [["roll", rpy.x], ["pitch", rpy.y], ["yaw", rpy.z]]:
		p[pair[0]] = "%.2f" % pair[1] if bool(_orientation_mask.get(pair[0], false)) else ""
	p["enabled"] = true
	# 按键未选过时给个默认，避免生成的 C 里 presetKey 落到回退值
	if not p.has("key") or str(p.get("key", "")).is_empty():
		p["key"] = ["A", "B", "C", "D"][idx % 4]
	_presets[idx] = p
	_play_idx = -1
	_rebuild_params()
	_emit_config_changed()


func _clear_presets() -> void:
	if not _editable:
		return
	for i in range(_presets.size()):
		_presets[i]["x"] = ""
		_presets[i]["y"] = ""
		_presets[i]["z"] = ""
		_presets[i]["roll"] = ""
		_presets[i]["pitch"] = ""
		_presets[i]["yaw"] = ""
		_presets[i]["enabled"] = false
	_play_idx = -1
	_rebuild_params()
	_emit_config_changed()


func _start_play() -> void:
	if not _mcu_ready:
		_play_idx = -1
		return
	var active: Array = _active_presets()
	if active.is_empty():
		return
	_play_idx = 0
	_play_t = 0.0
	_play_from = _target.duplicate()


# --- 手机传感器配置面板
func _build_phone_params(parent: Node) -> void:
	_add_section(parent, "手机传感器")
	# 连接信息
	var url: String = _phone_receiver.get_connection_url()
	var all_ips: Array[String] = _phone_receiver.get_local_ips()
	var conn_label := Label.new()
	conn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if all_ips.is_empty():
		conn_label.text = "无法获取本机 IP，请手动查看\n端口: %d" % PHONE_RECEIVER.DEFAULT_PORT
	else:
		conn_label.text = "连接地址: %s" % " / ".join(all_ips.map(
			func(ip: String) -> String: return "ws://%s:%d" % [ip, PHONE_RECEIVER.DEFAULT_PORT]))
	if _phone_receiver.has_phone():
		conn_label.text += "\n手机已连接: %s" % _phone_receiver.client_info
	else:
		conn_label.text += "\n等待手机连接…"
	parent.add_child(conn_label)
	# 二维码（供手机扫码连接）
	if not _phone_receiver.has_phone():
		var qr_path: String = _phone_receiver.generate_qr_png(url)
		if not qr_path.is_empty():
			var img := Image.new()
			if img.load(qr_path) == OK:
				var tex := ImageTexture.create_from_image(img)
				var qr_rect := TextureRect.new()
				qr_rect.texture = tex
				qr_rect.custom_minimum_size = Vector2(180, 180)
				qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				qr_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				qr_rect.tooltip_text = "用 PieBlock 遥控 APP 扫码自动填入地址"
				parent.add_child(qr_rect)
				var qr_label := Label.new()
				qr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				qr_label.text = "↑ 手机 APP 扫码连接"
				parent.add_child(qr_label)
	# 位置映射比例
	_add_slider_row(parent, "phone_pos_scale", "位置映射比例", 0.1, 10.0,
		_phone_receiver.position_scale, 0.1)
	# RPY 灵敏度
	_add_slider_row(parent, "phone_rpy_scale", "RPY 灵敏度", 0.1, 3.0,
		_phone_receiver.rpy_scale, 0.1)
	# 坐标轴翻转
	_add_toggle_row(parent, "翻转 X 轴", _phone_receiver.flip_x,
		func(v: bool) -> void: _phone_receiver.flip_x = v)
	_add_toggle_row(parent, "翻转 Y 轴", _phone_receiver.flip_y,
		func(v: bool) -> void: _phone_receiver.flip_y = v)
	_add_toggle_row(parent, "翻转 Z 轴", _phone_receiver.flip_z,
		func(v: bool) -> void: _phone_receiver.flip_z = v)
	# 各轴开关
	_add_toggle_row(parent, "启用 X", bool(_phone_receiver.axis_enable.get("x", true)),
		func(v: bool) -> void: _phone_receiver.axis_enable["x"] = v)
	_add_toggle_row(parent, "启用 Y", bool(_phone_receiver.axis_enable.get("y", true)),
		func(v: bool) -> void: _phone_receiver.axis_enable["y"] = v)
	_add_toggle_row(parent, "启用 Z", bool(_phone_receiver.axis_enable.get("z", true)),
		func(v: bool) -> void: _phone_receiver.axis_enable["z"] = v)
	_add_toggle_row(parent, "启用 Roll", bool(_phone_receiver.axis_enable.get("roll", true)),
		func(v: bool) -> void: _phone_receiver.axis_enable["roll"] = v)
	_add_toggle_row(parent, "启用 Pitch", bool(_phone_receiver.axis_enable.get("pitch", true)),
		func(v: bool) -> void: _phone_receiver.axis_enable["pitch"] = v)
	_add_toggle_row(parent, "启用 Yaw", bool(_phone_receiver.axis_enable.get("yaw", true)),
		func(v: bool) -> void: _phone_receiver.axis_enable["yaw"] = v)
	# 回中按钮
	var reset_btn := Button.new()
	reset_btn.text = "回中（重置原点）"
	reset_btn.tooltip_text = "以手机当前姿态为零点，末端 RPY 归零"
	reset_btn.pressed.connect(func() -> void:
		_phone_receiver.reset_origin()
		if _mcu_ready:
			_target = _mcu_actual.duplicate(true)
			_recompute())
	parent.add_child(reset_btn)
	# 说明
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "手机传感器数据在所有模式下均可注入末端目标位姿。\n"
	hint.text += "手机数据到达后 200ms 内屏蔽键盘/手柄的位置和姿态输入。\n"
	hint.text += "超界时手机会震动提醒。"
	parent.add_child(hint)


# --- 双模式遥控器模拟
func _build_controller_params(parent: Node) -> void:
	_build_control_editor(parent)
	_build_gripper_rows(parent)
	_add_section(parent, "底盘仿真标定")
	_add_slider_row(parent, "sim_speed", "10000 duty → m/s", 0.2, 6.0,
		_speed_scale, 0.1)
	_add_slider_row(parent, "sim_turn", "10000 duty → °/s", 30.0, 900.0,
		_turn_rate, 10.0)
	_add_section(parent, "遥控器状态")
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "上电模式：逆解 ｜ 切换键：%s ｜ 周期：%dms" % [
		_cfg.get("mode_switch_key", "R"), int(SIM_STEP_MS)]
	hint.text += "\nWASD / IJKL = 左 / 右摇杆 ｜ 1/2/3/4 = A/B/C/D"
	hint.text += "\n方向键 = 十字键 ｜ Shift / Z = 左 / 右摇杆按下 ｜ 鼠标左键 = R"
	parent.add_child(hint)


# ------------------------------------------------------------------ 每帧推进
func _process(delta: float) -> void:
	# PhonePoseReceiver 自己在 _process 里 poll WebSocket，不需要在这里调
	# 手机活跃超时计数：超过 200ms 没收到手机数据就解除"手机优先"
	if _phone_active_timer > 0:
		_phone_active_timer -= int(delta * 1000.0)
		if _phone_active_timer <= 0:
			_phone_active = false
	if _mode == Mode.PRESET:
		if _play_idx >= 0:
			_step_play(delta)
		_update_camera(delta)
		return
	if _mode == Mode.CONTROLLER:
		_poll_remote_inputs()
		_step_controller(delta)
	elif _mode == Mode.IK:
		# 焦点在数值框里时不吃键盘，否则输入 W/S 会同时推动末端。
		if _text_field_focused():
			_update_camera(delta)
			return
		_step_key_move(delta)
	_update_camera(delta)


## 当前焦点是否落在可输入文本的控件上
func _text_field_focused() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var f: Control = vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## 真实手柄始终可用；文本输入焦点只抑制键盘和鼠标代打。
func _poll_remote_inputs() -> void:
	var keyboard_enabled: bool = not _text_field_focused()
	_remote_snapshot = REMOTE_INPUT.sample(_engineer_deadzone(), _engineer_deadzone(),
		keyboard_enabled, keyboard_enabled and not _mouse_over_ui())
	_update_hint()


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
	for _s in range(steps):
		_controller_tick()


func _controller_tick() -> void:
	_update_remote_gripper()
	_update_remote_mode()
	_calculate_chassis_duty()
	_integrate_chassis()
	if not _mcu_ready:
		# Chassis and gripper simulation stay available, but arm commands are
		# disabled until HELLO has validated firmware, algorithm and fingerprint.
		_duty_aux_motor.fill(0)
		_home_key_held = false
		_update_status()
		return
	var home_hit: bool = _update_remote_home()
	if _inverse_mode:
		_duty_aux_motor.fill(0)
		if not home_hit:
			var preset_hit: bool = _apply_remote_preset()
			if not preset_hit:
				_apply_remote_ik_inputs()
			if _mcu_ready and not _home_command_pending:
				_mcu_link.send_pose(_target["position"], _target["rpy"])
			else:
				_update_status()
	else:
		if not home_hit and _mcu_ready:
			_apply_forward_mapping()
			_mcu_link.send_joints(_requested_angles, _jc)


func _update_remote_gripper() -> void:
	if not bool(_gripper.get("enabled", false)):
		_gripper_key_held = false
		return
	var pressed: bool = _remote_key(str(_gripper.get("key", "D")))
	if pressed and not _gripper_key_held:
		_gripper_key_held = true
		_preview_gripper(not _gripper_open)
	elif not pressed:
		_gripper_key_held = false


func _update_remote_mode() -> void:
	var pressed: bool = _remote_key(str(_cfg.get("mode_switch_key", "R")))
	if pressed and not _mode_key_held:
		_inverse_mode = not _inverse_mode
		_mode_key_held = true
		if _inverse_mode:
			_target = _mcu_actual.duplicate(true) if _mcu_ready else _target
		else:
			_requested_angles = _angles.duplicate()
	elif not pressed:
		_mode_key_held = false


## ROCKER2（键盘 Z / 手柄右摇杆按键）按下边沿直接恢复关节初始角。
## 返回 true 时，本周期跳过机械臂的其他控制，保证回中命令优先。
func _update_remote_home() -> bool:
	if not bool(_cfg.get("rocker2_home_enabled", false)):
		_home_key_held = false
		return false
	var pressed: bool = _remote_pressed_id("ROCKER2")
	if pressed and not _home_key_held:
		_home_key_held = true
		_home_command_pending = true
		_return_arm_home()
		return true
	if not pressed:
		_home_key_held = false
	return false


func _return_arm_home() -> void:
	if _mcu_ready:
		_mcu_link.send_home()
	else:
		_mcu_status = "未连接匹配的 MCU 求解器，回中命令未发送"
		_update_status()


func _calculate_chassis_duty() -> void:
	var roker: Array = _remote_snapshot["valueOfRoker"]
	var speed_limit: int = _engineer_int("normal_speed", 4000, 0, 10000)
	if bool(_engineer.get("sprint_enabled", false)) and _remote_pressed_id("ROCKER1"):
		speed_limit = _engineer_int("sprint_speed", 8000, 0, 10000)
	_base_speed = int(float(roker[0][1]) * speed_limit / ROKER_FULL)
	_turn_speed = int(float(roker[0][0]) * speed_limit / ROKER_FULL)
	var directions: Array = []
	for key in ["l1_dir", "l2_dir", "r1_dir", "r2_dir"]:
		directions.append(1 if str(_engineer.get(key, "正向")) == "正向" else -1)
	_duty_chassis[0] = clampi(directions[0] * (-_base_speed - _turn_speed), -speed_limit, speed_limit)
	_duty_chassis[1] = clampi(directions[1] * (-_base_speed - _turn_speed), -speed_limit, speed_limit)
	_duty_chassis[2] = clampi(directions[2] * (_base_speed - _turn_speed), -speed_limit, speed_limit)
	_duty_chassis[3] = clampi(directions[3] * (_base_speed - _turn_speed), -speed_limit, speed_limit)


## 确定性差速模型。接线方向只修正真机输出，不参与仿真的物理方向。
func _integrate_chassis() -> void:
	var dt: float = SIM_STEP_MS / 1000.0
	var linear_mps: float = float(_base_speed) / 10000.0 * _speed_scale
	var omega: float = - float(_turn_speed) / 10000.0 * deg_to_rad(_turn_rate)
	_vehicle_heading = wrapf(_vehicle_heading + omega * dt, -PI, PI)
	# 车头在局部机器人 +X；Godot +Y 旋转后方向为 (cos h, 0, -sin h)。
	var forward: Vector3 = Vector3(cos(_vehicle_heading), 0.0, -sin(_vehicle_heading))
	_vehicle_pos += forward * linear_mps * (1000.0 * MM_TO_UNIT) * dt
	var left_mps: float = float(_base_speed + _turn_speed) / 10000.0 * _speed_scale
	var right_mps: float = float(_base_speed - _turn_speed) / 10000.0 * _speed_scale
	var radius_m: float = WHEEL_RADIUS_MM / 1000.0
	for i in range(_wheel_spin.size()):
		var wheel_speed: float = left_mps if i < 2 else right_mps
		_wheel_spin[i] = wrapf(_wheel_spin[i] + wheel_speed / radius_m * dt, -PI, PI)
	_render_vehicle()
	_update_grid_origin()


func _render_vehicle() -> void:
	var vehicle: Node3D = get_node_or_null(P_VEHICLE)
	if vehicle == null:
		return
	vehicle.position = _vehicle_pos
	vehicle.rotation = Vector3(0.0, _vehicle_heading, 0.0)
	for i in range(min(_wheel_nodes.size(), _wheel_centers.size())):
		var wheel: MeshInstance3D = _wheel_nodes[i]
		if is_instance_valid(wheel):
			wheel.transform = Transform3D(
				Basis(Vector3.BACK, _wheel_spin[i]) * _wheel_basis(), _wheel_centers[i])


func _update_grid_origin() -> void:
	var grid: MeshInstance3D = get_node_or_null(P_GRID)
	if not grid is MeshInstance3D or _grid_step_unit <= 0.0:
		return
	grid.position.x = round(_vehicle_pos.x / _grid_step_unit) * _grid_step_unit
	grid.position.z = round(_vehicle_pos.z / _grid_step_unit) * _grid_step_unit


func _apply_remote_preset() -> bool:
	for preset in _presets:
		if preset.get("enabled", false) and _remote_key(str(preset.get("key", ""))):
			_apply_preset_target(preset)
			return true
	return false


func _apply_preset_target(preset: Dictionary) -> void:
	var rpy: Vector3 = _target["rpy"]
	for pair in [["roll", 0], ["pitch", 1], ["yaw", 2]]:
		if bool(_orientation_mask.get(pair[0], false)):
			rpy[pair[1]] = _p_float(preset, pair[0])
	_target = {"position": Vector3(_p_float(preset, "x"), _p_float(preset, "y"),
		_p_float(preset, "z")), "rpy": rpy}


func _apply_remote_ik_inputs() -> void:
	# 手机传感器活跃时屏蔽遥控器位置/姿态输入
	if _phone_active:
		return
	var joy_scale: float = _cfg_float("joy_scale", 5.0)
	var position: Vector3 = _target["position"]
	for i in range(3):
		var mapping: String = str(_cfg.get(["joy_x", "joy_y", "joy_z"][i], ""))
		position[i] += float(_remote_joy_value(mapping)) * joy_scale / ROKER_FULL
	_target["position"] = position
	var key_speed: float = _cfg_float("keymove_speed", 2.0)
	var orientation_speed: float = _cfg_float("orientation_key_speed", 1.0)
	var keymove: Array = _cfg.get("keymove", [])
	var orientation_names: Array[String] = ["roll", "pitch", "yaw"]
	for i in range(min(keymove.size(), 6)):
		var orientation_name: String = orientation_names[i - 3] if i >= 3 else ""
		if i >= 3 and not bool(_orientation_mask.get(orientation_name, false)):
			continue
		var pressed_plus: bool = _remote_key(str(keymove[i].get("plus", "不使用")))
		var pressed_minus: bool = _remote_key(str(keymove[i].get("minus", "不使用")))
		if i < 3:
			position = _target["position"]
			position[i] += key_speed if pressed_plus else 0.0
			position[i] -= key_speed if pressed_minus else 0.0
			_target["position"] = position
		else:
			var rpy: Vector3 = _target["rpy"]
			var delta: float = (orientation_speed if pressed_plus else 0.0) \
				- (orientation_speed if pressed_minus else 0.0)
			var rpy_index: int = i - 3
			if rpy_index == 1:
				rpy.y = clampf(rpy.y + delta, -90.0, 90.0)
			else:
				rpy[rpy_index] = wrapf(rpy[rpy_index] + delta, -180.0, 180.0)
			_target["rpy"] = rpy


func _apply_forward_mapping() -> void:
	var joint_by_io: Dictionary = {}
	for i in range(_jc):
		joint_by_io[str(_joints[i].get("io", ""))] = i
	for row in _engineer.get("key_map", []):
		var target: String = str(row.get("target", ""))
		if target.is_empty():
			continue
		var input_name: String = str(row.get("input", ""))
		var input_value: float = _forward_input_value(input_name)
		var joystick: bool = input_name in ["右摇杆X", "右摇杆Y"]
		var direction: float = 1.0 if str(row.get("dir", "正")) == "正" else -1.0
		var mode: String = str(row.get("mode", "增量"))
		var parameter: float = _number_or(str(row.get("param", "0")), 0.0)
		if joint_by_io.has(target) and mode == "增量":
			var joint: int = int(joint_by_io[target])
			_requested_angles[joint] += direction * absf(parameter) * (
				input_value / ROKER_FULL if joystick else input_value)
			continue
		if joint_by_io.has(target) and mode == "直接" and not joystick:
			if input_value != 0.0:
				_requested_angles[int(joint_by_io[target])] = parameter
			continue
		_apply_forward_aux(target, mode, direction, parameter, input_value, joystick)
	for i in range(_duty_aux_servo.size()):
		_duty_aux_servo[i] = clampf(_duty_aux_servo[i], _cg.SERVO_DUTY_MIN, _cg.SERVO_DUTY_MAX)
	for i in range(_duty_aux_main_servo.size()):
		_duty_aux_main_servo[i] = clampf(_duty_aux_main_servo[i], _cg.SERVO_DUTY_MIN, _cg.SERVO_DUTY_MAX)
	for i in range(_duty_aux_motor.size()):
		_duty_aux_motor[i] = clampi(_duty_aux_motor[i], -10000, 10000)


func _apply_forward_aux(target: String, mode: String, direction: float,
		parameter: float, input_value: float, joystick: bool) -> void:
	var slot: int = _cg._io_to_exp_slot(target)
	var io_type: String = str((_engineer.get("io_init", {}) as Dictionary).get(target, "舵机"))
	var main_index: int = 0 if target == "MP03" else (1 if target == "MP74" else -1)
	if io_type == "舵机" and (slot >= 0 or main_index >= 0):
		var values: Array = _duty_aux_servo if slot >= 0 else _duty_aux_main_servo
		var index: int = slot if slot >= 0 else main_index
		if mode == "增量":
			var step: float = float(_cg._servo_deg_to_duty_delta(absf(parameter)))
			values[index] += direction * step * (input_value / ROKER_FULL if joystick else input_value)
		elif mode == "直接" and not joystick and input_value != 0.0:
			values[index] = float(_cg._servo_angle_to_duty(int(parameter)))
		return
	if slot < 0 or io_type != "电机":
		return
	var scaled: int = int(input_value * direction * absf(parameter) / ROKER_FULL)
	match mode:
		"速度": _duty_aux_motor[slot] = scaled
		"增速": _duty_aux_motor[slot] += scaled
		"直接": _duty_aux_motor[slot] = int(direction * absf(parameter)) if input_value != 0.0 else 0


func _forward_input_value(input_name: String) -> float:
	var roker: Array = _remote_snapshot["valueOfRoker"]
	match input_name:
		"右摇杆X": return float(roker[1][0])
		"右摇杆Y": return float(roker[1][1])
		_: return 1.0 if _remote_key(input_name) else 0.0


func _remote_joy_value(mapping: String) -> int:
	if mapping == "不使用" or mapping.is_empty():
		return 0
	var source: String = mapping.split("->")[0]
	var roker: Array = _remote_snapshot["valueOfRoker"]
	var value: int = int(roker[1][1] if "Y" in source else roker[1][0])
	return -value if "反向" in source else value


func _remote_key(config_key: String) -> bool:
	return config_key != "不使用" and REMOTE_INPUT.is_pressed(_remote_snapshot, config_key)


func _remote_pressed_id(id: String) -> bool:
	return (_remote_snapshot.get("pressed", {}) as Dictionary).has(id)


func _engineer_deadzone() -> int:
	return _engineer_int("deadzone", 10, 0, 2047)


func _engineer_int(key: String, fallback: int, lo: int, hi: int) -> int:
	var text: String = str(_engineer.get(key, "")).strip_edges()
	return clampi(text.to_int(), lo, hi) if text.is_valid_int() else fallback


func _number_or(text: String, fallback: float) -> float:
	return text.to_float() if text.strip_edges().is_valid_float() else fallback


func _mouse_over_ui() -> bool:
	return _point_over_ui(get_global_mouse_position())


func _point_over_ui(pointer: Vector2) -> bool:
	for path in [P_SIDE_PANEL, P_TOP_PANEL]:
		var panel: Node = get_node_or_null(path)
		if panel is Control and panel.visible and panel.get_global_rect().has_point(pointer):
			return true
	return false


## 预设点位巡航：在目标空间线性插值，走完一个点位停 0.4s 再去下一个
func _step_play(delta: float) -> void:
	if not _mcu_ready:
		_play_idx = -1
		return
	var active: Array = _active_presets()
	if active.is_empty():
		_play_idx = -1
		return
	var idx: int = _play_idx % active.size()
	var p: Dictionary = active[idx]["preset"]
	var to_position: Vector3 = Vector3(_p_float(p, "x"), _p_float(p, "y"), _p_float(p, "z"))
	var to_rpy: Vector3 = _target["rpy"]
	for pair in [["roll", 0], ["pitch", 1], ["yaw", 2]]:
		if bool(_orientation_mask.get(pair[0], false)):
			to_rpy[pair[1]] = _p_float(p, pair[0])
	_play_t += delta / 1.2
	if _play_t >= 1.0:
		_play_t = 0.0
		_target = {"position": to_position, "rpy": to_rpy}
		_play_from = _target.duplicate(true)
		_play_idx = (_play_idx + 1) % active.size()
	else:
		var from_position: Vector3 = _play_from.get("position", _target["position"])
		var from_rpy: Vector3 = _play_from.get("rpy", _target["rpy"])
		var next_rpy: Vector3 = from_rpy
		for component in range(3):
			next_rpy[component] = lerp_angle(deg_to_rad(from_rpy[component]),
				deg_to_rad(to_rpy[component]), _play_t) * 180.0 / PI
		_target = {"position": from_position.lerp(to_position, _play_t), "rpy": next_rpy}
	_recompute()


# ------------------------------------------------------------------ 相机
func _reset_view() -> void:
	# 显式算出「臂 + 车」的竖直范围与水平半宽，再让取景距离同时满足两者。
	# 之前只用一个"包围半径"，车高一变就会把臂裁出画面顶部（踩过）。
	var arm_reach: float = _arm_reach()
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
	# 取景中心先在机械臂局部坐标计算，再换到 VehicleRoot 局部坐标。
	var mid_up_mm: float = (top_mm + bottom_mm) * 0.5
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
	_cam_yaw = -0.85
	# 俯角不能太大，否则底盘板会把下面的轮子与轮轴挡住
	_cam_pitch = 0.26
	_cam_focus_local = _camera_focus_from_mid_up(mid_up_mm)
	_cam_heading = _vehicle_heading
	_update_camera()


func _camera_focus_from_mid_up(mid_up_mm: float) -> Vector3:
	var focus_fwd: float = _mount.x * 0.5 if _chassis_visible else _mount.x
	var focus_side: float = _mount.y * 0.5 if _chassis_visible else _mount.y
	return _robot_to_godot(focus_fwd, focus_side, _mount.z + mid_up_mm)


func _refresh_camera_focus() -> void:
	var bottom_mm: float = _ground_level() if _chassis_visible else 0.0
	_cam_focus_local = _camera_focus_from_mid_up((_arm_reach() + bottom_mm) * 0.5)
	_update_camera()


func _vehicle_focus_world() -> Vector3:
	var vehicle: Node3D = get_node_or_null(P_VEHICLE)
	return vehicle.to_global(_cam_focus_local) if vehicle != null else _cam_focus_local


func _on_follow_toggled(on: bool) -> void:
	if on == _follow:
		return
	if on:
		_cam_heading = _vehicle_heading
		_cam_yaw = wrapf(_cam_yaw - _cam_heading, -PI, PI)
	else:
		_cam_yaw = wrapf(_cam_yaw + _cam_heading, -PI, PI)
	_follow = on
	_update_camera()
	_update_status()


func _reset_vehicle_pose(clear_trail: bool = true) -> void:
	_vehicle_pos = Vector3.ZERO
	_vehicle_heading = 0.0
	_base_speed = 0
	_turn_speed = 0
	_duty_chassis = [0, 0, 0, 0]
	_wheel_spin = [0.0, 0.0, 0.0, 0.0]
	_cam_heading = 0.0
	if clear_trail:
		_clear_trail()
	_render_vehicle()
	_update_grid_origin()
	_update_camera()
	_update_status()


func _update_camera(delta: float = 0.0) -> void:
	var cam: Node = get_node_or_null(P_CAMERA)
	if not cam is Camera3D:
		return
	if _follow:
		_cam_pivot = _vehicle_focus_world()
		if delta > 0.0:
			var t: float = 1.0 - exp(-CAM_FOLLOW_LERP * delta)
			_cam_heading = lerp_angle(_cam_heading, _vehicle_heading, t)
		else:
			_cam_heading = _vehicle_heading
	var yaw: float = _cam_heading + _cam_yaw if _follow else _cam_yaw
	var offset: Vector3 = Vector3(
		_cam_dist * cos(_cam_pitch) * sin(yaw),
		_cam_dist * sin(_cam_pitch),
		_cam_dist * cos(_cam_pitch) * cos(yaw))
	cam.position = _cam_pivot + offset
	cam.look_at(_cam_pivot, Vector3.UP)


# ------------------------------------------------------------------ 输入
func _input(event: InputEvent) -> void:
	if _mode == Mode.CONTROLLER \
			and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		get_viewport().set_input_as_handled()


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
			if _point_over_ui(e.global_position):
				return
			_cam_dist = max(0.2, _cam_dist * 0.9)
			_update_camera()
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			if _point_over_ui(e.global_position):
				return
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
			var follow_toggle: Node = get_node_or_null(P_FOLLOW_TOGGLE)
			if follow_toggle is BaseButton and follow_toggle.button_pressed:
				follow_toggle.button_pressed = false
			var scale: float = _cam_dist * 0.0015
			var basis: Basis = cam.global_transform.basis
			_cam_pivot -= basis.x * e.relative.x * scale
			_cam_pivot += basis.y * e.relative.y * scale
			_update_camera()
		accept_event()


# ------------------------------------------------------------------ 键盘控制末端
## 逆解模式下由键盘直接推末端目标。
## WASD 走水平面（W/S 是机器人 +X/-X，A/D 是 +Y/-Y），↑↓ 走 Z 高度。
## 按住 Shift 加速一倍，按住 Alt 减速到 1/4，便于粗调后微调。
func _step_key_move(delta: float) -> void:
	if not _mcu_ready:
		return
	# 手机传感器活跃时屏蔽键盘位置/姿态输入
	if _phone_active:
		return
	var d: Vector3 = _key_move_axis()
	var dpitch: float = _key_pitch_axis()
	if d == Vector3.ZERO and is_zero_approx(dpitch):
		return
	var mul: float = 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		mul = 2.0
	elif Input.is_key_pressed(KEY_ALT):
		mul = 0.25
	var step: float = _ik_move_speed * mul * delta
	var position: Vector3 = _target["position"]
	position += d * step
	_target["position"] = position
	if bool(_orientation_mask.get("pitch", false)):
		var rpy: Vector3 = _target["rpy"]
		rpy.y = clampf(rpy.y + dpitch * _ik_rot_speed * mul * delta, -90.0, 90.0)
		_target["rpy"] = rpy
	_recompute()


## 当前按键组合对应的移动方向（机器人坐标，各分量 -1/0/1）
func _key_move_axis() -> Vector3:
	var v: Vector3 = Vector3.ZERO
	v.x = _axis_pair(KEY_W, KEY_S)
	v.y = _axis_pair(KEY_A, KEY_D)
	v.z = _axis_pair(KEY_UP, KEY_DOWN)
	return v


## 4 轴腕部姿态角：Q/E
func _key_pitch_axis() -> float:
	return _axis_pair(KEY_E, KEY_Q)


## 一对按键 -> -1/0/1
func _axis_pair(pos_key: int, neg_key: int) -> float:
	var v: float = 0.0
	if Input.is_key_pressed(pos_key):
		v += 1.0
	if Input.is_key_pressed(neg_key):
		v -= 1.0
	return v
