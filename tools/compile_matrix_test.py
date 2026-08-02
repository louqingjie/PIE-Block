#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""编译矩阵 + 健壮性测试：用 CLI 批量编译各种配置，寻找代码生成器漏洞。

分两部分：
  A. 编译矩阵：每种配置 build 成 hex，验证能编译（0 Error(s)）
  B. 健壮性：喂畸形配置，验证 generate/check 不崩、返回合法 JSON

每个用例：{name, kind, config}。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "scripts" / "cli_codegen.gd"


def _eng(joints, presets=None, key_map=None, gripper=None, engineer_extra=None,
         mode_switch="R"):
    engineer = {
        "channel": "36", "deadzone": "10", "normal_speed": "4000",
        "sprint_speed": "8000", "sprint_enabled": False,
        "l1_io": "P74 P24", "l2_io": "P75 P25", "r1_io": "P76 P26", "r2_io": "P77 P27",
        "l1_dir": "正向", "l2_dir": "正向", "r1_dir": "正向", "r2_dir": "正向",
        "io_init": {"P60": "舵机", "P62": "舵机", "P64": "舵机", "P66": "舵机",
                    "P74": "电机", "P75": "电机", "P76": "电机", "P77": "电机"},
        "key_map": key_map if key_map is not None else [],
    }
    if engineer_extra:
        engineer.update(engineer_extra)
    ik = {
        "joint_count": len(joints),
        "mode_switch_key": mode_switch,
        "joints": joints,
        "gripper": gripper if gripper is not None else {
            "enabled": False, "io": "MP03", "dir": "正向",
            "open_angle": "45", "closed_angle": "-45", "initial_open": True, "key": "D"},
        "presets": presets if presets is not None else [],
        "joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
        "joy_scale": "5", "keymove_speed": "2", "orientation_key_speed": "1",
        "rocker2_home_enabled": False,
        "keymove": [
            {"plus": "上", "minus": "下"}, {"plus": "左", "minus": "右"},
            {"plus": "不使用", "minus": "不使用"}, {"plus": "不使用", "minus": "不使用"},
            {"plus": "不使用", "minus": "不使用"}, {"plus": "不使用", "minus": "不使用"}],
    }
    return {"engineer": engineer, "ik": ik}


def _joint(io, axis, length="120", extra=None):
    j = {"io": io, "dir": "正向", "axis": axis, "len": length,
         "offset": "", "zero": "10", "min": "-90", "max": "90"}
    if extra:
        j.update(extra)
    return j


IOS = ["P60", "P62", "P64", "P66", "MP03", "MP74"]

# ---------------------------------------------------------------------------
# A. 编译矩阵用例
# ---------------------------------------------------------------------------
CASES = []
ENG_AXES = ["Yaw", "Pitch", "Pitch", "Roll", "Pitch", "Roll"]


def _eng_axes(n):
    return [_joint(IOS[i], ENG_AXES[i]) for i in range(n)]


# -- 工程：关节数边界 --
CASES.append(("eng_1joint", "engineer", _eng([_joint("P60", "Yaw", "0")])))          # 钳到 2
j7cfg = _eng(_eng_axes(6))
j7cfg["ik"]["joint_count"] = 7                                                        # 钳到 6
CASES.append(("eng_7joint", "engineer", j7cfg))
CASES.append(("eng_6roll", "engineer", _eng([_joint(IOS[i], "Roll") for i in range(6)])))  # 全 Roll 病态
CASES.append(("eng_5mix", "engineer", _eng(_eng_axes(5))))
# -- 工程：转轴组合 --
CASES.append(("eng_2j_pure_pitch", "engineer", _eng(
    [_joint("P60", "Pitch"), _joint("P62", "Pitch")])))
CASES.append(("eng_3j_pure_yaw", "engineer", _eng(
    [_joint("P60", "Yaw", "0"), _joint("P62", "Yaw"), _joint("P64", "Yaw")])))
CASES.append(("eng_3j_mix_roll", "engineer", _eng(
    [_joint("P60", "Yaw", "0"), _joint("P62", "Roll"), _joint("P64", "Pitch")])))
