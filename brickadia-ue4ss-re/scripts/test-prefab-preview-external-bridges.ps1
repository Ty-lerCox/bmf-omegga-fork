$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-external-bridges-test"

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

$xrefs1442a6090 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1442a6090") `
  -OutputFile (Join-Path $tempRoot "xrefs-1442a6090.txt")

$calls144866e40 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144866e40") `
  -OutputFile (Join-Path $tempRoot "calls-144866e40.txt")

$calls14489e260 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14489e260") `
  -OutputFile (Join-Path $tempRoot "calls-14489e260.txt")

$window144866e58 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144866e58", "32") `
  -OutputFile (Join-Path $tempRoot "window-144866e58.txt")

$window14489ebf0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14489ebf0", "96") `
  -OutputFile (Join-Path $tempRoot "window-14489ebf0.txt")

Assert-Match -Text $xrefs1442a6090 -Pattern "FUN_144866e40 @ 144866e40" -Label "1442a6090 should have the small preview-side bridge caller"
Assert-Match -Text $xrefs1442a6090 -Pattern "FUN_14489e260 @ 14489e260" -Label "1442a6090 should have the heavier orchestration-side bridge caller"
Assert-Match -Text $xrefs1442a6090 -Pattern "145c13340 -> no function" -Label "1442a6090 should still remain anchored in the packed preview-family table"

Assert-Match -Text $calls144866e40 -Pattern "144866e58 -> 144864e90" -Label "144866e40 should start from the local preview-side setup helper"
Assert-Match -Text $calls144866e40 -Pattern "144866e6f -> 140237e50" -Label "144866e40 should seed a one-entry local payload carrier before lookup"
Assert-Match -Text $calls144866e40 -Pattern "144866e74 -> 1442a6090" -Label "144866e40 should call the packed preview-family bridge the first time"
Assert-Match -Text $calls144866e40 -Pattern "144866e7c -> 1442a6090" -Label "144866e40 should call the packed preview-family bridge the second time"
Assert-Match -Text $calls144866e40 -Pattern "144866e89 -> 1417ad070" -Label "144866e40 should combine the paired bridge results before dispatch"
Assert-Match -Text $calls144866e40 -Pattern "144866eac -> 1429d7320" -Label "144866e40 should hand the combined result into its downstream consumer"

Assert-Match -Text $window144866e58 -Pattern "LEA RDX,\[0x146cf1f20\]" -Label "144866e40 should seed the local preview-side table carrier"
Assert-Match -Text $window144866e58 -Pattern "CALL 0x1442a6090" -Label "144866e40 window should show direct bridge dispatch"
Assert-Match -Text $window144866e58 -Pattern "MOV RDI,RAX" -Label "144866e40 should retain the first bridge result"
Assert-Match -Text $window144866e58 -Pattern "MOV RDX,qword ptr \[RSP \+ 0x20\]" -Label "144866e40 should feed the local payload carrier into the combiner"
Assert-Match -Text $window144866e58 -Pattern "CALL 0x1417ad070" -Label "144866e40 should combine the paired bridge results"
Assert-Match -Text $window144866e58 -Pattern "CALL 0x1429d7320" -Label "144866e40 should dispatch the combined bridge result"

Assert-Match -Text $calls14489e260 -Pattern "14489ebfe -> 144862ff0" -Label "14489e260 should reacquire its owner/context before the first packed bridge call"
Assert-Match -Text $calls14489e260 -Pattern "14489ec06 -> 1442a6090" -Label "14489e260 should use the packed bridge in the first packaging phase"
Assert-Match -Text $calls14489e260 -Pattern "14489ec6e -> 14059f290" -Label "14489e260 should package the first bridge result into a temporary container"
Assert-Match -Text $calls14489e260 -Pattern "14489ec79 -> 14486b520" -Label "14489e260 should hand the packaged bridge result into the preview-side submit helper"
Assert-Match -Text $calls14489e260 -Pattern "14489ec9d -> 14486bd00" -Label "14489e260 should query a second preview-side state carrier before the second bridge call"
Assert-Match -Text $calls14489e260 -Pattern "14489ecaa -> 1442a6090" -Label "14489e260 should use the packed bridge again in the selection/membership phase"

Assert-Match -Text $window14489ebf0 -Pattern "CALL 0x144862ff0" -Label "14489e260 window should reacquire owner/context before the first bridge call"
Assert-Match -Text $window14489ebf0 -Pattern "CALL 0x1442a6090" -Label "14489e260 window should show the packed bridge call sequence"
Assert-Match -Text $window14489ebf0 -Pattern "MOV qword ptr \[RSP \+ 0x1d0\],RAX" -Label "14489e260 should retain the first bridge result for packaging"
Assert-Match -Text $window14489ebf0 -Pattern "CALL 0x14059f290" -Label "14489e260 should package the first bridge result into a one-entry container"
Assert-Match -Text $window14489ebf0 -Pattern "CALL 0x14486b520" -Label "14489e260 should submit the packaged bridge result through the preview-side helper"
Assert-Match -Text $window14489ebf0 -Pattern "CALL 0x14486bd00" -Label "14489e260 should query a preview-side selection state carrier"
Assert-Match -Text $window14489ebf0 -Pattern "MOVSXD RDX,dword ptr \[RAX \+ 0x38\]" -Label "14489e260 should interpret the second bridge result as an indexed selector entry"
Assert-Match -Text $window14489ebf0 -Pattern "CMP qword ptr \[RCX \+ RDX\*0x8\],RAX" -Label "14489e260 should verify membership against the selected slot table"

Write-Host "PASS test-prefab-preview-external-bridges"
