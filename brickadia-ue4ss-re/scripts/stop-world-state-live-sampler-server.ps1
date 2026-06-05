param(
  [string]$LiveInfoPath = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\world-state-live-sampler-live.json'
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path $LiveInfoPath)) {
  Write-Host "No live sampler session info found at $LiveInfoPath"
  return
}

$liveInfo = Get-Content -Raw $LiveInfoPath | ConvertFrom-Json
$stopped = @()

foreach ($entry in @(
  @{ name = 'server'; pid = $liveInfo.pid },
  @{ name = 'watcher'; pid = $liveInfo.parser_pid }
)) {
  $processId = $entry.pid
  if (-not $processId) {
    continue
  }

  try {
    Stop-Process -Id $processId -Force -ErrorAction Stop
    $stopped += [pscustomobject]@{
      name = $entry.name
      pid = $processId
      stopped = $true
    }
  } catch {
    $stopped += [pscustomobject]@{
      name = $entry.name
      pid = $processId
      stopped = $false
      error = $_.Exception.Message
    }
  }
}

$stopped | ConvertTo-Json -Depth 6
