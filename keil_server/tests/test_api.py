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


def test_auth_enforced_when_key_set(client, monkeypatch, tmp_path):
    """设置 KEIL_API_KEY 后，除 /health 外必须带正确 key；否则 401。"""
    from keil_server import config

    monkeypatch.setattr(config, "API_KEY", "secret123")
    monkeypatch.setattr(config, "API_KEYS_CSV", "")
    monkeypatch.setattr(config, "KEYS_FILE", tmp_path / "keys.json")
    # 无 key -> 401
    assert client.get("/tasks").status_code == 401
    # 错误 key -> 401
    assert client.get("/tasks", headers={"Authorization": "Bearer wrong"}).status_code == 401
    # 正确 Bearer key -> 200
    assert client.get("/tasks", headers={"Authorization": "Bearer secret123"}).status_code == 200
    # X-API-Key 头同样生效
    assert client.get("/tasks", headers={"X-API-Key": "secret123"}).status_code == 200
    # /health 保持开放（存活探测）
    assert client.get("/health").status_code == 200
    # 未设置任何 key 时开放模式
    monkeypatch.setattr(config, "API_KEY", "")
    assert client.get("/tasks").status_code == 200


def test_multi_user_keys(client, monkeypatch, tmp_path):
    """每个用户一把 key；管理员可增删；吊销后即失效（CSV 不覆盖文件）。"""
    from keil_server import config

    monkeypatch.setattr(config, "API_KEY", "admin-secret")
    monkeypatch.setattr(config, "API_KEYS_CSV", "alice:key-alice,bob:key-bob")
    monkeypatch.setattr(config, "KEYS_FILE", tmp_path / "keys.json")

    H = "Authorization"

    # 无 key / 陌生 key -> 401
    assert client.get("/tasks").status_code == 401
    assert client.get("/tasks", headers={H: "Bearer key-eve"}).status_code == 401
    # 各用户 key 都有效；管理员 key 也有效
    assert client.get("/tasks", headers={H: "Bearer key-alice"}).status_code == 200
    assert client.get("/tasks", headers={H: "Bearer key-bob"}).status_code == 200
    assert client.get("/tasks", headers={H: "Bearer admin-secret"}).status_code == 200

    # 管理接口需管理员 key
    assert client.get("/keys").status_code == 401
    assert client.get("/keys", headers={H: "Bearer key-alice"}).status_code == 401
    r = client.get("/keys", headers={H: "Bearer admin-secret"})
    assert r.status_code == 200
    users = {u["user"] for u in r.json()["users"]}
    assert {"alice", "bob"} <= users

    # 管理员新增用户（自动生成 key）
    r = client.post("/keys", json={"user": "carol"}, headers={H: "Bearer admin-secret"})
    assert r.status_code == 200
    carol_key = r.json()["key"]
    assert carol_key
    assert client.get("/tasks", headers={H: "Bearer " + carol_key}).status_code == 200

    # 管理员吊销 alice（CSV 种子已固化到文件，吊销真正生效）
    r = client.delete("/keys/alice", headers={H: "Bearer admin-secret"})
    assert r.status_code == 200
    assert client.get("/tasks", headers={H: "Bearer key-alice"}).status_code == 401
    # bob 与 carol 不受影响
    assert client.get("/tasks", headers={H: "Bearer key-bob"}).status_code == 200
    assert client.get("/tasks", headers={H: "Bearer " + carol_key}).status_code == 200

    # 编译任务带 user 归属
    with open(tmp_path / "dummy.zip", "wb") as f:
        f.write(b"not a zip")
    r = client.post(
        "/compile",
        files={"file": ("proj.zip", open(tmp_path / "dummy.zip", "rb"), "application/zip")},
        headers={H: "Bearer key-bob"},
    )
    # 非法 zip 也会生成任务并失败，但 user 应记录为 bob
    assert r.status_code == 200
    task_id = r.json()["task_id"]
    r = client.get(f"/tasks/{task_id}", headers={H: "Bearer admin-secret"})
    assert r.status_code == 200
    assert r.json()["user"] == "bob"
