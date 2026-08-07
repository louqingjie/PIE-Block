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

import os
import sys
import tempfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, PlainTextResponse

from keil_server import config, keil_detect
from keil_server.task_manager import TaskManager

app = FastAPI(
    title="Keil C251 Cloud Compiler",
    description="上传 Keil 工程 zip，服务端用安装的 Keil C251 编译并返回 HEX 固件。",
    version="0.2.0",
)

task_manager = TaskManager()


# ------------------------------------------------------------------ 鉴权
# 设了 config.API_KEY（环境变量 KEIL_API_KEY）后，除 /health 外的接口都要校验。
# 支持 Authorization: Bearer <key> 或 X-API-Key: <key> 两种请求头。
# 未设置 API_KEY 时保持开放模式（本机/内网用）。
def require_api_key(
    authorization: str | None = Header(default=None),
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> None:
    if not config.API_KEY:
        return
    token = ""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    elif x_api_key:
        token = x_api_key.strip()
    if token and token == config.API_KEY:
        return
    raise HTTPException(status_code=401, detail="无效或缺失 API Key")


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
    _key: None = Depends(require_api_key),
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
        task_id = await task_manager.submit(Path(tmp), timeout)
    finally:
        tmp_path = Path(tmp)
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass
    return {"task_id": task_id, "status": "queued"}


@app.get("/tasks")
def list_tasks(limit: int = Query(default=50, ge=1, le=200), _key: None = Depends(require_api_key)):
    return {"tasks": [t.to_public() for t in task_manager.list(limit)]}


@app.get("/tasks/{task_id}")
def get_task(task_id: str, _key: None = Depends(require_api_key)):
    task = task_manager.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return task.to_public()


@app.get("/tasks/{task_id}/log")
def get_task_log(task_id: str, _key: None = Depends(require_api_key)):
    task = task_manager.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return PlainTextResponse(task.log or "（无日志）")


@app.get("/tasks/{task_id}/hex")
def get_task_hex(task_id: str, _key: None = Depends(require_api_key)):
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
def delete_task(task_id: str, _key: None = Depends(require_api_key)):
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