CASES.append(("eng_4j_roll_first", "engineer", _eng(
    [_joint("P60", "Roll", "0"), _joint("P62", "Pitch"),
     _joint("P64", "Pitch"), _joint("P66", "Yaw")])))
CASES.append(("eng_6j_alt", "engineer", _eng(
    [_joint(IOS[i], ["Roll", "Pitch", "Roll", "Pitch", "Roll", "Pitch"][i]) for i in range(6)])))
# -- 工程：连杆长度 --
CASES.append(("eng_zero_len_mix", "engineer", _eng(
    [_joint("P60", "Yaw", "0"), _joint("P62", "Pitch"), _joint("P64", "Pitch", "60")])))
CASES.append(("eng_all_zero_len", "engineer", _eng(
    [_joint("P60", "Yaw", "0"), _joint("P62", "Pitch", "0"), _joint("P64", "Pitch", "0")])))
# -- 工程：预设点位 --
presets4 = [{"enabled": True, "key": k, "x": str(50 * i), "y": "10", "z": "40",
             "roll": "0", "pitch": "-15", "yaw": "5"}
            for i, k in enumerate(["A", "B", "C", "D"])]
j3 = _eng_axes(3)
CASES.append(("eng_presets4", "engineer", _eng(j3, presets=presets4)))
CASES.append(("eng_preset_pos_only", "engineer", _eng(j3, presets=[
    {"enabled": True, "key": "A", "x": "100", "y": "20", "z": "50",
     "roll": "", "pitch": "", "yaw": ""}])))
# -- 工程：夹爪 / key_map / 模式切换 --
grip = {"enabled": True, "io": "MP03", "dir": "正向", "open_angle": "45",
        "closed_angle": "-45", "initial_open": True, "key": "D"}
km_all = [
    {"input": "右摇杆X", "dir": "正向", "mode": "速度", "param": "3000", "target": "P60"},
    {"input": "右摇杆Y", "dir": "反向", "mode": "增速", "param": "5000", "target": "P62"},
    {"input": "A", "dir": "正向", "mode": "增量", "param": "5", "target": "MP03"},
    {"input": "B", "dir": "反向", "mode": "直接", "param": "30", "target": "P64"},
]
CASES.append(("eng_gripper", "engineer", _eng(j3, gripper=grip)))
CASES.append(("eng_gripper_full", "engineer", _eng(j3, presets=presets4, gripper=grip, key_map=km_all)))
CASES.append(("eng_keymap_speed", "engineer", _eng(j3, key_map=[
    {"input": "右摇杆X", "dir": "正向", "mode": "速度", "param": "3000", "target": "P60"},
    {"input": "A", "dir": "正向", "mode": "直接", "param": "30", "target": "P62"}])))
CASES.append(("eng_keymap_all", "engineer", _eng(j3, key_map=km_all)))
CASES.append(("eng_mode_switch_D", "engineer", _eng(j3, mode_switch="D")))
# -- 工程：IO 冲突（检查器应拦） --
CASES.append(("eng_dupio", "engineer", _eng([_joint("P60", "Yaw", "0"), _joint("P60", "Pitch")])))
CASES.append(("eng_io_conflict", "engineer", _eng([_joint("P74", "Yaw", "0"), _joint("P75", "Pitch")])))
CASES.append(("eng_empty_ioinit", "engineer", _eng(j3, engineer_extra={"io_init": {}})))

