# -*- coding: utf-8 -*-
"""编译提交限速：每用户每分钟 N 次、每日 M 次。

每日计数持久化到 JSON（可选 file_path）：重启后单日配额与用量统计不丢失。
60 秒滑动窗口仅存内存（重启后分钟级窗口清零，可接受）。
线程安全；按用户标识（admin / 用户名 / open）分别计数。
"""
from __future__ import annotations

import json
import os
import tempfile
import threading
import time
from collections import deque
from pathlib import Path


class RateLimiter:
    def __init__(
        self, per_minute: int = 10, per_day: int = 100,
        file_path: str | Path | None = None,
    ) -> None:
        self.per_minute = per_minute
        self.per_day = per_day
        self._file = Path(file_path) if file_path else None
        self._lock = threading.Lock()
        # user -> 最近提交时间戳队列（仅保留 60s 窗口内，内存态）
        self._recent: dict[str, deque] = {}
        # user -> {日期: 当日次数}（持久化）
        self._daily: dict[str, dict[str, int]] = {}
        if self._file is not None:
            self._load()

    # -- 持久化 -------------------------------------------------------------
    def _load(self) -> None:
        try:
            data = json.loads(self._file.read_text(encoding="utf-8"))
            self._daily = {
                str(u): {str(d): int(c) for d, c in days.items()}
                for u, days in data.get("daily", {}).items()
            }
        except (OSError, ValueError):
            self._daily = {}

    def _save(self) -> None:
        if self._file is None:
            return
        try:
            self._file.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(
                suffix=".tmp", prefix="usage_",
                dir=str(self._file.parent),
            )
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump({"daily": self._daily}, f, ensure_ascii=False)
                os.replace(tmp, self._file)
            except BaseException:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                raise
        except OSError:
            pass

    # -- 检查与记账 ----------------------------------------------------------
    def check(self, user: str) -> tuple[bool, str]:
        """检查并记账一次提交。返回 (allowed, 拒绝原因)。

        允许时记入窗口与当日计数并落盘；拒绝时不记账。
        """
        now = time.time()
        today = time.strftime("%Y-%m-%d")
        with self._lock:
            dq = self._recent.setdefault(user, deque())
            while dq and now - dq[0] >= 60.0:
                dq.popleft()
            if len(dq) >= self.per_minute:
                wait = max(1, int(60.0 - (now - dq[0])) + 1)
                return False, f"每分钟最多 {self.per_minute} 次编译，请约 {wait} 秒后重试"
            days = self._daily.setdefault(user, {})
            cnt = days.get(today, 0)
            if cnt >= self.per_day:
                return False, (
                    f"单日最多 {self.per_day} 次编译（今日已用 {cnt} 次），"
                    f"请明天再试或联系管理员"
                )
            dq.append(now)
            days[today] = cnt + 1
            self._save()
            return True, ""

    # -- 查询 -----------------------------------------------------------------
    def usage(self) -> dict:
        """用户用量统计：按日明细 + 今日/累计/近 7 天汇总。"""
        today = time.strftime("%Y-%m-%d")
        recent_days = [
            time.strftime("%Y-%m-%d", time.localtime(time.time() - 86400 * d))
            for d in range(7, -1, -1)
        ]
        with self._lock:
            users = {}
            for u, days in sorted(self._daily.items()):
                total = sum(days.values())
                last7 = {d: days.get(d, 0) for d in recent_days}
                users[u] = {
                    "today": days.get(today, 0),
                    "total": total,
                    "last7": last7,
                }
            return {"users": users}

    def stats(self) -> dict:
        """当前限速状态快照（调试用）。"""
        with self._lock:
            return {
                "per_minute": self.per_minute,
                "per_day": self.per_day,
                "users": {
                    u: {
                        "last_60s": len(dq),
                        "today": sum(self._daily.get(u, {}).values()),
                    }
                    for u, dq in self._recent.items()
                },
            }
