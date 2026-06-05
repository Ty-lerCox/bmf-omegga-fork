$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-shared-bridge-selector-contract-test"

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

function Assert-Count {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][int]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $count = ([regex]::Matches($Text, $Pattern)).Count
  if ($count -ne $Expected) {
    throw "Assertion failed: $Label (expected $Expected, got $count)"
  }
}

$calls144286c80 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144286c80") `
  -OutputFile (Join-Path $tempRoot "calls-144286c80.txt")

$window144844171 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144844171", "30") `
  -OutputFile (Join-Path $tempRoot "window-144844171.txt")

$window1448441ff = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1448441ff", "30") `
  -OutputFile (Join-Path $tempRoot "window-1448441ff.txt")

$window14427da74 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14427da74", "30") `
  -OutputFile (Join-Path $tempRoot "window-14427da74.txt")

Assert-Match -Text $calls144286c80 -Pattern "1448441ff <- FUN_144844100 @ 144844100" -Label "144286c80 should be reached from the shared bridge"
Assert-Count -Text $calls144286c80 -Pattern "<-" -Expected 1 -Label "144286c80 should have exactly one caller in the current image model"

Assert-Match -Text $window144844171 -Pattern "MOV R15,qword ptr \[RSP \+ 0x90\]" -Label "144844100 should source the downstream selector container from its staged incoming state"
Assert-Match -Text $window144844171 -Pattern "MOV R12,qword ptr \[R15\]" -Label "144844100 should treat that incoming state as a selector container pointer"
Assert-Match -Text $window144844171 -Pattern "CALL 0x1421f4310" -Label "144844100 should resolve the selector candidate through 1421f4310"
Assert-Match -Text $window144844171 -Pattern "MOVSXD RCX,dword ptr \[RAX \+ 0x38\]" -Label "144844100 should treat the resolved candidate as an indexed selector record"
Assert-Match -Text $window144844171 -Pattern "CMP ECX,dword ptr \[R12 \+ 0x38\]" -Label "144844100 should validate the resolved selector index against the container count"
Assert-Match -Text $window144844171 -Pattern "CMP qword ptr \[RDX \+ RCX\*0x8\],RAX" -Label "144844100 should validate membership through the selector pointer table"

Assert-Match -Text $window1448441ff -Pattern "MOV RCX,qword ptr \[R15\]" -Label "144844100 should re-load the shared bridge target before the exclusive downstream handoff"
Assert-Match -Text $window1448441ff -Pattern "MOV R14,qword ptr \[R14 \+ 0x4b8\]" -Label "144844100 should rebase the owner/context through +0x4b8 before the downstream handoff"
Assert-Match -Text $window1448441ff -Pattern "LEA RAX,\[RSP \+ 0x28\]" -Label "144844100 should stage the downstream bridge-side argument cell on the stack"
Assert-Match -Text $window1448441ff -Pattern "MOV RCX,R14" -Label "144844100 should pass the rebased owner/context into the exclusive downstream handoff"
Assert-Match -Text $window1448441ff -Pattern "MOV RDX,RBX" -Label "144844100 should forward the original selector/request block into the exclusive downstream handoff"
Assert-Match -Text $window1448441ff -Pattern "MOV R8,RDI" -Label "144844100 should preserve the shared bridge owner argument as the third downstream parameter"
Assert-Match -Text $window1448441ff -Pattern "MOV R9,RSI" -Label "144844100 should preserve the staged payload/context as the fourth downstream parameter"
Assert-Match -Text $window1448441ff -Pattern "CALL 0x144286c80" -Label "144844100 should perform the exclusive downstream handoff only after selector validation"

Assert-Match -Text $window14427da74 -Pattern "MOV R9,qword ptr \[RSP \+ 0x40\]" -Label "14427d8d0 should stage the fourth shared-bridge argument from its local scratch block"
Assert-Match -Text $window14427da74 -Pattern "MOV R8,qword ptr \[RSP \+ 0x48\]" -Label "14427d8d0 should stage the third shared-bridge argument from its local scratch block"
Assert-Match -Text $window14427da74 -Pattern "LEA RAX,\[RSP \+ 0x30\]" -Label "14427d8d0 should build the stack cell consumed by the shared bridge"
Assert-Match -Text $window14427da74 -Pattern "MOV qword ptr \[RSP \+ 0x20\],RAX" -Label "14427d8d0 should pass that stack cell by pointer into the shared bridge"
Assert-Match -Text $window14427da74 -Pattern "MOV RCX,RDI" -Label "14427d8d0 should pass its resolved owner/target as RCX into the shared bridge"
Assert-Match -Text $window14427da74 -Pattern "CALL 0x144844100" -Label "14427d8d0 should invoke the same shared bridge contract"
Assert-Match -Text $window14427da74 -Pattern "MOV byte ptr \[RSI\],AL" -Label "14427d8d0 should treat the shared bridge result as a returned success byte"

Write-Host "PASS test-prefab-preview-shared-bridge-selector-contract"
