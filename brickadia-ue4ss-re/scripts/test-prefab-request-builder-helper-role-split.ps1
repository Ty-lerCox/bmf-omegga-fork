$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-request-builder-helper-role-split-test"

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

$calls1449310d0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1449310d0") `
  -OutputFile (Join-Path $tempRoot "calls-1449310d0.txt")

$calls144931270 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144931270") `
  -OutputFile (Join-Path $tempRoot "calls-144931270.txt")

Assert-Match -Text $calls1449310d0 -Pattern "1449310e4 -> 14466d2a0" -Label "FUN_1449310d0 should start from the common low-level field/fragment copier"
Assert-Match -Text $calls1449310d0 -Pattern "1449310ff -> 144931140" -Label "FUN_1449310d0 should hand off into its own tiny local completion helper"
Assert-NotMatch -Text $calls1449310d0 -Pattern "-> 1447f0e50" -Label "FUN_1449310d0 should stay out of the richer owner-side helper lane"
Assert-NotMatch -Text $calls1449310d0 -Pattern "-> 1447f6ee0" -Label "FUN_1449310d0 should stay out of the richer transform/staging lane"
Assert-Match -Text $calls1449310d0 -Pattern "144816e51 <- FUN_144815870" -Label "FUN_1449310d0 should serve the richer 144815870 submit variant"
Assert-Match -Text $calls1449310d0 -Pattern "14481784b <- FUN_144815870" -Label "FUN_1449310d0 should also serve the simpler 144815870 submit variant"
Assert-Match -Text $calls1449310d0 -Pattern "14481f25f <- FUN_14481ede0" -Label "FUN_1449310d0 should be shared outside 144815870 in the wider controller-family lane"
Assert-Match -Text $calls1449310d0 -Pattern "14481faef <- FUN_14481f4d0" -Label "FUN_1449310d0 should be shared across multiple sibling controller-family handlers"
Assert-Match -Text $calls1449310d0 -Pattern "1448207d1 <- FUN_1448203b0" -Label "FUN_1449310d0 should be part of a broader common request-builder surface"

Assert-Match -Text $calls144931270 -Pattern "1449312d0 -> 1447f0e50" -Label "FUN_144931270 should enter the richer owner-side helper lane"
Assert-Match -Text $calls144931270 -Pattern "1449313be -> 1447f6ee0" -Label "FUN_144931270 should perform the richer transform/staging step"
Assert-Match -Text $calls144931270 -Pattern "1449313dc -> 144931460" -Label "FUN_144931270 should finish through its own richer local completion helper"
Assert-Match -Text $calls144931270 -Pattern "144816e2b <- FUN_144815870" -Label "FUN_144931270 should feed the richer 144815870 submit variant"
Assert-Match -Text $calls144931270 -Pattern "144816200 <- FUN_144815870" -Label "FUN_144931270 should recur inside the same 144815870 family"
Assert-NotMatch -Text $calls144931270 -Pattern "14481f25f <- FUN_14481ede0" -Label "FUN_144931270 should not be part of the wider common request-builder surface used by sibling handlers"

Write-Host "PASS test-prefab-request-builder-helper-role-split"
