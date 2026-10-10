#!/usr/bin/env bash
# 运行 FreeRTOS SDCC 端口的契约测试。
#
# 测试内容：
#   test_port_frame.py         工具链生成的中断序言/尾声与端口帧逐项对齐
#   test_sources_sdcc_only.py  源码里不再有 Keil 专有构造
#   test_manifest_layout.py    清单/配置的 edata 与堆预算自洽
#
# test_port_frame.py 需要 sdcc（默认取 vendor/sdcc-toolchain）；找不到时跳过。

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

exec python3 -m unittest discover -s tests -p 'test_*.py' -v
