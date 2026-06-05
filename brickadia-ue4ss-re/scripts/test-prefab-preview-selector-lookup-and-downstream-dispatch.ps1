$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-selector-lookup-and-downstream-dispatch-test"

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

$calls1421f4310 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1421f4310") `
  -OutputFile (Join-Path $tempRoot "calls-1421f4310.txt")

$window1421f4310 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1421f4310", "80") `
  -OutputFile (Join-Path $tempRoot "window-1421f4310.txt")

$window144286c80 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144286c80", "80") `
  -OutputFile (Join-Path $tempRoot "window-144286c80.txt")

Assert-Match -Text $calls1421f4310 -Pattern "144844171 <- FUN_144844100 @ 144844100" -Label "1421f4310 should be part of the shared bridge selector contract"
Assert-Match -Text $calls1421f4310 -Pattern "1447b72ce <- FUN_1447b71b0 @ 1447b71b0" -Label "1421f4310 should also be used directly by the packed-family sibling branch"
Assert-Match -Text $calls1421f4310 -Pattern "141e47a50 <- FUN_141e478d0 @ 141e478d0" -Label "1421f4310 should participate in the wider selector family beyond the preview-control lane"

Assert-Match -Text $window1421f4310 -Pattern "LEA RDX,\[RDI \+ 0x68\]" -Label "1421f4310 should use the hash-bucket base at +0x68"
Assert-Match -Text $window1421f4310 -Pattern "MOV R8,qword ptr \[RDI \+ 0x70\]" -Label "1421f4310 should allow an alternate bucket pointer at +0x70"
Assert-Match -Text $window1421f4310 -Pattern "MOV R8D,dword ptr \[RDI \+ 0x78\]" -Label "1421f4310 should use the bucket-mask/count field at +0x78"
Assert-Match -Text $window1421f4310 -Pattern "MOV EDX,dword ptr \[RDX \+ R8\*0x4\]" -Label "1421f4310 should fetch the candidate slot index from the hash bucket table"
Assert-Match -Text $window1421f4310 -Pattern "MOV R8,qword ptr \[RDI \+ 0x50\]" -Label "1421f4310 should use the selector membership bitset override at +0x50"
Assert-Match -Text $window1421f4310 -Pattern "CMP EDX,dword ptr \[RDI \+ 0x58\]" -Label "1421f4310 should validate the slot index against the selector count at +0x58"
Assert-Match -Text $window1421f4310 -Pattern "MOV R8D,dword ptr \[R8 \+ R9\*0x4\]" -Label "1421f4310 should test membership bits for the candidate slot"
Assert-Match -Text $window1421f4310 -Pattern "MOV R8,qword ptr \[RDI \+ 0x30\]" -Label "1421f4310 should use the record table rooted at +0x30"
Assert-Match -Text $window1421f4310 -Pattern "LEA RDX,\[R8 \+ R9\*0x8\]" -Label "1421f4310 should index into a 0x18-byte record table"
Assert-Match -Text $window1421f4310 -Pattern "CMP qword ptr \[R8 \+ R9\*0x8\],R14" -Label "1421f4310 should compare the record key against the requested selector key"
Assert-Match -Text $window1421f4310 -Pattern "MOV EDX,dword ptr \[RDX \+ 0x10\]" -Label "1421f4310 should follow the chained next-slot field at record +0x10 on collision"
Assert-Match -Text $window1421f4310 -Pattern "MOV RAX,qword ptr \[RDX \+ 0x8\]" -Label "1421f4310 should return the record payload pointer from +0x8 on hit"

Assert-Match -Text $window144286c80 -Pattern "MOV RDX,qword ptr \[0x147874be8\]" -Label "144286c80 should begin from a retained global/provider object before downstream dispatch"
Assert-Match -Text $window144286c80 -Pattern "CALL 0x1404dfb20" -Label "144286c80 should resolve its downstream dispatch root through 1404dfb20"
Assert-Match -Text $window144286c80 -Pattern "CALL 0x14037fdf0" -Label "144286c80 should normalize that dispatch root through 14037fdf0"
Assert-Match -Text $window144286c80 -Pattern "TEST byte ptr \[RAX \+ 0xd4\],0x80" -Label "144286c80 should branch on a dispatch-mode/status byte at +0xd4"
Assert-Match -Text $window144286c80 -Pattern "MOV RAX,qword ptr \[RSI\]" -Label "144286c80 should select a virtual path from the owner/context object"
Assert-Match -Text $window144286c80 -Pattern "MOV RAX,qword ptr \[RAX \+ 0x378\]" -Label "144286c80 should use one virtual downstream path at vtable +0x378 in the flagged branch"
Assert-Match -Text $window144286c80 -Pattern "MOV RAX,qword ptr \[RAX \+ 0x280\]" -Label "144286c80 should use the alternate downstream path at vtable +0x280"
Assert-Match -Text $window144286c80 -Pattern "MOV qword ptr \[RSP \+ 0x40\],R14" -Label "144286c80 should preserve the third bridge argument in its downstream stack payload"
Assert-Match -Text $window144286c80 -Pattern "MOV qword ptr \[RSP \+ 0x48\],RDI" -Label "144286c80 should preserve the fourth bridge argument in its downstream stack payload"
Assert-Match -Text $window144286c80 -Pattern "MOV qword ptr \[RSP \+ 0x50\],RCX" -Label "144286c80 should also carry the rebased selector-side owner/context into the downstream payload"
Assert-Match -Text $window144286c80 -Pattern "MOV RCX,RSI" -Label "144286c80 should dispatch using the rebased owner/context as RCX"
Assert-Match -Text $window144286c80 -Pattern "MOV RDX,RBX" -Label "144286c80 should pass the normalized dispatch root as RDX"
Assert-Match -Text $window144286c80 -Pattern "LEA R8,\[RSP \+ 0x30\]" -Label "144286c80 should pass the assembled downstream payload block by address"
Assert-Match -Text $window144286c80 -Pattern "CALL qword ptr \[0x145b61ac8\]" -Label "144286c80 should ultimately invoke the downstream virtual dispatch helper"

Write-Host "PASS test-prefab-preview-selector-lookup-and-downstream-dispatch"
