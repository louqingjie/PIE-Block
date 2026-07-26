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
const P_TRAIL_TOGGLE: NodePath = "TopPanel/HBox/TrailToggle"
const P_TRAIL_CLEAR: NodePath = "TopPanel/HBox/TrailClear"
const P_RESET_VIEW: NodePath = "TopPanel/HBox/ResetView"
const P_CONFIG_LABEL: NodePath = "TopPanel/HBox/ConfigLabel"

# ------------------------------------------------------------------ 常量
## mm -> Godot 单位。臂长通常 100~300mm，缩到 1~3 单位便于相机取景
const MM_TO_UNIT: float = 0.01
## 连杆圆柱半径（mm）
const LINK_RADIUS_MM: float = 7.0
## 关节球半径（mm）
const JOINT_RADIUS_MM: float = 11.0
## 末端球半径（mm），比关节球大一点便于拖拽
const TIP_RADIUS_MM: float = 14.0
## 轨迹点数上限（环形缓冲）
const TRAIL_MAX_POINTS: int = 300
## 相机俯仰角限制（弧度），避免翻越极点
const CAM_PITCH_LIMIT: float = 1.45
## 模拟手柄的固定步进周期（ms），与生成的 C 主循环 LOOP_PERIOD_MS 一致
const SIM_STEP_MS: float = 10.0
## 摇杆满偏值（与 C 端 valueOfRoker 量程一致）
const ROKER_FULL: float = 2047.0
## 模式枚举
enum Mode { IK = 0, FK = 1, PRESET = 2, JOYSTICK = 3 }

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
## 模拟手柄：右摇杆归一化值 [-1, 1]
var _joy: Vector2 = Vector2.ZERO
## 模拟手柄：按下的按键名集合
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
var _dragging_tip: bool = false

# ------------------------------------------------------------------ 场景对象
var _link_nodes: Array = []      # MeshInstance3D，每段连杆
var _joint_nodes: Array = []     # MeshInstance3D，每个关节球
var _tip_node: MeshInstance3D = null
var _trail_points: Array = []    # Vector3（Godot 坐标）
var _trail_enabled: bool = true

# 材质（在 _ready 里建好复用，避免每帧新建）
var _mat_link: StandardMaterial3D = null
var _mat_link_bad: StandardMaterial3D = null
var _mat_joint: StandardMaterial3D = null
var _mat_joint_clamped: StandardMaterial3D = null
var _mat_tip: StandardMaterial3D = null
var _mat_ghost: StandardMaterial3D = null

# 参数面板控件（按模式重建）
var _sliders: Dictionary = {}    # key -> HSlider
var _spins: Dictionary = {}      # key -> SpinBox
var _syncing: bool = false       # 滑块 <-> 数值框互相赋值时抑制回环


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


func _on_back_pressed() -> void:
	closed.emit()


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
			_joints.append({"zero": "0", "min": "-90", "max": "90"})
	_presets = _cfg.get("presets", [])
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
	for c in root.get_children():
		c.queue_free()
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


# ------------------------------------------------------------------ 静态辅助几何
## 网格地面 + 坐标轴。2 轴构型的"地面"是竖直工作平面，故网格朝向随构型变
func _rebuild_static_geometry() -> void:
	_build_grid()
	_build_axes()


