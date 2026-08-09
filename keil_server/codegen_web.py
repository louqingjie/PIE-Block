# -*- coding: utf-8 -*-
"""代码生成器 Web 页面与接口（主站 pieblock.asia）。

架构：浏览器填参数 -> 本服务调 Godot headless 跑 scripts/cli_codegen.gd
生成 main.c；「生成并编译」则打包工程 zip 走既有编译流水线返回 hex。

接口：
    GET  /                       主站首页（HTML）
    GET  /codegen/profiles       构型列表
    GET  /codegen/schema         配置 JSON Schema（?kind=）
    POST /codegen/generate       {kind, config} -> {ok, code, issues}
    POST /codegen/build          {kind, config} -> {task_id}（生成并提交编译）
    GET  /codegen/task/{id}      任务状态（页面轮询用）
    GET  /codegen/hex/{id}       hex 下载

godot 调用带全局锁串行化（headless CLI 共享 .godot 导入缓存，不宜并发）。
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import tempfile
from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, Response

from keil_server import config, task_manager
from keil_server.make_fixture import build_fixture
from keil_server.rate_limit import RateLimiter

GODOT_EXE = os.environ.get(
    "PIEBLOCK_GODOT",
    r"C:\godot\Godot_v4.4-stable_win64_console.exe",
)
CLI_SCRIPT = config.PROJECT_ROOT / "scripts" / "cli_codegen.gd"
WEB_HTML = Path(__file__).resolve().parent / "web" / "index.html"

# 网页侧开放模式限速（无 key，防滥用）：与普通用户同配额
_web_limiter = RateLimiter(per_minute=30, per_day=500)
_godot_lock = asyncio.Lock()

router = APIRouter(tags=["codegen"])


def _extract_json(stdout: str) -> dict:
    """stdout 里可能混有 Godot 启动日志，取第一个 { 到最后一个 }。"""
    start = stdout.find("{")
    end = stdout.rfind("}")
    if start < 0 or end <= start:
        raise HTTPException(status_code=500, detail="代码生成器输出异常（无 JSON）")
    return json.loads(stdout[start:end + 1])


def _run_godot_sync(args: list[str], input_text: str | None = None,
                    timeout: int = 180) -> dict:
    cmd = [
        GODOT_EXE, "--headless", "--no-header",
        "--path", str(config.PROJECT_ROOT),
        "--script", str(CLI_SCRIPT), "--",
    ] + args
    try:
        p = subprocess.run(
            cmd, input=input_text, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="代码生成器执行超时")
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail=f"找不到 Godot：{GODOT_EXE}")
    stdout = (p.stdout or "") + (p.stderr or "")
    try:
        return _extract_json(stdout)
    except ValueError as e:
        raise HTTPException(status_code=500, detail=f"代码生成器输出解析失败: {e}")


async def _run_godot(args: list[str], input_text: str | None = None,
                     timeout: int = 180) -> dict:
    async with _godot_lock:
        return await asyncio.to_thread(_run_godot_sync, args, input_text, timeout)


@router.get("/")
async def index() -> Response:
    if not WEB_HTML.exists():
        raise HTTPException(status_code=500, detail="缺少前端页面文件")
    return FileResponse(WEB_HTML, media_type="text/html; charset=utf-8")


@router.get("/codegen/profiles")
async def profiles():
    return await _run_godot(["profiles"])


@router.get("/codegen/schema")
async def schema(kind: str = Query(default="infantry")):
    return await _run_godot(["schema", "--kind", kind])


async def _generate_code(kind: str, cfg: dict) -> tuple[str, list]:
    """调 godot 生成 main.c，返回 (代码, 检查问题列表)。"""
    fd, tmp = tempfile.mkstemp(suffix=".c", prefix="codegen_web_")
    os.close(fd)
    out = Path(tmp)
    try:
        result = await _run_godot(
            ["generate", "--kind", kind, "--config", "-", "--out", str(out)],
            input_text=json.dumps(cfg, ensure_ascii=False),
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"生成失败: {e}")
    if not result.get("ok"):
        issues = result.get("issues", [])
        detail = "；".join(
            f"{i.get('type', '')} {i.get('field', '')}: {i.get('message', '')}"
            for i in issues[:5]
        ) or result.get("error", "生成失败")
        raise HTTPException(status_code=400, detail=detail)
    code = out.read_text(encoding="utf-8", errors="replace")
    return code, result.get("issues", [])


@router.post("/codegen/generate")
async def generate(payload: dict):
    kind = str(payload.get("kind", "infantry"))
    cfg = payload.get("config")
    if not isinstance(cfg, dict):
        raise HTTPException(status_code=400, detail="config 必须是 JSON 对象")
    allowed, reason = _web_limiter.check("web")
    if not allowed:
        raise HTTPException(status_code=429, detail=reason)
    code, issues = await _generate_code(kind, cfg)
    return {"ok": True, "code": code, "issues": issues}


@router.post("/codegen/build")
async def codegen_build(payload: dict):
    kind = str(payload.get("kind", "infantry"))
    cfg = payload.get("config")
    if not isinstance(cfg, dict):
        raise HTTPException(status_code=400, detail="config 必须是 JSON 对象")
    allowed, reason = _web_limiter.check("web")
    if not allowed:
        raise HTTPException(status_code=429, detail=reason)
    code, _issues = await _generate_code(kind, cfg)

    fd, tmp = tempfile.mkstemp(suffix=".c", prefix="codegen_web_")
    os.close(fd)
    tmp_path = Path(tmp)
    try:
        tmp_path.write_text(code, encoding="utf-8")
        zip_path = build_fixture(
            project=kind, out_path=None, main_c_path=tmp_path,
            use_codegen=False, include_libraries=True,
        )
        task_id = await task_manager.task_manager.submit(
            zip_path, timeout=None, user="web",
        )
    finally:
        try:
            tmp_path.unlink()
        except OSError:
            pass
    return {"task_id": task_id, "status": "queued"}


@router.get("/codegen/task/{task_id}")
async def codegen_task(task_id: str):
    tm = task_manager.task_manager
    task = tm.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return {
        "task_id": task.task_id,
        "status": task.status,
        "error": task.error,
        "hex_size": task.hex_size,
        "summary": task.summary,
        "license_restricted": task.license_restricted,
    }


@router.get("/codegen/hex/{task_id}")
async def codegen_hex(task_id: str):
    tm = task_manager.task_manager
    task = tm.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    if task.status != "success" or not task.hex_path:
        raise HTTPException(status_code=409, detail="任务未成功，没有 hex")
    hex_path = Path(task.hex_path)
    if not hex_path.exists():
        raise HTTPException(status_code=410, detail="hex 已被清理")
    return FileResponse(
        hex_path, filename=f"{task_id}.hex",
        media_type="application/octet-stream",
    )
