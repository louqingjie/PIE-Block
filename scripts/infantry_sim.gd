extends Control
## 步兵机器人 3D 仿真视图。
##
## 控制语义逐字复现 CodeGenInfantry 生成的 C 主循环：
##   ReadControllerInputs -> CalculateMotorControls -> CalculateGimbalControls
##   -> CalculateBoosterControl -> 限幅 -> 单发拨弹 -> 摩擦轮渐变 -> Ms_Delay(10)
## 云台的归中占空比与限幅边界直接取自 CodeGenInfantry.gimbal_params()，
## 不在本文件重推公式，避免仿真与生成的 C 代码脱节。
##
## 单位：与机械臂仿真不同，这里 1 Godot 单位 = 1 米，
## 好让 Jolt 的重力与弹丸抛物线天然正确。
##
## 输入：PC 手柄（XInput/DirectInput）与键盘都会被归一成
## valueOfRoker[2][2]（-2047~2047）与 valueOfKey[3][4]（0/1），
## 再喂给同一套控制逻辑。真机的智能交互手柄走 NRF24L01，PC 上接不进来。

# ------------------------------------------------------------------ 节点路径
const P_VIEWPORT: NodePath = "Sim/SubViewport"
const P_WORLD: NodePath = "Sim/SubViewport/World"
const P_CAMERA: NodePath = "Sim/SubViewport/World/Camera3D"
const P_GROUND: NodePath = "Sim/SubViewport/World/Ground"
const P_GRID: NodePath = "Sim/SubViewport/World/Grid"
const P_ROBOT: NodePath = "Sim/SubViewport/World/Robot"
const P_BULLETS: NodePath = "Sim/SubViewport/World/Bullets"
const P_TRACERS: NodePath = "Sim/SubViewport/World/Tracers"
const P_FRICTION_AUDIO: NodePath = "FrictionAudio"
const P_SHOT_AUDIO: NodePath = "ShotAudio"
const P_PARAMS: NodePath = "SidePanel/Scroll/Params"
const P_SIDE_PANEL: NodePath = "SidePanel"
const P_TOP_PANEL: NodePath = "TopPanel"
const P_STATUS: NodePath = "StatusPanel/Status"
const P_MODE: NodePath = "TopPanel/HBox/Mode"
const P_BACK: NodePath = "TopPanel/HBox/Back"
const P_FOLLOW_TOGGLE: NodePath = "TopPanel/HBox/FollowToggle"
const P_TRACER_TOGGLE: NodePath = "TopPanel/HBox/TracerToggle"
const P_TRACER_CLEAR: NodePath = "TopPanel/HBox/TracerClear"
const P_RESET_POSE: NodePath = "TopPanel/HBox/ResetPose"
const P_RESET_VIEW: NodePath = "TopPanel/HBox/ResetView"
const P_CONFIG_LABEL: NodePath = "TopPanel/HBox/ConfigLabel"
const P_HINT: NodePath = "HintLabel"

# ------------------------------------------------------------------ 车体尺寸（米）
## 用户要求「车大概 30cm」：底盘板前后 0.30，左右 0.24
const CHASSIS_LEN: float = 0.30
const CHASSIS_WIDTH: float = 0.24
const DECK_THICK: float = 0.02
const WHEEL_RADIUS: float = 0.03
const WHEEL_WIDTH: float = 0.025
## 轮心离底盘板侧面的距离：轮子整个露在板外，否则一半埋在板里看不见
const WHEEL_GAP: float = 0.004
## 云台底座尺寸
const YAW_BASE_H: float = 0.03
const GIMBAL_SIZE: float = 0.06
## 枪管长度与口径
const BARREL_LEN: float = 0.20
const BARREL_RADIUS: float = 0.012
## 摩擦轮（视觉）。转轴竖直，圆柱面与枪管相切，弹丸从两轮缝隙间被搓出去
const FRICTION_RADIUS: float = 0.028
## 摩擦轮厚度（沿转轴方向，即竖直方向）
const FRICTION_WIDTH: float = 0.014
## 摩擦轮颜色：未启动时的冷色，以及转速下限/上限对应的橙色 -> 橙红色。
## 占空比 500~1100 之间线性插值，转速高低一眼可辨
const FRICTION_COLD: Color = Color(0.35, 0.38, 0.42)
const FRICTION_HOT_LO: Color = Color(1.0, 0.55, 0.1)
const FRICTION_HOT_HI: Color = Color(1.0, 0.22, 0.05)
## 转起来时的自发光强度上限（占空比越高越亮）
const FRICTION_EMISSION_MAX: float = 1.2
## 摩擦轮沿枪管轴的位置（负值 = 靠枪口方向）。
## 必须让轮子后缘（FRICTION_Z + FRICTION_RADIUS）越过云台盒子前壁，
## 否则轮子会埋进盒子里看不见——盒子半宽 0.042 比轮心距 0.040 还大，挡得死死的
const FRICTION_Z: float = -0.085

# ------------------------------------------------------------------ 弹丸
## RM 17mm 弹丸：直径 17mm，标称质量 3.2g
const BULLET_RADIUS: float = 0.0085
const BULLET_MASS: float = 0.0032
## 在场弹丸上限，超出释放最旧的
const BULLET_MAX_ALIVE: int = 30
## 弹丸存活时间上限（秒）
const BULLET_LIFE_SEC: float = 4.0
## 同时显示的弹道条数上限（含在飞的）。只看最近五次，多了看不清
const TRACER_MAX_TRAILS: int = 5
## 弹丸颜色（绿色发光）与自发光强度。
## 强度不能开太高：2.5 时红蓝通道会一起顶到 1.0，绿色被洗成淡青白，反而看不出是绿的
const BULLET_COLOR: Color = Color(0.15, 0.95, 0.3)
const BULLET_EMISSION_ENERGY: float = 1.2
## 单条弹道的采样点上限
const TRACER_MAX_POINTS: int = 240

# ------------------------------------------------------------------ 标定系数（估值，非实测）
## 底盘：10000 duty 对应的车速（m/s）
const SPEED_SCALE_DEFAULT: float = 2.0
## 底盘：10000 duty 对应的原地转速（°/s）
const TURN_RATE_DEFAULT: float = 360.0
## 云台电机驱动时：10000 duty 对应的角速度（°/s）
const GIMBAL_MOTOR_RATE: float = 180.0
## 电机驱动云台没有位置反馈，仿真给一个机械限位以免转到离谱角度
const GIMBAL_MOTOR_PITCH_LIMIT: float = 60.0
## 摩擦轮占空比 -> 弹丸初速（m/s）。1100 对应官方守则上限
const MUZZLE_DUTY_LO: float = 500.0
const MUZZLE_DUTY_HI: float = 1100.0
const MUZZLE_V_LO_DEFAULT: float = 8.0
const MUZZLE_V_HI_DEFAULT: float = 30.0
## 摩擦轮没转起来时的「掉弹」速度
const MUZZLE_V_DEAD: float = 2.0

# ------------------------------------------------------------------ 控制常量（与生成的 C 一致）
## 主循环周期（ms）
const SIM_STEP_MS: float = 10.0
## 摇杆满偏读数
const ROKER_FULL: float = 2047.0
## 摩擦轮占空比区间（《RM电控指南》硬性规定，不得提高上限）
const BOOSTER_DUTY_MIN: int = 500
const BOOSTER_DUTY_MAX: int = 1100
## 官方阻塞启停序列：每 1500ms 增减 100 duty
const BOOSTER_STEP: int = 100
const BOOSTER_STEP_MS: float = 1500.0
## 一帧最多补的步数，掉帧时不至于一次跳很远
const MAX_STEPS_PER_FRAME: int = 20
## 目视闭环模式下按住扳机时的出弹间隔（ms）。
## 真机上拨弹电机持续转动会连续推弹，仿真按固定节奏出弹，
## 好让操作手练习「目视到一发弹出膛就松手」的手感。非实测标定，仅仿真观感。
const FEED_INTERVAL_MS: float = 100.0

# ------------------------------------------------------------------ 音效
## 摩擦轮音调直接等于占空比数值（500 duty -> 500Hz，1100 duty -> 1100Hz）
const AUDIO_SAMPLE_RATE: float = 44100.0
## 摩擦轮音量（线性，0~1）。常驻音不宜太响
const FRICTION_VOLUME: float = 0.16
## 音高平滑系数：占空比每 10ms 变 1，直接跟会有台阶感
const FRICTION_PITCH_LERP: float = 12.0
## 开火音效时长（秒）与音量
const SHOT_DURATION: float = 0.09
const SHOT_VOLUME: float = 0.5
## 开火音效的扫频区间（Hz）：从高扫到低，模拟「啪」的一声
const SHOT_FREQ_HI: float = 1800.0
const SHOT_FREQ_LO: float = 260.0

# ------------------------------------------------------------------ 相机
const CAM_PITCH_LIMIT: float = 1.45
## 跟随模式下相机朝向对齐车头的平滑系数（越大越跟手）
const CAM_FOLLOW_LERP: float = 6.0

# ------------------------------------------------------------------ 输入映射
const REMOTE_INPUT = preload("res://scripts/sim_remote_input.gd")

enum Mode {OPERATE = 0, CALIB = 1}

# ------------------------------------------------------------------ 生成器（数值语义真相源）
var _cg: CodeGenInfantry = CodeGenInfantry.new()

