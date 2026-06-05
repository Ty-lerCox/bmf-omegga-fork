$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-shared-bridge-caller-split-test"

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

$calls144844100 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144844100") `
  -OutputFile (Join-Path $tempRoot "calls-144844100.txt")

$calls14480c390 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14480c390") `
  -OutputFile (Join-Path $tempRoot "calls-14480c390.txt")

$window14480c49b = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14480c49b", "80") `
  -OutputFile (Join-Path $tempRoot "window-14480c49b.txt")

Assert-Match -Text $calls144844100 -Pattern "1447b72b8 <- FUN_1447b71b0 @ 1447b71b0" -Label "144844100 should be called from the packed-family sibling branch"
Assert-Match -Text $calls144844100 -Pattern "14480c49b <- FUN_14480c390 @ 14480c390" -Label "144844100 should also be called from the separate higher control-family branch"
Assert-Match -Text $calls144844100 -Pattern "14427da8b <- FUN_14427d8d0 @ 14427d8d0" -Label "144844100 should have at least one additional external caller beyond the two preview-control branches"
Assert-Match -Text $calls144844100 -Pattern "144844171 -> 1421f4310" -Label "144844100 should resolve the shared selector-like object surface"
Assert-Match -Text $calls144844100 -Pattern "1448441ff -> 144286c80" -Label "144844100 should hand off into the later bridge/apply helper after selector resolution"

Assert-Match -Text $calls14480c390 -Pattern "14480c49b -> 144844100" -Label "14480c390 should use the shared control bridge"
Assert-Match -Text $calls14480c390 -Pattern "14480c62a -> 144188fc0" -Label "14480c390 should continue into the later preview-side helper after the shared bridge path"
Assert-Match -Text $calls14480c390 -Pattern "14480c65c -> 1441707f0" -Label "14480c390 should preserve the downstream helper chain after its owner-state updates"

Assert-Match -Text $window14480c49b -Pattern "LEA RCX,\[RSI \+ 0x858\]" -Label "14480c390 should anchor a sibling owner-side object surface at +0x858 before the shared bridge"
Assert-Match -Text $window14480c49b -Pattern "MOV R15,qword ptr \[RDI \+ 0x10\]" -Label "14480c390 should source the bridge target from the incoming object payload"
Assert-Match -Text $window14480c49b -Pattern "LEA RDX,\[RSP \+ 0x50\]" -Label "14480c390 should stage a local request/result block for the shared bridge"
Assert-Match -Text $window14480c49b -Pattern "MOV RCX,R15" -Label "14480c390 should pass the bridge target as RCX into the shared bridge"
Assert-Match -Text $window14480c49b -Pattern "MOV R8,RSI" -Label "14480c390 should pass its owner/context as R8 into the shared bridge"
Assert-Match -Text $window14480c49b -Pattern "MOV R9,R14" -Label "14480c390 should forward the staged payload/context as R9 into the shared bridge"
Assert-Match -Text $window14480c49b -Pattern "CALL 0x144844100" -Label "14480c390 should call the shared bridge after staging the owner/context block"
Assert-Match -Text $window14480c49b -Pattern "MOV RCX,qword ptr \[RSI \+ 0x8b8\]" -Label "14480c390 should retain a second owner-side state surface at +0x8b8 after the shared bridge"
Assert-Match -Text $window14480c49b -Pattern "VADDSS XMM0,XMM6,dword ptr \[RSI \+ 0x8b0\]" -Label "14480c390 should fold owner threshold state from +0x8b0 after the shared bridge succeeds"

Write-Host "PASS test-prefab-preview-shared-bridge-caller-split"
