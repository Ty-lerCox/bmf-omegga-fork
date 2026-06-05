$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-higher-submit-wrapper-shares-owner-context-seam-test"

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

$calls144815870 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144815870") `
  -OutputFile (Join-Path $tempRoot "calls-144815870.txt")

$window144815ba0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144815ba0", "90") `
  -OutputFile (Join-Path $tempRoot "window-144815ba0.txt")

$window144816db3 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144816db3", "90") `
  -OutputFile (Join-Path $tempRoot "window-144816db3.txt")

$window1448177b7 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1448177b7", "90") `
  -OutputFile (Join-Path $tempRoot "window-1448177b7.txt")

Assert-Match -Text $calls144815870 -Pattern "144815ba0 -> 142955470" -Label "144815870 should enter the shared owner/context seam through 142955470"
Assert-Match -Text $calls144815870 -Pattern "144816db3 -> 1443fa1e0" -Label "144815870 should issue a first submit-side handoff through 1443fa1e0"
Assert-Match -Text $calls144815870 -Pattern "1448177b7 -> 1443fa1e0" -Label "144815870 should issue a second submit-side handoff through 1443fa1e0"

Assert-Match -Text $window144815ba0 -Pattern "ADD RSI,0x820" -Label "144815870 should rebase into the same +0x820 owner/context block as the thinner submit/additive lanes"
Assert-Match -Text $window144815ba0 -Pattern "MOV RCX,RSI" -Label "144815870 should pass that rebased owner/context block as RCX"
Assert-Match -Text $window144815ba0 -Pattern "CALL 0x142955470" -Label "144815870 should resolve the shared owner/context seam before submit orchestration"
Assert-Match -Text $window144815ba0 -Pattern "MOV R15,RAX" -Label "144815870 should retain the resolved owner/context object"
Assert-Match -Text $window144815ba0 -Pattern "ADD RDI,0x290" -Label "144815870 should pivot into an owner-context-local state block after the seam"
Assert-Match -Text $window144815ba0 -Pattern "MOV R14D,dword ptr \[R15 \+ 0x2a8\]" -Label "144815870 should source owner-controlled selector/count state from the resolved seam object"
Assert-Match -Text $window144815ba0 -Pattern "MOV RCX,qword ptr \[R15 \+ 0x2a0\]" -Label "144815870 should consult an owner-controlled table pointer from the resolved seam object"

Assert-Match -Text $window144816db3 -Pattern "MOV RCX,qword ptr \[RDI \+ 0x988\]" -Label "the first submit handoff should use the owner-local submit root from +0x988"
Assert-Match -Text $window144816db3 -Pattern "MOV RDX,R15" -Label "the first submit handoff should carry the staged request object in RDX"
Assert-Match -Text $window144816db3 -Pattern "MOV R8B,0x1" -Label "the first submit handoff should set the same submit mode byte"
Assert-Match -Text $window144816db3 -Pattern "XOR R9D,R9D" -Label "the first submit handoff should clear the final flag/register argument"
Assert-Match -Text $window144816db3 -Pattern "CALL 0x1443fa1e0" -Label "the first higher-wrapper submit site should enter the known submit bridge"

Assert-Match -Text $window1448177b7 -Pattern "MOV RCX,qword ptr \[RDI \+ 0x988\]" -Label "the second submit handoff should reuse the same owner-local submit root from +0x988"
Assert-Match -Text $window1448177b7 -Pattern "MOV RDX,R15" -Label "the second submit handoff should also carry a staged request object in RDX"
Assert-Match -Text $window1448177b7 -Pattern "MOV R8B,0x1" -Label "the second submit handoff should reuse the same submit mode byte"
Assert-Match -Text $window1448177b7 -Pattern "XOR R9D,R9D" -Label "the second submit handoff should also clear the final flag/register argument"
Assert-Match -Text $window1448177b7 -Pattern "CALL 0x1443fa1e0" -Label "the second higher-wrapper submit site should enter the same known submit bridge"

Write-Host "PASS test-prefab-higher-submit-wrapper-shares-owner-context-seam"
