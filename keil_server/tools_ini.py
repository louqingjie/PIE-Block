# -*- coding: utf-8 -*-
"""Keil TOOLS.INI 的解析与修复。

TOOLS.INI 是 Keil 的全局配置文件，位于 Keil 安装根目录，形如 INI：
    [ARM]
    PATH="C:\\Keil_v5\\ARM\\"
    LIC0=WHY9H-...        <- MDK 许可证
    [C251]
    PATH="C:\\Keil_v5\\C251\\"
    LIC0=76NXV-...        <- C251 许可证

注意两点（踩过坑）：
  - [ARM] 段也有 LIC0，读/写必须限定在 [C251] 段内，否则会误读/误写 ARM 密钥
  - 文件是 CRLF，且路径可能含非 ASCII（中文用户名）。按行编辑必须字节保真，
    这里用 latin-1 读写（字节 <-> 字符一一对应），避免 UTF-8 读写损坏内容
"""
from __future__ import annotations

from pathlib import Path


def _load_lines(ini_path: Path) -> list[str]:
    return ini_path.read_bytes().decode("latin-1").split("\n")


def _save_lines(ini_path: Path, lines: list[str]) -> None:
    ini_path.parent.mkdir(parents=True, exist_ok=True)
    ini_path.write_bytes(("\n".join(lines)).encode("latin-1"))


def _iter_section_ranges(lines: list[str]):
    """遍历所有 [段]，产出 (段名大写, 段内容起始行, 段内容结束行(不含))。"""
    section: str | None = None
    start = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if section is not None:
                yield section, start, i
            section = stripped[1:-1].strip().upper()
            start = i + 1
    if section is not None:
        yield section, start, len(lines)


def read_key(ini_path: Path, section: str, key: str) -> str:
    """读取指定段内某 key 的值；段或 key 不存在返回空串。"""
    if not ini_path.exists():
        return ""
    lines = _load_lines(ini_path)
    section = section.upper()
    prefix = key.upper() + "="
    for name, s, e in _iter_section_ranges(lines):
        if name == section:
            for line in lines[s:e]:
                st = line.strip()
                if st.upper().startswith(prefix):
                    value = st[len(prefix):].strip()
                    # PATH="C:\...\" 这类带引号的值，剥掉首尾引号
                    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
                        value = value[1:-1]
                    return value
            return ""
    return ""


def write_key(ini_path: Path, section: str, key: str, value: str = "") -> bool:
    """把 key=value 写入指定段；没有该 key 则插入段首。

    段不存在时在文件末尾追加整个段。返回 True 表示发生了写入。
    """
    expected = "%s=%s" % (key, value)
    if not ini_path.exists():
        ini_path.parent.mkdir(parents=True, exist_ok=True)
        ini_path.write_bytes(("[%s]\r\n%s\r\n" % (section, expected)).encode("latin-1"))
        return True
    lines = _load_lines(ini_path)
    section = section.upper()
    prefix = key.upper() + "="
    target: tuple[int, int] | None = None
    for name, s, e in _iter_section_ranges(lines):
        if name == section:
            target = (s, e)
            break
    if target is None:
        lines.append("[%s]" % section)
        lines.append(expected)
        _save_lines(ini_path, lines)
        return True
    start, end = target
    for i in range(start, end):
        if lines[i].strip().upper().startswith(prefix):
            if lines[i].strip() == expected:
                return False
            lines[i] = expected
            _save_lines(ini_path, lines)
            return True
    lines.insert(start, expected)
    _save_lines(ini_path, lines)
    return True


def ensure_c251_path(ini_path: Path, c251_dir_abs: str) -> bool:
    """确保 [C251] 段的 PATH= 指向 c251_dir_abs（反斜杠绝对路径，末尾带 \\）。

    Keil 的 PATH 必须带引号且用反斜杠（正斜杠会导致 "failed to execute
    C251.EXE"）。返回 True 表示发生了写入。
    """
    expected = 'PATH="%s"' % c251_dir_abs
    if not ini_path.exists():
        ini_path.parent.mkdir(parents=True, exist_ok=True)
        ini_path.write_bytes(("[C251]\r\n%s\r\nVERSION=5.60\r\n" % expected).encode("latin-1"))
        return True
    lines = _load_lines(ini_path)
    target: tuple[int, int] | None = None
    for name, s, e in _iter_section_ranges(lines):
        if name == "C251":
            target = (s, e)
            break
    if target is None:
        lines.append("[C251]")
        lines.append(expected)
        lines.append("VERSION=5.60")
        _save_lines(ini_path, lines)
        return True
    start, end = target
    for i in range(start, end):
        if lines[i].strip().upper().startswith("PATH="):
            if lines[i].strip() == expected:
                return False
            lines[i] = expected
            _save_lines(ini_path, lines)
            return True
    lines.insert(start, expected)
    _save_lines(ini_path, lines)
    return True
