$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-global-gridtarget-cache-entry-archive-bridge-test"

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

$window1443f7bb8 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443f7bb8", "110") `
  -OutputFile (Join-Path $tempRoot "window-1443f7bb8.txt")

Assert-Match -Text $calls1443f6f00 -Pattern "1443f7bb8 -> 142959410" -Label "1443f6f00 should resolve its first additive-side owner/context through 142959410"
Assert-Match -Text $calls1443f6f00 -Pattern "1443f7bc0 -> 144734d70" -Label "1443f6f00 should resolve the first selector candidate through 144734d70"
Assert-Match -Text $calls1443f6f00 -Pattern "1443f7bea -> 144734d70" -Label "1443f6f00 should re-run selector resolution before committing the candidate"
Assert-Match -Text $calls1443f6f00 -Pattern "1443f7c1e -> 142955470" -Label "1443f6f00 should rebase into the additive owner/context through 142955470"
Assert-Match -Text $calls1443f6f00 -Pattern "1443f7ce9 -> 14473cae0" -Label "1443f6f00 should hand the built request into the shared additive coordinator"

Assert-Match -Text $window1443f7bb8 -Pattern "CALL 0x142959410" -Label "1443f6f00 should begin its additive handoff by resolving an owner/context root"
Assert-Match -Text $window1443f7bb8 -Pattern "CALL 0x144734d70" -Label "1443f6f00 should resolve a selector candidate through 144734d70 before additive launch"
Assert-Match -Text $window1443f7bb8 -Pattern "ADD RDI,0x820" -Label "1443f6f00 should rebase the owner/context through the +0x820 additive-state block"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV RCX,RDI" -Label "1443f6f00 should pass the rebased additive owner/context as RCX"
Assert-Match -Text $window1443f7bb8 -Pattern "CALL 0x142955470" -Label "1443f6f00 should normalize the rebased additive owner/context through 142955470"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV RAX,qword ptr \[R15 \+ 0x18\]" -Label "1443f6f00 should source a cached prefab/cache-entry object from +0x18"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV RDX,qword ptr \[RAX \+ 0xf0\]" -Label "1443f6f00 should pull PrefabArchive from the cache entry at +0xf0"
Assert-Match -Text $window1443f7bb8 -Pattern "LEA R8,\[RSP \+ 0xd0\]" -Label "1443f6f00 should stage the GlobalGridTarget params block at [RSP+0xd0]"
Assert-Match -Text $window1443f7bb8 -Pattern "LEA R9,\[RSP \+ 0x70\]" -Label "1443f6f00 should stage the additive result/work block at [RSP+0x70]"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV byte ptr \[RSP \+ 0xf4\],AL" -Label "1443f6f00 should materialize the first GlobalGridTarget policy byte into the additive params block"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV byte ptr \[RSP \+ 0xf5\],AL" -Label "1443f6f00 should materialize the second GlobalGridTarget policy byte into the additive params block"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV byte ptr \[RSP \+ 0xf6\],AL" -Label "1443f6f00 should materialize the third GlobalGridTarget policy byte into the additive params block"
Assert-Match -Text $window1443f7bb8 -Pattern "CALL 0x14473cae0" -Label "1443f6f00 should send PrefabArchive plus GlobalGridTarget params into the shared additive coordinator"

Write-Host "PASS test-prefab-global-gridtarget-cache-entry-archive-bridge"
