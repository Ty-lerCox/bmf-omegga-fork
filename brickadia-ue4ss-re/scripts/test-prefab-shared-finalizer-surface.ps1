$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-shared-finalizer-surface-test"

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

$xrefs14473d890 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14473d890") `
  -OutputFile (Join-Path $tempRoot "xrefs-14473d890.txt")

$calls14473d890 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14473d890") `
  -OutputFile (Join-Path $tempRoot "calls-14473d890.txt")

$window14473d890 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473d890", "40") `
  -OutputFile (Join-Path $tempRoot "window-14473d890.txt")

Assert-Match -Text $xrefs14473d890 -Pattern "FUN_14473cf60 @ 14473cf60" -Label "14473d890 should be shared with the additive-stage family via 14473cf60"
Assert-Match -Text $xrefs14473d890 -Pattern "FUN_14439d4f0 @ 14439d4f0" -Label "14473d890 should also be reached from the prefab-cache consumer path"
Assert-Match -Text $xrefs14473d890 -Pattern "FUN_144739070 @ 144739070" -Label "14473d890 should be shared with nearby additive-side callback helpers"

Assert-Match -Text $window14473d890 -Pattern "MOV RCX,qword ptr \[RCX \+ 0x588\]" -Label "14473d890 should start by sweeping the retained object slot at +0x588"
Assert-Match -Text $window14473d890 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x558\]" -Label "14473d890 should release the retained slot at +0x558"
Assert-Match -Text $window14473d890 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x548\]" -Label "14473d890 should release the retained slot at +0x548"
Assert-Match -Text $window14473d890 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x538\]" -Label "14473d890 should release the retained slot at +0x538"
Assert-Match -Text $window14473d890 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x528\]" -Label "14473d890 should release the retained slot at +0x528"
Assert-Match -Text $window14473d890 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x518\]" -Label "14473d890 should release the retained slot at +0x518"
Assert-Match -Text $window14473d890 -Pattern "CALL 0x14008a1e0" -Label "14473d890 should drop retained references through the shared release helper"

Assert-Match -Text $calls14473d890 -Pattern "TryAcquireSRWLockExclusive" -Label "14473d890 should participate in synchronized cleanup or state reset"
Assert-Match -Text $calls14473d890 -Pattern "ReleaseSRWLockExclusive" -Label "14473d890 should release its cleanup locks after sweeping retained state"

Write-Host "PASS test-prefab-shared-finalizer-surface"
