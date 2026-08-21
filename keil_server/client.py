# -*- coding: utf-8 -*-
r"""keil_server 云端编译客户端（命令行 + 可导入库）。

把「生成 main.c → 打包自包含工程 zip → 上传编译服务 → 轮询 → 下载 hex」做成
一个可复用的客户端。编译逻辑全部在服务器端（keil_server），本机不需要装 Keil。

用法（命令行）：
    python -m keil_server.client health [--server URL]
    python -m keil_server.client build --kind infantry --config cfg.json \
        [--server URL] [--out-hex out.hex] [--timeout 120] [--quiet]
    python -m keil_server.client build --project x.pieproj ...
    python -m keil_server.client build --code main.c ...

库函数：
    from keil_server.client import build_remote, health

环境变量：
    PIEBLOCK_KEIL_SERVER_URL   默认服务器地址（命令行 --server 优先）
    PIEBLOCK_GODOT             生成 main.c 需要的 Godot 可执行文件
    PIEBLOCK_PYTHON            （可选）CLI 侧调用本客户端的 python 解释器

输出 JSON 与本地 CLI build 对齐：
    {"ok": bool, "exit": 0/1, "kind": str, "log": str, "hex": str, "hex_exists": bool}
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import httpx

from keil_server.config import PROJECT_ROOT

# ------------------------------------------------------------------ 常量
# 构型 -> 打包用的工程模板目录（debug / music 复用步兵模板，与 cli_codegen 一致）
PROJECT_DIRS = {
    "infantry": "ROBOMASTER_INFANTRY",
    "engineer": "ROBOMASTER_ENGINEER",
    "debug": "ROBOMASTER_INFANTRY",
    "music": "ROBOMASTER_INFANTRY",
}
DEFAULT_SERVER = "http://127.0.0.1:8000"
POLL_INTERVAL = 1.0


def server_url(override: str = "") -> str:
    """解析服务器地址：显式 > PIEBLOCK_KEIL_SERVER_URL > 默认本地。"""
    if override and override.strip():
        return override.strip().rstrip("/")
    env = os.environ.get("PIEBLOCK_KEIL_SERVER_URL", "").strip()
    return env.rstrip("/") if env else DEFAULT_SERVER


def api_key(override: str = "") -> str:
    """解析 API Key：显式 > 环境变量 PIEBLOCK_KEIL_API_KEY。空串表示不鉴权。"""
    if override and override.strip():
        return override.strip()
    return os.environ.get("PIEBLOCK_KEIL_API_KEY", "").strip()


def _auth_headers(key: str) -> dict:
    """设置 API Key 时返回 Bearer 请求头，否则空。"""
    return {"Authorization": "Bearer " + key} if key else {}


# ------------------------------------------------------------------ HTTP 封装
def health(server: str = "", timeout: float = 10.0, api_key_override: str = "") -> dict:
    """探测编译服务健康状态。"""
    url = server_url(server)
    key = api_key(api_key_override)
    try:
        r = httpx.get(f"{url}/health", timeout=timeout, headers=_auth_headers(key))
        r.raise_for_status()
        data = r.json()
        data["_server"] = url
        return data
    except httpx.HTTPError as e:
        return {"status": "unreachable", "_server": url, "error": str(e)}


def submit_compile(
    server: str, zip_path: Path, timeout: int | None = None, api_key_override: str = "",
) -> str:
    """上传 zip，返回 task_id。"""
    url = server_url(server)
    key = api_key(api_key_override)
    files = {"file": ("project.zip", zip_path.read_bytes(), "application/zip")}
    params = {"timeout": timeout} if timeout else None
    r = httpx.post(
        f"{url}/compile", files=files, params=params,
        timeout=120.0, headers=_auth_headers(key),
    )
    r.raise_for_status()
    return r.json()["task_id"]


def wait_task(
    server: str, task_id: str,
    poll: float = POLL_INTERVAL, timeout: float = 600.0, api_key_override: str = "",
) -> dict:
    """轮询任务直到 success/failed。"""
    url = server_url(server)
    key = api_key(api_key_override)
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = httpx.get(
            f"{url}/tasks/{task_id}", timeout=30.0, headers=_auth_headers(key),
        )
        r.raise_for_status()
        data = r.json()
        if data["status"] in ("success", "failed"):
            return data
        time.sleep(poll)
    return {"status": "timeout", "task_id": task_id, "error": f"轮询超时（>{timeout}s）"}


def get_task_log(server: str, task_id: str, api_key_override: str = "") -> str:
    url = server_url(server)
    key = api_key(api_key_override)
    r = httpx.get(
        f"{url}/tasks/{task_id}/log", timeout=60.0, headers=_auth_headers(key),
    )
    if r.status_code == 200:
        return r.text
    return "（无法获取日志: HTTP %s）" % r.status_code


def download_hex(
    server: str, task_id: str, out_path: Path, api_key_override: str = "",
) -> Path:
    """下载 hex 到 out_path，返回写入的路径。"""
    url = server_url(server)
    key = api_key(api_key_override)
    r = httpx.get(
        f"{url}/tasks/{task_id}/hex", timeout=120.0, headers=_auth_headers(key),
    )
    r.raise_for_status()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(r.content)
    return out_path


def delete_task(server: str, task_id: str, api_key_override: str = "") -> None:
    url = server_url(server)
    key = api_key(api_key_override)
    try:
        httpx.delete(
            f"{url}/tasks/{task_id}", timeout=30.0, headers=_auth_headers(key),
        )
    except httpx.HTTPError:
        pass


# ------------------------------------------------------------------ main.c 生成
def find_godot() -> str:
    """定位 Godot（生成 main.c 用），同 make_fixture。"""
    env = os.environ.get("PIEBLOCK_GODOT", "").strip()
    if env and Path(env).exists():
        return env
    p = shutil.which("godot")
    if p:
        return p
    raise FileNotFoundError(
        "找不到 godot。请设置 PIEBLOCK_GODOT 指向 godot 可执行文件，或让它出现在 PATH 中"
    )


def _run_cli_generate(args: list[str], out_path: Path) -> None:
    """调 Godot CLI 的 generate 子命令，把 main.c 写到 out_path。"""
    godot = find_godot()
    cli = PROJECT_ROOT / "scripts" / "cli_codegen.gd"
    cmd = [
        godot, "--headless", "--no-header", "--path", str(PROJECT_ROOT),
        "--script", str(cli), "--",
        "generate",
    ] + args + ["--out", str(out_path)]
    proc = subprocess.run(
        cmd, capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=180,
    )
    if not out_path.exists():
        raise RuntimeError(
            f"代码生成失败（退出码 {proc.returncode}）: {(proc.stderr or '')[:500]}"
        )


def generate_main_c(
    kind: str, out_path: Path,
    config_path: str | None = None,
    config_text: str | None = None,
    project_path: str | None = None,
) -> None:
    """按输入类型生成 main.c 到 out_path（不编译）。"""
    tmp: str | None = None
    try:
        if config_text is not None:
            fd, tmp = tempfile.mkstemp(suffix=".json", prefix="pieblock_cfg_")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(json.loads(config_text), f, ensure_ascii=False, indent=2)
            args = ["--kind", kind, "--config", tmp]
        elif config_path is not None:
            args = ["--kind", kind, "--config", config_path]
        elif project_path is not None:
            args = ["--project", project_path]
        else:
            raise ValueError("需要 --config / --config-text / --project 之一")
        _run_cli_generate(args, out_path)
    finally:
        if tmp:
            try:
                os.remove(tmp)
            except OSError:
                pass


# ------------------------------------------------------------------ 打包
def build_fixture_zip(
    kind: str, out_path: Path, main_c_path: Path | None = None,
) -> Path:
    """把工程模板 + main.c 打成自包含 zip（复用 make_fixture）。

    kind 直接传给 make_fixture（infantry/engineer/debug/music），由它内部映射模板目录。
    """
    from keil_server.make_fixture import build_fixture

    return build_fixture(
        project=kind,
        out_path=out_path,
        main_c_path=main_c_path,
        use_codegen=False,           # main.c 由本客户端生成，避免重复生成
        include_libraries=True,
    )


# ------------------------------------------------------------------ 云端编译主流程
def build_remote(
    kind: str = "infantry",
    server: str = "",
    config_path: str | None = None,
    config_text: str | None = None,
    project_path: str | None = None,
    code_path: str | None = None,
    timeout: int = 120,
    out_hex: Path | None = None,
    keep_task: bool = True,
    api_key_override: str = "",
) -> dict:
    """生成 main.c → 打包 → 上传云端编译 → 下载 hex。

    返回与本地 CLI build 对齐的字典：
        {"ok", "exit", "kind", "log", "hex", "hex_exists", "task_id", "summary"}
    """
    if kind not in PROJECT_DIRS:
        return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                "hex_exists": False, "error": f"未知构型: {kind}"}

    url = server_url(server)
    # 0) 健康检查（快速失败）
    h = health(url, api_key_override=api_key_override)
    if not h.get("keil", {}).get("available"):
        return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                "hex_exists": False,
                "error": f"编译服务不可用（{url}）: {h.get('error') or h.get('reason') or h.get('keil', {}).get('reason', '未知')}"}

    tmpdir = Path(tempfile.mkdtemp(prefix="pieblock_remote_"))
    try:
        # 1) 确定 main.c
        main_c: Path | None = None
        if code_path is not None:
            main_c = Path(code_path)
            if not main_c.exists():
                return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                        "hex_exists": False, "error": f"代码文件不存在: {main_c}"}
        else:
            main_c = tmpdir / "main.c"
            try:
                generate_main_c(
                    kind, main_c,
                    config_path=config_path,
                    config_text=config_text,
                    project_path=project_path,
                )
            except (RuntimeError, ValueError, FileNotFoundError) as e:
                return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                        "hex_exists": False, "error": str(e)}
        if main_c.stat().st_size == 0:
            return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                    "hex_exists": False, "error": "生成的 main.c 为空（配置可能不完整）"}

        # 2) 打包自包含 zip
        zip_path = tmpdir / "project.zip"
        try:
            build_fixture_zip(kind, zip_path, main_c)
        except (FileNotFoundError, ValueError) as e:
            return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                    "hex_exists": False, "error": f"打包失败: {e}"}

        # 3) 上传
        try:
            task_id = submit_compile(
                url, zip_path, timeout, api_key_override=api_key_override,
            )
        except httpx.HTTPError as e:
            return {"ok": False, "exit": 1, "kind": kind, "log": "", "hex": "",
                    "hex_exists": False, "error": f"上传失败: {e}"}

        # 4) 轮询
        task = wait_task(
            url, task_id, timeout=timeout + 180.0, api_key_override=api_key_override,
        )
        status = task.get("status")
        if status == "success":
            hex_path = tmpdir / "firmware.hex"
            try:
                download_hex(
                    url, task_id, hex_path, api_key_override=api_key_override,
                )
            except httpx.HTTPError as e:
                return {"ok": False, "exit": 1, "kind": kind, "log": "",
                        "hex": "", "hex_exists": False,
                        "error": f"hex 下载失败: {e}", "task_id": task_id}
            if out_hex is not None:
                shutil.copyfile(hex_path, out_hex)
                out = Path(out_hex)
            else:
                out = hex_path
            return {
                "ok": True, "exit": 0, "kind": kind,
                "log": get_task_log(url, task_id, api_key_override=api_key_override),
                "hex": str(out), "hex_exists": True,
                "task_id": task_id, "summary": task.get("summary", {}),
            }
        # 失败 / 超时
        return {
            "ok": False, "exit": 1, "kind": kind,
            "log": get_task_log(url, task_id, api_key_override=api_key_override),
            "hex": "", "hex_exists": False,
            "error": task.get("error", f"任务状态: {status}"),
            "task_id": task_id,
        }
    finally:
        if not keep_task:
            # keep_task=False 时保留 hex 输出目录（可能被引用），否则清理
            pass
        try:
            shutil.rmtree(tmpdir, ignore_errors=True)
        except OSError:
            pass


# ------------------------------------------------------------------ 命令行
def _cmd_health(args: argparse.Namespace) -> int:
    data = health(args.server, api_key_override=args.api_key)
    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0 if data.get("status") == "ok" and data.get("keil", {}).get("available") else 1


def _cmd_build(args: argparse.Namespace) -> int:
    out_hex = Path(args.out_hex) if args.out_hex else None
    result = build_remote(
        kind=args.kind,
        server=args.server,
        config_path=args.config,
        config_text=args.config_text,
        project_path=args.project,
        code_path=args.code,
        timeout=args.timeout,
        out_hex=out_hex,
        api_key_override=args.api_key,
    )
    if args.quiet:
        # 只输出精简结果，便于被脚本/MCP 消费
        slim = {k: result.get(k) for k in ("ok", "exit", "kind", "hex", "hex_exists", "error", "task_id")}
        print(json.dumps(slim, ensure_ascii=False))
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok") else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="keil_server.client", description=__doc__)
    parser.add_argument("--server", default="",
                        help=f"编译服务地址（默认 {DEFAULT_SERVER}）")
    sub = parser.add_subparsers(dest="cmd", required=True)

    h = sub.add_parser("health", help="探测编译服务健康状态")
    h.add_argument("--server", default="", help="编译服务地址")
    h.add_argument("--api-key", default="", help="API Key（或设 PIEBLOCK_KEIL_API_KEY）")

    b = sub.add_parser("build", help="云端编译为 hex")
    b.add_argument("--server", default="", help="编译服务地址")
    b.add_argument("--api-key", default="", help="API Key（或设 PIEBLOCK_KEIL_API_KEY）")
    b.add_argument("--kind", choices=list(PROJECT_DIRS), default="infantry")
    b.add_argument("--config", default=None, help="配置 JSON 文件路径")
    b.add_argument("--config-text", default=None, help="配置 JSON 字符串")
    b.add_argument("--project", default=None, help=".pieproj 项目文件路径")
    b.add_argument("--code", default=None, help="已有 main.c 文件路径")
    b.add_argument("--out-hex", default=None, help="hex 输出路径（默认写到临时目录）")
    b.add_argument("--timeout", type=int, default=120, help="编译超时（秒，5~600）")
    b.add_argument("--quiet", action="store_true", help="只输出精简 JSON")

    args = parser.parse_args(argv)
    if args.cmd == "health":
        return _cmd_health(args)
    if args.cmd == "build":
        return _cmd_build(args)
    parser.error("未知命令")
    return 2


if __name__ == "__main__":
    sys.exit(main())
