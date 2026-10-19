#!/usr/bin/env bash
# 编译脚本：需要已安装 TeX Live / MacTeX（含 latexmk）
# 用法：在 book 目录执行  ./build.sh

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v latexmk >/dev/null 2>&1; then
  echo "未检测到 latexmk。请先安装 TeX Live 2024+ / MacTeX，安装指南：" >&2
  echo "  https://github.com/OsbertWang/install-latex-guide-zh-cn/releases" >&2
  echo "或把 book/ 打包上传 Overleaf，编译器选 XeLaTeX。" >&2
  exit 1
fi

latexmk -xelatex -interaction=nonstopmode -synctex=1 main.tex
echo "编译成功：$(pwd)/main.pdf"
