param(
  [string]$Bundle = "CL12960"
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $workspaceRoot "notes"
$bundleKey = $Bundle.ToLower()

$roadmapPath = Join-Path $notesRoot "$bundleKey-community-roadmap.md"
$reportPath = Join-Path $notesRoot "$bundleKey-baseline-tests-latest.json"

& (Join-Path $PSScriptRoot "run-cl12960-baseline-tests.ps1") -Bundle $Bundle | Out-Null

python (Join-Path $PSScriptRoot "render-community-roadmap.py") `
  --report $reportPath `
  --write $roadmapPath
