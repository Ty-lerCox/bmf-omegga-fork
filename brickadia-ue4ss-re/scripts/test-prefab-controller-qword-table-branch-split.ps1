$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-controller-qword-table-branch-split-test"

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

$qwords146cb1900 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpQwords.java" `
  -Arguments @("146cb1910", "7") `
  -OutputFile (Join-Path $tempRoot "qwords-146cb1910.txt")

$calls144815870 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144815870") `
  -OutputFile (Join-Path $tempRoot "calls-144815870.txt")

$calls1448156d0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1448156d0") `
  -OutputFile (Join-Path $tempRoot "calls-1448156d0.txt")

$calls144819060 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("144819060") `
  -OutputFile (Join-Path $tempRoot "calls-144819060.txt")

$calls1448193b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1448193b0") `
  -OutputFile (Join-Path $tempRoot "calls-1448193b0.txt")

$window1448157de = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1448157de", "60") `
  -OutputFile (Join-Path $tempRoot "window-1448157de.txt")

Assert-Match -Text $qwords146cb1900 -Pattern "146cb1910 -> 14481ae60" -Label "the controller-family qword block should start with the native ServerPastePrefab implementation"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1938 -> 144815870" -Label "the controller-family qword block should include the higher submit orchestrator"
Assert-Match -Text $qwords146cb1900 -Pattern "146cb1940 -> 1448156d0" -Label "the controller-family qword block should include the shared-seam helper sibling"

Assert-Match -Text $calls144815870 -Pattern "144815ba0 -> 142955470" -Label "144815870 should resolve the shared owner/context seam"
Assert-Match -Text $calls144815870 -Pattern "144816db3 -> 1443fa1e0" -Label "144815870 should submit through the first known handoff site"
Assert-Match -Text $calls144815870 -Pattern "1448177b7 -> 1443fa1e0" -Label "144815870 should submit through the second known handoff site"

Assert-Match -Text $calls1448156d0 -Pattern "1448157de -> 142955470" -Label "1448156d0 should also enter the shared owner/context seam"
Assert-Match -Text $calls1448156d0 -Pattern "144815811 -> 144619190" -Label "1448156d0 should diverge into the post-seam helper lane instead of direct submit"
Assert-Match -Text $calls1448156d0 -Pattern "14481582e -> 144661420" -Label "1448156d0 should continue through the helper/build lane after the seam"
Assert-Match -Text $calls1448156d0 -Pattern "14481583c -> 14440aa50" -Label "1448156d0 should finish through a writer/apply helper after the seam"
Assert-NotMatch -Text $calls1448156d0 -Pattern "1443fa1e0" -Label "1448156d0 should not directly submit through 1443fa1e0"

Assert-Match -Text $window1448157de -Pattern "ADD RDI,0x820" -Label "1448156d0 should rebase through the same +0x820 owner/context block"
Assert-Match -Text $window1448157de -Pattern "MOV RCX,RDI" -Label "1448156d0 should pass that rebased block as RCX"
Assert-Match -Text $window1448157de -Pattern "CALL 0x142955470" -Label "1448156d0 should resolve the shared seam before diverging"
Assert-Match -Text $window1448157de -Pattern "CALL 0x1441bd030" -Label "1448156d0 should peel into a separate helper immediately after resolving the seam"
Assert-Match -Text $window1448157de -Pattern "CALL 0x144619190" -Label "1448156d0 should drive the post-seam helper lane with the resolved seam object"

Assert-Match -Text $calls144819060 -Pattern "1448191d5 -> 1447f64c0" -Label "144819060 should follow its own sibling branch rather than the shared submit seam"
Assert-Match -Text $calls144819060 -Pattern "14481920f -> 1447f37c0" -Label "144819060 should continue through the same sibling branch family"
Assert-Match -Text $calls144819060 -Pattern "144819217 -> 144602330" -Label "144819060 should terminate through its sibling branch helper"
Assert-NotMatch -Text $calls144819060 -Pattern "142955470" -Label "144819060 should not enter the shared owner/context seam"
Assert-NotMatch -Text $calls144819060 -Pattern "1443fa1e0" -Label "144819060 should not directly submit through 1443fa1e0"

Assert-Match -Text $calls1448193b0 -Pattern "144819465 -> 144840c90" -Label "1448193b0 should follow its own sibling branch rather than the shared submit seam"
Assert-Match -Text $calls1448193b0 -Pattern "14481949b -> 1441707f0" -Label "1448193b0 should feed the preview/notification-style helper family"
Assert-Match -Text $calls1448193b0 -Pattern "1448195b3 -> 1442e1c00" -Label "1448193b0 should continue through its sibling helper lane"
Assert-NotMatch -Text $calls1448193b0 -Pattern "142955470" -Label "1448193b0 should not enter the shared owner/context seam"
Assert-NotMatch -Text $calls1448193b0 -Pattern "1443fa1e0" -Label "1448193b0 should not directly submit through 1443fa1e0"

Write-Host "PASS test-prefab-controller-qword-table-branch-split"
