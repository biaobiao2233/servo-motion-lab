@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tools\Start-DemoSession.ps1"
if errorlevel 1 pause
