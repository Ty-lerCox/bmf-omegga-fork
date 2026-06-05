$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-finalization-helper-split-test"

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

$xrefs14439ea50ea90 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439ea50", "14439ea90") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439ea50-14439ea90.txt")

$window14439e620 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439e620", "28") `
  -OutputFile (Join-Path $tempRoot "window-14439e620.txt")

$window14439e6b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439e6b0", "28") `
  -OutputFile (Join-Path $tempRoot "window-14439e6b0.txt")

$window14439e770 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439e770", "40") `
  -OutputFile (Join-Path $tempRoot "window-14439e770.txt")

Assert-Match -Text $calls14439e620 -Pattern "140238f80" -Label "14439e620 should use the tiny formatter helper"
Assert-Match -Text $calls14439e620 -Pattern "1401332a0" -Label "14439e620 should emit through the shared logging sink"
Assert-Match -Text $window14439e620 -Pattern "ADD RCX,0x28" -Label "14439e620 should log from the shared finalization record payload"
Assert-Match -Text $window14439e620 -Pattern "LEA RDX,\[0x146d6b380\]" -Label "14439e620 should use its dedicated diagnostic format string"

Assert-Match -Text $calls14439e6b0 -Pattern "140238f80" -Label "14439e6b0 should use the tiny formatter helper"
Assert-Match -Text $calls14439e6b0 -Pattern "1401332a0" -Label "14439e6b0 should emit through the shared logging sink"
Assert-Match -Text $window14439e6b0 -Pattern "MOV RBX,qword ptr \[RDX \+ 0x98\]" -Label "14439e6b0 should report the accumulated payload bytes from +0x98"
Assert-Match -Text $window14439e6b0 -Pattern "MOV RSI,qword ptr \[RCX \+ 0x100\]" -Label "14439e6b0 should report the current prefab payload bytes from +0x100"
Assert-Match -Text $window14439e6b0 -Pattern "LEA RDX,\[0x146d6b3e0\]" -Label "14439e6b0 should use its dedicated diagnostic format string"

Assert-Match -Text $calls14439e770 -Pattern "14439ea50" -Label "14439e770 should call its threshold diagnostic helper"
Assert-Match -Text $calls14439e770 -Pattern "14439ea90" -Label "14439e770 should call its contextual threshold diagnostic helper"
Assert-Match -Text $window14439e770 -Pattern "CMP qword ptr \[RCX \+ 0x98\],0x40000001" -Label "14439e770 should guard on the accumulated payload threshold"
Assert-Match -Text $window14439e770 -Pattern "LEA RDI,\[RSI \+ 0x58\]" -Label "14439e770 should walk the shared bitset payload rooted at +0x58"
Assert-Match -Text $window14439e770 -Pattern "MOV EAX,dword ptr \[RSI \+ 0x70\]" -Label "14439e770 should read the bitset count from +0x70"

Assert-Match -Text $xrefs14439ea50ea90 -Pattern "14439e7af -> FUN_14439e770 @ 14439e770" -Label "14439ea50 should be private to 14439e770"
Assert-Match -Text $xrefs14439ea50ea90 -Pattern "14439ea0e -> FUN_14439e770 @ 14439e770" -Label "14439ea90 should be private to 14439e770"

Write-Host "PASS test-prefab-finalization-helper-split"
