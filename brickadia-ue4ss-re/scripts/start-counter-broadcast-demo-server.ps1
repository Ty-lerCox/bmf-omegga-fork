param(
  [string]$RuntimeModsDir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods',
  [string]$BrickadiaExe = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe',
  [string]$UserDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data',
  [string]$GlobalTokenPath = 'C:\Users\tycox\AppData\Roaming\omegga\global_auth_token',
  [string]$Map = 'Plate',
  [int]$Port = 7777,
  [int]$IntervalMs = 3000,
  [int]$VerifyWaitSeconds = 15
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$sourceMod = Join-Path $workspaceRoot 'probes\CL12960\CounterBroadcastDemo'
$targetMod = Join-Path $RuntimeModsDir 'CounterBroadcastDemo'
$bundleSignaturesDir = Join-Path $workspaceRoot 'bundles\CL12960\CustomGameConfigs\Brickadia\UE4SS_Signatures'
$runtimeSignaturesDir = Join-Path (Split-Path $RuntimeModsDir -Parent) 'UE4SS_Signatures'
$notesRoot = Join-Path $workspaceRoot 'notes'
$liveInfoOut = Join-Path $notesRoot 'counter-broadcast-demo-live.json'
$builtUe4ssDll = 'C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\build_cmake_local_Game__Shipping__Win64\Game__Shipping__Win64\bin\UE4SS.dll'
$runtimeUe4ssDll = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\UE4SS.dll'
$stateRoot = Join-Path $UserDir 'ue4ss-counter-broadcast-demo'
$statePath = Join-Path $stateRoot 'count.txt'
$tracePath = Join-Path $stateRoot 'mod.log'
$bridgeInboxPath = Join-Path $stateRoot 'bridge-inbox.ndjson'
$bridgeOutboxPath = Join-Path $stateRoot 'bridge-outbox.ndjson'
$bridgeStatusPath = Join-Path $stateRoot 'bridge-status.json'
$bridgeTracePath = Join-Path $stateRoot 'bridge-trace.log'
$chatTracePath = Join-Path $stateRoot 'chat-trace.log'
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
  throw "CounterBroadcastDemo source mod is missing: $sourceMod"
}

if (!(Test-Path $BrickadiaExe)) {
  throw "Missing Brickadia server binary: $BrickadiaExe"
}

if (!(Test-Path $GlobalTokenPath)) {
  throw "Missing global auth token: $GlobalTokenPath"
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

Set-Content -Path $tracePath -Value '' -Encoding ascii
Set-Content -Path $bridgeInboxPath -Value '' -Encoding ascii
Set-Content -Path $bridgeOutboxPath -Value '' -Encoding ascii
Set-Content -Path $bridgeTracePath -Value '' -Encoding ascii
Set-Content -Path $chatTracePath -Value '' -Encoding ascii
if (Test-Path $bridgeStatusPath) {
  Remove-Item $bridgeStatusPath -Force
}

if (Test-Path $targetMod) {
  Remove-Item -Recurse -Force $targetMod
}
Copy-Item -Recurse -Force $sourceMod $targetMod

$enabledPath = Join-Path $targetMod 'enabled.txt'
Set-Content -Path $enabledPath -Value '' -Encoding ascii

foreach ($proofMod in @('BaselineChatProof', 'BaselineObjectProof')) {
  $proofEnabledPath = Join-Path (Join-Path $RuntimeModsDir $proofMod) 'enabled.txt'
  if (Test-Path $proofEnabledPath) {
    Remove-Item $proofEnabledPath -Force
  }
}

$selectedPort = Get-AvailablePort -PreferredPort $Port

$env:OMEGGA_UE4SS_COUNTER_BROADCAST_INTERVAL_MS = [string]$IntervalMs
$env:OMEGGA_UE4SS_COUNTER_BROADCAST_POLL_MS = '250'
$env:OMEGGA_UE4SS_COUNTER_BROADCAST_START_DELAY_MS = '12000'
$env:OMEGGA_UE4SS_COUNTER_BROADCAST_STATE = $statePath
$env:OMEGGA_UE4SS_COUNTER_BROADCAST_LOG = $tracePath
$env:OMEGGA_UE4SS_INBOX = $bridgeInboxPath
$env:OMEGGA_UE4SS_OUTBOX = $bridgeOutboxPath
$env:OMEGGA_UE4SS_STATUS = $bridgeStatusPath
$env:OMEGGA_UE4SS_TRACE = $bridgeTracePath
$env:OMEGGA_UE4SS_CHAT_TRACE_PATH = $chatTracePath
$env:OMEGGA_UE4SS_ENABLE_REFLECTION_CHAT_DISCOVERY = '0'
$env:OMEGGA_UE4SS_CHAT_TRACE = '1'
$env:OMEGGA_UE4SS_ENABLE_CHAT_DISCOVERY_HOOKS = '0'
$env:OMEGGA_UE4SS_UNSAFE_PROBES = '0'
$env:OMEGGA_UE4SS_PREFER_TYPED_CHAT_BROADCAST = '1'

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
$verifyReason = 'bridge/mod startup not observed yet'
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 1

  if ($proc.HasExited) {
    $verifyReason = "server exited early with code $($proc.ExitCode)"
    break
  }

  $traceContents = if (Test-Path $tracePath) { Get-Content -Raw $tracePath } else { '' }
  $outboxContents = if (Test-Path $bridgeOutboxPath) { Get-Content -Raw $bridgeOutboxPath } else { '' }
  if ($traceContents -match 'counter broadcast bridge/context ready' -and $outboxContents -match '"method":"bridge\.hello"') {
    $verified = $true
    $verifyReason = 'observed bridge hello plus demo bridge/context readiness'
    break
  }
}

$liveInfo = [ordered]@{
  mod_name = 'CounterBroadcastDemo'
  started_at = (Get-Date).ToString('o')
  pid = $proc.Id
  selected_port = $selectedPort
  map = $Map
  interval_ms = $IntervalMs
  connect_host = '127.0.0.1'
  connect_address = "127.0.0.1:$selectedPort"
  verified = $verified
  verify_reason = $verifyReason
  state_path = $statePath
  trace_path = $tracePath
  bridge_inbox_path = $bridgeInboxPath
  bridge_outbox_path = $bridgeOutboxPath
  bridge_status_path = $bridgeStatusPath
  bridge_trace_path = $bridgeTracePath
  chat_trace_path = $chatTracePath
  ue4ss_log = $ue4ssLog
  brickadia_log = $brickadiaLog
  runtime_mod = $targetMod
}

$liveInfo | ConvertTo-Json -Depth 8 | Set-Content -Path $liveInfoOut -Encoding utf8
$liveInfo | ConvertTo-Json -Depth 8
