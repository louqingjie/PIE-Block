# -*- coding: utf-8 -*-
"""Keil C251 编译核心。

把 toolchain.gd 已验证的编译经验复刻到 Python 服务端：
  - 命令行：uVision.com -r <uvproj> -o <log>（-r rebuild，避免 -b 返回陈旧 hex）
  - 成功判据：日志含 "0 Error(s)"（退出码不可靠，实测有警告也返回 0）
  - TOOLS.INI [C251] PATH 必须是反斜杠绝对路径
  - 许可证受限：日志含 RESTRICTED VERSION / LICENSE ERROR / ERROR L250
"""
from __future__ import annotations

import os
import re
import signal
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from keil_server import config, keil_detect, safe_unzip, tools_ini


class CompileError(Exception):
    """编译不可执行（zip 缺工程、Keil 缺失等），message 面向用户。"""


@dataclass
class CompileResult:
    ok: bool
    log: str = ""
    hex_path: str = ""
    hex_size: int = 0
    summary: dict = field(default_factory=dict)   # code/xdata/data/const
    error: str = ""
    license_restricted: bool = False


# ------------------------------------------------------------------ 工程定位
def find_uvproj(work_dir: Path) -> Path:
    """在解压目录里定位 .uvproj 工程文件。

    优先 Project_Template.uvproj；否则取目录内唯一一个 *.uvproj；
    多个且无优先名时报错（无法确定编译入口）。
    """
    mdks = list(work_dir.rglob("*.uvproj"))
    if not mdks:
        raise CompileError("zip 内未找到 .uvproj 工程文件")
    for p in mdks:
        if p.name.lower() == "project_template.uvproj":
            return p
    if len(mdks) == 1:
        return mdks[0]
    names = ", ".join(str(p.relative_to(work_dir)) for p in mdks[:5])
    raise CompileError(f"zip 内存在多个 .uvproj，无法确定编译入口: {names}")


# ------------------------------------------------------------------ 文本读取
def _read_text_lossless(path: Path) -> str:
    """读取文本：优先 UTF-8，失败回退 GBK（中文 Windows 的 Keil 日志常为 GBK）。"""
    data = path.read_bytes()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("gbk", errors="replace")


# ------------------------------------------------------------------ 日志解析
def parse_build_log(log: str) -> dict:
    """提取 Program Size 摘要与 Error/Warning 计数。

    Keil C251 的 Program Size 形如：
        Program Size: data=8.1 edata+hdata=1197 xdata=4 const=3646 code=22135
    data 可能是浮点（8.1），顺序也不是固定的 code/xdata/data。
    """
    result: dict = {"errors": 0, "warnings": 0, "size": {}}
    m = re.search(r"Program Size:\s*(.+)", log)
    if m:
        fields: dict = {}
        for key, val in re.findall(r"([\w+]+)=([\d.]+)", m.group(1)):
            fields[key] = int(val) if "." not in val else float(val)
        result["size"] = fields
    m = re.search(r"(\d+)\s+Error\(s\)", log)
    if m:
        result["errors"] = int(m.group(1))
    m = re.search(r"(\d+)\s+Warning\(s\)", log)
    if m:
        result["warnings"] = int(m.group(1))
    return result


def detect_license_restricted(log: str) -> bool:
    upper = log.upper()
    return ("RESTRICTED VERSION" in upper
            or "LICENSE ERROR" in upper
            or "ERROR L250" in upper)


def find_hex(mdk_dir: Path) -> Path | None:
    """在 MDK/Objects 下找最新的 .hex（HexSelection=1 时 ECODE 才会进 hex）。"""
    objs = mdk_dir / "Objects"
    if not objs.exists():
        return None
    hexes = [p for p in objs.iterdir() if p.suffix.lower() == ".hex"]
    if not hexes:
        return None
    return max(hexes, key=lambda p: p.stat().st_mtime)


# ------------------------------------------------------------------ 进程终止
def _kill_pid_tree(pid: int) -> None:
    """强杀进程树（uVision.com 会拉起 UV4.exe，超时必须整树终止）。"""
    if sys.platform == "win32":
        try:
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(pid)],
                capture_output=True, timeout=15,
            )
        except Exception:
            pass
    else:
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except Exception:
            pass


def _kill_process_tree(proc: subprocess.Popen) -> None:
    """兼容旧调用：按 Popen.pid 终止进程树。"""
    _kill_pid_tree(proc.pid)