# ------------------------------------------------------------------ 配置状态
var _cfg: Dictionary = {}
var _gp: Dictionary = {}
var _max_speed: int = 4000
var _ultra_speed: int = 8000
var _deadzone: int = 10
var _sprint_enabled: bool = false
var _zero_enabled: bool = false
var _arrow_key: String = "移动"
var _yaw_is_servo: bool = true
var _pitch_is_servo: bool = true
## 底盘四个电机的接线方向 L1/L2/R1/R2。
## 只用于算展示用的占空比，不影响车体实际运动（见 _integrate_chassis）。
## 云台的 yaw_dir / pitch_dir 同理，因完全不影响仿真行为而不再读取
var _wheel_dirs: Array = [1, 1, 1, 1]
var _trigger_key_id: String = "E"
var _booster_key_id: String = "A"
var _trigger_time_ms: int = 250
var _friction_max_duty: int = BOOSTER_DUTY_MAX
## 拨弹模式：true=目视闭环（按住持续拨弹，松开即停，不阻塞），false=阻塞开环（单发）
var _visual_feed: bool = false
## 目视闭环模式下的出弹节流累加器（ms），按住扳机期间累积
var _feed_tick_ms: float = 0.0

# ------------------------------------------------------------------ 运行状态（对应 C 侧同名变量）
var _mode: int = Mode.OPERATE
## valueOfRoker[2][2]：左摇杆水平/竖直，右摇杆水平/竖直
var _roker: Array = [[0, 0], [0, 0]]
## valueOfKey[3][4]
var _key: Array = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
## 单独读取的扳机键与摩擦轮开关键
var _trigger_key: int = 0
var _booster_key: int = 0
var _last_trigger_key: int = 0
var _last_booster_key: int = 0
var _base_speed: int = 0
var _turn_speed: int = 0
## dutyOfMotor[0..3] = L1/L2/R1/R2，[4] = 拨弹
var _duty_motor: Array = [0, 0, 0, 0, 0]
## 云台电机驱动时的占空比
var _duty_gimbal: Array = [0, 0]
var _float_duty_servo: Array = [0.0, 0.0]
var _duty_servo: Array = [0, 0]
## 云台被限幅时的标记，状态行用
var _servo_clamped: Array = [false, false]
var _duty_booster: int = 0
var _status_booster: int = 0
## 摩擦轮启动阻塞序列距离下一级占空比的剩余时间
var _friction_ramp_ms: float = 0.0
## 1=阻塞增速，-1=阻塞减速，0=非摩擦轮阻塞状态
var _friction_ramp_direction: int = 0
## Ms_Delay 阻塞剩余时间（ms）。复现单发拨弹期间主循环停摆的副作用
var _block_ms: float = 0.0
var _sim_accum: float = 0.0

# ------------------------------------------------------------------ 车体位姿
## 底盘位置（米，世界坐标，y 恒为 0）与朝向（弧度，绕 +Y）
var _pos: Vector3 = Vector3.ZERO
var _heading: float = 0.0
## 云台角度（度）。舵机驱动时由 duty 反推，电机驱动时按角速度积分
var _yaw_deg: float = 0.0
var _pitch_deg: float = 0.0
## 各车轮累计转角（弧度），纯视觉
var _wheel_spin: Array = [0.0, 0.0, 0.0, 0.0]

# ------------------------------------------------------------------ 可调标定系数
var _speed_scale: float = SPEED_SCALE_DEFAULT
var _turn_rate: float = TURN_RATE_DEFAULT
var _muzzle_v_lo: float = MUZZLE_V_LO_DEFAULT
var _muzzle_v_hi: float = MUZZLE_V_HI_DEFAULT

# ------------------------------------------------------------------ 视图状态
## 跟随模式下是「相对车身」的偏移角（0 = 正车尾，视线沿车头正前方），
## 非跟随模式下是世界系绝对角
var _cam_yaw: float = 0.0
## 相机当前跟到的车头朝向（弧度）。平滑追随 _heading，不瞬时对齐
var _cam_heading: float = 0.0
var _cam_pitch: float = 0.45
var _cam_dist: float = 1.6
var _cam_pivot: Vector3 = Vector3.ZERO
var _orbiting: bool = false
var _panning: bool = false
var _follow: bool = true
var _tracer_enabled: bool = true

# ------------------------------------------------------------------ 场景对象
var _robot_root: Node3D = null
var _yaw_root: Node3D = null
var _pitch_root: Node3D = null
var _muzzle: Marker3D = null
var _wheel_nodes: Array = []
var _friction_nodes: Array = []
## 在场弹丸：[{body, born, trail}]
var _bullets: Array = []
## 已完成的弹道折线：[PackedVector3Array]
var _tracers: Array = []
## 最近一发的统计，状态行用
var _last_shot: Dictionary = {}

# ------------------------------------------------------------------ 音效状态
## 摩擦轮常驻音的播放缓冲。正弦波实时合成，音高 = 当前占空比
var _friction_playback: AudioStreamGeneratorPlayback = null
## 正弦波相位（弧度）。跨缓冲区必须连续，否则每帧接缝处会「咔哒」响
var _friction_phase: float = 0.0
## 当前实际发声的频率（Hz），平滑趋近目标频率
var _friction_freq: float = 0.0
## 开火音效播放缓冲与剩余待填样本数
var _shot_playback: AudioStreamGeneratorPlayback = null
var _shot_remain: int = 0
var _shot_phase: float = 0.0
var _shot_total: int = 0
## 音效总开关
var _audio_enabled: bool = true

# ------------------------------------------------------------------ 复用资源
var _bullet_shape: SphereShape3D = null
var _bullet_mesh: SphereMesh = null
var _mat_deck: StandardMaterial3D = null
var _mat_wheel: StandardMaterial3D = null
var _mat_gimbal: StandardMaterial3D = null
var _mat_barrel: StandardMaterial3D = null
## 摩擦轮材质。颜色随占空比逐帧改，因此两个轮子各持一份
## （共用也行，但分开日后想分别显示左右转速时不用再改）。
## 切记不要每帧 new 材质，会持续产生垃圾
var _mat_friction_wheels: Array = []
var _mat_bullet: StandardMaterial3D = null
var _mat_ground: StandardMaterial3D = null
var _mat_nose: StandardMaterial3D = null

# ------------------------------------------------------------------ 参数面板
var _sliders: Dictionary = {}
var _spins: Dictionary = {}
var _syncing: bool = false

# ------------------------------------------------------------------ 信号
## 返回配置界面时发出（由 ui.gd 连接）
signal closed
## 在仿真里改了云台归中角时发出，携带完整 cfg 供 ui.gd 回填
signal config_changed(cfg: Dictionary)


# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	_build_materials()
	_bullet_shape = SphereShape3D.new()
	_bullet_shape.radius = BULLET_RADIUS
	_bullet_mesh = SphereMesh.new()
	_bullet_mesh.radius = BULLET_RADIUS
	_bullet_mesh.height = BULLET_RADIUS * 2.0
	_bullet_mesh.radial_segments = 10
	_bullet_mesh.rings = 6
	_setup_audio()
	_connect_ui()
	# set_config 可能在 _ready 之前被调用（外部先 instantiate 再赋配置）
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
	var ft: Node = get_node_or_null(P_FOLLOW_TOGGLE)
	if ft is BaseButton:
		ft.toggled.connect(_on_follow_toggled)
	var tt: Node = get_node_or_null(P_TRACER_TOGGLE)
	if tt is BaseButton:
		tt.toggled.connect(_on_tracer_toggled)
	var tc: Node = get_node_or_null(P_TRACER_CLEAR)
	if tc is BaseButton:
		tc.pressed.connect(_clear_tracers)
	var rp: Node = get_node_or_null(P_RESET_POSE)
	if rp is BaseButton:
		rp.pressed.connect(_reset_pose)
	var rv: Node = get_node_or_null(P_RESET_VIEW)
	if rv is BaseButton:
		rv.pressed.connect(_reset_view)


func _on_back_pressed() -> void:
	_stop_audio()
	closed.emit()


## 场景被移除时也要停声（ui.gd 走 queue_free，不一定经过返回按钮）
func _exit_tree() -> void:
	_stop_audio()


# ------------------------------------------------------------------ 外部接口
## 由 ui.gd 传入 _collect_config() 的结果
func set_config(cfg: Dictionary) -> void:
	_cfg = cfg.duplicate(true)
	if is_inside_tree():
		_apply_config()


## 把仿真里标定出来的云台归中角通知 ui.gd 回填。
## _cfg 里的值已由 _on_mid_offset_changed 写成整数字符串
func _emit_config_changed() -> void:
	config_changed.emit(_cfg.duplicate(true))


