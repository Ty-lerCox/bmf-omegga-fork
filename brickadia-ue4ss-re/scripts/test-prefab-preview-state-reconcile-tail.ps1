$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-state-reconcile-tail-test"

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

function Assert-Count {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][int]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $count = ([regex]::Matches($Text, $Pattern)).Count
  if ($count -ne $Expected) {
    throw "Assertion failed: $Label (expected $Expected, got $count)"
  }
}

$calls14480c390 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14480c390") `
  -OutputFile (Join-Path $tempRoot "calls-14480c390.txt")

$calls14480da80 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14480da80") `
  -OutputFile (Join-Path $tempRoot "calls-14480da80.txt")

$window14480c390 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14480c390", "120") `
  -OutputFile (Join-Path $tempRoot "window-14480c390.txt")

$window14480da80 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14480da80", "120") `
  -OutputFile (Join-Path $tempRoot "window-14480da80.txt")

Assert-Match -Text $calls14480c390 -Pattern "14480d3be <- FUN_14480d300 @ 14480d300" -Label "14480c390 should be entered from its local wrapper/controller family"
Assert-Match -Text $calls14480c390 -Pattern "14480c49b -> 144844100" -Label "14480c390 should feed the shared bridge before entering the preview-state reconcile tail"
Assert-Match -Text $calls14480c390 -Pattern "14480c4ab -> 141e43a80" -Label "14480c390 should start the shared preview-state reconcile tail with 141e43a80"
Assert-Match -Text $calls14480c390 -Pattern "14480c4c4 -> 14298a490" -Label "14480c390 should query the preview-state container through 14298a490"
Assert-Match -Text $calls14480c390 -Pattern "14480c59d -> 14298a980" -Label "14480c390 should drive the shared preview-state action selector through 14298a980"
Assert-Match -Text $calls14480c390 -Pattern "14480c62a -> 144188fc0" -Label "14480c390 should continue into the later preview-side follow-up lane"
Assert-Match -Text $calls14480c390 -Pattern "14480c65c -> 1441707f0" -Label "14480c390 should finish through the later preview-side follow-up lane"

Assert-Match -Text $calls14480da80 -Pattern "1447b7379 <- FUN_1447b71b0 @ 1447b71b0" -Label "14480da80 should currently only be reached from the packed preview-family handler"
Assert-Count -Text $calls14480da80 -Pattern "<-" -Expected 1 -Label "14480da80 should have exactly one caller in the current model"
Assert-Match -Text $calls14480da80 -Pattern "14480dab7 -> 141e43a80" -Label "14480da80 should begin its shared reconcile/build tail with 141e43a80"
Assert-Match -Text $calls14480da80 -Pattern "14480dad0 -> 14298a490" -Label "14480da80 should query the same preview-state container through 14298a490"
Assert-Match -Text $calls14480da80 -Pattern "14480dba7 -> 14298a980" -Label "14480da80 should drive the same preview-state action selector through 14298a980"

Assert-Match -Text $window14480c390 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x8b8\]" -Label "14480c390 should pivot into the preview-state container rooted at +0x8b8"
Assert-Match -Text $window14480c390 -Pattern "LEA RAX,\[0x145c55c50\]" -Label "14480c390 should allocate the shared preview callback shell"
Assert-Match -Text $window14480c390 -Pattern "LEA RAX,\[0x145fc5350\]" -Label "14480c390 should swap in the shared preview callback vtable"
Assert-Match -Text $window14480c390 -Pattern "LEA RAX,\[0x14480c6f0\]" -Label "14480c390 should install the same preview callback continuation"
Assert-Match -Text $window14480c390 -Pattern "LEA RCX,\[0x1462690b0\]" -Label "14480c390 should dispatch preview-state results through the shared result table"

Assert-Match -Text $window14480da80 -Pattern "CMP byte ptr \[RCX \+ 0x8b6\],0x0" -Label "14480da80 should guard the reconcile tail with the +0x8b6 reentry byte"
Assert-Match -Text $window14480da80 -Pattern "MOV RCX,qword ptr \[RSI \+ 0x8b8\]" -Label "14480da80 should use the same preview-state container rooted at +0x8b8"
Assert-Match -Text $window14480da80 -Pattern "LEA RAX,\[0x145c55c50\]" -Label "14480da80 should allocate the shared preview callback shell"
Assert-Match -Text $window14480da80 -Pattern "LEA RAX,\[0x145fc5350\]" -Label "14480da80 should swap in the shared preview callback vtable"
Assert-Match -Text $window14480da80 -Pattern "LEA RAX,\[0x14480c6f0\]" -Label "14480da80 should install the same preview callback continuation as 14480c390"
Assert-Match -Text $window14480da80 -Pattern "LEA RCX,\[0x1462690b0\]" -Label "14480da80 should dispatch preview-state results through the same shared result table"

Write-Host "PASS test-prefab-preview-state-reconcile-tail"
