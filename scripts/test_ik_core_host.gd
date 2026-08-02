extends SceneTree

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")

var failures: int = 0


func _initialize() -> void:
	var joints: Array = [
		_joint("Yaw", 0.0),
		_joint("Pitch", 120.0),
		_joint("Pitch", 90.0),
		_joint("Roll", 0.0),
	]
	var cg = CG.new()
	var lens: Array = cg.joint_lengths(joints, 4)
	var source: String = _host_prefix(cg, joints, lens, 4)
	source += cg._build_joint_config_arrays(joints, 4)
	source += cg._build_kinematics_arrays(joints, 4)
	source += cg.generate_kinematics_core(4, joints, lens)
	source += _host_main()
	var dir: String = ProjectSettings.globalize_path("user://ik-core-host")
	DirAccess.make_dir_recursive_absolute(dir)
	var source_path: String = dir.path_join("ik_core_host.c")
	var exe_path: String = dir.path_join("ik_core_host.exe")
	var file := FileAccess.open(source_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write generated host kinematics test")
		quit(1)
		return
	file.store_string(source)
	file.close()
	var build_output: Array = []
	var build_exit: int = OS.execute("gcc.exe", ["-std=c99", "-O0", "-Wall", "-Werror",
			"-Wno-misleading-indentation",
			source_path, "-lm", "-o", exe_path], build_output, true)
	_check("generated MCU core compiles as executable C", build_exit == 0,
		"\n".join(build_output))
	if build_exit == 0:
		var run_output: Array = []
		var run_exit: int = OS.execute(exe_path, [], run_output, true)
		_check("generated MCU core host harness exits cleanly", run_exit == 0,
			"\n".join(run_output))
		var values: Dictionary = _parse_output("\n".join(run_output))
		_check("Y/P/P/R MCU diagnosis enables Roll only", int(values.get("mask", -1)) == 1,
			str(values))
		_check("ignored Yaw target does not drive the Roll joint",
			absf(float(values.get("yaw_delta", INF))) < 0.001, str(values))
		_check("Roll target drives the Roll joint",
			absf(float(values.get("roll_delta", 0.0))) > 1.0, str(values))
	for guard_case in [
		["2j", [_joint("Yaw", 100.0), _joint("Pitch", 80.0)]],
		["3j_zero", [_joint("Roll", 0.0), _joint("Roll", 0.0), _joint("Roll", 0.0)]],
		["5j", [_joint("Yaw", 0.0), _joint("Pitch", 100.0),
			_joint("Roll", 0.0), _joint("Pitch", 50.0), _joint("Yaw", 20.0)]],
		["6j", [_joint("Yaw", 0.0), _joint("Pitch", 120.0),
			_joint("Pitch", 90.0), _joint("Roll", 0.0),
			_joint("Yaw", 30.0), _joint("Roll", 10.0)]],
	]:
		_run_guard_case(cg, guard_case[0], guard_case[1], dir)
	print("MCU C kinematics runtime: %d failure(s)" % failures)
	quit(failures)


func _joint(axis: String, length: float) -> Dictionary:
	return {"io": "P74", "dir": "正向", "axis": axis, "len": str(length),
		"offset": "0", "zero": "0", "min": "-90", "max": "90"}


func _host_prefix(cg, joints: Array, lens: Array, joint_count: int) -> String:
	return """#include <math.h>
#include <stdint.h>
#include <stdio.h>
#define xdata
#define JOINT_COUNT %d
#define IK_EPS 0.001f
#define DEG_TO_RAD 0.0174532925f
#define RAD_TO_DEG 57.29577951f
#define IK_MAX_STEP_DEG %.1ff
#define ORIENTATION_WEIGHT %.2ff
float jointAngle[JOINT_COUNT] = {0};
uint8_t solverMask=0,solverPositionDof=0,solverOrientationDof=0;
uint8_t ikDiagnosing=0,ik_reachable=1;
""" % [joint_count, cg.JACOBI_MAX_STEP_DEG, cg._orientation_weight(lens)]


func _run_guard_case(cg, tag: String, joints: Array, dir: String) -> void:
	var jc: int = joints.size()
	var lens: Array = cg.joint_lengths(joints, jc)
	var source: String = _host_prefix(cg, joints, lens, jc)
	source += cg._build_joint_config_arrays(joints, jc)
	source += cg._build_kinematics_arrays(joints, jc)
	source += cg.generate_kinematics_core(jc, joints, lens)
	source += _guard_main()
	var source_path: String = dir.path_join("ik_core_guard_%s.c" % tag)
	var exe_path: String = dir.path_join("ik_core_guard_%s.exe" % tag)
	var file := FileAccess.open(source_path, FileAccess.WRITE)
	if file == null:
		_check("%s host source can be written" % tag, false)
		return
	file.store_string(source)
	file.close()
	var build_output: Array = []
	var build_exit: int = OS.execute("gcc.exe", ["-std=c99", "-O0", "-Wall", "-Werror",
		"-Wno-misleading-indentation", source_path, "-lm", "-o", exe_path],
		build_output, true)
	_check("%s generated MCU core compiles" % tag, build_exit == 0,
		"\n".join(build_output))
	if build_exit != 0:
		return
	var run_output: Array = []
	var run_exit: int = OS.execute(exe_path, [], run_output, true)
	_check("%s unreachable solve remains finite and inside limits" % tag,
		run_exit == 0, "\n".join(run_output))


func _guard_main() -> String:
	return """
int main(void){
  uint8_t i,k;int finite_ok=1,limits_ok=1;
  ik_diagnose();
  for(k=0;k<40;k++)ik_solve(1000000.0f,-1000000.0f,1000000.0f,89.0f,89.0f,89.0f);
  for(i=0;i<JOINT_COUNT;i++){
    if(!isfinite(jointAngle[i]))finite_ok=0;
    if(jointAngle[i]<jointMin[i]-0.001f||jointAngle[i]>jointMax[i]+0.001f)limits_ok=0;
  }
  printf("finite=%d limits=%d pdof=%u odof=%u\\n",finite_ok,limits_ok,
    (unsigned)solverPositionDof,(unsigned)solverOrientationDof);
  return finite_ok&&limits_ok?0:2;
}
"""


func _host_main() -> String:
	return """
static void reset_home(void){uint8_t i;for(i=0;i<JOINT_COUNT;i++)jointAngle[i]=jointHome[i];}
int main(void){
  uint8_t i;float x,y,z,yaw_before,roll_before;
  ik_diagnose();
  reset_home();ik_fk();x=ikPts[JOINT_COUNT][0];y=ikPts[JOINT_COUNT][1];z=ikPts[JOINT_COUNT][2];
  yaw_before=jointAngle[3];for(i=0;i<20;i++)ik_solve(x,y,z,0.0f,0.0f,20.0f);
  printf("mask=%u\\n",(unsigned)solverMask);printf("yaw_delta=%.6f\\n",jointAngle[3]-yaw_before);
  reset_home();ik_fk();roll_before=jointAngle[3];for(i=0;i<20;i++)ik_solve(x,y,z,20.0f,0.0f,0.0f);
  printf("roll_delta=%.6f\\n",jointAngle[3]-roll_before);return 0;
}
"""


func _parse_output(output: String) -> Dictionary:
	var values: Dictionary = {}
	for line in output.split("\n", false):
		var pair: PackedStringArray = line.strip_edges().split("=", true, 1)
		if pair.size() == 2:
			values[pair[0]] = pair[1].to_float() if pair[1].is_valid_float() else pair[1]
	return values


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] ", label)
	else:
		failures += 1
		push_error("%s: %s" % [label, detail])
