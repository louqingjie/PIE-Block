class_name CodeGenEngineerIK
extends CodeGenBase
## 工程机器人逆解算代码生成器。
## 根据配置字典生成工程机械臂逆解算 main.c 代码。
## 支持 2~6 关节任意 Pitch/Roll/Yaw 搭配，统一使用雅可比转置数值逆解。
## 预设点位与摇杆实时目标都由 MCU 上的同一套求解器处理。


# 舵机 50Hz 占空比参数继承自 CodeGenBase（SERVO_DUTY_MIN/MID/MAX）
# 角度约定：以舵机中位为 0°，行程 ±90°（对应物理 0~180°）
# duty/度 线性系数：整个 duty 跨度对应 180°
const SERVO_DUTY_PER_DEG: float = float(SERVO_DUTY_MAX - SERVO_DUTY_MIN) \
	/ float(SERVO_MAX_OFFSET_DEG * 2)
# 关节角可表达边界（度）
const JOINT_ANGLE_MIN: float = -90.0
const JOINT_ANGLE_MAX: float = 90.0
# 逆解可达性判定的最小半径，避免除零（与生成的 C 宏 IK_EPS 同值）
const IK_EPS: float = 0.001
# 关节数上限 = 6。
#
# 注意：瓶颈不是算力。真机实测（STC32G @33.1776MHz）雅可比 IK 单次耗时
# 2 关节 54.7μs / 4 关节 116.7μs / 6 关节 196.8μs，线性拟合约 13μs + 30.6μs×n。
# 每周期做 IK_SUBSTEPS=10 步子迭代，6 关节也仅 ~2ms。
# 主循环 10ms 减去扩展板发送 5ms，留给逆解约 4ms，预算充裕。
#
# 6 这个上限的真实依据：
#   1. 舵机口只有 10 个（扩展板 P60/P62/P64/P66/P74~P77 + 主控板 MP03/MP74），
#      6 关节 + 1 夹爪才装得下
#   2. 手动遥控 6 个自由度已经很难操作
#   3. C251 单函数局部变量段上限 128 字节：FK 中间结果必须声明成
#      static xdata，否则 4 关节就报 "segment too big (act=287, max=128)"
const MAX_JOINTS: int = 6
# 扩展板引脚名（按槽位顺序）
const EXP_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]
# 主循环周期(ms)：ExpansionBoradControl 之后的延时也计入其中
const LOOP_PERIOD_MS: int = 10
# 发送板间指令后必须留给硬件的响应延时(ms)
const EXP_SEND_DELAY_MS: int = 5
const SOLVER_PROTOCOL_VERSION: int = 1
const SOLVER_ALGORITHM_VERSION: String = "jacobi-pose-v2"
const SOLVER_ALGORITHM_WIRE_VERSION: int = 2

## 只影响运动学核心的配置指纹。控制映射、IO 和夹爪变化不需要重烧求解器。
func solver_fingerprint(cfg: Dictionary) -> String:
	var jc: int = clampi(int(cfg.get("joint_count", 2)), 2, MAX_JOINTS)
	var joints: Array = cfg.get("joints", [])
	var canonical: String = SOLVER_ALGORITHM_VERSION + ";jc=" + str(jc)
	for i in range(jc):
		var joint: Dictionary = joints[i] if i < joints.size() else {}
		canonical += ";%s,%.6f,%.6f,%.6f,%.6f" % [
			str(joint.get("axis", "Pitch")),
			_to_float(joint.get("len", "0"), 0.0),
			_to_float(joint.get("zero", "0"), 0.0),
			_to_float(joint.get("min", "-90"), -90.0),
			_to_float(joint.get("max", "90"), 90.0)]
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_SHA256)
	hash_ctx.update(canonical.to_utf8_buffer())
	return hash_ctx.finish().hex_encode().substr(0, 16)

## 生成不初始化任何执行器的 MCU 求解器固件。
## 该入口与正式工程共用 FK/IK 生成函数；差异仅在输入输出外壳。
func generate_simulator(cfg: Dictionary) -> String:
	var normalized: Dictionary = cfg.duplicate(true)
	var jc: int = clampi(int(normalized.get("joint_count", 2)), 2, MAX_JOINTS)
	var joints: Array = normalized.get("joints", [])
	var lens: Array = joint_lengths(joints, jc)
	var mask: Dictionary = {"roll": true, "pitch": true, "yaw": true}
	var fingerprint: String = solver_fingerprint(normalized)
	var code: String = ""
	code += "// Pie-Block MCU IK simulator firmware; NO actuator IO is initialized.\n"
	code += "#include \"main.h\"\n#include \"MATH.H\"\n"
	code += "#define JOINT_COUNT %d\n#define IK_EPS 0.001f\n" % jc
	code += "#define DEG_TO_RAD 0.0174532925f\n#define RAD_TO_DEG 57.29577951f\n"
	code += "#define IK_MAX_STEP_DEG %.1ff\n" % JACOBI_MAX_STEP_DEG
	code += "#define IK_SUBSTEPS %d\n" % IK_SUBSTEPS
	code += "#define IK_STALL_COUNT %d\n" % IK_STALL_COUNT
	code += "#define IK_STALL_RELAX %d\n" % IK_STALL_RELAX
	code += "#define IK_STALL_SNAP %d\n" % IK_STALL_SNAP
	code += "#define ORIENTATION_WEIGHT %.2ff\n" % _orientation_weight(lens)
	code += "#define SOLVER_PROTOCOL_VERSION %d\n" % SOLVER_PROTOCOL_VERSION
	code += "#define SOLVER_ALGORITHM_VERSION %d\n" % SOLVER_ALGORITHM_WIRE_VERSION
	code += "#define FRAME_DELIMITER 0x7e\n#define FRAME_ESCAPE 0x7d\n"
	code += "#define RESP_HELLO 0x81\n#define RESP_STATE 0x82\n#define RESP_ERROR 0xff\n"
	code += "float jointAngle[%d] = {" % jc
	for i in range(jc):
		var home: float = _to_float(joints[i].get("zero", "0"), 0.0) if i < joints.size() else 0.0
		if i > 0: code += ", "
		code += "%.3ff" % home
	code += "};\n"
	code += "float targetX, targetY, targetZ, targetRoll, targetPitch, targetYaw;\n"
	code += "uint8_t Channal = 0; /* nrf24l01.obj link placeholder; NRF is never initialized. */\n"
	code += "uint8_t solverMask = 0, solverPositionDof = 0, solverOrientationDof = 0;\n"
	code += "uint8_t solverStatus = 1, ikDiagnosing = 0, ik_reachable = 1;\n"
	code += "uint8_t ikStallCount = 0;\n"
	code += _build_joint_config_arrays(joints, jc)
	code += _build_kinematics_arrays(joints, jc)
	code += generate_kinematics_core(jc, joints, lens)
	code += _gen_sim_protocol(fingerprint, jc)
	code += "void main(void)\n{\n"
	code += "    Board_Init();\n"
	code += _gen_uart_init_first()
	code += "    ik_diagnose();\n"
	code += "    IkSimSyncTarget();\n"
	code += "    while (1)\n    {\n"
	code += "        if (ikSimFrameReady) IkSimProcessFrame();\n"
	code += "    }\n}\n"
	return code

func _gen_sim_protocol(fingerprint: String, jc: int) -> String:
	var s: String = ""
	s += "static uint8_t xdata ikSimFrame[128];\n"
	s += "static uint8_t xdata ikSimTx[128], ikSimPayload[96];\n"
	s += "volatile uint8_t ikSimFrameReady = 0;\n"
	s += "static uint8_t ikSimLen = 0, ikSimInFrame = 0, ikSimEscaped = 0;\n"
	s += "static const uint8_t solverFingerprint[8] = {"
	for i in range(0, 16, 2):
		if i > 0: s += ", "
		s += "0x%s" % fingerprint.substr(i, 2)
	s += "};\n"
	s += "static uint16_t IkSimCrc(uint8_t *p, uint8_t n) { uint16_t c=0xffff; uint8_t i,b; for(i=0;i<n;i++){c^=(uint16_t)p[i]<<8;for(b=0;b<8;b++)c=(c&0x8000)?(uint16_t)((c<<1)^0x1021):(uint16_t)(c<<1);}return c;}\n"
	s += "static uint8_t IkSimReserved(uint8_t b) { return b==0x7e||b==0x7d||b==0xab||b==0xbc||b==0x40||b==0x50||b==0x49||b==0x45||b==0x41||b==0x23; }\n"
	s += "static void IkSimPut(uint8_t b) { if(IkSimReserved(b)){UART_PutChar(UART_1,0x7d);UART_PutChar(UART_1,b^0x20);}else UART_PutChar(UART_1,b); }\n"
	s += "static void IkSimReply(uint8_t type, uint16_t seq, uint8_t *payload, uint8_t n) { uint8_t i=0,total; uint16_t c;ikSimTx[i++]=SOLVER_PROTOCOL_VERSION;ikSimTx[i++]=type;ikSimTx[i++]=(uint8_t)seq;ikSimTx[i++]=(uint8_t)(seq>>8);ikSimTx[i++]=n;for(;i<5+n;i++)ikSimTx[i]=payload[i-5];c=IkSimCrc(ikSimTx,i);ikSimTx[i++]=(uint8_t)c;ikSimTx[i++]=(uint8_t)(c>>8);total=i;UART_PutChar(UART_1,FRAME_DELIMITER);for(i=0;i<total;i++)IkSimPut(ikSimTx[i]);UART_PutChar(UART_1,FRAME_DELIMITER); }\n"
	s += "static void IkSimPutFloat(uint8_t *p, uint8_t *at, float v) { union { float f; uint32_t i; } u; u.f=v;p[(*at)++]=(uint8_t)(u.i>>24);p[(*at)++]=(uint8_t)(u.i>>16);p[(*at)++]=(uint8_t)(u.i>>8);p[(*at)++]=(uint8_t)u.i; }\n"
	s += "static uint8_t IkSimFinite(float v) { return v==v&&v<3.402823e38f&&v> -3.402823e38f; }\n"
	s += "static void IkSimPutFiniteFloat(uint8_t *p, uint8_t *at, float v) { if(!IkSimFinite(v)){v=0.0f;solverStatus|=32;}IkSimPutFloat(p,at,v); }\n"
	s += "static float IkSimGetFloat(uint8_t *p) { union { float f; uint32_t i; } u;u.i=((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|(uint32_t)p[3];return u.f; }\n"
	s += "void IKSimRxByte(uint8_t b){if(b==FRAME_DELIMITER){if(ikSimFrameReady)return;if(ikSimInFrame&&ikSimLen>0){ikSimFrameReady=1;ikSimInFrame=0;return;}ikSimInFrame=1;ikSimEscaped=0;ikSimLen=0;return;}if(!ikSimInFrame||ikSimFrameReady)return;if(b==FRAME_ESCAPE){ikSimEscaped=1;return;}if(ikSimEscaped){b^=0x20;ikSimEscaped=0;}if(ikSimLen<sizeof(ikSimFrame))ikSimFrame[ikSimLen++]=b;else{ikSimInFrame=0;ikSimLen=0;}}\n"
	s += "static void IkSimSyncTarget(void){float ps;ik_fk();targetX=ikPts[JOINT_COUNT][0];targetY=ikPts[JOINT_COUNT][1];targetZ=ikPts[JOINT_COUNT][2];targetRoll=atan2(ikBasis[2][1],ikBasis[2][2])*RAD_TO_DEG;ps=ikBasis[2][0];if(ps>1.0f)ps=1.0f;if(ps< -1.0f)ps=-1.0f;targetPitch=asin(ps)*RAD_TO_DEG;targetYaw=atan2(ikBasis[1][0],ikBasis[0][0])*RAD_TO_DEG;ikStallCount=0;}\n"
	s += "static void IkSimState(uint8_t type,uint16_t seq){uint8_t n=0,i,t;float r,pit,y,pe,er=0.0f,ep=0.0f,ey=0.0f,e;ik_fk();r=atan2(ikBasis[2][1],ikBasis[2][2])*RAD_TO_DEG;pit=ikBasis[2][0];if(pit>1.0f)pit=1.0f;if(pit< -1.0f)pit=-1.0f;pit=asin(pit)*RAD_TO_DEG;y=atan2(ikBasis[1][0],ikBasis[0][0])*RAD_TO_DEG;pe=sqrt((targetX-ikPts[JOINT_COUNT][0])*(targetX-ikPts[JOINT_COUNT][0])+(targetY-ikPts[JOINT_COUNT][1])*(targetY-ikPts[JOINT_COUNT][1])+(targetZ-ikPts[JOINT_COUNT][2])*(targetZ-ikPts[JOINT_COUNT][2]));ik_orientation_error(targetRoll,targetPitch,targetYaw);ik_build_position_cols();ikRequestedMask=solverMask;ik_build_tasks();for(t=0;t<ikTaskCount;t++){e=(ikOriErr[0]*ikTaskAxes[t][0]+ikOriErr[1]*ikTaskAxes[t][1]+ikOriErr[2]*ikTaskAxes[t][2])*RAD_TO_DEG;if(ikTaskKind[t]==0)ep=e;else if(ikTaskKind[t]==1)ey=e;else er=e;}if(pe<1.0f&&(!(solverMask&1)||fabs(er)<1.0f)&&(!(solverMask&2)||fabs(ep)<1.0f)&&(!(solverMask&4)||fabs(ey)<1.0f))solverStatus|=2;ikSimPayload[n++]=solverStatus;ikSimPayload[n++]=JOINT_COUNT;ikSimPayload[n++]=solverPositionDof;ikSimPayload[n++]=solverOrientationDof;ikSimPayload[n++]=solverMask;for(i=0;i<8;i++)ikSimPayload[n++]=solverFingerprint[i];for(i=0;i<JOINT_COUNT;i++)IkSimPutFiniteFloat(ikSimPayload,&n,jointAngle[i]);for(;i<6;i++)IkSimPutFloat(ikSimPayload,&n,0.0f);IkSimPutFiniteFloat(ikSimPayload,&n,ikPts[JOINT_COUNT][0]);IkSimPutFiniteFloat(ikSimPayload,&n,ikPts[JOINT_COUNT][1]);IkSimPutFiniteFloat(ikSimPayload,&n,ikPts[JOINT_COUNT][2]);IkSimPutFiniteFloat(ikSimPayload,&n,y);IkSimPutFiniteFloat(ikSimPayload,&n,pit);IkSimPutFiniteFloat(ikSimPayload,&n,r);IkSimPutFiniteFloat(ikSimPayload,&n,pe);IkSimPutFiniteFloat(ikSimPayload,&n,er);IkSimPutFiniteFloat(ikSimPayload,&n,ep);IkSimPutFiniteFloat(ikSimPayload,&n,ey);IkSimReply(type,seq,ikSimPayload,n);}\n"
	s += "void IkSimProcessFrame(void){uint8_t *p=ikSimFrame,n=ikSimLen,cmd,i,k,valid,sub,stall,clampAcc,nanAcc;float v[6];uint16_t seq,got,want;if(n<7){ikSimFrameReady=0;return;}got=(uint16_t)p[n-2]|((uint16_t)p[n-1]<<8);want=IkSimCrc(p,(uint8_t)(n-2u));if(got!=want||p[0]!=SOLVER_PROTOCOL_VERSION||p[4]+7u!=n){solverStatus=32;ikSimFrameReady=0;return;}cmd=p[1];seq=(uint16_t)p[2]|((uint16_t)p[3]<<8);if(cmd==1&&p[4]==0){k=0;ikSimPayload[k++]=SOLVER_PROTOCOL_VERSION;ikSimPayload[k++]=SOLVER_ALGORITHM_VERSION;ikSimPayload[k++]=1;ikSimPayload[k++]=JOINT_COUNT;ikSimPayload[k++]=solverMask;ikSimPayload[k++]=solverPositionDof;ikSimPayload[k++]=solverOrientationDof;ikSimPayload[k++]=0;for(i=0;i<8;i++)ikSimPayload[k++]=solverFingerprint[i];IkSimReply(RESP_HELLO,seq,ikSimPayload,k);}else if(cmd==2&&p[4]==24){valid=1;for(i=0;i<6;i++){v[i]=IkSimGetFloat(&p[5+i*4]);if(!IkSimFinite(v[i]))valid=0;}if(!valid){solverStatus=32;IkSimReply(RESP_ERROR,seq,ikSimPayload,0);}else{targetX=v[0];targetY=v[1];targetZ=v[2];targetYaw=v[3];targetPitch=v[4];targetRoll=v[5];solverStatus=1;stall=0;clampAcc=0;nanAcc=0;for(sub=0;sub<IK_SUBSTEPS;sub++){ik_solve(targetX,targetY,targetZ,targetRoll,targetPitch,targetYaw);if(ikStepClamped)clampAcc=1;if(ikNumericProtected)nanAcc=1;if(ik_reachable)stall=0;else{stall++;if(stall>=IK_STALL_COUNT)break;}}if(!ik_reachable)solverStatus|=8;if(clampAcc)solverStatus|=4;if(nanAcc)solverStatus|=32;if(ikTaskCount<solverOrientationDof)solverStatus|=16;IkSimState(RESP_STATE,seq);}}else if(cmd==3&&p[4]==25&&p[5]==JOINT_COUNT){valid=1;for(i=0;i<JOINT_COUNT;i++){v[i]=IkSimGetFloat(&p[6+i*4]);if(!IkSimFinite(v[i]))valid=0;}if(!valid){solverStatus=32;IkSimReply(RESP_ERROR,seq,ikSimPayload,0);}else{solverStatus=1;for(i=0;i<JOINT_COUNT;i++){jointAngle[i]=v[i];if(jointAngle[i]<jointMin[i]){jointAngle[i]=jointMin[i];solverStatus|=4;}if(jointAngle[i]>jointMax[i]){jointAngle[i]=jointMax[i];solverStatus|=4;}}IkSimSyncTarget();IkSimState(RESP_STATE,seq);}}else if(cmd==4&&p[4]==0){solverStatus=1;for(i=0;i<JOINT_COUNT;i++)jointAngle[i]=jointHome[i];IkSimSyncTarget();IkSimState(RESP_STATE,seq);}else if(cmd==5&&p[4]==0){solverStatus=1;IkSimState(RESP_STATE,seq);}else{solverStatus=32;IkSimReply(RESP_ERROR,seq,ikSimPayload,0);}ikSimFrameReady=0;ikSimLen=0;}\n"
	return s.replace(";", ";\n")


