param(
  [string]$Bundle = 'CL12960'
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $workspaceRoot 'notes'
$bundleKey = $Bundle.ToLower()
$probeRoot = Join-Path $workspaceRoot ("probes\{0}\output" -f $Bundle)
$proofOut = Join-Path $probeRoot 'world-export-context-proof.jsonl'
$jsonReportPath = Join-Path $notesRoot "$bundleKey-world-export-canary-latest.json"
$markdownReportPath = Join-Path $notesRoot "$bundleKey-world-export-canary-latest.md"

New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null

& (Join-Path $PSScriptRoot 'run-clean-world-export-session.ps1') -Bundle $Bundle -ProofOut $proofOut | Out-Null

python (Join-Path $PSScriptRoot 'run-world-export-canary-tests.py') `
  --workspace $workspaceRoot `
  --bundle $Bundle `
  --proof-output $proofOut `
  --write-json $jsonReportPath `
  --write-md $markdownReportPath
