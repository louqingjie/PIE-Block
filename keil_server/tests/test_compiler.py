# -*- coding: utf-8 -*-
"""集成测试：用真实 Keil 编译夹具工程。

需要本机/服务器有可用的 Keil C251（完整正版或项目精简版均可）。
没有可用工具链时自动跳过，不影响其它测试。
"""
from __future__ import annotations

import zipfile
from pathlib import Path

import pytest

from keil_server import config, keil_detect
from keil_server.compiler import compile_dir, run_keil_build


@pytest.fixture(scope="module")
def keil_info():
    info = keil_detect.detect()
    if not info.available:
        pytest.skip(f"无可用 Keil C251: {info.reason}")
    return info


@pytest.fixture(scope="module")
def godot_ok():
    """夹具生成需要 Godot 跑代码生成器；没有则跳过。"""
    try:
        from keil_server.make_fixture import find_godot
        find_godot()
    except FileNotFoundError as e:
        pytest.skip(str(e))
    return True


@pytest.fixture(scope="module")
def extracted_work(tmp_path_factory, keil_info, godot_ok):
    """生成夹具 zip 并预先解压，编译测试直接复用，避免每次重复。"""
    from keil_server.make_fixture import build_fixture
    from keil_server.safe_unzip import safe_extract

    zip_path = build_fixture(
        project="infantry",
        out_path=tmp_path_factory.mktemp("zip") / "infantry_fixture.zip",
    )
    work = tmp_path_factory.mktemp("work")
    safe_extract(
        zip_path, work,
        config.EXTRACT_MAX_SIZE,
        config.EXTRACT_MAX_FILES,
        config.EXTRACT_MAX_FILE_SIZE,
    )
    return work


def test_compile_success(extracted_work):
    result = compile_dir(extracted_work, timeout=180)
    assert result.ok, result.error
    assert result.hex_path
    assert Path(result.hex_path).exists()
    assert Path(result.hex_path).stat().st_size > 0
    assert "0 Error(s)" in result.log
    assert result.summary.get("code", 0) > 0


def test_run_keil_build_full(tmp_path, keil_info, godot_ok):
    from keil_server.make_fixture import build_fixture

    zip_path = build_fixture(
        project="infantry",
        out_path=tmp_path / "f.zip",
    )
    work = tmp_path / "work"
    result = run_keil_build(zip_path, work, timeout=180)
    assert result.ok, result.error
    assert result.hex_path


def test_bad_zip_no_project(tmp_path, keil_info):
    bad = tmp_path / "bad.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("readme.txt", "not a keil project at all")
    work = tmp_path / "work2"
    result = run_keil_build(bad, work, timeout=30)
    assert not result.ok
    assert "uvproj" in result.error


def test_malicious_zip_rejected(tmp_path, keil_info):
    bad = tmp_path / "evil.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("../../escape.txt", "oops")
    work = tmp_path / "work3"
    result = run_keil_build(bad, work, timeout=30)
    assert not result.ok
    assert "解压失败" in result.error
    assert not (tmp_path / "escape.txt").exists()
