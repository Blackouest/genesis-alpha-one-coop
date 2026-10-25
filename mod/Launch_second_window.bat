@echo off
rem Second game window for local co-op tests (test copy only)
cd /d "%~dp0"
start "" "Genesis-Win64-Shipping.exe" -windowed -ResX=1280 -ResY=720 -nosplash
