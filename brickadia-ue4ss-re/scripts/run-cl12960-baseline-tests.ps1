param(
  [string]$Bundle = "CL12960"
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $workspaceRoot "notes"
$probeRoot = Join-Path $workspaceRoot ("probes\{0}\output" -f $Bundle)
$bundleKey = $Bundle.ToLower()

$baselineSessionPath = Join-Path $notesRoot "$bundleKey-baseline-session-latest.json"
$unwrapSessionPath = Join-Path $notesRoot "$bundleKey-baseline-unwrap-session-latest.json"
$findFirstOfSessionPath = Join-Path $notesRoot "$bundleKey-baseline-findfirstof-session-latest.json"
$staticFindObjectSessionPath = Join-Path $notesRoot "$bundleKey-baseline-staticfindobject-session-latest.json"
$evidencePath = Join-Path $notesRoot "$bundleKey-evidence-latest.json"
$jsonReportPath = Join-Path $notesRoot "$bundleKey-baseline-tests-latest.json"
$markdownReportPath = Join-Path $notesRoot "$bundleKey-baseline-tests-latest.md"

New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null

& (Join-Path $PSScriptRoot "run-clean-baseline-session.ps1") `
  -Bundle $Bundle `
  -ProofOut (Join-Path $probeRoot "baseline-proof.jsonl") | Set-Content -Path $baselineSessionPath -Encoding utf8

& (Join-Path $PSScriptRoot "run-clean-baseline-session.ps1") `
  -Bundle $Bundle `
  -UnwrapHookParams `
  -ProofOut (Join-Path $probeRoot "baseline-proof-unwrap.jsonl") | Set-Content -Path $unwrapSessionPath -Encoding utf8

& (Join-Path $PSScriptRoot "run-clean-baseline-session.ps1") `
  -Bundle $Bundle `
  -LookupProbeSet "findfirstof" `
  -LookupDelayMs 0 `
  -ProofOut (Join-Path $probeRoot "baseline-proof-findfirstof.jsonl") | Set-Content -Path $findFirstOfSessionPath -Encoding utf8

& (Join-Path $PSScriptRoot "run-clean-baseline-session.ps1") `
  -Bundle $Bundle `
  -LookupProbeSet "staticfindobject" `
  -LookupDelayMs 0 `
  -ProofOut (Join-Path $probeRoot "baseline-proof-staticfindobject.jsonl") | Set-Content -Path $staticFindObjectSessionPath -Encoding utf8

python (Join-Path $PSScriptRoot "collect-cl12960-evidence.py") --bundle $Bundle | Set-Content -Path $evidencePath -Encoding utf8

python (Join-Path $PSScriptRoot "run-baseline-tests.py") `
  --workspace $workspaceRoot `
  --bundle $Bundle `
  --evidence $evidencePath `
  --write-json $jsonReportPath `
  --write-md $markdownReportPath
