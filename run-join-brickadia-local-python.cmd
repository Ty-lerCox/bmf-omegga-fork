@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT=%SCRIPT_DIR%join-brickadia-local.py"

if not "%PYTHON_EXE%"=="" goto run_env

where py >nul 2>nul
if %ERRORLEVEL%==0 goto run_py

where python >nul 2>nul
if %ERRORLEVEL%==0 goto run_python

echo Python 3 was not found.
echo Install Python 3, or set PYTHON_EXE to the Python executable path.
exit /b 1

:run_env
"%PYTHON_EXE%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%

:run_py
py -3 "%SCRIPT%" %*
exit /b %ERRORLEVEL%

:run_python
python "%SCRIPT%" %*
exit /b %ERRORLEVEL%
