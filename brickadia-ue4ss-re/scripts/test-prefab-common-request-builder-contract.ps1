$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-common-request-builder-contract-test"

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

$window = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1449310d0", "170") `
  -OutputFile (Join-Path $tempRoot "window-1449310d0.txt")

Assert-Match -Text $window -Pattern "TEST RDX,RDX" -Label "the common request builder should guard on a nullable source pointer"
Assert-Match -Text $window -Pattern "JZ 0x144931106" -Label "the common request builder should branch to a dedicated null-source fallback"
Assert-Match -Text $window -Pattern "MOV RCX,RDX" -Label "the common request builder should first normalize the incoming source pointer directly"
Assert-Match -Text $window -Pattern "1449310e4: CALL 0x14466d2a0" -Label "the common request builder should perform a first low-level extraction/copy from the source"
Assert-Match -Text $window -Pattern "MOV RCX,RDI" -Label "the common request builder should then repeat the copy using the saved source pointer"
Assert-Match -Text $window -Pattern "1449310f1: CALL 0x14466d2a0" -Label "the common request builder should perform a second low-level extraction/copy from the same source"
Assert-Match -Text $window -Pattern "MOV RCX,RSI" -Label "the common request builder should write into the destination object"
Assert-Match -Text $window -Pattern "MOV RDX,RAX" -Label "the common request builder should forward the normalized fragment into the finisher"
Assert-Match -Text $window -Pattern "XOR R8D,R8D" -Label "the common request builder should zero the optional third argument for its finisher in the simple case"
Assert-Match -Text $window -Pattern "1449310ff: CALL 0x144931140" -Label "the common request builder should finish through FUN_144931140"
Assert-Match -Text $window -Pattern "144931106: LEA RDX,\[0x145c563ac\]" -Label "the null-source fallback should load a shared diagnostic/default string"
Assert-Match -Text $window -Pattern "144931110: CALL 0x14002e8e0" -Label "the null-source fallback should report/fill through the shared fallback helper"

Assert-Match -Text $window -Pattern "144931160: TEST RDX,RDX" -Label "the finisher should repeat the same null-source guard for its own richer path"
Assert-Match -Text $window -Pattern "14493117e: CALL 0x14002eaf0" -Label "the finisher should build a first staging string/object before assembly"
Assert-Match -Text $window -Pattern "144931192: CALL 0x14002eaf0" -Label "the finisher should build a second staging string/object before assembly"
Assert-Match -Text $window -Pattern "1449311a2: CALL 0x14481e060" -Label "the finisher should derive an intermediate descriptor/value from the source"
Assert-Match -Text $window -Pattern "1449311b2: CALL 0x142735ef0" -Label "the finisher should extract a secondary source fragment"
Assert-Match -Text $window -Pattern "1449311c2: CALL 0x144931580" -Label "the finisher should normalize that secondary fragment into a staging object"
Assert-Match -Text $window -Pattern "1449311e2: CALL 0x144931460" -Label "the finisher should emit the completed request fragment through FUN_144931460"
Assert-Match -Text $window -Pattern "144931225: LEA RDX,\[0x145c563ac\]" -Label "the finisher should share the same null-source fallback string"
Assert-Match -Text $window -Pattern "14493122f: CALL 0x14002e8e0" -Label "the finisher should share the same null-source fallback helper"

Write-Host "PASS test-prefab-common-request-builder-contract"
