$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-owner-wrapper-ladder-test"

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

$xrefs14489e260 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14489e260") `
  -OutputFile (Join-Path $tempRoot "xrefs-14489e260.txt")

$calls1447c6030 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447c6030") `
  -OutputFile (Join-Path $tempRoot "calls-1447c6030.txt")

$window1447c61b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1447c61b0", "64") `
  -OutputFile (Join-Path $tempRoot "window-1447c61b0.txt")

$calls1447c65e0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447c65e0") `
  -OutputFile (Join-Path $tempRoot "calls-1447c65e0.txt")

$calls1447c7b70 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447c7b70") `
  -OutputFile (Join-Path $tempRoot "calls-1447c7b70.txt")

$xrefs1447c65e0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1447c65e0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1447c65e0.txt")

$xrefs1447c7b70 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1447c7b70") `
  -OutputFile (Join-Path $tempRoot "xrefs-1447c7b70.txt")

Assert-Match -Text $xrefs14489e260 -Pattern "FUN_1447c6030 @ 1447c6030" -Label "14489e260 should have the stack-packaging preview wrapper caller"
Assert-Match -Text $xrefs14489e260 -Pattern "FUN_1448c8cb0 @ 1448c8cb0" -Label "14489e260 should remain reachable from the first heavier preview-side wrapper"
Assert-Match -Text $xrefs14489e260 -Pattern "FUN_1448c92d0 @ 1448c92d0" -Label "14489e260 should remain reachable from the second heavier preview-side wrapper"

Assert-Match -Text $calls1447c6030 -Pattern "1447c61c5 -> 14489e260" -Label "1447c6030 should directly dispatch into the heavier orchestration bridge"
Assert-Match -Text $calls1447c6030 -Pattern "1447c7325 <- FUN_1447c65e0 @ 1447c65e0" -Label "1447c6030 should be reached from the first higher preview-owner wrapper"
Assert-Match -Text $calls1447c6030 -Pattern "1447c854c <- FUN_1447c7b70 @ 1447c7b70" -Label "1447c6030 should be reached from the second higher preview-owner wrapper"

Assert-Match -Text $window1447c61b0 -Pattern "MOVZX EAX,byte ptr \[RSI \+ 0x10\]" -Label "1447c6030 should start by staging the small mode/flag byte from the source request"
Assert-Match -Text $window1447c61b0 -Pattern "MOV qword ptr \[RSP \+ 0x28\],RCX" -Label "1447c6030 should stage the first pointer-sized request field on the stack"
Assert-Match -Text $window1447c61b0 -Pattern "MOV dword ptr \[RSP \+ 0x38\],ECX" -Label "1447c6030 should stage the small integer request field on the stack"
Assert-Match -Text $window1447c61b0 -Pattern "VMOVUPS ymmword ptr \[RSP \+ 0x48\],YMM0" -Label "1447c6030 should copy the large vector/body payload block onto the stack"
Assert-Match -Text $window1447c61b0 -Pattern "MOV qword ptr \[RSP \+ 0xf8\],RCX" -Label "1447c6030 should stage the late pointer field from the source request"
Assert-Match -Text $window1447c61b0 -Pattern "MOV qword ptr \[RSP \+ 0x100\],RAX" -Label "1447c6030 should stage the first trailer qword from the source request"
Assert-Match -Text $window1447c61b0 -Pattern "MOV byte ptr \[RSP \+ 0x110\],AL" -Label "1447c6030 should stage the final trailer byte from the source request"
Assert-Match -Text $window1447c61b0 -Pattern "LEA RDX,\[RSP \+ 0x20\]" -Label "1447c6030 should pass the fully packed stack request by address"
Assert-Match -Text $window1447c61b0 -Pattern "MOV RCX,RDI" -Label "1447c6030 should preserve the owner/context in RCX for the downstream bridge"
Assert-Match -Text $window1447c61b0 -Pattern "MOV R8D,EBX" -Label "1447c6030 should pass the mode/select flag as the third argument"
Assert-Match -Text $window1447c61b0 -Pattern "CALL 0x14489e260" -Label "1447c6030 should dispatch the packed request into the heavier orchestration bridge"

Assert-Match -Text $calls1447c65e0 -Pattern "1447c7325 -> 1447c6030" -Label "1447c65e0 should delegate into the stack-packaging preview wrapper"
Assert-Match -Text $calls1447c65e0 -Pattern "1447b4ff0 @ 1447b4ff0" -Label "1447c65e0 should be reachable from the older higher preview-owner family"
Assert-Match -Text $calls1447c65e0 -Pattern "FUN_1447c8920 @ 1447c8920" -Label "1447c65e0 should also be reachable from the sibling preview-owner wrapper family"
Assert-Match -Text $calls1447c65e0 -Pattern "FUN_1447c8b00 @ 1447c8b00" -Label "1447c65e0 should remain reachable from the second sibling preview-owner wrapper family"

Assert-Match -Text $calls1447c7b70 -Pattern "1447c854c -> 1447c6030" -Label "1447c7b70 should also delegate into the stack-packaging preview wrapper"
Assert-Match -Text $calls1447c7b70 -Pattern "FUN_1447c74e0 @ 1447c74e0" -Label "1447c7b70 should be reachable from its higher preview-owner wrapper"

Assert-Match -Text $xrefs1447c65e0 -Pattern "FUN_1447b4ff0 @ 1447b4ff0" -Label "1447c65e0 xrefs should include the older higher preview-owner family"
Assert-Match -Text $xrefs1447c65e0 -Pattern "FUN_1447c8920 @ 1447c8920" -Label "1447c65e0 xrefs should include the first sibling preview-owner wrapper"
Assert-Match -Text $xrefs1447c65e0 -Pattern "FUN_1447c8b00 @ 1447c8b00" -Label "1447c65e0 xrefs should include the second sibling preview-owner wrapper"
Assert-Match -Text $xrefs1447c7b70 -Pattern "FUN_1447c74e0 @ 1447c74e0" -Label "1447c7b70 xrefs should include its higher preview-owner wrapper"

Write-Host "PASS test-prefab-preview-owner-wrapper-ladder"
