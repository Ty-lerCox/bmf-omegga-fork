param(
  [string]$RuntimeModsDir = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods',
  [string]$ProofOut = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\world-export-context-proof.jsonl',
  [string]$Ue4ssLog = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log',
  [string]$BrickadiaLog = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Logs\Brickadia.log',
  [string]$DeployProofModScript = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\deploy-world-export-context-proof-mod.ps1',
  [string]$BrickadiaExe = 'C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe',
  [string]$UserDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data',
  [string]$GlobalTokenPath = 'C:\Users\tycox\AppData\Roaming\omegga\global_auth_token',
  [string]$StopLiveSamplerScript = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\stop-world-state-live-sampler-server.ps1',
  [string]$Bundle = 'CL12960',
  [int]$DurationSeconds = 35,
  [string]$Map = 'Plate',
  [int]$Port = 7777,
  [int]$ProbeDelayMs = 2500,
  [string]$Keywords = 'brick,grid,owner,entity,component,prefab,region,selection,template,bundle,serializer,manager,world,paste',
  [string]$CandidateClasses = 'GameModeBase,GameStateBase,GameSession,PlayerController,BP_PlayerController_C,BP_PlayerState_C,Tool_Selector_C,BP_ToolPreviewActor_C,BrickGrid,BrickGridActor,BrickGridComponent,BrickGridDynamicActor,Entity_DynamicBrickGrid,BrickBuildingTemplate,BrickGridPreviewActor,BrickGridPreviewActor_C,BP_BrickGrid_C,BRWorldManager,BRWorldSerializer,BrickPrefabs,BRBundleArchive,BRChatCommandWorldSubsystem,ChatCommandWorldSubsystem,BP_ChatCommandWorldSubsystem_C,BRBundleTransferComponent,BRGizmoManagerComponent,BRCharacter'
)

$ErrorActionPreference = 'Stop'

$modsTxt = Join-Path $RuntimeModsDir 'mods.txt'
$modsBackup = Join-Path $RuntimeModsDir 'mods.codex-backup.txt'
$modsJson = Join-Path $RuntimeModsDir 'mods.json'
$modsJsonBackup = Join-Path $RuntimeModsDir 'mods.codex-backup.json'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$bundleSignaturesDir = Join-Path $workspaceRoot ("bundles\{0}\CustomGameConfigs\Brickadia\UE4SS_Signatures" -f $Bundle)
$runtimeSignaturesDir = Join-Path (Split-Path $RuntimeModsDir -Parent) 'UE4SS_Signatures'
$token = (Get-Content -Raw $GlobalTokenPath).Trim()
$script:enabledStateBackups = @()
$originalDelayMs = $env:OMEGGA_UE4SS_WORLD_EXPORT_DELAY_MS
$originalKeywords = $env:OMEGGA_UE4SS_WORLD_EXPORT_KEYWORDS
$originalFindAllClasses = $env:OMEGGA_UE4SS_WORLD_EXPORT_FINDALL_CLASSES

function Backup-EnabledState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ModName
  )

  $enabledPath = Join-Path (Join-Path $RuntimeModsDir $ModName) 'enabled.txt'
  $backupPath = Join-Path $RuntimeModsDir ("{0}.codex-backup.enabled.txt" -f $ModName)
  if (Test-Path $backupPath) {
    Remove-Item $backupPath -Force
  }

  $hadEnabled = Test-Path $enabledPath
  if ($hadEnabled) {
    Copy-Item $enabledPath $backupPath -Force
  }

  $script:enabledStateBackups += [pscustomobject]@{
    EnabledPath = $enabledPath
    BackupPath = $backupPath
    HadEnabled = $hadEnabled
  }
}

function Restore-EnabledStates {
  foreach ($state in $script:enabledStateBackups) {
    if ($state.HadEnabled) {
      if (Test-Path $state.BackupPath) {
        Move-Item $state.BackupPath $state.EnabledPath -Force
      }
    } else {
      if (Test-Path $state.EnabledPath) {
        Remove-Item $state.EnabledPath -Force
      }
      if (Test-Path $state.BackupPath) {
        Remove-Item $state.BackupPath -Force
      }
    }
  }
}

if ([string]::IsNullOrWhiteSpace($token)) {
  throw "Global auth token is empty: $GlobalTokenPath"
}

if (!(Test-Path $DeployProofModScript)) {
  throw "Missing world export proof deploy script: $DeployProofModScript"
}

if (!(Test-Path $BrickadiaExe)) {
  throw "Missing Brickadia server binary: $BrickadiaExe"
}

if (Test-Path $StopLiveSamplerScript) {
  try {
    & $StopLiveSamplerScript | Out-Null
    Start-Sleep -Seconds 1
  } catch {
  }
}

New-Item -ItemType Directory -Force -Path $runtimeSignaturesDir | Out-Null
if (Test-Path $bundleSignaturesDir) {
  Copy-Item -Path (Join-Path $bundleSignaturesDir '*') -Destination $runtimeSignaturesDir -Force
}

