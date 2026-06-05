$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-wrapper-family-test"

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

$xrefs144867650 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("144867650") `
  -OutputFile (Join-Path $tempRoot "xrefs-144867650.txt")

$calls1448698b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1448698b0") `
  -OutputFile (Join-Path $tempRoot "calls-1448698b0.txt")

$xrefs1448698b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1448698b0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1448698b0.txt")

$window14486999c = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14486999c", "40") `
  -OutputFile (Join-Path $tempRoot "window-14486999c.txt")

$window144885582 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144885582", "48") `
  -OutputFile (Join-Path $tempRoot "window-144885582.txt")

$window144867604 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144867604", "40") `
  -OutputFile (Join-Path $tempRoot "window-144867604.txt")

Assert-Match -Text $xrefs144867650 -Pattern "FUN_144867490 @ 144867490" -Label "144867650 should have a local packaging wrapper caller"
Assert-Match -Text $xrefs144867650 -Pattern "FUN_1448854e0 @ 1448854e0" -Label "144867650 should have a prefab-entry wrapper caller"
Assert-Match -Text $xrefs144867650 -Pattern "FUN_1448698b0 @ 1448698b0" -Label "144867650 should have a cache-lookup wrapper caller"

Assert-Match -Text $xrefs1448698b0 -Pattern "FUN_144869890 @ 144869890" -Label "1448698b0 should be reachable through a tiny tail wrapper"
Assert-Match -Text $xrefs1448698b0 -Pattern "FUN_1442a5f60 @ 1442a5f60" -Label "1448698b0 should also have a higher non-local caller family"
Assert-Match -Text $calls1448698b0 -Pattern "14439ce60" -Label "1448698b0 should perform prefab-cache lookup by hash"

Assert-Match -Text $window14486999c -Pattern "CALL 0x14439ce60" -Label "1448698b0 should resolve a prefab cache entry before preview staging"
Assert-Match -Text $window14486999c -Pattern "MOV RCX,qword ptr \[RAX \+ 0xf0\]" -Label "1448698b0 should pull the archive-backed object from the cache entry"
Assert-Match -Text $window14486999c -Pattern "MOV qword ptr \[RSI \+ 0x1b0\],RCX" -Label "1448698b0 should seed the preview runner's payload slot at +0x1b0"
Assert-Match -Text $window14486999c -Pattern "JMP 0x144867650" -Label "1448698b0 should tail-jump into the shared preview runner"

Assert-Match -Text $window144885582 -Pattern "MOV RAX,qword ptr \[RSI \+ 0xf0\]" -Label "1448854e0 should extract the archive-backed object from a prefab entry"
Assert-Match -Text $window144885582 -Pattern "MOV qword ptr \[RCX \+ 0x1b0\],RAX" -Label "1448854e0 should seed the same preview payload slot at +0x1b0"
Assert-Match -Text $window144885582 -Pattern "CALL 0x144867650" -Label "1448854e0 should dispatch into the shared preview runner after seeding +0x1b0"

Assert-Match -Text $window144867604 -Pattern "CMP byte ptr \[RDI \+ 0x38\],0x1" -Label "144867490 should gate its preview dispatch on a wrapper mode byte"
Assert-Match -Text $window144867604 -Pattern "CALL 0x144867650" -Label "144867490 should conditionally dispatch into the shared preview runner"
Assert-Match -Text $window144867604 -Pattern "CALL 0x144867a00" -Label "144867490 should follow preview dispatch with its own local post-step"

Write-Host "PASS test-prefab-preview-wrapper-family"
