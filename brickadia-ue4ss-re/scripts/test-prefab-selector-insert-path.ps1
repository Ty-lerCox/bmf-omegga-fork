$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-selector-insert-path-test"

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

$xrefs1443c23c0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1443c23c0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1443c23c0.txt")

$xrefs1443c2520 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1443c2520") `
  -OutputFile (Join-Path $tempRoot "xrefs-1443c2520.txt")

$window1443c244a = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443c244a", "24") `
  -OutputFile (Join-Path $tempRoot "window-1443c244a.txt")

$window1443c2496 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443c2496", "28") `
  -OutputFile (Join-Path $tempRoot "window-1443c2496.txt")

$window1443c2594 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443c2594", "28") `
  -OutputFile (Join-Path $tempRoot "window-1443c2594.txt")

$window1443c25d6 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443c25d6", "28") `
  -OutputFile (Join-Path $tempRoot "window-1443c25d6.txt")

Assert-Match -Text $xrefs1443c23c0 -Pattern "FUN_14439e310 @ 14439e310" -Label "1443c23c0 should be reached from 14439e310"
Assert-Match -Text $xrefs1443c2520 -Pattern "FUN_1443c23c0 @ 1443c23c0" -Label "1443c2520 should only be reached from 1443c23c0"

Assert-Match -Text $window1443c244a -Pattern "VMOVUPS ymmword ptr \[RBX\],YMM0" -Label "1443c23c0 should stage the 0x20-byte selector record into the temp node"
Assert-Match -Text $window1443c244a -Pattern "MOV qword ptr \[RBX \+ 0x20\],RCX" -Label "1443c23c0 should carry the auxiliary pointer into the temp node"
Assert-Match -Text $window1443c244a -Pattern "MOV dword ptr \[RBX \+ 0x28\],0xffffffff" -Label "1443c23c0 should initialize the selected slot sentinel to -1"
Assert-Match -Text $window1443c244a -Pattern "LEA R9,\[RSP \+ 0x2c\]" -Label "1443c23c0 should pass a stack out-index pointer into 1443c2520"
Assert-Match -Text $window1443c244a -Pattern "CALL 0x1443c2520" -Label "1443c23c0 should delegate slot selection to 1443c2520"
Assert-Match -Text $window1443c244a -Pattern "TEST AL,AL" -Label "1443c23c0 should branch on the selector result flag"

Assert-Match -Text $window1443c2496 -Pattern "MOV dword ptr \[RDI \+ 0x48\],R8D" -Label "1443c23c0 should update the selector table mask/size on the growth path"
Assert-Match -Text $window1443c2496 -Pattern "CALL 0x1407fffe0" -Label "1443c23c0 should trigger table growth when selection fails"
Assert-Match -Text $window1443c2496 -Pattern "MOV dword ptr \[RBX \+ 0x2c\],ECX" -Label "1443c23c0 should cache the ring-probe slot index on the temp node"
Assert-Match -Text $window1443c2496 -Pattern "MOV dword ptr \[RBX \+ 0x28\],R8D" -Label "1443c23c0 should cache the current selector-table slot value on the temp node"
Assert-Match -Text $window1443c2496 -Pattern "MOV dword ptr \[R8 \+ RDX\*0x4\],EAX" -Label "1443c23c0 should update the ring slot array with the returned selector index"
Assert-Match -Text $window1443c2496 -Pattern "MOV dword ptr \[RSI\],EAX" -Label "1443c23c0 should write the chosen selector index back to its caller"

Assert-Match -Text $window1443c2594 -Pattern "MOV R10D,dword ptr \[R10 \+ R11\*0x4\]" -Label "1443c2520 should probe its occupancy/bitset words"
Assert-Match -Text $window1443c2594 -Pattern "BT R10D,ESI" -Label "1443c2520 should test the probed selector bit"
Assert-Match -Text $window1443c2594 -Pattern "VMOVUPS YMM0,ymmword ptr \[R11 \+ RDI\*0x1\]" -Label "1443c2520 should compare the staged selector record against an existing slot"
Assert-Match -Text $window1443c2594 -Pattern "VPTEST YMM0,YMM0" -Label "1443c2520 should detect an exact selector-record match"

Assert-Match -Text $window1443c25d6 -Pattern "VMOVUPS ymmword ptr \[R10\],YMM0" -Label "1443c2520 should copy the staged selector record into the chosen slot on success"
Assert-Match -Text $window1443c25d6 -Pattern "MOV qword ptr \[R10 \+ 0x20\],RAX" -Label "1443c2520 should copy the auxiliary pointer into the chosen slot"
Assert-Match -Text $window1443c25d6 -Pattern "CALL 0x1403a0af0" -Label "1443c2520 should finalize bookkeeping on successful slot commit"
Assert-Match -Text $window1443c25d6 -Pattern "MOV dword ptr \[RDI\],ESI" -Label "1443c2520 should write the committed slot index back through the out-index pointer"
Assert-Match -Text $window1443c25d6 -Pattern "MOV AL,0x1" -Label "1443c2520 should return success on committed selector slot insertion"

Write-Host "PASS test-prefab-selector-insert-path"