# ------------------------------------------------------------------ 代码生成
## 基于配置字典生成完整的 main.c 代码字符串
func generate(cfg: Dictionary) -> String:
	# 工程 UI 的两个页面共同传入 {engineer, ik}；保留直接传 IK 配置的测试兼容性。
	var dual_mode: bool = cfg.has("ik")
	var engineer_cfg: Dictionary = cfg.get("engineer", {}) if dual_mode else {}
	if dual_mode:
		cfg = cfg.get("ik", {})
	# 关节数必须钳到 [2, MAX_JOINTS]：不钳的话 jc 超过 joints 长度会让
	# 数组生成函数越界，产出缺失声明的 C 代码（jointHome 未定义等，编译报 C67）。
	# 与其他入口（solver_fingerprint / generate_simulator）保持一致。
	var jc: int = clampi(int(cfg.get("joint_count", 2)), 2, MAX_JOINTS)
	var joints: Array = cfg.get("joints", [])
	var presets: Array = cfg.get("presets", [])
	var gripper: Dictionary = _gripper_config(cfg.get("gripper", {}))
	var gripper_enabled: bool = bool(gripper["enabled"])
	var joy_scale: float = _to_float(cfg.get("joy_scale", "5"), 5.0)
	var keymove_speed: float = _to_float(cfg.get("keymove_speed", "2"), 2.0)
	var orientation_key_speed: float = _to_float(
		cfg.get("orientation_key_speed", "1"), 1.0)
	# 先 is bool 判类型：畸形输入（字符串/数字）不崩溃，按 false 处理
	var _rh: Variant = cfg.get("rocker2_home_enabled", false)
	var rocker2_home_enabled: bool = _rh is bool and _rh == true
	# 启用的预设点位数量（0 时不生成预设相关数组与查询循环）
	var preset_count: int = _active_presets(presets).size()
	# 逐关节转轴与连杆长度：雅可比逆解算的全部输入
	var kin_lens: Array = joint_lengths(joints, jc)
	# 每个末端姿态维度是否可独立控制由构形诊断决定，不由关节数猜测。
	# 不可控维度的目标变量、形参和按键映射都不生成。
	# MCU 上电诊断是姿态可控性的唯一权威。生产固件始终保留完整 RPY
	# 目标，运行时再由 solverMask 忽略不可控维度。
	var orientation_mask: Dictionary = {"roll": true, "pitch": true, "yaw": true}
	var has_orientation: bool = bool(orientation_mask.get("roll", false)) \
		or bool(orientation_mask.get("pitch", false)) or bool(orientation_mask.get("yaw", false))
	var tvars: Array = _target_vars_for(orientation_mask)
	var switch_key: String = str(cfg.get("mode_switch_key", "E"))
	var switch_offset: String = _key_name_to_offset(switch_key)
	var channel: String = _int_or_default(engineer_cfg.get("channel", "36"), 36, 0, 125)
	var deadzone: String = _int_or_default(engineer_cfg.get("deadzone", "10"), 10, 0, 2047)

	# 舵机蜂鸣反馈固定按关节、夹爪、正解辅助舵机的稳定顺序检查。
	# 辅助舵机按扩展板物理槽位 P60~P77，再按主控板 MP03、MP74 排列。
	var servo_buzzer_exprs: Array = []
	for i in range(jc):
		servo_buzzer_exprs.append("dutyOfServo[%d]" % i)
	if gripper_enabled:
		servo_buzzer_exprs.append("dutyOfGripper")
	if dual_mode:
		var gripper_pin_for_buzzer: String = str(gripper.get("io", "")) if gripper_enabled else ""
		var aux_buzzer_slots: Array = _aux_servo_slots(
			engineer_cfg, joints, jc, gripper_pin_for_buzzer)
		for slot in range(EXP_PINS.size()):
			if slot in aux_buzzer_slots:
				servo_buzzer_exprs.append("(uint16_t)dutyOfAuxServo[%d]" % slot)
		var aux_buzzer_main: Array = _aux_main_servo_list(
			engineer_cfg, joints, jc, gripper_pin_for_buzzer)
		for si in [0, 1]:
			for entry in aux_buzzer_main:
				if int(entry["idx"]) == si:
					servo_buzzer_exprs.append("(uint16_t)dutyOfAuxMainServo[%d]" % si)
					break

	var code: String = ""
	code += "// 工程机器人正解/逆解双模式代码（由 Pie-Block 配置生成器自动生成）\n" if dual_mode \
		else "// 工程机器人逆解算代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "#include \"MATH.H\"\n"
	code += "void IKSimRxByte(uint8_t dat) { if (dat == 0u) return; }\n"
	code += "// ========================= 参数区 =========================\n"
	code += "// 关节数：%d。各关节的转轴与连杆长度见下方 jointAxis / jointLen 两张表。\n" % jc
	code += "// 逆解算是通用的雅可比法，不假定任何特定构型。\n"
	code += "#define JOINT_COUNT %d\n" % jc
	code += "// 逆解算除零保护阈值\n"
	code += "#define IK_EPS  0.001f\n"
	code += "// 弧度与度的换算\n"
	code += "#define DEG_TO_RAD  0.0174532925f\n"
	code += "#define RAD_TO_DEG  57.29577951f\n"
	code += "// 逆解单步最大转动量(度)：防大误差时末端猛冲，也避免线性近似失效\n"
	code += "#define IK_MAX_STEP_DEG  %.1ff\n" % JACOBI_MAX_STEP_DEG
	code += "// 每周期子迭代次数：单步只走 4°，多步连走加速收敛\n"
	code += "#define IK_SUBSTEPS  %d\n" % IK_SUBSTEPS
	code += "// 子迭代连续不靠近目标的退出阈值\n"
	code += "#define IK_STALL_COUNT  %d\n" % IK_STALL_COUNT
	code += "// 跨帧停滞阈值：达此周期数后放开姿态门控\n"
	code += "#define IK_STALL_RELAX  %d\n" % IK_STALL_RELAX
	code += "// 跨帧停滞阈值：达此周期数后把目标吸到实际末端\n"
	code += "#define IK_STALL_SNAP  %d\n" % IK_STALL_SNAP
	if has_orientation:
		code += "// 姿态误差权重(mm/rad)，取连杆总长：\n"
		code += "// 让 1 弧度的俯仰角误差与一个臂长的位置误差等重，两者才能相加\n"
		code += "#define ORIENTATION_WEIGHT  %.2ff\n" % _orientation_weight(kin_lens)
	code += "// 舵机占空比参数（50Hz）\n"
	code += "// 关节角以舵机中位为 0°，行程 ±90°（对应物理 0~180°）\n"
	code += "#define SERVO_MID_DUTY  %d   // 0°\n" % SERVO_DUTY_MID
	code += "#define SERVO_MIN_DUTY  %d   // -%d°\n" % [SERVO_DUTY_MIN, SERVO_MAX_OFFSET_DEG]
	code += "#define SERVO_MAX_DUTY  %d  // +%d°\n" % [SERVO_DUTY_MAX, SERVO_MAX_OFFSET_DEG]
	code += "#define SERVO_DUTY_PER_DEG  %.4ff\n" % SERVO_DUTY_PER_DEG
	if gripper_enabled:
		code += "// 夹爪是独立末端舵机，不计入 JOINT_COUNT 或逆解。\n"
		code += "#define GRIPPER_OPEN_DUTY  %d\n" % _gripper_duty(gripper, true)
		code += "#define GRIPPER_CLOSED_DUTY  %d\n" % _gripper_duty(gripper, false)
	code += "// 摇杆推到满偏时末端每周期位移(mm)\n"
	code += "#define JOY_SCALE  %.2ff\n" % joy_scale
	code += "// 按键长按时末端每周期位移(mm)\n"
	code += "#define KEYMOVE_POSITION_SPEED  %.2ff\n" % keymove_speed
	if has_orientation:
		code += "// 按键长按时末端姿态角每周期变化(度)\n"
		code += "#define KEYMOVE_ORIENTATION_SPEED  %.2ff\n" % orientation_key_speed
	# 注：关节限位夹紧在 angle_to_duty 内直接比较，无需 LIMIT_VALUE 宏
	code += _build_protocol_macros()
	# NRF24L01 通信通道（nrf24l01.c 通过 extern 引用，必须在此定义）
	code += "uint8_t Channal = %s;                          // NRF24L01 通信通道（0-125），与遥控器一致\n" % channel
	code += "// 自定义变量\n"
	code += "uint16_t dutyOfServo[%d];       // 各关节舵机占空比\n" % jc
	code += "float    jointAngle[%d];        // 各关节角度(度)\n" % jc
	code += "float    %s;\n" % ", ".join(tvars)
	code += "uint8_t  ik_reachable;          // 逆解算可达性标志(1=本步在靠近目标,0=已贴到极限)\n"
	code += "uint8_t  ikStallCount = 0;      // 跨帧停滞计数：连续不靠近目标的周期数\n"
	code += "uint8_t  solverMask = 0;        // bit0=Roll bit1=Pitch bit2=Yaw，由 MCU 上电诊断\n"
	code += "uint8_t  solverPositionDof = 0, solverOrientationDof = 0;\n"
	code += "uint8_t  ikDiagnosing = 0;\n"
	code += "uint8_t  presetHit;             // 本周期是否命中预设点位\n"
	code += "int16_t  valueOfRoker[2][2];    // 左摇杆水平、竖直；右摇杆水平、竖直\n"
	# 工程页多模式按键映射的键位（方向键、ABCD、左右摇杆按键）
	code += "uint8_t  valueOfKey[3][4];      // 方向键、ABCD、左右摇杆按键\n"
	if rocker2_home_enabled:
		code += "uint8_t  armHomeHit = 0;        // 本周期是否执行机械臂回初始角\n"
		code += "uint8_t  armHomeKeyHeld = 0;    // ROCKER2 锁存，长按只触发一次\n"
	code += "uint16_t deadBandOfLeft = %s;\n" % deadzone
	code += "uint16_t deadBandOfRight = %s;\n" % deadzone
	if gripper_enabled:
		code += "uint16_t dutyOfGripper = %s; // 夹爪舵机当前占空比\n" % \
			("GRIPPER_OPEN_DUTY" if bool(gripper["initial_open"]) else "GRIPPER_CLOSED_DUTY")
		code += "uint8_t  gripperOpen = %d;       // 1=张开，0=闭合\n" % \
			(1 if bool(gripper["initial_open"]) else 0)
		code += "uint8_t  gripperKeyHeld = 0;    // 夹爪键锁存，长按只触发一次\n"
	if dual_mode:
		code += "int       dutyOfChassis[4];     // 底盘四个电机控制值\n"
		code += "int       dutyOfAuxMotor[8];     // 正解模式下的其他扩展板电机\n"
		code += "float     dutyOfAuxServo[8];     // 正解模式下的其他扩展板舵机\n"
		code += "float     dutyOfAuxMainServo[2]; // 正解模式下的 MP03/MP74 舵机\n"
		code += "uint8_t   inverseMode = 1;       // 上电默认逆解模式\n"
		code += "uint8_t   modeKeyHeld = 0;       // 切换键锁存，长按只触发一次\n"
	code += "uint8_t  i;\n"
	code += "uint8_t  j;\n"
	code += "static const uint8_t keyOffsets[3][4] = {\n"
	code += "    {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},\n"
	code += "    {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},\n"
	code += "    {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 实际只有2个\n"
	code += "};\n"
	# 关节配置常量数组（初始角/限位/IO 槽位）
	code += _build_joint_config_arrays(joints, jc)
	# 运动学常量表：逆解算完全由转轴与连杆长度两张表驱动
	code += _build_kinematics_arrays(joints, jc)
	# 生产与仿真固件逐字共用的 FK/IK/诊断核心。
	code += generate_kinematics_core(jc, joints, kin_lens)
	# 预设点位表只保存末端位姿，关节目标由 MCU 运行时求解。
	code += _build_preset_table(presets, jc, joints, orientation_mask)
	code += "\n"
	# 函数声明
	code += "void All_Init();\n"
	code += "void ReadControllerInputs();\n"
	if gripper_enabled:
		code += "void UpdateGripper();\n"
	if dual_mode:
		code += "void UpdateControlMode();\n"
		code += "void CalculateForwardControl();\n"
		code += "void CalculateChassisControl();\n"
	code += "void SyncIKTargetFromJoints();\n"
	if rocker2_home_enabled:
		code += "uint8_t ReturnArmHome();\n"
	code += "void CalculateIK(uint8_t hit);\n"
	code += "void ApplyServoControl();\n"
	if preset_count > 0:
		code += "uint8_t CheckPresetKeys();\n"
	code += "uint16_t angle_to_duty(int joint, float angle);\n"
	code += "void mat_vec(float m[3][3], float v[3], float out[3]);\n"
	code += "void axis_rot(float a[3], float ang, float m[3][3]);\n"
	code += "void mat_mul(float x[3][3], float y[3][3], float out[3][3]);\n"
	code += "void ik_fk();\n"
	code += "void ik_diagnose();\n"
	code += "void ik_solve(%s);\n" % _ik_params_for(orientation_mask)
	code += "uint8_t ik_target_too_far(float x, float y, float z);\n"
	if bool(orientation_mask.get("roll", false)) or bool(orientation_mask.get("yaw", false)):
		code += "float normalize_angle_deg(float angle);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	code += CodeGenBase.REMOTE_CONTROL_INIT_CODE
	# 初始化诊断工具（LED + 蜂鸣器）与 UART1 查询发送（修复 UART 死锁）
	code += _gen_led_diag_tools()
	code += CodeGenBase.UART_TX_QUERY_CODE
	code += _gen_servo_buzzer_tools(servo_buzzer_exprs)

	# --- main() ---
	# 增量模式目标由 MCU 在设置初始关节角后通过共享 FK 初始化。
	# 主控板舵机发送耗时可忽略，扩展板每次发送后需 EXP_SEND_DELAY_MS 延时
	var has_exp: bool = _has_exp_slot(joints, jc) \
		or (gripper_enabled and _io_to_exp_slot(str(gripper["io"])) >= 0)
	var chassis_slots: Array = _chassis_slots(engineer_cfg) if dual_mode else []
	var exp_send_count: int = (1 if has_exp or not chassis_slots.is_empty() else 0) \
		+ (1 if not chassis_slots.is_empty() else 0)
	var tail_delay: int = maxi(0, LOOP_PERIOD_MS - EXP_SEND_DELAY_MS * exp_send_count)
	code += "void main()\n{\n"
	code += "    All_Init();\n"
	code += "    // 初始化各关节到初始角度\n"
	code += "    for (i = 0; i < JOINT_COUNT; i++)\n"
	code += "        jointAngle[i] = jointHome[i];\n"
	code += "    ik_diagnose();             // MCU 自行确定同一姿态下可同时控制的姿态维度\n"
	code += "    // MCU FK 是初始末端目标的唯一来源。\n"
	code += "    SyncIKTargetFromJoints();\n"
	code += "    ik_reachable = 1;\n"
	code += "    while (1)\n"
	code += "    {\n"
	code += _gen_nrf_poll()
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n"
	code += "        ReadControllerInputs();\n"
	if gripper_enabled:
		code += "        UpdateGripper();             // 单击切换夹爪开合，长按不重复\n"
	if dual_mode:
		code += "        UpdateControlMode();         // 单击切换正解/逆解，长按不连跳\n"
		code += "        CalculateChassisControl();    // 底盘不受机械臂模式影响\n"
	if rocker2_home_enabled:
		code += "        armHomeHit = ReturnArmHome(); // ROCKER2 单击恢复关节初始角\n"
	if dual_mode:
		code += "        if (inverseMode)\n"
		code += "        {\n"
		code += "            for (i = 0; i < 8; i++)\n"
		code += "                dutyOfAuxMotor[i] = 0; // 逆解模式停掉正解专用电机\n"
		if rocker2_home_enabled:
			code += "            if (!armHomeHit)\n"
			code += "            {\n"
		var inverse_indent: String = "                " if rocker2_home_enabled else "            "
		if preset_count > 0:
			code += inverse_indent + "presetHit = CheckPresetKeys(); // 预设点位按键检测\n"
		else:
			code += inverse_indent + "presetHit = 0;                 // 未配置预设点位\n"
		code += inverse_indent + "CalculateIK(presetHit);        // 摇杆/按键增量 + 逆解算\n"
		if rocker2_home_enabled:
			code += "            }\n"
		code += "        }\n"
		code += "        else"
		code += " if (!armHomeHit)" if rocker2_home_enabled else ""
		code += "\n            CalculateForwardControl(); // 直接调整各关节角\n"
	else:
		if rocker2_home_enabled:
			code += "        if (!armHomeHit)\n        {\n"
		var standalone_indent: String = "            " if rocker2_home_enabled else "        "
		if preset_count > 0:
			code += standalone_indent + "presetHit = CheckPresetKeys(); // 预设点位按键检测\n"
		else:
			code += standalone_indent + "presetHit = 0;                 // 未配置预设点位\n"
		code += standalone_indent + "CalculateIK(presetHit);        // 摇杆/按键增量 + 逆解算\n"
		if rocker2_home_enabled:
			code += "        }\n"
	code += "        ApplyServoControl();           // 应用舵机控制\n"
	code += "        UpdateBuzzerFeedback();\n"
	code += "        Ms_Delay(%d);                   // 与舵机发送延时合计 %dms/周期\n" % [tail_delay, LOOP_PERIOD_MS]
	code += "    }\n"
	code += "}\n\n"

	# --- angle_to_duty ---
	code += _gen_angle_to_duty()
	# --- ReadControllerInputs ---
	code += _gen_read_inputs(rocker2_home_enabled)
	if gripper_enabled:
		code += _gen_gripper_control(gripper)
	code += _gen_sync_ik_target(orientation_mask)
	if dual_mode:
		code += _gen_mode_control(switch_offset)
		code += _gen_forward_control(engineer_cfg, joints, jc)
		code += _gen_chassis_control(engineer_cfg)
	if rocker2_home_enabled:
		code += _gen_return_arm_home()
	# --- CheckPresetKeys ---
	if preset_count > 0:
		code += _gen_check_preset_keys(jc, orientation_mask)
	# --- CalculateIK ---
	code += _gen_target_too_far(jc, kin_lens)
	code += _gen_calculate_ik(cfg, orientation_mask)
	# --- ApplyServoControl ---
	code += _gen_apply_servo_control(joints, jc, has_exp,
		engineer_cfg if dual_mode else {}, gripper)
	# --- All_Init ---
	code += _gen_all_init(joints, jc, engineer_cfg if dual_mode else {}, gripper)
	# --- ExpansionBoradControl ---
	code += _gen_expansion_board_func()
	return code


