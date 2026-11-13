@echo off
chcp 65001 >nul
title Minh An B2B AI Agent Localhost Server (Port 8080)
cd /d "%~dp0"
echo Dang khoi dong Minh An B2B AI Agent Server tai http://localhost:8080/ ...
start "" "http://localhost:8080/"
powershell -ExecutionPolicy Bypass -File ".\start_server.ps1" -Port 8080
pause