func _build_grid() -> void:
	var grid: MeshInstance3D = get_node_or_null(P_GRID)
	if not grid is MeshInstance3D:
		return
	var reach: float = _l1 + _l2 + _l3
	# 网格总边长就贴着最大可达半径，再大会把臂显得很小；
	# 步长对齐到 10mm 的整数倍，读数更好认
	var half: int = 4
	var step_mm: float = max(10.0, round(reach / float(half) / 10.0) * 10.0)
	var im: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var minor: Color = Color(1, 1, 1, 0.12)
	for i in range(-half, half + 1):
		# 过原点的中线交给坐标轴画（彩色），网格再画一遍会把它盖成白色
		if i == 0:
			continue
		var t: float = float(i) * step_mm
		var lim: float = float(half) * step_mm
		var col: Color = minor
		if _config_type == 0:
			# 2 轴：网格铺在 XY 竖直平面（臂的工作平面）
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(t, -lim, 0.0))
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(t, lim, 0.0))
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(-lim, t, 0.0))
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(lim, t, 0.0))
		else:
			# 3/4 轴：网格铺在 XY 水平面（z=0 底座平面）
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(t, -lim, 0.0))
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(t, lim, 0.0))
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(-lim, t, 0.0))
			im.surface_set_color(col)
			im.surface_add_vertex(_robot_to_godot(lim, t, 0.0))
	im.surface_end()
	grid.mesh = im


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
	lines.append("关节 " + "  ".join(ang_parts))
	# 可达性：与生成的 C 代码里的 ik_reachable 同义
	if _mode == Mode.FK:
		lines.append("正解模式：由关节角推算末端，不做逆解")
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
	if over.size() > 0:
		lines.append(", ".join(over))
	label.text = "\n".join(lines)


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
	_recompute()


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
		Mode.JOYSTICK:
			_build_joystick_params(params)


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
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "在视图里左键拖拽绿色末端球可直接改目标。"
	if _config_type != 0:
		hint.text += "\n按住 Shift 拖拽改底座旋转 θ1。"
	hint.text += "\n黄色半透明球是目标位置，与末端分离即表示被钳位。"
	parent.add_child(hint)


# --- FK 模式参数
func _build_fk_params(parent: Node) -> void:
	_add_section(parent, "关节角度（正解）")
	for i in range(_jc):
		var lo: float = -90.0
		var hi: float = 90.0
		if i < _joints.size():
			var mn: String = str(_joints[i].get("min", "")).strip_edges()
			var mx: String = str(_joints[i].get("max", "")).strip_edges()
			if mn.is_valid_float():
				lo = mn.to_float()
			if mx.is_valid_float():
				hi = mx.to_float()
		if lo >= hi:
			# 限位配置非法时回退到舵机全行程，避免滑块不可用
			lo = -90.0
			hi = 90.0
		_add_slider_row(parent, "j%d" % i, "关节%d θ (°) 限位 [%.0f, %.0f]" % [i + 1, lo, hi],
			lo, hi, _fk_angles[i], 0.5)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "滑块范围取自各关节限位配置，与 C 端 angle_to_duty 的夹紧一致。"
	parent.add_child(hint)


# --- 预设点位模式
func _build_preset_params(parent: Node) -> void:
	_add_section(parent, "预设点位")
	var active: Array = _active_presets()
	if active.is_empty():
		var l: Label = Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "未配置预设点位。回到配置界面填写 Preset 坐标后再进来。"
		parent.add_child(l)
		return
	for entry in active:
		var p: Dictionary = entry["preset"]
		var btn: Button = Button.new()
		var coord: String = "X=%.0f Y=%.0f" % [_p_float(p, "x"), _p_float(p, "y")]
		if _config_type != 0:
			coord += " Z=%.0f" % _p_float(p, "z")
		if _jc >= 4:
			coord += " φ=%.0f°" % _p_float(p, "phi")
		btn.text = "P%d [键 %s]  %s" % [entry["index"] + 1, p.get("key", "?"), coord]
		btn.pressed.connect(_goto_preset.bind(entry["index"]))
		parent.add_child(btn)
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


func _start_play() -> void:
	var active: Array = _active_presets()
	if active.is_empty():
		return
	_play_idx = 0
	_play_t = 0.0
	_play_from = _target.duplicate()