## 生产固件与仿真求解器固件必须原样拼接这一段，禁止各自维护运动学实现。
func generate_kinematics_core(jc: int, joints: Array, lens: Array = []) -> String:
	var actual_lens: Array = lens if not lens.is_empty() else joint_lengths(joints, jc)
	var full_mask: Dictionary = {"roll": true, "pitch": true, "yaw": true}
	return _gen_ik_workspace(jc) + _gen_kinematics_helpers() + _gen_ik_fk() \
		+ _gen_ik_orientation_error() + _gen_ik_task_builder(full_mask) + _gen_ik_diagnose() \
		+ _gen_ik_solve_pose(jc, full_mask, actual_lens)


# ------------------------------------------------------------------ 协议宏
func _build_protocol_macros() -> String:
	var s: String = ""
	s += "/*帧头帧尾，内部调用，无需关心*/\n"
	s += "#define COMM_HEADER_1 0xAB\n#define COMM_HEADER_2 0xBC\n#define COMM_END_1 0xCD\n#define COMM_END_2 0xDE\n"
	s += "/*命令码*/\n"
	s += "#define Init_Order 0xAA        // 初始化模式\n"
	s += "#define Duty_Change_Order 0xBB // 修改占空比\n"
	s += "#define Freq_Change_Order 0xCC // 修改频率\n"
	s += "#define Dir_Change_Order 0xDD  // 修改方向 1为正 0为负 设置一次即可\n"
	s += "#define Zero_Order 0xEE        // 0命令\n"
	s += "/*内部调用变量，无需关心，请勿定义同名变量*/\n"
	s += "uint16_t control_data[8] = {0};\n"
	s += "uint16_t motor_dir[8] = {0};\n"
	s += "uint8_t control_command = 0x00;\n"
	return s


# ------------------------------------------------------------------ 关节配置数组
func _build_joint_config_arrays(joints: Array, jc: int) -> String:
	# 越界保护：jc 可能超过 joints 长度（配置不完整时），缺失关节按空字典
	# 处理，让 joint_offsets 等有默认值兜底，避免运行时中断导致数组声明缺失。
	var safe_joints: Array = []
	for k in range(jc):
		safe_joints.append(joints[k] if k < joints.size() and joints[k] is Dictionary else {})
	var offsets: Array = joint_offsets(safe_joints, jc)
	var s: String = ""
	s += "// 各关节安装中位朝向(度，运动学角)：舵机处于中位时该关节的实际朝向。\n"
	s += "// 舵机盘装歪时填这里，逆解算不受影响，只在 angle_to_duty 里换算掉。\n"
	s += "const float jointOffset[%d] = {" % jc
	for i in range(jc):
		if i > 0:
			s += ", "
		s += "%.2ff" % offsets[i]
	s += "};\n"
	s += "// 各关节初始角度(度，运动学角)\n"
	s += "const float jointHome[%d] = {" % jc
	for i in range(jc):
		var zero: float = _to_float(safe_joints[i].get("zero", "0"), 0.0)
		if i > 0:
			s += ", "
		s += "%.2ff" % clampf(zero, offsets[i] + JOINT_ANGLE_MIN, offsets[i] + JOINT_ANGLE_MAX)
	s += "};\n"
	s += "// 各关节限位(度，运动学角) [min, max]，可表达范围 = 中位朝向 ±%d°\n" \
		% SERVO_MAX_OFFSET_DEG
	s += "const float jointMin[%d] = {" % jc
	for i in range(jc):
		var mn: float = _to_float(safe_joints[i].get("min", str(JOINT_ANGLE_MIN)), JOINT_ANGLE_MIN)
		if i > 0:
			s += ", "
		s += "%.2ff" % clampf(mn, offsets[i] + JOINT_ANGLE_MIN, offsets[i] + JOINT_ANGLE_MAX)
	s += "};\n"
	s += "const float jointMax[%d] = {" % jc
	for i in range(jc):
		var mx: float = _to_float(safe_joints[i].get("max", str(JOINT_ANGLE_MAX)), JOINT_ANGLE_MAX)
		if i > 0:
			s += ", "
		s += "%.2ff" % clampf(mx, offsets[i] + JOINT_ANGLE_MIN, offsets[i] + JOINT_ANGLE_MAX)
	s += "};\n"
	s += "// 各关节方向(1=正向, 0=反向)，仅在 angle_to_duty 中生效\n"
	s += "const uint8_t jointDir[%d] = {" % jc
	for i in range(jc):
		var d: int = 1 if safe_joints[i].get("dir", "正向") == "正向" else 0
		if i > 0:
			s += ", "
		s += str(d)
	s += "};\n"
	return s


# ------------------------------------------------------------------ 运动学常量表
## 转轴与连杆长度表。逆解算完全由这两张表驱动，
## 关节数与转轴搭配的差异全部落在数据里，代码本身不变。
func _build_kinematics_arrays(joints: Array, jc: int) -> String:
	var axis_names: Array = joint_axes(joints, jc)
	var lens: Array = joint_lengths(joints, jc)
	var s: String = ""
	s += "// 各关节转轴（关节局部坐标系，连杆沿局部 +X 伸出）：\n"
	s += "//   Yaw=(0,0,1) 左右摆 / Pitch=(0,-1,0) 上下俯仰 / Roll=(1,0,0) 绕自身轴自转\n"
	s += "const float jointAxis[%d][3] = {\n" % jc
	for i in range(jc):
		var v: Vector3 = AXIS_VECTORS[axis_names[i]]
		s += "    {%.1ff, %.1ff, %.1ff}" % [v.x, v.y, v.z]
		if i < jc - 1:
			s += ","
		s += "   // 关节%d %s\n" % [i + 1, axis_names[i]]
	s += "};\n"
	s += "// 各关节之后的连杆长度(mm)。最后一个是末端到夹爪的距离。\n"
	s += "const float jointLen[%d] = {" % jc
	for i in range(jc):
		if i > 0:
			s += ", "
		s += "%.2ff" % float(lens[i])
	s += "};\n"
	return s


# ------------------------------------------------------------------ 预设点位
## 过滤出启用的预设点位
func _active_presets(presets: Array) -> Array:
	var active: Array = []
	for p in presets:
		if p.get("enabled", false):
			active.append(p)
	return active


## 预设点位表只存末端位姿。可达性和关节目标由 MCU 运行时统一求解。
func _build_preset_table(presets: Array, jc: int, joints: Array,
		orientation_mask: Dictionary) -> String:
	var active: Array = _active_presets(presets)
	var count: int = active.size()
	var s: String = ""
	s += "// 预设点位数量\n"
	s += "#define PRESET_COUNT %d\n" % count
	if count == 0:
		# C89 不允许零长数组，未配置预设点位时不生成任何相关数组
		s += "// 未配置预设点位，故不生成 presetKey / presetPos 数组\n"
		return s
	s += "// 预设点位：按键 KEY_OFFSET\n"
	s += "const uint8_t presetKey[PRESET_COUNT] = {"
	for i in range(count):
		var key_name: String = active[i].get("key", "A")
		var key_offset: String = _key_name_to_offset(key_name)
		if i > 0:
			s += ", "
		s += key_offset
	s += "};\n"
	# 存末端坐标而非关节角度：与增量模式统一走 ik_solve，避免两套状态冲突
	s += "// 预设点位末端位姿 {x, y, z, roll, pitch, yaw}\n"
	s += "const float presetPose[PRESET_COUNT][6] = {\n"
	for i in range(count):
		var p: Dictionary = active[i]
		var x: float = _to_float(p.get("x", "0"), 0.0)
		var y: float = _to_float(p.get("y", "0"), 0.0)
		var z: float = _to_float(p.get("z", "0"), 0.0)
		var roll: float = _to_float(p.get("roll", "0"), 0.0)
		var pitch: float = _to_float(p.get("pitch", "0"), 0.0)
		var yaw: float = _to_float(p.get("yaw", "0"), 0.0)
		s += "    {%.2ff, %.2ff, %.2ff, %.2ff, %.2ff, %.2ff}" \
			% [x, y, z, roll, pitch, yaw]
		if i < count - 1:
			s += ","
		s += "\n"
	s += "};\n"
	return s


# ------------------------------------------------------------------ 雅可比转置数值逆解
## 单步步长上限（度）。一个 10ms 周期内单关节最多转这么多，
## 防止大误差时末端猛冲，也避免线性近似在大角度下失效。
const JACOBI_MAX_STEP_DEG: float = 4.0
## 每个主循环周期内 ik_solve 的子迭代次数。
## 单次 ik_solve 只走一个雅可比步（限幅 4°/关节），6 关节仅 ~200μs，
## 但 5ms 预算只用了 4%。大目标变化要几十个 10ms 周期才收敛（60步=600ms），
## 手感很慢。多步子迭代在一个周期内连续走 N 步，收敛速度提升 N 倍。
## 10 步 × 6 关节 ≈ 2ms，远在 5ms 预算内。
const IK_SUBSTEPS: int = 10
## 子迭代中连续 N 步误差不下降就提前退出，避免在极限位/奇异点空转。
const IK_STALL_COUNT: int = 3
## 目标可达域的余量系数：只拦「超出臂展 × 该系数」的目标。
## 留余量是为了避免在边界处反复拖拽/回退造成拖影。
const IK_REACH_MARGIN: float = 0.98
## 认为已经收敛的位置误差（mm）。到这个量级就不再动，避免在噪声上抖。
const JACOBI_POS_TOL: float = 0.05
## 判定不可达所需的「误差不下降」连续次数
const JACOBI_STALL_COUNT: int = 3
## 跨帧停滞阈值：连续这么多周期误差不下降后，放开姿态门控，
## 让冗余自由度开始控制 Roll/Yaw（位置够不着时姿态不应冻结）。
const IK_STALL_RELAX: int = 10
## 跨帧停滞阈值：连续这么多周期误差不下降后，把目标吸到当前实际末端，
## 避免操作手把目标推到不可达位置后调不回来。
const IK_STALL_SNAP: int = 100


## 六维位姿雅可比转置单步。姿态行先投影到位置雅可比的零空间，
## 因此姿态调整不会在一阶近似里牺牲可控的 XYZ。
func solve_ik_pose(target_position: Vector3, target_basis: Basis,
		orientation_mask: Dictionary, angles: Array, joints: Array, jc: int) -> Dictionary:
	var cur: Array = []
	for i in range(jc):
		cur.append(float(angles[i]) if i < angles.size() else 0.0)
	var lens: Array = joint_lengths(joints, jc)
	var w: float = _orientation_weight(lens)
	var chain: Dictionary = fk_chain(cur, joints, jc)
	var pts: Array = chain["points"]
	var tip: Vector3 = pts[pts.size() - 1]
	var e: Vector3 = target_position - tip
	var pos_err: float = e.length()
	var current_rpy: Vector3 = tip_rpy_deg(chain)
	var target_rpy: Vector3 = tip_rpy_deg({"tip_basis": target_basis})
	for pair in [["roll", 0], ["pitch", 1], ["yaw", 2]]:
		if not bool(orientation_mask.get(pair[0], false)):
			target_rpy[pair[1]] = current_rpy[pair[1]]
	var effective_target_basis: Basis = basis_from_rpy_deg(target_rpy)
	var orientation_error: Vector3 = orientation_error_vector(
		chain["tip_basis"], effective_target_basis)
	var task: Dictionary = orientation_task_rows(chain, jc, orientation_mask)
	var orientation_errors: Dictionary = {}
	var orientation_max_deg: float = 0.0
	for name in task["order"]:
		var component: float = orientation_error.dot(task["axes"][name])
		orientation_errors[name] = rad_to_deg(component)
		orientation_max_deg = maxf(orientation_max_deg, absf(rad_to_deg(component)))
	# 已经到位就不动，省得在数值噪声上抖
	if pos_err < JACOBI_POS_TOL and orientation_max_deg < 0.01:
		return {"angles": cur, "err": pos_err, "orientation_err": orientation_errors,
			"reachable": true}
	# Jᵀe：位置三行 + 已诊断为可控的姿态行
	var cols: Array = jacobian_columns(chain, jc)
	var jte: Array = []
	for i in range(jc):
		var v: float = (cols[i] as Vector3).dot(e)
		if pos_err < 2.0:
			for name in task["order"]:
				var component: float = orientation_error.dot(task["axes"][name])
				v += float(task["rows"][name][i]) * w * (component * w)
		jte.append(v)
	# α 自适应（最速下降的精确步长）：
	# 沿 Δθ = αJᵀe 走一步后残差是 |e − αJJᵀe|²，对 α 求极小得
	#   α = (e·JJᵀe) / |JJᵀe|² = |Jᵀe|² / |JJᵀe|²
	# 分子是**关节空间**的 |Jᵀe|²，不是任务空间的 |e|²（差好几个数量级，踩过）。
	# 固定 α 不可行：不同臂长/姿态下合适的步长差几个数量级
	# （bench 里那个 0.00002f 只对那一组臂长成立）。
	var jjte: Vector3 = Vector3.ZERO
	var orientation_dot: Dictionary = {}
	for name in task["order"]:
		orientation_dot[name] = 0.0
	for i in range(jc):
		jjte += (cols[i] as Vector3) * float(jte[i])
		if pos_err < 2.0:
			for name in task["order"]:
				orientation_dot[name] += float(task["rows"][name][i]) * w * float(jte[i])
	var denom: float = jjte.length_squared()
	if pos_err < 2.0:
		for name in task["order"]:
			denom += pow(float(orientation_dot[name]), 2.0)
	var alpha: float = 0.0
	if denom > IK_EPS:
		var num: float = 0.0
		for i in range(jc):
			num += float(jte[i]) * float(jte[i])
		alpha = num / denom
	# 防溢出：与 C 端一致，姿态行在奇异构形下残差可能巨大，
	# 让 num/den 溢出为 inf，进而 0*inf=NaN 污染关节角。
	for i in range(jc):
		if not is_finite(float(jte[i])) or absf(float(jte[i])) > 1.0e6:
			jte[i] = 0.0
	# 步长限幅：换算成度之后不超过 JACOBI_MAX_STEP_DEG
	var max_step: float = 0.0
	for i in range(jc):
		max_step = maxf(max_step, absf(rad_to_deg(alpha * float(jte[i]))))
	if max_step > JACOBI_MAX_STEP_DEG:
		alpha *= JACOBI_MAX_STEP_DEG / max_step
	if not is_finite(alpha) or absf(alpha) > 100000.0:
		alpha = 0.0
	var next: Array = []
	for i in range(jc):
		next.append(cur[i] + rad_to_deg(alpha * float(jte[i])))
	# 限位钳位：与 C 端 angle_to_duty 内的夹紧一致
	var clamped: Dictionary = clamp_angles_to_limits(next, joints)
	var out: Array = clamped["angles"]
	# 走完这一步的实际误差，用于判断是否还在靠近目标。
	# 必须把姿态误差一起算进总误差，否则纯姿态步骤会被误判为停滞。
	var chain2: Dictionary = fk_chain(out, joints, jc)
	var pts2: Array = chain2["points"]
	var new_pos_err: float = (target_position - (pts2[pts2.size() - 1] as Vector3)).length()
	var before: float = pos_err * pos_err
	var after: float = new_pos_err * new_pos_err
	if pos_err < 2.0:
		for name in task["order"]:
			before += pow(deg_to_rad(float(orientation_errors[name])) * w, 2.0)
	var error2: Vector3 = orientation_error_vector(chain2["tip_basis"], effective_target_basis)
	var task2: Dictionary = orientation_task_rows(chain2, jc, orientation_mask)
	if pos_err < 2.0:
		for name in task2["order"]:
			after += pow(error2.dot(task2["axes"][name]) * w, 2.0)
	return {"angles": out, "err": new_pos_err, "orientation_err": orientation_errors,
		"reachable": after < before - 1.0e-4}


