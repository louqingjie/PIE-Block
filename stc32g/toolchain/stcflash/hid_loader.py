#!/usr/bin/env python3
"""hid_loader.py - 确保 hidapi 原生库可被 ctypes 加载（Windows）。

`hid` Python 包用 ctypes.cdll.LoadLibrary('hidapi.dll') 按裸名加载，
Windows 上"安全 DLL 搜索"不一定能找到 exe 目录，导致 ImportError:
    Unable to load any of the following libraries: ... hidapi.dll ...

本模块在 `import hid` 之前调用 ensure_hidapi_available()，
用 os.add_dll_directory()（Python 3.8+）把候选目录加入进程 DLL 搜索路径，
并把 PATH 也补上作为兜底。

候选目录：
  1. sys.executable 所在目录（.venv\\Scripts，hidapi.dll 通常放这里）
  2. 本文件所在目录（stcflash/）
"""
import os
import sys


def _candidate_dirs():
    dirs = []
    exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    if exe_dir:
        dirs.append(exe_dir)
    this_dir = os.path.dirname(os.path.abspath(__file__))
    if this_dir:
        dirs.append(this_dir)
    # 去重保序
    seen = set()
    out = []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def ensure_hidapi_available():
    if os.name != "nt":
        # Linux/macOS 通过系统库/udev 处理，无需 add_dll_directory
        return
    for d in _candidate_dirs():
        dll = os.path.join(d, "hidapi.dll")
        if os.path.isfile(dll):
            try:
                os.add_dll_directory(d)
            except Exception:  # noqa: BLE001
                pass
            # 兜底：把目录加进 PATH，让 LoadLibrary 最后一步能找到
            path = os.environ.get("PATH", "")
            if d not in path:
                os.environ["PATH"] = d + os.pathsep + path
            return
