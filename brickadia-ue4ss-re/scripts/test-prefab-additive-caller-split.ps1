$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-additive-caller-split-test"

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

$calls1443f6f00 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1443f6f00") `
  -OutputFile (Join-Path $tempRoot "calls-1443f6f00.txt")

$calls144867650 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144867650") `
  -OutputFile (Join-Path $tempRoot "calls-144867650.txt")

$window1443f7ce9 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443f7ce9", "40") `
  -OutputFile (Join-Path $tempRoot "window-1443f7ce9.txt")

$window14486796d = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14486796d", "40") `
  -OutputFile (Join-Path $tempRoot "window-14486796d.txt")

Assert-Match -Text $calls1443f6f00 -Pattern "1443f7ce9 -> 14473cae0" -Label "1443f6f00 should feed the shared additive coordinator"
Assert-Match -Text $calls144867650 -Pattern "14486796d -> 14473cae0" -Label "144867650 should also feed the shared additive coordinator"

Assert-Match -Text $window1443f7ce9 -Pattern "MOV qword ptr \[RSP \+ 0xd0\],RCX" -Label "1443f6f00 should stage its object target into the GlobalGridTarget block"
Assert-Match -Text $window1443f7ce9 -Pattern "MOV dword ptr \[R13 \+ 0x8\],EAX" -Label "1443f6f00 should stage the GlobalGridTarget index or dimension field"
Assert-Match -Text $window1443f7ce9 -Pattern "MOV qword ptr \[R13\],RAX" -Label "1443f6f00 should stage the GlobalGridTarget pointer field"
Assert-Match -Text $window1443f7ce9 -Pattern "MOV byte ptr \[RSP \+ 0xf4\],AL" -Label "1443f6f00 should populate the first additive policy flag"
Assert-Match -Text $window1443f7ce9 -Pattern "MOV byte ptr \[RSP \+ 0xf5\],AL" -Label "1443f6f00 should populate the second additive policy flag"
Assert-Match -Text $window1443f7ce9 -Pattern "MOV byte ptr \[RSP \+ 0xf6\],AL" -Label "1443f6f00 should populate the third additive policy flag"
Assert-Match -Text $window1443f7ce9 -Pattern "MOV RDX,qword ptr \[RAX \+ 0xf0\]" -Label "1443f6f00 should pass the archive-backed preview/payload object through RDX"
Assert-Match -Text $window1443f7ce9 -Pattern "LEA R8,\[RSP \+ 0xd0\]" -Label "1443f6f00 should pass the staged GlobalGridTarget block in R8"
Assert-Match -Text $window1443f7ce9 -Pattern "LEA R9,\[RSP \+ 0x70\]" -Label "1443f6f00 should pass the additive params/result block in R9"

Assert-Match -Text $window14486796d -Pattern "MOV qword ptr \[RSP \+ 0x40\],0x0" -Label "144867650 should clear the GlobalGridTarget slot for PreviewPart mode"
Assert-Match -Text $window14486796d -Pattern "MOV qword ptr \[RSP \+ 0x58\],RSI" -Label "144867650 should stage its PreviewPart pointer into the alternate target slot"
Assert-Match -Text $window14486796d -Pattern "VMOVUPS ymmword ptr \[RSP \+ 0xbc\],YMM0" -Label "144867650 should zero the preview-mode params/result block"
Assert-Match -Text $window14486796d -Pattern "VMOVUPS ymmword ptr \[RSP \+ 0xa0\],YMM0" -Label "144867650 should continue zeroing the preview-mode params/result block"
Assert-Match -Text $window14486796d -Pattern "VMOVUPS ymmword ptr \[RSP \+ 0x80\],YMM0" -Label "144867650 should zero the staging block passed as R9"
Assert-Match -Text $window14486796d -Pattern "MOV RDX,qword ptr \[RSI \+ 0x1b0\]" -Label "144867650 should pass the PreviewPart-owned bundle/payload object through RDX"
Assert-Match -Text $window14486796d -Pattern "LEA R8,\[RSP \+ 0x40\]" -Label "144867650 should pass the mutually-exclusive target block in R8"
Assert-Match -Text $window14486796d -Pattern "LEA R9,\[RSP \+ 0x80\]" -Label "144867650 should pass the preview-mode params/result block in R9"

Write-Host "PASS test-prefab-additive-caller-split"