## 姿态误差的权重（mm/rad）：取臂总长。
##
## 这样 1 rad 的姿态误差与「一个臂长的位置误差」等重，两者可以相加。
## 不做成用户可调：学生没有量纲直觉，多一个参数就是多一个出错点。
func _orientation_weight(lens: Array) -> float:
	var total: float = 0.0
	for v in lens:
		total += absf(float(v))
	return maxf(total, 1.0)


## 仅供运动学回归测试使用的收敛参考；3D 操控和代码生成均不调用它。
## max_iter 上限防止测试在奇异位形附近原地打转。
func solve_ik_pose_converge(target_position: Vector3, target_basis: Basis,
		orientation_mask: Dictionary, angles: Array, joints: Array, jc: int,
		max_iter: int = 200) -> Dictionary:
	var cur: Array = angles.duplicate()
	var last: Dictionary = {}
	var stall: int = 0
	for _n in range(max_iter):
		last = solve_ik_pose(target_position, target_basis, orientation_mask, cur, joints, jc)
		cur = last["angles"]
		var done: bool = float(last["err"]) < JACOBI_POS_TOL
		for value in (last.get("orientation_err", {}) as Dictionary).values():
			done = done and absf(float(value)) < 0.1
		if done:
			break
		# 连续多次不再靠近 => 已经贴到可达域边界或卡在奇异点
		if not bool(last["reachable"]):
			stall += 1
			if stall >= JACOBI_STALL_COUNT:
				break
		else:
			stall = 0
	# 用最终姿态重算一次误差，返回的是「停在哪」而非「上一步之前的误差」
	var chain: Dictionary = fk_chain(cur, joints, jc)
	var pts: Array = chain["points"]
	var final_err: float = (target_position - (pts[pts.size() - 1] as Vector3)).length()
	var final_orientation: Dictionary = {}
	var final_vector: Vector3 = orientation_error_vector(chain["tip_basis"], target_basis)
	var final_task: Dictionary = orientation_task_rows(chain, jc, orientation_mask)
	var reached: bool = final_err < 1.0
	for name in final_task["order"]:
		var error_deg: float = rad_to_deg(final_vector.dot(final_task["axes"][name]))
		final_orientation[name] = error_deg
		reached = reached and absf(error_deg) < 1.0
	return {"angles": cur, "err": final_err, "orientation_err": final_orientation,
		"reachable": reached}


# ------------------------------------------------------------------ 关节限位钳位
## 复现 C 端 angle_to_duty 内的 jointMin/jointMax 夹紧。
## 钳位发生在逆解之后，故钳位后实际末端 ≠ 目标末端。
## 返回 {"angles": Array[float], "clamped": Array[bool]}
func clamp_angles_to_limits(angles: Array, joints: Array) -> Dictionary:
	var out: Array = []
	var clamped: Array = []
	for i in range(angles.size()):
		var a: float = angles[i]
		var lo: float = JOINT_ANGLE_MIN
		var hi: float = JOINT_ANGLE_MAX
		if i < joints.size():
			lo = _to_float(joints[i].get("min", ""), JOINT_ANGLE_MIN)
			hi = _to_float(joints[i].get("max", ""), JOINT_ANGLE_MAX)
		var c: float = clamp(a, lo, hi)
		out.append(c)
		clamped.append(not is_equal_approx(c, a))
	return {"angles": out, "clamped": clamped}


# ------------------------------------------------------------------ 安装中位朝向
## 各关节的安装中位朝向（度，运动学角）：舵机处于中位时该关节的实际朝向。
## 舵机盘装歪时靠它修正，逆解算本身不受影响。
func joint_offsets(joints: Array, jc: int) -> Array:
	var out: Array = []
	for i in range(jc):
		if i < joints.size():
			out.append(_to_float(joints[i].get("offset", "0"), 0.0))
		else:
			out.append(0.0)
	return out


## 运动学角 -> 舵机指令角（复现 C 端 angle_to_duty 里的减法）。
## 返回 {"angles": Array[float], "over_travel": Array[bool]}，
## over_travel 标记该关节超出舵机 ±90° 行程（装歪导致够不到）。
func servo_angles(angles: Array, joints: Array) -> Dictionary:
	var offsets: Array = joint_offsets(joints, angles.size())
	var out: Array = []
	var over: Array = []
	for i in range(angles.size()):
		var s: float = float(angles[i]) - offsets[i]
		out.append(s)
		over.append(s < JOINT_ANGLE_MIN or s > JOINT_ANGLE_MAX)
	return {"angles": out, "over_travel": over}


# ------------------------------------------------------------------ 正运动学（初始姿态末端位置）
## 从关节配置数组里取出初始角度（度）。
## 长度跟随实际关节数，缺失补 0。
func _joint_home_angles(joints: Array) -> Array:
	var n: int = mini(joints.size(), MAX_JOINTS)
	var out: Array = []
	out.resize(n)
	out.fill(0.0)
	for i in range(min(joints.size(), n)):
		out[i] = _to_float(joints[i].get("zero", "0"), 0.0)
	return out
# ============================================================ 通用正运动学
# 支持每个关节独立选择 Pitch / Roll / Yaw 转轴，不再假定「底座 Yaw + 共面 Pitch」。
# 用户是没有机械基础的大一学生，会造出任意构形的臂，写死构形会导致
# 生成的 C 代码按错误假设算角度却编译通过（静默出错）。
#
# 轴向约定（关节局部坐标系，连杆沿局部 +X 伸出）：
#   Yaw   = 绕局部 Z（竖直轴）  —— 左右摆
#   Pitch = 绕局部 -Y          —— 上下俯仰；取负号才能让正角度抬升连杆，
#                                 与历史构型的 zz = L·sin(θ) 一致
#   Roll  = 绕局部 X（连杆自身轴线）—— 自转，不改变末端位置
const AXIS_YAW: String = "Yaw"
const AXIS_PITCH: String = "Pitch"
const AXIS_ROLL: String = "Roll"
## 转轴名 -> 局部单位向量
const AXIS_VECTORS: Dictionary = {
	AXIS_YAW: Vector3(0.0, 0.0, 1.0),
	AXIS_PITCH: Vector3(0.0, -1.0, 0.0),
	AXIS_ROLL: Vector3(1.0, 0.0, 0.0),
}
## 各关节转轴名。空值回落到配置界面的默认值：
##   第 1 个关节 = Yaw（底座左右摆），其余 = Pitch（上下俯仰）
##
func joint_axes(joints: Array, jc: int) -> Array:
	var out: Array = []
	for i in range(jc):
		var name: String = ""
		if i < joints.size():
			name = str(joints[i].get("axis", "")).strip_edges()
		if not AXIS_VECTORS.has(name):
			name = AXIS_YAW if i == 0 else AXIS_PITCH
		out.append(name)
	return out


## 各关节之后的连杆长度（mm）。空值按 0 处理。
func joint_lengths(joints: Array, jc: int) -> Array:
	var out: Array = []
	for i in range(jc):
		var s: String = ""
		if i < joints.size():
			s = str(joints[i].get("len", "")).strip_edges()
		if s.is_valid_float():
			out.append(s.to_float())
		else:
			out.append(0.0)
	return out


## 通用正运动学链。逐关节累乘旋转，返回世界系（机器人坐标，mm）下的：
##   points: 长度 jc+1，各关节位置 + 末端位置
##   axes:   长度 jc，各关节转轴的世界方向（单位向量），雅可比要用
##   tip_basis: 末端姿态（局部 +X 即末端朝向），夹爪渲染要用
## 注意 points 里可能出现重合点（len=0 的关节，如底座 Yaw 与肩部 Pitch 同位）。
func fk_chain(angles: Array, joints: Array, jc: int) -> Dictionary:
	var axis_names: Array = joint_axes(joints, jc)
	var lens: Array = joint_lengths(joints, jc)
	var basis: Basis = Basis.IDENTITY
	var pos: Vector3 = Vector3.ZERO
	var points: Array = []
	var axes: Array = []
	for i in range(jc):
		var local_axis: Vector3 = AXIS_VECTORS[axis_names[i]]
		# 关节 i 的世界转轴：由「该关节之前」的姿态决定。
		# 绕自身轴旋转不改变该轴方向，故用旋转前后的 basis 结果相同。
		var world_axis: Vector3 = (basis * local_axis).normalized()
		axes.append(world_axis)
		# 关节位置记录在施加自身旋转之前的落点
		points.append(pos)
		var ang: float = deg_to_rad(float(angles[i]) if i < angles.size() else 0.0)
		basis = basis * Basis(local_axis, ang)
		# 沿旋转后的局部 +X 伸出该关节之后的连杆
		pos += basis * Vector3(lens[i], 0.0, 0.0)
	points.append(pos)
	return {"points": points, "axes": axes, "tip_basis": basis}


# ------------------------------------------------------------------ 雅可比与完整末端姿态
## 末端朝向（approach）：末段连杆指向，即 tip_basis 的局部 +X。
## 夹爪朝这个方向抓取。
func tip_approach(chain: Dictionary) -> Vector3:
	return ((chain["tip_basis"] as Basis) * Vector3(1.0, 0.0, 0.0)).normalized()


## RPY 约定：R = Rz(yaw) * R(-Y, pitch) * Rx(roll)。
## 机器人坐标 X 向前、Y 向左、Z 向上，所以 Pitch 正值表示抬头。
func basis_from_rpy_deg(rpy: Vector3) -> Basis:
	var roll: float = deg_to_rad(wrapf(rpy.x, -180.0, 180.0))
	var pitch: float = deg_to_rad(clampf(rpy.y, -90.0, 90.0))
	var yaw: float = deg_to_rad(wrapf(rpy.z, -180.0, 180.0))
	return (Basis(Vector3(0.0, 0.0, 1.0), yaw)
		* Basis(Vector3(0.0, -1.0, 0.0), pitch)
		* Basis(Vector3(1.0, 0.0, 0.0), roll)).orthonormalized()


func tip_rpy_deg(chain: Dictionary) -> Vector3:
	var b: Basis = (chain["tip_basis"] as Basis).orthonormalized()
	var pitch: float = asin(clampf(b.x.z, -1.0, 1.0))
	var cp: float = cos(pitch)
	var roll: float = 0.0
	var yaw: float = 0.0
	if absf(cp) > 1.0e-5:
		roll = atan2(b.y.z, b.z.z)
		yaw = atan2(b.x.y, b.x.x)
	else:
		yaw = atan2(-b.y.x, b.y.y)
	return Vector3(wrapf(rad_to_deg(roll), -180.0, 180.0),
		clampf(rad_to_deg(pitch), -90.0, 90.0),
		wrapf(rad_to_deg(yaw), -180.0, 180.0))


## current -> target 的最短世界系旋转向量（方向=旋转轴，长度=弧度）。
func orientation_error_vector(current: Basis, target: Basis) -> Vector3:
	var delta: Basis = (target.orthonormalized()
		* current.orthonormalized().transposed()).orthonormalized()
	var q: Quaternion = delta.get_rotation_quaternion().normalized()
	var angle: float = q.get_angle()
	var axis: Vector3 = q.get_axis()
	if angle > PI:
		angle -= TAU
	if not is_finite(angle) or not is_finite(axis.x) or not is_finite(axis.y) \
			or not is_finite(axis.z) or absf(angle) < 1.0e-8:
		return Vector3.ZERO
	return axis.normalized() * angle


## 位置雅可比的列向量：第 i 列 = a_i × (p_tip - o_i)，单位 mm/rad。
## 描述关节 i 单位角速度引起的末端线速度。
func jacobian_columns(chain: Dictionary, jc: int) -> Array:
	var pts: Array = chain["points"]
	var axes: Array = chain["axes"]
	var tip: Vector3 = pts[pts.size() - 1]
	var cols: Array = []
	for i in range(jc):
		cols.append((axes[i] as Vector3).cross(tip - (pts[i] as Vector3)))
	return cols


## 返回位置优先、可同时控制的姿态任务行。每一行都已剔除位置行空间以及
## 更高优先级姿态行的分量。优先级固定为 Pitch、Yaw、Roll。
func orientation_task_rows(chain: Dictionary, jc: int, mask: Dictionary) -> Dictionary:
	var cols: Array = jacobian_columns(chain, jc)
	var joint_basis: Array = []
	for component in range(3):
		var position_row: Array = []
		for i in range(jc):
			position_row.append(float((cols[i] as Vector3)[component]))
		_add_independent_row(joint_basis, position_row, 1.0e-6)
	var current: Basis = chain["tip_basis"]
	var rpy: Vector3 = tip_rpy_deg(chain)
	var yaw_basis: Basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(rpy.z))
	var world_axes: Dictionary = {
		"pitch": (yaw_basis * Vector3(0.0, -1.0, 0.0)).normalized(),
		"yaw": Vector3(0.0, 0.0, 1.0),
		"roll": current.x.normalized(),
	}
	var desired_names: Array[String] = []
	var desired_basis: Array[Vector3] = []
	for name in ["pitch", "yaw", "roll"]:
		if bool(mask.get(name, false)):
			desired_names.append(name)
			_add_world_direction(desired_basis, world_axes[name])
	# 约束掉目标姿态子空间之外的角速度。否则 Roll 轴在世界 Z 上有投影时，
	# 单纯点乘会把 Roll 误判成 Yaw。
	var complement: Array[Vector3] = []
	for seed in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var value: Vector3 = seed
		for direction in desired_basis:
			value -= direction * value.dot(direction)
		for direction in complement:
			value -= direction * value.dot(direction)
		if value.length() > 1.0e-5:
			complement.append(value.normalized())
	for direction in complement:
		var blocked_row: Array = []
		for axis in chain["axes"]:
			blocked_row.append((axis as Vector3).dot(direction))
		_add_independent_row(joint_basis, blocked_row, 1.0e-6)
	var rows: Dictionary = {}
	var axes_out: Dictionary = {}
	var order: Array[String] = []
	for name in desired_names:
		var raw: Array = []
		for axis in chain["axes"]:
			raw.append((axis as Vector3).dot(world_axes[name]))
		var residual: Array = _row_residual(raw, joint_basis)
		var norm: float = _row_norm(residual)
		if norm <= 1.0e-4:
			continue
		var normalized: Array = []
		for value in residual:
			normalized.append(float(value) / norm)
		joint_basis.append(normalized)
		rows[name] = residual
		axes_out[name] = world_axes[name]
		order.append(name)
	return {"rows": rows, "axes": axes_out, "order": order}


func diagnose_orientation_mask_at_chain(chain: Dictionary, jc: int) -> Dictionary:
	var selected: Dictionary = {"roll": false, "pitch": false, "yaw": false}
	for name in ["pitch", "yaw", "roll"]:
		var candidate: Dictionary = selected.duplicate(true)
		candidate[name] = true
		var task: Dictionary = orientation_task_rows(chain, jc, candidate)
		var expected: int = 0
		for enabled in candidate.values():
			if bool(enabled): expected += 1
		if (task["order"] as Array).size() == expected:
			selected = candidate
	return selected


func _add_world_direction(basis: Array[Vector3], direction: Vector3) -> bool:
	var value: Vector3 = direction
	for existing in basis:
		value -= existing * value.dot(existing)
	if value.length() <= 1.0e-5:
		return false
	basis.append(value.normalized())
	return true


func _row_residual(row: Array, basis_rows: Array) -> Array:
	var out: Array = row.duplicate()
	for basis_row in basis_rows:
		var dot: float = 0.0
		for i in range(min(out.size(), basis_row.size())):
			dot += float(out[i]) * float(basis_row[i])
		for i in range(min(out.size(), basis_row.size())):
			out[i] = float(out[i]) - dot * float(basis_row[i])
	return out


func _row_norm(row: Array) -> float:
	var length_sq: float = 0.0
	for value in row:
		length_sq += float(value) * float(value)
	return sqrt(length_sq)


func _add_independent_row(basis_rows: Array, row: Array, epsilon: float) -> bool:
	var residual: Array = _row_residual(row, basis_rows)
	var norm: float = _row_norm(residual)
	if norm <= epsilon:
		return false
	var normalized: Array = []
	for value in residual:
		normalized.append(float(value) / norm)
	basis_rows.append(normalized)
	return true


func _target_vars_for(mask: Dictionary) -> Array:
	var out: Array = ["targetX", "targetY", "targetZ"]
	for name in ["roll", "pitch", "yaw"]:
		if bool(mask.get(name, false)):
			out.append("target" + name.capitalize())
	return out


## ik_solve 的形参列表（雅可比版），与 _target_vars_for 一一对应
func _ik_params_for(mask: Dictionary) -> String:
	var names: Array = ["float x", "float y", "float z"]
	for name in ["roll", "pitch", "yaw"]:
		if bool(mask.get(name, false)):
			names.append("float " + name)
	return ", ".join(names)


# ------------------------------------------------------------------ 槽位判定
## 是否有任一关节挂在扩展板上（决定发送后是否需要额外延时）
func _has_exp_slot(joints: Array, jc: int) -> bool:
	for i in range(jc):
		if _io_to_exp_slot(joints[i].get("io", "P60")) >= 0:
			return true
	return false


