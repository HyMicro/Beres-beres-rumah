@echo off
setlocal
title Beres Rumah - WebGL
cd /d "%~dp0"

echo.
echo  BERES RUMAH - WEBGL
echo  ===================
echo  Menyiapkan web server lokal...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Serve-WebGL.ps1" -Port 8080

if errorlevel 1 (
    echo.
    echo  Server gagal dijalankan.
    echo  Pastikan Windows PowerShell tersedia, lalu coba lagi.
    echo.
    pause
)

endlocal
