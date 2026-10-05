#!/usr/bin/env bash
# 构建、暂存并校验面向 Linux 的离线 SDCC C251 工具链。
# 用法: prepare_sdcc_toolchain.sh [--force] [--package-only]
#   --force        即使 vendor/sdcc-toolchain 已存在也重新构建暂存
#   --package-only 只重新执行暂存与 manifest 生成，不重新编译工具链
# 与 tools/prepare_sdcc_toolchain.ps1 保持同一 bundle_manifest.json schema，
# 额外写入 platform 字段区分平台；两者共用 vendor/sdcc-toolchain 暂存目录。
set -euo pipefail

force=0
package_only=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --package-only) package_only=1 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repo_root/sdcc-c251"
stage_root="$repo_root/vendor/sdcc-toolchain"
build_root="$repo_root/tmp/pie-block-sdcc-linux-build"
install_root="$repo_root/tmp/pie-block-sdcc-linux-install"

if [ ! -f "$source_root/.version" ]; then
  echo "未找到 sdcc-c251 子模块，请先执行: git submodule update --init sdcc-c251" >&2
  exit 1
fi

if [ "$force" -eq 0 ] && [ -f "$stage_root/bundle_manifest.json" ]; then
  echo "SDCC 工具链已准备；如需重建请加 --force。"
  exit 0
fi

if [ "$package_only" -eq 0 ]; then
  "$repo_root/tools/build_sdcc_linux_package.sh" \
    "$source_root" "$build_root" "$install_root"
fi

installed="$install_root/sdcc"
if [ ! -d "$installed" ]; then
  echo "SDCC 安装目录不存在: $installed（--package-only 需先完成一次完整构建）" >&2
  exit 1
fi

rm -rf -- "$stage_root"
mkdir -p "$stage_root/bin"
for binary in sdcc sdcpp sdas251 sdld; do
  install -m 755 "$installed/bin/$binary" "$stage_root/bin/"
done
cp -a "$installed/include" "$stage_root/include"
cp -a "$installed/libexec" "$stage_root/libexec"
mkdir -p "$stage_root/lib"
cp -a "$installed/lib/mcs251-large-stack-auto" "$stage_root/lib/"
install -m 644 "$source_root/README.md" "$stage_root/"
install -m 644 "$source_root/COPYING" "$stage_root/"
install -m 644 "$source_root/sdas/COPYING3" "$stage_root/"

cc1="$(find "$stage_root/libexec" -type f -name cc1 | head -1)"
required=(
  "bin/sdcc" "bin/sdcpp" "bin/sdas251" "bin/sdld"
  "include/mcs51/mcs51reg.h"
  "lib/mcs251-large-stack-auto/mcs251.lib"
  "lib/mcs251-large-stack-auto/libsdcc.lib"
)
for relative in "${required[@]}"; do
  if [ ! -f "$stage_root/$relative" ]; then
    echo "SDCC 工具链缺少必要文件: $relative" >&2
    exit 1
  fi
done
if [ -z "$cc1" ]; then
  echo "SDCC 工具链缺少必要文件: libexec/**/cc1" >&2
  exit 1
fi

# 冒烟验证：走通 sdcpp→cc1 预处理、编译、sdas251 汇编与 sdld 链接全链路，
# 单靠 --version 无法暴露 cc1/libexec 路径问题。
smoke_root="$(mktemp -d)"
trap 'rm -rf -- "$smoke_root"' EXIT
cat > "$smoke_root/smoke.c" <<'EOF'
#include <mcs51reg.h>
static unsigned char smoke_counter;
void main(void) {
  smoke_counter = 0;
  while (1) {
    smoke_counter++;
  }
}
EOF
mkdir -p "$smoke_root/out"
( cd "$smoke_root/out" \
  && "$stage_root/bin/sdcc" \
      -mmcs251 --model-large --stack-auto --opt-code-size --constseg CSEG -c \
      -I"$stage_root/include" -I"$stage_root/include/mcs51" \
      -o smoke.rel ../smoke.c \
  && "$stage_root/bin/sdcc" \
      -mmcs251 --model-large --stack-auto --constseg CSEG \
      --nostdlib --iram-size 0x1000 --xram-loc 0x010000 --xram-size 0x2000 \
      --code-loc 0xff0000 '-Wl-b GSINIT0=0xfe0000' \
      -L. -L"$stage_root/lib/mcs251-large-stack-auto" \
      smoke.rel mcs251.lib libsdcc.lib liblong.lib libint.lib \
      libfloat.lib liblonglong.lib \
      -o smoke.hex )
if [ ! -s "$smoke_root/out/smoke.hex" ]; then
  echo "冒烟编译未产出 HEX" >&2
  exit 1
fi

commit="$(git -C "$source_root" rev-parse HEAD)"
python3 - "$stage_root" "$commit" <<'PYEOF'
import datetime
import hashlib
import json
import pathlib
import sys

stage_root = pathlib.Path(sys.argv[1])
commit = sys.argv[2]
files = {}
for path in sorted(p for p in stage_root.rglob('*') if p.is_file()):
    relative = path.relative_to(stage_root).as_posix()
    files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
bundle = {
    'version': commit,
    'source_repository': 'https://github.com/louqingjie/sdcc-c251.git',
    'source_commit': commit,
    'generated_at_utc': datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec='seconds')
        .replace('+00:00', 'Z'),
    'platform': 'linux-x64',
    'files': files,
}
(stage_root / 'bundle_manifest.json').write_text(
    json.dumps(bundle, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PYEOF

"$stage_root/bin/sdcc" --version
echo "[PASS] SDCC 工具链已准备: $stage_root"
