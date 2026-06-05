$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-additive-stage-runner-test"

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

$calls14473cf60 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14473cf60") `
  -OutputFile (Join-Path $tempRoot "calls-14473cf60.txt")

$calls14473cae0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpFunctionCalls.java" `
  -Arguments @("14473cae0") `
  -OutputFile (Join-Path $tempRoot "calls-14473cae0.txt")

$window14473cae0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473cae0", "48") `
  -OutputFile (Join-Path $tempRoot "window-14473cae0.txt")

$window14473d2b9 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473d2b9", "32") `
  -OutputFile (Join-Path $tempRoot "window-14473d2b9.txt")

$window14473d662 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("14473d662", "32") `
  -OutputFile (Join-Path $tempRoot "window-14473d662.txt")

Assert-Match -Text $calls14473cf60 -Pattern "14473cb5f <- FUN_14473cae0 @ 14473cae0" -Label "14473cf60 should be reached only from the additive-stage coordinator"
Assert-Match -Text $calls14473cae0 -Pattern "14486796d <- FUN_144867650 @ 144867650" -Label "14473cae0 should be reached from the PreviewPart additive caller"
Assert-Match -Text $calls14473cae0 -Pattern "1443f7ce9 <- FUN_1443f6f00 @ 1443f6f00" -Label "14473cae0 should be reached from the GlobalGridTarget additive caller"
Assert-Match -Text $calls14473cae0 -Pattern "1446ea5b6 <- FUN_1446ea4c0 @ 1446ea4c0" -Label "14473cae0 should also be reached from the reflected bundle-manager additive callback"

Assert-Match -Text $window14473cae0 -Pattern "CMP qword ptr \[R8\],0x0" -Label "14473cae0 should inspect the first mutually-exclusive additive target slot"
Assert-Match -Text $window14473cae0 -Pattern "CMP qword ptr \[R8 \+ 0x18\],0x0" -Label "14473cae0 should inspect the second mutually-exclusive additive target slot"
Assert-Match -Text $window14473cae0 -Pattern "XOR CL,AL" -Label "14473cae0 should enforce the mutually-exclusive additive target shape"
Assert-Match -Text $window14473cae0 -Pattern "JZ 0x14473cf38" -Label "14473cae0 should reject the additive request when both or neither targets are present"
Assert-Match -Text $window14473cae0 -Pattern "MOV R8,R15" -Label "14473cae0 should forward the original additive target payload into 14473cf60"
Assert-Match -Text $window14473cae0 -Pattern "MOV R9,R14" -Label "14473cae0 should forward the staged params/result block into 14473cf60"
Assert-Match -Text $window14473cae0 -Pattern "CALL 0x14473cf60" -Label "14473cae0 should delegate execution to the additive-stage runner"

Assert-Match -Text $window14473d2b9 -Pattern "CALL 0x1447330c0" -Label "14473cf60 should invoke the prefab serializer/materialization stage"
Assert-Match -Text $window14473d2b9 -Pattern "CALL 0x1442d2920" -Label "14473cf60 should hand off the staged load result after prefab materialization"
Assert-Match -Text $window14473d662 -Pattern "CALL 0x14473d890" -Label "14473cf60 should invoke the shared finalizer after the staged additive work"
Assert-Match -Text $window14473d662 -Pattern "MOV byte ptr \[RSI \+ 0x20\],0x0" -Label "14473cf60 should clear its success/inflight byte before final cleanup"

Write-Host "PASS test-prefab-additive-stage-runner"