# -- 步兵 --
inf_full = {
    "channel": "36", "deadzone": "10", "normal_speed": "4000", "sprint_speed": "8000",
    "sprint_enabled": False,
    "l1_io": "P74 P24", "l2_io": "P75 P25", "r1_io": "P76 P26", "r2_io": "P77 P27",
    "l1_dir": "正向", "l2_dir": "正向", "r1_dir": "正向", "r2_dir": "正向",
    "booster_io": "P60", "booster_dir": "正向", "friction_l_dir": "正向",
    "friction_r_dir": "正向",
    "yaw_drive": "舵机", "yaw_io": "MP74", "yaw_dir": "正向",
    "pitch_drive": "舵机", "pitch_io": "MP03", "pitch_dir": "正向",
    "yaw_mid_offset": "0", "pitch_mid_offset": "0",
    "arrow_key": "移动", "trigger_key": "R", "trigger_speed": "6000",
    "trigger_time": "100", "booster_key": "A", "zero_enabled": False,
}
CASES.append(("inf_empty", "infantry", {}))
CASES.append(("inf_full", "infantry", inf_full))
# 云台电机 + 舵机混合（yaw 电机用 P62）
inf_motor = dict(inf_full)
inf_motor.update({"yaw_drive": "电机", "yaw_io": "P62"})
CASES.append(("inf_yaw_motor", "infantry", inf_motor))
# 云台偏移角边界 ±90
inf_off = dict(inf_full)
inf_off.update({"yaw_mid_offset": "90", "pitch_mid_offset": "-90"})
CASES.append(("inf_offset90", "infantry", inf_off))
# 速度边界 0 / 10000
inf_spd = dict(inf_full)
inf_spd.update({"normal_speed": "0", "sprint_speed": "10000"})
CASES.append(("inf_speed_bound", "infantry", inf_spd))
# 拨弹参数极端
inf_boo = dict(inf_full)
inf_boo.update({"trigger_speed": "10000", "trigger_time": "1000"})
CASES.append(("inf_booster_extreme", "infantry", inf_boo))

# -- 调试 --
CASES.append(("dbg_empty", "debug", {"debug_rows": []}))
CASES.append(("dbg_full", "debug", {"debug_rows": [
    {"pin": p, "drive_type": "舵机", "dir": 1, "value": 0, "enabled": True}
    for p in ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]]}))
CASES.append(("dbg_mix", "debug", {"debug_rows": [
    {"pin": "P60", "drive_type": "舵机", "dir": 1, "value": 0, "enabled": True},
    {"pin": "P62", "drive_type": "电机", "dir": 1, "value": 3000, "enabled": True},
    {"pin": "P64", "drive_type": "摩擦轮", "dir": 1, "value": 800, "enabled": True},
    {"pin": "MP74", "drive_type": "舵机", "dir": 0, "value": 0, "enabled": True}]}))
CASES.append(("dbg_disabled", "debug", {"debug_rows": [
    {"pin": p, "drive_type": "舵机", "dir": 1, "value": 0, "enabled": False}
    for p in ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]]}))

# ---------------------------------------------------------------------------
# B. 健壮性用例（畸形配置，验证 generate/check 不崩）
# ---------------------------------------------------------------------------
ROBUST = [
    ("r_empty", "infantry", {}),
    ("r_bad_channel_type", "infantry", {"channel": 36}),                     # 数字当字符串
    ("r_unknown_fields", "infantry", {"foo": "bar", "xyz": 1, "n": None}),   # 未知/多余字段
    ("r_bad_enum_dir", "infantry", {"l1_dir": "歪", "trigger_key": "不存在"}),
    ("r_channel_neg", "infantry", {"channel": "-5"}),
    ("r_null_config", "infantry", {"channel": None, "sprint_enabled": "yes"}),
    ("r_array_config", "infantry", [1, 2, 3]),                               # config 是数组
    ("r_bad_axis", "engineer", _eng([_joint("P60", "X", "120")])),           # 非法转轴
    ("r_bad_dir", "engineer", _eng([_joint("P60", "Pitch", "120", {"dir": "歪"})])),
    ("r_short_joints", "engineer", _eng(_eng_axes(2))),                      # joint_count=6 但只给 2 个
    ("r_missing_ik", "engineer", {"engineer": {}}),                          # 缺 ik
    ("r_missing_engineer", "engineer", {"ik": {}}),                          # 缺 engineer
    ("r_joint_no_fields", "engineer", {"ik": {"joint_count": 3, "joints": [{}, {}, {}]}}),
    ("r_debug_null_rows", "debug", {"debug_rows": None}),
    ("r_debug_rows_not_array", "debug", {"debug_rows": "P60"}),
]


