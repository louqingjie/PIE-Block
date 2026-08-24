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
  --disable-ucsim --disable-sdcdb --disable-sdbinutils --disable-non-free

make -j2 sdcc-base
install -m 755 support/cpp/gcc/cpp.exe bin/sdcpp.exe
install -m 755 support/cpp/gcc/cc1.exe bin/cc1.exe
make -j2
package_root="$install_root/sdcc"
mkdir -p "$package_root/bin" "$package_root/include/mcs51" \
  "$package_root/lib/mcs251-large-stack-auto" \
  "$package_root/libexec/sdcc/x86_64-pc-mingw64/12.1.0"
install -m 755 bin/sdcc.exe bin/sdcpp.exe bin/sdas251.exe bin/sdld.exe \
  "$package_root/bin/"
install -m 755 bin/cc1.exe \
  "$package_root/libexec/sdcc/x86_64-pc-mingw64/12.1.0/cc1.exe"
cp -a "$source_copy/device/include/asm" "$package_root/include/"
cp -a "$source_copy/device/include/"*.h "$package_root/include/"
cp -a "$source_copy/device/include/mcs51/." "$package_root/include/mcs51/"
cp -a device/lib/build/mcs251-large-stack-auto/. \
  "$package_root/lib/mcs251-large-stack-auto/"
