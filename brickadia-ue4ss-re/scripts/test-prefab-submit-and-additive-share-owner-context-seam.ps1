$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-submit-and-additive-share-owner-context-seam-test"

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

$calls1443fa1e0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1443fa1e0") `
  -OutputFile (Join-Path $tempRoot "calls-1443fa1e0.txt")

$calls1443fa4d0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1443fa4d0") `
  -OutputFile (Join-Path $tempRoot "calls-1443fa4d0.txt")

$calls1443f6f00 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1443f6f00") `
  -OutputFile (Join-Path $tempRoot "calls-1443f6f00.txt")

$window1443fa424 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443fa424", "60") `
  -OutputFile (Join-Path $tempRoot "window-1443fa424.txt")

$window1443fa584 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443fa584", "80") `
  -OutputFile (Join-Path $tempRoot "window-1443fa584.txt")

$window1443f7bb8 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1443f7bb8", "80") `
  -OutputFile (Join-Path $tempRoot "window-1443f7bb8.txt")

Assert-Match -Text $calls1443fa1e0 -Pattern "1448b350c <- FUN_1448b2e30 @ 1448b2e30" -Label "1443fa1e0 should be reached from the thin native submitter 1448b2e30"
Assert-Match -Text $calls1443fa1e0 -Pattern "1448b613e <- FUN_1448b5100 @ 1448b5100" -Label "1443fa1e0 should also be reached from the thin native submitter 1448b5100"
Assert-Match -Text $calls1443fa1e0 -Pattern "1443fa424 -> 1443fa4d0" -Label "1443fa1e0 should hand into the shared submit-side owner/context stage"

Assert-Match -Text $calls1443fa4d0 -Pattern "1443fa584 -> 142955470" -Label "1443fa4d0 should resolve its owner/context through 142955470"
Assert-Match -Text $calls1443fa4d0 -Pattern "1443fa5fa -> 1443fb630" -Label "1443fa4d0 should continue into the submit-side dispatch lane"

Assert-Match -Text $calls1443f6f00 -Pattern "1443f7c1e -> 142955470" -Label "1443f6f00 should use the same owner/context helper as the submit-side stage"
Assert-Match -Text $calls1443f6f00 -Pattern "1443f7ce9 -> 14473cae0" -Label "1443f6f00 should peel off into the additive coordinator after that shared seam"

Assert-Match -Text $window1443fa424 -Pattern "MOV qword ptr \[RDI \+ 0x138\],RSI" -Label "1443fa1e0 should preserve its staging/context object before entering 1443fa4d0"
Assert-Match -Text $window1443fa424 -Pattern "MOV RCX,RDI" -Label "1443fa1e0 should pass the assembled submit context as RCX"
Assert-Match -Text $window1443fa424 -Pattern "CALL 0x1443fa4d0" -Label "1443fa1e0 should enter the shared submit-side owner/context stage"

Assert-Match -Text $window1443fa584 -Pattern "ADD RDI,0x820" -Label "1443fa4d0 should rebase through the +0x820 owner/context block"
Assert-Match -Text $window1443fa584 -Pattern "MOV RCX,RDI" -Label "1443fa4d0 should pass that rebased owner/context as RCX"
Assert-Match -Text $window1443fa584 -Pattern "CALL 0x142955470" -Label "1443fa4d0 should resolve the shared owner/context helper after the +0x820 rebase"
Assert-Match -Text $window1443fa584 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x98\]" -Label "1443fa4d0 should then recover its submit-side record source from +0x98"
Assert-Match -Text $window1443fa584 -Pattern "CALL 0x1443fb1c0" -Label "1443fa4d0 should build the submit-side record after the shared seam"
Assert-Match -Text $window1443fa584 -Pattern "CALL 0x1443fb2e0" -Label "1443fa4d0 should hand the built submit-side record into the submit dispatcher"
Assert-Match -Text $window1443fa584 -Pattern "CALL 0x1443fb630" -Label "1443fa4d0 should finish through the submit-side follow-up lane"

Assert-Match -Text $window1443f7bb8 -Pattern "ADD RDI,0x820" -Label "1443f6f00 should rebase through the same +0x820 owner/context block"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV RCX,RDI" -Label "1443f6f00 should pass that rebased owner/context as RCX"
Assert-Match -Text $window1443f7bb8 -Pattern "CALL 0x142955470" -Label "1443f6f00 should resolve the same owner/context helper after the +0x820 rebase"
Assert-Match -Text $window1443f7bb8 -Pattern "MOV RDX,qword ptr \[RAX \+ 0xf0\]" -Label "1443f6f00 should pull PrefabArchive from the cache entry after the shared seam"
Assert-Match -Text $window1443f7bb8 -Pattern "CALL 0x14473cae0" -Label "1443f6f00 should branch into the additive coordinator after the shared seam"

Write-Host "PASS test-prefab-submit-and-additive-share-owner-context-seam"
