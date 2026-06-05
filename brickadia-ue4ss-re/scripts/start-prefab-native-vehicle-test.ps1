param(
  [string]$BridgeDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799',
  [int]$Port = 7799,
  [string]$SourceBrz = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\artifacts\Clipboard.physics-meta.brz',
  [string]$ReplayArgs = 'offset 3000 0 700',
  [string]$ExpectedKind = 'any',
  [string]$PostHashPaste = 'dry-run',
  [string]$PostHashPasteTarget = 'last',
  [int]$TimeoutMs = 1800000,
  [int]$PollMs = 1000,
  [int]$WaitMs = 6000,
  [string]$OutJson = '',
  [switch]$RestartServer,
  [switch]$DryRun,
  [switch]$RequirePlayer
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$reDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $reDir

function Invoke-NodeJson {
  param(
    [string[]]$ArgumentList
  )

  $raw = & node @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "node $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE"
  }
  return $raw | ConvertFrom-Json
}

function Stop-ExistingWatcher {
  Get-CimInstance Win32_Process |
    Where-Object {
      $_.Name -eq 'node.exe' -and
      $_.CommandLine -like '*wait-prefab-native-capture-replay.js*' -and
      $_.CommandLine -like "*$BridgeDir*"
    } |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Clear-PrefabCaptureFiles {
  foreach ($fileName in @(
    'prefab-native-last.txt',
    'prefab-native-last-replayable.txt',
    'prefab-native-captures.ndjson',
    'prefab-native-watch-status.json'
  )) {
    $filePath = Join-Path $BridgeDir $fileName
    if (Test-Path $filePath) {
      Remove-Item -LiteralPath $filePath -Force
    }
  }
}

Set-Location $repoRoot
New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null

Stop-ExistingWatcher

$serverStart = $null
if ($RestartServer) {
  $serverStartRaw = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'start-bridge-test-server.ps1') `
    -BridgeDir $BridgeDir `
    -Port $Port `
    -EnableUnsafeProbes `
    -VerifyWaitSeconds 25
  if ($LASTEXITCODE -ne 0) {
    throw "start-bridge-test-server.ps1 failed with exit code $LASTEXITCODE"
  }
  $serverStart = $serverStartRaw | ConvertFrom-Json
  Clear-PrefabCaptureFiles
}

$install = Invoke-NodeJson @(
  (Join-Path $scriptDir 'send-bridge-rpc.js'),
  '--dir', $BridgeDir,
  '--method', 'console.exec',
  '--command-raw', 'Omegga.Bridge.InstallPrefabNativeHooks all',
  '--wait-ms', [string]$WaitMs,
  '--include-logs', '0'
)

$selfTest = Invoke-NodeJson @(
  (Join-Path $scriptDir 'send-bridge-rpc.js'),
  '--dir', $BridgeDir,
  '--method', 'console.exec',
  '--command-raw', 'Omegga.Bridge.SelfTestPrefabNativeReplay',
  '--wait-ms', [string]([Math]::Max($WaitMs, 8000)),
  '--include-logs', '0'
)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$watcherOut = Join-Path $BridgeDir "prefab-native-watch-$stamp.json"
$watcherErr = Join-Path $BridgeDir "prefab-native-watch-$stamp.err.txt"
$watcherStatus = Join-Path $BridgeDir 'prefab-native-watch-status.json'
$dryRunValue = if ($DryRun) { '1' } else { '0' }
$requirePlayerValue = if ($RequirePlayer) { '1' } else { '0' }

$watcherArgs = @(
  "`"$(Join-Path $scriptDir 'wait-prefab-native-capture-replay.js')`"",
  '--dir', "`"$BridgeDir`"",
  '--expected-kind', $ExpectedKind,
  '--replay-args', "`"$ReplayArgs`"",
  '--timeout-ms', [string]$TimeoutMs,
  '--poll-ms', [string]$PollMs,
  '--wait-ms', [string]$WaitMs,
  '--status-path', "`"$watcherStatus`"",
  '--status-interval-ms', '5000',
  '--dry-run', $dryRunValue,
  '--require-player', $requirePlayerValue,
  '--post-hash-paste', $PostHashPaste,
  '--post-hash-paste-target', $PostHashPasteTarget
) -join ' '

$watcher = Start-Process `
  -FilePath 'node' `
  -ArgumentList $watcherArgs `
  -WorkingDirectory $repoRoot `
  -RedirectStandardOutput $watcherOut `
  -RedirectStandardError $watcherErr `
  -PassThru `
  -WindowStyle Hidden

Start-Sleep -Seconds 2

$readinessArgs = @(
  (Join-Path $scriptDir 'prefab-native-readiness.js'),
  '--dir', $BridgeDir,
  '--wait-ms', [string]([Math]::Max($WaitMs, 10000))
)
if ($SourceBrz -and (Test-Path $SourceBrz)) {
  $readinessArgs += @('--source-brz', $SourceBrz)
}
$readiness = Invoke-NodeJson $readinessArgs

$verifier = Invoke-NodeJson @(
  (Join-Path $scriptDir 'verify-prefab-native-vehicle-replay.js'),
  '--dir', $BridgeDir
)

$summary = [ordered]@{
  server_start = $serverStart
  bridge_dir = $BridgeDir
  connect_address = "127.0.0.1:$Port"
  source_brz = $SourceBrz
  install_hooks = @{
    success = [bool]$install.complete.success
    executor = $install.result.executor
  }
  self_test = @{
    success = [bool]$selfTest.complete.success
    executor = $selfTest.result.executor
    lines = @($selfTest.chunks | ForEach-Object { $_.line })
  }
  watcher = @{
    pid = $watcher.Id
    status_path = $watcherStatus
    stdout = $watcherOut
    stderr = $watcherErr
    replay_args = $ReplayArgs
    expected_kind = $ExpectedKind
    dry_run = [bool]$DryRun
  }
  readiness = $readiness
  vehicle_replay_verifier = $verifier
  next_action = $readiness.next_action
}

$summaryJson = $summary | ConvertTo-Json -Depth 12
if ($OutJson) {
  $outJsonPath = [System.IO.Path]::GetFullPath($OutJson)
  $outDir = Split-Path -Parent $outJsonPath
  if ($outDir) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  }
  Set-Content -LiteralPath $outJsonPath -Value $summaryJson -Encoding UTF8
}
Write-Output $summaryJson
