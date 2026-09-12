# 构建官网里的 Flutter Web 版并 staging 到 website/app/。
# 用法: tools/build_website.ps1 [-SkipBuild]
#
# 产物不进 git（.gitignore 里忽略 website/app/），发布流程是：
#   tools/build_website.ps1 ; wrangler deploy
#
# 两个参数是刻意的：
#   --base-href /app/     官网只能托管 website/ 一个目录，应用放在它的子路径下，
#                         不带这个参数页面会去根路径找 main.dart.js 而 404。
#   --pwa-strategy=none   默认的 service worker 缓存很激进，网页版迭代时
#                         用户容易卡在旧版本上。
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

if (-not $SkipBuild) {
    flutter build web --release --base-href /app/ --pwa-strategy=none
    if ($LASTEXITCODE -ne 0) { throw "flutter build web 失败，退出码: $LASTEXITCODE" }
}

$source = Join-Path $repoRoot 'build/web'
$target = Join-Path $repoRoot 'website/app'

if (-not (Test-Path -LiteralPath (Join-Path $source 'main.dart.js'))) {
    throw "构建产物不完整：$source/main.dart.js 不存在，先不要用 -SkipBuild"
}

if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force

# *.symbols 只用于堆栈还原，运行时不会被请求；删掉能省约 8MB 磁盘。
Get-ChildItem -LiteralPath $target -Recurse -Filter '*.symbols' | Remove-Item -Force

$sizeMb = [math]::Round(
    (Get-ChildItem -LiteralPath $target -Recurse -File |
        Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Write-Host "[PASS] 网页版已就位: website/app（$sizeMb MB）"
