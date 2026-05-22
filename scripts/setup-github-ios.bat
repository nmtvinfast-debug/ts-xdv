@echo off
REM Tránh lỗi Execution Policy trên Windows
if "%~1"=="" (
  echo Cach dung:
  echo   scripts\setup-github-ios.bat https://github.com/nmtvinfast-debug/ts-xdv.git
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-github-ios.ps1" -RepoUrl "%~1"
