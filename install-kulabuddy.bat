@echo off
setlocal
title KulaBuddy one-click install

cd /d "%~dp0"
echo [KulaBuddy] Starting one-click install...

where node >nul 2>nul
if errorlevel 1 (
  echo [KulaBuddy] Node.js is not installed.
  echo [KulaBuddy] Please install Node.js LTS from https://nodejs.org and run this file again.
  pause
  exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
  echo [KulaBuddy] npm is not available.
  echo [KulaBuddy] Please reinstall Node.js LTS and run again.
  pause
  exit /b 1
)

if not exist ".env" (
  if exist ".env.example" (
    copy ".env.example" ".env" >nul
    echo [KulaBuddy] Created .env from .env.example
  )
)

echo [KulaBuddy] Installing dependencies...
call npm.cmd install
if errorlevel 1 (
  echo [KulaBuddy] npm install failed.
  pause
  exit /b 1
)

echo [KulaBuddy] Building project...
call npm.cmd run build
if errorlevel 1 (
  echo [KulaBuddy] build failed.
  pause
  exit /b 1
)

echo [KulaBuddy] Install complete.
echo [KulaBuddy] Next step: double-click daDa.bat or use: npm run dev
pause
exit /b 0
