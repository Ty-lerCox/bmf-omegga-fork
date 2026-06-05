param(
  [string]$Bundle = "CL12960"
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $workspaceRoot "notes"
$bundleKey = $Bundle.ToLower()

$sessionPath = Join-Path $notesRoot "$bundleKey-chat-session-latest.json"
$evidencePath = Join-Path $notesRoot "$bundleKey-chat-evidence-latest.json"
$jsonReportPath = Join-Path $notesRoot "$bundleKey-chat-canary-latest.json"
$markdownReportPath = Join-Path $notesRoot "$bundleKey-chat-canary-latest.md"
$probeRoot = Join-Path $workspaceRoot ("probes\{0}\output" -f $Bundle)
$proofOut = Join-Path $probeRoot "baseline-chat-proof.jsonl"

New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null

& (Join-Path $PSScriptRoot "run-clean-chat-session.ps1") -Bundle $Bundle -ProofOut $proofOut | Set-Content -Path $sessionPath -Encoding utf8

python (Join-Path $PSScriptRoot "collect-cl12960-evidence.py") --bundle $Bundle | Set-Content -Path $evidencePath -Encoding utf8

python (Join-Path $PSScriptRoot "run-chat-canary-tests.py") `
  --workspace $workspaceRoot `
  --bundle $Bundle `
  --evidence $evidencePath `
  --write-json $jsonReportPath `
  --write-md $markdownReportPath
