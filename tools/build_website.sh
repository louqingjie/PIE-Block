#!/usr/bin/env bash
# 构建官网里的 Flutter Web 版并 staging 到 website/app/。
# 用法: build_website.sh [--skip-build]
#
# 产物不进 git（.gitignore 里忽略 website/app/），发布流程是：
#   tools/build_website.sh && wrangler deploy
#
# 两个参数是刻意的：
#   --base-href /app/     官网只能托管 website/ 一个目录，应用放在它的子路径下，
#                         不带这个参数页面会去根路径找 main.dart.js 而 404。
#   --pwa-strategy=none   默认的 service worker 缓存很激进，网页版迭代时
#                         用户容易卡在旧版本上。
set -euo pipefail

skip_build=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-build) skip_build=1 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ "$skip_build" -eq 0 ]; then
  flutter build web --release --base-href /app/ --pwa-strategy=none
fi

source_dir="build/web"
target_dir="website/app"

if [ ! -f "$source_dir/main.dart.js" ]; then
  echo "构建产物不完整：$source_dir/main.dart.js 不存在，先不要用 --skip-build" >&2
  exit 1
fi

rm -rf -- "$target_dir"
mkdir -p "$target_dir"
cp -a "$source_dir/." "$target_dir/"

# *.symbols 只用于堆栈还原，运行时不会被请求；删掉能省约 8MB 磁盘。
find "$target_dir" -name "*.symbols" -delete

echo "[PASS] 网页版已就位: $target_dir ($(du -sh "$target_dir" | cut -f1))"
