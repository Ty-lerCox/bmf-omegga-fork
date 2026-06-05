$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-family-handoff-test"

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

$calls14486b520 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14486b520") `
  -OutputFile (Join-Path $tempRoot "calls-14486b520.txt")

$calls14486bd00 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14486bd00") `
  -OutputFile (Join-Path $tempRoot "calls-14486bd00.txt")

$window14486b5d0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14486b5d0", "96") `
  -OutputFile (Join-Path $tempRoot "window-14486b5d0.txt")

Assert-Match -Text $calls14486b520 -Pattern "14489e604 <- FUN_14489e260 @ 14489e260" -Label "14486b520 should be reached from the heavier orchestration-side preview bridge"
Assert-Match -Text $calls14486b520 -Pattern "14489ec79 <- FUN_14489e260 @ 14489e260" -Label "14486b520 should be reused by the second orchestration-side preview phase"
Assert-Match -Text $calls14486b520 -Pattern "1442a7036 <- FUN_1442a6fb0 @ 1442a6fb0" -Label "14486b520 should also remain reachable from the packed preview-family side"
Assert-Match -Text $calls14486b520 -Pattern "14486b5b4 -> 1442a5210" -Label "14486b520 should consume packed preview-family selector state"
Assert-Match -Text $calls14486b520 -Pattern "14486b5f4 -> 144885710" -Label "14486b520 should hand off into the vtable-style preview family"
Assert-Match -Text $calls14486b520 -Pattern "14486b625 -> 144266c20" -Label "14486b520 should resolve a second selector-backed state after the handoff"
Assert-Match -Text $calls14486b520 -Pattern "14486b64a -> 14466d2a0" -Label "14486b520 should normalize the resolved handoff object before storing it"
Assert-Match -Text $calls14486b520 -Pattern "14486b6b1 -> 140b9c7d0" -Label "14486b520 should commit the bridged preview object through its final submit helper"

Assert-Match -Text $calls14486bd00 -Pattern "14489ec9d <- FUN_14489e260 @ 14489e260" -Label "14486bd00 should feed the heavier orchestration-side bridge"
Assert-Match -Text $calls14486bd00 -Pattern "1442a6f3c <- FUN_1442a6ec0 @ 1442a6ec0" -Label "14486bd00 should also feed the packed preview-family side"

Assert-Match -Text $window14486b5d0 -Pattern "MOV RAX,qword ptr \[RCX \+ 0x98\]" -Label "14486b520 should begin from its preview-side state carrier"
Assert-Match -Text $window14486b5d0 -Pattern "CMP byte ptr \[RAX \+ 0x170\],0x3" -Label "14486b520 should gate on the preview-side state byte before the handoff"
Assert-Match -Text $window14486b5d0 -Pattern "CALL 0x1442a5210" -Label "14486b520 should read packed-family selector state during the handoff"
Assert-Match -Text $window14486b5d0 -Pattern "CMP qword ptr \[RDX \+ RCX\*0x8\],RAX" -Label "14486b520 should validate selector membership before creating the vtable-family object"
Assert-Match -Text $window14486b5d0 -Pattern "CALL 0x144885710" -Label "14486b520 should create or acquire the vtable-family preview object"
Assert-Match -Text $window14486b5d0 -Pattern "MOV qword ptr \[RSI \+ 0xb8\],RDI" -Label "14486b520 should retain the vtable-family preview object on its local state carrier"
Assert-Match -Text $window14486b5d0 -Pattern "CALL 0x144266c20" -Label "14486b520 should resolve a second selector-backed object after the vtable-family handoff"
Assert-Match -Text $window14486b5d0 -Pattern "CMP qword ptr \[RCX \+ RDX\*0x8\],RAX" -Label "14486b520 should validate the second selector-backed object before storage"
Assert-Match -Text $window14486b5d0 -Pattern "MOV qword ptr \[RBX \+ 0x2c0\],RDI" -Label "14486b520 should store the normalized bridged preview object onto the retained state"
Assert-Match -Text $window14486b5d0 -Pattern "MOV qword ptr \[RDI \+ 0x2c8\],RSI" -Label "14486b520 should back-link the bridged preview object to its source state"
Assert-Match -Text $window14486b5d0 -Pattern "MOV R8D,0x3" -Label "14486b520 should stage the final commit mode"
Assert-Match -Text $window14486b5d0 -Pattern "CALL 0x140b9c7d0" -Label "14486b520 should commit the bridged preview object through the final submit helper"

Write-Host "PASS test-prefab-preview-family-handoff"
