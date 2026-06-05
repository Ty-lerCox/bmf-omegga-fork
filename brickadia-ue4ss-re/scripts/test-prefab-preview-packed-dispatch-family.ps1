$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-packed-dispatch-family-test"

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

$dwords145c1d540 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpDwords.java" `
  -Arguments @("145c1d540", "24") `
  -OutputFile (Join-Path $tempRoot "dwords-145c1d540.txt")

$rangeRefs145c1d540 = Invoke-GhidraDump `
  -ScriptName "GhidraFindRefsToRange.java" `
  -Arguments @("145c1d540", "145c1d5a0") `
  -OutputFile (Join-Path $tempRoot "range-refs-145c1d540.txt")

$calls1447b71b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("1447b71b0") `
  -OutputFile (Join-Path $tempRoot "calls-1447b71b0.txt")

Assert-Match -Text $dwords145c1d540 -Pattern "145c1d548 -> 047afe60 candidate=1447afe60" -Label "The packed dispatch-family block should begin with the leading sibling entry"
Assert-Match -Text $dwords145c1d540 -Pattern "145c1d55c -> 047b3aa0 candidate=1447b3aa0" -Label "The packed dispatch-family block should include the first nearby control-family sibling"
Assert-Match -Text $dwords145c1d540 -Pattern "145c1d570 -> 047b71b0 candidate=1447b71b0" -Label "The packed dispatch-family block should include the preview-adjacent sibling"
Assert-Match -Text $dwords145c1d540 -Pattern "145c1d584 -> 047b8110 candidate=1447b8110" -Label "The packed dispatch-family block should include the next higher sibling"
Assert-Match -Text $dwords145c1d540 -Pattern "145c1d598 -> 047b84f0 candidate=1447b84f0" -Label "The packed dispatch-family block should include the trailing sibling in this scanned window"

Assert-Match -Text $rangeRefs145c1d540 -Pattern "no instruction references found" -Label "The packed dispatch-family block should be data-only from the instruction-reference side"

Assert-Match -Text $calls1447b71b0 -Pattern "1447b72b8 -> 144844100" -Label "1447b71b0 should bridge into the nearby higher control/helper family"
Assert-Match -Text $calls1447b71b0 -Pattern "1447b734e -> 144266c20" -Label "1447b71b0 should also touch the preview-adjacent selector object surface"
Assert-Match -Text $calls1447b71b0 -Pattern "1447b7379 -> 14480da80" -Label "1447b71b0 should continue into the adjacent preview-side helper lane"

Write-Host "PASS test-prefab-preview-packed-dispatch-family"
