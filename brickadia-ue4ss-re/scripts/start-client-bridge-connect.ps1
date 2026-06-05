param(
  [string]$BrickadiaClientExe = 'J:\SteamLibrary\steamapps\common\Brickadia\Brickadia\Binaries\Win64\BrickadiaSteam-Win64-Shipping.exe',
  [string]$RuntimeModsDir = '',
  [string]$UE4SSSourceWin64Dir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64',
  [string]$BridgeDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-client-connect',
  [string]$ServerBridgeDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799',
  [string]$Address = '127.0.0.1:7799',
  [int]$VerifyWaitSeconds = 45,
  [int]$ContextWaitSeconds = 60,
  [switch]$RestartExisting
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path $BrickadiaClientExe)) {
  throw "Missing Brickadia client binary: $BrickadiaClientExe"
}
if (!(Test-Path $UE4SSSourceWin64Dir)) {
  throw "Missing UE4SS source Win64 directory: $UE4SSSourceWin64Dir"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sendRpc = Join-Path $PSScriptRoot 'send-bridge-rpc.js'
$omeggaBridgeTemplateDir = Join-Path $repoRoot 'omegga-master\omegga-master\templates\windows-ue4ss\ue4ss\Mods\OmeggaBridge'
$clientWin64Dir = Split-Path $BrickadiaClientExe -Parent
if ([string]::IsNullOrWhiteSpace($RuntimeModsDir)) {
  $RuntimeModsDir = Join-Path $clientWin64Dir 'ue4ss\Mods'
}
$omeggaBridgeRuntimeDir = Join-Path $RuntimeModsDir 'OmeggaBridge'

if (!(Test-Path $omeggaBridgeTemplateDir)) {
  throw "Missing OmeggaBridge template directory: $omeggaBridgeTemplateDir"
}
if (!(Test-Path $sendRpc)) {
  throw "Missing bridge RPC helper: $sendRpc"
}

$existingClients = @(Get-Process -Name 'BrickadiaSteam-Win64-Shipping' -ErrorAction SilentlyContinue)
if ($existingClients.Count -gt 0 -and !$RestartExisting) {
  [ordered]@{
    ok = $false
    result = 'client-already-running'
    detail = 'Pass -RestartExisting to stop the existing idle client before launching a bridge-enabled client.'
    existing_client_pids = @($existingClients | Select-Object -ExpandProperty Id)
  } | ConvertTo-Json -Depth 4
  exit 2
}

$sourceProxy = Join-Path $UE4SSSourceWin64Dir 'dwmapi.dll'
$sourceXInput = Join-Path $UE4SSSourceWin64Dir 'xinput1_3.dll'
$sourceUe4ss = Join-Path $UE4SSSourceWin64Dir 'ue4ss'
$targetProxy = Join-Path $clientWin64Dir 'dwmapi.dll'
$targetXInput = Join-Path $clientWin64Dir 'xinput1_3.dll'
$targetUe4ss = Join-Path $clientWin64Dir 'ue4ss'
if (!(Test-Path $sourceProxy)) {
  throw "Missing UE4SS proxy DLL: $sourceProxy"
}
if (!(Test-Path $sourceUe4ss)) {
  throw "Missing UE4SS source directory: $sourceUe4ss"
}
Copy-Item -Path $sourceProxy -Destination $targetProxy -Force
if (Test-Path $sourceXInput) {
  Copy-Item -Path $sourceXInput -Destination $targetXInput -Force
}
Copy-Item -Path $sourceUe4ss -Destination $targetUe4ss -Recurse -Force

New-Item -ItemType Directory -Force -Path $RuntimeModsDir | Out-Null
New-Item -ItemType Directory -Force -Path $omeggaBridgeRuntimeDir | Out-Null
Copy-Item -Path (Join-Path $omeggaBridgeTemplateDir '*') -Destination $omeggaBridgeRuntimeDir -Recurse -Force

$omeggaBridgeEnabledPath = Join-Path $omeggaBridgeRuntimeDir 'enabled.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $omeggaBridgeEnabledPath -Parent) | Out-Null
Set-Content -Path $omeggaBridgeEnabledPath -Value '' -Encoding ascii

if ($RestartExisting) {
  foreach ($client in $existingClients) {
    Stop-Process -Id $client.Id -Force -ErrorAction SilentlyContinue
  }
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    $remaining = @(Get-Process -Name 'BrickadiaSteam-Win64-Shipping' -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
      break
    }
    Start-Sleep -Milliseconds 250
  }
}

