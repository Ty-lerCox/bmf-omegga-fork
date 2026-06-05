$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-submit-orchestrator-request-builder-split-test"

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

function Assert-NotMatch {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Text -match $Pattern) {
    throw "Assertion failed: $Label"
  }
}

$windowFirstVariant = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144816e12", "180") `
  -OutputFile (Join-Path $tempRoot "window-first-variant.txt")

$windowSecondVariant = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1448177b7", "180") `
  -OutputFile (Join-Path $tempRoot "window-second-variant.txt")

Assert-Match -Text $windowFirstVariant -Pattern "CALL 0x141e439b0" -Label "the richer submit variant should resolve an owner/context-derived helper before request assembly"
Assert-Match -Text $windowFirstVariant -Pattern "CALL 0x144931270" -Label "the richer submit variant should build a first request fragment through FUN_144931270"
Assert-Match -Text $windowFirstVariant -Pattern "CALL 0x1449310d0" -Label "the richer submit variant should also build a second request fragment through FUN_1449310d0"
Assert-Match -Text $windowFirstVariant -Pattern "MOV dword ptr \[RSP \+ 0x3b0\],0x2" -Label "the richer submit variant should stamp an explicit mode/discriminant field into the staged request record"
Assert-Match -Text $windowFirstVariant -Pattern "VMOVSS dword ptr \[RSP \+ 0x3b8\],XMM7" -Label "the richer submit variant should preserve the computed float payload into the staged request record"
Assert-Match -Text $windowFirstVariant -Pattern "MOV RCX,qword ptr \[RDI \+ 0x988\]" -Label "the richer submit variant should still end in the shared thin-submit root"
Assert-Match -Text $windowFirstVariant -Pattern "CALL 0x1443fa1e0" -Label "the richer submit variant should hand off through the known thin-submit bridge"

Assert-Match -Text $windowSecondVariant -Pattern "CALL 0x1449310d0" -Label "the simpler submit variant should still build a request fragment through FUN_1449310d0"
Assert-NotMatch -Text $windowSecondVariant -Pattern "CALL 0x144931270" -Label "the simpler submit variant should not depend on the richer FUN_144931270 request fragment builder"
Assert-NotMatch -Text $windowSecondVariant -Pattern "MOV dword ptr \[RSP \+ 0x3b0\],0x2" -Label "the simpler submit variant should not stamp the richer explicit mode/discriminant field"
Assert-NotMatch -Text $windowSecondVariant -Pattern "VMOVSS dword ptr \[RSP \+ 0x3b8\],XMM7" -Label "the simpler submit variant should not preserve the richer float payload field"
Assert-Match -Text $windowSecondVariant -Pattern "MOV RCX,qword ptr \[RDI \+ 0x988\]" -Label "the simpler submit variant should still end in the shared thin-submit root"
Assert-Match -Text $windowSecondVariant -Pattern "CALL 0x1443fa1e0" -Label "the simpler submit variant should also hand off through the known thin-submit bridge"

Write-Host "PASS test-prefab-submit-orchestrator-request-builder-split"