# ------------------------------------------------------------------ 配置解析
func _apply_config() -> void:
	_max_speed = clampi(_cfg_int("normal_speed", 4000), 0, 10000)
	_ultra_speed = clampi(_cfg_int("sprint_speed", 8000), 0, 10000)
	_deadzone = clampi(_cfg_int("deadzone", 10), 0, 2047)
	_trigger_time_ms = clampi(_cfg_int("trigger_time", 250), 0, 65535)
	_friction_max_duty = clampi(_cfg_int("friction_max_duty", BOOSTER_DUTY_MAX),
		BOOSTER_DUTY_MIN, BOOSTER_DUTY_MAX)
	if _friction_max_duty % BOOSTER_STEP != 0:
		_friction_max_duty = BOOSTER_DUTY_MAX
	_visual_feed = str(_cfg.get("feed_mode", "阻塞开环")) == "目视闭环"
	_sprint_enabled = bool(_cfg.get("sprint_enabled", false))
	_zero_enabled = bool(_cfg.get("zero_enabled", false))
	_arrow_key = str(_cfg.get("arrow_key", "移动"))
	_yaw_is_servo = str(_cfg.get("yaw_drive", "舵机")) == "舵机"
	_pitch_is_servo = str(_cfg.get("pitch_drive", "舵机")) == "舵机"
	_wheel_dirs = [
		_dir_to_int(str(_cfg.get("l1_dir", "正向"))),
		_dir_to_int(str(_cfg.get("l2_dir", "正向"))),
		_dir_to_int(str(_cfg.get("r1_dir", "正向"))),
		_dir_to_int(str(_cfg.get("r2_dir", "正向"))),
	]
	_trigger_key_id = REMOTE_INPUT.CONFIG_KEY_TO_ID.get(str(_cfg.get("trigger_key", "E")), "E")
	_booster_key_id = REMOTE_INPUT.CONFIG_KEY_TO_ID.get(str(_cfg.get("booster_key", "A")), "A")
	# 云台数值语义（归中占空比 / 限幅边界 / 变化率）全部来自生成器
	_gp = _cg.gimbal_params(_cfg)
	_reset_control_state()
	_build_ground()
	_build_grid()
	_build_robot()
	_rebuild_params()
	_reset_pose()
	_reset_view()
	_update_config_label()
	_update_hint()
	_update_status()


## 控制状态归位到「上电」时刻
func _reset_control_state() -> void:
	_float_duty_servo = [float(_gp["yaw_mid"]), float(_gp["pitch_mid"])]
	_duty_servo = [int(_gp["yaw_mid"]), int(_gp["pitch_mid"])]
	_servo_clamped = [false, false]
	_duty_motor = [0, 0, 0, 0, 0]
	_duty_gimbal = [0, 0]
	_duty_booster = 0
	_status_booster = 0
	_friction_ramp_ms = 0.0
	_friction_ramp_direction = 0
	_base_speed = 0
	_turn_speed = 0
	_block_ms = 0.0
	_feed_tick_ms = 0.0
	_sim_accum = 0.0
	_last_trigger_key = 0
	_last_booster_key = 0
	_yaw_deg = 0.0
	_pitch_deg = 0.0
	_sync_gimbal_from_duty()


func _cfg_int(key: String, default_val: int) -> int:
	var s: String = str(_cfg.get(key, "")).strip_edges()
	if s.is_valid_int():
		return int(s)
	return default_val


func _dir_to_int(text: String) -> int:
	return 1 if text == "正向" else 0


func _update_config_label() -> void:
	var label: Node = get_node_or_null(P_CONFIG_LABEL)
	if label is Label:
		label.text = "Yaw %s ｜ Pitch %s ｜ 速度 %d / 冲刺 %d ｜ 拨弹 %s ｜ 摩擦轮 %s" % [
			"舵机" if _yaw_is_servo else "电机",
			"舵机" if _pitch_is_servo else "电机",
			_max_speed, _ultra_speed,
			"目视闭环" if _visual_feed else "阻塞开环",
			str(_cfg.get("booster_key", "A"))]


# ------------------------------------------------------------------ 材质
func _build_materials() -> void:
	_mat_deck = _make_material(Color(0.28, 0.32, 0.38), 0.6, 0.2)
	_mat_wheel = _make_material(Color(0.13, 0.14, 0.16), 0.85, 0.05)
	_mat_gimbal = _make_material(Color(0.42, 0.55, 0.72), 0.35, 0.45)
	_mat_barrel = _make_material(Color(0.83, 0.85, 0.88), 0.2, 0.7)
	_mat_friction_wheels = []
	for i in range(2):
		var m: StandardMaterial3D = _make_material(FRICTION_COLD, 0.5, 0.3)
		m.emission = FRICTION_HOT_HI
		_mat_friction_wheels.append(m)
	# 弹丸：绿色自发光。不受光照影响，否则飞进阴影里就看不见了
	_mat_bullet = _make_material(BULLET_COLOR, 0.4, 0.0)
	_mat_bullet.emission_enabled = true
	_mat_bullet.emission = BULLET_COLOR
	_mat_bullet.emission_energy_multiplier = BULLET_EMISSION_ENERGY
	_mat_ground = _make_material(Color(0.15, 0.16, 0.19), 0.9, 0.0)
	_mat_nose = StandardMaterial3D.new()
	_mat_nose.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_nose.albedo_color = Color(0.95, 0.72, 0.28)


func _make_material(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# ------------------------------------------------------------------ 地面
## 地面是弹丸的碰撞体，顶面在 y=0
func _build_ground() -> void:
	var ground: Node = get_node_or_null(P_GROUND)
	if not ground is StaticBody3D:
		return
	_clear_children(ground)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)
	ground.add_child(shape)
	var plane: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	plane.mesh = pm
	plane.material_override = _mat_ground
	plane.position = Vector3(0.0, -0.002, 0.0)
	ground.add_child(plane)


## 地面网格：0.5m 一格，边长 20m，方便目测射程
func _build_grid() -> void:
	var grid: Node = get_node_or_null(P_GRID)
	if not grid is MeshInstance3D:
		return
	var step: float = 0.5
	var half: int = 20
	var lim: float = float(half) * step
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-half, half + 1):
		var t: float = float(i) * step
		# 每 2m 一根亮线，便于读距离
		var bright: bool = absi(i) % 4 == 0
		var c: Color = Color(1, 1, 1, 0.22) if bright else Color(1, 1, 1, 0.08)
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(t, 0.0, -lim))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(t, 0.0, lim))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(-lim, 0.0, t))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(lim, 0.0, t))
	im.surface_end()
	grid.mesh = im
	grid.position = Vector3(0.0, 0.001, 0.0)


# ------------------------------------------------------------------ 车体（程序化）
## 底盘 + 四轮 + Yaw 座 + Pitch 云台 + 枪管 + 两个摩擦轮。
## 车头朝 -Z（Godot 惯例），Yaw 绕 +Y，Pitch 绕 +X（正角度抬头）。
func _build_robot() -> void:
	var root: Node = get_node_or_null(P_ROBOT)
	if not root is Node3D:
		return
	_clear_children(root)
	_robot_root = root
	_wheel_nodes.clear()
	_friction_nodes.clear()
	var deck_bottom: float = WHEEL_RADIUS * 2.0
	var deck_top: float = deck_bottom + DECK_THICK
	# 底盘板
	var deck: MeshInstance3D = MeshInstance3D.new()
	var dbox: BoxMesh = BoxMesh.new()
	dbox.size = Vector3(CHASSIS_WIDTH, DECK_THICK, CHASSIS_LEN)
	deck.mesh = dbox
	deck.material_override = _mat_deck
	deck.position = Vector3(0.0, deck_bottom + DECK_THICK * 0.5, 0.0)
	root.add_child(deck)
	# 四个轮子。顺序与 dutyOfMotor[0..3] 一致：L1 左前, L2 左后, R1 右前, R2 右后。
	# 轮心放在底盘板侧面以外半个轮宽处，让轮子整个露出来
	var wheel_x: float = CHASSIS_WIDTH * 0.5 + WHEEL_WIDTH * 0.5 + WHEEL_GAP
	var wheel_z: float = CHASSIS_LEN * 0.32
	var wheel_slots: Array = [
		Vector3(-wheel_x, WHEEL_RADIUS, -wheel_z),
		Vector3(-wheel_x, WHEEL_RADIUS, wheel_z),
		Vector3(wheel_x, WHEEL_RADIUS, -wheel_z),
		Vector3(wheel_x, WHEEL_RADIUS, wheel_z),
	]
	for i in range(4):
		var wheel: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = WHEEL_RADIUS
		cyl.bottom_radius = WHEEL_RADIUS
		cyl.height = WHEEL_WIDTH
		cyl.radial_segments = 18
		cyl.rings = 1
		wheel.mesh = cyl
		wheel.material_override = _mat_wheel
		wheel.position = wheel_slots[i]
		root.add_child(wheel)
		_wheel_nodes.append(wheel)
	# 车头三角，避免前后装反看不出来
	var nose: MeshInstance3D = MeshInstance3D.new()
	var nim: ImmediateMesh = ImmediateMesh.new()
	nim.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat_nose)
	for p in [Vector3(-CHASSIS_WIDTH * 0.3, 0.0, -CHASSIS_LEN * 0.5),
			Vector3(0.0, 0.0, -CHASSIS_LEN * 0.5 - 0.05),
			Vector3(CHASSIS_WIDTH * 0.3, 0.0, -CHASSIS_LEN * 0.5)]:
		nim.surface_add_vertex(p)
	nim.surface_end()
	nose.mesh = nim
	nose.position = Vector3(0.0, deck_top + 0.001, 0.0)
	root.add_child(nose)
	# Yaw 座（绕 Y 旋转的整个云台）
	_yaw_root = Node3D.new()
	_yaw_root.name = "YawRoot"
	_yaw_root.position = Vector3(0.0, deck_top, 0.0)
	root.add_child(_yaw_root)
	var yaw_base: MeshInstance3D = MeshInstance3D.new()
	var ybox: CylinderMesh = CylinderMesh.new()
	ybox.top_radius = GIMBAL_SIZE * 0.5
	ybox.bottom_radius = GIMBAL_SIZE * 0.6
	ybox.height = YAW_BASE_H
	ybox.radial_segments = 16
	ybox.rings = 1
	yaw_base.mesh = ybox
	yaw_base.material_override = _mat_gimbal
	yaw_base.position = Vector3(0.0, YAW_BASE_H * 0.5, 0.0)
	_yaw_root.add_child(yaw_base)
	# Pitch 轴（绕 X 旋转，正角度抬头）
	_pitch_root = Node3D.new()
	_pitch_root.name = "PitchRoot"
	_pitch_root.position = Vector3(0.0, YAW_BASE_H + GIMBAL_SIZE * 0.5, 0.0)
	_yaw_root.add_child(_pitch_root)
	var body: MeshInstance3D = MeshInstance3D.new()
	var bbox: BoxMesh = BoxMesh.new()
	bbox.size = Vector3(GIMBAL_SIZE * 1.4, GIMBAL_SIZE, GIMBAL_SIZE * 1.2)
	body.mesh = bbox
	body.material_override = _mat_gimbal
	_pitch_root.add_child(body)
	# 枪管：沿 -Z 伸出
	var barrel: MeshInstance3D = MeshInstance3D.new()
	var bcyl: CylinderMesh = CylinderMesh.new()
	bcyl.top_radius = BARREL_RADIUS
	bcyl.bottom_radius = BARREL_RADIUS
	bcyl.height = BARREL_LEN
	bcyl.radial_segments = 14
	bcyl.rings = 1
	barrel.mesh = bcyl
	barrel.material_override = _mat_barrel
	# CylinderMesh 默认沿 +Y，转到 -Z
	barrel.transform = Transform3D(
		Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP),
		Vector3(0.0, 0.0, -BARREL_LEN * 0.5))
	_pitch_root.add_child(barrel)
	# 两个摩擦轮，夹在枪管两侧。
	# 转轴竖直（Pitch 水平时垂直于地面），即 CylinderMesh 的默认 +Y 朝向，不需旋转。
	# 轮心离枪管轴 = 摩擦轮半径 + 枪管半径，使圆柱面正好与枪管相切（弹丸从缝里挤过去）。
	for sx in [-1.0, 1.0]:
		var fw: MeshInstance3D = MeshInstance3D.new()
		var fcyl: CylinderMesh = CylinderMesh.new()
		fcyl.top_radius = FRICTION_RADIUS
		fcyl.bottom_radius = FRICTION_RADIUS
		fcyl.height = FRICTION_WIDTH
		fcyl.radial_segments = 20
		fcyl.rings = 1
		fw.mesh = fcyl
		fw.position = Vector3(sx * (FRICTION_RADIUS + BARREL_RADIUS), 0.0, FRICTION_Z)
		_pitch_root.add_child(fw)
		_friction_nodes.append(fw)
	# 枪口：弹丸出生点
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, 0.0, -BARREL_LEN - BULLET_RADIUS * 2.0)
	_pitch_root.add_child(_muzzle)
	# 摩擦轮材质按当前占空比上色（新建时还没有 material_override）
	_update_friction_color()