if (Test-Path $modsTxt) {
  Copy-Item $modsTxt $modsBackup -Force
}
if (Test-Path $modsJson) {
  Copy-Item $modsJson $modsJsonBackup -Force
}

try {
  $env:OMEGGA_UE4SS_WORLD_EXPORT_DELAY_MS = [string]$ProbeDelayMs
  $env:OMEGGA_UE4SS_WORLD_EXPORT_KEYWORDS = $Keywords
  $env:OMEGGA_UE4SS_WORLD_EXPORT_FINDALL_CLASSES = $CandidateClasses

  & $DeployProofModScript -RuntimeModsDir $RuntimeModsDir -ProofOut $ProofOut -SourceBundle $Bundle | Out-Null
  Set-Content -Path $modsTxt -Value 'WorldExportContextProof : 1' -Encoding utf8
  @(
    [pscustomobject]@{ mod_name = 'WorldExportContextProof'; mod_enabled = $true }
    [pscustomobject]@{ mod_name = 'OmeggaBridge'; mod_enabled = $false }
    [pscustomobject]@{ mod_name = 'OmeggaBridgeProbe'; mod_enabled = $false }
    [pscustomobject]@{ mod_name = 'BaselineObjectProof'; mod_enabled = $false }
    [pscustomobject]@{ mod_name = 'BaselineChatProof'; mod_enabled = $false }
    [pscustomobject]@{ mod_name = 'CounterBroadcastDemo'; mod_enabled = $false }
  ) | ConvertTo-Json -Depth 8 | Set-Content -Path $modsJson -Encoding utf8

  foreach ($modName in @('WorldExportContextProof', 'BaselineObjectProof', 'BaselineChatProof', 'CounterBroadcastDemo', 'OmeggaBridge', 'OmeggaBridgeProbe')) {
    Backup-EnabledState -ModName $modName
  }

  foreach ($modName in @('BaselineObjectProof', 'BaselineChatProof', 'CounterBroadcastDemo', 'OmeggaBridge', 'OmeggaBridgeProbe')) {
    $disabledEnabledPath = Join-Path (Join-Path $RuntimeModsDir $modName) 'enabled.txt'
    if (Test-Path $disabledEnabledPath) {
      Remove-Item $disabledEnabledPath -Force
    }
  }

  $proofEnabledPath = Join-Path (Join-Path $RuntimeModsDir 'WorldExportContextProof') 'enabled.txt'
  Set-Content -Path $proofEnabledPath -Value '' -Encoding ascii

  foreach ($path in @($ProofOut, $Ue4ssLog, $BrickadiaLog)) {
    if (Test-Path $path) {
      Remove-Item $path -Force
    }
  }

  $argList = @(
    "-Environment=`"$Map`"",
    '-NotInstalled',
    '-stdout',
    '-FullStdOutLogOutput',
    '-log',
    "-UserDir=`"$UserDir`"",
    "-Token=`"$token`"",
    "-port=`"$Port`""
  )

  $proc = Start-Process -FilePath $BrickadiaExe -ArgumentList $argList -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds $DurationSeconds

  if (!$proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
  }

  [pscustomobject]@{
    ProofOutExists = Test-Path $ProofOut
    Ue4ssLogExists = Test-Path $Ue4ssLog
    BrickadiaLogExists = Test-Path $BrickadiaLog
    RuntimeModsDir = $RuntimeModsDir
    ProofOut = $ProofOut
    Ue4ssLog = $Ue4ssLog
    BrickadiaLog = $BrickadiaLog
    ProbeDelayMs = $ProbeDelayMs
    Keywords = $Keywords
    CandidateClasses = $CandidateClasses
  } | ConvertTo-Json -Compress
}
finally {
  if ($null -eq $originalDelayMs) {
    Remove-Item Env:OMEGGA_UE4SS_WORLD_EXPORT_DELAY_MS -ErrorAction SilentlyContinue
  } else {
    $env:OMEGGA_UE4SS_WORLD_EXPORT_DELAY_MS = $originalDelayMs
  }

  if ($null -eq $originalKeywords) {
    Remove-Item Env:OMEGGA_UE4SS_WORLD_EXPORT_KEYWORDS -ErrorAction SilentlyContinue
  } else {
    $env:OMEGGA_UE4SS_WORLD_EXPORT_KEYWORDS = $originalKeywords
  }

  if ($null -eq $originalFindAllClasses) {
    Remove-Item Env:OMEGGA_UE4SS_WORLD_EXPORT_FINDALL_CLASSES -ErrorAction SilentlyContinue
  } else {
    $env:OMEGGA_UE4SS_WORLD_EXPORT_FINDALL_CLASSES = $originalFindAllClasses
  }

  Restore-EnabledStates
  if (Test-Path $modsBackup) {
    Move-Item $modsBackup $modsTxt -Force
  }
  if (Test-Path $modsJsonBackup) {
    Move-Item $modsJsonBackup $modsJson -Force
  }
}
