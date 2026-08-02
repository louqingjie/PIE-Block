#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pie-Block 代码生成器 MCP Server
================================

把 Godot 里的图形化代码生成器暴露成 MCP 工具，供任何 MCP 客户端（Claude、
Copilot、open-code 等）调用。

原理：
  1. 本 Server 通过 subprocess 调用 `scripts/cli_codegen.gd`（Godot headless CLI）
  2. CLI 复用项目里现有的 CodeGenInfantry / CodeGenEngineerIK / CodeGenDebug
     与 StaticChecker，零逻辑重复
  3. 每次调用启动一个 Godot 进程（约 1~2 秒），对 Agent 交互来说可接受

配置：
  PIEBLOCK_GODOT    godot 可执行文件路径（默认走 PATH 里的 godot）
  PIEBLOCK_ROOT     项目根目录（默认 = 本文件上两级）

用法：
  python tools/pieblock_mcp_server.py            # stdio 模式（MCP 客户端用）
  python tools/pieblock_mcp_server.py --help     # 帮助

把下面这行加进 MCP 客户端配置即可接入：
  { "command": "python", "args": ["tools/pieblock_mcp_server.py"], "cwd": "<项目根>" }
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import MCPServer

# ---------------------------------------------------------------------------
# 路径与可执行文件定位
# ---------------------------------------------------------------------------
DEFAULT_ROOT: Path = Path(__file__).resolve().parent.parent
ROOT: Path = Path(os.environ.get("PIEBLOCK_ROOT", str(DEFAULT_ROOT)))
CLI_SCRIPT: Path = ROOT / "scripts" / "cli_codegen.gd"

KINDS = ["infantry", "engineer", "debug"]


def find_godot() -> str | None:
    """定位 godot 可执行文件。优先环境变量，其次 PATH。"""
    env = os.environ.get("PIEBLOCK_GODOT")
    if env and Path(env).exists():
        return env
    return shutil.which("godot")


# ---------------------------------------------------------------------------
# CLI 子进程封装
# ---------------------------------------------------------------------------
def _run_cli(args: list[str], timeout: int = 120) -> dict[str, Any]:
    """调用 Godot CLI，返回解析后的 JSON 结果字典。

    CLI stdout 第一行是 GDExtension 插件横幅（"Initialize godot-rust..."），
    真正的 JSON 从第一个 `{` 开始。解析时跳过横幅行。
    timeout: 秒。编译（build）较耗时，调用方传入更大超时。
    """
    godot = find_godot()
    if godot is None:
        raise RuntimeError("找不到 godot 可执行文件。请安装 Godot 4.x 并加入 PATH，"
                           "或设置环境变量 PIEBLOCK_GODOT 指向 godot 可执行文件。")
    if not CLI_SCRIPT.exists():
        raise RuntimeError(f"找不到 CLI 脚本: {CLI_SCRIPT}")

    cmd = [godot, "--headless", "--no-header", "--path", str(ROOT),
           "--script", str(CLI_SCRIPT), "--"] + args
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"Godot CLI 执行超时（{timeout} 秒）")

    out = proc.stdout or ""
    # 跳过横幅行：找第一个以 { 开头的行的位置
    idx = out.find("{")
    if idx < 0:
        stderr = (proc.stderr or "").strip()
        raise RuntimeError(f"CLI 未返回 JSON（退出码 {proc.returncode}）。stderr: {stderr}")

    try:
        return json.loads(out[idx:])
    except json.JSONDecodeError as e:
        raise RuntimeError(f"CLI 返回了非法 JSON: {e}\n原始输出: {out[idx:idx + 400]}")