## 同帧内可能重建多次（改配置/拖滑块），必须立即释放而非 queue_free，
## 否则旧节点会堆积（机械臂仿真踩过这个坑）
func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.free()


# ------------------------------------------------------------------ 输入采集
## 采样手柄与键盘，归一成 valueOfRoker / valueOfKey，复现 ReadControllerInputs
func _read_controller_inputs() -> void:
	var keyboard_enabled: bool = not _text_field_focused()
	var snapshot: Dictionary = REMOTE_INPUT.sample(
		_deadzone, _deadzone, keyboard_enabled, not _mouse_over_ui())
	_roker = snapshot["valueOfRoker"].duplicate(true)
	_key = snapshot["valueOfKey"].duplicate(true)
	var pressed: Dictionary = snapshot["pressed"]
	_trigger_key = 1 if pressed.has(_trigger_key_id) else 0
	_booster_key = 1 if pressed.has(_booster_key_id) else 0


## 当前焦点是否落在可输入文本的控件上（否则输入 W/S 会同时开车）
func _text_field_focused() -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var f: Control = vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## 鼠标是否悬在面板控件上。开火绑了鼠标左键，
## 故拖侧栏滑块或点顶栏按钮时必须抑制，否则会误发弹
func _mouse_over_ui() -> bool:
	var pos: Vector2 = get_global_mouse_position()
	for path in [P_SIDE_PANEL, P_TOP_PANEL]:
		var panel: Node = get_node_or_null(path)
		if panel is Control and panel.visible \
				and panel.get_global_rect().has_point(pos):
			return true
	return false


# ------------------------------------------------------------------ 主循环（定步 10ms）
func _process(delta: float) -> void:
	_sim_accum += delta * 1000.0
	var steps: int = int(_sim_accum / SIM_STEP_MS)
	if steps > 0:
		_sim_accum -= float(steps) * SIM_STEP_MS
		steps = mini(steps, MAX_STEPS_PER_FRAME)
		for _s in range(steps):
			_tick()
	_update_bullets(delta)
	_render_robot()
	_update_camera(delta)
	_update_friction_audio(delta)
	_update_shot_audio()
	_update_status()


## 一个完整的 10ms 周期：采输入 + 走一趟主循环。
## 拨弹或摩擦轮增速期间 C 端卡在 Ms_Delay 里，主循环整体停摆。
func _tick() -> void:
	if _friction_ramp_ms > 0.0:
		_friction_ramp_ms -= SIM_STEP_MS
		if _friction_ramp_ms <= 0.0:
			if _friction_ramp_direction > 0 and _duty_booster < _friction_max_duty:
				_duty_booster = mini(_duty_booster + BOOSTER_STEP, _friction_max_duty)
				# 到达最大值后仍保持一个 1500ms 安全间隔，随后才恢复主循环。
				_friction_ramp_ms = BOOSTER_STEP_MS
			elif _friction_ramp_direction < 0 and _duty_booster > BOOSTER_DUTY_MIN:
				_duty_booster -= BOOSTER_STEP
				_friction_ramp_ms = BOOSTER_STEP_MS
			elif _friction_ramp_direction < 0 and _duty_booster == BOOSTER_DUTY_MIN:
				_duty_booster = 0
				_friction_ramp_ms = BOOSTER_STEP_MS
			else:
				_friction_ramp_direction = 0
		return
	if _block_ms > 0.0:
		_block_ms -= SIM_STEP_MS
		return
	_read_controller_inputs()
	_step_once()


## 主循环一趟（不含输入采集），对应生成的 C 里
## CalculateMotorControls -> CalculateGimbalControls -> CalculateBoosterControl
## -> LIMIT_VALUE -> 单发拨弹 -> 摩擦轮渐变 的顺序。
## 输入采集独立成 _tick，测试可直接灌 _roker / _key 后调用本函数。
func _step_once() -> void:
	_calculate_motor_controls()
	if _mode == Mode.OPERATE:
		_calculate_gimbal_controls()
	_calculate_booster_control()
	# 限幅（对应 C 侧 LIMIT_VALUE）
	for i in range(4):
		_duty_motor[i] = clampi(_duty_motor[i], -10000, 10000)
	_duty_motor[4] = clampi(_duty_motor[4], 0, 10000)
	if _mode == Mode.OPERATE:
		_limit_servo()
	# 拨弹（两种模式与生成的 C 一一对应）：
	# 目视闭环：按住持续拨弹、松开即停，不阻塞主循环；按住期间按 FEED_INTERVAL_MS 连续出弹
	# 阻塞开环：扳机上升沿触发一发，转动 trigger_time 后停转，期间阻塞主循环
	if _visual_feed:
		_duty_motor[4] = clampi(_cfg_int("trigger_speed", 10000), 0, 10000) \
			if _trigger_key == 1 else 0
		_last_trigger_key = _trigger_key
		if _trigger_key == 1:
			_feed_tick_ms += SIM_STEP_MS
			while _feed_tick_ms >= FEED_INTERVAL_MS:
				_feed_tick_ms -= FEED_INTERVAL_MS
				_fire()
	else:
		if _trigger_key == 1 and _last_trigger_key == 0:
			_duty_motor[4] = clampi(_cfg_int("trigger_speed", 10000), 0, 10000)
			_fire()
			_block_ms = float(_trigger_time_ms)
			_last_trigger_key = _trigger_key
			return
		_last_trigger_key = _trigger_key
	_integrate_chassis()
	_sync_gimbal_from_duty()