New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null
foreach ($fileName in @('inbox.ndjson', 'outbox.ndjson', 'bridge.log', 'status.json')) {
  $filePath = Join-Path $BridgeDir $fileName
  if (Test-Path $filePath) {
    Remove-Item $filePath -Force
  }
}

$env:OMEGGA_UE4SS_BRIDGE_DIR = $BridgeDir
$env:OMEGGA_UE4SS_UNSAFE_PROBES = '1'
$env:OMEGGA_UE4SS_DEBUG_BRIDGE_HOOKS = '0'

$argList = @(
  '-windowed',
  '-ResX=960',
  '-ResY=540'
)

$proc = Start-Process -FilePath $BrickadiaClientExe -ArgumentList $argList -PassThru

$bridgeLogPath = Join-Path $BridgeDir 'bridge.log'
$statusPath = Join-Path $BridgeDir 'status.json'
$verified = $false
$verifyReason = 'client bridge startup not observed yet'
$deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)

while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 1

  if ($proc.HasExited) {
    $verifyReason = "client exited early with code $($proc.ExitCode)"
    break
  }

  $bridgeLog = if (Test-Path $bridgeLogPath) { Get-Content -Raw $bridgeLogPath } else { '' }
  $statusExists = Test-Path $statusPath
  if ($bridgeLog -match 'bridge mod loaded' -and $bridgeLog -match 'Starting inbox poller' -and $statusExists) {
    $verified = $true
    $verifyReason = 'observed client bridge load, inbox poller, and status file'
    break
  }
}

$connectCommand = "Omegga.Bridge.ForceConsoleExecutor consolemanager open $Address/Game/Maps/MainMenu/MainMenu?Password"
$connectResult = $null
$connectError = $null
if ($verified) {
  try {
    $connectRaw = & node $sendRpc `
      --dir $BridgeDir `
      --method console.exec `
      --command-raw $connectCommand `
      --wait-ms 10000 `
      --include-logs 0
    $connectResult = $connectRaw | ConvertFrom-Json
  } catch {
    $connectError = $_.Exception.Message
  }
}

$contextResult = $null
$contextAvailable = $false
$contextDeadline = (Get-Date).AddSeconds($ContextWaitSeconds)
while ($verified -and (Get-Date) -lt $contextDeadline) {
  Start-Sleep -Seconds 1
  try {
    $contextRaw = & node $sendRpc `
      --dir $ServerBridgeDir `
      --method console.exec `
      --command-raw 'Omegga.Bridge.DescribeServerPastePrefabContext' `
      --wait-ms 6000 `
      --include-logs 0
    $contextResult = $contextRaw | ConvertFrom-Json
    $contextLines = @($contextResult.chunks | ForEach-Object { $_.line })
    if ($contextLines -contains 'context_available=true') {
      $contextAvailable = $true
      break
    }
  } catch {
    $contextResult = [ordered]@{ error = $_.Exception.Message }
  }
}

$players = $null
try {
  $playersRaw = & node $sendRpc `
    --dir $ServerBridgeDir `
    --method players.list `
    --wait-ms 6000 `
    --include-logs 0
  $players = $playersRaw | ConvertFrom-Json
} catch {
  $players = [ordered]@{ error = $_.Exception.Message }
}

[ordered]@{
  ok = $verified -and $contextAvailable
  result = if (!$verified) { 'client-bridge-not-verified' } elseif ($contextAvailable) { 'context-ready' } else { 'timeout-waiting-for-context' }
  client_pid = $proc.Id
  client_exited = $proc.HasExited
  connect_address = $Address
  client_bridge_dir = $BridgeDir
  client_bridge_verified = $verified
  client_bridge_verify_reason = $verifyReason
  connect_command = $connectCommand
  connect_result = $connectResult
  connect_error = $connectError
  server_context_available = $contextAvailable
  server_context = $contextResult
  players = $players
} | ConvertTo-Json -Depth 8
