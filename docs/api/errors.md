# Errors

Shared result shape and error codes for the high-level Lua API.

Status: `Draft`

## Result Contract

High-level functions should return a table. They should not throw for expected
operational failures such as missing files, failed validation, or load timeouts.

```lua
{
  ok = false,
  code = "BUNDLE_NOT_FOUND",
  message = "World bundle was not found in Saved/Worlds",
  data = {},
}
```

Unexpected programmer errors can still throw, such as passing a non-table where
an options table is required.

## Common Codes

| Code | Meaning | Typical Fix |
| --- | --- | --- |
| `OK` | Operation completed. | None. |
| `INVALID_OPTIONS` | Required option missing or wrong type. | Fix the options table. |
| `SOURCE_NOT_FOUND` | Source `.brz` path does not exist. | Re-copy the prefab or update `source`. |
| `SOURCE_UNREADABLE` | Source archive exists but cannot be read. | Check permissions and whether the file is locked. |
| `BUNDLE_EXISTS` | Output `.brdb` already exists and overwrite is false. | Use a new name or set `overwrite = true`. |
| `BUNDLE_NOT_FOUND` | Staged `.brdb` is missing from `Saved/Worlds`. | Build or copy the bundle before loading. |
| `CONVERSION_FAILED` | `.brz` to `.brdb` conversion failed. | Inspect archive layout and conversion logs. |
| `ENTITY_SCAN_FAILED` | Entity diagnostics failed. | Load without entity validation or inspect manually. |
| `BRIDGE_NOT_READY` | UE4SS bridge did not report ready. | Restart the test server or check bridge env paths. |
| `CONSOLE_MANAGER_UNAVAILABLE` | Console manager singleton or process input pointer is missing. | Recheck signatures and vtable offset for this build. |
| `WORLD_CONTEXT_UNAVAILABLE` | No valid `UWorld*` was available. | Wait for map load or restart server. |
| `LOAD_COMMAND_FAILED` | The bridge command returned failure. | Check command output and server log. |
| `LOAD_LOG_TIMEOUT` | Load command was sent but success log was not observed. | Check `Brickadia.log`; the load may have failed or logging may lag. |

## Error Data

Each error should include enough `data` to debug without reading implementation
logs first.

For file errors:

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

For bridge errors:

```lua
{
  ok = false,
  code = "CONSOLE_MANAGER_UNAVAILABLE",
  message = "Console manager process input is unavailable",
  data = {
    initializer = "0x00007ff7...",
    slot = "0x00007ff7...",
    singleton = nil,
    processInput = nil,
    vtableOffset = "0xe0",
  },
}
```

For load verification errors:

```lua
{
  ok = false,
  code = "LOAD_LOG_TIMEOUT",
  message = "World load success log was not observed before timeout",
  data = {
    name = "PrefabBridge_ClipboardDynamic",
    command = "BR.World.LoadAdditive PrefabBridge_ClipboardDynamic 2000 0 300 16",
    timeoutMs = 60000,
    logPath = "C:/.../Saved/Logs/Brickadia.log",
  },
}
```

## Throwing Rules

Throw only when the caller used the API incorrectly in a way that cannot be
represented as an operation result.

Examples:

- `Omegga.Prefabs.LoadWorld(nil)`
- `Omegga.Prefabs.LoadWorld("PrefabName")`
- `Omegga.Prefabs.LoadWorld({ position = "bad" })`

Return a structured failure for everything that can happen during normal server
operation.
