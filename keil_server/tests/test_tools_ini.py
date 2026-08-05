# -*- coding: utf-8 -*-
"""tools_ini 单元测试：段隔离读写、PATH 修复、CRLF 保真。"""
from __future__ import annotations

from keil_server.tools_ini import ensure_c251_path, read_key, write_key

INI = (
    "[ARM]\r\n"
    "PATH=\"C:\\Keil_v5\\ARM\\\"\r\n"
    "LIC0=ARMKEY-123\r\n"
    "\r\n"
    "[C251]\r\n"
    "PATH=\"C:\\Keil_v5\\C251\\\"\r\n"
    "LIC0=C251KEY-456\r\n"
    "\r\n"
)


def test_read_key_sections_isolated(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    ini.write_bytes(INI.encode("latin-1"))
    assert read_key(ini, "C251", "LIC0") == "C251KEY-456"
    assert read_key(ini, "ARM", "LIC0") == "ARMKEY-123"
    assert read_key(ini, "C251", "PATH") == "C:\\Keil_v5\\C251\\"


def test_read_key_missing(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    ini.write_bytes(INI.encode("latin-1"))
    assert read_key(ini, "C251", "NOPE") == ""
    assert read_key(ini, "C166", "LIC0") == ""


def test_read_key_no_file(tmp_path):
    assert read_key(tmp_path / "nope.ini", "C251", "LIC0") == ""


def test_ensure_c251_path_replaces_only_c251(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    ini.write_bytes(INI.encode("latin-1"))
    changed = ensure_c251_path(ini, "D:\\keil\\C251\\")
    assert changed is True
    text = ini.read_bytes().decode("latin-1")
    assert 'PATH="D:\\keil\\C251\\"' in text
    # [ARM] 段不受影响
    assert 'PATH="C:\\Keil_v5\\ARM\\"' in text
    assert read_key(ini, "ARM", "LIC0") == "ARMKEY-123"


def test_ensure_c251_path_idempotent(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    ini.write_bytes(INI.encode("latin-1"))
    assert ensure_c251_path(ini, "C:\\Keil_v5\\C251\\") is False
    assert ensure_c251_path(ini, "C:\\Keil_v5\\C251\\") is False


def test_ensure_c251_path_creates_section(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    ini.write_bytes("[ARM]\r\nPATH=\"C:\\ARM\\\"\r\n".encode("latin-1"))
    changed = ensure_c251_path(ini, "C:\\New\\C251\\")
    assert changed is True
    assert read_key(ini, "C251", "PATH") == "C:\\New\\C251\\"
    assert read_key(ini, "ARM", "PATH") == "C:\\ARM\\"


def test_write_key_creates_file(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    write_key(ini, "C251", "LIC0", "NEWKEY-1")
    assert read_key(ini, "C251", "LIC0") == "NEWKEY-1"


def test_crlf_preserved(tmp_path):
    ini = tmp_path / "TOOLS.INI"
    ini.write_bytes(INI.encode("latin-1"))
    ensure_c251_path(ini, "C:\\x\\C251\\")
    raw = ini.read_bytes()
    assert b"\r\n" in raw  # 仍保持 CRLF，而不是被转成 LF