## 对应 CalculateMotorControls
func _calculate_motor_controls() -> void:
	var speed: int = _max_speed
	# 冲刺模式：按下左摇杆（valueOfKey[2][0]）时用冲刺速度
	if _sprint_enabled and _key[2][0] == 1:
		speed = _ultra_speed
	# 符号约定：baseSpeed > 0 = 前进，turnSpeed > 0 = 向右转。
	# 这个约定对用户是固定的，与他们怎么接线无关：接线方向由 l1_dir 等配置
	# 在电机公式里消化，绝不能反过来影响操作方向
	_base_speed = int(float(_roker[0][1]) * float(speed) / ROKER_FULL)
	_turn_speed = int(float(_roker[0][0]) * float(speed) / ROKER_FULL)
	# 方向键：按配置决定是移动、冲刺还是不参与
	if _arrow_key == "移动" or _arrow_key == "冲刺":
		var v: int = _ultra_speed if _arrow_key == "冲刺" else _max_speed
		if _key[0][0] == 1:
			_base_speed = v
		if _key[0][1] == 1:
			_base_speed = -v
		if _key[0][2] == 1:
			_turn_speed = -v
		if _key[0][3] == 1:
			_turn_speed = v
	# 四个底盘电机的占空比公式与生成的 C 逐字一致。
	# 注意：这些值只用于状态行展示与车轮视觉，不参与车体运动积分。
	# 原因见 _integrate_chassis：接线方向不得影响操作方向。
	_duty_motor[0] = _wheel_duty(0, _base_speed + _turn_speed)
	_duty_motor[1] = _wheel_duty(1, _base_speed + _turn_speed)
	_duty_motor[2] = _wheel_duty(2, -_base_speed + _turn_speed)
	_duty_motor[3] = _wheel_duty(3, -_base_speed + _turn_speed)
	# D 键停拨弹
	if _key[1][3] == 1:
		_duty_motor[4] = 0


## 生成的 C 里：正向 -> "-baseSpeed - turnSpeed"，反向 -> "baseSpeed + turnSpeed"
func _wheel_duty(idx: int, raw: int) -> int:
	return -raw if _wheel_dirs[idx] == 1 else raw


## 对应 CalculateGimbalControls
func _calculate_gimbal_controls() -> void:
	var rate: float = _gp["rate"]
	# 电机驱动时生成的 C 会根据 yaw_dir / pitch_dir 给占空比取反，
	# 但那是在补偿接线；对用户而言推杆方向与云台转向的关系是固定的，
	# 故仿真这里不跟着取反（见 _sync_gimbal_from_duty 同类处理）
	if _yaw_is_servo:
		_float_duty_servo[0] += float(_roker[1][0]) * rate
	else:
		_duty_gimbal[0] = int(float(_roker[1][0]) * float(_ultra_speed) / ROKER_FULL)
	if _pitch_is_servo:
		_float_duty_servo[1] += float(_roker[1][1]) * rate
	else:
		_duty_gimbal[1] = int(float(_roker[1][1]) * float(_ultra_speed) / ROKER_FULL)
	# 按下右摇杆云台归中（仅在配置里勾了「归中」才有）
	if _zero_enabled and _key[2][1] == 1:
		if _yaw_is_servo:
			_float_duty_servo[0] = float(_gp["yaw_mid"])
		if _pitch_is_servo:
			_float_duty_servo[1] = float(_gp["pitch_mid"])
	_duty_servo[0] = int(_float_duty_servo[0])
	_duty_servo[1] = int(_float_duty_servo[1])


## 云台舵机限幅。边界由 gimbal_params 给出，已同时收敛到
## 「归中角 ±摆动幅度」与舵机物理行程之内
func _limit_servo() -> void:
	_servo_clamped = [false, false]
	if _yaw_is_servo:
		var lo: float = float(_gp["yaw_lo"])
		var hi: float = float(_gp["yaw_hi"])
		if _float_duty_servo[0] < lo:
			_float_duty_servo[0] = lo
			_servo_clamped[0] = true
		elif _float_duty_servo[0] > hi:
			_float_duty_servo[0] = hi
			_servo_clamped[0] = true
		_duty_servo[0] = int(_float_duty_servo[0])
	if _pitch_is_servo:
		var plo: float = float(_gp["pitch_lo"])
		var pitch_upper: float = float(_gp["pitch_hi"])
		if _float_duty_servo[1] < plo:
			_float_duty_servo[1] = plo
			_servo_clamped[1] = true
		elif _float_duty_servo[1] > pitch_upper:
			_float_duty_servo[1] = pitch_upper
			_servo_clamped[1] = true
		_duty_servo[1] = int(_float_duty_servo[1])


## 对应 CalculateBoosterControl：只有开/关；开启后按官方规则阻塞增速
func _calculate_booster_control() -> void:
	if _booster_key == 1 and _last_booster_key == 0:
		_status_booster = 0 if _status_booster == 1 else 1
		if _status_booster == 1:
			_duty_booster = BOOSTER_DUTY_MIN
			_friction_ramp_direction = 1
			_friction_ramp_ms = BOOSTER_STEP_MS
		else:
			# 禁止高速直接断电：保持当前 duty，随后每 1500ms 减少 100，
			# 经 500 后才降到 0，并在 0 duty 再等待一个安全间隔。
			_friction_ramp_direction = -1
			_friction_ramp_ms = BOOSTER_STEP_MS
	_last_booster_key = _booster_key


# ------------------------------------------------------------------ 底盘运动
## 差速积分。直接用 baseSpeed / turnSpeed，**不用各轮占空比反推**。
##
## 这是个刻意的选择：用户把某个电机配成「反向」，意思是它的线接反了、
## 靠这个配置去补偿；补偿到位后车在物理上就是正常跑的。若仿真从占空比
## 反推运动，配了反向的车在仿真里会倒着跑——那是把「正确的补偿」当成
## 错误来展示，不对。
##
## 输入到运动的方向关系对用户永远固定：推前就前进、推右就向右转。
## 接线方向是硬件层面的事，已在生成的 C 电机公式里消化完。
func _integrate_chassis() -> void:
	var dt: float = SIM_STEP_MS / 1000.0
	var linear: float = float(_base_speed) / 10000.0 * _speed_scale
	# turnSpeed > 0 = 向右转；heading 绕 +Y，正值 = 向左，故取负
	var omega: float = - float(_turn_speed) / 10000.0 * deg_to_rad(_turn_rate)
	_heading += omega * dt
	_heading = wrapf(_heading, -PI, PI)
	# 车头朝 -Z
	var fwd: Vector3 = Vector3(-sin(_heading), 0.0, -cos(_heading))
	_pos += fwd * linear * dt
	# 车轮转动（纯视觉）：按各轮在车上的应有转速，同样不看接线方向
	var v_left: float = float(_base_speed + _turn_speed)
	var v_right: float = float(_base_speed - _turn_speed)
	for i in range(4):
		var v: float = v_left if i < 2 else v_right
		_wheel_spin[i] += v / 10000.0 * _speed_scale / WHEEL_RADIUS * dt


# ------------------------------------------------------------------ 云台角度
## 占空比 -> 角度（度）。舵机：由 duty 反推；电机：按角速度积分
func _sync_gimbal_from_duty() -> void:
	var dpd: float = _gp.get("duty_per_deg", 1000.0 / 180.0)
	var dt: float = SIM_STEP_MS / 1000.0
	# 方向配置（yaw_dir / pitch_dir）是给接反的线做补偿用的，补偿到位后
	# 云台在物理上就是按用户推杆方向转的，故这里不取反
	if _yaw_is_servo:
		_yaw_deg = (float(_duty_servo[0]) - float(CodeGenBase.SERVO_DUTY_MID)) / dpd
	else:
		_yaw_deg += float(_duty_gimbal[0]) / 10000.0 * GIMBAL_MOTOR_RATE * dt
	if _pitch_is_servo:
		_pitch_deg = (float(_duty_servo[1]) - float(CodeGenBase.SERVO_DUTY_MID)) / dpd
	else:
		_pitch_deg += float(_duty_gimbal[1]) / 10000.0 * GIMBAL_MOTOR_RATE * dt
		# 电机驱动没有位置反馈，真机会一直转到撞机械限位，这里给一个限位
		_pitch_deg = clampf(_pitch_deg, -GIMBAL_MOTOR_PITCH_LIMIT, GIMBAL_MOTOR_PITCH_LIMIT)


func _render_robot() -> void:
	if _robot_root == null or not is_instance_valid(_robot_root):
		return
	_robot_root.position = _pos
	_robot_root.rotation = Vector3(0.0, _heading, 0.0)
	if _yaw_root != null:
		# 舵机角正方向定义为「云台向右」，Godot 的 +Y 旋转是向左，故取负
		_yaw_root.rotation = Vector3(0.0, -deg_to_rad(_yaw_deg), 0.0)
	if _pitch_root != null:
		_pitch_root.rotation = Vector3(deg_to_rad(_pitch_deg), 0.0, 0.0)
	for i in range(_wheel_nodes.size()):
		var w: MeshInstance3D = _wheel_nodes[i]
		# 轮轴沿 X：先把圆柱的 +Y 转到 X，再绕 X 自转
		w.transform = Transform3D(
			Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).rotated(
				Vector3.RIGHT, _wheel_spin[i]) * Basis(Vector3.UP, Vector3.RIGHT, Vector3.BACK),
			w.position)
	_update_friction_color()


## 摩擦轮颜色随占空比连续渐变：
## 未启动（< 500）冷灰，500 橙色，1100 橙红，中间线性插值。
func _update_friction_color() -> void:
	var t: float = -1.0
	if _duty_booster >= BOOSTER_DUTY_MIN:
		t = clampf(float(_duty_booster - BOOSTER_DUTY_MIN)
			/ float(BOOSTER_DUTY_MAX - BOOSTER_DUTY_MIN), 0.0, 1.0)
	for i in range(_friction_nodes.size()):
		if i >= _mat_friction_wheels.size():
			break
		var m: StandardMaterial3D = _mat_friction_wheels[i]
		if t < 0.0:
			m.albedo_color = FRICTION_COLD
			m.emission_enabled = false
		else:
			var c: Color = FRICTION_HOT_LO.lerp(FRICTION_HOT_HI, t)
			m.albedo_color = c
			# 转速越高越亮，低速时几乎不发光
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = FRICTION_EMISSION_MAX * t
		_friction_nodes[i].material_override = m


