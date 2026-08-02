extends SceneTree

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const P = preload("res://scripts/ik_sim_protocol.gd")

var failures: int = 0


func _initialize() -> void:
	var cg = CG.new()
	var joints: Array = [
		_joint("Yaw", 0.0), _joint("Pitch", 120.0),
		_joint("Pitch", 90.0), _joint("Roll", 20.0),
	]
	var cfg: Dictionary = {"joint_count": 4, "joints": joints}
	var source: String = _host_prefix(cg, joints)
	source += cg._build_joint_config_arrays(joints, 4)
	source += cg._build_kinematics_arrays(joints, 4)
	source += cg.generate_kinematics_core(4, joints)
	source += cg._gen_sim_protocol(cg.solver_fingerprint(cfg), 4)
	source += _host_main()
	var dir: String = ProjectSettings.globalize_path("user://ik-sim-firmware-host")
	DirAccess.make_dir_recursive_absolute(dir)
	var source_path: String = dir.path_join("ik_sim_firmware_host.c")
	var exe_path: String = dir.path_join("ik_sim_firmware_host.exe")
	var file := FileAccess.open(source_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write MCU simulator protocol host test")
		quit(1)
		return
	file.store_string(source)
	file.close()
	var build_output: Array = []
	var build_exit: int = OS.execute("gcc.exe", ["-std=c99", "-O0", "-Wall", "-Werror",
		"-Wno-misleading-indentation", "-Wno-sign-compare", source_path,
		"-lm", "-o", exe_path], build_output, true)
	_check("generated MCU simulator protocol compiles as host C", build_exit == 0,
		"\n".join(build_output))
	if build_exit != 0:
		print("MCU simulator firmware host: %d failure(s)" % failures)
		quit(failures)
		return
	var run_output: Array = []
	var run_exit: int = OS.execute(exe_path, [], run_output, true)
	_check("generated MCU simulator protocol host exits cleanly", run_exit == 0,
		"\n".join(run_output))
	var frames: Dictionary = _parse_output("\n".join(run_output))
	_check_response(frames, "hello", P.RESP_HELLO, 1)
	_check_response(frames, "ping", P.RESP_STATE, 2)
	_check_response(frames, "unknown", P.RESP_ERROR, 3)
	_check_response(frames, "nan_pose", P.RESP_ERROR, 4)
	var set_frame: Dictionary = _frame(frames, "set_joints")
	_check("SET_JOINTS returns state", bool(set_frame.get("ok", false))
		and int(set_frame.get("type", 0)) == P.RESP_STATE)
	if bool(set_frame.get("ok", false)):
		var payload: PackedByteArray = set_frame.get("payload", PackedByteArray())
		_check("SET_JOINTS applies joint limits",
			is_equal_approx(P.read_float32(payload, 13), 90.0)
			and is_equal_approx(P.read_float32(payload, 17), -90.0))
		_check("SET_JOINTS reports clamping",
			(int(payload[0]) & P.STATUS_CLAMPED) != 0)
	_check("CRC-corrupt request produces no response",
		str(frames.get("bad_crc", "")) == "")
	_check_response(frames, "after_bad_crc", P.RESP_STATE, 7)
	_check("oversize request produces no response",
		str(frames.get("oversize", "")) == "")
	_check_response(frames, "after_oversize", P.RESP_STATE, 8)
	_check_response(frames, "home", P.RESP_STATE, 9)
	print("MCU simulator firmware host: %d failure(s)" % failures)
	quit(failures)


func _joint(axis: String, length: float) -> Dictionary:
	return {"io": "P74", "dir": "正向", "axis": axis, "len": str(length),
		"offset": "0", "zero": "0", "min": "-90", "max": "90"}


func _host_prefix(cg, joints: Array) -> String:
	return """#include <math.h>
#include <stdint.h>
#include <stdio.h>
#define xdata
#define JOINT_COUNT 4
#define IK_EPS 0.001f
#define DEG_TO_RAD 0.0174532925f
#define RAD_TO_DEG 57.29577951f
#define IK_MAX_STEP_DEG %.1ff
#define ORIENTATION_WEIGHT %.2ff
#define SOLVER_PROTOCOL_VERSION 1
#define SOLVER_ALGORITHM_VERSION 2
#define FRAME_DELIMITER 0x7e
#define FRAME_ESCAPE 0x7d
#define RESP_HELLO 0x81
#define RESP_STATE 0x82
#define RESP_ERROR 0xff
#define UART_1 1
float jointAngle[JOINT_COUNT] = {0,0,0,0};
float targetX,targetY,targetZ,targetRoll,targetPitch,targetYaw;
uint8_t solverMask=0,solverPositionDof=0,solverOrientationDof=0;
uint8_t solverStatus=1,ikDiagnosing=0,ik_reachable=1;
static uint8_t tx[512];static unsigned txLen=0;
void UART_PutChar(uint8_t uart,uint8_t value){(void)uart;if(txLen<sizeof(tx))tx[txLen++]=value;}
""" % [cg.JACOBI_MAX_STEP_DEG, cg._orientation_weight(cg.joint_lengths(joints, 4))]


func _host_main() -> String:
	var hello: String = _c_bytes(P.pack_frame(P.CMD_HELLO, 1, PackedByteArray()))
	var ping: String = _c_bytes(P.pack_frame(P.CMD_PING, 2, PackedByteArray()))
	var unknown: String = _c_bytes(P.pack_frame(0x66, 3, PackedByteArray()))
	var nan_pose: String = _c_bytes(P.pack_frame(P.CMD_STEP_POSE, 4,
		P.pose_payload(Vector3(NAN, 0, 0), Vector3.ZERO)))
	var set_joints: String = _c_bytes(P.pack_frame(P.CMD_SET_JOINTS, 5,
		P.joints_payload([200.0, -200.0, 10.0, 20.0], 4)))
	var bad_crc_bytes: PackedByteArray = P.pack_frame(P.CMD_PING, 6, PackedByteArray())
	bad_crc_bytes[3] ^= 0x01
	var bad_crc: String = _c_bytes(bad_crc_bytes)
	var after_bad_crc: String = _c_bytes(P.pack_frame(P.CMD_PING, 7, PackedByteArray()))
	var after_oversize: String = _c_bytes(P.pack_frame(P.CMD_PING, 8, PackedByteArray()))
	var home: String = _c_bytes(P.pack_frame(P.CMD_HOME, 9, PackedByteArray()))
	return """
static const uint8_t hello[] = {%s};
static const uint8_t ping[] = {%s};
static const uint8_t unknown[] = {%s};
static const uint8_t nan_pose[] = {%s};
static const uint8_t set_joints[] = {%s};
static const uint8_t bad_crc[] = {%s};
static const uint8_t after_bad_crc[] = {%s};
static const uint8_t after_oversize[] = {%s};
static const uint8_t home[] = {%s};
static void print_tx(const char *name){unsigned i;printf("%%s=",name);for(i=0;i<txLen;i++)printf("%%02x",tx[i]);printf("\\n");}
static void feed(const char *name,const uint8_t *data,unsigned size){unsigned i;txLen=0;for(i=0;i<size;i++)IKSimRxByte(data[i]);if(ikSimFrameReady)IkSimProcessFrame();print_tx(name);}
int main(void){unsigned i;ik_diagnose();IkSimSyncTarget();
feed("hello",hello,sizeof(hello));feed("ping",ping,sizeof(ping));feed("unknown",unknown,sizeof(unknown));
feed("nan_pose",nan_pose,sizeof(nan_pose));feed("set_joints",set_joints,sizeof(set_joints));
feed("bad_crc",bad_crc,sizeof(bad_crc));feed("after_bad_crc",after_bad_crc,sizeof(after_bad_crc));
txLen=0;IKSimRxByte(0x7e);for(i=0;i<150;i++)IKSimRxByte(0x11);IKSimRxByte(0x7e);if(ikSimFrameReady)IkSimProcessFrame();print_tx("oversize");
feed("after_oversize",after_oversize,sizeof(after_oversize));feed("home",home,sizeof(home));return 0;}
""" % [hello, ping, unknown, nan_pose, set_joints, bad_crc,
		after_bad_crc, after_oversize, home]


func _c_bytes(bytes: PackedByteArray) -> String:
	var values: Array[String] = []
	for value in bytes:
		values.append("0x%02x" % int(value))
	return ",".join(values)


func _parse_output(output: String) -> Dictionary:
	var result: Dictionary = {}
	for line in output.split("\n", false):
		var pair: PackedStringArray = line.strip_edges().split("=", true, 1)
		if pair.size() == 2:
			result[pair[0]] = pair[1]
	return result


func _frame(frames: Dictionary, name: String) -> Dictionary:
	var text: String = str(frames.get(name, ""))
	return P.parse_frame(text.hex_decode()) if not text.is_empty() else {
		"ok": false, "error": "empty"}


func _check_response(frames: Dictionary, name: String, kind: int, sequence: int) -> void:
	var parsed: Dictionary = _frame(frames, name)
	_check("%s response type and sequence" % name, bool(parsed.get("ok", false))
		and int(parsed.get("type", 0)) == kind
		and int(parsed.get("sequence", -1)) == sequence, str(parsed))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] ", label)
	else:
		failures += 1
		push_error("%s: %s" % [label, detail])
