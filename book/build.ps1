# 编译脚本：需要已安装 TeX Live / MacTeX（含 latexmk）
# 用法：在 book 目录执行  .\build.ps1

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command latexmk -ErrorAction SilentlyContinue)) {
    Write-Host "未检测到 latexmk。" -ForegroundColor Red
    Write-Host "请先安装 TeX Live 2024+ / MacTeX，安装指南：" -ForegroundColor Yellow
    Write-Host "  https://github.com/OsbertWang/install-latex-guide-zh-cn/releases" -ForegroundColor Yellow
    Write-Host "或把 book/ 打包上传 Overleaf，编译器选 XeLaTeX。" -ForegroundColor Yellow
    exit 1
}

latexmk -xelatex -interaction=nonstopmode -synctex=1 main.tex

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "编译成功：$(Join-Path (Get-Location) 'main.pdf')" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "编译失败，请查看 main.log 中的错误信息。" -ForegroundColor Red
    exit $LASTEXITCODE
}
