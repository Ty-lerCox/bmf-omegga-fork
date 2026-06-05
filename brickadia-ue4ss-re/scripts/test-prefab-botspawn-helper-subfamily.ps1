$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-botspawn-helper-subfamily-test"

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

$descBotSpawn = Invoke-GhidraDump `
  -ScriptName "GhidraDescribeAddress.java" `
  -Arguments @("146bf305a") `
  -OutputFile (Join-Path $tempRoot "desc-146bf305a.txt")

$descScript = Invoke-GhidraDump `
  -ScriptName "GhidraDescribeAddress.java" `
  -Arguments @("146b72ff0") `
  -OutputFile (Join-Path $tempRoot "desc-146b72ff0.txt")

$descEngine = Invoke-GhidraDump `
  -ScriptName "GhidraDescribeAddress.java" `
  -Arguments @("145c8ad06") `
  -OutputFile (Join-Path $tempRoot "desc-145c8ad06.txt")

$calls1448154d0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1448154d0") `
  -OutputFile (Join-Path $tempRoot "calls-1448154d0.txt")

$calls1448156d0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1448156d0") `
  -OutputFile (Join-Path $tempRoot "calls-1448156d0.txt")

$calls144815870 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144815870") `
  -OutputFile (Join-Path $tempRoot "calls-144815870.txt")

Assert-Match -Text $descBotSpawn -Pattern 'u"UBrickComponentType_BotSpawn"' -Label "1441bd030 should be anchored on the UBrickComponentType_BotSpawn reflected name"
Assert-Match -Text $descScript -Pattern 'u"/Script/Brickadia"' -Label "1441bd030 should be anchored in the Brickadia script package"
Assert-Match -Text $descEngine -Pattern 'u"Engine"' -Label "1441bd030 should also carry the Engine package string used in reflected class setup"

Assert-Match -Text $calls1448154d0 -Pattern "1448155e9 -> 1441bd030" -Label "1448154d0 should call the BotSpawn reflected helper"
Assert-Match -Text $calls1448156d0 -Pattern "1448157e6 -> 1441bd030" -Label "1448156d0 should call the BotSpawn reflected helper"
Assert-NotMatch -Text $calls144815870 -Pattern "1441bd030" -Label "144815870 should not depend on the BotSpawn-specific helper chain"

Write-Host "PASS test-prefab-botspawn-helper-subfamily"
