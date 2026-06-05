$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-cache-finalization-orchestration-test"

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

$xrefs14439e310 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439e310") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439e310.txt")

$calls14439e620 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14439e620") `
  -OutputFile (Join-Path $tempRoot "calls-14439e620.txt")

$calls14439e6b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14439e6b0") `
  -OutputFile (Join-Path $tempRoot "calls-14439e6b0.txt")

$calls14439e770 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14439e770") `
  -OutputFile (Join-Path $tempRoot "calls-14439e770.txt")

$window14439de67 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439de67", "18") `
  -OutputFile (Join-Path $tempRoot "window-14439de67.txt")

$window14439e46f = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439e46f", "18") `
  -OutputFile (Join-Path $tempRoot "window-14439e46f.txt")

$window14439e5a9 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439e5a9", "18") `
  -OutputFile (Join-Path $tempRoot "window-14439e5a9.txt")

$window14439e5b5 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439e5b5", "18") `
  -OutputFile (Join-Path $tempRoot "window-14439e5b5.txt")

Assert-Match -Text $xrefs14439e310 -Pattern "FUN_14439d4f0 @ 14439d4f0" -Label "14439e310 should be called from the shared cache-finalization body 14439d4f0"

Assert-Match -Text $window14439de67 -Pattern "MOV RCX,RSI" -Label "14439d4f0 should pass the shared cache object as RCX into 14439e310"
Assert-Match -Text $window14439de67 -Pattern "LEA RDX,\[RSP \+ 0x138\]" -Label "14439d4f0 should pass the stack output struct as RDX into 14439e310"
Assert-Match -Text $window14439de67 -Pattern "MOV R8B,0x1" -Label "14439d4f0 should enable the conditional tail flag into 14439e310"
Assert-Match -Text $window14439de67 -Pattern "CALL 0x14439e310" -Label "14439d4f0 should call 14439e310"

Assert-Match -Text $calls14439e620 -Pattern "14439e46f <- FUN_14439e310 @ 14439e310" -Label "14439e620 should only be reached from 14439e310"
Assert-Match -Text $calls14439e6b0 -Pattern "14439e5a9 <- FUN_14439e310 @ 14439e310" -Label "14439e6b0 should only be reached from 14439e310"
Assert-Match -Text $calls14439e770 -Pattern "14439e5b5 <- FUN_14439e310 @ 14439e310" -Label "14439e770 should only be reached from 14439e310"

Assert-Match -Text $window14439e46f -Pattern "CALL 0x14439e620" -Label "14439e310 should call 14439e620 in its early sync block"
Assert-Match -Text $window14439e46f -Pattern "MOV RDI,qword ptr \[R15 \+ 0xf0\]" -Label "14439e310 should fetch the prefab archive pointer after the early sync block"

Assert-Match -Text $window14439e5a9 -Pattern "MOV RAX,qword ptr \[RAX \+ 0x100\]" -Label "14439e310 should read the cached prefab payload size from +0x100 before accumulation"
Assert-Match -Text $window14439e5a9 -Pattern "ADD qword ptr \[RDI \+ 0x98\],RAX" -Label "14439e310 should accumulate payload size into the shared finalization record"
Assert-Match -Text $window14439e5a9 -Pattern "CALL 0x14439e6b0" -Label "14439e310 should call 14439e6b0 in its accumulation block"

Assert-Match -Text $window14439e5b5 -Pattern "TEST BL,BL" -Label "14439e310 should gate the tail helper on BL"
Assert-Match -Text $window14439e5b5 -Pattern "CALL 0x14439e770" -Label "14439e310 should conditionally call 14439e770 as its tail helper"

Write-Host "PASS test-prefab-cache-finalization-orchestration"