# --- 模拟手柄模式
func _build_joystick_params(parent: Node) -> void:
	_add_section(parent, "右摇杆（末端增量）")
	var joy_scale: float = _cfg_float("joy_scale", 5.0)
	var jl: Label = Label.new()
	jl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jl.text = "映射：%s / %s" % [_cfg.get("joy_x", "右X->末端X"), _cfg.get("joy_y", "右Y->末端Y")]
	if _jc >= 3:
		jl.text += " / %s" % _cfg.get("joy_z", "右X->末端Z")
	jl.text += "\n满偏步长 JOY_SCALE = %.2f mm/周期（%dms）" % [joy_scale, int(SIM_STEP_MS)]
	parent.add_child(jl)
	# 摇杆用两个滑块表达水平/竖直偏移，松手自动回中
	_add_joy_slider(parent, "摇杆水平", 0)
	_add_joy_slider(parent, "摇杆竖直", 1)
	var center: Button = Button.new()
	center.text = "摇杆回中"
	center.pressed.connect(_center_joystick)
	parent.add_child(center)
	_add_section(parent, "按键（长按持续移动）")
	var keymove: Array = _cfg.get("keymove", [])
	var labels: Array = ["末端X", "末端Y", "末端Z", "姿态角φ"]
	var any: bool = false
	for i in range(min(keymove.size(), 4)):
		if _jc < 3 and i == 2:
			continue
		if _jc < 4 and i == 3:
			continue
		for sign_key in ["plus", "minus"]:
			var kname: String = str(keymove[i].get(sign_key, "不使用"))
			if kname == "不使用":
				continue
			any = true
			var btn: Button = Button.new()
			btn.toggle_mode = true
			btn.text = "%s %s  (键 %s)" % [labels[i], "+" if sign_key == "plus" else "-", kname]
			btn.toggled.connect(_on_key_toggled.bind(i, 1.0 if sign_key == "plus" else -1.0))
			parent.add_child(btn)
	if not any:
		var l2: Label = Label.new()
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.text = "未配置按键移动。"
		parent.add_child(l2)
	var hint: Label = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "复现 C 端 CalculateIK：增量累加 -> 逆解 -> 越界且上次可达时回退本周期增量。"
	parent.add_child(hint)


func _add_joy_slider(parent: Node, label_text: String, axis: int) -> void:
	var l: Label = Label.new()
	l.text = label_text
	parent.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = -1.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = 0.0
	parent.add_child(s)
	_sliders["joy%d" % axis] = s
	s.value_changed.connect(func(v: float) -> void:
		if axis == 0:
			_joy.x = v
		else:
			_joy.y = v)


func _center_joystick() -> void:
	_joy = Vector2.ZERO
	for axis in [0, 1]:
		var key: String = "joy%d" % axis
		if _sliders.has(key):
			_sliders[key].set_value_no_signal(0.0)


func _on_key_toggled(pressed: bool, axis: int, sign_val: float) -> void:
	var key: String = "%d:%d" % [axis, int(sign_val)]
	if pressed:
		_keys_down[key] = true
	else:
		_keys_down.erase(key)


# ------------------------------------------------------------------ 每帧推进
func _process(delta: float) -> void:
	if _mode == Mode.JOYSTICK:
		_step_joystick(delta)
	elif _mode == Mode.PRESET and _play_idx >= 0:
		_step_play(delta)


## 复现生成的 C 主循环：固定 10ms 一步，把不定 delta 切成整数步，
## 保证仿真里的移动速度与真机一致
func _step_joystick(delta: float) -> void:
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
	var reach: float = (_l1 + _l2 + _l3) * MM_TO_UNIT
	# 取景距离按可达半径给，保证整条臂占满画面而不溢出
	_cam_dist = max(0.6, reach * 1.7)
	if _config_type == 0:
		# 2 轴：臂在 XY 平面内，正视最直观
		_cam_yaw = 0.0
		_cam_pitch = 0.0
		_cam_pivot = Vector3(0.0, reach * 0.15, 0.0)
	else:
		_cam_yaw = -0.85
		_cam_pitch = 0.42
		_cam_pivot = Vector3(0.0, reach * 0.3, 0.0)
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
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				# 只在 IK 模式允许拖末端；点中末端球附近才进入拖拽
				_dragging_tip = _mode == Mode.IK and _is_near_tip(e.position)
			else:
				_dragging_tip = false
			if _dragging_tip:
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
	elif _dragging_tip:
		_drag_tip(e)
		accept_event()


