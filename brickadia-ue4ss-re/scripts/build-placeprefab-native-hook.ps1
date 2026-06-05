param(
  [string]$SourcePath = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\native\placeprefab_hook\placeprefab_hook.cpp',
  [string]$OutDir = 'C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\artifacts',
  [string]$DllName = 'placeprefab_native_hook.dll',
  [string]$VsRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community',
  [string]$MsvcVersion = '14.44.35207'
)

$ErrorActionPreference = 'Stop'

$vcvars = Join-Path $VsRoot 'VC\Auxiliary\Build\vcvars64.bat'
if (!(Test-Path $vcvars)) {
  throw "vcvars64.bat not found at $vcvars"
}

if (!(Test-Path $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$dllPath = Join-Path $OutDir $DllName
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($DllName)
$pdbPath = Join-Path $OutDir ($baseName + '.pdb')
$objPath = Join-Path $OutDir ($baseName + '.obj')

$compile = @(
  "`"$vcvars`"",
  '>',
  'NUL',
  '&&',
  'cl.exe',
  '/nologo',
  '/std:c++20',
  '/EHsc',
  '/O2',
  '/LD',
  "`"$SourcePath`"",
  '/Fe:' + "`"$dllPath`"",
  '/Fd:' + "`"$pdbPath`"",
  '/Fo:' + "`"$objPath`"",
  'kernel32.lib',
  'user32.lib'
) -join ' '

cmd.exe /d /s /c $compile
if ($LASTEXITCODE -ne 0) {
  throw "cl.exe failed with exit code $LASTEXITCODE"
}

Get-Item $dllPath
