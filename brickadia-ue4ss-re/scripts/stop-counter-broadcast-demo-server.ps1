param(
  [string]$LiveInfoPath = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\counter-broadcast-demo-live.json',
  [string]$RuntimeModsDir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods'
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path $LiveInfoPath)) {
  throw "Missing live session metadata: $LiveInfoPath"
}

$liveInfo = Get-Content -Raw $LiveInfoPath | ConvertFrom-Json
$stopped = $false
$processFound = $false

if ($liveInfo.pid) {
  $proc = Get-Process -Id ([int]$liveInfo.pid) -ErrorAction SilentlyContinue
  if ($proc) {
    $processFound = $true
    Stop-Process -Id $proc.Id -Force
    $stopped = $true
  }
}

$enabledPath = Join-Path (Join-Path $RuntimeModsDir 'CounterBroadcastDemo') 'enabled.txt'
if (Test-Path $enabledPath) {
  Remove-Item $enabledPath -Force
}

[pscustomobject]@{
  live_info_path = $LiveInfoPath
  pid = $liveInfo.pid
  process_found = $processFound
  stopped = $stopped
  connect_address = $liveInfo.connect_address
} | ConvertTo-Json -Depth 8
