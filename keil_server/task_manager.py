# -*- coding: utf-8 -*-
"""编译任务管理：状态机、并发控制、持久化与 TTL 清理。

任务状态：
    queued -> building -> success | failed
服务重启时，未完成（queued/building）的任务标记为 failed（中断）。

任务目录结构（DATA_DIR/tasks/<id>/）：
    upload.zip   客户端上传的原始 zip
    work/        解压后的工程（编译在此进行）
    task.json    任务元数据（不含 log，重启恢复用）
    build.log    完整编译日志
"""
from __future__ import annotations

import asyncio
import json
import shutil
import time
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path

from keil_server import config
from keil_server.compiler import CompileResult, run_keil_build


@dataclass
class Task:
    task_id: str
    status: str = "queued"
    created_at: float = field(default_factory=time.time)
    started_at: float | None = None
    finished_at: float | None = None
    user: str = ""
    error: str = ""
    hex_path: str = ""
    hex_size: int = 0
    summary: dict = field(default_factory=dict)
    log: str = ""
    license_restricted: bool = False

    def to_public(self) -> dict:
        return {
            "task_id": self.task_id,
            "status": self.status,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "user": self.user,
            "error": self.error,
            "hex_size": self.hex_size,
            "summary": self.summary,
            "license_restricted": self.license_restricted,
            "has_log": bool(self.log),
            "has_hex": self.status == "success" and bool(self.hex_path),
        }


class TaskManager:
    def __init__(self) -> None:
        self._tasks: dict[str, Task] = {}
        self._sem: asyncio.Semaphore | None = None
        self._tasks_dir = config.DATA_DIR / "tasks"
        self._tasks_dir.mkdir(parents=True, exist_ok=True)
        self._load_persisted()

    # -- 并发信号量（惰性创建，绑定到运行中的事件循环） ---------------------
    def _semaphore(self) -> asyncio.Semaphore:
        if self._sem is None:
            self._sem = asyncio.Semaphore(config.MAX_CONCURRENT_BUILDS)
        return self._sem

    def task_dir(self, task_id: str) -> Path:
        return self._tasks_dir / task_id

    # -- 提交 --------------------------------------------------------------
    async def submit(
        self, zip_path: Path, timeout: int | None = None, user: str = "",
    ) -> str:
        """登记任务并把 zip 移入任务目录，后台异步编译。返回 task_id。"""
        self._purge_expired()
        task_id = uuid.uuid4().hex[:12]
        tdir = self.task_dir(task_id)
        tdir.mkdir(parents=True, exist_ok=True)
        dst = tdir / "upload.zip"
        shutil.move(str(zip_path), str(dst))
        task = Task(task_id=task_id, user=user)
        self._tasks[task_id] = task
        self._persist(task)
        asyncio.get_running_loop().create_task(
            self._run(task_id, dst, timeout)
        )
        return task_id

    async def _run(self, task_id: str, zip_path: Path, timeout: int | None) -> None:
        async with self._semaphore():
            task = self._tasks.get(task_id)
            if task is None:
                return
            task.status = "building"
            task.started_at = time.time()
            self._persist(task)

            work = self.task_dir(task_id) / "work"
            result = await asyncio.to_thread(
                run_keil_build,
                zip_path,
                work,
                timeout or config.BUILD_TIMEOUT,
            )
            self._finalize(task_id, result)

    def _finalize(self, task_id: str, result: CompileResult) -> None:
        task = self._tasks.get(task_id)
        if task is None:
            return
        task.status = "success" if result.ok else "failed"
        task.finished_at = time.time()
        task.error = result.error
        task.hex_path = result.hex_path
        task.hex_size = result.hex_size
        task.summary = result.summary
        task.log = result.log
        task.license_restricted = result.license_restricted
        self._persist(task)

    # -- 查询与删除 ----------------------------------------------------------
    def get(self, task_id: str) -> Task | None:
        return self._tasks.get(task_id)

    def list(self, limit: int = 50) -> list[Task]:
        ordered = sorted(self._tasks.values(), key=lambda t: t.created_at, reverse=True)
        return ordered[:limit]

    def delete(self, task_id: str) -> bool:
        task = self._tasks.pop(task_id, None)
        if task is None:
            return False
        tdir = self.task_dir(task_id)
        if tdir.exists():
            shutil.rmtree(tdir, ignore_errors=True)
        return True

    # -- 持久化（重启恢复） ----------------------------------------------------
    def _meta_path(self, task_id: str) -> Path:
        return self.task_dir(task_id) / "task.json"

    def _log_path(self, task_id: str) -> Path:
        return self.task_dir(task_id) / "build.log"

    def _persist(self, task: Task) -> None:
        try:
            data = asdict(task)
            log = data.pop("log", "")
            self._meta_path(task.task_id).write_text(
                json.dumps(data, ensure_ascii=False), encoding="utf-8"
            )
            if log:
                self._log_path(task.task_id).write_text(log, encoding="utf-8")
        except OSError:
            pass

    def _load_persisted(self) -> None:
        if not self._tasks_dir.exists():
            return
        for tdir in self._tasks_dir.iterdir():
            meta = tdir / "task.json"
            if not meta.exists():
                continue
            try:
                data = json.loads(meta.read_text(encoding="utf-8"))
                task = Task(**data)
            except Exception:
                continue
            if task.status in ("queued", "building"):
                task.status = "failed"
                task.error = "服务重启，任务中断"
                task.finished_at = time.time()
            log_path = tdir / "build.log"
            if log_path.exists():
                task.log = log_path.read_text(encoding="utf-8", errors="replace")
            self._tasks[task.task_id] = task

    # -- TTL 清理 -----------------------------------------------------------------
    def _purge_expired(self) -> None:
        now = time.time()
        for task_id, task in list(self._tasks.items()):
            if task.status in ("success", "failed", "cancelled"):
                finished = task.finished_at or task.created_at
                if now - finished > config.TASK_TTL:
                    self.delete(task_id)
