param(
  [string]$RuntimeModsDir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods',
  [string]$ProofOut = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\baseline-chat-proof.jsonl',
  [string]$SourceBundle = 'CL12960'
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$sourceMod = Join-Path $workspaceRoot ("probes\{0}\BaselineChatProof" -f $SourceBundle)
if (!(Test-Path $sourceMod) -and $SourceBundle -ne 'CL12960') {
  $sourceMod = Join-Path $workspaceRoot 'probes\CL12960\BaselineChatProof'
}
$targetMod = Join-Path $RuntimeModsDir 'BaselineChatProof'
$modsTxt = Join-Path $RuntimeModsDir 'mods.txt'
$modsJson = Join-Path $RuntimeModsDir 'mods.json'

if (!(Test-Path $sourceMod)) {
  throw "Chat proof mod source is missing: $sourceMod"
}

New-Item -ItemType Directory -Force -Path $RuntimeModsDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProofOut) | Out-Null
if (Test-Path $targetMod) {
  Remove-Item -Recurse -Force $targetMod
}
Copy-Item -Recurse -Force $sourceMod $targetMod

$mainLua = Join-Path $targetMod 'Scripts\main.lua'
$contents = Get-Content -Raw $mainLua
$contents = $contents -replace '__BASELINE_CHAT_PROOF_OUT__', ($ProofOut -replace '\\', '\\')
Set-Content -Path $mainLua -Value $contents -NoNewline

$modsLines = @()
if (Test-Path $modsTxt) {
  $modsLines = Get-Content $modsTxt | Where-Object { $_ -notmatch '^\s*BaselineChatProof\s*:' }
}
$modsLines += 'BaselineChatProof : 1'
Set-Content -Path $modsTxt -Value ($modsLines -join [Environment]::NewLine)

$modsJsonData = @()
if (Test-Path $modsJson) {
  try {
    $modsJsonData = Get-Content -Raw $modsJson | ConvertFrom-Json
  } catch {
    $modsJsonData = @()
  }
}
if ($null -eq $modsJsonData) {
  $modsJsonData = @()
}
if ($modsJsonData -isnot [System.Collections.IEnumerable] -or $modsJsonData -is [string]) {
  $modsJsonData = @()
}

$modsJsonArray = @($modsJsonData)
$chatEntry = $modsJsonArray | Where-Object { $_.mod_name -eq 'BaselineChatProof' } | Select-Object -First 1
if ($null -eq $chatEntry) {
  $modsJsonArray += [pscustomobject]@{
    mod_name = 'BaselineChatProof'
    mod_enabled = $true
  }
} else {
  $chatEntry.mod_enabled = $true
}

$modsJsonArray | ConvertTo-Json -Depth 8 | Set-Content -Path $modsJson -Encoding utf8

Write-Host "Deployed BaselineChatProof to $targetMod"
Write-Host "Proof output path: $ProofOut"
