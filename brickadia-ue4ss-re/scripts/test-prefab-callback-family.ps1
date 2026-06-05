$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-callback-family-test"

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

$xrefs146db2880 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("146db2880") `
  -OutputFile (Join-Path $tempRoot "xrefs-146db2880.txt")

$window1448b4bdb = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1448b4bdb", "40") `
  -OutputFile (Join-Path $tempRoot "window-1448b4bdb.txt")

$window144739859 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144739859", "40") `
  -OutputFile (Join-Path $tempRoot "window-144739859.txt")

$window14473bee2 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473bee2", "40") `
  -OutputFile (Join-Path $tempRoot "window-14473bee2.txt")

Assert-Match -Text $xrefs146db2880 -Pattern "FUN_1448b3ff0 @ 1448b3ff0" -Label "146db2880 should be used by 1448b3ff0"
Assert-Match -Text $xrefs146db2880 -Pattern "FUN_144739070 @ 144739070" -Label "146db2880 should be used by 144739070"
Assert-Match -Text $xrefs146db2880 -Pattern "FUN_14473be00 @ 14473be00" -Label "146db2880 should be used by 14473be00"

Assert-Match -Text $window1448b4bdb -Pattern "LEA RAX,\[0x1448b5100\]" -Label "1448b3ff0 should install callback 1448b5100"
Assert-Match -Text $window1448b4bdb -Pattern "MOV qword ptr \[R14 \+ 0x30\],RAX" -Label "1448b3ff0 should store callback at +0x30"

Assert-Match -Text $window144739859 -Pattern "LEA RAX,\[0x146db2880\]" -Label "144739070 should swap to callback vtable 146db2880"
Assert-Match -Text $window144739859 -Pattern "LEA RAX,\[0x14473be00\]" -Label "144739070 should install callback 14473be00"
Assert-Match -Text $window144739859 -Pattern "MOV qword ptr \[RBX \+ 0x30\],RAX" -Label "144739070 should store callback at +0x30"

Assert-Match -Text $window14473bee2 -Pattern "LEA RAX,\[0x146db2880\]" -Label "14473be00 should swap to callback vtable 146db2880"
Assert-Match -Text $window14473bee2 -Pattern "LEA RAX,\[0x14473c3f0\]" -Label "14473be00 should install callback 14473c3f0"
Assert-Match -Text $window14473bee2 -Pattern "MOV qword ptr \[RBX \+ 0x30\],RAX" -Label "14473be00 should store callback at +0x30"

Write-Host "PASS test-prefab-callback-family"
