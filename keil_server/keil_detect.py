# -*- coding: utf-8 -*-
"""探测本机/服务器上的 Keil C251 安装。

完整正版安装的目录结构（与项目精简版 Keil_noarm 一致）：
    <keil_root>/
      UV4/uVision.com 与 UV4.exe
      C251/BIN/C251.EXE
      TOOLS.INI

本模块负责：
  - 定位 Keil 根目录（KEIL_PATH > 候选路径）
  - 校验关键可执行文件与 TOOLS.INI
  - 读取 [C251] 段许可证 LIC0 是否存在（只检测，不破解）
  - 把「项目内分发的精简工具链」部署副本到可写数据目录后使用
"""
from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from keil_server import config, tools_ini

# 部署副本的版本标记（内容变更时触发重新复制）
_TOOLCHAIN_STAMP = "keil_server_keil_noarm_v1"


@dataclass
class KeilInfo:
    """一次探测的结果。available=False 时 reason 给出失败原因。"""
    available: bool = False
    root: Path | None = None
    uv4_path: Path | None = None      # 优先 uVision.com，回退 UV4.exe
    c251_exe: Path | None = None
    c251_dir: Path | None = None      # TOOLS.INI [C251] PATH 应指向的目录
    tools_ini_path: Path | None = None
    license_ok: bool = False
    reason: str = ""


def _find_named(root: Path, name: str, depth: int = 0) -> Path | None:
    """深度优先找名字匹配的文件（作回退扫描，正常布局不触发）。"""
    if depth > 6:
        return None
    try:
        for p in root.iterdir():
            if p.name.lower() == name.lower():
                return p
    except OSError:
        return None
    try:
        for p in root.iterdir():
            if p.is_dir() and not p.name.startswith("."):
                hit = _find_named(p, name, depth + 1)
                if hit:
                    return hit
    except OSError:
        return None
    return None


def _is_under_project(root: Path) -> bool:
    """判断根目录是否位于项目内（即项目分发的精简工具链）。"""
    try:
        root.resolve().relative_to(config.PROJECT_ROOT.resolve())
        return True
    except ValueError:
        return False


def _provision_packaged(root: Path) -> Path:
    """把项目内分发的精简工具链部署副本到可写数据目录，返回可写根。

    原因：Keil_noarm/TOOLS.INI 里的 PATH/LIC0 指向仓库原始位置，
    直接使用会：1) 路径随仓库位置变化而失效；2) ensure_c251_path 修复时
    会改动仓库内被跟踪的 TOOLS.INI。部署到 DATA_DIR/keil 后即可自由修复。
    """
    dst = config.DATA_DIR / "keil"
    ver = dst / ".keil_server_version"
    if ver.exists() and ver.read_text(encoding="utf-8").strip() == _TOOLCHAIN_STAMP:
        return dst
    if dst.exists():
        shutil.rmtree(dst, ignore_errors=True)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(root, dst)
    ver.write_text(_TOOLCHAIN_STAMP, encoding="utf-8")
    return dst


def _inspect(root: Path) -> KeilInfo:
    info = KeilInfo(root=root)
    if not root.exists() or not root.is_dir():
        info.reason = f"目录不存在: {root}"
        return info

    # uVision.com 优先（控制台子系统，无 GUI 弹窗），回退 UV4.exe
    uv4_std = root / "UV4"
    uv4 = None
    for cand in ("uVision.com", "UV4.exe"):
        p = uv4_std / cand
        if p.exists():
            uv4 = p
            break
    if uv4 is None:
        uv4 = _find_named(root, "uVision.com") or _find_named(root, "UV4.exe")
    info.uv4_path = uv4

    # C251.EXE 标准位置 C251/BIN/
    c251_exe = root / "C251" / "BIN" / "C251.EXE"
    if not c251_exe.exists():
        c251_exe = _find_named(root, "C251.EXE")
    info.c251_exe = c251_exe if c251_exe and c251_exe.exists() else None

    if info.uv4_path is None:
        info.reason = "未找到 uVision.com / UV4.exe（不是有效的 Keil 安装）"
        return info
    if info.c251_exe is None:
        info.reason = "未找到 C251.EXE（该安装没有 C251 工具链）"
        return info

    # TOOLS.INI 在 Keil 根（UV4 的上级）
    tools_ini_path = root / "TOOLS.INI"
    info.tools_ini_path = tools_ini_path if tools_ini_path.exists() else None
    # [C251] PATH 应指向 C251 安装目录（BIN 的上级）
    c251_dir = root / "C251"
    if not c251_dir.exists():
        c251_dir = info.c251_exe.parent.parent
    info.c251_dir = c251_dir

    if info.tools_ini_path:
        lic = tools_ini.read_key(info.tools_ini_path, "C251", "LIC0")
        info.license_ok = bool(lic and lic.strip())

    info.available = True
    return info


def detect(keil_path_override: str = "") -> KeilInfo:
    """探测 Keil 安装。优先级：
        显式 keil_path_override > 环境变量 KEIL_PATH > 候选路径
    全部找不到时返回 available=False 及原因。
    """
    candidates: list[Path] = []
    if keil_path_override:
        candidates.append(Path(keil_path_override))
    env = os.environ.get("KEIL_PATH", "").strip()
    if env:
        candidates.append(Path(env))
    candidates += [Path(p) for p in config.KEIL_CANDIDATE_PATHS]

    reasons: list[str] = []
    for root in candidates:
        effective = root
        # 项目内分发的精简工具链 -> 部署副本后使用（可写、路径可修复）
        if root.exists() and _is_under_project(root):
            try:
                effective = _provision_packaged(root)
            except OSError as e:
                reasons.append(f"{root}: 部署副本失败: {e}")
                continue
        info = _inspect(effective)
        if info.available:
            return info
        reasons.append(f"{root}: {info.reason}")
    return KeilInfo(available=False, reason="；".join(reasons) or "未配置 Keil 路径")


def info_dict(info: KeilInfo) -> dict:
    """供 /health 输出的可序列化字典。"""
    return {
        "available": info.available,
        "root": str(info.root) if info.root else None,
        "uv4": str(info.uv4_path) if info.uv4_path else None,
        "c251_exe": str(info.c251_exe) if info.c251_exe else None,
        "tools_ini": str(info.tools_ini_path) if info.tools_ini_path else None,
        "license_ok": info.license_ok,
        "reason": info.reason,
    }