## 鼠标位置是否落在末端球投影附近（屏幕空间半径判定，够用且无需物理体）
func _is_near_tip(pos: Vector2) -> bool:
	var cam: Node = get_node_or_null(P_CAMERA)
	if not cam is Camera3D or _tip_node == null:
		return false
	if cam.is_position_behind(_tip_node.global_position):
		return false
	var screen: Vector2 = cam.unproject_position(_tip_node.global_position)
	return screen.distance_to(_viewport_pos(pos)) < 26.0


## Control 局部坐标 -> SubViewport 内坐标。SubViewportContainer 是 stretch 的，
## 两者尺寸一致时可直接用，但分辨率不同则需按比例换算
func _viewport_pos(pos: Vector2) -> Vector2:
	var vp: Node = get_node_or_null(P_VIEWPORT)
	if vp is SubViewport and size.x > 0.0 and size.y > 0.0:
		return pos * (Vector2(vp.size) / size)
	return pos


## 拖拽末端：Shift 时改底座旋转（3/4 轴），否则在臂的工作平面内移动
func _drag_tip(e: InputEventMouseMotion) -> void:
	var cam: Node = get_node_or_null(P_CAMERA)
	if not cam is Camera3D:
		return
	if _config_type != 0 and e.shift_pressed:
		# 底座旋转：水平拖拽改 θ1(atan2(y,x))，保持水平半径与高度不变
		var r: float = sqrt(_target[0] * _target[0] + _target[1] * _target[1])
		var ang: float = atan2(_target[1], _target[0]) - e.relative.x * 0.01
		_target[0] = r * cos(ang)
		_target[1] = r * sin(ang)
		_recompute()
		return
	# 在过末端、法向朝相机的平面上投影鼠标射线，得到新的目标点
	var tip_g: Vector3 = _robot_to_godot(_target[0], _target[1], _target[2])
	var normal: Vector3 = _drag_plane_normal(cam)
	var plane: Plane = Plane(normal, tip_g.dot(normal))
	var vp_pos: Vector2 = _viewport_pos(e.position)
	var origin: Vector3 = cam.project_ray_origin(vp_pos)
	var dir: Vector3 = cam.project_ray_normal(vp_pos)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return
	var p: Vector3 = hit
	_target_from_godot(p)
	_recompute()


## 拖拽平面法向：2 轴构型锁在工作平面（Godot Z），3/4 轴用臂所在的竖直平面法向
func _drag_plane_normal(cam: Camera3D) -> Vector3:
	if _config_type == 0:
		return Vector3(0, 0, 1)
	# 3/4 轴：臂在过底座的竖直平面内，法向 = 该平面的水平法线
	var r: float = sqrt(_target[0] * _target[0] + _target[1] * _target[1])
	if r < 1e-3:
		# 末端在轴心上时无方向可依，退化为面向相机的平面
		return -cam.global_transform.basis.z
	var ang: float = atan2(_target[1], _target[0])
	# 机器人 (x, y) -> Godot (x, -y)，故平面法向取 (-sin, 0, -cos·(-1))
	return Vector3(-sin(ang), 0.0, -cos(ang)).normalized()


## Godot 坐标 -> 写回 _target（逆 _robot_to_godot）
func _target_from_godot(p: Vector3) -> void:
	var v: Vector3 = p / MM_TO_UNIT
	if _config_type == 0:
		_target[0] = v.x
		_target[1] = v.y
	else:
		_target[0] = v.x
		_target[1] = -v.z
		_target[2] = v.y
