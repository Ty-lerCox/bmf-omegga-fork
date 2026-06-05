$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-serverpaste-vs-submit-orchestrator-branch-split-test"

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

function Assert-NotMatch {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Text -match $Pattern) {
    throw "Assertion failed: $Label"
  }
}

$calls14481ae60 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14481ae60") `
  -OutputFile (Join-Path $tempRoot "calls-14481ae60.txt")

$calls144815870 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144815870") `
  -OutputFile (Join-Path $tempRoot "calls-144815870.txt")

$window14481b0a2 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14481b0a2", "72") `
  -OutputFile (Join-Path $tempRoot "window-14481b0a2.txt")

Assert-Match -Text $calls14481ae60 -Pattern "14481b0ac -> 142955470" -Label "ServerPastePrefab should enter the same +0x820 owner/context seam"
Assert-Match -Text $calls14481ae60 -Pattern "14481b0b7 -> 14439ce60" -Label "ServerPastePrefab should perform prefab-cache lookup after the shared seam"
Assert-Match -Text $calls14481ae60 -Pattern "14481b0d2 -> 14481b240" -Label "ServerPastePrefab cache-hit lane should enter the native paste-hit handler"
Assert-Match -Text $calls14481ae60 -Pattern "14481b1af -> 1447a7750" -Label "ServerPastePrefab cache-miss lane should fall back to hash-acquire/client-upload staging"
Assert-NotMatch -Text $calls14481ae60 -Pattern "-> 1443fa1e0" -Label "ServerPastePrefab should not directly use the thin submit bridge used by the higher submit orchestrator"

Assert-Match -Text $calls144815870 -Pattern "144815ba0 -> 142955470" -Label "the higher submit orchestrator should share the same owner/context seam"
Assert-Match -Text $calls144815870 -Pattern "144816db3 -> 1443fa1e0" -Label "the higher submit orchestrator should issue a first direct thin-submit handoff"
Assert-Match -Text $calls144815870 -Pattern "1448177b7 -> 1443fa1e0" -Label "the higher submit orchestrator should issue a second direct thin-submit handoff"
Assert-NotMatch -Text $calls144815870 -Pattern "-> 14439ce60" -Label "the higher submit orchestrator should not depend on the ServerPastePrefab cache lookup helper"
Assert-NotMatch -Text $calls144815870 -Pattern "-> 14481b240" -Label "the higher submit orchestrator should not route through the ServerPastePrefab cache-hit paste handler"
Assert-NotMatch -Text $calls144815870 -Pattern "-> 1447a7750" -Label "the higher submit orchestrator should not fall back to the cache-miss hash-acquire path"

Assert-Match -Text $window14481b0a2 -Pattern "ADD R14,0x820" -Label "ServerPastePrefab should rebase into the shared +0x820 owner/context block before diverging"
Assert-Match -Text $window14481b0a2 -Pattern "MOV RCX,R14" -Label "ServerPastePrefab should pass the rebased owner/context block as RCX"
Assert-Match -Text $window14481b0a2 -Pattern "CALL 0x142955470" -Label "ServerPastePrefab should resolve the same owner/context seam before its branch-specific work"
Assert-Match -Text $window14481b0a2 -Pattern "MOV RDX,RDI" -Label "ServerPastePrefab should carry the incoming prefab hash/request record into the cache lookup"
Assert-Match -Text $window14481b0a2 -Pattern "CALL 0x14439ce60" -Label "ServerPastePrefab should branch first through the prefab-cache lookup helper"
Assert-Match -Text $window14481b0a2 -Pattern "CALL 0x14481b240" -Label "ServerPastePrefab should route cache hits into the native paste-hit handler"

Write-Host "PASS test-prefab-serverpaste-vs-submit-orchestrator-branch-split"
