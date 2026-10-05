#!/usr/bin/env bash
# 构建面向 Linux x86_64 的离线 SDCC C251 工具链。
# 用法: build_sdcc_linux_package.sh <源码目录> <构建目录> <安装目录>
# 配置裁剪与 fork 官方 CI（sdcc-c251/.github/workflows/windows-package.yml）
# 保持一致；差异点仅限平台本身：无 MSYS2 环境、路径分隔符用默认值、
# 链接改用 -static-libstdc++/-static-libgcc（Linux 下不建议静态链接 glibc）。
# 说明：cc1 依赖 support/sdbinutils 树的 libiberty，因此不能加
# --disable-sdbinutils（fork CI 亦未加）。
# 依赖: gcc/g++/make/bison/flex（git 检出不含预生成的语法分析器源码）。
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "用法: $0 <源码目录> <构建目录> <安装目录>" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$(realpath "$1")"
build_root="$(realpath -m "$2")"
install_root="$(realpath -m "$3")"

case "$source_root" in
  "$repo_root"/sdcc-c251|"$repo_root"/sdcc-c251/*) ;;
  *) echo "拒绝意外的源码路径: $source_root" >&2; exit 2 ;;
esac
for path in "$build_root" "$install_root"; do
  case "$path" in
    "$repo_root"/tmp/*) ;;
    *) echo "拒绝仓库 tmp/ 之外的构建/安装路径: $path" >&2; exit 2 ;;
  esac
done

for tool in gcc g++ make bison flex; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "缺少构建依赖: $tool" >&2
    exit 1
  }
done

rm -rf -- "$build_root" "$install_root"
mkdir -p "$build_root" "$install_root"
source_copy="$build_root/source"
mkdir -p "$source_copy"
cp -a "$source_root/." "$source_copy/"
tr -d '\r' < "$source_copy/.version" > "$source_copy/.version.lf"
mv "$source_copy/.version.lf" "$source_copy/.version"
mkdir -p "$build_root/build"

cd "$build_root/build"
LIB_TYPE=LIB CFLAGS=-std=gnu17 LDFLAGS="-static-libstdc++ -static-libgcc" \
  "$source_copy/configure" \
  --enable-mcs251-port \
  --prefix=/sdcc \
  --datarootdir=/sdcc \
  'docdir=${datarootdir}/doc' \
  include_dir_suffix=include \
  non_free_include_dir_suffix=non-free/include \
  lib_dir_suffix=lib \
  non_free_lib_dir_suffix=non-free/lib \
  --disable-z80-port --disable-z180-port --disable-r2k-port \
  --disable-r2ka-port --disable-r3ka-port --disable-r4k-port \
  --disable-r5k-port --disable-r6k-port --disable-sm83-port \
  --disable-tlcs90-port --disable-ez80-port --disable-z80n-port \
  --disable-r800-port --disable-ds390-port --disable-ds400-port \
  --disable-pic14-port --disable-pic16-port --disable-hc08-port \
  --disable-s08-port --disable-stm8-port --disable-pdk13-port \
  --disable-pdk14-port --disable-pdk15-port --disable-mos6502-port \
  --disable-mos65c02-port --disable-f8-port --disable-f8l-port \
  --disable-ucsim --disable-sdcdb --disable-non-free

# 与 fork CI 相同的三步构建：基础编译器 → 设备库 → DESTDIR 完整安装。
# make install 会把 cc1 自动放到 libexec/sdcc/<target>/<gcc 版本>/ 下，
# 路径由构建系统决定，无需手工硬编码。
make -j2 sdcc-base
install -m 755 support/cpp/gcc/cpp bin/sdcpp
install -m 755 support/cpp/gcc/cc1 bin/cc1
make -j2
make -C "$build_root/build" DESTDIR="$install_root" install

package_root="$install_root/sdcc"
for binary in sdcc sdcpp sdas251 sdld; do
  if [ ! -x "$package_root/bin/$binary" ]; then
    echo "安装产物缺少: bin/$binary" >&2
    exit 1
  fi
done
if ! find "$package_root/libexec" -type f -name cc1 | grep -q .; then
  echo "安装产物缺少: libexec/**/cc1" >&2
  exit 1
fi

echo "[PASS] SDCC Linux 工具链已构建: $package_root"