# ------------------------------------------------------------------ angle_to_duty
func _gen_angle_to_duty() -> String:
	var s: String = ""
	s += "/// @brief 关节角度(运动学角，度) -> 舵机占空比\n"
	s += "/// @param joint 关节索引(0..JOINT_COUNT-1)\n"
	s += "/// @param angle 运动学角(度)，即连杆的实际朝向\n"
	s += "/// @return 舵机占空比(SERVO_MIN_DUTY~SERVO_MAX_DUTY)\n"
	s += "/// @note 两个角度空间：运动学角是连杆朝向（逆解算的输出），\n"
	s += "///       舵机指令角 = 运动学角 - jointOffset[joint]，行程 ±%d°：\n" \
		% SERVO_MAX_OFFSET_DEG
	s += "///       -%d°=%d, 0°=%d, +%d°=%d。\n" \
		% [SERVO_MAX_OFFSET_DEG, SERVO_DUTY_MIN,
			SERVO_DUTY_MID, SERVO_MAX_OFFSET_DEG, SERVO_DUTY_MAX]
	s += "///       反向关节沿中位镜像；舵机方向只由占空比决定，\n"
	s += "///       故不再向扩展板发 Dir_Change_Order。\n"
	s += "uint16_t angle_to_duty(int joint, float angle)\n"
	s += "{\n"
	s += "    int duty;\n"
	s += "    float servo;\n"
	s += "    // 限位夹紧（限位也是运动学角）\n"
	s += "    if (angle < jointMin[joint])\n"
	s += "        angle = jointMin[joint];\n"
	s += "    if (angle > jointMax[joint])\n"
	s += "        angle = jointMax[joint];\n"
	s += "    // 运动学角 -> 舵机指令角：扣掉安装中位朝向\n"
	s += "    servo = angle - jointOffset[joint];\n"
	s += "    // 舵机指令角 -> 占空比（0° 即中位 %d），反向关节沿中位镜像\n" % SERVO_DUTY_MID
	s += "    if (jointDir[joint])\n"
	s += "        duty = (int)(SERVO_MID_DUTY + servo * SERVO_DUTY_PER_DEG);\n"
	s += "    else\n"
	s += "        duty = (int)(SERVO_MID_DUTY - servo * SERVO_DUTY_PER_DEG);\n"
	s += "    if (duty < SERVO_MIN_DUTY)\n"
	s += "        duty = SERVO_MIN_DUTY;\n"
	s += "    if (duty > SERVO_MAX_DUTY)\n"
	s += "        duty = SERVO_MAX_DUTY;\n"
	s += "    return (uint16_t)duty;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ 运动学辅助函数
## 3x3 矩阵运算。逆解算每周期都要用，独立成函数避免 ik_solve 局部变量
## 撑爆 C251 的 128 字节函数段上限。
func _gen_kinematics_helpers() -> String:
	var s: String = ""
	s += "/// @brief 矩阵乘向量 out = m * v\n"
	s += "void mat_vec(float m[3][3], float v[3], float out[3])\n"
	s += "{\n"
	s += "    out[0] = m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2];\n"
	s += "    out[1] = m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2];\n"
	s += "    out[2] = m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2];\n"
	s += "}\n\n"
	s += "/// @brief 绕任意单位轴 a 转 ang 弧度的旋转矩阵（罗德里格斯公式）\n"
	s += "/// @note 转轴是 Pitch/Roll/Yaw 只影响传进来的 a，公式本身通用\n"
	s += "void axis_rot(float a[3], float ang, float m[3][3])\n"
	s += "{\n"
	s += "    float c, s, t;\n"
	s += "    c = cos(ang);\n"
	s += "    s = sin(ang);\n"
	s += "    t = 1.0f - c;\n"
	s += "    m[0][0] = t * a[0] * a[0] + c;\n"
	s += "    m[0][1] = t * a[0] * a[1] - s * a[2];\n"
	s += "    m[0][2] = t * a[0] * a[2] + s * a[1];\n"
	s += "    m[1][0] = t * a[0] * a[1] + s * a[2];\n"
	s += "    m[1][1] = t * a[1] * a[1] + c;\n"
	s += "    m[1][2] = t * a[1] * a[2] - s * a[0];\n"
	s += "    m[2][0] = t * a[0] * a[2] - s * a[1];\n"
	s += "    m[2][1] = t * a[1] * a[2] + s * a[0];\n"
	s += "    m[2][2] = t * a[2] * a[2] + c;\n"
	s += "}\n\n"
	s += "/// @brief 矩阵乘矩阵 out = x * y\n"
	s += "void mat_mul(float x[3][3], float y[3][3], float out[3][3])\n"
	s += "{\n"
	s += "    uint8_t r, c;\n"
	s += "    for (r = 0; r < 3; r++)\n"
	s += "        for (c = 0; c < 3; c++)\n"
	s += "            out[r][c] = x[r][0] * y[0][c] + x[r][1] * y[1][c] + x[r][2] * y[2][c];\n"
	s += "}\n\n"
	return s


## 逆解算的中间结果。必须放 xdata：C251 单函数局部变量段上限 128 字节，
## 这些数组放栈上会直接编译失败（ERROR C172: segment too big）。
func _gen_ik_workspace(jc: int) -> String:
	var s: String = ""
	s += "// 逆解算中间结果。放 xdata 而非栈上：C251 单函数局部变量段上限 128 字节，\n"
	s += "// 这几个数组加起来远超上限，声明成局部变量会报 segment too big。\n"
	s += "static float xdata ikBasis[3][3], ikRot[3][3], ikTmp[3][3];\n"
	s += "static float xdata ikPts[%d][3];      // 各关节位置 + 末端位置\n" % (jc + 1)
	s += "static float xdata ikAxes[%d][3];     // 各关节转轴的世界方向\n" % jc
	s += "static float xdata ikCols[%d][3];     // 雅可比各列 a_i x (tip - o_i)\n" % jc
	s += "static float xdata ikJte[%d];         // J^T e\n" % jc
	s += "static float xdata ikLa[3], ikLv[3], ikWv[3], ikEv[3];\n"
	s += "static float xdata ikTargetBasis[3][3], ikOriErr[3];\n"
	s += "static float xdata ikBasisRows[6][6], ikTaskRows[3][6], ikTaskAxes[3][3], ikTaskDot[3], ikTaskErr[3];\n"
	s += "static float xdata ikDesiredAxes[3][3], ikComplementAxes[3][3];\n"
	s += "static uint8_t ikBasisCount, ikPositionRank, ikTaskCount, ikTaskKind[3], ikRequestedMask;\n"
	s += "static uint8_t ikStepClamped, ikNumericProtected;\n"
	return s


func _gen_ik_task_builder(mask: Dictionary) -> String:
	var s: String = ""
	s += "static void ik_build_position_cols(void)\n{\n"
	s += "    uint8_t k;\n"
	s += "    for(k=0;k<JOINT_COUNT;k++){ikLv[0]=ikPts[JOINT_COUNT][0]-ikPts[k][0];ikLv[1]=ikPts[JOINT_COUNT][1]-ikPts[k][1];ikLv[2]=ikPts[JOINT_COUNT][2]-ikPts[k][2];ikCols[k][0]=ikAxes[k][1]*ikLv[2]-ikAxes[k][2]*ikLv[1];ikCols[k][1]=ikAxes[k][2]*ikLv[0]-ikAxes[k][0]*ikLv[2];ikCols[k][2]=ikAxes[k][0]*ikLv[1]-ikAxes[k][1]*ikLv[0];}\n"
	s += "}\n\n"
	s += "/* Build pure orientation tasks inside the position nullspace. */\n"
	s += "static void ik_build_tasks(void)\n{\n"
	s += "    uint8_t i,j,t,c,desiredCount,complementCount;\n"
	s += "    float dot,norm,ax,ay,az,yawNorm,vx,vy,vz;\n"
	s += "    ikBasisCount=0; ikTaskCount=0;\n"
	s += "    for(t=0;t<3;t++){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[t][i]=ikCols[i][t];"
	s += "for(j=0;j<ikBasisCount;j++){dot=0.0f;for(i=0;i<JOINT_COUNT;i++)dot+=ikBasisRows[t][i]*ikBasisRows[j][i];"
	s += "for(i=0;i<JOINT_COUNT;i++)ikBasisRows[t][i]-=dot*ikBasisRows[j][i];}"
	s += "norm=0.0f;for(i=0;i<JOINT_COUNT;i++)norm+=ikBasisRows[t][i]*ikBasisRows[t][i];"
	s += "norm=sqrt(norm);if(norm>0.000001f){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[ikBasisCount][i]=ikBasisRows[t][i]/norm;ikBasisCount++;}}\n"
	s += "    ikPositionRank=ikBasisCount;desiredCount=0;\n"
	s += "    for(t=0;t<3;t++){if(!((t==0&&(ikRequestedMask&2))||(t==1&&(ikRequestedMask&4))||(t==2&&(ikRequestedMask&1))))continue;if(t==0){yawNorm=sqrt(ikBasis[0][0]*ikBasis[0][0]+ikBasis[1][0]*ikBasis[1][0]);if(yawNorm>0.0001f){vx=ikBasis[1][0]/yawNorm;vy=-ikBasis[0][0]/yawNorm;vz=0.0f;}else{vx=0.0f;vy=0.0f;vz=0.0f;}}else if(t==1){vx=0.0f;vy=0.0f;vz=1.0f;}else{vx=ikBasis[0][0];vy=ikBasis[1][0];vz=ikBasis[2][0];}for(j=0;j<desiredCount;j++){dot=vx*ikDesiredAxes[j][0]+vy*ikDesiredAxes[j][1]+vz*ikDesiredAxes[j][2];vx-=dot*ikDesiredAxes[j][0];vy-=dot*ikDesiredAxes[j][1];vz-=dot*ikDesiredAxes[j][2];}norm=sqrt(vx*vx+vy*vy+vz*vz);if(norm>0.00001f){ikDesiredAxes[desiredCount][0]=vx/norm;ikDesiredAxes[desiredCount][1]=vy/norm;ikDesiredAxes[desiredCount][2]=vz/norm;desiredCount++;}}\n"
	s += "    complementCount=0;for(c=0;c<3;c++){vx=(c==0)?1.0f:0.0f;vy=(c==1)?1.0f:0.0f;vz=(c==2)?1.0f:0.0f;for(j=0;j<desiredCount;j++){dot=vx*ikDesiredAxes[j][0]+vy*ikDesiredAxes[j][1]+vz*ikDesiredAxes[j][2];vx-=dot*ikDesiredAxes[j][0];vy-=dot*ikDesiredAxes[j][1];vz-=dot*ikDesiredAxes[j][2];}for(j=0;j<complementCount;j++){dot=vx*ikComplementAxes[j][0]+vy*ikComplementAxes[j][1]+vz*ikComplementAxes[j][2];vx-=dot*ikComplementAxes[j][0];vy-=dot*ikComplementAxes[j][1];vz-=dot*ikComplementAxes[j][2];}norm=sqrt(vx*vx+vy*vy+vz*vz);if(norm>0.00001f){ikComplementAxes[complementCount][0]=vx/norm;ikComplementAxes[complementCount][1]=vy/norm;ikComplementAxes[complementCount][2]=vz/norm;complementCount++;}}\n"
	s += "    for(c=0;c<complementCount;c++){for(i=0;i<JOINT_COUNT;i++)ikTaskRows[0][i]=ikAxes[i][0]*ikComplementAxes[c][0]+ikAxes[i][1]*ikComplementAxes[c][1]+ikAxes[i][2]*ikComplementAxes[c][2];for(j=0;j<ikBasisCount;j++){dot=0.0f;for(i=0;i<JOINT_COUNT;i++)dot+=ikTaskRows[0][i]*ikBasisRows[j][i];for(i=0;i<JOINT_COUNT;i++)ikTaskRows[0][i]-=dot*ikBasisRows[j][i];}norm=0.0f;for(i=0;i<JOINT_COUNT;i++)norm+=ikTaskRows[0][i]*ikTaskRows[0][i];norm=sqrt(norm);if(norm>0.000001f&&ikBasisCount<6){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[ikBasisCount][i]=ikTaskRows[0][i]/norm;ikBasisCount++;}}\n"
	s += "    for(t=0;t<3;t++){if(!((t==0&&(ikRequestedMask&2))||(t==1&&(ikRequestedMask&4))||(t==2&&(ikRequestedMask&1))))continue;if(t==0){yawNorm=sqrt(ikBasis[0][0]*ikBasis[0][0]+ikBasis[1][0]*ikBasis[1][0]);if(yawNorm>0.0001f){ax=ikBasis[1][0]/yawNorm;ay=-ikBasis[0][0]/yawNorm;az=0.0f;}else{ax=0.0f;ay=0.0f;az=0.0f;}}else if(t==1){ax=0.0f;ay=0.0f;az=1.0f;}else{ax=ikBasis[0][0];ay=ikBasis[1][0];az=ikBasis[2][0];}for(i=0;i<JOINT_COUNT;i++)ikTaskRows[ikTaskCount][i]=ikAxes[i][0]*ax+ikAxes[i][1]*ay+ikAxes[i][2]*az;for(j=0;j<ikBasisCount;j++){dot=0.0f;for(i=0;i<JOINT_COUNT;i++)dot+=ikTaskRows[ikTaskCount][i]*ikBasisRows[j][i];for(i=0;i<JOINT_COUNT;i++)ikTaskRows[ikTaskCount][i]-=dot*ikBasisRows[j][i];}norm=0.0f;for(i=0;i<JOINT_COUNT;i++)norm+=ikTaskRows[ikTaskCount][i]*ikTaskRows[ikTaskCount][i];norm=sqrt(norm);if(norm>0.0001f&&ikBasisCount<6){for(i=0;i<JOINT_COUNT;i++)ikBasisRows[ikBasisCount][i]=ikTaskRows[ikTaskCount][i]/norm;ikBasisCount++;ikTaskAxes[ikTaskCount][0]=ax;ikTaskAxes[ikTaskCount][1]=ay;ikTaskAxes[ikTaskCount][2]=az;ikTaskKind[ikTaskCount]=t;ikTaskCount++;}}\n"
	s += "}\n\n"
	return s


## MCU 上电在四组确定性关节姿态上诊断。每次候选 mask 都来自同一姿态，
## 只选择其中任务秩最高的一组，绝不合并不同采样姿态的能力。
func _gen_ik_diagnose() -> String:
	var s: String = ""
	s += "void ik_diagnose(void)\n{\n"
	s += "    uint8_t sample,i,t,candidateBit,required,selected,mask,bestMask,bestPos,bestOri;\n"
	s += "    uint16_t score,bestScore; float offset;\n"
	s += "    bestMask=0;bestPos=0;bestOri=0;bestScore=0;ikDiagnosing=1;\n"
	s += "    for(sample=0;sample<4;sample++){for(i=0;i<JOINT_COUNT;i++){offset=0.0f;if(sample==1)offset=(i&1)?-25.0f:25.0f;else if(sample==2)offset=(i&1)?25.0f:-25.0f;else if(sample==3)offset=((int)(i%3)-1)*35.0f;jointAngle[i]=jointHome[i]+offset;if(jointAngle[i]<jointMin[i])jointAngle[i]=jointMin[i];if(jointAngle[i]>jointMax[i])jointAngle[i]=jointMax[i];}ik_fk();ik_build_position_cols();selected=0;for(t=0;t<3;t++){candidateBit=(t==0)?2:((t==1)?4:1);ikRequestedMask=selected|candidateBit;ik_build_tasks();required=((ikRequestedMask&1)?1:0)+((ikRequestedMask&2)?1:0)+((ikRequestedMask&4)?1:0);if(ikTaskCount==required)selected|=candidateBit;}mask=selected;ikRequestedMask=mask;ik_build_tasks();score=(uint16_t)ikPositionRank*64u+(uint16_t)ikTaskCount*8u+((mask&2)?4u:0u)+((mask&4)?2u:0u)+((mask&1)?1u:0u);if(score>bestScore){bestScore=score;bestMask=mask;bestPos=ikPositionRank;bestOri=ikTaskCount;}}\n"
	s += "    solverMask=bestMask;solverPositionDof=bestPos;solverOrientationDof=bestOri;ikRequestedMask=solverMask;ikDiagnosing=0;for(i=0;i<JOINT_COUNT;i++)jointAngle[i]=jointHome[i];ik_fk();\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ik_solve（雅可比）
