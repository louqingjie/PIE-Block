#!/usr/bin/env bash
# 用仓库内置 SDCC MCS-251 工具链构建 FreeRTOS STC32G12K128 演示固件。
#
# 用法:
#   ./build.sh
#   ./build.sh --project FREERTOS_DEMO
#   ./build.sh --sdcc /path/to/sdcc --lib-dir /path/to/mcs251-large-stack-auto
#
# 可通过 SDCC / SDCC_LIB_DIR / SDCC_INCLUDE_DIR 环境变量覆盖工具链路径，
# 与 tools/prepare_sdcc_toolchain.sh 暂存的 vendor/sdcc-toolchain 保持一致。

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extra=()
if [ -n "${SDCC:-}" ]; then
  extra+=(--sdcc "$SDCC")
fi
if [ -n "${SDCC_LIB_DIR:-}" ]; then
  extra+=(--lib-dir "$SDCC_LIB_DIR")
fi
if [ -n "${SDCC_INCLUDE_DIR:-}" ]; then
  extra+=(--std-include "$SDCC_INCLUDE_DIR")
fi

exec python3 "$root/tools/build_firmware.py" "${extra[@]}" "$@"
