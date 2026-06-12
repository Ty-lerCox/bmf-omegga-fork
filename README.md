# BMF Omegga Windows Runtime Fork

This repository is the BMF-supported Omegga fork for Windows Brickadia
dedicated-server automation.

Use this fork when BMF documentation says the supported Omegga runtime:

- BMF repository: <https://github.com/Ty-lerCox/brickadia-modding-framework>
- Supported Omegga fork: <https://github.com/Ty-lerCox/bmf-omegga-fork>

Stock upstream Omegga and the global npm package are Linux/WSL-oriented and are
not the supported Windows runtime for BMF. This fork intentionally trails the
latest upstream Omegga builds because BMF validates against the Windows/UE4SS
bridge surfaces in this repository.

## What This Fork Provides

- Windows-oriented Omegga runtime support for BMF.
- UE4SS bridge templates, including `OmeggaBridge`.
- BMF command routing through `Omegga.Bridge.BMF`.
- Helper surfaces used by BMF canaries and live-player APIs.
- Prometheus `/metrics` export and Grafana Cloud/Alloy observability docs for
  local performance telemetry.
- Packaging hooks for BMF/Omegga integration work.

This repository is not a general replacement for upstream Omegga. Use upstream
Omegga for generic Linux/WSL Omegga server work unless BMF specifically requires
the Windows runtime fork.

## Layout

```text
omegga-master/omegga-master/      Omegga runtime source and templates
docs/                             BMF/Omegga bridge and prefab API notes
brickadia-ue4ss-re/               Brickadia UE4SS compatibility workspace
scripts/                          Local helper scripts
```

Generated runtime data, local Brickadia server state, logs, and build outputs
are intentionally ignored.

## Development

From the Omegga source directory:

```powershell
cd .\omegga-master\omegga-master
npm install
npm run build
```

Build the Windows console bridge when changing bridge code:

```powershell
npm run build:bridge
```

Run package or BMF validation from the BMF repository when the change affects
BMF behavior. Keep BMF documentation and this fork's runtime contract aligned.

Observability setup lives in
`omegga-master/omegga-master/docs/observability-grafana-cloud.md`. That guide
covers the local `/metrics` endpoint, Grafana Alloy remote-write setup,
dashboard import, BMF command-worker metrics, and native frame-time telemetry.

## Local BMF/CityRPG Runtime Profile

`run-omegga.cmd` carries the local validation defaults for BMF-backed CityRPG
tree work. Keep this profile conservative unless the matching BMF and CityRPG
changes are updated and revalidated together.

Current tree/runtime defaults:

```text
BMF_TREECUT_NATIVE_ENABLED=1
BMF_TREECUT_TARGET_AUTO_REFRESH=0
BMF_TREECUT_TARGET_REFRESH_ENABLED=0
BMF_BRICK_RUNTIME_SET_ENABLED=1
BMF_BRICK_CONTEXT_BACKGROUND_SCAN_ENABLED=1
BMF_BRICK_VISIBILITY_SET_ENABLED=1
BMF_BRICK_VISIBILITY_DIRECT_WRITE_ENABLED=0
BMF_BRICK_COLLISION_SET_ENABLED=1
BMF_BRICK_COLLISION_DIRECT_WRITE_ENABLED=0
BMF_BRICK_RUNTIME_CONTEXT_HOOK_ENABLED=0
BMF_BRICK_RUNTIME_PLACE_CONTEXT_HOOK_ENABLED=0
BMF_BRICK_RUNTIME_LOW_SETTER_HOOK_ENABLED=0
BMF_BRICK_RUNTIME_CONTEXT_OVERRIDE_ENABLED=0
BMF_BRICK_OWNER_CONTEXT_SCAN_ENABLED=0
BMF_TREE_PHYSICAL_SET_ENABLED=0
CITYRPG_TREE_PHYSICAL_STATE=1
CITYRPG_TREE_PHYSICAL_COLLISION=0
CITYRPG_TREE_PHYSICAL_SAVED_BRICK_INDEX=0
CITYRPG_NATIVE_TREE_HIT_COOLDOWN_MS=2500
CITYRPG_NATIVE_TREE_REQUIRE_TAG=1
CITYRPG_NATIVE_TREE_IMPACT_ANCHORS=0
CITYRPG_TREE_RUNTIME_WORLD_EDIT=0
CITYRPG_TREE_TAG_INDEX_ON_HIT=0
CITYRPG_TREE_TAG_INDEX_STARTUP=1
CITYRPG_TREE_TAG_INDEX_FILE=%SCRIPT_DIR%artifacts\tree-tag-index.json
```

The practical behavior is: CityRPG can hide/restore tagged runtime trees by
calling `bmf.bricks.runtime.set` with both a candidate `brickid` and the
`treeid:` tag, but collision is left unchanged while the collision mutation
path is still under crash validation. BMF may use the off-game-thread
background sparse-grid resolver on cold start. The launcher leaves the native
context hooks, low-level setter hook, explicit context override, and owner scan
disabled so normal tree chopping does not rely on broad or risky live scans.
Impact anchors and on-hit tag indexing are disabled; tree identity should come
from the startup tag-index file or an explicit admin refresh.

## Runtime Contract

When updating this fork, keep these BMF-facing surfaces intact unless the BMF
repo is updated and validated at the same time:

- `Omegga.Bridge.BMF`
- `Omegga.Bridge.ForceConsoleExecutor`
- `OmeggaBridge`
- `OmeggaExecuteConsoleManagerInput`
- `OmeggaExecuteKismetConsoleCommand`
- `OmeggaExecuteCachedConsoleExec`
- `OmeggaCallFunctionByNameWithArguments`

Environment preset reloads are part of this contract. The Omegga fork routes
`Server.Environment.LoadPreset ...` and `Server.Environment.Reset` through
`Omegga.Bridge.ForceConsoleExecutor consolemanager ...` on the Windows UE4SS
runtime so plugins can apply weather/environment files without restarting the
Brickadia server.

Do not replace this fork with a newer upstream Omegga build until BMF has
validated that build against the Windows UE4SS bridge, player-sync adapters,
command transport, and canaries.
