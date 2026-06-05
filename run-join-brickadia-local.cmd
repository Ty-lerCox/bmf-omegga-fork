@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT=%SCRIPT_DIR%join-brickadia-local.ahk"

if not "%AHK_EXE%"=="" goto run_script

if exist "%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_EXE=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK_EXE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if "%AHK_EXE%"=="" if exist "%ProgramFiles%\AutoHotkey\AutoHotkey.exe" set "AHK_EXE=%ProgramFiles%\AutoHotkey\AutoHotkey.exe"
if "%AHK_EXE%"=="" if exist "%ProgramFiles(x86)%\AutoHotkey\AutoHotkey.exe" set "AHK_EXE=%ProgramFiles(x86)%\AutoHotkey\AutoHotkey.exe"

if "%AHK_EXE%"=="" (
  echo AutoHotkey was not found.
  echo Install AutoHotkey v2, or set AHK_EXE to the AutoHotkey executable path.
  exit /b 1
)

:run_script
"%AHK_EXE%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%
