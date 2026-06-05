$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-submit-orchestrator-shares-qword-table-with-serverpaste-test"

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Invoke-GhidraDump {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptName,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$OutputFile
  )

  $argList = @(
    $projectRoot,
    $projectName,
    "-readOnly",
    "-noanalysis",
    "-process",
    $programName,
    "-scriptPath",
    $scriptPath,
    "-postScript",
    $ScriptName
  ) + $Arguments

  $output = & $analyzeHeadless @argList 2>&1 | Out-String
  Set-Content -Path $OutputFile -Value $output

  if ($LASTEXITCODE -ne 0) {
    throw "Ghidra dump failed for $ScriptName $($Arguments -join ' ')"
  }

  return $output
}

function Assert-Match {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Text -notmatch $Pattern) {
    throw "Assertion failed: $Label"
  }
}

$refs144815870 = Invoke-GhidraDump `
  -ScriptName "GhidraListReferencesToAddress.java" `
  -Arguments @("144815870") `
  -OutputFile (Join-Path $tempRoot "refs-144815870.txt")

$qwords146cb1900 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpQwords.java" `
  -Arguments @("146cb1900", "10") `
  -OutputFile (Join-Path $tempRoot "qwords-146cb1900.txt")

Assert-Match -Text $refs144815870 -Pattern "from 146cb1938 type=DATA" -Label "144815870 should be owned by a real data-table entry, not just CFG/runtime metadata"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1910 -> 14481ae60" -Label "the shared qword block should include the native ServerPastePrefab implementation"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1918 -> 1448193b0" -Label "the shared qword block should continue through the neighboring controller-family handlers"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1920 -> 144819060" -Label "the shared qword block should continue through the neighboring controller-family handlers"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1928 -> 144818bf0" -Label "the shared qword block should continue through the neighboring controller-family handlers"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1930 -> 144818a40" -Label "the shared qword block should include the immediate predecessor to 144815870"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1938 -> 144815870" -Label "the shared qword block should include the higher submit orchestrator"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1940 -> 1448156d0" -Label "the shared qword block should continue past the higher submit orchestrator into the same family"

Write-Host "PASS test-prefab-submit-orchestrator-shares-qword-table-with-serverpaste"
