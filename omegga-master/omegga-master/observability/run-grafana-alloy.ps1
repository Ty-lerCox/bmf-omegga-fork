param(
  [string]$AlloyPath = "alloy",
  [string]$ConfigPath = (Join-Path $PSScriptRoot "grafana-cloud.alloy"),
  [string]$StoragePath = (Join-Path $PSScriptRoot ".alloy-data")
)

$ErrorActionPreference = "Stop"

$required = @(
  "GRAFANA_CLOUD_PROMETHEUS_RW_URL",
  "GRAFANA_CLOUD_PROMETHEUS_USERNAME",
  "GRAFANA_CLOUD_API_KEY"
)

foreach ($name in $required) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    throw "Missing required environment variable: $name"
  }
}

if ($AlloyPath -eq "alloy" -and -not (Get-Command alloy -ErrorAction SilentlyContinue)) {
  $installedAlloyCandidates = @(
    (Join-Path $env:ProgramFiles "GrafanaLabs\Alloy\alloy.exe"),
    (Join-Path $env:ProgramFiles "GrafanaLabs\Alloy\alloy-windows-amd64.exe")
  )
  $installedAlloy = $installedAlloyCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($installedAlloy) {
    $AlloyPath = $installedAlloy
  } else {
    throw "Grafana Alloy was not found. Install it with: winget install GrafanaLabs.Alloy"
  }
}

if ([string]::IsNullOrWhiteSpace($env:OMEGGA_METRICS_TARGET)) {
  $env:OMEGGA_METRICS_TARGET = "127.0.0.1:8080"
}

if ([string]::IsNullOrWhiteSpace($env:BRICKADIA_METRICS_ENVIRONMENT)) {
  $env:BRICKADIA_METRICS_ENVIRONMENT = "local"
}

if ([string]::IsNullOrWhiteSpace($env:BRICKADIA_METRICS_INSTANCE)) {
  $env:BRICKADIA_METRICS_INSTANCE = $env:COMPUTERNAME
}

New-Item -ItemType Directory -Path $StoragePath -Force | Out-Null

& $AlloyPath run "--storage.path=$StoragePath" $ConfigPath
