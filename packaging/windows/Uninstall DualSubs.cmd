@echo off
setlocal
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Uninstall-DualSubs.ps1" %*
exit /b %ERRORLEVEL%
