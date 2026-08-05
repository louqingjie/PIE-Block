# -*- coding: utf-8 -*-
"""API 端到端测试（TestClient）。

需要真实 Keil；没有则跳过。测试产生的任务会在结束时清理。
"""
from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient

from keil_server import keil_detect


@pytest.fixture(scope="module")
def client():
    if not keil_detect.detect().available:
        pytest.skip("无可用 Keil C251，跳过 API 端到端测试")
    try:
        from keil_server.make_fixture import find_godot
        find_godot()
    except FileNotFoundError as e:
        pytest.skip(str(e))
    from keil_server.server import app

    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="module")
def fixture_zip(tmp_path_factory):
    from keil_server.make_fixture import build_fixture

    return build_fixture(
        project="infantry",
        out_path=tmp_path_factory.mktemp("api") / "infantry_fixture.zip",
    )


def _wait_done(client, task_id: str, timeout: float = 180.0) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = client.get(f"/tasks/{task_id}")
        assert r.status_code == 200
        data = r.json()
        if data["status"] in ("success", "failed"):
            return data
        time.sleep(0.5)
    raise TimeoutError(f"任务 {task_id} 轮询超时")


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert data["keil"]["available"] is True


def test_compile_end_to_end(client, fixture_zip):
    with open(fixture_zip, "rb") as f:
        r = client.post(
            "/compile",
            files={"file": ("proj.zip", f, "application/zip")},
        )
    assert r.status_code == 200
    task_id = r.json()["task_id"]
    assert task_id

    data = _wait_done(client, task_id)
    assert data["status"] == "success", data.get("error")

    # 下载 hex（Intel HEX 首行以冒号开头）
    r = client.get(f"/tasks/{task_id}/hex")
    assert r.status_code == 200
    assert r.content.startswith(b":")
    assert len(r.content) > 0

    # 完整日志
    r = client.get(f"/tasks/{task_id}/log")
    assert r.status_code == 200
    assert "0 Error(s)" in r.text

    # 清理后 404
    r = client.delete(f"/tasks/{task_id}")
    assert r.status_code == 200
    assert client.get(f"/tasks/{task_id}").status_code == 404


def test_compile_rejects_non_zip(client, tmp_path):
    f = tmp_path / "main.c"
    f.write_text("int main(){return 0;}")
    with open(f, "rb") as fh:
        r = client.post("/compile", files={"file": ("main.c", fh, "text/plain")})
    assert r.status_code == 400


def test_task_not_found(client):
    assert client.get("/tasks/does-not-exist").status_code == 404
