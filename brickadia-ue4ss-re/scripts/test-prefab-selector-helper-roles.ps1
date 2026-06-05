$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-selector-helper-roles-test"

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

$calls1407fffe0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1407fffe0") `
  -OutputFile (Join-Path $tempRoot "calls-1407fffe0.txt")

$calls1403a0af0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1403a0af0") `
  -OutputFile (Join-Path $tempRoot "calls-1403a0af0.txt")

$xrefsHelpers = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1407fffe0", "1403a0af0") `
  -OutputFile (Join-Path $tempRoot "xrefs-helpers.txt")

$window1407fffe0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1407fffe0", "36") `
  -OutputFile (Join-Path $tempRoot "window-1407fffe0.txt")

$window1403a0af0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1403a0af0", "36") `
  -OutputFile (Join-Path $tempRoot "window-1403a0af0.txt")

$window1443c248f = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443c248f", "20") `
  -OutputFile (Join-Path $tempRoot "window-1443c248f.txt")

$window1443c260f = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443c260f", "20") `
  -OutputFile (Join-Path $tempRoot "window-1443c260f.txt")

Assert-Match -Text $xrefsHelpers -Pattern "1443c248f -> FUN_1443c23c0 @ 1443c23c0" -Label "1407fffe0 should be used by the prefab selector growth path"
Assert-Match -Text $xrefsHelpers -Pattern "1443c260f -> FUN_1443c2520 @ 1443c2520" -Label "1403a0af0 should be used by the prefab selector commit path"

Assert-Match -Text $window1443c248f -Pattern "MOV dword ptr \[RDI \+ 0x48\],R8D" -Label "1443c23c0 should update selector-table size before calling 1407fffe0"
Assert-Match -Text $window1443c248f -Pattern "CALL 0x1407fffe0" -Label "1443c23c0 should delegate table growth/reset to 1407fffe0"

Assert-Match -Text $window1407fffe0 -Pattern "LEA RBX,\[RCX \+ 0x40\]" -Label "1407fffe0 should work on the selector table storage rooted at +0x40"
Assert-Match -Text $window1407fffe0 -Pattern "MOV EDI,dword ptr \[RSI \+ 0x48\]" -Label "1407fffe0 should read the selector-table size or mask from +0x48"
Assert-Match -Text $window1407fffe0 -Pattern "CALL 0x14002da20" -Label "1407fffe0 should allocate or clear selector-table storage"

Assert-Match -Text $window1443c260f -Pattern "CALL 0x1403a0af0" -Label "1443c2520 should delegate selector bookkeeping to 1403a0af0 after commit"
Assert-Match -Text $window1443c260f -Pattern "MOV dword ptr \[RDI\],ESI" -Label "1443c2520 should write the committed slot index after bookkeeping"

Assert-Match -Text $window1403a0af0 -Pattern "LEA R10,\[RCX \+ 0x10\]" -Label "1403a0af0 should use the inline selector bitset base at +0x10"
Assert-Match -Text $window1403a0af0 -Pattern "MOV R15,qword ptr \[RAX \+ 0x20\]" -Label "1403a0af0 should consult the optional heap bitset pointer at +0x20"
Assert-Match -Text $window1403a0af0 -Pattern "CMOVZ R15,R10" -Label "1403a0af0 should fall back to the inline bitset when heap storage is absent"
Assert-Match -Text $window1403a0af0 -Pattern "MOV EBP,dword ptr \[R15 \+ R14\*0x4\]" -Label "1403a0af0 should read occupancy words from the selected bitset"
Assert-Match -Text $window1403a0af0 -Pattern "BT EBP,ECX" -Label "1403a0af0 should test selector occupancy bits"

Assert-Match -Text $calls1407fffe0 -Pattern "14002da20" -Label "1407fffe0 should be centered on generic storage management"
Assert-Match -Text $calls1403a0af0 -Pattern "1403a0af0" -Label "1403a0af0 should recurse or chain through the same bookkeeping family"

Write-Host "PASS test-prefab-selector-helper-roles"
