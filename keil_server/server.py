# -*- coding: utf-8 -*-
"""云端 Keil C251 编译服务（FastAPI）。

用法（从项目根或任意位置）：
    python -m keil_server.server            # 开发（127.0.0.1:8000）
    uvicorn keil_server.server:app --host 0.0.0.0 --port 8000

接口：
    GET    /health                 服务与 Keil 安装探测
    POST   /compile                上传 zip，提交编译任务（multipart: file）
    GET    /tasks                  任务列表
    GET    /tasks/{id}             任务状态
    GET    /tasks/{id}/log         完整编译日志
    GET    /tasks/{id}/hex         下载 hex 固件
    DELETE /tasks/{id}             清理任务
"""
from __future__ import annotations

import base64
import os
import sys
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi import Body, Depends, FastAPI, File, Header, HTTPException, Query, Security, UploadFile
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from keil_server import config, keil_detect, keys as keys_store
from keil_server.task_manager import TaskManager


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # 启动时把 KEIL_API_KEYS 种子固化到 data/api_keys.json，
    # 保证 -ApiKeys 给的初始用户立即可用（而不是等第一次查询才写入）。
    try:
        keys_store.load_keys()
    except Exception:
        pass
    yield


app = FastAPI(
    title="Keil C251 Cloud Compiler",
    description="上传 Keil 工程 zip，服务端用安装的 Keil C251 编译并返回 HEX 固件。",
    version="0.3.0",
    lifespan=lifespan,
)

task_manager = TaskManager()

# Bearer 安全方案：让 /docs 显示 Authorize 按钮（实际校验见 require_api_key）
bearer = HTTPBearer(auto_error=False)


