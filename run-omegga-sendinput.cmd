@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "OMEGGA_DIR=%SCRIPT_DIR%omegga-master\omegga-master"
set "TRACE_FILE=%OMEGGA_DIR%\windows-bridge-trace.log"

if not exist "%OMEGGA_DIR%\package.json" (
  echo Omegga project not found at:
  echo   %OMEGGA_DIR%
  exit /b 1
)

if exist "%TRACE_FILE%" del /f /q "%TRACE_FILE%" >nul 2>nul

set "OMEGGA_BRIDGE_SENDKEYS=1"
set "OMEGGA_BRIDGE_KEEP_VISIBLE=1"
set "OMEGGA_BRIDGE_DEBUG=1"
set "OMEGGA_BRIDGE_TRACE=%TRACE_FILE%"

echo Experimental Windows SendKeys mode enabled.
echo Keep the bridge console visible while testing /status or plugin actions.
echo Trace log: %TRACE_FILE%
echo.

pushd "%OMEGGA_DIR%"
call npm start
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