# ------------------------------------------------------------------ 弹丸
## 摩擦轮当前占空比 -> 出膛速度（m/s）
func _muzzle_speed() -> float:
	if _duty_booster < int(MUZZLE_DUTY_LO):
		return MUZZLE_V_DEAD
	var t: float = clampf(
		(float(_duty_booster) - MUZZLE_DUTY_LO) / (MUZZLE_DUTY_HI - MUZZLE_DUTY_LO), 0.0, 1.0)
	return lerpf(_muzzle_v_lo, _muzzle_v_hi, t)


func _fire() -> void:
	var holder: Node = get_node_or_null(P_BULLETS)
	if not holder is Node3D or _muzzle == null:
		return
	var xf: Transform3D = _muzzle.global_transform
	var speed: float = _muzzle_speed()
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = BULLET_MASS
	# 30m/s 的弹丸一帧能走 0.5m，不开连续碰撞检测会直接穿过地面
	body.continuous_cd = true
	body.contact_monitor = false
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = _bullet_shape
	body.add_child(col)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = _bullet_mesh
	mesh.material_override = _mat_bullet
	body.add_child(mesh)
	holder.add_child(body)
	body.global_transform = Transform3D(Basis(), xf.origin)
	# 枪口朝向就是 -Z
	body.linear_velocity = - xf.basis.z.normalized() * speed
	var trail: PackedVector3Array = PackedVector3Array()
	trail.append(xf.origin)
	_bullets.append({
		"body": body,
		"born": Time.get_ticks_msec(),
		"origin": xf.origin,
		"speed": speed,
		"trail": trail,
		"peak": xf.origin.y,
	})
	_last_shot = {
		"speed": speed, "duty": _duty_booster,
		"range": 0.0, "flight": 0.0, "peak": 0.0,
	}
	_play_shot_sound()
	# 超出上限时释放最旧的一发
	while _bullets.size() > BULLET_MAX_ALIVE:
		_retire_bullet(0)


func _update_bullets(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var i: int = _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		var body: Node = b["body"]
		if body == null or not is_instance_valid(body):
			_bullets.remove_at(i)
			i -= 1
			continue
		var rb: RigidBody3D = body as RigidBody3D
		var p: Vector3 = rb.global_position
		var trail: PackedVector3Array = b["trail"]
		if trail.size() == 0 or trail[trail.size() - 1].distance_to(p) > 0.01:
			if trail.size() < TRACER_MAX_POINTS:
				trail.append(p)
				b["trail"] = trail
		b["peak"] = maxf(float(b["peak"]), p.y)
		var age: float = float(now - int(b["born"])) / 1000.0
		# 落地或超时即回收：贴地且几乎不动就算落定
		var landed: bool = p.y <= BULLET_RADIUS * 1.5 and rb.linear_velocity.length() < 0.4
		if landed or age > BULLET_LIFE_SEC:
			_last_shot["range"] = Vector2(p.x - float(b["origin"].x),
				p.z - float(b["origin"].z)).length()
			_last_shot["flight"] = age
			_last_shot["peak"] = float(b["peak"])
			_retire_bullet(i)
		i -= 1
	_redraw_tracers()


## 回收一发弹丸，把它的弹道折线存进 _tracers
func _retire_bullet(idx: int) -> void:
	if idx < 0 or idx >= _bullets.size():
		return
	var b: Dictionary = _bullets[idx]
	var trail: PackedVector3Array = b["trail"]
	if _tracer_enabled and trail.size() >= 2:
		_tracers.append(trail)
		while _tracers.size() > TRACER_MAX_TRAILS:
			_tracers.pop_front()
	var body: Node = b["body"]
	if body != null and is_instance_valid(body):
		body.queue_free()
	_bullets.remove_at(idx)


## 弹道折线：已落地的用 _tracers，在飞的实时画
func _redraw_tracers() -> void:
	var node: Node = get_node_or_null(P_TRACERS)
	if not node is MeshInstance3D:
		return
	if not _tracer_enabled:
		node.mesh = null
		return
	# 已落地的在前、在飞的在后，即按时间先后排序
	var lines: Array = []
	for t in _tracers:
		lines.append(t)
	for b in _bullets:
		lines.append(b["trail"])
	# 只保留最近五条。_tracers 自身已限长，但加上在飞的仍可能超出
	if lines.size() > TRACER_MAX_TRAILS:
		lines = lines.slice(lines.size() - TRACER_MAX_TRAILS)
	var any: bool = false
	for l in lines:
		if l.size() >= 2:
			any = true
			break
	if not any:
		node.mesh = null
		return
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for li in range(lines.size()):
		var pts: PackedVector3Array = lines[li]
		if pts.size() < 2:
			continue
		# 越旧越淡
		var fade: float = 0.25 + 0.65 * (float(li + 1) / float(lines.size()))
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for p in pts:
			# 弹道跟弹丸同色，一眼能对上是哪发打出来的
			im.surface_set_color(Color(BULLET_COLOR.r, BULLET_COLOR.g, BULLET_COLOR.b, fade))
			im.surface_add_vertex(p)
		im.surface_end()
	node.mesh = im


func _clear_tracers() -> void:
	_tracers.clear()
	_redraw_tracers()


func _on_tracer_toggled(on: bool) -> void:
	_tracer_enabled = on
	if not on:
		_clear_tracers()


func _on_audio_toggled(on: bool) -> void:
	_audio_enabled = on
	if not on:
		_stop_audio()


# ------------------------------------------------------------------ 音效
## 两个 AudioStreamGenerator：摩擦轮常驻音 + 开火短音。
## 用实时合成而非音频文件，是因为音高要精确等于占空比数值。
func _setup_audio() -> void:
	var fp: Node = get_node_or_null(P_FRICTION_AUDIO)
	if fp is AudioStreamPlayer:
		var gen: AudioStreamGenerator = AudioStreamGenerator.new()
		gen.mix_rate = AUDIO_SAMPLE_RATE
		# 缓冲越短延迟越低；0.1s 足够平滑又不会让音高变化拖尾
		gen.buffer_length = 0.1
		fp.stream = gen
		fp.volume_db = linear_to_db(FRICTION_VOLUME)
	var sp: Node = get_node_or_null(P_SHOT_AUDIO)
	if sp is AudioStreamPlayer:
		var gen2: AudioStreamGenerator = AudioStreamGenerator.new()
		gen2.mix_rate = AUDIO_SAMPLE_RATE
		gen2.buffer_length = 0.2
		sp.stream = gen2
		sp.volume_db = linear_to_db(SHOT_VOLUME)


## 摩擦轮目标频率（Hz）= 当前占空比数值。未启动时为 0（静音）
func _friction_target_freq() -> float:
	if _duty_booster < BOOSTER_DUTY_MIN:
		return 0.0
	return float(_duty_booster)


## 每帧推进摩擦轮常驻音：按占空比调音高，填满可用缓冲
func _update_friction_audio(delta: float) -> void:
	var player: Node = get_node_or_null(P_FRICTION_AUDIO)
	if not player is AudioStreamPlayer:
		return
	var target: float = _friction_target_freq() if _audio_enabled else 0.0
	if target <= 0.0:
		# 停机：直接停播，避免残留缓冲继续发声
		if player.playing:
			player.stop()
		_friction_playback = null
		_friction_freq = 0.0
		return
	if not player.playing:
		player.play()
		_friction_playback = player.get_stream_playback()
		# 从目标频率起步，不然开机瞬间会从 0Hz 扫上来
		_friction_freq = target
		_friction_phase = 0.0
	if _friction_playback == null:
		_friction_playback = player.get_stream_playback()
	if _friction_playback == null:
		return
	# 平滑趋近：占空比每 10ms 变 1，直接跟会有台阶感
	var t: float = 1.0 - exp(-FRICTION_PITCH_LERP * delta)
	_friction_freq = lerpf(_friction_freq, target, t)
	_fill_sine(_friction_playback, _friction_freq)


## 往缓冲里填正弦波。相位跨调用连续，否则接缝处会「咔哒」响
func _fill_sine(pb: AudioStreamGeneratorPlayback, freq: float) -> void:
	var frames: int = pb.get_frames_available()
	if frames <= 0:
		return
	var step: float = TAU * freq / AUDIO_SAMPLE_RATE
	for i in range(frames):
		var v: float = sin(_friction_phase)
		pb.push_frame(Vector2(v, v))
		_friction_phase += step
	_friction_phase = fmod(_friction_phase, TAU)


## 开火：起一段从高到低的扫频短音，带指数衰减包络，听着像「啪」
func _play_shot_sound() -> void:
	if not _audio_enabled:
		return
	var player: Node = get_node_or_null(P_SHOT_AUDIO)
	if not player is AudioStreamPlayer:
		return
	player.stop()
	player.play()
	_shot_playback = player.get_stream_playback()
	_shot_total = int(SHOT_DURATION * AUDIO_SAMPLE_RATE)
	_shot_remain = _shot_total
	_shot_phase = 0.0


## 每帧把开火音效剩余部分填进缓冲
func _update_shot_audio() -> void:
	if _shot_playback == null or _shot_remain <= 0:
		return
	var frames: int = mini(_shot_playback.get_frames_available(), _shot_remain)
	for i in range(frames):
		# 进度 0->1 对应频率从 HI 扫到 LO、音量指数衰减
		var p: float = 1.0 - float(_shot_remain) / float(_shot_total)
		var freq: float = lerpf(SHOT_FREQ_HI, SHOT_FREQ_LO, p)
		var env: float = exp(-5.0 * p)
		var v: float = sin(_shot_phase) * env
		_shot_playback.push_frame(Vector2(v, v))
		_shot_phase = fmod(_shot_phase + TAU * freq / AUDIO_SAMPLE_RATE, TAU)
		_shot_remain -= 1
	if _shot_remain <= 0:
		_shot_playback = null


## 离开仿真时必须停声，否则返回配置界面后摩擦轮还在响
func _stop_audio() -> void:
	for path in [P_FRICTION_AUDIO, P_SHOT_AUDIO]:
		var p: Node = get_node_or_null(path)
		if p is AudioStreamPlayer and p.playing:
			p.stop()
	_friction_playback = null
	_shot_playback = null
	_shot_remain = 0


# ------------------------------------------------------------------ 归位
func _reset_pose() -> void:
	_pos = Vector3.ZERO
	_heading = 0.0
	_cam_heading = 0.0
	_wheel_spin = [0.0, 0.0, 0.0, 0.0]
	for i in range(_bullets.size() - 1, -1, -1):
		var body: Node = _bullets[i]["body"]
		if body != null and is_instance_valid(body):
			body.queue_free()
	_bullets.clear()
	_clear_tracers()
	_reset_control_state()
	_render_robot()


# ------------------------------------------------------------------ 相机
## 切换跟随时要补偿 _cam_yaw，否则视角会突变：
## 跟随模式下 _cam_yaw 是「相对车身」的偏移，非跟随时是世界系绝对角。
## 重新开启跟随时必须先把 _cam_heading 拉到车当前朝向——它在非跟随期间不再更新，
## 直接拿旧值做补偿会算出错误的偏移（踩过）。
func _on_follow_toggled(on: bool) -> void:
	if on == _follow:
		return
	if on:
		_cam_heading = _heading
		_cam_yaw = wrapf(_cam_yaw - _cam_heading, -PI, PI)
	else:
		_cam_yaw = wrapf(_cam_yaw + _cam_heading, -PI, PI)
	_follow = on
	_update_camera()


func _reset_view() -> void:
	# 跟随模式下这是相对车尾的偏移角，0 = 相机正在车尾、视线沿车头正前方
	_cam_yaw = 0.0
	_cam_pitch = 0.42
	_cam_dist = 1.6
	_cam_pivot = _pos + Vector3(0.0, 0.12, 0.0)
	# 重置视角时相机朝向立即对齐车头，不走平滑
	_cam_heading = _heading
	_update_camera()


## delta > 0 时相机朝向平滑跟向车头；delta = 0 表示立即对齐。
## 不平滑的话，原地转向默认 360°/s 会让画面每秒转一整圈，看着很晕
func _update_camera(delta: float = 0.0) -> void:
	var cam: Node = get_node_or_null(P_CAMERA)
	if not cam is Camera3D:
		return
	if _follow:
		_cam_pivot = _pos + Vector3(0.0, 0.12, 0.0)
		if delta > 0.0:
			# 指数靠近：每秒补上差值的 CAM_FOLLOW_LERP 倍，与帧率无关
			var t: float = 1.0 - exp(-CAM_FOLLOW_LERP * delta)
			_cam_heading = lerp_angle(_cam_heading, _heading, t)
		else:
			_cam_heading = _heading
	# 跟随时相机绕到车尾，朝向与车头一致；非跟随时 _cam_yaw 就是绝对角
	var yaw: float = (_cam_heading + _cam_yaw) if _follow else _cam_yaw
	var offset: Vector3 = Vector3(
		_cam_dist * cos(_cam_pitch) * sin(yaw),
		_cam_dist * sin(_cam_pitch),
		_cam_dist * cos(_cam_pitch) * cos(yaw))
	cam.position = _cam_pivot + offset
	cam.look_at(_cam_pivot, Vector3.UP)


## 在 GUI 处理之前吞掉手柄事件。
##
## 手柄输入全走 Input 单例轮询（见 _read_controller_inputs），不靠事件，
## 而 Godot 默认把摇杆/十字键映射成 ui_left/ui_right 等 UI 导航动作：
## 不拦的话推摇杆会同时改动侧栏滑块、按 A 键会误触按钮。
## _input 在 GUI 事件分发之前调用，在这里标已处理即可隔绝。
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(e: InputEventMouseButton) -> void:
	# 鼠标在侧栏/顶栏上时不动相机：侧栏滑到头时 ScrollContainer 不再消耗滚轮，
	# 事件会冒泡到根节点，导致滚列表的同时把镜头拉远拉近
	if e.pressed and _mouse_over_ui():
		return
	match e.button_index:
		MOUSE_BUTTON_RIGHT:
			_orbiting = e.pressed
			accept_event()
		MOUSE_BUTTON_MIDDLE:
			_panning = e.pressed
			accept_event()
		MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(0.3, _cam_dist * 0.9)
			_update_camera()
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(80.0, _cam_dist * 1.1)
			_update_camera()
			accept_event()


func _handle_mouse_motion(e: InputEventMouseMotion) -> void:
	if _orbiting:
		_cam_yaw -= e.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch + e.relative.y * 0.008, -CAM_PITCH_LIMIT, CAM_PITCH_LIMIT)
		_update_camera()
		accept_event()
	elif _panning:
		var cam: Node = get_node_or_null(P_CAMERA)
		if cam is Camera3D:
			# 手动平移就当用户想脱离跟随，否则下一帧又被拉回车上
			var f: Node = get_node_or_null(P_FOLLOW_TOGGLE)
			if f is BaseButton and f.button_pressed:
				f.button_pressed = false
			var scale: float = _cam_dist * 0.0015
			var basis: Basis = cam.global_transform.basis
			_cam_pivot -= basis.x * e.relative.x * scale
			_cam_pivot += basis.y * e.relative.y * scale
			_update_camera()
		accept_event()


