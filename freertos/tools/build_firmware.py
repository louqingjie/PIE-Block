#!/usr/bin/env python3
"""用仓库内置 SDCC MCS-251 工具链构建 FreeRTOS STC32G12K128 演示固件。

用法（在 freertos/ 目录下）：
    python3 tools/build_firmware.py
    python3 tools/build_firmware.py --sdcc ../path/to/sdcc --lib-dir ../path/to/lib
    python3 tools/build_firmware.py --project freertos

构建流程与 stc32g_sdcc 保持一致：先扫描 __interrupt() 定义生成声明头并
--include 进 main 编译单元（SDCC 只在含 main 的单元生成中断向量表），然后
逐个编译、用 sdas251 汇编 portheap.asm、链接并做布局校验。
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "build_manifest.json"

INTERRUPT_PATTERN = re.compile(
    r"^\s*(?:static\s+)?void\s+([A-Za-z_]\w*)\s*\(\s*void\s*\)\s*"
    r"__interrupt\s*\(\s*([^)]*?)\s*\)",
    re.MULTILINE,
)


def fail(message: str) -> "None":
    print(f"错误: {message}", file=sys.stderr)
    raise SystemExit(1)


def resolve_binary(path: str, fallback_name: str) -> Path:
    candidate = Path(path)
    if candidate.is_file():
        return candidate.resolve()
    found = shutil.which(fallback_name)
    if found is not None:
        return Path(found).resolve()
    fail(f"找不到 {fallback_name}: {path}")


def run(command: list[str], what: str) -> None:
    result = subprocess.run(command)
    if result.returncode != 0:
        fail(f"{what}失败，退出码 {result.returncode}\n命令: {' '.join(command)}")


def write_interrupt_header(sources: list[Path], destination: Path) -> None:
    declarations: set[str] = set()
    for source in sources:
        text = source.read_text(encoding="utf-8", errors="replace")
        for match in INTERRUPT_PATTERN.finditer(text):
            name = match.group(1)
            vector = match.group(2).strip()
            declarations.add(f"void {name}(void) __interrupt ({vector});")
    lines = [
        "#ifndef FREERTOS_SDCC_INTERRUPT_DECLARATIONS_H",
        "#define FREERTOS_SDCC_INTERRUPT_DECLARATIONS_H",
        '#include "STC32Gxx.h"',
        "#include <stdlib.h>",
        *sorted(declarations),
        "#endif",
    ]
    destination.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=None, help="工程名，默认取 kind_projects.freertos")
    parser.add_argument("--sdcc", default=str(ROOT.parent / "vendor/sdcc-toolchain/bin/sdcc"),
                        help="sdcc 可执行文件路径")
    parser.add_argument("--lib-dir", default=None,
                        help="mcs251-large-stack-auto 运行库目录")
    parser.add_argument("--std-include", default=None, help="SDCC 标准头文件目录")
    parser.add_argument("--output", default=None, help="输出目录，默认 freertos/build/<工程名>")
    parser.add_argument("--all", action="store_true", help="构建清单里的全部工程")
    args = parser.parse_args()

    if not MANIFEST.is_file():
        fail(f"缺少构建清单: {MANIFEST}")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    sdcc = resolve_binary(args.sdcc, "sdcc")
    sdcc_dir = sdcc.parent
    assembler = resolve_binary(str(sdcc_dir / "sdas251"), "sdas251")

    lib_dir = Path(args.lib_dir).resolve() if args.lib_dir else (sdcc_dir.parent / "lib" / "mcs251-large-stack-auto").resolve()
    std_include = Path(args.std_include).resolve() if args.std_include else (sdcc_dir.parent / "include").resolve()
    if not lib_dir.is_dir():
        fail(f"运行库目录不存在: {lib_dir}")
    if not std_include.is_dir():
        fail(f"SDCC 标准头文件目录不存在: {std_include}")

    for library in manifest["runtime_libraries"]:
        if not (lib_dir / library).is_file():
            fail(f"缺少运行库: {lib_dir / library}")

    include_args: list[str] = [f"-I{std_include}", f"-I{std_include / 'mcs51'}"]
    for relative in manifest["include_dirs"]:
        directory = (ROOT / relative).resolve()
        if not directory.is_dir():
            fail(f"包含目录不存在: {directory}")
        include_args.append(f"-I{directory}")

    if args.all:
        project_names = sorted(manifest["projects"].keys())
    else:
        project_name = args.project or manifest.get("kind_projects", {}).get("freertos")
        if project_name is None:
            fail("未指定工程，且清单没有 kind_projects.freertos")
        if project_name not in manifest["projects"]:
            fail(f"构建清单缺少工程: {project_name}")
        project_names = [project_name]

    compile_flags = [str(flag) for flag in manifest["compile_flags"]]
    link_flags = [str(flag) for flag in manifest["link_flags"]]

    for project_name in project_names:
        spec = manifest["projects"][project_name]
        relative_sources: list[str] = [str(spec["main"])]
        for group in spec["source_groups"]:
            relative_sources.extend(str(item) for item in manifest["source_groups"][group])

        source_paths: list[Path] = []
        for relative in relative_sources:
            path = ROOT / relative
            if not path.is_file():
                fail(f"源文件缺失: {path}")
            source_paths.append(path)

        assemblies: list[Path] = []
        for relative in manifest.get("assemblies", []):
            path = ROOT / relative
            if not path.is_file():
                fail(f"汇编文件缺失: {path}")
            assemblies.append(path)

        output = Path(args.output).resolve() if args.output else (ROOT / "build" / project_name).resolve()
        output.mkdir(parents=True, exist_ok=True)

        interrupt_header = output / "generated_interrupt_declarations.h"
        scan_paths = [ROOT / relative for relative in spec.get("interrupt_scan", [])]
        for path in scan_paths:
            if not path.is_file():
                fail(f"中断扫描文件缺失: {path}")
        write_interrupt_header(scan_paths, interrupt_header)

        objects: list[Path] = []
        for source in source_paths:
            if source.name == "main.c":
                compile_extra = ["--include", str(interrupt_header)]
            else:
                compile_extra = []
            obj = output / (source.stem + ".rel")
            command = [str(sdcc), *compile_flags, *include_args, *compile_extra,
                       "-o", str(obj), str(source)]
            run(command, f"编译 {source.name}")
            objects.append(obj)

        for assembly in assemblies:
            obj = output / (assembly.stem + ".rel")
            # -l 生成 .lst：链接器会按 .rel 里记录的调试信息去打开它。
            run([str(assembler), "-l", "-o", str(obj), str(assembly)],
                f"汇编 {assembly.name}")
            objects.append(obj)

        hex_path = output / (project_name + ".hex")
        link_command = [str(sdcc), *link_flags, f"-L{output}", f"-L{lib_dir}",
                        *include_args, *[str(obj) for obj in objects],
                        *[str(lib) for lib in manifest["runtime_libraries"]],
                        "-o", str(hex_path)]
        run(link_command, f"链接 {project_name}")

        map_path = hex_path.with_suffix(".map")
        if not hex_path.is_file() or not map_path.is_file():
            fail(f"未生成完整 HEX/MAP: {hex_path}")

        run([sys.executable, str(ROOT / "tools" / "check_layout.py"),
             str(hex_path), "--map", str(map_path), "--manifest", str(MANIFEST)],
            f"布局校验 {project_name}")
        print(f"[PASS] {project_name} -> {hex_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