## 雅可比转置数值逆解。取代 2/3/4 轴各一套的解析公式。
##
## Δθ = α·Jᵀe，J 第 i 列 = a_i × (p_tip − o_i)。
## 转轴类型只改变 a_i 这个单位向量，公式本身不变 —— 这是它能支持
## 任意关节数与任意 Pitch/Roll/Yaw 搭配的根本原因。
##
## 与 GDScript 侧 solve_ik_pose 逐行对应，改动必须同步两边。
func _gen_ik_orientation_error() -> String:
	var s: String = ""
	s += "static void ik_orientation_error(float roll,float pitch,float yaw)\n{\n"
	s += "    float cr,sr,cp,sp,cy,sy,sinAngle,cosAngle,angleScale,currentPitch;\n"
	s += "    if(!(solverMask&1))roll=atan2(ikBasis[2][1],ikBasis[2][2])*RAD_TO_DEG;\n"
	s += "    currentPitch=ikBasis[2][0];if(currentPitch>1.0f)currentPitch=1.0f;if(currentPitch< -1.0f)currentPitch=-1.0f;\n"
	s += "    if(!(solverMask&2))pitch=asin(currentPitch)*RAD_TO_DEG;\n"
	s += "    if(!(solverMask&4))yaw=atan2(ikBasis[1][0],ikBasis[0][0])*RAD_TO_DEG;\n"
	s += "    cr=cos(roll*DEG_TO_RAD);sr=sin(roll*DEG_TO_RAD);cp=cos(pitch*DEG_TO_RAD);sp=sin(pitch*DEG_TO_RAD);cy=cos(yaw*DEG_TO_RAD);sy=sin(yaw*DEG_TO_RAD);\n"
	s += "    ikTargetBasis[0][0]=cy*cp;ikTargetBasis[1][0]=sy*cp;ikTargetBasis[2][0]=sp;\n"
	s += "    ikTargetBasis[0][1]=-sy*cr-cy*sp*sr;ikTargetBasis[1][1]=cy*cr-sy*sp*sr;ikTargetBasis[2][1]=cp*sr;\n"
	s += "    ikTargetBasis[0][2]=sy*sr-cy*sp*cr;ikTargetBasis[1][2]=-cy*sr-sy*sp*cr;ikTargetBasis[2][2]=cp*cr;\n"
	s += "    ikOriErr[0]=0.5f*((ikBasis[1][0]*ikTargetBasis[2][0]-ikBasis[2][0]*ikTargetBasis[1][0])+(ikBasis[1][1]*ikTargetBasis[2][1]-ikBasis[2][1]*ikTargetBasis[1][1])+(ikBasis[1][2]*ikTargetBasis[2][2]-ikBasis[2][2]*ikTargetBasis[1][2]));\n"
	s += "    ikOriErr[1]=0.5f*((ikBasis[2][0]*ikTargetBasis[0][0]-ikBasis[0][0]*ikTargetBasis[2][0])+(ikBasis[2][1]*ikTargetBasis[0][1]-ikBasis[0][1]*ikTargetBasis[2][1])+(ikBasis[2][2]*ikTargetBasis[0][2]-ikBasis[0][2]*ikTargetBasis[2][2]));\n"
	s += "    ikOriErr[2]=0.5f*((ikBasis[0][0]*ikTargetBasis[1][0]-ikBasis[1][0]*ikTargetBasis[0][0])+(ikBasis[0][1]*ikTargetBasis[1][1]-ikBasis[1][1]*ikTargetBasis[0][1])+(ikBasis[0][2]*ikTargetBasis[1][2]-ikBasis[1][2]*ikTargetBasis[0][2]));\n"
	s += "    sinAngle=sqrt(ikOriErr[0]*ikOriErr[0]+ikOriErr[1]*ikOriErr[1]+ikOriErr[2]*ikOriErr[2]);\n"
	s += "    cosAngle=0.5f*(ikTargetBasis[0][0]*ikBasis[0][0]+ikTargetBasis[1][0]*ikBasis[1][0]+ikTargetBasis[2][0]*ikBasis[2][0]+ikTargetBasis[0][1]*ikBasis[0][1]+ikTargetBasis[1][1]*ikBasis[1][1]+ikTargetBasis[2][1]*ikBasis[2][1]+ikTargetBasis[0][2]*ikBasis[0][2]+ikTargetBasis[1][2]*ikBasis[1][2]+ikTargetBasis[2][2]*ikBasis[2][2]-1.0f);\n"
	s += "    if(cosAngle>1.0f)cosAngle=1.0f;if(cosAngle< -1.0f)cosAngle=-1.0f;angleScale=(sinAngle>IK_EPS)?atan2(sinAngle,cosAngle)/sinAngle:1.0f;\n"
	s += "    ikOriErr[0]*=angleScale;ikOriErr[1]*=angleScale;ikOriErr[2]*=angleScale;\n"
	s += "}\n\n"
	return s


func _gen_ik_solve_pose(jc: int, mask: Dictionary, lens: Array) -> String:
	var s: String = ""
	var enabled: Array = []
	for name in ["pitch", "yaw", "roll"]:
		if bool(mask.get(name, false)):
			enabled.append(name)
	s += "/// @brief Position-priority XYZ + Roll/Pitch/Yaw numerical IK.\n"
	s += "void ik_solve(%s)\n" % _ik_params_for(mask)
	s += "{\n"
	s += "    uint8_t k,t,doOrient;\n"
	s += "    float num, den, alpha, maxStep, step, errBefore, errAfter, posErr2;\n"
	s += "    ik_fk();\n"
	s += "    ikEv[0]=x-ikPts[JOINT_COUNT][0]; ikEv[1]=y-ikPts[JOINT_COUNT][1]; ikEv[2]=z-ikPts[JOINT_COUNT][2];\n"
	s += "    posErr2=ikEv[0]*ikEv[0]+ikEv[1]*ikEv[1]+ikEv[2]*ikEv[2];\n"
	if not enabled.is_empty():
		s += "    doOrient=(posErr2<4.0f||ikStallCount>=IK_STALL_RELAX)?1:0;\n"
		s += "    ik_orientation_error(roll,pitch,yaw);\n"
	s += "    ik_build_position_cols();for(k=0;k<JOINT_COUNT;k++){ikJte[k]=ikCols[k][0]*ikEv[0]+ikCols[k][1]*ikEv[1]+ikCols[k][2]*ikEv[2];"
	if not enabled.is_empty():
		s += "}ikRequestedMask=solverMask;ik_build_tasks();for(t=0;t<ikTaskCount;t++)ikTaskErr[t]=(ikOriErr[0]*ikTaskAxes[t][0]+ikOriErr[1]*ikTaskAxes[t][1]+ikOriErr[2]*ikTaskAxes[t][2])*ORIENTATION_WEIGHT;for(k=0;k<JOINT_COUNT;k++){if(doOrient)for(t=0;t<ikTaskCount;t++)ikJte[k]+=ikTaskRows[t][k]*ikTaskErr[t]*ORIENTATION_WEIGHT;"
	s += "}\n"
	s += "    // 防溢出：姿态行在奇异构形下 Gram-Schmidt 残差可能巨大，\n"
	s += "    // 让 num/den 溢出为 inf，进而 0*inf=NaN 污染 jointAngle。\n"
	s += "    for(k=0;k<JOINT_COUNT;k++){if(ikJte[k]!=ikJte[k]||ikJte[k]>1.0e6f||ikJte[k]<-1.0e6f)ikJte[k]=0.0f;}\n"
	s += "    num=0.0f;ikWv[0]=0.0f;ikWv[1]=0.0f;ikWv[2]=0.0f;for(t=0;t<ikTaskCount;t++)ikTaskDot[t]=0.0f;for(k=0;k<JOINT_COUNT;k++){num+=ikJte[k]*ikJte[k];ikWv[0]+=ikCols[k][0]*ikJte[k];ikWv[1]+=ikCols[k][1]*ikJte[k];ikWv[2]+=ikCols[k][2]*ikJte[k];if(doOrient)for(t=0;t<ikTaskCount;t++)ikTaskDot[t]+=ikTaskRows[t][k]*ORIENTATION_WEIGHT*ikJte[k];}den=ikWv[0]*ikWv[0]+ikWv[1]*ikWv[1]+ikWv[2]*ikWv[2];if(doOrient)for(t=0;t<ikTaskCount;t++)den+=ikTaskDot[t]*ikTaskDot[t];alpha=(den>IK_EPS)?num/den:0.0f;ikNumericProtected=0;if(alpha!=alpha||alpha>100000.0f||alpha< -100000.0f){alpha=0.0f;ikNumericProtected=1;}\n"
	s += "    maxStep=0.0f;for(k=0;k<JOINT_COUNT;k++){step=alpha*ikJte[k]*RAD_TO_DEG;if(step<0.0f)step=-step;if(step>maxStep)maxStep=step;}if(maxStep>IK_MAX_STEP_DEG)alpha*=IK_MAX_STEP_DEG/maxStep;errBefore=posErr2;\n"
	s += "    ikStepClamped=0;for(k=0;k<JOINT_COUNT;k++){jointAngle[k]+=alpha*ikJte[k]*RAD_TO_DEG;if(jointAngle[k]!=jointAngle[k]||jointAngle[k]>1.0e6f||jointAngle[k]<-1.0e6f){jointAngle[k]=jointHome[k];ikNumericProtected=1;}if(jointAngle[k]<jointMin[k]){jointAngle[k]=jointMin[k];ikStepClamped=1;}if(jointAngle[k]>jointMax[k]){jointAngle[k]=jointMax[k];ikStepClamped=1;}}\n"
	if not enabled.is_empty():
		s += "    if(doOrient)for(t=0;t<ikTaskCount;t++)errBefore+=ikTaskErr[t]*ikTaskErr[t];\n"
	s += "    ik_fk();errAfter=(x-ikPts[JOINT_COUNT][0])*(x-ikPts[JOINT_COUNT][0])+(y-ikPts[JOINT_COUNT][1])*(y-ikPts[JOINT_COUNT][1])+(z-ikPts[JOINT_COUNT][2])*(z-ikPts[JOINT_COUNT][2]);"
	if not enabled.is_empty():
		s += "if(doOrient){ik_orientation_error(roll,pitch,yaw);ikRequestedMask=solverMask;ik_build_tasks();for(t=0;t<ikTaskCount;t++){step=(ikOriErr[0]*ikTaskAxes[t][0]+ikOriErr[1]*ikTaskAxes[t][1]+ikOriErr[2]*ikTaskAxes[t][2])*ORIENTATION_WEIGHT;errAfter+=step*step;}}"
	s += "ik_reachable=(errAfter<errBefore-0.0001f)?1:0;\n"
	s += "    if(ik_reachable)ikStallCount=0;else if(ikStallCount<255)ikStallCount++;\n"
	s += "}\n\n"
	return s


## 正运动学链。逐关节累乘旋转，同时记下雅可比要用的世界转轴。
##
## ik_solve 走一步前后都要算一次（后一次用于判断误差是否下降），
## 故抽成单独函数；同时也避开了 C251 的函数段大小限制。
func _gen_ik_fk() -> String:
	var s: String = ""
	s += "/// @brief 按当前 jointAngle[] 算正运动学链\n"
	s += "/// @note 结果写入：ikPts[]=各关节位置+末端，ikAxes[]=各关节世界转轴，\n"
	s += "///       ikBasis=末端姿态（第一列即末端朝向）\n"
	s += "void ik_fk()\n"
	s += "{\n"
	s += "    uint8_t k, r, c;\n"
	s += "    float ang;\n"
	s += "    for (r = 0; r < 3; r++)\n"
	s += "        for (c = 0; c < 3; c++)\n"
	s += "            ikBasis[r][c] = (r == c) ? 1.0f : 0.0f;\n"
	s += "    ikPts[0][0] = 0.0f; ikPts[0][1] = 0.0f; ikPts[0][2] = 0.0f;\n"
	s += "    for (k = 0; k < JOINT_COUNT; k++)\n"
	s += "    {\n"
	s += "        ikLa[0] = jointAxis[k][0];\n"
	s += "        ikLa[1] = jointAxis[k][1];\n"
	s += "        ikLa[2] = jointAxis[k][2];\n"
	s += "        // 关节 k 的世界转轴由它之前的姿态决定\n"
	s += "        // （绕自身轴转不改变该轴方向，故用旋转前的 basis）\n"
	s += "        mat_vec(ikBasis, ikLa, ikWv);\n"
	s += "        ikAxes[k][0] = ikWv[0]; ikAxes[k][1] = ikWv[1]; ikAxes[k][2] = ikWv[2];\n"
	s += "        ang = jointAngle[k] * DEG_TO_RAD;\n"
	s += "        axis_rot(ikLa, ang, ikRot);\n"
	s += "        mat_mul(ikBasis, ikRot, ikTmp);\n"
	s += "        for (r = 0; r < 3; r++)\n"
	s += "            for (c = 0; c < 3; c++)\n"
	s += "                ikBasis[r][c] = ikTmp[r][c];\n"
	s += "        // 沿旋转后的局部 +X 伸出该关节之后的连杆\n"
	s += "        ikLv[0] = jointLen[k]; ikLv[1] = 0.0f; ikLv[2] = 0.0f;\n"
	s += "        mat_vec(ikBasis, ikLv, ikWv);\n"
	s += "        ikPts[k + 1][0] = ikPts[k][0] + ikWv[0];\n"
	s += "        ikPts[k + 1][1] = ikPts[k][1] + ikWv[1];\n"
	s += "        ikPts[k + 1][2] = ikPts[k][2] + ikWv[2];\n"
	s += "    }\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ReadControllerInputs
func _gen_read_inputs(read_rocker2: bool = false) -> String:
	var s: String = ""
	s += "/// @brief 读取摇杆并做死区过滤\n"
	s += "void ReadControllerInputs()\n"
	s += "{\n"
	s += "    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);\n"
	s += "    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);\n"
	s += "    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);\n"
	s += "    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);\n"
	s += "    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)\n"
	s += "        valueOfRoker[0][0] = 0;\n"
	s += "    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)\n"
	s += "        valueOfRoker[0][1] = 0;\n"
	s += "    if (abs(valueOfRoker[1][0]) <= deadBandOfRight)\n"
	s += "        valueOfRoker[1][0] = 0;\n"
	s += "    if (abs(valueOfRoker[1][1]) <= deadBandOfRight)\n"
	s += "        valueOfRoker[1][1] = 0;\n"
	# 工程页多模式按键映射的键位矩阵（方向键、ABCD、LC/RC）
	s += "    for (i = 0; i < 3; i++)\n"
	s += "        for (j = 0; j < 4; j++)\n"
	s += "        {\n"
	s += "            if (i == 2 && j >= 2)\n"
	s += "                break;\n"
	s += "            valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);\n"
	s += "        }\n"
	if read_rocker2:
		s += "    valueOfKey[2][1] = RcKeyValueRead(KEY_OFFSET_Rocker21);\n"
	s += "}\n\n"
	return s


func _gen_gripper_control(gripper: Dictionary) -> String:
	var s: String = ""
	s += "/// @brief 夹爪按键上升沿切换开合；独立于正解/逆解模式\n"
	s += "void UpdateGripper()\n"
	s += "{\n"
	s += "    uint8_t pressed;\n"
	s += "    pressed = RcKeyValueRead(%s);\n" % _key_name_to_offset(str(gripper["key"]))
	s += "    if (pressed && !gripperKeyHeld)\n"
	s += "    {\n"
	s += "        gripperOpen = gripperOpen ? 0 : 1;\n"
	s += "        dutyOfGripper = gripperOpen ? GRIPPER_OPEN_DUTY : GRIPPER_CLOSED_DUTY;\n"
	s += "        gripperKeyHeld = 1;\n"
	s += "    }\n"
	s += "    else if (!pressed)\n"
	s += "        gripperKeyHeld = 0;\n"
	s += "}\n\n"
	return s


## 从当前关节姿态刷新完整末端目标，供模式切换与回初始角共用。
func _gen_sync_ik_target(mask: Dictionary) -> String:
	var s: String = ""
	s += "void SyncIKTargetFromJoints()\n"
	s += "{\n"
	if bool(mask.get("pitch", false)):
		s += "    float pitchSin;\n"
	s += "    ik_fk();\n"
	s += "    targetX = ikPts[JOINT_COUNT][0];\n"
	s += "    targetY = ikPts[JOINT_COUNT][1];\n"
	s += "    targetZ = ikPts[JOINT_COUNT][2];\n"
	if bool(mask.get("roll", false)):
		s += "    targetRoll = atan2(ikBasis[2][1], ikBasis[2][2]) * RAD_TO_DEG;\n"
	if bool(mask.get("pitch", false)):
		s += "    pitchSin = ikBasis[2][0];\n"
		s += "    if (pitchSin > 1.0f) pitchSin = 1.0f;\n"
		s += "    if (pitchSin < -1.0f) pitchSin = -1.0f;\n"
		s += "    targetPitch = asin(pitchSin) * RAD_TO_DEG;\n"
	if bool(mask.get("yaw", false)):
		s += "    targetYaw = atan2(ikBasis[1][0], ikBasis[0][0]) * RAD_TO_DEG;\n"
	s += "}\n\n"
	return s


## 模式键按下边沿翻转；回到逆解时用当前关节姿态刷新末端目标，避免追逐旧目标。
func _gen_mode_control(switch_offset: String) -> String:
	var s: String = ""
	s += "void UpdateControlMode()\n"
	s += "{\n"
	s += "    uint8_t pressed;\n"
	s += "    pressed = RcKeyValueRead(%s);\n" % switch_offset
	s += "    if (pressed && !modeKeyHeld)\n"
	s += "    {\n"
	s += "        inverseMode = inverseMode ? 0 : 1;\n"
	s += "        modeKeyHeld = 1;\n"
	s += "        if (inverseMode)\n"
	s += "            SyncIKTargetFromJoints();\n"
	s += "    }\n"
	s += "    else if (!pressed)\n"
	s += "        modeKeyHeld = 0;\n"
	s += "}\n\n"
	return s


func _gen_return_arm_home() -> String:
	var s: String = ""
	s += "/// @brief ROCKER2 上升沿恢复关节初始角，并同步完整逆解目标\n"
	s += "uint8_t ReturnArmHome()\n"
	s += "{\n"
	s += "    uint8_t pressed;\n"
	s += "    pressed = valueOfKey[2][1];\n"
	s += "    if (pressed && !armHomeKeyHeld)\n"
	s += "    {\n"
	s += "        armHomeKeyHeld = 1;\n"
	s += "        for (i = 0; i < JOINT_COUNT; i++)\n"
	s += "        {\n"
	s += "            jointAngle[i] = jointHome[i];\n"
	s += "            if (jointAngle[i] < jointMin[i]) jointAngle[i] = jointMin[i];\n"
	s += "            if (jointAngle[i] > jointMax[i]) jointAngle[i] = jointMax[i];\n"
	s += "        }\n"
	s += "        SyncIKTargetFromJoints();\n"
	s += "        return 1;\n"
	s += "    }\n"
	s += "    if (!pressed)\n"
	s += "        armHomeKeyHeld = 0;\n"
	s += "    return 0;\n"
	s += "}\n\n"
	return s