def _start_build_process(cmd: list[str], cwd: Path):
    """启动编译进程；配置了降权用户（KEIL_BUILD_USER）时以该低权限账户启动。

    返回 (pid, out_file, err_file)：
      - pid         子进程 PID（超时整树终止用）
      - out/err     file-like 对象，可阻塞读取（utf-8 文本，替代 Popen 管道）
    """
    if (
        sys.platform == "win32"
        and config.BUILD_USER
        and config.BUILD_PASSWORD
    ):
        import msvcrt
        import win32api
        import win32con
        import win32file
        import win32pipe
        import win32process
        import win32security

        r_out, w_out = win32pipe.CreatePipe(None, 0)
        r_err, w_err = win32pipe.CreatePipe(None, 0)
        win32api.SetHandleInformation(w_out, win32con.HANDLE_FLAG_INHERIT, 1)
        win32api.SetHandleInformation(w_err, win32con.HANDLE_FLAG_INHERIT, 1)
        si = win32process.STARTUPINFO()
        si.dwFlags = win32con.STARTF_USESTDHANDLES
        si.hStdInput = win32api.GetStdHandle(win32api.STD_INPUT_HANDLE)
        si.hStdOutput = int(w_out)
        si.hStdError = int(w_err)
        si.wShowWindow = win32con.SW_HIDE
        try:
            h_token = win32security.LogonUser(
                config.BUILD_USER, None, config.BUILD_PASSWORD,
                win32con.LOGON32_LOGON_INTERACTIVE,
                win32con.LOGON32_PROVIDER_DEFAULT,
            )
            h, t, pid, _tid = win32process.CreateProcessAsUser(
                h_token, None, subprocess.list2cmdline(cmd), None, None, 1,
                win32con.CREATE_NO_WINDOW, None, str(cwd), si,
            )
        finally:
            win32file.CloseHandle(int(w_out))
            win32file.CloseHandle(int(w_err))
        win32api.CloseHandle(h_token)
        win32api.CloseHandle(h)
        win32api.CloseHandle(t)
        fd_out = msvcrt.open_osfhandle(int(r_out), os.O_RDONLY)
        fd_err = msvcrt.open_osfhandle(int(r_err), os.O_RDONLY)
        return (
            pid,
            os.fdopen(fd_out, "rb", closefd=True),
            os.fdopen(fd_err, "rb", closefd=True),
        )
    proc = subprocess.Popen(
        cmd, cwd=str(cwd),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
    )
    return proc.pid, proc.stdout, proc.stderr


def _communicate_timeout(
    pid: int, out_file, err_file, timeout: int,
) -> tuple[str, str, bool]:
    """并行读取 stdout/stderr，超时则整树终止。返回 (stdout, stderr, timed_out)。"""
    import threading

    chunks: dict[str, list] = {"out": [], "err": []}

    def pump(handle, key: str) -> None:
        while True:
            try:
                data = handle.read(65536)
            except Exception:
                break
            if not data:
                break
            # 降权路径是二进制流（rb），fallback 是文本流，统一成 str
            if isinstance(data, bytes):
                data = data.decode("utf-8", "replace")
            chunks[key].append(data)

    threads = [
        threading.Thread(target=pump, args=(out_file, "out"), daemon=True),
        threading.Thread(target=pump, args=(err_file, "err"), daemon=True),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout)
    timed_out = any(t.is_alive() for t in threads)
    if timed_out:
        _kill_pid_tree(pid)
        for t in threads:
            t.join(10)
    for f in (out_file, err_file):
        try:
            f.close()
        except Exception:
            pass
    stdout = "".join(chunks["out"])
    stderr = "".join(chunks["err"])
    return stdout, stderr, timed_out


def _is_uv4_running() -> bool:
    """是否有 uVision 编译进程在跑（后台 UV4.exe）。"""
    if sys.platform != "win32":
        return False
    try:
        r = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq UV4.exe", "/FO", "CSV"],
            capture_output=True, text=True, timeout=10,
        )
        return "UV4.exe" in r.stdout
    except Exception:
        return False


def _wait_for_build_done(log_abs: Path, timeout: int) -> None:
    """uVision.com 可能启动 UV4.exe 后立即退出（快速退出模式），
    管道 EOF 不代表编译结束，UV4 会在后台继续编译写 log。
    轮询：UV4 进程消失 且 log 文件大小稳定 2 秒 视为完成；超时兜底。"""
    import time

    deadline = time.time() + timeout
    last_size = -1
    stable_since: float | None = None
    while time.time() < deadline:
        uv4_alive = _is_uv4_running()
        try:
            size = log_abs.stat().st_size if log_abs.exists() else 0
        except OSError:
            size = 0
        if not uv4_alive and size > 0 and size == last_size:
            if stable_since is None:
                stable_since = time.time()
            elif time.time() - stable_since >= 2.0:
                return
        else:
            stable_since = None
        last_size = size
        time.sleep(0.5)


