param(
  [string]$RuntimeModsDir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods',
  [string]$BrickadiaExe = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe',
  [string]$UserDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data',
  [string]$GlobalTokenPath = 'C:\Users\tycox\AppData\Roaming\omegga\global_auth_token',
  [string]$BridgeDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799',
  [string]$Map = 'Plate',
  [int]$Port = 7799,
  [int]$VerifyWaitSeconds = 20,
  [switch]$EnableUnsafeProbes,
  [switch]$EnableDebugHooks
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path $BrickadiaExe)) {
  throw "Missing Brickadia server binary: $BrickadiaExe"
}

if (!(Test-Path $GlobalTokenPath)) {
  throw "Missing global auth token: $GlobalTokenPath"
}

$token = (Get-Content -Raw $GlobalTokenPath).Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "Global auth token is empty: $GlobalTokenPath"
}

New-Item -ItemType Directory -Force -Path $RuntimeModsDir | Out-Null

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$omeggaBridgeTemplateDir = Join-Path $repoRoot 'omegga-master\omegga-master\templates\windows-ue4ss\ue4ss\Mods\OmeggaBridge'
$omeggaBridgeRuntimeDir = Join-Path $RuntimeModsDir 'OmeggaBridge'
if (!(Test-Path $omeggaBridgeTemplateDir)) {
  throw "Missing OmeggaBridge template directory: $omeggaBridgeTemplateDir"
}
New-Item -ItemType Directory -Force -Path $omeggaBridgeRuntimeDir | Out-Null
Copy-Item -Path (Join-Path $omeggaBridgeTemplateDir '*') -Destination $omeggaBridgeRuntimeDir -Recurse -Force

foreach ($modName in @('WorldStateLiveSampler', 'WorldExportContextProof', 'CounterBroadcastDemo', 'BaselineChatProof', 'BaselineObjectProof', 'OmeggaBridgeProbe')) {
  $disabledEnabledPath = Join-Path (Join-Path $RuntimeModsDir $modName) 'enabled.txt'
  if (Test-Path $disabledEnabledPath) {
    Remove-Item $disabledEnabledPath -Force
  }
}

$omeggaBridgeEnabledPath = Join-Path $omeggaBridgeRuntimeDir 'enabled.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $omeggaBridgeEnabledPath -Parent) | Out-Null
Set-Content -Path $omeggaBridgeEnabledPath -Value '' -Encoding ascii

Get-CimInstance Win32_Process |
  Where-Object { $_.Name -eq 'BrickadiaServer-Win64-Shipping.exe' -and $_.CommandLine -like "*-port=`"$Port`"*"} |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 2

New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null
foreach ($fileName in @('inbox.ndjson', 'outbox.ndjson', 'bridge.log', 'status.json')) {
  $filePath = Join-Path $BridgeDir $fileName
  if (Test-Path $filePath) {
    Remove-Item $filePath -Force
  }
}

$env:OMEGGA_UE4SS_BRIDGE_DIR = $BridgeDir
$env:OMEGGA_UE4SS_UNSAFE_PROBES = if ($EnableUnsafeProbes) { '1' } else { '0' }
$env:OMEGGA_UE4SS_DEBUG_BRIDGE_HOOKS = if ($EnableDebugHooks) { '1' } else { '0' }

$argList = @(
  "-Environment=`"$Map`"",
  '-NotInstalled',
  '-stdout',
  '-FullStdOutLogOutput',
  '-log',
  "-UserDir=`"$UserDir`"",
  "-Token=`"$token`"",
  "-port=`"$Port`""
)

$proc = Start-Process -FilePath $BrickadiaExe -ArgumentList $argList -PassThru -WindowStyle Hidden

$bridgeLogPath = Join-Path $BridgeDir 'bridge.log'
$statusPath = Join-Path $BridgeDir 'status.json'
$deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)
$verified = $false
$verifyReason = 'bridge startup not observed yet'

while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 1

  if ($proc.HasExited) {
    $verifyReason = "server exited early with code $($proc.ExitCode)"
    break
  }

  $bridgeLog = if (Test-Path $bridgeLogPath) { Get-Content -Raw $bridgeLogPath } else { '' }
  $statusExists = Test-Path $statusPath
  if ($bridgeLog -match 'bridge mod loaded' -and $bridgeLog -match 'Starting inbox poller' -and $statusExists) {
    $verified = $true
    $verifyReason = 'observed bridge load, inbox poller, and status file'
    break
  }
}

[ordered]@{
  pid = $proc.Id
  connect_address = "127.0.0.1:$Port"
  bridge_dir = $BridgeDir
  bridge_log = $bridgeLogPath
  bridge_status = $statusPath
  verified = $verified
  verify_reason = $verifyReason
  unsafe_probes = [bool]$EnableUnsafeProbes
  debug_hooks = [bool]$EnableDebugHooks
} | ConvertTo-Json -Depth 4