# ------------------------------------------------------------------ 模式
func _on_mode_selected(idx: int) -> void:
	_mode = idx
	_rebuild_params()
	_update_hint()
	_update_status()


func _update_hint() -> void:
	var label: Node = get_node_or_null(P_HINT)
	if not label is Label:
		return
	var base: String = "右键旋转视角 · 滚轮缩放 · 中键平移"
	match _mode:
		Mode.OPERATE:
			var pads: Array = Input.get_connected_joypads()
			var pad_txt: String = "未检测到手柄"
			if pads.size() > 0:
				pad_txt = "手柄：%s" % Input.get_joy_name(pads[0])
			label.text = "%s ｜ WASD 左摇杆(底盘) · IJKL 右摇杆(云台) · 1/2/3/4 = A/B/C/D · %s ｜ %s" % [
				base, "鼠标左键/RT 发射 · Shift 冲刺 · Z 归中", pad_txt]
		Mode.CALIB:
			label.text = "%s ｜ 标定模式下摇杆不动云台，用滑块摆到实际中位再存" % base
		_:
			label.text = base


# ------------------------------------------------------------------ 参数面板
func _rebuild_params() -> void:
	var params: Node = get_node_or_null(P_PARAMS)
	if params == null:
		return
	for c in params.get_children():
		c.queue_free()
	_sliders.clear()
	_spins.clear()
	match _mode:
		Mode.OPERATE:
			_build_operate_params(params)
		Mode.CALIB:
			_build_calib_params(params)


func _add_section(parent: Node, text: String) -> void:
	var sep: HSeparator = HSeparator.new()
	parent.add_child(sep)
	var l: Label = Label.new()
	l.text = text
	parent.add_child(l)


func _add_note(parent: Node, text: String) -> void:
	var l: Label = Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	spin.value = clampf(value, lo, hi)
	spin.custom_minimum_size = Vector2(96, 0)
	head.add_child(spin)
	var slider: HSlider = HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = clampf(value, lo, hi)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slider)
	_sliders[key] = slider
	_spins[key] = spin
	slider.value_changed.connect(_on_param_changed.bind(key, spin))
	spin.value_changed.connect(_on_param_changed.bind(key, slider))


func _on_param_changed(value: float, key: String, peer: Node) -> void:
	if _syncing:
		return
	_syncing = true
	if peer is Range:
		peer.value = value
	_syncing = false
	match key:
		"spdscale": _speed_scale = value
		"turnrate": _turn_rate = value
		"vlo": _muzzle_v_lo = value
		"vhi": _muzzle_v_hi = value
		"yawmid", "pitchmid":
			_on_mid_offset_changed(key, value)
	_update_status()


## 标定模式改归中角：重算限幅边界并把云台摆到新中位
func _on_mid_offset_changed(key: String, value: float) -> void:
	var deg: int = clampi(int(round(value)), -CodeGenBase.SERVO_MAX_OFFSET_DEG,
		CodeGenBase.SERVO_MAX_OFFSET_DEG)
	if key == "yawmid":
		_cfg["yaw_mid_offset"] = str(deg)
	else:
		_cfg["pitch_mid_offset"] = str(deg)
	_gp = _cg.gimbal_params(_cfg)
	_float_duty_servo = [float(_gp["yaw_mid"]), float(_gp["pitch_mid"])]
	_duty_servo = [int(_gp["yaw_mid"]), int(_gp["pitch_mid"])]
	_sync_gimbal_from_duty()
	_render_robot()
	_emit_config_changed()


