$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-top-owner-table-anchor-test"

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

$calls1447b4290 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447b4290") `
  -OutputFile (Join-Path $tempRoot "calls-1447b4290.txt")

$xrefs1447b4290 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1447b4290") `
  -OutputFile (Join-Path $tempRoot "xrefs-1447b4290.txt")

$window1447b45de = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1447b45de", "80") `
  -OutputFile (Join-Path $tempRoot "window-1447b45de.txt")

$qwords146ba46b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpQwords.java" `
  -Arguments @("146ba46b0", "16") `
  -OutputFile (Join-Path $tempRoot "qwords-146ba46b0.txt")

$dwords147b073b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpDwords.java" `
  -Arguments @("147b073b0", "16") `
  -OutputFile (Join-Path $tempRoot "dwords-147b073b0.txt")

$rangeRefs146ba46b0 = Invoke-GhidraDump `
  -ScriptName "GhidraFindRefsToRange.java" `
  -Arguments @("146ba46b0", "146ba4730") `
  -OutputFile (Join-Path $tempRoot "range-refs-146ba46b0.txt")

$rangeRefs147b073b0 = Invoke-GhidraDump `
  -ScriptName "GhidraFindRefsToRange.java" `
  -Arguments @("147b073b0", "147b073f0") `
  -OutputFile (Join-Path $tempRoot "range-refs-147b073b0.txt")

Assert-Match -Text $calls1447b4290 -Pattern "1447b45de -> 1447b4ff0" -Label "1447b4290 should dispatch into the next higher preview owner"

Assert-Match -Text $xrefs1447b4290 -Pattern "ref 145c1d566 -> no function" -Label "1447b4290 should be referenced by the packed dispatch table"
Assert-Match -Text $xrefs1447b4290 -Pattern "ref 146ba46d0 -> no function" -Label "1447b4290 should also be anchored in the qword dispatch table"
Assert-Match -Text $xrefs1447b4290 -Pattern "ref 147b073cc -> no function" -Label "1447b4290 should also appear in the packed dword candidate table"

Assert-Match -Text $window1447b45de -Pattern "CMP byte ptr \[RSI \+ 0x850\],0x0" -Label "1447b4290 should gate the higher preview owner on its cached-state byte"
Assert-Match -Text $window1447b45de -Pattern "MOV RCX,RSI" -Label "1447b4290 should call the higher preview owner with its retained owner/context"
Assert-Match -Text $window1447b45de -Pattern "VMOVAPS XMM1,XMM6" -Label "1447b4290 should forward the staged preview vector payload into the higher preview owner"
Assert-Match -Text $window1447b45de -Pattern "CALL 0x1447b4ff0" -Label "1447b4290 should directly invoke the higher preview owner"
Assert-Match -Text $window1447b45de -Pattern "CMP byte ptr \[RSI \+ 0x739\],0x1" -Label "1447b4290 should continue into its second gate after the higher preview owner returns"
Assert-Match -Text $window1447b45de -Pattern "CMP byte ptr \[RSI \+ 0x73a\],0x1" -Label "1447b4290 should preserve the paired follow-up gate for the later branch"

Assert-Match -Text $qwords146ba46b0 -Pattern "146ba46d0 -> 1447b4290" -Label "The qword dispatch table should contain 1447b4290 at the expected slot"
Assert-Match -Text $qwords146ba46b0 -Pattern "146ba4700 -> 1447b3aa0" -Label "The same qword dispatch table should keep the adjacent preview-family sibling slot"

Assert-Match -Text $dwords147b073b0 -Pattern "147b073cc -> 047b4290 candidate=1447b4290" -Label "The packed dword candidate table should include 1447b4290"
Assert-Match -Text $dwords147b073b0 -Pattern "147b073e4 -> 047b4ff0 candidate=1447b4ff0" -Label "The packed dword candidate table should keep the next preview owner beside 1447b4290"
Assert-Match -Text $dwords147b073b0 -Pattern "147b073e8 -> 047b54dc candidate=1447b54dc" -Label "The packed dword candidate table should preserve the next sibling entry after 1447b4ff0"
Assert-Match -Text $dwords147b073b0 -Pattern "147b073d8 -> 047b4fd0 candidate=1447b4fd0" -Label "The packed dword candidate table should preserve the nearby preview-family helper cluster"
Assert-Match -Text $dwords147b073b0 -Pattern "147b073dc -> 047b4fea candidate=1447b4fea" -Label "The packed dword candidate table should preserve the trailing helper entry before the higher preview owner"

Assert-Match -Text $rangeRefs146ba46b0 -Pattern "no instruction references found" -Label "The qword dispatch table should be data-only from the instruction-reference side"
Assert-Match -Text $rangeRefs147b073b0 -Pattern "no instruction references found" -Label "The packed dword candidate table should also be data-only from the instruction-reference side"

Write-Host "PASS test-prefab-preview-top-owner-table-anchor"