## 工程页映射到关节 IO 的舵机行，在正解模式下直接更新统一 jointAngle[]。
func _gen_forward_control(engineer_cfg: Dictionary, joints: Array, jc: int) -> String:
	var joint_by_io: Dictionary = {}
	for i in range(jc):
		joint_by_io[str(joints[i].get("io", ""))] = i
	var body: String = ""
	for row in _all_engineer_rows(engineer_cfg):
		var io: String = str(row.get("io", ""))
		var key: String = str(row.get("key", ""))
		var expr: String = _row_key_expr(key)
		if expr == "0":
			continue
		var axis: Dictionary = _row_axis(key)
		var is_joystick: bool = not axis.is_empty()
		var joystick_expr: String = ""
		if is_joystick:
			joystick_expr = "(float)valueOfRoker[%d][%d]" % [axis["row"], axis["col"]]
		var direction: float = 1.0 if str(row.get("dir", "正")) == "正" else -1.0
		var mode: String = str(row.get("mode", "增量"))
		var param: float = _to_float(row.get("param", "0"), 0.0)
		if joint_by_io.has(io) and mode == "增量":
			# 指向 IK 关节的增量行：正解模式下直接推关节角
			var joint: int = joint_by_io[io]
			if is_joystick:
				body += "    jointAngle[%d] += %s * %.2ff / 2047.0f;\n" \
					% [joint, joystick_expr, direction * absf(param)]
			else:
				body += "    if (%s)\n" % expr
				body += "        jointAngle[%d] += %.2ff;\n" % [joint, direction * absf(param)]
		elif joint_by_io.has(io) and mode == "直接" and not is_joystick:
			var joint: int = joint_by_io[io]
			body += "    if (%s)\n" % expr
			body += "        jointAngle[%d] = %.2ff;\n" % [joint, param]
		else:
			var slot: int = _io_to_exp_slot(io)
			var io_type: String = str((engineer_cfg.get("io_init", {}) as Dictionary).get(io, "舵机"))
			var main_idx: int = 0 if io == "MP03" else (1 if io == "MP74" else -1)
			if io_type == "舵机" and (slot >= 0 or main_idx >= 0):
				var servo_var: String = "dutyOfAuxServo[%d]" % slot if slot >= 0 \
					else "dutyOfAuxMainServo[%d]" % main_idx
				if mode == "增量":
					var duty_step: int = _servo_deg_to_duty_delta(absf(param))
					if is_joystick:
						body += "    %s += %s * %.2ff / 2047.0f;\n" \
							% [servo_var, joystick_expr, direction * duty_step]
					else:
						body += "    if (%s)\n" % expr
						body += "        %s += %.2ff;\n" % [servo_var, direction * duty_step]
				elif mode == "直接" and not is_joystick:
					body += "    if (%s)\n" % expr
					body += "        %s = %d.0f;\n" % [servo_var, _servo_angle_to_duty(int(param))]
				continue
			if slot < 0 or io_type != "电机":
				continue
			if mode == "速度":
				body += "    dutyOfAuxMotor[%d] = (int)(%s * %.2ff / 2047.0f);\n" \
					% [slot, joystick_expr, direction * absf(param)]
			elif mode == "增速":
				body += "    dutyOfAuxMotor[%d] += (int)(%s * %.2ff / 2047.0f);\n" \
					% [slot, joystick_expr, direction * absf(param)]
			elif mode == "直接" and not is_joystick:
				body += "    if (%s)\n" % expr
				body += "        dutyOfAuxMotor[%d] = %d;\n" % [slot, int(direction * absf(param))]
				body += "    else\n"
				body += "        dutyOfAuxMotor[%d] = 0;\n" % slot
	if not body.is_empty():
		body += "    for (i = 0; i < JOINT_COUNT; i++)\n"
		body += "    {\n"
		body += "        if (jointAngle[i] < jointMin[i]) jointAngle[i] = jointMin[i];\n"
		body += "        if (jointAngle[i] > jointMax[i]) jointAngle[i] = jointMax[i];\n"
		body += "    }\n"
		body += "    for (i = 0; i < 8; i++)\n"
		body += "    {\n"
		body += "        if (dutyOfAuxServo[i] < SERVO_MIN_DUTY) dutyOfAuxServo[i] = SERVO_MIN_DUTY;\n"
		body += "        if (dutyOfAuxServo[i] > SERVO_MAX_DUTY) dutyOfAuxServo[i] = SERVO_MAX_DUTY;\n"
		body += "    }\n"
		body += "    for (i = 0; i < 2; i++)\n"
		body += "    {\n"
		body += "        if (dutyOfAuxMainServo[i] < SERVO_MIN_DUTY) dutyOfAuxMainServo[i] = SERVO_MIN_DUTY;\n"
		body += "        if (dutyOfAuxMainServo[i] > SERVO_MAX_DUTY) dutyOfAuxMainServo[i] = SERVO_MAX_DUTY;\n"
		body += "    }\n"
	return "void CalculateForwardControl()\n{\n%s}\n\n" % body


## 工程多模式按键映射行展平（逆解固件的正解部分暂不区分模式，全部行生效）。
## 注：模式切换与逆解的正解/逆解切换的合并语义待定，当前按全部行处理。
func _all_engineer_rows(engineer_cfg: Dictionary) -> Array:
	var out: Array = []
	var modes: Array = engineer_cfg.get("modes", []) if engineer_cfg.get("modes", []) is Array else []
	for mi in range(modes.size()):
		var rows: Array = modes[mi].get("rows", []) if modes[mi] is Dictionary else []
		for row in rows:
			out.append(row)
	return out


## 左摇杆底盘控制在正解和逆解模式下都持续运行。
func _gen_chassis_control(cfg: Dictionary) -> String:
	var normal_speed: String = _int_or_default(cfg.get("normal_speed", "4000"), 4000, 0, 10000)
	var sprint_speed: String = _int_or_default(cfg.get("sprint_speed", "8000"), 8000, 0, 10000)
	var sprint_enabled: bool = cfg.get("sprint_enabled", false) is bool \
		and cfg.get("sprint_enabled", false) == true
	var l1_dir: float = 1.0 if str(cfg.get("l1_dir", "正向")) == "正向" else -1.0
	var l2_dir: float = 1.0 if str(cfg.get("l2_dir", "正向")) == "正向" else -1.0
	var r1_dir: float = 1.0 if str(cfg.get("r1_dir", "正向")) == "正向" else -1.0
	var r2_dir: float = 1.0 if str(cfg.get("r2_dir", "正向")) == "正向" else -1.0
	var s: String = ""
	s += "void CalculateChassisControl()\n"
	s += "{\n"
	s += "    int baseSpeed, turnSpeed, speedLimit;\n"
	s += "    speedLimit = %s;\n" % normal_speed
	if sprint_enabled:
		s += "    if (RcKeyValueRead(KEY_OFFSET_Rocker11))\n"
		s += "        speedLimit = %s;\n" % sprint_speed
	s += "    baseSpeed = (int)((float)valueOfRoker[0][1] * speedLimit / 2047.0f);\n"
	s += "    turnSpeed = (int)((float)valueOfRoker[0][0] * speedLimit / 2047.0f);\n"
	s += "    dutyOfChassis[0] = (int)(%.1ff * (-baseSpeed - turnSpeed));\n" % l1_dir
	s += "    dutyOfChassis[1] = (int)(%.1ff * (-baseSpeed - turnSpeed));\n" % l2_dir
	s += "    dutyOfChassis[2] = (int)(%.1ff * (baseSpeed - turnSpeed));\n" % r1_dir
	s += "    dutyOfChassis[3] = (int)(%.1ff * (baseSpeed - turnSpeed));\n" % r2_dir
	s += "    for (i = 0; i < 4; i++)\n"
	s += "    {\n"
	s += "        if (dutyOfChassis[i] > speedLimit) dutyOfChassis[i] = speedLimit;\n"
	s += "        if (dutyOfChassis[i] < -speedLimit) dutyOfChassis[i] = -speedLimit;\n"
	s += "    }\n"
	s += "    for (i = 0; i < 8; i++)\n"
	s += "    {\n"
	s += "        if (dutyOfAuxMotor[i] > 10000) dutyOfAuxMotor[i] = 10000;\n"
	s += "        if (dutyOfAuxMotor[i] < -10000) dutyOfAuxMotor[i] = -10000;\n"
	s += "    }\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ CheckPresetKeys
func _gen_check_preset_keys(jc: int, mask: Dictionary) -> String:
	var s: String = ""
	s += "/// @brief 预设点位按键检测：按下时把末端目标设为该点位坐标\n"
	s += "/// @return 1=命中预设点位（本周期跳过摇杆/按键增量），0=未命中\n"
	s += "uint8_t CheckPresetKeys()\n"
	s += "{\n"
	s += "    for (i = 0; i < PRESET_COUNT; i++)\n"
	s += "    {\n"
	s += "        if (RcKeyValueRead(presetKey[i]))\n"
	s += "        {\n"
	s += "            targetX = presetPose[i][0];\n"
	s += "            targetY = presetPose[i][1];\n"
	s += "            targetZ = presetPose[i][2];\n"
	if bool(mask.get("roll", false)):
		s += "            if (solverMask & 1) targetRoll = presetPose[i][3];\n"
	if bool(mask.get("pitch", false)):
		s += "            if (solverMask & 2) targetPitch = presetPose[i][4];\n"
	if bool(mask.get("yaw", false)):
		s += "            if (solverMask & 4) targetYaw = presetPose[i][5];\n"
	s += "            return 1;\n"
	s += "        }\n"
	s += "    }\n"
	s += "    return 0;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ CalculateIK
func _gen_calculate_ik(cfg: Dictionary, mask: Dictionary) -> String:
	var jc: int = clampi(int(cfg.get("joint_count", 2)), 2, MAX_JOINTS)
	var s: String = ""
	if bool(mask.get("roll", false)) or bool(mask.get("yaw", false)):
		s += "/// @brief 将角度环绕到 [-180, 180)\n"
		s += "float normalize_angle_deg(float angle)\n"
		s += "{\n"
		s += "    while (angle >= 180.0f) angle -= 360.0f;\n"
		s += "    while (angle < -180.0f) angle += 360.0f;\n"
		s += "    return angle;\n"
		s += "}\n\n"
	s += "/// @brief 摇杆/按键输入末端位置增量 -> 逆解算\n"
	s += "/// @param hit 1=本周期已由预设点位设定目标，跳过增量累加\n"
	s += "/// @note 采用增量累积模式：摇杆偏移量和长按按键都对 target 做累加，\n"
	s += "///       松开后末端保持当前位置不动。\n"
	s += "///       逆解是雅可比增量法，每周期走 IK_SUBSTEPS 步加速收敛。\n"
	# 备份变量与 ik_solve 实参都随构型裁剪，避免未使用变量
	var tvars: Array = _target_vars_for(mask)
	var backups: Array = []
	var save_stmts: Array = []
	var restore_stmts: Array = []
	for v in tvars:
		var b: String = "last" + v.substr(6) # targetX -> lastX
		backups.append(b)
		save_stmts.append("%s = %s;" % [b, v])
		restore_stmts.append("%s = %s;" % [v, b])
	var call_args: String = ", ".join(tvars)
	s += "void CalculateIK(uint8_t hit)\n"
	s += "{\n"
	s += "    float %s;\n" % ", ".join(backups)
	s += "    uint8_t sub, stall;\n"
	s += "    // 备份上次目标：目标跑到臂展外时要把这一步的增量撤掉，\n"
	s += "    // 否则长推摇杆会让 target 一直飘远，松手后末端要等很久才追回来\n"
	s += "    %s\n" % " ".join(save_stmts)
	s += "    if (!hit)\n"
	s += "    {\n"
	s += _indent_block(_build_joy_mapping(cfg))
	s += _indent_block(_build_keymove_mapping(cfg, mask))
	s += "    }\n"
	s += "    // 目标是否落在可达范围内：拿末端到底座的距离与连杆总长比。\n"
	s += "    // 注意不能用 ik_reachable 判断——雅可比法下它表示\n"
	s += "    // 「这一步有没有靠近目标」，正常收敛途中也会因步长限幅而为 0。\n"
	s += "    // 完全伸直的上电目标本来就在 98% 软边界外；越界时仍允许朝内移动，\n"
	s += "    // 只撤回让目标半径继续增大的输入。\n"
	var now_d2: String = "targetX * targetX + targetY * targetY + targetZ * targetZ"
	var old_d2: String = "lastX * lastX + lastY * lastY + lastZ * lastZ"
	s += "    if (!hit && ik_target_too_far(%s)\n" % ", ".join(tvars.slice(0, 3))
	s += "            && %s > %s + IK_EPS)\n" % [now_d2, old_d2]
	s += "    {\n"
	s += "        // 撤回继续向外的增量；向内的增量可以逐步进入软边界\n"
	s += "        %s\n" % " ".join(restore_stmts)
	s += "    }\n"
	s += "    // 多步子迭代：一个周期内连续走 IK_SUBSTEPS 步雅可比，\n"
	s += "    // 收敛速度提升 N 倍。连续 IK_STALL_COUNT 步不靠近目标就提前退出。\n"
	s += "    stall = 0;\n"
	s += "    for (sub = 0; sub < IK_SUBSTEPS; sub++)\n"
	s += "    {\n"
	s += "        ik_solve(%s);\n" % call_args
	s += "        if (ik_reachable)\n"
	s += "            stall = 0;\n"
	s += "        else\n"
	s += "        {\n"
	s += "            stall++;\n"
	s += "            if (stall >= IK_STALL_COUNT)\n"
	s += "                break;\n"
	s += "        }\n"
	s += "    }\n"
	s += "    // 持续停滞（目标够不着）后把目标吸到当前实际末端，\n"
	s += "    // 避免操作手把目标推到不可达位置后永远调不回来。\n"
	s += "    if (ikStallCount >= IK_STALL_SNAP)\n"
	s += "    {\n"
	s += "        SyncIKTargetFromJoints();\n"
	s += "        ikStallCount = 0;\n"
	s += "    }\n"
	s += "}\n\n"
	return s


## 目标是否超出臂展。雅可比法本身不需要可达性判断（够不着自然停在最近点），
## 但摇杆是增量累加的：若不拦住，长推摇杆会让 target 无限飘远，
## 松手后末端得花很久才追回来，手感上像是「卡住了」。
func _gen_target_too_far(jc: int, lens: Array) -> String:
	var reach: float = 0.0
	for v in lens:
		reach += absf(float(v))
	var s: String = ""
	s += "/// @brief 目标点是否超出臂展（连杆总长）\n"
	s += "/// @note 只拦「明显够不着」，留 %d%% 余量避免边界处反复抖动\n" \
		% int(round((1.0 - IK_REACH_MARGIN) * 100.0))
	s += "uint8_t ik_target_too_far(float x, float y, float z)\n"
	s += "{\n"
	s += "    float d2;\n"
	s += "    d2 = x * x + y * y + z * z;\n"
	# 比较平方值省一次 sqrt
	var limit: float = reach * IK_REACH_MARGIN
	s += "    // 与 (臂展 * %.2f)^2 比，省一次开方\n" % IK_REACH_MARGIN
	s += "    return (d2 > %.2ff) ? 1 : 0;\n" % (limit * limit)
	s += "}\n\n"
	return s


## 给生成的代码块每行加 4 空格缩进（用于嵌入 if 块内）
func _indent_block(block: String) -> String:
	if block.is_empty():
		return ""
	var out: String = ""
	for line in block.split("\n"):
		if line.is_empty():
			continue
		out += "    " + line + "\n"
	return out


## 摇杆映射代码生成（增量累积模式）
func _build_joy_mapping(cfg: Dictionary) -> String:
	var s: String = ""
	# 每个末端方向都可独立不使用摇杆，留给按键或预设控制。
	var mappings: Array = [
		["targetX", str(cfg.get("joy_x", "右X->末端X"))],
		["targetY", str(cfg.get("joy_y", "右Y->末端Y"))],
		["targetZ", str(cfg.get("joy_z", "右X->末端Z"))],
	]
	for mapping in mappings:
		var mapping_text: String = str(mapping[1])
		if mapping_text == "不使用" or mapping_text.is_empty():
			continue
		if s.is_empty():
			s += "    // 摇杆增量：摇杆值 -2047~2047 归一化后乘 JOY_SCALE 作为每周期位移\n"
		var axis: Array = parse_joy_axis(mapping_text)
		var sign: String = "-" if "反向" in mapping_text.split("->")[0] else ""
		s += "    %s += %s(float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" \
			% [mapping[0], sign, axis[0], axis[1]]
	return s


