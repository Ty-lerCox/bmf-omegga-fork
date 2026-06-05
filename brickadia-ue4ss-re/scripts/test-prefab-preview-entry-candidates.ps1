$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ghidraRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC"
$analyzeHeadless = Join-Path $ghidraRoot "support\analyzeHeadless.bat"
$projectRoot = "C:\Users\tycox\Tools\reverse-engineering\ghidra-projects"
$projectName = "BrickadiaCL12960"
$programName = "BrickadiaServer-Win64-Shipping.exe"
$scriptPath = $PSScriptRoot
$tempRoot = Join-Path $env:TEMP "brickadia-prefab-preview-entry-candidates-test"

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

$xrefs1448698b0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1448698b0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1448698b0.txt")

$xrefs1448854e0 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpAddressXrefs.java" `
  -Arguments @("1448854e0") `
  -OutputFile (Join-Path $tempRoot "xrefs-1448854e0.txt")

$window1442a5f70 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("1442a5f70", "40") `
  -OutputFile (Join-Path $tempRoot "window-1442a5f70.txt")

$window144869898 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144869898", "24") `
  -OutputFile (Join-Path $tempRoot "window-144869898.txt")

$window144885434 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144885434", "16") `
  -OutputFile (Join-Path $tempRoot "window-144885434.txt")

$window144885498 = Invoke-GhidraDump `
  -ScriptName "GhidraDumpInstructionWindow.java" `
  -Arguments @("144885498", "40") `
  -OutputFile (Join-Path $tempRoot "window-144885498.txt")

Assert-Match -Text $xrefs1448698b0 -Pattern "FUN_144869890 @ 144869890" -Label "1448698b0 should have a tiny post-wrapper caller"
Assert-Match -Text $xrefs1448698b0 -Pattern "FUN_1442a5f60 @ 1442a5f60" -Label "1448698b0 should have a tiny lease/count wrapper caller"
Assert-Match -Text $xrefs1448854e0 -Pattern "FUN_144885430 @ 144885430" -Label "1448854e0 should have a tiny offset-adjust wrapper"
Assert-Match -Text $xrefs1448854e0 -Pattern "FUN_144885440 @ 144885440" -Label "1448854e0 should have a validated prefab-entry wrapper"

Assert-Match -Text $window1442a5f70 -Pattern "MOV RAX,qword ptr \[RDX \+ 0x20\]" -Label "1442a5f60 should read the small lease/count field before dispatch"
Assert-Match -Text $window1442a5f70 -Pattern "MOV qword ptr \[RDX \+ 0x20\],RAX" -Label "1442a5f60 should update the same lease/count field before dispatch"
Assert-Match -Text $window1442a5f70 -Pattern "JMP 0x1448698b0" -Label "1442a5f60 should tail-jump into the cache-lookup preview wrapper"

Assert-Match -Text $window144869898 -Pattern "CALL 0x1448698b0" -Label "144869890 should delegate into the cache-lookup preview wrapper"
Assert-Match -Text $window144869898 -Pattern "JMP 0x144867a00" -Label "144869890 should follow the cache-lookup wrapper with its local post-step"

Assert-Match -Text $window144885434 -Pattern "ADD RCX,0x20" -Label "144885430 should rebase RCX to the prefab-entry payload before dispatch"
Assert-Match -Text $window144885434 -Pattern "JMP 0x1448854e0" -Label "144885430 should tail-jump into the prefab-entry wrapper"

Assert-Match -Text $window144885498 -Pattern "CALL 0x14008d510" -Label "144885440 should run its first validation step before prefab-entry dispatch"
Assert-Match -Text $window144885498 -Pattern "CALL 0x14053e2a0" -Label "144885440 should query entry state before dispatch"
Assert-Match -Text $window144885498 -Pattern "CALL 0x1448854e0" -Label "144885440 should dispatch through the prefab-entry wrapper"
Assert-Match -Text $window144885498 -Pattern "CALL 0x1404ee2b0" -Label "144885440 should release temporary state after prefab-entry dispatch"

Write-Host "PASS test-prefab-preview-entry-candidates"
