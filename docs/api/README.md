# Brickadia Server Lua API

Draft API documentation for exposing dedicated-server automation through
Omegga and UE4SS Lua.

This section is written like public website documentation: start with the
supported workflow, then drill into function references and error behavior.
The high-level prefab API is the target contract. The low-level bridge commands
are the pieces currently available while that contract is being implemented.

## Status

| Area | Status | Notes |
| --- | --- | --- |
| Bridge transport | Available | File-backed JSON-RPC over `inbox.ndjson` and `outbox.ndjson`. |
| Console manager executor | Available | Used to call `BR.World.LoadAdditive` from inside the server. |
| Native prefab hooks | Internal | `ServerPastePrefab`, `ServerPlaceCurrentPrefab`, `ServerPlaceSimpleEntityVolume`, upload, and paste RPC hooks register on `CL13530` with the patched UE4SS resolver. |
| Prefab high-level API | Draft | Proposed Lua wrapper should move from additive loading toward native paste/placer calls for dynamic prefabs. |
| Vehicle/entity repair | Investigating | Additive loading is not sufficient for dynamic vehicle physics; capture the native client paste path before implementing server-side paste. |

## Quick Start

The intended high-level flow is:

```lua
local bundle = Omegga.Prefabs.BuildWorldBundle({
  source = "C:/Users/tycox/AppData/Local/Brickadia/Saved/Temp/Clipboard.brz",
  name = "PrefabBridge_ClipboardDynamic",
  environment = "Plate",
})

if not bundle.ok then
  error(bundle.message)
end

local load = Omegga.Prefabs.LoadWorld({
  name = "PrefabBridge_ClipboardDynamic",
  position = { x = 2000, y = 0, z = 300 },
  orientation = 16,
})

if not load.ok then
  error(load.message)
end
```

Today, the equivalent low-level command is:

```text
Omegga.Bridge.ForceConsoleExecutor consolemanager BR.World.LoadAdditive PrefabBridge_ClipboardDynamic 2000 0 300 16
```

The API wrapper should make that command safe to call by validating that the
bundle exists, that the bridge is healthy, and that the load result is visible
in server logs.

For dynamic vehicle prefabs, `BR.World.LoadAdditive` is diagnostic only. The
current native-paste diagnostic flow is:

```text
Omegga.Bridge.InstallPrefabNativeHooks all
Omegga.Bridge.DescribePrefabNativeHooks 24
Omegga.Bridge.DescribeLastPrefabNativeCapture
Omegga.Bridge.ReplayLastPrefabNativeCapture offset 3000 0 700
```

## Documentation

- [Prefab API](prefabs.md): target high-level Lua functions for building,
  inspecting, and loading prefab world bundles.
- [Bridge API](bridge.md): current low-level bridge transport and console
  execution commands.
- [Errors](errors.md): shared result shape and common error codes.
- [Low-level notes](../low-level/prefab-server-pasting.md): implementation
  details, current paths, and debugging workflow.

## Stability Labels

| Label | Meaning |
| --- | --- |
| `Available` | The capability exists in the current bridge or UE4SS build. |
| `Draft` | The API shape is proposed and documented before implementation. |
| `Internal` | Useful for debugging, but not intended for normal plugins. |
| `Unsafe` | Can crash or corrupt server state when called with stale pointers, bad signatures, or invalid input. |

## Result Shape

High-level API calls should return a table with a consistent shape:

```lua
{
  ok = true,
  code = "OK",
  message = "World loaded",
  data = {
    name = "PrefabBridge_ClipboardDynamic",
    position = { x = 2000, y = 0, z = 300 },
    orientation = 16,
  },
}
```

On failure:

```lua
{
  ok = false,
  code = "BUNDLE_NOT_FOUND",
  message = "World bundle was not found in Saved/Worlds",
  data = {
    name = "PrefabBridge_ClipboardDynamic",
    expectedPath = "C:/.../Saved/Worlds/PrefabBridge_ClipboardDynamic.brdb",
  },
}
```

See [Errors](errors.md) for the shared error list.

## Design Rules

- Validate before calling native code.
- Prefer named options tables over positional arguments.
- Return structured results instead of throwing for normal operational failures.
- Keep raw console execution behind the bridge API.
- Use large spawn offsets in tests so repeated additive loads do not overlap.
- Treat entity and vehicle correctness as data-dependent until the archive
  relationship model is fully understood.
