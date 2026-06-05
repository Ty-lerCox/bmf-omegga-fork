$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-packed-family-owner-shape-test"

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

$window1447b72b8 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1447b72b8", "80") `
  -OutputFile (Join-Path $tempRoot "window-1447b72b8.txt")

$window1447b7379 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1447b7379", "80") `
  -OutputFile (Join-Path $tempRoot "window-1447b7379.txt")

Assert-Match -Text $window1447b72b8 -Pattern "LEA RBX,\[RCX \+ 0x648\]" -Label "1447b71b0 should anchor the same owner-side object slot family at +0x648"
Assert-Match -Text $window1447b72b8 -Pattern "CALL 0x144844100" -Label "1447b71b0 should dispatch through the nearby packed-family bridge first"
Assert-Match -Text $window1447b72b8 -Pattern "MOV R13,qword ptr \[RDI \+ 0x840\]" -Label "1447b71b0 should retain the same owner-side preview object surface at +0x840"
Assert-Match -Text $window1447b72b8 -Pattern "CMP byte ptr \[RDI \+ 0x851\],0x1" -Label "1447b71b0 should gate the selector-validated branch on owner flag +0x851"
Assert-Match -Text $window1447b72b8 -Pattern "CALL 0x144266c20" -Label "1447b71b0 should resolve the preview-adjacent selector object before the owner-side apply helper"
Assert-Match -Text $window1447b72b8 -Pattern "CALL 0x14480da80" -Label "1447b71b0 should hand the validated selector object into the adjacent preview-side helper"

Assert-Match -Text $window1447b7379 -Pattern "CMP RSI,qword ptr \[RDI \+ 0x2e0\]" -Label "1447b71b0 should compare the selected object against an owner-retained surface at +0x2e0"
Assert-Match -Text $window1447b7379 -Pattern "VADDSS XMM0,XMM6,dword ptr \[RDI \+ 0x854\]" -Label "1447b71b0 should fold owner threshold state from +0x854 into the later distance gate"
Assert-Match -Text $window1447b7379 -Pattern "VMOVSS XMM1,dword ptr \[RDI \+ 0x858\]" -Label "1447b71b0 should also use the paired owner threshold slot at +0x858"
Assert-Match -Text $window1447b7379 -Pattern "MOV RCX,RDI" -Label "1447b71b0 should continue treating RDI as the packed-family owner/context across the later gate"

Write-Host "PASS test-prefab-preview-packed-family-owner-shape"
