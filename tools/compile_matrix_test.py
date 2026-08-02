#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""编译矩阵测试：用 CLI 批量编译各种配置，寻找代码生成器漏洞。

每个用例：{name, kind, config}，调用 godot CLI build，汇总 ok/code/错误。
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

# 工程模板：3 关节默认配置（可改 joint_count/joints 变体）
def _eng(joints, presets=None, key_map=None, gripper=None, engineer_extra=None):
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
        "mode_switch_key": "R",
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


# 工程机械臂 IO 池（避开底盘 P74-P77）
IOS = ["P60", "P62", "P64", "P66", "MP03", "MP74"]

# ---------------------------------------------------------------------------
# 用例定义
# ---------------------------------------------------------------------------
CASES = []

# 1. 关节数越界：1 个关节（应被钳到 2）
CASES.append(("eng_1joint", "engineer", _eng([_joint("P60", "Yaw", "0")])))
# 2. 关节数越界：joint_count=7（应被钳到 6）
j7cfg = _eng([_joint(IOS[i], ["Yaw", "Pitch", "Pitch", "Roll", "Pitch", "Roll"][i])
              for i in range(6)])
j7cfg["ik"]["joint_count"] = 7
CASES.append(("eng_7joint", "engineer", j7cfg))
# 3. 6 关节全 Roll（病态构型，应有诊断提示）
j6r = [_joint(IOS[i], "Roll") for i in range(6)]
CASES.append(("eng_6roll", "engineer", _eng(j6r)))
# 4. 5 关节混合
j5 = [_joint(IOS[i], ["Yaw", "Pitch", "Pitch", "Roll", "Pitch"][i]) for i in range(5)]
CASES.append(("eng_5mix", "engineer", _eng(j5)))
# 5. 关节 IO 重复（两个关节用同一 IO，检查器应报错）
jdup = [_joint("P60", "Yaw", "0"), _joint("P60", "Pitch")]
CASES.append(("eng_dupio", "engineer", _eng(jdup)))
# 6. 关节 IO 与底盘冲突（P74 是底盘电机，应报错）
jconflict = [_joint("P74", "Yaw", "0"), _joint("P75", "Pitch")]
CASES.append(("eng_io_conflict", "engineer", _eng(jconflict)))
# 7. 启用夹爪（占 MP03 舵机）
j3 = [_joint("P60", "Yaw", "0"), _joint("P62", "Pitch"), _joint("P64", "Pitch")]
grip = {"enabled": True, "io": "MP03", "dir": "正向", "open_angle": "45",
        "closed_angle": "-45", "initial_open": True, "key": "D"}
CASES.append(("eng_gripper", "engineer", _eng(j3, gripper=grip)))
# 8. key_map 用速度模式（需要摇杆输入行：右摇杆X）
km = [
    {"input": "右摇杆X", "dir": "正向", "mode": "速度", "param": "3000", "target": "P60"},
    {"input": "A", "dir": "正向", "mode": "直接", "param": "30", "target": "P62"},
]
CASES.append(("eng_keymap_speed", "engineer", _eng(j3, key_map=km)))
# 9. 空 io_init（缺省，应回退舵机/电机默认）
CASES.append(("eng_empty_ioinit", "engineer", _eng(
    j3, engineer_extra={"io_init": {}})))
# 10. 步兵：空配置直接编译（默认值兜底）
CASES.append(("inf_empty", "infantry", {}))
# 11. 步兵：云台电机 + 摩擦轮 + 拨弹全配
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
CASES.append(("inf_full", "infantry", inf_full))
# 12. 调试：空 debug_rows
CASES.append(("dbg_empty", "debug", {"debug_rows": []}))
# 13. 调试：全引脚启用
dbg_full = {"debug_rows": [
    {"pin": p, "drive_type": "舵机", "dir": 1, "value": 0, "enabled": True}
    for p in ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]]}
CASES.append(("dbg_full", "debug", dbg_full))


# ---------------------------------------------------------------------------
# 执行
# ---------------------------------------------------------------------------
def run_cli(args):
    godot = "godot"
    cmd = [godot, "--headless", "--no-header", "--path", str(ROOT),
           "--script", str(CLI), "--"] + args
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=300)
    except subprocess.TimeoutExpired:
        return {"timeout": True}
    out = proc.stdout or ""
    idx = out.find("{")
    if idx < 0:
        return {"ok": False, "exit": -1, "log": f"无 JSON, stderr={proc.stderr[:200]}", "error": True}
    try:
        return json.loads(out[idx:])
    except json.JSONDecodeError:
        return {"ok": False, "exit": -1, "log": out[idx:idx + 300], "error": True}


def main():
    failed = []
    print(f"{'用例':<22}{'ok':<5}{'exit':<6}{'code':<8} 备注")
    print("-" * 70)
    for name, kind, cfg in CASES:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                         encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False)
            path = f.name
        # 先 check 拿 issues
        chk = run_cli(["check", "--kind", kind, "--config", path])
        errors = chk.get("error_count", "?")
        # 再 build
        res = run_cli(["build", "--kind", kind, "--config", path])
        os.unlink(path)
        if res.get("timeout"):
            print(f"{name:<22}{'超时':<5} {'':<6}{'':<8} 300s 超时!")
            failed.append(name)
            continue
        ok = res.get("ok")
        m = re.search(r"code=(\d+)", res.get("log", ""))
        code = m.group(1) if m else "?"
        note = []
        if errors:
            note.append(f"检查{errors}err")
        if res.get("log") and not res.get("log", "").strip():
            note.append("空日志")
        if res.get("error"):
            note.append("CLI异常:" + str(res.get("log", ""))[:60])
        print(f"{name:<22}{str(ok):<5}{str(res.get('exit','?')):<6}{code:<8} {' '.join(note)}")
        if not ok:
            failed.append((name, res.get("log", "")[-300:]))

    print("-" * 70)
    if failed:
        print(f"\n!!! {len(failed)} 个用例编译失败:")
        for name, log in failed:
            print(f"\n=== {name} ===")
            print(log)
    else:
        print("\n全部用例编译通过（或按预期）")


if __name__ == "__main__":
    sys.exit(main())
