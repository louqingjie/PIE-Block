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


def _first_json(text: str) -> dict:
    """build_* 工具会在 JSON 后追加一行提示文本，取第一个 `{` 到最后一个 `}` 之间的部分。"""
    start = text.index("{")
    end = text.rfind("}") + 1
    return json.loads(text[start:end])


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
        assert "build_code" in names
        assert "build_project" in names

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

        # 9. build_code infantry（编译为 hex 固件）
        r = await client.call_tool("build_code", {
            "kind": "infantry",
            "config": json.dumps(_cfg("test_infantry_config.json")),
        })
        data = _first_json(r.content[0].text)
        print(f"[9] build_code OK: ok={data['ok']}, exit={data['exit']}, hex_exists={data['hex_exists']}")
        assert data["ok"], "编译应当成功（0 Error(s)）"
        assert data["hex_exists"], "应当生成 hex 固件"

        # 10. build_project（从 .pieproj 编译）
        r = await client.call_tool("build_project", {
            "project_path": str(ROOT / "调试项目.pieproj"),
        })
        data = _first_json(r.content[0].text)
        print(f"[10] build_project OK: ok={data['ok']}, kind={data['kind']}, hex_exists={data['hex_exists']}")

        # 11. channel 参数：显式传入应填入/覆盖 config 的 channel
        import re
        base = _cfg("test_infantry_config.json")
        base.pop("channel", None)  # 去掉 channel，看参数能否填入
        r = await client.call_tool("generate_code", {
            "kind": "infantry",
            "config": json.dumps(base),
            "channel": "55",
        })
        data = _first_json(r.content[0].text)  # has_error 时会追加提示文本，须取首个 JSON
        m = re.search(r"Channal\s*=\s*(\d+)", data["code"])
        assert m and m.group(1) == "55", f"channel 参数未生效: {m.group(1) if m else '未找到'}"
        assert not data["has_error"], "channel=55 填入后不应再有通道号 Error"
        print(f"[11] channel 参数 OK: channel=55 -> Channal = {m.group(1)}, has_error={data['has_error']}")

        print("\n=== 全部 MCP 测试通过 ===")
        return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
