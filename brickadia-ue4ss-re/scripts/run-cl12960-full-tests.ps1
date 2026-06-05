param(
  [string]$Bundle = "CL12960"
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $workspaceRoot "notes"
$bundleKey = $Bundle.ToLower()

$baselineJsonPath = Join-Path $notesRoot "$bundleKey-baseline-tests-latest.json"
$chatJsonPath = Join-Path $notesRoot "$bundleKey-chat-canary-latest.json"
$worldExportJsonPath = Join-Path $notesRoot "$bundleKey-world-export-canary-latest.json"
$jsonReportPath = Join-Path $notesRoot "$bundleKey-full-tests-latest.json"
$markdownReportPath = Join-Path $notesRoot "$bundleKey-full-tests-latest.md"

& (Join-Path $PSScriptRoot "run-cl12960-baseline-tests.ps1") -Bundle $Bundle | Out-Null
& (Join-Path $PSScriptRoot "run-cl12960-chat-canary-tests.ps1") -Bundle $Bundle | Out-Null
& (Join-Path $PSScriptRoot "run-cl12960-world-export-canary-tests.ps1") -Bundle $Bundle | Out-Null

python (Join-Path $PSScriptRoot "render-full-test-suite.py") `
  --workspace $workspaceRoot `
  --bundle $Bundle `
  --baseline-report $baselineJsonPath `
  --chat-report $chatJsonPath `
  --world-export-report $worldExportJsonPath `
  --write-json $jsonReportPath `
  --write-md $markdownReportPath