## 按键控制六维末端目标（长按持续移动）
## keymove 索引：0=X, 1=Y, 2=Z, 3=Roll, 4=Pitch, 5=Yaw
func _build_keymove_mapping(cfg: Dictionary, mask: Dictionary) -> String:
	var keymove: Array = cfg.get("keymove", [])
	if keymove.is_empty():
		return ""
	var target_names: Array = ["targetX", "targetY", "targetZ",
		"targetRoll", "targetPitch", "targetYaw"]
	var axis_labels: Array = ["X", "Y", "Z", "Roll", "Pitch", "Yaw"]
	var step_macros: Array = ["KEYMOVE_POSITION_SPEED", "KEYMOVE_POSITION_SPEED",
		"KEYMOVE_POSITION_SPEED", "KEYMOVE_ORIENTATION_SPEED",
		"KEYMOVE_ORIENTATION_SPEED", "KEYMOVE_ORIENTATION_SPEED"]
	var orientation_names: Array = ["roll", "pitch", "yaw"]
	var orientation_bits: Array = [1, 2, 4]
	var s: String = ""
	var has_any: bool = false
	for i in range(min(keymove.size(), 6)):
		# 姿态维度只在构形上真的能独立控制时才生成。
		if i >= 3 and not bool(mask.get(orientation_names[i - 3], false)):
			continue
		var plus_key: String = keymove[i].get("plus", "不使用")
		var minus_key: String = keymove[i].get("minus", "不使用")
		if plus_key == "不使用" and minus_key == "不使用":
			continue
		if not has_any:
			s += "    // 按键增量：位置与姿态分别使用 mm/周期和度/周期\n"
			has_any = true
		if plus_key != "不使用":
			var plus_guard: String = "RcKeyValueRead(%s)" % _key_name_to_offset(plus_key)
			if i >= 3:
				plus_guard = "(solverMask & %d) && %s" % [orientation_bits[i - 3], plus_guard]
			s += "    if (%s)\n" % plus_guard
			s += "        %s += %s; // 末端%s 正向（按键 %s）\n" % [target_names[i], step_macros[i], axis_labels[i], plus_key]
		if minus_key != "不使用":
			var minus_guard: String = "RcKeyValueRead(%s)" % _key_name_to_offset(minus_key)
			if i >= 3:
				minus_guard = "(solverMask & %d) && %s" % [orientation_bits[i - 3], minus_guard]
			s += "    if (%s)\n" % minus_guard
			s += "        %s -= %s; // 末端%s 负向（按键 %s）\n" % [target_names[i], step_macros[i], axis_labels[i], minus_key]
		if i == 4:
			s += "    if ((solverMask & 2) && targetPitch > 90.0f) targetPitch = 90.0f;\n"
			s += "    if ((solverMask & 2) && targetPitch < -90.0f) targetPitch = -90.0f;\n"
		elif i >= 3:
			s += "    if (solverMask & %d) %s = normalize_angle_deg(%s);\n" % [
				orientation_bits[i - 3], target_names[i], target_names[i]]
	return s


## 解析摇杆选项文本 -> [rocker_idx, axis_idx]
## 左摇杆固定用于底盘移动，末端控制只用右摇杆（rocker_idx=1）
## 只看 "->" 左侧的源轴，否则 "右Y->末端X" 会被右侧的 X 误判成水平轴
## "右X->末端X" -> [1, 0]; "右Y->末端X" -> [1, 1]
func parse_joy_axis(text: String) -> Array:
	if text == "不使用" or text.is_empty():
		return []
	var rocker: int = 1 # 固定右摇杆（左摇杆用于底盘）
	var src: String = text
	var arrow: int = text.find("->")
	if arrow >= 0:
		src = text.substr(0, arrow)
	var axis: int = 1 if "Y" in src else 0
	return [rocker, axis]


# ------------------------------------------------------------------ ApplyServoControl
func _gen_apply_servo_control(joints: Array, jc: int, has_exp: bool,
		engineer_cfg: Dictionary = {}, gripper: Dictionary = {}) -> String:
	var s: String = ""
	s += "/// @brief 应用舵机控制：关节角度 -> 占空比 -> 发送\n"
	s += "void ApplyServoControl()\n"
	s += "{\n"
	s += "    for (i = 0; i < JOINT_COUNT; i++)\n"
	s += "        dutyOfServo[i] = angle_to_duty(i, jointAngle[i]);\n"
	# 扩展板槽位（P60~P77）走 ExpansionBoradControl，主控板 MP03/MP74 走 PWM_SET_Frequency
	var exp_slots: Dictionary = _exp_slot_map(joints, jc)
	var main_pwm: Array = _main_pwm_list(joints, jc)
	var gripper_enabled: bool = bool(gripper.get("enabled", false))
	var gripper_pin: String = str(gripper.get("io", "")) if gripper_enabled else ""
	var gripper_slot: int = _io_to_exp_slot(gripper_pin)
	var aux_servo_slots: Array = _aux_servo_slots(engineer_cfg, joints, jc, gripper_pin)
	var aux_main_servos: Array = _aux_main_servo_list(engineer_cfg, joints, jc, gripper_pin)
	# 扩展板控制：底盘电机与关节舵机共用一次方向/占空比发送。
	var chassis_slots: Array = _chassis_slots(engineer_cfg)
	var aux_slots: Array = _aux_motor_slots(engineer_cfg)
	if has_exp or not chassis_slots.is_empty():
		var duty_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		var dir_vals: Array = ["1", "1", "1", "1", "1", "1", "1", "1"]
		for slot in exp_slots.keys():
			duty_vals[slot] = "dutyOfServo[%d]" % exp_slots[slot]
		for slot in aux_servo_slots:
			duty_vals[slot] = "(uint16_t)dutyOfAuxServo[%d]" % slot
		for motor in range(chassis_slots.size()):
			var slot: int = chassis_slots[motor]
			if slot >= 0:
				duty_vals[slot] = "(uint16_t)abs(dutyOfChassis[%d])" % motor
				dir_vals[slot] = "(dutyOfChassis[%d] >= 0 ? 1 : 0)" % motor
		for slot in aux_slots:
			duty_vals[slot] = "(uint16_t)abs(dutyOfAuxMotor[%d])" % slot
			dir_vals[slot] = "(dutyOfAuxMotor[%d] >= 0 ? 1 : 0)" % slot
		if gripper_slot >= 0:
			duty_vals[gripper_slot] = "dutyOfGripper"
			dir_vals[gripper_slot] = "1"
		if not chassis_slots.is_empty() or not aux_slots.is_empty():
			s += "    ExpansionBoradControl(Dir_Change_Order,\n"
			s += "                          %s);\n" % _exp_args(dir_vals)
			s += "    Ms_Delay(%d);\n" % EXP_SEND_DELAY_MS
		s += "    ExpansionBoradControl(Duty_Change_Order,\n"
		s += "                          %s);\n" % _exp_args(duty_vals)
		s += "    Ms_Delay(%d);\n" % EXP_SEND_DELAY_MS
	# 主控板 PWM 控制
	if main_pwm.size() > 0:
		s += "    // 主控板舵机控制（PWM）\n"
		for entry in main_pwm:
			var pwm_ch: String = entry["ch"]
			var ji: int = entry["joint"]
			s += "    PWM_SET_Frequency(%s, 50, dutyOfServo[%d]);\n" % [pwm_ch, ji]
	for entry in aux_main_servos:
		s += "    PWM_SET_Frequency(%s, 50, (uint16_t)dutyOfAuxMainServo[%d]);\n" \
			% [entry["ch"], entry["idx"]]
	if gripper_enabled and gripper_slot < 0:
		s += "    PWM_SET_Frequency(%s, 50, dutyOfGripper);\n" % _pin_to_pwm_channel(gripper_pin)
	s += "}\n\n"
	return s


## 扩展板槽位 -> 关节索引
func _exp_slot_map(joints: Array, jc: int) -> Dictionary:
	var m: Dictionary = {}
	for i in range(jc):
		var slot: int = _io_to_exp_slot(joints[i].get("io", "P60"))
		if slot >= 0:
			m[slot] = i
	return m


## 挂在主控板 PWM 引脚上的关节列表 [{joint, ch}]
func _main_pwm_list(joints: Array, jc: int) -> Array:
	var out: Array = []
	for i in range(jc):
		var pin: String = joints[i].get("io", "P60")
		if _io_to_exp_slot(pin) < 0:
			out.append({"joint": i, "ch": _pin_to_pwm_channel(pin)})
	return out


## 把 8 个槽位参数格式化为 ExpansionBoradControl 的实参列表（每行两个，对齐续行）
func _exp_args(vals: Array) -> String:
	return "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [
		vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7]]


# ------------------------------------------------------------------ All_Init
func _gen_all_init(joints: Array, jc: int, engineer_cfg: Dictionary = {},
		gripper: Dictionary = {}) -> String:
	var s: String = ""
	s += "void All_Init()\n"
	s += "{\n"
	s += "    // 初始化诊断分步：卡在哪步，LED 就停在对应编码（P37 P36 P35 二进制）\n"
	s += "    //   000 上电   001 Board_Init   010 UART1   011 LED 自检\n"
	s += "    //   100 NRF遥控 101 拓展板 Init 110 PWM/舵机 111 完成\n"
	s += "    StepBegin(0);\n"
	s += "    Board_Init();\n"
	s += "    StepDone(0);\n"
	s += "    StepBegin(1);\n"
	s += _gen_uart_init_first()
	s += "    StepDone(1);\n"
	s += "    StepBegin(2);\n"
	s += _gen_led_diag_init()
	s += "    StepDone(2);\n"
	s += "    StepBegin(3);\n"
	s += _gen_nrf_init_safe()
	s += "    StepDone(3);\n"
	s += "    StepBegin(4);\n"
	# 扩展板槽位（P60~P77）走 ExpansionBoradControl，主控板 MP03/MP74 走 PWM_Init
	var exp_slots: Dictionary = _exp_slot_map(joints, jc)
	var main_pwm: Array = _main_pwm_list(joints, jc)
	var chassis_slots: Array = _chassis_slots(engineer_cfg)
	var gripper_enabled: bool = bool(gripper.get("enabled", false))
	var gripper_pin: String = str(gripper.get("io", "")) if gripper_enabled else ""
	var gripper_slot: int = _io_to_exp_slot(gripper_pin)
	var aux_servo_slots: Array = _aux_servo_slots(engineer_cfg, joints, jc, gripper_pin)
	var aux_main_servos: Array = _aux_main_servo_list(engineer_cfg, joints, jc, gripper_pin)
	# 工程正解模式辅助舵机的初始角（IO 初始化区填写，相对中位偏移角）
	var io_mid: Dictionary = engineer_cfg.get("io_mid", {})
	if exp_slots.size() > 0 or not chassis_slots.is_empty() or gripper_slot >= 0:
		# 构建 Init_Order：舵机槽位频率 50，其余 0（维持原状）
		var init_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots.keys():
			init_vals[slot] = "50"
		for slot in aux_servo_slots:
			init_vals[slot] = "50"
		for slot in chassis_slots:
			if slot >= 0:
				init_vals[slot] = "10000"
		for slot in _aux_motor_slots(engineer_cfg):
			init_vals[slot] = "10000"
		if gripper_slot >= 0:
			init_vals[gripper_slot] = "50"
		s += "    // 扩展板舵机初始化（频率 50Hz），未占用槽位传 0 表示维持原状\n"
		s += "    ExpansionBoradControl(Init_Order,\n"
		s += "                          %s);\n" % _exp_args(init_vals)
		s += "    Ms_Delay(20);\n"
		# 舵机转向已由 angle_to_duty 的占空比镜像实现，
		# 若此处再发 Dir_Change_Order 会与之叠加抵消，故不发送。
		s += "    // 舵机转向已在 angle_to_duty 中以占空比镜像实现，无需 Dir_Change_Order\n"
		# 上电即推到初始角度，避免舵机停在上次断电位置
		var home_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots.keys():
			var idx: int = exp_slots[slot]
			home_vals[slot] = "angle_to_duty(%d, jointHome[%d])" % [idx, idx]
		for slot in aux_servo_slots:
			home_vals[slot] = str(_io_mid_duty(io_mid, EXP_PINS[slot]))
		if gripper_slot >= 0:
			home_vals[gripper_slot] = "dutyOfGripper"
		s += "    // 上电先把关节与夹爪推到初始状态\n"
		s += "    ExpansionBoradControl(Duty_Change_Order,\n"
		s += "                          %s);\n" % _exp_args(home_vals)
		s += "    Ms_Delay(20);\n"
	s += "    StepDone(4);\n"
	s += "    StepBegin(5);\n"
	# 主控板 PWM 初始化
	if main_pwm.size() > 0:
		s += "    // 主控板舵机 PWM 初始化，初始占空比 = 初始角度对应值\n"
		for entry in main_pwm:
			var pwm_ch: String = entry["ch"]
			var ji: int = entry["joint"]
			s += "    PWM_Init(%s, 50, angle_to_duty(%d, jointHome[%d]));\n" % [pwm_ch, ji, ji]
	for entry in aux_main_servos:
		var aux_pin: String = "MP03" if entry["idx"] == 0 else "MP74"
		s += "    PWM_Init(%s, 50, %d);\n" % [entry["ch"], _io_mid_duty(io_mid, aux_pin)]
	if gripper_enabled and gripper_slot < 0:
		s += "    PWM_Init(%s, 50, dutyOfGripper);\n" % _pin_to_pwm_channel(gripper_pin)
	if not engineer_cfg.is_empty():
		s += "    for (i = 0; i < 8; i++) dutyOfAuxServo[i] = SERVO_MID_DUTY;\n"
		for slot in aux_servo_slots:
			s += "    dutyOfAuxServo[%d] = %d;\n" % [slot, _io_mid_duty(io_mid, EXP_PINS[slot])]
		s += "    dutyOfAuxMainServo[0] = %d; // MP03\n" % _io_mid_duty(io_mid, "MP03")
		s += "    dutyOfAuxMainServo[1] = %d; // MP74\n" % _io_mid_duty(io_mid, "MP74")
	s += "    StepDone(5);\n"
	s += _gen_init_done("Beep")
	s += "}\n\n"
	return s


func _chassis_slots(cfg: Dictionary) -> Array:
	if cfg.is_empty():
		return []
	return [
		_io_to_exp_slot(_parse_io_pair(str(cfg.get("l1_io", "P74 P24")))),
		_io_to_exp_slot(_parse_io_pair(str(cfg.get("l2_io", "P75 P25")))),
		_io_to_exp_slot(_parse_io_pair(str(cfg.get("r1_io", "P76 P26")))),
		_io_to_exp_slot(_parse_io_pair(str(cfg.get("r2_io", "P77 P27")))),
	]


func _aux_motor_slots(cfg: Dictionary) -> Array:
	var slots: Array = []
	var io_init: Dictionary = cfg.get("io_init", {})
	for row in _all_engineer_rows(cfg):
		var pin: String = str(row.get("io", ""))
		var slot: int = _io_to_exp_slot(pin)
		if slot >= 0 and str(io_init.get(pin, "舵机")) == "电机" and not slot in slots:
			slots.append(slot)
	return slots


func _aux_servo_slots(cfg: Dictionary, joints: Array, jc: int,
		excluded_pin: String = "") -> Array:
	var joint_ios: Array = []
	for i in range(jc):
		joint_ios.append(str(joints[i].get("io", "")))
	var slots: Array = []
	var io_init: Dictionary = cfg.get("io_init", {})
	for row in _all_engineer_rows(cfg):
		var pin: String = str(row.get("io", ""))
		var slot: int = _io_to_exp_slot(pin)
		if slot >= 0 and pin != excluded_pin and not pin in joint_ios \
				and str(io_init.get(pin, "舵机")) == "舵机" \
				and not slot in slots:
			slots.append(slot)
	return slots


func _aux_main_servo_list(cfg: Dictionary, joints: Array, jc: int,
		excluded_pin: String = "") -> Array:
	var joint_ios: Array = []
	for i in range(jc):
		joint_ios.append(str(joints[i].get("io", "")))
	var out: Array = []
	for pin in ["MP03", "MP74"]:
		if pin in joint_ios or pin == excluded_pin:
			continue
		for row in _all_engineer_rows(cfg):
			if str(row.get("io", "")) == pin:
				out.append({"idx": 0 if pin == "MP03" else 1,
					"ch": _pin_to_pwm_channel(pin)})
				break
	return out


# ------------------------------------------------------------------ ExpansionBoradControl
func _gen_expansion_board_func() -> String:
	var s: String = ""
	s += "/// @brief 板间通信函数，用于主控给拓展版发送\n"
	s += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	s += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	s += "                           uint16_t data_p77)\n"
	s += "{\n"
	s += "    uint8_t i = 0;\n"
	s += "    uint8_t control_frame_pack[21] = {0};\n"
	s += "    control_frame_pack[0] = COMM_HEADER_1;\n"
	s += "    control_frame_pack[1] = COMM_HEADER_2;\n"
	s += "    control_frame_pack[19] = COMM_END_1;\n"
	s += "    control_frame_pack[20] = COMM_END_2;\n"
	s += "    control_frame_pack[2] = control_cmd;\n"
	s += "    control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);\n"
	s += "    control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);\n"
	s += "    control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);\n"
	s += "    control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);\n"
	s += "    control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);\n"
	s += "    control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);\n"
	s += "    control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);\n"
	s += "    control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);\n"
	s += "    for (i = 0; i < 21; i++)\n"
	s += "        Uart1TxQuery(control_frame_pack[i]); // 查询发送，不依赖 TX 中断\n"
	s += "}\n"
	return s


# ------------------------------------------------------------------ 工具
func _gripper_config(raw: Variant) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	return {
		"enabled": bool(src.get("enabled", false)),
		"io": str(src.get("io", "MP03")),
		"dir": str(src.get("dir", "正向")),
		"open_angle": str(src.get("open_angle", "45")),
		"closed_angle": str(src.get("closed_angle", "-45")),
		"initial_open": bool(src.get("initial_open", true)),
		"key": str(src.get("key", "D")),
	}


func _gripper_duty(gripper: Dictionary, opened: bool) -> int:
	var field: String = "open_angle" if opened else "closed_angle"
	var angle: float = clampf(_to_float(str(gripper.get(field, "0")), 0.0),
		- SERVO_MAX_OFFSET_DEG, SERVO_MAX_OFFSET_DEG)
	if str(gripper.get("dir", "正向")) == "反向":
		angle = - angle
	return clampi(SERVO_DUTY_MID + int(round(angle * SERVO_DUTY_PER_DEG)),
		SERVO_DUTY_MIN, SERVO_DUTY_MAX)


func _to_float(s: String, default: float) -> float:
	s = s.strip_edges()
	if s.is_empty():
		return default
	if s.is_valid_float():
		return s.to_float()
	return default
