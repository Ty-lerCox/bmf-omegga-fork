$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-controller-non-botspawn-branch-split-test"

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

$qwords146cb1910 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpQwords.java" `
  -Arguments @("146cb1910", "6") `
  -OutputFile (Join-Path $tempRoot "qwords-146cb1910.txt")

$calls144818bf0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144818bf0") `
  -OutputFile (Join-Path $tempRoot "calls-144818bf0.txt")

$calls144815870 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144815870") `
  -OutputFile (Join-Path $tempRoot "calls-144815870.txt")

$window144818daa = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144818daa", "80") `
  -OutputFile (Join-Path $tempRoot "window-144818daa.txt")

Assert-Match -Text $qwords146cb1910 -Pattern "146cb1910 -> 14481ae60" -Label "the non-BotSpawn controller-family slice should still start at ServerPastePrefab"
Assert-Match -Text $qwords146cb1910 -Pattern "146cb1928 -> 144818bf0" -Label "the non-BotSpawn controller-family slice should include 144818bf0"
Assert-Match -Text $qwords146cb1910 -Pattern "146cb1938 -> 144815870" -Label "the non-BotSpawn controller-family slice should include the submit orchestrator"

Assert-Match -Text $calls144818bf0 -Pattern "144818daa -> 142955470" -Label "144818bf0 should resolve a shared selector/context helper"
Assert-Match -Text $calls144818bf0 -Pattern "144818db2 -> 141b9cbb0" -Label "144818bf0 should diverge into a comparison/selector helper after the seam"
Assert-Match -Text $calls144818bf0 -Pattern "144818e12 -> 1447f0e50" -Label "144818bf0 should run the first comparison/build helper"
Assert-Match -Text $calls144818bf0 -Pattern "144818e1a -> 144602330" -Label "144818bf0 should materialize the first helper result"
Assert-Match -Text $calls144818bf0 -Pattern "144818e5e -> 1447f37c0" -Label "144818bf0 should run the second comparison/build helper"
Assert-Match -Text $calls144818bf0 -Pattern "144818e66 -> 144602330" -Label "144818bf0 should materialize the second helper result"
Assert-NotMatch -Text $calls144818bf0 -Pattern "1443fa1e0" -Label "144818bf0 should not directly submit through the known prefab submit bridge"

Assert-Match -Text $window144818daa -Pattern "ADD R12,0x100" -Label "144818bf0 should rebase through a different context block than the +0x820 submit seam"
Assert-Match -Text $window144818daa -Pattern "MOV RCX,R12" -Label "144818bf0 should pass that rebased +0x100 context block into the selector helper"
Assert-Match -Text $window144818daa -Pattern "CALL 0x142955470" -Label "144818bf0 should still resolve through 142955470"
Assert-Match -Text $window144818daa -Pattern "CALL 0x141b9cbb0" -Label "144818bf0 should immediately peel into the comparison/selector helper after resolving the seam"
Assert-Match -Text $window144818daa -Pattern "CALL 0x1447f0e50" -Label "144818bf0 should run the first result-builder helper"
Assert-Match -Text $window144818daa -Pattern "CALL 0x1447f37c0" -Label "144818bf0 should run the second result-builder helper"
Assert-Match -Text $window144818daa -Pattern "CALL 0x144602330" -Label "144818bf0 should materialize helper results before comparing them"

Assert-Match -Text $calls144815870 -Pattern "144816db3 -> 1443fa1e0" -Label "144815870 should remain the direct submit orchestrator in this non-BotSpawn slice"
Assert-Match -Text $calls144815870 -Pattern "1448177b7 -> 1443fa1e0" -Label "144815870 should still issue the repeated submit handoffs"
Assert-NotMatch -Text $calls144815870 -Pattern "141b9cbb0" -Label "144815870 should not follow the comparison-heavy 144818bf0 branch"
Assert-NotMatch -Text $calls144815870 -Pattern "1447f0e50" -Label "144815870 should not follow the first comparison/build helper used by 144818bf0"
Assert-NotMatch -Text $calls144815870 -Pattern "1447f37c0" -Label "144815870 should not follow the second comparison/build helper used by 144818bf0"

Write-Host "PASS test-prefab-controller-non-botspawn-branch-split"
