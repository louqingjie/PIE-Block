# -*- coding: utf-8 -*-
"""多用户 API Key 管理。

每个用户一个 key，存 JSON 文件（默认 data/api_keys.json）：
    {
      "<key>": {"user": "alice", "created_at": 169..., "enabled": true},
      ...
    }

管理员主 key 用环境变量 KEIL_API_KEY（见 config），不在此表。

用法（命令行）：
    python -m keil_server.keys list                 # 列出所有用户与 key
    python -m keil_server.keys add alice            # 新增用户，自动生成 key
    python -m keil_server.keys add bob mykey123     # 指定 key
    python -m keil_server.keys remove alice         # 吊销该用户全部 key

环境变量：
    KEIL_API_KEYS       初始用户（user:key,user:key），读取时并入文件
    KEIL_API_KEYS_FILE  自定义 key 表路径（默认 keil_server/data/api_keys.json）
"""
from __future__ import annotations

import json
import secrets
import time
from pathlib import Path

from keil_server import config


def _default_path() -> Path:
    return config.KEYS_FILE


def load_keys() -> dict:
    """读取全部用户 key。

    规则（保证"吊销真正生效"）：
      - **文件优先**：key 表文件存在时以文件为准（运行时增删都写文件）。
      - **CSV 仅作首次种子**：文件不存在时，KEIL_API_KEYS（user:key,user:key）
        作为初始用户写入文件固化；之后增删以文件为准，CSV 不再覆盖。
    """
    path = _default_path()
    if path.exists():
        try:
            file_data = json.loads(path.read_text(encoding="utf-8"))
            data: dict = {}
            for k, v in file_data.items():
                if isinstance(v, dict) and v.get("user"):
                    data[k] = {
                        "user": v["user"],
                        "created_at": v.get("created_at", time.time()),
                        "enabled": bool(v.get("enabled", True)),
                    }
            return data
        except Exception:
            pass
    # 无文件：用 CSV 种子初始化（写入文件固化）
    data: dict = {}
    if config.API_KEYS_CSV:
        for pair in config.API_KEYS_CSV.split(","):
            pair = pair.strip()
            if not pair or ":" not in pair:
                continue
            user, key = pair.split(":", 1)
            user, key = user.strip(), key.strip()
            if user and key:
                data.setdefault(key, {
                    "user": user, "created_at": time.time(), "enabled": True,
                })
        if data:
            try:
                save_keys(data)
            except OSError:
                pass
    return data


def save_keys(data: dict) -> None:
    path = _default_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def generate_key() -> str:
    return secrets.token_urlsafe(24)


def add_user(user: str, key: str | None = None) -> str:
    """新增用户，返回其 key（未指定则自动生成）。同一用户可有多把 key。"""
    user = user.strip()
    if not user:
        raise ValueError("用户名为空")
    data = load_keys()
    key = (key or "").strip() or generate_key()
    data[key] = {"user": user, "created_at": time.time(), "enabled": True}
    save_keys(data)
    return key


def revoke_user(user: str) -> int:
    """吊销某用户全部 key，返回吊销条数。"""
    data = load_keys()
    to_del = [k for k, v in data.items() if v.get("user") == user]
    for k in to_del:
        data.pop(k, None)
    if to_del:
        save_keys(data)
    return len(to_del)


def list_users() -> list[dict]:
    """按用户聚合返回：{user, key_count, keys}。"""
    data = load_keys()
    by_user: dict[str, dict] = {}
    for k, v in data.items():
        u = v.get("user", "?")
        entry = by_user.setdefault(u, {"user": u, "key_count": 0, "keys": []})
        entry["key_count"] += 1
        entry["keys"].append({
            "key": k,
            "created_at": v.get("created_at"),
            "enabled": bool(v.get("enabled", True)),
        })
    return sorted(by_user.values(), key=lambda e: e["user"])


def resolve(token: str) -> str | None:
    """给定 token，返回其用户；无效/已吊销返回 None。管理员 key 不在此表。"""
    if not token:
        return None
    rec = load_keys().get(token)
    if rec and rec.get("enabled", True):
        return rec["user"]
    return None


def main() -> None:
    import argparse
    import sys

    parser = argparse.ArgumentParser(prog="keil_server.keys", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="列出所有用户与 key")
    a = sub.add_parser("add", help="新增用户")
    a.add_argument("user")
    a.add_argument("key", nargs="?", default=None, help="可选，指定 key")
    r = sub.add_parser("remove", help="吊销用户全部 key")
    r.add_argument("user")

    args = parser.parse_args()
    if args.cmd == "list":
        users = list_users()
        if not users:
            print("（暂无用户 key）")
        for u in users:
            print("%s: %d key(s)" % (u["user"], u["key_count"]))
            for k in u["keys"]:
                print("    %s %s" % ("OK " if k["enabled"] else "OFF", k["key"]))
    elif args.cmd == "add":
        key = add_user(args.user, args.key)
        print("新增用户 %s，key=%s" % (args.user, key))
    elif args.cmd == "remove":
        n = revoke_user(args.user)
        print("吊销用户 %s 的 %d 个 key" % (args.user, n))
    sys.exit(0)


if __name__ == "__main__":
    main()
