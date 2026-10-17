@echo off
rem Run PIE-Block on Windows with normal (Medium) integrity level.
rem
rem Why this wrapper exists:
rem   - The repository directory may carry a Low integrity label (AI agent sandbox).
rem     PowerShell then refuses to load tools\run_windows.ps1 ("not digitally signed"),
rem     so the script needs -ExecutionPolicy Bypass for this process only.
rem   - .ps1 has no file association on this machine, so double-clicking it does nothing.
rem
rem Usage (no extra flags needed):
rem   tools\run_windows.cmd
rem   tools\run_windows.cmd --release
rem   tools\run_windows.cmd --profile --verbose
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_windows.ps1" %*
exit /b %ERRORLEVEL%