# --- 操控模式
func _build_operate_params(parent: Node) -> void:
	_add_section(parent, "摩擦轮")
	_add_note(parent, ("只有开/关两种稳态。开关键 %s 上升沿翻转；开启时从 500 duty 起步，"
		+ "每 1500ms 阻塞增加 100，直到用户设定的 %d；关闭时按相同间隔逐级降至 0。")
			% [str(_cfg.get("booster_key", "A")), _friction_max_duty])
	_add_section(parent, "音效")
	var audio_cb: CheckButton = CheckButton.new()
	audio_cb.text = "音效"
	audio_cb.button_pressed = _audio_enabled
	audio_cb.toggled.connect(_on_audio_toggled)
	parent.add_child(audio_cb)
	_add_note(parent, "摩擦轮音高等于当前占空比，阻塞爬升的每一级都能听出来。"
		+"\n开火是一段从高扫到低的短音。")
	_add_section(parent, "弹丸初速映射")
	_add_slider_row(parent, "vlo", "duty 500 时 (m/s)", 1.0, 30.0, _muzzle_v_lo, 0.5)
	_add_slider_row(parent, "vhi", "duty 1100 时 (m/s)", 1.0, 40.0, _muzzle_v_hi, 0.5)
	_add_note(parent, "17mm 弹丸，直径 %.0fmm、质量 %.1fg。初速按摩擦轮占空比线性插值，"
		% [BULLET_RADIUS * 2000.0, BULLET_MASS * 1000.0]
		+"占空比不到 500 时只会「掉弹」。这两个端点是估值，不是实测标定。")
	_add_section(parent, "底盘速度标定")
	_add_slider_row(parent, "spdscale", "10000 duty → m/s", 0.2, 6.0, _speed_scale, 0.1)
	_add_slider_row(parent, "turnrate", "10000 duty → °/s", 30.0, 900.0, _turn_rate, 10.0)
	_add_note(parent, "这两个系数只影响仿真观感，不进代码生成，默认值是估值而非实测。"
		+"\n车身 %.0f×%.0f cm，轮径 %.0f cm。"
			% [CHASSIS_LEN * 100.0, CHASSIS_WIDTH * 100.0, WHEEL_RADIUS * 200.0])
	_add_section(parent, "按键映射（手柄 / 键盘）")
	_add_note(parent, _keymap_text())
	_add_section(parent, "与真机的对应关系")
	_add_note(parent, "本模式每 10ms 走一趟，逐字对应生成的 C 主循环："
		+"读输入 → 底盘差速 → 云台积分 → 摩擦轮开关 → 限幅 → 拨弹 → 摩擦轮渐变。"
		+ _feed_mode_note())
	_add_note(parent, "拨弹模式：%s。"
		% str(_cfg.get("feed_mode", "阻塞开环"))
		+ "目视闭环按住扳机持续拨弹、松开即停，出弹间隔 %.0f ms（仅仿真观感，非实测）；"
			% FEED_INTERVAL_MS
		+ "阻塞开环按一下拨弹固定时长。真机手感请以实际机构为准。")


## 拨弹模式对应的「与真机对应关系」补充说明
func _feed_mode_note() -> String:
	if _visual_feed:
		return "目视闭环不阻塞主循环，按住期间整车照常响应。"
	return ("单发拨弹期间 C 端在 Ms_Delay 里阻塞主循环 %d ms，仿真里同样会整车停摆，"
		% _trigger_time_ms
		+ "这就是真机连发时手感发顿的原因。")


func _keymap_text() -> String:
	var lines: Array = [
		"左摇杆（底盘）：手柄左摇杆 / 键盘 WASD",
		"右摇杆（云台）：手柄右摇杆 / 键盘 IJKL",
		"A/B/C/D：手柄 A/B/X/Y / 键盘 1/2/3/4",
		"方向键：手柄十字键 / 键盘方向键（当前作用：%s）" % _arrow_key,
		"扳机 %s：手柄 RT / 鼠标左键（拨弹：%s）" % [
			str(_cfg.get("trigger_key", "E")),
			"按住持续拨弹，松开即停" if _visual_feed else "按一下拨弹固定时长"],
		"按下左摇杆（冲刺）：手柄按下左摇杆 / 键盘 Shift%s"
			% ("" if _sprint_enabled else "（配置未勾选冲刺，无效）"),
		"按下右摇杆（云台归中）：手柄按下右摇杆 / 键盘 Z%s"
			% ("" if _zero_enabled else "（配置未勾选归中，无效）"),
	]
	return "\n".join(lines)


# --- 云台标定模式
func _build_calib_params(parent: Node) -> void:
	_add_section(parent, "云台归中角（相对舵机中位的偏移角）")
	if not _yaw_is_servo and not _pitch_is_servo:
		_add_note(parent, "Yaw 与 Pitch 都配成了电机驱动，没有归中角可标。"
			+"电机没有位置反馈，中位只能靠机械限位。")
		return
	var lim: float = float(CodeGenBase.SERVO_MAX_OFFSET_DEG)
	if _yaw_is_servo:
		_add_slider_row(parent, "yawmid", "Yaw 归中角 (°)", -lim, lim,
			float(_gp["yaw_mid_deg"]), 1.0)
	if _pitch_is_servo:
		_add_slider_row(parent, "pitchmid", "Pitch 归中角 (°)", -lim, lim,
			float(_gp["pitch_mid_deg"]), 1.0)
	_add_note(parent, "舵机盘装歪时用：拖滑块把云台摆到「舵机处于中位时它实际的朝向」，"
		+"数值会实时回填到配置界面的归中角输入框。"
		+"\n摆动幅度 ±%d°，限幅边界 Yaw [%d, %d] / Pitch [%d, %d]（占空比），"
			% [int(_gp["swing_deg"]), int(_gp["yaw_lo"]), int(_gp["yaw_hi"]),
				int(_gp["pitch_lo"]), int(_gp["pitch_hi"])]
		+"已同时收敛到舵机物理行程 [%d, %d] 之内。"
			% [CodeGenBase.SERVO_DUTY_MIN, CodeGenBase.SERVO_DUTY_MAX])


# ------------------------------------------------------------------ 状态行
func _update_status() -> void:
	var label: Node = get_node_or_null(P_STATUS)
	if not label is Label:
		return
	var lines: Array = []
	lines.append("摇杆 左(%+5d, %+5d) 右(%+5d, %+5d)   死区 %d" % [
		_roker[0][0], _roker[0][1], _roker[1][0], _roker[1][1], _deadzone])
	var v: float = (- (float(_duty_motor[0]) + float(_duty_motor[1])) * 0.5
		- (float(_duty_motor[2]) + float(_duty_motor[3])) * 0.5) * 0.5 / 10000.0 * _speed_scale
	lines.append("baseSpeed=%d turnSpeed=%d  →  车速 %.2f m/s   航向 %.0f°" % [
		_base_speed, _turn_speed, v, rad_to_deg(_heading)])
	lines.append("底盘 duty L1=%d L2=%d R1=%d R2=%d  拨弹=%d" % [
		_duty_motor[0], _duty_motor[1], _duty_motor[2], _duty_motor[3], _duty_motor[4]])
	lines.append(_gimbal_status_text())
	var boost_state: String = "开" if _status_booster == 1 else "关"
	lines.append("摩擦轮 %s  duty=%d（开机目标 %d）  出膛 %.1f m/s" % [
		boost_state, _duty_booster, _friction_max_duty, _muzzle_speed()])
	var shot: String = "尚未开火"
	if not _last_shot.is_empty():
		shot = "最近一发 出膛 %.1f m/s" % float(_last_shot.get("speed", 0.0))
		if float(_last_shot.get("flight", 0.0)) > 0.0:
			shot += "  射程 %.2f m  飞行 %.2f s  最高 %.2f m" % [
				float(_last_shot.get("range", 0.0)),
				float(_last_shot.get("flight", 0.0)),
				float(_last_shot.get("peak", 0.0))]
	lines.append("在场弹丸 %d 发   %s" % [_bullets.size(), shot])
	if _block_ms > 0.0:
		lines.append("⚠ 单发拨弹中：主循环被 Ms_Delay 阻塞，剩余 %.0f ms（真机同样停摆）"
			% _block_ms)
	elif _visual_feed and _trigger_key == 1:
		lines.append("目视拨弹中：按住扳机持续拨弹，出弹间隔 %.0f ms，松开即停"
			% FEED_INTERVAL_MS)
	label.text = "\n".join(lines)


func _gimbal_status_text() -> String:
	var parts: Array = []
	if _yaw_is_servo:
		parts.append("Yaw duty=%d (%+.1f°)%s" % [
			_duty_servo[0], _yaw_deg, " ✗限幅" if _servo_clamped[0] else ""])
	else:
		parts.append("Yaw 电机 duty=%d (%+.1f°)" % [_duty_gimbal[0], _yaw_deg])
	if _pitch_is_servo:
		parts.append("Pitch duty=%d (%+.1f°)%s" % [
			_duty_servo[1], _pitch_deg, " ✗限幅" if _servo_clamped[1] else ""])
	else:
		parts.append("Pitch 电机 duty=%d (%+.1f°)" % [_duty_gimbal[1], _pitch_deg])
	return "云台 " + "   ".join(parts)
