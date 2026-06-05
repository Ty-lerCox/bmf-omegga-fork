@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "OMEGGA_DIR=%SCRIPT_DIR%omegga-master\omegga-master"
set "UE4SS_SOURCE=%SCRIPT_DIR%zDEV-UE4SS_v3.0.1-940-g01e0a584"
set "OMEGGA_WINDOWS_BACKEND=ue4ss"
set "OMEGGA_UE4SS_PREFAB_PASTE=1"
set "OMEGGA_UE4SS_UNSAFE_PROBES=1"
set "OMEGGA_UE4SS_ALLOW_DEGRADED_WORLD_COMMANDS=1"
set "OMEGGA_UE4SS_ALLOW_UNSAFE_PLAYER_LOCATION=0"
set "OMEGGA_NATIVE_PREFAB_PLAYER_LOCATION=0"
set "OMEGGA_NATIVE_PREFAB_FALLBACK_X=14"
set "OMEGGA_NATIVE_PREFAB_FALLBACK_Y=-8"
set "OMEGGA_NATIVE_PREFAB_FALLBACK_Z=80"
set "OMEGGA_PREFAB_BROKER=1"
set "OMEGGA_PREFAB_BROKER_REQUEST_PATH=%SCRIPT_DIR%artifacts\spawncar-broker-requests.ndjson"
set "OMEGGA_NATIVE_PREFAB_LEGACY_HOOK=0"
set "OMEGGA_NATIVE_PREFAB_FORCE_LEGACY_HOOK=0"
set "OMEGGA_NATIVE_PREFAB_FILE_HOOK=0"
set "OMEGGA_NATIVE_PREFAB_FILE_SHARED=0"
set "OMEGGA_NATIVE_PREFAB_SHARED_REPLAY=0"
set "OMEGGA_NATIVE_PREFAB_LIVE_SHARED_REPLAY=0"
set "OMEGGA_NATIVE_PREFAB_COMBINED_PASTE_PLACE=0"
set "OMEGGA_NATIVE_PREFAB_REQUIRE_NATIVE_COMMIT=0"
set "OMEGGA_NATIVE_PREFAB_COMMIT_WAIT_MS=1000"
set "OMEGGA_NATIVE_PREFAB_HOOK_LOG_PATH=%SCRIPT_DIR%brickadia-ue4ss-re\artifacts\placeprefab-native-hook.log"

if not exist "%OMEGGA_DIR%\package.json" (
  echo Omegga project not found at:
  echo   %OMEGGA_DIR%
  exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js was not found in PATH.
  exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
  echo npm was not found in PATH.
  exit /b 1
)

if exist "%UE4SS_SOURCE%\dwmapi.dll" (
  set "OMEGGA_UE4SS_SOURCE=%UE4SS_SOURCE%"
) else (
  echo WARNING: Bundled UE4SS source was not found at:
  echo   %UE4SS_SOURCE%
  echo Omegga will fall back to its normal UE4SS source resolution.
  echo.
)

pushd "%OMEGGA_DIR%"

if not exist "%OMEGGA_DIR%\node_modules" (
  echo Installing npm dependencies...
  call npm install --no-fund --no-audit
  if errorlevel 1 (
    set "EXIT_CODE=%ERRORLEVEL%"
    popd
    exit /b %EXIT_CODE%
  )
)

echo Building backend...
call npm run build
if errorlevel 1 (
  set "EXIT_CODE=%ERRORLEVEL%"
  popd
  exit /b %EXIT_CODE%
)

echo Provisioning managed UE4SS payload...
call node --enable-source-maps index.js ue4ss install
if errorlevel 1 (
  set "EXIT_CODE=%ERRORLEVEL%"
  popd
  exit /b %EXIT_CODE%
)

echo Launching Omegga with the Windows UE4SS backend...
echo.
call npm start -- %*
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
