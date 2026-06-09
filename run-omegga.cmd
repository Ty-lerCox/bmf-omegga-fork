@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "OMEGGA_DIR=%SCRIPT_DIR%omegga-master\omegga-master"
set "UE4SS_SOURCE=%SCRIPT_DIR%zDEV-UE4SS_v3.0.1-940-g01e0a584"
set "OMEGGA_WINDOWS_BACKEND=ue4ss"
set "OMEGGA_UE4SS_PREFAB_PASTE=1"
set "OMEGGA_UE4SS_UNSAFE_PROBES=1"
set "OMEGGA_UE4SS_ALLOW_DEGRADED_WORLD_COMMANDS=1"
set "OMEGGA_UE4SS_ALLOW_STAGED_OBJECT_CONTROL=1"
set "OMEGGA_UE4SS_NOOP_UNSAFE_CONSOLE_COMMANDS=1"
set "OMEGGA_UE4SS_ALLOW_UNSAFE_POSITION_PROBES=1"
set "OMEGGA_UE4SS_ALLOW_UNSAFE_PLAYERS_LIST=0"
set "OMEGGA_UE4SS_ALLOW_UNSAFE_PLAYER_LOCATION=1"
set "OMEGGA_NATIVE_PREFAB_PLAYER_LOCATION=0"
set "BMF_ALLOW_LOOPASYNC=1"
set "OMEGGA_BMF_SOCKET_POLL_MS=200"
set "CITYRPG_BULK_POSITIONS=0"
set "CITYRPG_BRIDGE_POSITIONS=0"
set "CITYRPG_BMF_POSITIONS=1"
set "CITYRPG_BMF_LIVE_CONTROLLER_POSITIONS=1"
set "CITYRPG_BMF_POSITION_CACHE_MS=1500"
set "CITYRPG_BMF_UNSAFE_LIVE_PAWN_POSITIONS=0"
set "CITYRPG_LIVE_CONTROLLER_POSITIONS=0"
set "BMF_PLAYERS_POSITIONS_LIVE_CONTROLLER=0"
set "BMF_PLAYERS_LIST_LIVE_CONTROLLERS=1"
set "BMF_NATIVE_LOCATION_SCAN=0"
set "BMF_NATIVE_LOCATION_NAME_LOOKUP=0"
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

if exist "%SCRIPT_DIR%..\bmf\framework\ue4ss\Mods\BMF\bmf.json" (
  set "OMEGGA_BMF_SOURCE_DIR=%SCRIPT_DIR%..\bmf"
) else (
  echo WARNING: Sibling BMF repo was not found at:
  echo   %SCRIPT_DIR%..\bmf
  echo Omegga will fall back to its packaged BMF template.
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
