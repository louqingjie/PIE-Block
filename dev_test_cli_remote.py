# -*- coding: utf-8 -*-
"""临时：对比 client 的 generate 调用 vs 直接 build --remote，定位差异。"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent   # 脚本位于项目根，用 parent
sys.path.insert(0, str(ROOT))

GODOT = r"C:\Users\louqi\Desktop\program\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
os.environ["PIEBLOCK_GODOT"] = GODOT
os.environ["PIEBLOCK_PYTHON"] = str(ROOT / ".venv" / "Scripts" / "python.exe")

cli = ROOT / "scripts" / "cli_codegen.gd"
print("ROOT      =", str(ROOT))
print("CLI       =", str(cli))
print("cli exists=", cli.exists())


def run_cli(args):
    cmd = [GODOT, "--headless", "--no-header", "--path", str(ROOT),
           "--script", str(cli), "--"] + args
    return subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=240)


out_c = ROOT / "dev_out_main.c"
r1 = run_cli(["generate", "--kind", "infantry",
              "--config", str(ROOT / "tools" / "test_infantry_config.json"),
              "--out", str(out_c)])
print("\n== 1) generate ==")
print("RC:", r1.returncode)
print("stdout tail:", r1.stdout[-300:])
print("stderr tail:", r1.stderr[-500:])
print("main.c exists:", out_c.exists())

r2 = run_cli(["build", "--kind", "infantry",
              "--config", str(ROOT / "tools" / "test_infantry_config.json"),
              "--remote", "http://127.0.0.1:8000"])
print("\n== 2) build --remote ==")
print("RC:", r2.returncode)
print("stdout tail:", r2.stdout[-1500:])
print("stderr tail:", r2.stderr[-1500:])
