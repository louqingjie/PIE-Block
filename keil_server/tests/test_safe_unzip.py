# -*- coding: utf-8 -*-
"""safe_unzip 单元测试：zip-slip / zip bomb / 正常解压。"""
from __future__ import annotations

import zipfile
from pathlib import Path

import pytest

from keil_server.safe_unzip import UnzipError, safe_extract

LIMITS = dict(max_total_size=1024 * 1024, max_files=100, max_file_size=256 * 1024)


def _make_zip(tmp_path: Path, entries: dict[str, bytes]) -> Path:
    p = tmp_path / "in.zip"
    with zipfile.ZipFile(p, "w") as zf:
        for name, data in entries.items():
            zf.writestr(name, data)
    return p


def test_normal_extract(tmp_path):
    z = _make_zip(tmp_path, {"a/b.txt": b"hello", "a/c.txt": b"world"})
    dest = tmp_path / "out"
    n = safe_extract(z, dest, **LIMITS)
    assert n == 2
    assert (dest / "a" / "b.txt").read_bytes() == b"hello"
    assert (dest / "a" / "c.txt").read_bytes() == b"world"


def test_zip_slip_traversal(tmp_path):
    z = _make_zip(tmp_path, {"../../evil.txt": b"boom"})
    dest = tmp_path / "out"
    with pytest.raises(UnzipError):
        safe_extract(z, dest, **LIMITS)
    assert not (tmp_path / "evil.txt").exists()


def test_zip_slip_absolute(tmp_path):
    z = _make_zip(tmp_path, {"/abs/evil.txt": b"boom"})
    with pytest.raises(UnzipError):
        safe_extract(z, tmp_path / "out", **LIMITS)


def test_backslash_name(tmp_path):
    # Windows 打包工具常用反斜杠分隔
    z = _make_zip(tmp_path, {r"a\b.txt": b"hi"})
    dest = tmp_path / "out"
    n = safe_extract(z, dest, **LIMITS)
    assert n == 1
    assert (dest / "a" / "b.txt").read_bytes() == b"hi"


def test_zip_bomb_total(tmp_path):
    z = _make_zip(tmp_path, {"big.txt": b"x" * (1024 * 1024 + 1)})
    with pytest.raises(UnzipError):
        safe_extract(z, tmp_path / "out",
                     max_total_size=1024 * 1024, max_files=100, max_file_size=256 * 1024)


def test_zip_bomb_single_file(tmp_path):
    # 单文件超过单文件上限（即使总量够）
    z = _make_zip(tmp_path, {"big.txt": b"x" * (300 * 1024)})
    with pytest.raises(UnzipError):
        safe_extract(z, tmp_path / "out",
                     max_total_size=10 * 1024 * 1024, max_files=100, max_file_size=256 * 1024)


def test_too_many_files(tmp_path):
    z = _make_zip(tmp_path, {f"f{i}.txt": b"x" for i in range(10)})
    with pytest.raises(UnzipError):
        safe_extract(z, tmp_path / "out",
                     max_total_size=1024 * 1024, max_files=5, max_file_size=1024)
