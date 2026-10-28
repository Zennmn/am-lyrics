@echo off
setlocal
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\upload-lyrics.ps1" %*
set "upload_exit=%errorlevel%"
echo.
if not "%upload_exit%"=="0" echo Upload failed. See the error above.
pause
exit /b %upload_exit%
