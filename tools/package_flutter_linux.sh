#!/usr/bin/env bash
# 打包面向 Linux x86_64 的自包含发布 tar.gz。
# 用法: package_flutter_linux.sh [--skip-build] [--output-base-name 名称]
# 产物: build/dist/PIEBlock-<版本>-linux-x64.tar.gz
# 与 tools/package_flutter_windows.ps1 对应：以 pubspec.yaml 为版本单一来源，
# 打包前校验 Release 产物与内置工具链、固件模板齐全。
set -euo pipefail

skip_build=0
output_base_name=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-build) skip_build=1 ;;
    --output-base-name)
      output_base_name="${2:?--output-base-name 需要参数}"
      shift
      ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' pubspec.yaml | head -1)"
if [ -z "$version" ]; then
  echo "无法从 pubspec.yaml 解析 version 行。" >&2
  exit 1
fi

if [ ! -f vendor/sdcc-toolchain/bundle_manifest.json ]; then
  echo "缺少内置 SDCC 工具链，请先运行 tools/prepare_sdcc_toolchain.sh。" >&2
  exit 1
fi
manifest_platform="$(python3 -c \
  "import json;print(json.load(open('vendor/sdcc-toolchain/bundle_manifest.json')).get('platform',''))")"
if [ "$manifest_platform" != "linux-x64" ]; then
  echo "vendor/sdcc-toolchain 的 platform 字段为 '$manifest_platform'，需要 linux-x64。" >&2
  exit 1
fi

if [ "$skip_build" -eq 0 ]; then
  flutter pub get
  flutter build linux --release
fi

bundle="build/linux/x64/release/bundle"
required=(
  "$bundle/pieblock_app"
  "$bundle/data/icudtl.dat"
  "$bundle/data/flutter_assets"
  "$bundle/data/flutter_assets/assets/fonts/NotoSansSC-Regular-subset.ttf"
)
for relative in "${required[@]}"; do
  if [ ! -e "$relative" ]; then
    echo "Release 产物缺失: $relative（请勿跳过构建）" >&2
    exit 1
  fi
done

# 运行时资源：内置 SDCC 工具链 + STC32G 固件模板 + Keil 工程参考。
# 发布包内与可执行文件同级放置，供 pieblock_toolchain 的 _locateAssets() 定位。
runtime="$bundle/data/pieblock_runtime"
rm -rf -- "$runtime"
mkdir -p "$runtime"
cp -a vendor/sdcc-toolchain "$runtime/sdcc-toolchain"
cp -a stc32g_sdcc "$runtime/stc32g_sdcc"
cp -a stc32g "$runtime/stc32g"

required_runtime=(
  "$runtime/sdcc-toolchain/bundle_manifest.json"
  "$runtime/sdcc-toolchain/bin/sdcc"
  "$runtime/stc32g_sdcc/build_manifest.json"
  "$runtime/stc32g/Libraries"
)
for relative in "${required_runtime[@]}"; do
  if [ ! -e "$relative" ]; then
    echo "运行时资源缺失: $relative" >&2
    exit 1
  fi
done

if [ -z "$output_base_name" ]; then
  output_base_name="PIEBlock-$version-linux-x64"
fi
dist="build/dist"
stage="$dist/$output_base_name"
rm -rf -- "$stage"
mkdir -p "$dist" "$stage"
cp -a "$bundle/." "$stage/"
chmod -R u+w "$stage"

# 顶层目录保留可执行位；去除构建过程产生的写权限差异，统一交给解包者。
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage/pieblock_app"
chmod 755 "$stage/data/pieblock_runtime/sdcc-toolchain/bin/"*

tarball="$dist/$output_base_name.tar.gz"
rm -f -- "$tarball"
tar -czf "$tarball" -C "$dist" "$output_base_name"
rm -rf -- "$stage"

echo "[PASS] Linux 发布包: $tarball"
