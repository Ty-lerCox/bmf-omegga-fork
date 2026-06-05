$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-post-selector-consumer-test"

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

$calls14475f3c0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14475f3c0") `
  -OutputFile (Join-Path $tempRoot "calls-14475f3c0.txt")

$calls1443c2640 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1443c2640") `
  -OutputFile (Join-Path $tempRoot "calls-1443c2640.txt")

$window14475f3c0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14475f3c0", "40") `
  -OutputFile (Join-Path $tempRoot "window-14475f3c0.txt")

Assert-Match -Text $calls14475f3c0 -Pattern "14439dcbe <- FUN_14439d4f0 @ 14439d4f0" -Label "14475f3c0 should be a downstream consumer reached from 14439d4f0"
Assert-Match -Text $calls1443c2640 -Pattern "14475f804 <- FUN_14475f3c0 @ 14475f3c0" -Label "14475f3c0 should participate in the shared post-consumer cleanup family"

Assert-Match -Text $window14475f3c0 -Pattern "MOV dword ptr \[R8\],0x0" -Label "14475f3c0 should clear its first output slot before processing"
Assert-Match -Text $window14475f3c0 -Pattern "MOV dword ptr \[R9\],0x0" -Label "14475f3c0 should clear its second output slot before processing"
Assert-Match -Text $window14475f3c0 -Pattern "MOV dword ptr \[RDX\],0x0" -Label "14475f3c0 should clear its third output slot before processing"
Assert-Match -Text $window14475f3c0 -Pattern "MOV dword ptr \[RCX\],0x0" -Label "14475f3c0 should clear its fourth output slot before processing"
Assert-Match -Text $window14475f3c0 -Pattern "MOV EDX,dword ptr \[RBX \+ 0x178\]" -Label "14475f3c0 should drive processing from the working-record count at +0x178"
Assert-Match -Text $window14475f3c0 -Pattern "MOV qword ptr \[RSP \+ 0x38\],RBX" -Label "14475f3c0 should preserve the working object across its downstream processing"
Assert-Match -Text $window14475f3c0 -Pattern "CALL 0x1400692f0" -Label "14475f3c0 should initialize its staging buffer before iterating the working-record set"

Write-Host "PASS test-prefab-post-selector-consumer"
