# -*- coding: utf-8 -*-
"""RateLimiter 单元测试。"""
import time

from keil_server.rate_limit import RateLimiter


def test_per_minute_limit():
    rl = RateLimiter(per_minute=3, per_day=100)
    for _ in range(3):
        ok, reason = rl.check("alice")
        assert ok
    ok, reason = rl.check("alice")
    assert not ok
    assert "每分钟最多 3 次" in reason


def test_per_day_limit():
    rl = RateLimiter(per_minute=100, per_day=2)
    assert rl.check("bob")[0]
    assert rl.check("bob")[0]
    ok, reason = rl.check("bob")
    assert not ok
    assert "单日最多 2 次" in reason


def test_users_isolated():
    rl = RateLimiter(per_minute=1, per_day=100)
    assert rl.check("alice")[0]
    assert rl.check("alice")[0] is False
    assert rl.check("bob")[0]


def test_window_expires():
    rl = RateLimiter(per_minute=1, per_day=100)
    assert rl.check("alice")[0]
    assert rl.check("alice")[0] is False
    rl._recent["alice"][0] -= 61  # 时间往前拨 61 秒
    assert rl.check("alice")[0]


def test_persistence_roundtrip(tmp_path):
    f = tmp_path / "usage.json"
    rl = RateLimiter(per_minute=100, per_day=5, file_path=f)
    assert rl.check("alice")[0]
    assert rl.check("bob")[0]
    assert rl.check("bob")[0]
    assert f.exists()
    rl2 = RateLimiter(per_minute=100, per_day=5, file_path=f)
    assert rl2.check("alice")[0]          # 当日 1/5，允许
    assert rl2.check("bob")[0]            # 当日 3/5，允许
    for _ in range(2):
        assert rl2.check("bob")[0]
    assert rl2.check("bob")[0] is False   # 当日 5/5，拒绝


def test_usage_summary(tmp_path):
    f = tmp_path / "usage.json"
    rl = RateLimiter(per_minute=100, per_day=100, file_path=f)
    rl.check("alice")
    rl.check("alice")
    u = rl.usage()
    assert u["users"]["alice"]["today"] == 2
    assert u["users"]["alice"]["total"] == 2
    assert len(u["users"]["alice"]["last7"]) == 8
    # 模拟昨天的记录
    rl._daily["alice"]["2000-01-01"] = 7
    u = rl.usage()
    assert u["users"]["alice"]["total"] == 9
    assert "2000-01-01" not in u["users"]["alice"]["last7"]  # 不在近 7 天窗口
