#!/usr/bin/env bash
# 打包 PIE-Block TUI（Linux x86_64）
#
# 用法：
#   ./tui/scripts/package.sh                 # 构建 release 并打包
#   SKIP_BUILD=1 ./tui/scripts/package.sh    # 复用已构建的 release 产物
#   ./tui/scripts/package.sh 0.2.0           # 指定版本
#
# 产物：dist/PIE-Block-TUI-<版本>-linux-x86_64.tar.gz + .sha256
set -euo pipefail

TUI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$TUI_ROOT/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$TUI_ROOT/dist}"
VERSION="${1:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 -E '^version\s*=\s*"' "$TUI_ROOT/Cargo.toml" | sed -E 's/.*"([^"]+)".*/\1/')"
fi
[[ -n "$VERSION" ]] || { echo "无法读取版本号" >&2; exit 1; }

echo "==> PIE-Block TUI $VERSION（linux-x86_64）打包"
if [[ "$SKIP_BUILD" != "1" ]]; then
  cargo build --release -p pieblock-tui --manifest-path "$TUI_ROOT/Cargo.toml"
fi
BIN="$TUI_ROOT/target/release/pieblock-tui"
[[ -f "$BIN" ]] || { echo "找不到 release 产物：$BIN" >&2; exit 1; }

STAGE_NAME="PIE-Block-TUI-$VERSION-linux-x86_64"
STAGE="$OUTPUT_ROOT/$STAGE_NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/data/pieblock_runtime" "$STAGE/assets/templates"

cp "$BIN" "$STAGE/pieblock-tui"
cp "$TUI_ROOT/README.md" "$STAGE/README.md"
cp -a "$REPO_ROOT/vendor/sdcc-toolchain" "$STAGE/data/pieblock_runtime/sdcc-toolchain"
cp -a "$REPO_ROOT/stc32g_sdcc" "$STAGE/data/pieblock_runtime/stc32g_sdcc"
cp -a "$REPO_ROOT/assets/templates/." "$STAGE/assets/templates/"

cat > "$STAGE/THIRD_PARTY_NOTICES.txt" <<'EOF'
PIE-Block TUI 发布包第三方组件声明

本发布包包含 SDCC（C251 版）工具链，位于 data/pieblock_runtime/sdcc-toolchain。
SDCC 以其原始许可证（GPL）发布，许可证原文见 sdcc-toolchain/COPYING 与 COPYING3。
stc32g_sdcc/ 为项目自带固件支撑源码，随本仓库许可证发布。
EOF

# 校验：发布产物中不得出现 Dart/Flutter 运行时文件。
if find "$STAGE" \( -name '*.dart' -o -name '*.dill' -o -name 'libapp*' -o -name 'flutter_*' -o -name 'libflutter*' \) -print -quit | grep -q .; then
  echo "发布产物包含 Dart/Flutter 文件，打包中止" >&2
  exit 1
fi
if find "$STAGE" -type d \( -name flutter -o -name dart-sdk -o -name .dart_tool \) -print -quit | grep -q .; then
  echo "发布产物包含 Dart/Flutter 目录，打包中止" >&2
  exit 1
fi

# 自检：从无关目录启动，可执行文件应自行定位包内运行时资源。
echo "==> 自检发布包运行环境…"
DIAG="$(cd /tmp && "$STAGE/pieblock-tui" --diagnostics)"
echo "$DIAG"
grep -qF "$STAGE/data/pieblock_runtime" <<< "$DIAG" || { echo "发布包未定位到自身运行时资源" >&2; exit 1; }

TARBALL="$OUTPUT_ROOT/$STAGE_NAME.tar.gz"
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$OUTPUT_ROOT" "$STAGE_NAME"
HASH="$(sha256sum "$TARBALL" | awk '{print $1}')"
echo "$HASH  $STAGE_NAME.tar.gz" > "$TARBALL.sha256"

echo "==> 完成：$TARBALL（$(du -h "$TARBALL" | cut -f1)）"
echo "==> SHA-256：$HASH"
