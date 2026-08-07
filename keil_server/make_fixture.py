# -*- coding: utf-8 -*-
r"""把项目里现成的 Keil 工程打包成「自包含 zip」夹具，供测试与演示。

用法（从项目根）：
    python -m keil_server.make_fixture --project infantry
    python -m keil_server.make_fixture --project engineer --out out.zip
    python -m keil_server.make_fixture --project infantry --main-c my_main.c

zip 内保持与 uvproj 相对引用一致的目录结构：
    Projects/<ROBOMASTER_INFANTRY|ENGINEER>/...   （MDK/、USER/…）
    Libraries/...                                  （uvproj 用 ..\..\..\Libraries\ 引用）

main.c 来源（默认第一项）：
    1. --main-c <文件>   显式指定
    2. 代码生成器 CLI     用 tools/test_{kind}_config.json 生成当前版本 main.c
                          （仓库里模板的 main.c 是过期快照，isr.c 引用的 ISP 符号
                            它没定义，直接编译会 L127 链接失败 —— 别用它）
    3. --no-codegen      保留模板自带 main.c（仅调试用，通常编不过）

生成 main.c 需要 Godot 4.x：设置环境变量 PIEBLOCK_GODOT 指向可执行文件，
或让 godot 在 PATH 中。
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from keil_server.config import PROJECT_ROOT

PROJECT_DIRS = {
    "infantry": "ROBOMASTER_INFANTRY",
    "engineer": "ROBOMASTER_ENGINEER",
    # debug 复用步兵模板（与 scripts/cli_codegen.gd 的 _project_dst_for_kind 一致）
    "debug": "ROBOMASTER_INFANTRY",
}


def find_godot() -> str:
    """定位 Godot 4.x 可执行文件。优先 PIEBLOCK_GODOT，其次 PATH。"""
    env = os.environ.get("PIEBLOCK_GODOT", "").strip()
    if env and Path(env).exists():
        return env
    p = shutil.which("godot")
    if p:
        return p
    raise FileNotFoundError(
        "找不到 godot 可执行文件。请安装 Godot 4.x 并设置环境变量 "
        "PIEBLOCK_GODOT 指向 godot，或让它出现在 PATH 中。"
    )


def generate_main_c(kind: str, out_path: Path) -> None:
    """用项目代码生成器 CLI 生成当前版本的 main.c 到 out_path。"""
    godot = find_godot()
    cfg = PROJECT_ROOT / "tools" / f"test_{kind}_config.json"
    if not cfg.exists():
        raise FileNotFoundError(
            f"找不到默认配置: {cfg}，请改用 --main-c 显式传入 main.c"
        )
    cli = PROJECT_ROOT / "scripts" / "cli_codegen.gd"
    cmd = [
        godot, "--headless", "--no-header", "--path", str(PROJECT_ROOT),
        "--script", str(cli),
        "--", "generate", "--kind", kind, "--config", str(cfg), "--out", str(out_path),
    ]
    proc = subprocess.run(
        cmd, capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=120,
    )
    if not out_path.exists():
        raise RuntimeError(
            f"代码生成失败（退出码 {proc.returncode}）: {(proc.stderr or '')[:500]}"
        )


def build_fixture(
    project: str = "infantry",
    out_path: Path | None = None,
    main_c_path: Path | None = None,
    use_codegen: bool = True,
    include_libraries: bool = True,
) -> Path:
    """打包一个自包含工程 zip，返回 zip 路径。"""
    proj_dir = PROJECT_DIRS.get(project)
    if proj_dir is None:
        raise ValueError(f"未知项目类型: {project}（可选 {list(PROJECT_DIRS)}）")
    src_proj = PROJECT_ROOT / "stc32g" / "Projects" / proj_dir
    src_libs = PROJECT_ROOT / "stc32g" / "Libraries"
    if not src_proj.exists():
        raise FileNotFoundError(f"项目模板不存在: {src_proj}")

    if out_path is None:
        out_path = (
            Path(__file__).resolve().parent / "tests" / "fixtures" / f"{project}_fixture.zip"
        )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    # 确定 main.c 内容
    main_c_content: str | None = None
    if main_c_path is not None:
        main_c_content = Path(main_c_path).read_text(encoding="utf-8", errors="replace")
    elif use_codegen:
        fd, tmp_name = tempfile.mkstemp(suffix=".c", prefix="main_cgen_")
        os.close(fd)
        gen = Path(tmp_name)
        try:
            generate_main_c(project, gen)
            main_c_content = gen.read_text(encoding="utf-8", errors="replace")
        finally:
            try:
                gen.unlink()
            except OSError:
                pass

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
        main_arc = (Path("Projects") / proj_dir / "USER" / "src" / "main.c").as_posix()
        # 用生成/指定的 main.c 替换模板自带，打包时跳过同名条目避免重复
        _add_dir(zf, src_proj, Path("Projects") / proj_dir, skip_arc=main_arc)
        if include_libraries:
            if not src_libs.exists():
                raise FileNotFoundError(f"Libraries 不存在: {src_libs}")
            _add_dir(zf, src_libs, Path("Libraries"))
        if main_c_content is not None:
            zf.writestr(main_arc, main_c_content)
    return out_path


def _add_dir(
    zf: zipfile.ZipFile,
    src: Path,
    arc_prefix: Path,
    skip_arc: str | None = None,
) -> None:
    for p in sorted(src.rglob("*")):
        if p.is_file() and not p.name.startswith("."):
            arc = (arc_prefix / p.relative_to(src)).as_posix()
            if skip_arc is not None and arc == skip_arc:
                continue
            zf.write(p, arc)


def main() -> None:
    parser = argparse.ArgumentParser(description="生成自包含 Keil 工程测试 zip")
    parser.add_argument("--project", choices=list(PROJECT_DIRS), default="infantry")
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument(
        "--main-c", type=Path, default=None,
        help="显式指定 main.c 文件（默认用代码生成器 CLI 生成）",
    )
    parser.add_argument(
        "--no-codegen", action="store_true",
        help="不生成 main.c，保留模板自带（通常编不过，仅调试用）",
    )
    parser.add_argument(
        "--no-libraries", action="store_true",
        help="不打包 Libraries（需 zip 外挂载）",
    )
    args = parser.parse_args()
    path = build_fixture(
        project=args.project,
        out_path=args.out,
        main_c_path=args.main_c,
        use_codegen=not args.no_codegen,
        include_libraries=not args.no_libraries,
    )
    print("已生成夹具: %s (%.1f KB)" % (path, path.stat().st_size / 1024))


if __name__ == "__main__":
    main()
