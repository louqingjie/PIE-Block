#!/usr/bin/env bash
# 安装 PIE-Block 主控板的 udev 规则，让普通用户（活动登录会话）可以直接
# 访问 hidraw 设备，无需 root 运行应用。
# 用法: tools/install_udev_rules.sh
# 在仓库或解压后的发布包里均可运行；重复执行幂等。
set -euo pipefail

rules_name="70-pieblock-hid.rules"
candidates=(
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/linux/udev/$rules_name"
  "$(pwd)/linux/udev/$rules_name"
  "$(pwd)/$rules_name"
)
rules=""
for candidate in "${candidates[@]}"; do
  if [ -f "$candidate" ]; then
    rules="$candidate"
    break
  fi
done
if [ -z "$rules" ]; then
  echo "未找到 $rules_name（请在仓库根目录或解压后的发布包目录运行）。" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "需要 root 权限写 /etc/udev/rules.d，将使用 sudo 重新执行。"
  exec sudo "$0"
fi

install -m 644 "$rules" "/etc/udev/rules.d/$rules_name"
command -v udevadm >/dev/null 2>&1 || {
  echo "未找到 udevadm（非 systemd 环境？）。规则已复制，请手动重载 udev。" >&2
  exit 0
}
udevadm control --reload
udevadm trigger --subsystem-match=hidraw
echo "[PASS] udev 规则已安装：/etc/udev/rules.d/$rules_name"
echo "如果主控板已插在 USB 上，请拔出后重新插入（或重新上电进 ISP）再检测。"
