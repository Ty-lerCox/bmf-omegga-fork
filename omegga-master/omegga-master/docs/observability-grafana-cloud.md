# Grafana Cloud Observability

Omegga exposes a Prometheus-compatible scrape endpoint for Brickadia and BMF
runtime metrics:

```text
http://127.0.0.1:<omegga-port>/metrics
```

The endpoint is enabled by default and is localhost-only unless
`OMEGGA_METRICS_ALLOW_REMOTE=1` is set. Set `OMEGGA_METRICS_ENABLED=0` to disable
it.

## Metrics

Current exporter coverage:

- Brickadia server state: up, starting, stopping, players, bricks, components,
  uptime, aggregate player ping.
- Omegga process state: uptime, memory, CPU seconds, latest server-status poll
  duration.
- BMF runtime state when `Mods/BMF/runtime/status.json` is readable: runtime up,
  status age, loaded plugin count, plugin errors, plugin tick state, audit
  records, watchdog-isolated plugins.
- BMF telemetry state when `Mods/BMF/runtime/telemetry.json` is readable:
  command counts and durations, file/socket transport timings, event emit and
  handler timings, plugin command/hook timings, and bridge worker throughput.
- Native frame telemetry when the optional BMFFrameTelemetry UE4SS C++ mod is
  deployed and `Mods/BMF/runtime/frame-telemetry.json` is readable: Unreal
  engine tick delta time, frame-rate estimate, sample counts, and slow-frame
  counters.

The exporter deliberately avoids player names, UUIDs, addresses, command args,
and other high-cardinality labels.

The BMF timing metrics measure bridge, command, event, and Lua/plugin execution
cost. True Unreal dedicated-server frame time requires the optional native
BMFFrameTelemetry sampler; until that mod is deployed and the server is
restarted, `brickadia_frame_telemetry_up` remains `0`. The current
`omegga_server_status_poll_duration_seconds` metric is only a low-risk
responsiveness proxy.

## Grafana Alloy

Use `observability/grafana-cloud.alloy` to scrape Omegga locally and remote-write
to Grafana Cloud. The Alloy config uses environment variables for secrets.

Install Alloy on Windows:

```powershell
winget install GrafanaLabs.Alloy
```

Required variables:

```powershell
$env:GRAFANA_CLOUD_PROMETHEUS_RW_URL = "https://<stack-prometheus-url>/api/prom/push"
$env:GRAFANA_CLOUD_PROMETHEUS_USERNAME = "<prometheus-user-id>"
$env:GRAFANA_CLOUD_API_KEY = "<grafana-cloud-api-token>"
```

Optional variables:

```powershell
$env:OMEGGA_METRICS_TARGET = "127.0.0.1:8080"
$env:BRICKADIA_METRICS_ENVIRONMENT = "local"
$env:BRICKADIA_METRICS_INSTANCE = $env:COMPUTERNAME
$env:OMEGGA_BMF_STATUS_PATH = "C:\path\to\Mods\BMF\runtime\status.json"
$env:OMEGGA_BMF_FRAME_TELEMETRY_PATH = "C:\path\to\Mods\BMF\runtime\frame-telemetry.json"
```

Grafana Cloud shows the remote-write URL, username, and password/API key from
the Prometheus card details page.

Start Alloy in the foreground:

```powershell
.\observability\run-grafana-alloy.ps1
```

If `alloy.exe` is not on `PATH`, pass it explicitly:

```powershell
.\observability\run-grafana-alloy.ps1 -AlloyPath "C:\Program Files\GrafanaLabs\Alloy\alloy-windows-amd64.exe"
```

The runner starts Alloy in the foreground using a repo-local WAL directory at
`observability/.alloy-data`. For a persistent Windows service install, copy
`observability/grafana-cloud.alloy` to `%PROGRAMFILES%\GrafanaLabs\Alloy\config.alloy`,
set the same environment variables in the Alloy service configuration, then
restart the service.

The config is tuned for a single local game server: it scrapes every 15 seconds,
disables metadata sends, and caps Grafana Cloud remote-write at one shard. This
keeps the collector quiet enough for a low-rate local telemetry pipeline while
still giving useful server health and performance samples.

Quick local checks:

```powershell
Invoke-WebRequest http://127.0.0.1:8080/metrics
Invoke-WebRequest http://127.0.0.1:12345/-/ready
```

## Dashboard

Import `observability/grafana/brickadia-overview-dashboard.json` into Grafana
Cloud and select the Grafana Cloud Prometheus data source. The dashboard includes
the base server/Omegga health panels plus a BMF bridge and runtime timing section
for command duration, command rate, transport duration, worker throughput, event
timing, plugin command timing, and plugin hook timing. It also includes a native
frame-time section that stays empty until BMFFrameTelemetry is deployed and
writing `frame-telemetry.json`.
