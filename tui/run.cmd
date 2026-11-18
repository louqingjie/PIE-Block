@echo off
setlocal

set "CARGO="
where cargo >nul 2>nul && set "CARGO=cargo"
if not defined CARGO if exist "%USERPROFILE%\.cargo\bin\cargo.exe" set "CARGO=%USERPROFILE%\.cargo\bin\cargo.exe"

if not defined CARGO (
  echo cargo not found. Install Rust from https://rustup.rs and reopen the terminal.
  exit /b 1
)

"%CARGO%" run -p pieblock-tui -- %*
exit /b %errorlevel%
