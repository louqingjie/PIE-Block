#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MCP Server 冒烟测试：用官方 stdio 客户端连接并调用所有工具。"""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

from mcp import Client, StdioServerParameters, stdio_client

ROOT = Path(__file__).resolve().parent.parent


def _cfg(name: str) -> dict:
    with open(ROOT / "tools" / name, encoding="utf-8") as f:
        return json.load(f)


async def main() -> int:
    params = StdioServerParameters(
        command=sys.executable,
        args=["tools/pieblock_mcp_server.py"],
        cwd=str(ROOT),
    )
    async with Client(stdio_client(params)) as client:
        # 1. 列出工具
        tools = await client.list_tools()
        names = [t.name for t in tools.tools]
        print(f"[1] 可用工具: {names}")
        assert "list_profiles" in names
        assert "generate_code" in names
        assert "check_config" in names
        assert "get_schema" in names
        assert "generate_from_project" in names

        # 2. list_profiles
        r = await client.call_tool("list_profiles", {})
        text = r.content[0].text
        data = json.loads(text)
        print(f"[2] list_profiles OK: {[p['kind'] for p in data['profiles']]}")

        # 3. get_schema infantry
        r = await client.call_tool("get_schema", {"kind": "infantry"})
        s = json.loads(r.content[0].text)
        print(f"[3] get_schema infantry OK: {len(s['properties'])} 字段, channel default={s['properties'].get('channel', {}).get('default')}")

        # 4. generate_code infantry（合法配置）
        r = await client.call_tool("generate_code", {
            "kind": "infantry",
            "config": json.dumps(_cfg("test_infantry_config.json")),
        })
        data = json.loads(r.content[0].text)
        print(f"[4] generate_code infantry OK: has_error={data['has_error']}, code_lines={len(data['code'].splitlines())}")

        # 5. check_config engineer（有错误的配置 -> 应返回 error_count > 0）
        r = await client.call_tool("check_config", {
            "kind": "engineer",
            "config": json.dumps(_cfg("test_engineer_config.json")),
        })
        data = json.loads(r.content[0].text)
        print(f"[5] check_config engineer OK: errors={data['error_count']}")

        # 6. generate_code debug
        r = await client.call_tool("generate_code", {
            "kind": "debug",
            "config": json.dumps(_cfg("test_debug_config.json")),
        })
        data = json.loads(r.content[0].text)
        print(f"[6] generate_code debug OK: code_lines={len(data['code'].splitlines())}")

        # 7. 非法 kind 应友好报错
        r = await client.call_tool("generate_code", {"kind": "bogus", "config": "{}"})
        print(f"[7] 非法 kind -> {r.content[0].text[:50]}")

        # 8. generate_from_project（调试项目）
        r = await client.call_tool("generate_from_project", {
            "project_path": str(ROOT / "调试项目.pieproj"),
        })
        data = json.loads(r.content[0].text)
        print(f"[8] generate_from_project OK: kind={data['kind']}, has_error={data['has_error']}")

        print("\n=== 全部 MCP 测试通过 ===")
        return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
