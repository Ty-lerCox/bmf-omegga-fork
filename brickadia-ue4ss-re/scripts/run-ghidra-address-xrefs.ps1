param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
  [string[]]$Addresses,
  [string]$ProjectRoot = 'C:\Users\tycox\Tools\reverse-engineering\ghidra-projects',
  [string]$ProjectName = 'BrickadiaCL12960',
  [string]$ProgramName = 'BrickadiaServer-Win64-Shipping.exe',
  [string]$OutFile = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-address-xrefs-latest.txt',
  [switch]$NoAnalysis = $true
)

$ErrorActionPreference = 'Stop'

if (Test-Path $OutFile) {
  Remove-Item $OutFile -Force
}

$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

$args = @(
  $ProjectRoot,
  $ProjectName,
  '-process', $ProgramName
)

if ($NoAnalysis) {
  $args += '-noanalysis'
}

$args += @(
  '-scriptPath', (Split-Path -Parent $PSCommandPath),
  '-postScript', 'GhidraDumpAddressXrefs.java'
)

$args += $Addresses

& 'C:\Users\tycox\Tools\reverse-engineering\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat' @args 2>&1 | Tee-Object -FilePath $OutFile
