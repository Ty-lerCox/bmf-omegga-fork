param(
  [string]$RuntimeModsDir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods',
  [string]$BrickadiaExe = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe',
  [string]$UserDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data',
  [string]$GlobalTokenPath = 'C:\Users\tycox\AppData\Roaming\omegga\global_auth_token',
  [string]$Map = 'Plate',
  [int]$Port = 7777,
  [int]$IntervalMs = 750,
  [string]$Center = '0,0,0',
  [string]$Extent = '100,100,100',
  [string]$CandidateClasses = 'GameModeBase,GameStateBase,GameSession,PlayerController,BP_PlayerController_C,BP_PlayerState_C,Tool_Selector_C,BP_ToolPreviewActor_C,BrickGrid,BrickGridActor,BrickGridComponent,BrickGridDynamicActor,Entity_DynamicBrickGrid,BrickBuildingTemplate,BrickGridPreviewActor,BrickGridPreviewActor_C,BP_BrickGrid_C,BRWorldManager,BRWorldSerializer,BrickPrefabs,BRBundleArchive,BRChatCommandWorldSubsystem,BRBundleTransferComponent,BRGizmoManagerComponent,BRPrefabCache,BRPrefabCacheInMemoryPrefab,BRPrefabHashAndMetadata,BRPrefabDetachedPasteInfo',
[string]$NativeCalls = 'BRWorldManager:GetPendingWorldBundle,BRBundleTransferComponent:GetPendingWorldBundle,BRWorldManager:GetCurrentBundleState,BRBundleTransferComponent:GetCurrentBundleState,BRWorldManager:GetGlobalBrickGrid,BRWorldManager:GetGlobalBrickGridActor,BrickGridActor:GetBrickCount,BrickGridActor:GetBrickGrid,BrickGridComponent:GetBrickCount,BrickGridComponent:GetBrickGrid,BrickGridDynamicActor:GetBrickCount,BrickGridDynamicActor:GetBrickGrid,BRBundleArchive:GetBrickCount,BRBundleArchive:CountBricksAndComponents,Tool_Selector_C:HasSelection,Tool_Selector_C:HasSelectionBox,Tool_Selector_C:GetCurrentSelectionState,Tool_Selector_C:GetSelectionLayers,BP_ToolPreviewActor_C:GetPlaceable',
  [int]$VerifyWaitSeconds = 20
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$sourceMod = Join-Path $workspaceRoot 'probes\CL12960\WorldStateLiveSampler'
$targetMod = Join-Path $RuntimeModsDir 'WorldStateLiveSampler'
$bundleSignaturesDir = Join-Path $workspaceRoot 'bundles\CL12960\CustomGameConfigs\Brickadia\UE4SS_Signatures'
$runtimeSignaturesDir = Join-Path (Split-Path $RuntimeModsDir -Parent) 'UE4SS_Signatures'
$notesRoot = Join-Path $workspaceRoot 'notes'
$liveInfoOut = Join-Path $notesRoot 'world-state-live-sampler-live.json'
$builtUe4ssDll = 'C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\build_cmake_local_Game__Shipping__Win64\Game__Shipping__Win64\bin\UE4SS.dll'
$runtimeUe4ssDll = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\UE4SS.dll'
$stateRoot = Join-Path $UserDir 'ue4ss-world-state-live-sampler'
$tracePath = Join-Path $stateRoot 'mod.log'
$snapshotPath = Join-Path $stateRoot 'latest-snapshot.json'
$historyPath = Join-Path $stateRoot 'history.jsonl'
$ue4ssLog = Join-Path (Split-Path $RuntimeModsDir -Parent) 'UE4SS.log'
$brickadiaLog = Join-Path $UserDir 'Saved\Logs\Brickadia.log'

function Test-PortAvailable {
  param(
    [Parameter(Mandatory = $true)]
    [int]$PortNumber
  )

  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $PortNumber)
    $listener.Start()
    $listener.Stop()
    return $true
  } catch {
    return $false
  }
}

function Get-AvailablePort {
  param(
    [Parameter(Mandatory = $true)]
    [int]$PreferredPort
  )

  $candidate = $PreferredPort
  while (-not (Test-PortAvailable -PortNumber $candidate)) {
    $candidate += 1
  }
  return $candidate
}

if (!(Test-Path $sourceMod)) {
  throw "WorldStateLiveSampler source mod is missing: $sourceMod"
}

if (!(Test-Path $BrickadiaExe)) {
  throw "Missing Brickadia server binary: $BrickadiaExe"
}

if (!(Test-Path $GlobalTokenPath)) {
  throw "Missing global auth token: $GlobalTokenPath"
}