# ---------------------------------------------------------------------------
# CLI 封装
# ---------------------------------------------------------------------------
def run_cli(args, timeout=300):
    godot = "godot"
    cmd = [godot, "--headless", "--no-header", "--path", str(ROOT),
           "--script", str(CLI), "--"] + args
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"timeout": True}
    out = proc.stdout or ""
    idx = out.find("{")
    if idx < 0:
        return {"ok": False, "exit": -1, "log": f"无 JSON, stderr={proc.stderr[:300]}", "error": True}
    try:
        return json.loads(out[idx:])
    except json.JSONDecodeError:
        return {"ok": False, "exit": -1, "log": out[idx:idx + 300], "error": True}


def _write_cfg(cfg):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                     encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False)
        return f.name


# ---------------------------------------------------------------------------
# 执行
# ---------------------------------------------------------------------------
def run_matrix():
    failed = []
    print("========== A. 编译矩阵 ==========")
    print(f"{'用例':<24}{'ok':<5}{'exit':<6}{'code':<8} 备注")
    print("-" * 72)
    for name, kind, cfg in CASES:
        path = _write_cfg(cfg)
        chk = run_cli(["check", "--kind", kind, "--config", path])
        errors = chk.get("error_count", "?")
        res = run_cli(["build", "--kind", kind, "--config", path])
        os.unlink(path)
        if res.get("timeout"):
            print(f"{name:<24}{'超时':<5} {'':<6}{'':<8} 300s 超时!")
            failed.append((name, "timeout"))
            continue
        ok = res.get("ok")
        m = re.search(r"code=(\d+)", res.get("log", ""))
        code = m.group(1) if m else "?"
        note = f"检查{errors}err" if errors else ""
        if res.get("error"):
            note += " CLI异常:" + str(res.get("log", ""))[:50]
        print(f"{name:<24}{str(ok):<5}{str(res.get('exit', '?')):<6}{code:<8} {note}")
        # 判定：只有「检查器无 Error 但编译失败」才是真漏洞。
        # 检查器已报 Error 的配置编译失败属预期（非法配置被正确拦截）。
        is_illegal = isinstance(errors, int) and errors > 0
        if not ok and not is_illegal:
            failed.append((name, res.get("log", "")[-250:]))
    return failed


def run_robust():
    bad = []
    print("\n========== B. 健壮性（畸形配置，应不崩且返回合法 JSON） ==========")
    for name, kind, cfg in ROBUST:
        path = _write_cfg(cfg)
        gen = run_cli(["generate", "--kind", kind, "--config", path], timeout=60)
        chk = run_cli(["check", "--kind", kind, "--config", path], timeout=60)
        os.unlink(path)
        if gen.get("timeout") or chk.get("timeout"):
            print(f"{name:<24} 超时!")
            bad.append((name, "timeout"))
        elif gen.get("error"):
            status = "异常:" + str(gen.get("log", ""))[:40]
            print(f"{name:<24} {status}")
            bad.append((name, gen.get("log", "")[:200]))
        else:
            code = gen.get("code", "")
            if not isinstance(code, str) or not code.strip():
                print(f"{name:<24} 无代码!")
                bad.append((name, "generate 未返回代码"))
            else:
                cerr = chk.get("error_count", "?")
                w = chk.get("warn_count", "?")
                print(f"{name:<24} 代码{len(code.splitlines())}行 检查{cerr}err/{w}warn")
    return bad


def main():
    matrix_failed = run_matrix()
    robust_bad = run_robust()
    print("-" * 72)
    total_fail = len(matrix_failed) + len(robust_bad)
    if total_fail:
        print(f"\n!!! {total_fail} 个问题:")
        for name, log in matrix_failed:
            print(f"\n=== [编译] {name} ===")
            print(log)
        for name, log in robust_bad:
            print(f"\n=== [健壮性] {name} ===")
            print(log)
        return 1
    print("\n全部通过：编译矩阵 + 健壮性均无异常")
    return 0


if __name__ == "__main__":
    sys.exit(main())