# ------------------------------------------------------------------ 编译
def compile_dir(work_dir: Path, timeout: int) -> CompileResult:
    """在已解压的工作目录里执行一次 Keil C251 编译。"""
    uvproj = find_uvproj(work_dir)

    keil = keil_detect.detect()
    if not keil.available:
        return CompileResult(ok=False, error=f"未找到可用的 Keil C251 安装: {keil.reason}")

    # 确保 TOOLS.INI [C251] PATH 指向安装的 C251 目录（反斜杠绝对路径）。
    # 完整版安装的 TOOLS.INI 由安装程序生成、PATH 通常已正确，只在失配时修复；
    # 只读安装写失败时跳过，让 Keil 用安装时生成的配置。
    c251_abs = str(keil.c251_dir).replace("/", "\\")
    tools_ini_target = keil.tools_ini_path or (keil.root / "TOOLS.INI")
    try:
        tools_ini.ensure_c251_path(tools_ini_target, c251_abs)
    except OSError:
        pass

    mdk_dir = uvproj.parent
    log_abs = mdk_dir / "pie_block_build.log"

    # 清掉旧 hex，避免编译失败却返回上次产物
    old_hex = find_hex(mdk_dir)
    if old_hex:
        try:
            old_hex.unlink()
        except OSError:
            pass

    cmd = [str(keil.uv4_path), "-r", str(uvproj), "-o", str(log_abs)]
    comm_timeout = max(15, timeout // 2)
    pid, fh_out, fh_err = _start_build_process(cmd, mdk_dir)
    try:
        stdout, stderr, timed_out = _communicate_timeout(pid, fh_out, fh_err, comm_timeout)
    except Exception:
        _kill_pid_tree(pid)
        return CompileResult(ok=False, error=f"编译内部错误: 无法读取编译输出")
    if timed_out:
        return CompileResult(ok=False, error=f"编译超时（>{timeout} 秒），已终止进程树")
    _wait_for_build_done(log_abs, timeout - comm_timeout)

    if log_abs.exists():
        log_text = _read_text_lossless(log_abs)
    else:
        log_text = (stdout or "") + "\n" + (stderr or "")

    summary = parse_build_log(log_text)
    ok = "0 Error(s)" in log_text
    hex_path = find_hex(mdk_dir)

    result = CompileResult(
        ok=ok,
        log=log_text,
        hex_path=str(hex_path) if hex_path else "",
        hex_size=hex_path.stat().st_size if hex_path else 0,
        summary=summary["size"],
        license_restricted=detect_license_restricted(log_text),
    )
    if not ok:
        if result.license_restricted:
            result.error = (
                "编译失败：Keil C251 许可证受限（RESTRICTED VERSION / ERROR L250）。"
                "请用 keil.com 官方流程申请免费 C251 许可证，并写入 "
                "TOOLS.INI 的 [C251] 段 LIC0=。"
            )
        elif not result.hex_path:
            result.error = "编译失败：未生成 hex 文件（详见日志）"
        else:
            result.error = (
                f"编译失败：{summary['errors']} Error(s), "
                f"{summary['warnings']} Warning(s)（详见日志）"
            )
    return result


def run_keil_build(
    zip_path: Path,
    work_dir: Path,
    timeout: int = config.BUILD_TIMEOUT,
) -> CompileResult:
    """完整一步：安全解压 -> 定位工程 -> 编译。供任务管理器与集成测试调用。"""
    try:
        safe_unzip.safe_extract(
            zip_path, work_dir,
            config.EXTRACT_MAX_SIZE,
            config.EXTRACT_MAX_FILES,
            config.EXTRACT_MAX_FILE_SIZE,
        )
    except safe_unzip.UnzipError as e:
        return CompileResult(ok=False, error=f"解压失败: {e}")
    except Exception as e:
        return CompileResult(ok=False, error=f"解压失败（非法 zip）: {e}")
    try:
        return compile_dir(work_dir, timeout)
    except CompileError as e:
        return CompileResult(ok=False, error=str(e))
    except Exception as e:
        return CompileResult(ok=False, error=f"编译内部错误: {e}")