if (Test-Path $liveInfoOut) {
  try {
    $priorRun = Get-Content -Raw $liveInfoOut | ConvertFrom-Json
    foreach ($processId in @($priorRun.pid, $priorRun.parser_pid)) {
      if ($processId) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {
  }
}

$shouldSyncUe4ss = $false
if (Test-Path $builtUe4ssDll) {
  if (!(Test-Path $runtimeUe4ssDll)) {
    $shouldSyncUe4ss = $true
  } else {
    $builtHash = (Get-FileHash -Algorithm SHA256 $builtUe4ssDll).Hash
    $runtimeHash = (Get-FileHash -Algorithm SHA256 $runtimeUe4ssDll).Hash
    $shouldSyncUe4ss = $builtHash -ne $runtimeHash
  }
}

if ($shouldSyncUe4ss) {
  Copy-Item -Force $builtUe4ssDll $runtimeUe4ssDll
}

$token = (Get-Content -Raw $GlobalTokenPath).Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "Global auth token is empty: $GlobalTokenPath"
}

New-Item -ItemType Directory -Force -Path $RuntimeModsDir | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeSignaturesDir | Out-Null
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
New-Item -ItemType Directory -Force -Path $notesRoot | Out-Null

if (Test-Path $bundleSignaturesDir) {
  Copy-Item -Path (Join-Path $bundleSignaturesDir '*') -Destination $runtimeSignaturesDir -Force
}

foreach ($file in @($tracePath, $snapshotPath, $historyPath)) {
  if (Test-Path $file) {
    Remove-Item $file -Force
  }
}

if (Test-Path $targetMod) {
  Remove-Item -Recurse -Force $targetMod
}
Copy-Item -Recurse -Force $sourceMod $targetMod

$enabledPath = Join-Path $targetMod 'enabled.txt'
Set-Content -Path $enabledPath -Value '' -Encoding ascii

foreach ($modName in @('BaselineChatProof', 'BaselineObjectProof', 'WorldExportContextProof', 'CounterBroadcastDemo', 'OmeggaBridge', 'OmeggaBridgeProbe')) {
  $disabledEnabledPath = Join-Path (Join-Path $RuntimeModsDir $modName) 'enabled.txt'
  if (Test-Path $disabledEnabledPath) {
    Remove-Item $disabledEnabledPath -Force
  }
}

$selectedPort = Get-AvailablePort -PreferredPort $Port

$env:OMEGGA_UE4SS_WORLD_STATE_INTERVAL_MS = [string]$IntervalMs
$env:OMEGGA_UE4SS_WORLD_STATE_START_DELAY_MS = '1500'
$env:OMEGGA_UE4SS_WORLD_STATE_LOG = $tracePath
$env:OMEGGA_UE4SS_WORLD_STATE_SNAPSHOT = $snapshotPath
$env:OMEGGA_UE4SS_WORLD_STATE_HISTORY = $historyPath
$env:OMEGGA_UE4SS_WORLD_STATE_CENTER = $Center
$env:OMEGGA_UE4SS_WORLD_STATE_EXTENT = $Extent
$env:OMEGGA_UE4SS_WORLD_STATE_CLASSES = $CandidateClasses
$env:OMEGGA_UE4SS_WORLD_STATE_NATIVE_CALLS = $NativeCalls

$argList = @(
  "-Environment=`"$Map`"",
  '-NotInstalled',
  '-stdout',
  '-FullStdOutLogOutput',
  '-log',
  "-UserDir=`"$UserDir`"",
  "-Token=`"$token`"",
  "-port=`"$selectedPort`""
)

$proc = Start-Process -FilePath $BrickadiaExe -ArgumentList $argList -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)
$verified = $false
$verifyReason = 'native sampler startup not observed yet'
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 1

  if ($proc.HasExited) {
    $verifyReason = "server exited early with code $($proc.ExitCode)"
    break
  }

  $traceContents = if (Test-Path $tracePath) { Get-Content -Raw $tracePath } else { '' }
  $snapshotExists = Test-Path $snapshotPath
  if ($traceContents -match 'native sampler ready' -and $snapshotExists) {
    $verified = $true
    $verifyReason = 'observed native sampler ready trace and snapshot output'
    break
  }
}

$liveInfo = [ordered]@{
  mod_name = 'WorldStateLiveSampler'
  started_at = (Get-Date).ToString('o')
  pid = $proc.Id
  parser_pid = $null
  selected_port = $selectedPort
  map = $Map
  interval_ms = $IntervalMs
  region_center = $Center
  region_extent = $Extent
  connect_host = '127.0.0.1'
  connect_address = "127.0.0.1:$selectedPort"
  verified = $verified
  verify_reason = $verifyReason
  snapshot_path = $snapshotPath
  history_path = $historyPath
  trace_path = $tracePath
  ue4ss_log = $ue4ssLog
  brickadia_log = $brickadiaLog
  runtime_mod = $targetMod
  candidate_classes = $CandidateClasses
  native_calls = $NativeCalls
}

$liveInfo | ConvertTo-Json -Depth 8 | Set-Content -Path $liveInfoOut -Encoding utf8
$liveInfo | ConvertTo-Json -Depth 8