# ------------------------------------------------------------------ 鉴权
# 多用户 API Key：
#   - 管理员主 key：环境变量 KEIL_API_KEY（永远有效，管理接口用它）
#   - 普通用户 key：data/api_keys.json（或 KEIL_API_KEYS 初始注入），每个用户一把
# 支持 Authorization: Bearer <key> 或 X-API-Key: <key> 两种请求头。
# 未配置任何 key 时保持开放模式（本机/内网用）。
def require_api_key(
    creds: HTTPAuthorizationCredentials | None = Security(bearer),
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> str:
    """鉴权并返回用户标识：admin / 用户名 / open（开放模式）。

    用 Security(bearer) 让 /docs 显示 Authorize 按钮；实际校验在本函数完成。
    """
    if not config.API_KEY and not keys_store.load_keys():
        return "open"
    token = (creds.credentials if creds else "").strip()
    if not token and x_api_key:
        token = x_api_key.strip()
    if not token:
        raise HTTPException(status_code=401, detail="缺失 API Key")
    if config.API_KEY and token == config.API_KEY:
        return "admin"
    user = keys_store.resolve(token)
    if user is None:
        raise HTTPException(status_code=401, detail="无效或已吊销的 API Key")
    return user


def require_admin(
    creds: HTTPAuthorizationCredentials | None = Security(bearer),
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> None:
    """管理接口专用：只认管理员主 key（KEIL_API_KEY）。"""
    if not config.API_KEY:
        raise HTTPException(status_code=503, detail="未配置管理员 key（KEIL_API_KEY）")
    token = (creds.credentials if creds else "").strip()
    if not token and x_api_key:
        token = x_api_key.strip()
    if token != config.API_KEY:
        raise HTTPException(status_code=401, detail="需要管理员 API Key")


# ------------------------------------------------------------------ 用户 key 管理（仅管理员）
@app.get("/keys")
def list_api_keys(_: None = Depends(require_admin)):
    return {"users": keys_store.list_users()}


@app.post("/keys")
def add_api_key(payload: dict = Body(...), _: None = Depends(require_admin)):
    user = str(payload.get("user", "")).strip()
    if not user:
        raise HTTPException(status_code=400, detail="缺少 user 字段")
    key = keys_store.add_user(user, payload.get("key") or None)
    return {"user": user, "key": key, "note": "把 key 分发给该用户；吊销用 DELETE /keys/{user}"}


@app.delete("/keys/{user}")
def revoke_api_key(user: str, _: None = Depends(require_admin)):
    n = keys_store.revoke_user(user)
    if n == 0:
        raise HTTPException(status_code=404, detail=f"用户 {user} 没有可用 key")
    return {"revoked": user, "count": n}


@app.get("/health")
def health():
    info = keil_detect.detect()
    return {
        "status": "ok",
        "keil": keil_detect.info_dict(info),
        "config": {
            "max_concurrent_builds": config.MAX_CONCURRENT_BUILDS,
            "build_timeout": config.BUILD_TIMEOUT,
            "upload_max_size": config.UPLOAD_MAX_SIZE,
            "task_ttl": config.TASK_TTL,
        },
    }


@app.post("/compile")
async def compile_zip(
    file: UploadFile = File(...),
    timeout: int | None = Query(
        default=None, ge=5, le=600, description="覆盖默认编译超时（秒）"
    ),
    user: str = Depends(require_api_key),
):
    if file.filename is None or not file.filename.lower().endswith(".zip"):
        raise HTTPException(status_code=400, detail="只接受 .zip 文件")
    # 流式落盘，避免整个上传占内存；同时做大小校验
    fd, tmp = tempfile.mkstemp(suffix=".zip", prefix="keil_upload_")
    total = 0
    try:
        with os.fdopen(fd, "wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > config.UPLOAD_MAX_SIZE:
                    raise HTTPException(
                        status_code=413,
                        detail=f"上传超过大小上限 {config.UPLOAD_MAX_SIZE} 字节",
                    )
                out.write(chunk)
        if total == 0:
            raise HTTPException(status_code=400, detail="上传内容为空")
        task_id = await task_manager.submit(Path(tmp), timeout, user=user)
    finally:
        tmp_path = Path(tmp)
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass
    return {"task_id": task_id, "status": "queued"}


@app.post("/compile_base64")
async def compile_zip_base64(
    payload: dict = Body(...),
    user: str = Depends(require_api_key),
):
    """接收 base64 编码的 zip（Godot 端 HTTPClient 的 request body 是 String，
    无法直接发二进制，故用 base64）。与 /compile 等效。
    body: {"zip_base64": "...", "timeout": 120?}
    """
    zip_b64 = str(payload.get("zip_base64", ""))
    if not zip_b64:
        raise HTTPException(status_code=400, detail="缺少 zip_base64 字段")
    try:
        data = base64.b64decode(zip_b64)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"zip_base64 不是合法 base64: {e}")
    if not data:
        raise HTTPException(status_code=400, detail="zip_base64 解码为空")
    if len(data) > config.UPLOAD_MAX_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"数据超过大小上限 {config.UPLOAD_MAX_SIZE} 字节",
        )
    timeout = payload.get("timeout")
    if timeout is not None:
        try:
            timeout = int(timeout)
            if not (5 <= timeout <= 600):
                raise ValueError
        except (TypeError, ValueError):
            timeout = None
    fd, tmp = tempfile.mkstemp(suffix=".zip", prefix="keil_upload_b64_")
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
        task_id = await task_manager.submit(Path(tmp), timeout, user=user)
    finally:
        tmp_path = Path(tmp)
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass
    return {"task_id": task_id, "status": "queued"}


@app.get("/tasks")
def list_tasks(limit: int = Query(default=50, ge=1, le=200), _user: str = Depends(require_api_key)):
    return {"tasks": [t.to_public() for t in task_manager.list(limit)]}


@app.get("/tasks/{task_id}")
def get_task(task_id: str, _user: str = Depends(require_api_key)):
    task = task_manager.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return task.to_public()


@app.get("/tasks/{task_id}/log")
def get_task_log(task_id: str, _user: str = Depends(require_api_key)):
    task = task_manager.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return PlainTextResponse(task.log or "（无日志）")


@app.get("/tasks/{task_id}/hex")
def get_task_hex(task_id: str, _user: str = Depends(require_api_key)):
    task = task_manager.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    if task.status != "success" or not task.hex_path:
        raise HTTPException(
            status_code=409,
            detail="任务未成功或没有可用的 hex 产物（status=%s）" % task.status,
        )
    hex_path = Path(task.hex_path)
    if not hex_path.exists():
        raise HTTPException(status_code=410, detail="hex 产物已被清理")
    return FileResponse(
        hex_path,
        filename="%s.hex" % task_id,
        media_type="application/octet-stream",
    )


@app.delete("/tasks/{task_id}")
def delete_task(task_id: str, _user: str = Depends(require_api_key)):
    if not task_manager.delete(task_id):
        raise HTTPException(status_code=404, detail="任务不存在")
    return {"deleted": task_id}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=os.environ.get("KEIL_SERVER_HOST", "127.0.0.1"),
        port=int(os.environ.get("KEIL_SERVER_PORT", "8000")),
    )
