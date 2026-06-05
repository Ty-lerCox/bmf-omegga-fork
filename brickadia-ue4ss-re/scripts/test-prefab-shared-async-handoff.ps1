$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-shared-async-handoff-test"

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

$xrefs14439bf90 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439bf90") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439bf90.txt")

$xrefs1443c1260 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1443c1260") `
  -OutputFile (Join-Path $tempRoot "xrefs-1443c1260.txt")

$xrefs14439c090 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439c090") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439c090.txt")

$xrefs14439cf70 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439cf70") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439cf70.txt")

$xrefs14439d280 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439d280") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439d280.txt")

$xrefs14439e190 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439e190") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439e190.txt")

$xrefs14439e280 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439e280") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439e280.txt")

$xrefs14439d370 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439d370") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439d370.txt")

$xrefs14439d4f0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("14439d4f0") `
  -OutputFile (Join-Path $tempRoot "xrefs-14439d4f0.txt")

$window14439c831 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439c831", "18") `
  -OutputFile (Join-Path $tempRoot "window-14439c831.txt")

$window14439bdd9 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14439bdd9", "18") `
  -OutputFile (Join-Path $tempRoot "window-14439bdd9.txt")

$window14473989e = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473989e", "18") `
  -OutputFile (Join-Path $tempRoot "window-14473989e.txt")

$window14473bf24 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473bf24", "18") `
  -OutputFile (Join-Path $tempRoot "window-14473bf24.txt")

Assert-Match -Text $xrefs14439bf90 -Pattern "FUN_14439c410 @ 14439c410" -Label "14439bf90 should be used by 14439c410"
Assert-Match -Text $xrefs14439bf90 -Pattern "FUN_14439bbf0 @ 14439bbf0" -Label "14439bf90 should be used by 14439bbf0"
Assert-Match -Text $xrefs14439bf90 -Pattern "FUN_144739070 @ 144739070" -Label "14439bf90 should be used by 144739070"
Assert-Match -Text $xrefs14439bf90 -Pattern "FUN_14473be00 @ 14473be00" -Label "14439bf90 should be used by 14473be00"

Assert-Match -Text $xrefs1443c1260 -Pattern "FUN_14439bf90 @ 14439bf90" -Label "14439bf90 should be the direct caller into 1443c1260"

Assert-Match -Text $xrefs14439c090 -Pattern "FUN_14439bbf0 @ 14439bbf0" -Label "14439c090 should be installed from 14439bbf0"
Assert-Match -Text $xrefs14439cf70 -Pattern "FUN_14439c410 @ 14439c410" -Label "14439cf70 should be installed from 14439c410"
Assert-Match -Text $xrefs14439d280 -Pattern "FUN_14439c090 @ 14439c090" -Label "14439d280 should be unique to the archive-wrap callback"
Assert-Match -Text $xrefs14439e190 -Pattern "FUN_14439cf70 @ 14439cf70" -Label "14439e190 should be unique to the raw-bytes callback"
Assert-Match -Text $xrefs14439e280 -Pattern "FUN_14439cf70 @ 14439cf70" -Label "14439e280 should be unique to the raw-bytes callback"
Assert-Match -Text $xrefs14439d370 -Pattern "FUN_14439c090 @ 14439c090" -Label "14439d370 should be reached from the archive-wrap callback"
Assert-Match -Text $xrefs14439d370 -Pattern "FUN_14439cf70 @ 14439cf70" -Label "14439d370 should be reached from the raw-bytes callback"
Assert-Match -Text $xrefs14439d4f0 -Pattern "FUN_14439c090 @ 14439c090" -Label "14439d4f0 should be reached from the archive-wrap callback"
Assert-Match -Text $xrefs14439d4f0 -Pattern "FUN_14439cf70 @ 14439cf70" -Label "14439d4f0 should be reached from the raw-bytes callback"

Assert-Match -Text $window14439c831 -Pattern "LEA RAX,\[0x14439cf70\]" -Label "14439c410 should install callback 14439cf70"
Assert-Match -Text $window14439c831 -Pattern "MOV qword ptr \[R14 \+ 0x68\],RAX" -Label "14439c410 should store callback at +0x68"
Assert-Match -Text $window14439c831 -Pattern "CALL 0x14439bf90" -Label "14439c410 should hand off through 14439bf90"

Assert-Match -Text $window14439bdd9 -Pattern "LEA RAX,\[0x14439c090\]" -Label "14439bbf0 should install callback 14439c090"
Assert-Match -Text $window14439bdd9 -Pattern "MOV qword ptr \[R14 \+ 0x48\],RAX" -Label "14439bbf0 should store callback at +0x48"
Assert-Match -Text $window14439bdd9 -Pattern "CALL 0x14439bf90" -Label "14439bbf0 should hand off through 14439bf90"

Assert-Match -Text $window14473989e -Pattern "LEA RAX,\[0x14473be00\]" -Label "144739070 should install callback 14473be00"
Assert-Match -Text $window14473989e -Pattern "MOV qword ptr \[RBX \+ 0x30\],RAX" -Label "144739070 should store callback at +0x30"
Assert-Match -Text $window14473989e -Pattern "CALL 0x14439bf90" -Label "144739070 should hand off through 14439bf90"

Assert-Match -Text $window14473bf24 -Pattern "LEA RAX,\[0x14473c3f0\]" -Label "14473be00 should install callback 14473c3f0"
Assert-Match -Text $window14473bf24 -Pattern "MOV qword ptr \[RBX \+ 0x30\],RAX" -Label "14473be00 should store callback at +0x30"
Assert-Match -Text $window14473bf24 -Pattern "CALL 0x14439bf90" -Label "14473be00 should hand off through 14439bf90"

Write-Host "PASS test-prefab-shared-async-handoff"