def _write_temp_config(cfg: dict[str, Any]) -> str:
    """把配置字典写入临时 JSON 文件，返回路径。"""
    fd, path = tempfile.mkstemp(suffix=".json", prefix="pieblock_cfg_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return path


def _result_text(result: dict[str, Any]) -> str:
    """把 CLI 返回的 issues 列表格式化成 Agent 可读的文本。"""
    issues = result.get("issues", [])
    lines = [f"检查结果: {len(issues)} 条问题"]
    for i in issues:
        lines.append(f"  [{i.get('type', 'Info')}] {i.get('msg', '')}")
    if not issues:
        lines.append("  （无问题）")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# MCP Server 与工具
# ---------------------------------------------------------------------------
mcp = MCPServer(
    name="pie-block-codegen",
    title="Pie-Block 代码生成器",
    description="为 STC32G 主控板生成步兵/工程/调试机器人 main.c 代码，并做静态检查。"
                "用户是制作机器人机械结构的大一学生，不熟悉编程。",
    version="0.1.0",
    instructions=(
        "此服务器把 Pie-Block 图形化代码生成器暴露为命令行工具。\n"
        "支持的 kind: infantry（步兵）/ engineer（工程，含 2~6 关节机械臂逆解算）/ debug（调试）。\n"
        "生成配置用 JSON 字符串传入。可用 get_schema(kind) 获取每种 kind 的完整字段定义。\n"
        "重要硬件约束（不可违反）：\n"
        "- 只向主控板烧录，绝不向机械扩展板烧录\n"
        "- 扩展板 IO（P60/P62/P64/P66/P74/P75/P76/P77）只能通过 ExpansionBoradControl 控制，"
        "禁止使用 PWM_* 函数，且使用前必须初始化\n"
        "- 步兵上 P64/P66 固定用于两个摩擦轮\n"
        "- 主控板 MP74/MP03 只能驱动舵机，且与扩展板 P74 不是同一个 IO\n"
        "generate_code 返回的 has_error 表示配置存在 Error 级问题（代码仍会生成供参考），"
        "Agent 应在修复配置后重新生成。"
    ),
)


@mcp.tool()
def list_profiles() -> str:
    """列出所有支持的项目类型（infantry / engineer / debug）及其用途说明。"""
    try:
        result = _run_cli(["profiles"])
    except RuntimeError as e:
        return f"错误: {e}"
    return json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def get_schema(kind: str) -> str:
    """获取指定项目类型的配置 JSON Schema（字段名、类型、默认值、可选值）。

    参数 kind: infantry / engineer / debug 之一。
    """
    if kind not in KINDS:
        return f"错误: 未知 kind「{kind}」，合法值: {', '.join(KINDS)}"
    try:
        result = _run_cli(["schema", "--kind", kind])
    except RuntimeError as e:
        return f"错误: {e}"
    return json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def generate_code(kind: str, config: str, out_path: str | None = None) -> str:
    """根据 JSON 配置生成 main.c 代码，并返回静态检查结果。

    参数:
      kind: infantry / engineer / debug
      config: JSON 字符串。字段定义见 get_schema(kind)。engineer 需要 {engineer, ik} 双字典。
      out_path: 可选，把生成的 C 代码写入此绝对路径（不指定则只返回 JSON，code 字段含代码）。

    返回 JSON:
      ok: 命令是否执行成功
      has_error: 配置是否有 Error 级问题（代码仍会生成供参考）
      issues: 静态检查问题列表
      code: 生成的 C 代码（未指定 out_path 时）
      out: 输出文件路径（指定 out_path 时）
    """
    if kind not in KINDS:
        return f"错误: 未知 kind「{kind}」，合法值: {', '.join(KINDS)}"
    try:
        cfg: dict[str, Any] = json.loads(config)
        if not isinstance(cfg, dict):
            return "错误: config 必须是 JSON 对象（字典）"
    except json.JSONDecodeError as e:
        return f"错误: config 不是合法 JSON: {e}"

    cfg_path = _write_temp_config(cfg)
    try:
        args = ["generate", "--kind", kind, "--config", cfg_path]
        if out_path:
            args += ["--out", out_path]
        result = _run_cli(args)
    except RuntimeError as e:
        return f"错误: {e}"
    finally:
        try:
            os.remove(cfg_path)
        except OSError:
            pass

    out = json.dumps(result, ensure_ascii=False, indent=2)
    if result.get("has_error"):
        out += "\n\n[!] 配置存在 Error 级问题（代码仅供参考）。请根据 issues 修复配置后重新生成。"
    return out


@mcp.tool()
def check_config(kind: str, config: str) -> str:
    """仅运行静态检查，不生成代码。

    参数:
      kind: infantry / engineer / debug
      config: JSON 字符串，同 generate_code。

    返回 JSON:
      ok: 是否有 Error（true = 无 Error）
      issues: 问题列表（Error 必须修复，Warn 建议修复）
      error_count / warn_count: 数量统计
    """
    if kind not in KINDS:
        return f"错误: 未知 kind「{kind}」，合法值: {', '.join(KINDS)}"
    try:
        cfg: dict[str, Any] = json.loads(config)
        if not isinstance(cfg, dict):
            return "错误: config 必须是 JSON 对象（字典）"
    except json.JSONDecodeError as e:
        return f"错误: config 不是合法 JSON: {e}"

    cfg_path = _write_temp_config(cfg)
    try:
        result = _run_cli(["check", "--kind", kind, "--config", cfg_path])
    except RuntimeError as e:
        return f"错误: {e}"
    finally:
        try:
            os.remove(cfg_path)
        except OSError:
            pass
    return json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def generate_from_project(project_path: str, out_path: str | None = None) -> str:
    """从 .pieproj 项目文件生成代码（复用项目里保存的配置）。

    参数:
      project_path: .pieproj 文件绝对路径
      out_path: 可选，把生成的 C 代码写入此路径

    注意: 旧版本保存的项目（config 用旧节点路径）可能无法完整还原配置，
    此时 issues 会报错。推荐用 generate_code 传结构化 JSON。
    """
    if not os.path.isfile(project_path):
        return f"错误: 项目文件不存在: {project_path}"
    try:
        args = ["generate", "--project", project_path]
        if out_path:
            args += ["--out", out_path]
        result = _run_cli(args)
    except RuntimeError as e:
        return f"错误: {e}"
    return json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
def build_code(kind: str, config: str) -> str:
    """生成代码并用 Keil C251 编译为 hex 固件（供真机烧录）。

    参数:
      kind: infantry / engineer / debug
      config: JSON 字符串，同 generate_code。字段定义见 get_schema(kind)。

    返回 JSON:
      ok: 编译是否成功（Keil 日志含 "0 Error(s)"）
      exit: Keil 退出码
      kind: 项目类型
      log: 编译日志（含 Error/Warning 与 Program Size）
      hex: 编译产物 hex 文件绝对路径
      hex_exists: hex 固件是否已生成

    注意: 编译同步阻塞，通常 10~60 秒（首次会先解压 Keil 工具链）。
    生成代码前请先确认 config 无 Error 级问题（用 check_config）。
    """
    if kind not in KINDS:
        return f"错误: 未知 kind「{kind}」，合法值: {', '.join(KINDS)}"
    try:
        cfg: dict[str, Any] = json.loads(config)
        if not isinstance(cfg, dict):
            return "错误: config 必须是 JSON 对象（字典）"
    except json.JSONDecodeError as e:
        return f"错误: config 不是合法 JSON: {e}"

    cfg_path = _write_temp_config(cfg)
    try:
        result = _run_cli(["build", "--kind", kind, "--config", cfg_path], timeout=300)
    except RuntimeError as e:
        return f"错误: {e}"
    finally:
        try:
            os.remove(cfg_path)
        except OSError:
            pass

    out = json.dumps(result, ensure_ascii=False, indent=2)
    if result.get("ok"):
        out += "\n\n[✓] 编译成功，hex 固件已生成。"
    else:
        out += "\n\n[!] 编译失败，请根据 log 中的 Error 修复配置后重新编译。"
    return out


@mcp.tool()
def build_project(project_path: str) -> str:
    """从 .pieproj 项目文件编译为 hex 固件（优先用项目里已保存的代码）。

    参数:
      project_path: .pieproj 文件绝对路径

    返回 JSON: 同 build_code。
    """
    if not os.path.isfile(project_path):
        return f"错误: 项目文件不存在: {project_path}"
    try:
        result = _run_cli(["build", "--project", project_path], timeout=300)
    except RuntimeError as e:
        return f"错误: {e}"
    return json.dumps(result, ensure_ascii=False, indent=2)


def main() -> None:
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        return
    asyncio.run(mcp.run_stdio_async())


if __name__ == "__main__":
    main()
