@echo off
rem 构建 pieblock_hid GDExtension（Windows 裸 HID）并把产物拷到 addons/pieblock_usb/win/
rem 前置：MSYS2 UCRT64 已安装（g++ 在 /c/msys64/ucrt64/bin），godot-cpp 已克隆到本目录
setlocal

set ROOT=%~dp0..
set SRC=%ROOT%\tools\gdext_pieblock_hid
set VENV_PY=%ROOT%\.venv\Scripts\python.exe
set DST=%ROOT%\addons\pieblock_usb\win

if not exist "%VENV_PY%" (
    echo [Error] 找不到 %VENV_PY% ^(项目 .venv 未创建^)
    exit /b 1
)

if not exist "%SRC%\godot-cpp\SConstruct" (
    echo [Info] 克隆 godot-cpp ^(master, Godot 4.7 API^) ...
    git clone --depth 1 https://github.com/godotengine/godot-cpp.git "%SRC%\godot-cpp"
    if errorlevel 1 exit /b 1
)

rem scons 装进项目 .venv，不污染系统 Python
"%VENV_PY%" -m pip install scons >nul 2>&1

rem 源码含中文字符串，scons 签名库默认按 GBK 写会崩，强制 UTF-8
set "PYTHONIOENCODING=utf-8"

rem 把 MSYS2 UCRT64 的 g++ 放进 PATH（scons use_mingw=yes 走它）
set "PATH=C:\msys64\ucrt64\bin;%PATH%"

pushd "%SRC%"
"%VENV_PY%" -m SCons platform=windows target=template_release use_mingw=yes -j8
if errorlevel 1 (
    popd
    echo [Error] 编译失败
    exit /b 1
)
popd

if not exist "%DST%" mkdir "%DST%"
copy /Y "%SRC%\bin\pieblock_hid.windows.template_release.x86_64.dll" "%DST%\pieblock_hid.dll" >nul
if errorlevel 1 (
    echo [Error] 拷贝 dll 失败
    exit /b 1
)
echo [OK] pieblock_hid.dll 已就绪: %DST%
endlocal
