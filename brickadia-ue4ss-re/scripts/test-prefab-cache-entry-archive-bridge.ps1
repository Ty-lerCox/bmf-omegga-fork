$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-cache-entry-archive-bridge-test"

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

$xrefs14439d370 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439d370") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439d370.txt")

$window14439d370 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439d370", "40") `
  -OutputFile (Join-Path $tempRoot "window-14439d370.txt")

Assert-Match -Text $xrefs14439d370 -Pattern "FUN_14439c090 @ 14439c090" -Label "14439d370 should be reached from the archive-wrap cache-seeding lane"
Assert-Match -Text $xrefs14439d370 -Pattern "FUN_14439cf70 @ 14439cf70" -Label "14439d370 should also be reached from the raw-bytes cache-seeding lane"

Assert-Match -Text $window14439d370 -Pattern "MOV RCX,qword ptr \[RDX \+ 0xf0\]" -Label "14439d370 should pull PrefabArchive from BRPrefabCacheInMemoryPrefab at +0xf0"
Assert-Match -Text $window14439d370 -Pattern "CALL 0x1446cfb60" -Label "14439d370 should derive an archive-backed helper record before handoff"
Assert-Match -Text $window14439d370 -Pattern "MOV qword ptr \[RSP \+ 0x20\],RDI" -Label "14439d370 should stage the downstream working-context pointer on stack"
Assert-Match -Text $window14439d370 -Pattern "ADD RSI,0x38" -Label "14439d370 should advance into the converged working-record region at +0x38"
Assert-Match -Text $window14439d370 -Pattern "MOV RCX,RSI" -Label "14439d370 should pass the working-record region as the destination object"
Assert-Match -Text $window14439d370 -Pattern "CALL 0x141620b50" -Label "14439d370 should inject the archive-derived helper into the converged working-record region"

Write-Host "PASS test-prefab-cache-entry-archive-bridge"
