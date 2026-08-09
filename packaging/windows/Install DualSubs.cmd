@echo off
setlocal
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Install-DualSubs.ps1" %*
exit /b %ERRORLEVEL%
