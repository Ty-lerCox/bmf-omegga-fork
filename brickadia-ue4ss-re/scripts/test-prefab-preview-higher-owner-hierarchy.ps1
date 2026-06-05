$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-higher-owner-hierarchy-test"

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

$calls1447b4ff0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447b4ff0") `
  -OutputFile (Join-Path $tempRoot "calls-1447b4ff0.txt")

$calls1447c74e0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447c74e0") `
  -OutputFile (Join-Path $tempRoot "calls-1447c74e0.txt")

$calls1447c8920 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447c8920") `
  -OutputFile (Join-Path $tempRoot "calls-1447c8920.txt")

$calls1447c8b00 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447c8b00") `
  -OutputFile (Join-Path $tempRoot "calls-1447c8b00.txt")

$calls1447b4290 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447b4290") `
  -OutputFile (Join-Path $tempRoot "calls-1447b4290.txt")

$window1447b509f = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1447b509f", "80") `
  -OutputFile (Join-Path $tempRoot "window-1447b509f.txt")

$window1447b515f = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1447b515f", "40") `
  -OutputFile (Join-Path $tempRoot "window-1447b515f.txt")

$xrefs1447b4ff0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1447b4ff0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1447b4ff0.txt")

$xrefs1447c74e0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1447c74e0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1447c74e0.txt")

Assert-Match -Text $calls1447b4ff0 -Pattern "1447b509f -> 1447c65e0" -Label "1447b4ff0 should drive the first mid-owner preview wrapper"
Assert-Match -Text $calls1447b4ff0 -Pattern "1447b515f -> 1447c74e0" -Label "1447b4ff0 should also drive the second mid-owner preview wrapper"
Assert-Match -Text $calls1447b4ff0 -Pattern "1447b45de <- FUN_1447b4290 @ 1447b4290" -Label "1447b4ff0 should be owned by the next higher preview owner"

Assert-Match -Text $calls1447c74e0 -Pattern "1447c782d -> 1447c7b70" -Label "1447c74e0 should drive the first lower preview-owner branch"
Assert-Match -Text $calls1447c74e0 -Pattern "1447c78a4 -> 1447c7b70" -Label "1447c74e0 should reuse the first lower preview-owner branch in a second phase"
Assert-Match -Text $calls1447c74e0 -Pattern "1447c7ae4 -> 1447c8920" -Label "1447c74e0 should also delegate into the sibling lower preview-owner branch"
Assert-Match -Text $calls1447c74e0 -Pattern "1447b515f <- FUN_1447b4ff0 @ 1447b4ff0" -Label "1447c74e0 should be owned by the higher preview owner"

Assert-Match -Text $calls1447c8920 -Pattern "1447c897f -> 1447c65e0" -Label "1447c8920 should fall back into the first mid-owner preview wrapper"
Assert-Match -Text $calls1447c8b00 -Pattern "1447c8bd3 -> 1447c65e0" -Label "1447c8b00 should also fall back into the first mid-owner preview wrapper"

Assert-Match -Text $calls1447b4290 -Pattern "1447b45de -> 1447b4ff0" -Label "1447b4290 should be the next higher owner above the preview-owner split"

Assert-Match -Text $xrefs1447b4ff0 -Pattern "FUN_1447b4290 @ 1447b4290" -Label "1447b4ff0 xrefs should include the next higher preview owner"
Assert-Match -Text $xrefs1447c74e0 -Pattern "FUN_1447b4ff0 @ 1447b4ff0" -Label "1447c74e0 xrefs should include the higher preview owner"

Assert-Match -Text $window1447b509f -Pattern "MOV RDI,qword ptr \[RCX \+ 0x8a8\]" -Label "1447b4ff0 should begin by reading its retained preview object slot"
Assert-Match -Text $window1447b509f -Pattern "CMP byte ptr \[RSI \+ 0x170\],0x3" -Label "1447b4ff0 should gate on the same preview-side state byte before the first mid-owner branch"
Assert-Match -Text $window1447b509f -Pattern "MOVZX EAX,byte ptr \[RSI \+ 0xac4\]" -Label "1447b4ff0 should stage the first preview option byte for the first mid-owner branch"
Assert-Match -Text $window1447b509f -Pattern "MOVZX EAX,byte ptr \[RSI \+ 0xac5\]" -Label "1447b4ff0 should stage the second preview option byte for the first mid-owner branch"
Assert-Match -Text $window1447b509f -Pattern "LEA RDX,\[RSP \+ 0x40\]" -Label "1447b4ff0 should pass the first staged local request block by address"
Assert-Match -Text $window1447b509f -Pattern "LEA R8,\[RSP \+ 0x30\]" -Label "1447b4ff0 should pass the paired local result/status block by address"
Assert-Match -Text $window1447b509f -Pattern "CALL 0x1447c65e0" -Label "1447b4ff0 should dispatch into the first mid-owner preview wrapper"
Assert-Match -Text $window1447b509f -Pattern "MOV qword ptr \[RSI \+ 0xd50\],RBX" -Label "1447b4ff0 should retain the first mid-owner result on its owner state"
Assert-Match -Text $window1447b509f -Pattern "VMOVUPS xmmword ptr \[RSI \+ 0xd58\],XMM0" -Label "1447b4ff0 should also retain the associated preview vector payload"

Assert-Match -Text $window1447b515f -Pattern "MOV RCX,RSI" -Label "1447b4ff0 should call the second mid-owner wrapper with itself as owner/context"
Assert-Match -Text $window1447b515f -Pattern "CALL 0x1447c74e0" -Label "1447b4ff0 should dispatch into the second mid-owner preview wrapper"
Assert-Match -Text $window1447b515f -Pattern "CMP RBX,qword ptr \[RSI \+ 0x8a8\]" -Label "1447b4ff0 should compare the retained preview object after the second branch"
Assert-Match -Text $window1447b515f -Pattern "MOV byte ptr \[RSI \+ 0xac5\],0x0" -Label "1447b4ff0 should clear the second preview option byte when the retained object changes"

Write-Host "PASS test-prefab-preview-higher-owner-hierarchy"
