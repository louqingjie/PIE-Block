#!/usr/bin/env bash
set -euo pipefail
export MSYSTEM=UCRT64
export CHERE_INVOKING=1
export PATH="/ucrt64/bin:/usr/bin:$PATH"

source_root="$1"
build_root="$2"
install_root="$3"

case "$build_root:$install_root" in
  *pie-block*sdcc-windows-build*:*pie-block*sdcc-windows-install*) ;;
  *) echo "refusing unexpected build/install paths" >&2; exit 2 ;;
esac

rm -rf -- "$build_root" "$install_root"
mkdir -p "$build_root" "$install_root"
source_copy="$build_root/source"
mkdir -p "$source_copy"
cp -a "$source_root/." "$source_copy/"
tr -d '\r' < "$source_copy/.version" > "$source_copy/.version.lf"
mv "$source_copy/.version.lf" "$source_copy/.version"
mkdir -p "$build_root/build"

cd "$build_root/build"
# 不能加 --disable-sdbinutils：configure.ac:801 会跳过 support/sdbinutils，
# 而 cc1 链接时需要它产出的 libiberty.a（报错形如
# "No rule to make target '../../sdbinutils/libiberty/libiberty.a', needed by 'cc1.exe'"）。
LIB_TYPE=LIB CFLAGS=-std=gnu17 LDFLAGS=-static "$source_copy/configure" \
  --enable-mcs251-port \
  --prefix=/sdcc \
  --datarootdir=/sdcc \
  'docdir=${datarootdir}/doc' \
  include_dir_suffix=include \
  non_free_include_dir_suffix=non-free/include \
  lib_dir_suffix=lib \
  non_free_lib_dir_suffix=non-free/lib \
  'sdccconf_h_dir_separator=\\' \
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

make -j2 sdcc-base
install -m 755 support/cpp/gcc/cpp.exe bin/sdcpp.exe
install -m 755 support/cpp/gcc/cc1.exe bin/cc1.exe
make -j2

# 用 make install 装进暂存目录：构建树里 bin/ 的可执行名在各平台并不一致
# （Windows 上出现过无 .exe 后缀的 bin/sdcc），安装规则始终产出 bin/sdcc.exe 等标准名。
package_root="$install_root/sdcc"
rm -rf "$package_root"
make DESTDIR="$install_root" install

cc1_target="$package_root/libexec/sdcc/x86_64-pc-mingw64/12.1.0"
mkdir -p "$cc1_target"
if [ ! -f "$cc1_target/cc1.exe" ]; then
  # 安装规则在部分配置下不落 cc1，用刚编译出的副本补齐 libexec 布局。
  install -m 755 support/cpp/gcc/cc1.exe "$cc1_target/cc1.exe"
fi

for expected in bin/sdcc.exe bin/sdcpp.exe bin/sdas251.exe bin/sdld.exe \
  include/mcs51/mcs51reg.h lib/mcs251-large-stack-auto/libsdcc.lib \
  libexec/sdcc/x86_64-pc-mingw64/12.1.0/cc1.exe; do
  if [ ! -f "$package_root/$expected" ]; then
    echo "安装产物缺少 $expected；$package_root/bin 内容：" >&2
    ls -l "$package_root/bin" >&2
    exit 3
  fi
done
