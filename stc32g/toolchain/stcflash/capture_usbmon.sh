#!/usr/bin/env bash
# capture_usbmon.sh - 抓一次 usbmon 文本并跑一次「应用同链路」烧录，供 analyze_usbmon.py 分析。
#
#   stc32g/toolchain/stcflash/capture_usbmon.sh <firmware.hex> [输出文件]
#
# 需要 sudo（脚本内部调用，会提示你输密码）；抓包总线从 sysfs 自动识别，
# 找不到 34BF 设备时直接退出（先把主控板断电几秒重新上电进 ISP）。
#
# 抓完自动打印分析命令；也可以直接：
#   python3 analyze_usbmon.py <输出文件> --timeline
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"

if [ $# -lt 1 ]; then
  echo "用法: $0 <firmware.hex> [输出文件]" >&2
  exit 64
fi
hex="$(readlink -f "$1")"
out="${2:-/tmp/usbmon-$(date +%H%M%S).txt}"

bus=""
for vendor in /sys/bus/usb/devices/*/idVendor; do
  if [ "$(cat "$vendor" 2>/dev/null || true)" = "34bf" ]; then
    dev="$(basename "$(dirname "$vendor")")"
    bus="${dev%%-*}"
  fi
done
if [ -z "$bus" ]; then
  echo "总线上没有 34BF 设备：请先给主控板断电几秒后重新上电进入 ISP" >&2
  exit 2
fi

lib="$repo/build/linux/x64/debug/bundle/lib/libpieblock_hid.so"
if [ ! -f "$lib" ]; then
  echo "找不到 $lib：先跑一次 flutter build linux --release（或 flutter run -d linux）" >&2
  exit 3
fi

echo "抓包总线 ${bus}u → $out（最长 180 秒，烧完自动停）"
sudo sh -c "modprobe usbmon; exec timeout 180 cat /sys/kernel/debug/usb/usbmon/${bus}u > '$out'" &
capture=$!
sleep 1

set +e
(
  cd "$repo" &&
    PIEBLOCK_HID_DLL="$lib" dart run packages/pieblock_hid/tool/flash_hex.dart "$hex"
)
status=$?
set -e

sleep 1
sudo pkill -f "usbmon/${bus}u" 2>/dev/null || true
wait "$capture" 2>/dev/null || true

echo
echo "抓包结束（烧录退出码 $status）：$out"
echo "分析：python3 $here/analyze_usbmon.py $out --timeline"
exit "$status"
