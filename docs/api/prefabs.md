# Prefab API

High-level Lua API for staging and loading Brickadia prefab archives into a
running dedicated server.

Status: `Draft`

The functions below are the intended public wrapper over the current low-level
bridge path. They should hide `.brz` to `.brdb` conversion, world-bundle
staging, console-manager execution, and log verification.

Important: the additive world-bundle API is not sufficient for dynamic vehicle
prefabs. It can stage and load archive contents, but current testing shows it
does not create the same physics/dynamic actor state as Brickadia's normal
catalog/prefab placement flow. Dynamic vehicle support should be built on the
native paste/placer capture path documented below.

## Concepts

### Source Archive

A source archive is a Brickadia `.brz` file, usually from the clipboard temp
folder or the gallery cache.

Example:

```text
C:/Users/tycox/AppData/Local/Brickadia/Saved/Temp/Clipboard.brz
```

### World Bundle

A world bundle is a staged `.brdb` file under the server data directory:

```text
<server-data>/Saved/Worlds/<name>.brdb
```

`BR.World.LoadAdditive` loads by bundle name, not by full path. For a file named
`PrefabBridge_ClipboardDynamic.brdb`, pass `PrefabBridge_ClipboardDynamic`.

### Position

Positions use Brickadia world coordinates:

```lua
{ x = 2000, y = 0, z = 300 }
```

Use a high `z` value while testing so the object does not spawn underground.
Use large `x` or `y` offsets when repeatedly loading the same prefab.

## `Omegga.Prefabs.BuildWorldBundle(options)`

Converts a `.brz` prefab archive into a staged `.brdb` world bundle.

Status: `Draft`

### Parameters

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `source` | `string` | Yes |  | Full path to a `.brz` source archive. |
| `name` | `string` | Yes |  | Bundle name to write under `Saved/Worlds`. Do not include `.brdb`. |
| `environment` | `string` | No | `"Plate"` | World environment written to `Meta/World.json`. |
| `overwrite` | `boolean` | No | `false` | Replaces an existing staged `.brdb` when true. |
| `validateEntities` | `boolean` | No | `true` | Reads entity chunks and includes a summary in the result. |
| `patchPhysicsMetadata` | `boolean` | No | `false` | Diagnostic only. Repairs `Meta/Prefab.json` for copied dynamic prefabs; do not use for normal additive loads. |

### Example

```lua
local result = Omegga.Prefabs.BuildWorldBundle({
  source = "C:/Users/tycox/AppData/Local/Brickadia/Saved/Temp/Clipboard.brz",
  name = "PrefabBridge_ClipboardDynamic",
  environment = "Plate",
  overwrite = true,
})
```

### Success Result

```lua
{
  ok = true,
  code = "OK",
  message = "World bundle staged",
  data = {
    name = "PrefabBridge_ClipboardDynamic",
    path = "C:/.../Saved/Worlds/PrefabBridge_ClipboardDynamic.brdb",
    environment = "Plate",
    source = "C:/.../Clipboard.brz",
    entitySummary = {
      hasDynamicActors = true,
      types = {
        "BP_Entity_Wheel_Deep1_C",
        "BrickGridDynamicActor",
      },
    },
  },
}
```

### Failure Codes

- `SOURCE_NOT_FOUND`
- `SOURCE_UNREADABLE`
- `BUNDLE_EXISTS`
- `CONVERSION_FAILED`
- `ENTITY_SCAN_FAILED`

### Current Equivalent

```powershell
node .\brickadia-ue4ss-re\scripts\build-prefab-world-brdb.js `
  "C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz" `
  "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Worlds\PrefabBridge_ClipboardDynamic.brdb" `
  Plate
```

## `Omegga.Prefabs.LoadWorld(options)`

Loads a staged `.brdb` world bundle into the current server world.

Status: `Draft`, static/additive path only for dynamic vehicles

### Parameters

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `name` | `string` | Yes |  | Staged bundle name without `.brdb`. |
| `position` | `table` | Yes |  | `{ x, y, z }` spawn position. |
| `orientation` | `integer` | No | `0` | Brickadia orientation value passed to `BR.World.LoadAdditive`. |
| `verifyLog` | `boolean` | No | `true` | Waits for the success sequence in `Brickadia.log`. |
| `timeoutMs` | `integer` | No | `60000` | Maximum time to wait for bridge and log verification. |
| `executor` | `string` | No | `"consolemanager"` | Console executor. Normal callers should not change this. |

### Example

```lua
local result = Omegga.Prefabs.LoadWorld({
  name = "PrefabBridge_ClipboardDynamic",
  position = { x = 2000, y = 0, z = 300 },
  orientation = 16,
})
```

### Success Result

```lua
{
  ok = true,
  code = "OK",
  message = "World loaded",
  data = {
    name = "PrefabBridge_ClipboardDynamic",
    command = "BR.World.LoadAdditive PrefabBridge_ClipboardDynamic 2000 0 300 16",
    position = { x = 2000, y = 0, z = 300 },
    orientation = 16,
    verifiedLog = true,
  },
}
```

### Failure Codes

- `BUNDLE_NOT_FOUND`
- `BRIDGE_NOT_READY`
- `CONSOLE_MANAGER_UNAVAILABLE`
- `WORLD_CONTEXT_UNAVAILABLE`
- `LOAD_COMMAND_FAILED`
- `LOAD_LOG_TIMEOUT`

### Current Equivalent

```text
Omegga.Bridge.ForceConsoleExecutor consolemanager BR.World.LoadAdditive PrefabBridge_ClipboardDynamic 2000 0 300 16
```

## Native Paste Diagnostics

Status: `Internal`

Before implementing a public dynamic vehicle paste API, capture Brickadia's own
native placement call from a normal client action:

```text
Omegga.Bridge.InstallPrefabNativeHooks all
Omegga.Bridge.DescribePrefabNativeHooks 24
Omegga.Bridge.DescribeLastPrefabNativeCapture
Omegga.Bridge.DescribePrefabNativeReplay
```

The current hook set registers `ServerPastePrefab`,
`ServerPlaceCurrentPrefab`, `ServerUploadPrefab`, `ClientUploadPrefab`,
`ServerPasteBrick`, `ServerPasteEntity`, `HandleAttachedPlacement`,
`SetPlaceAsPhysicsAvailable`, `SetPlaceAsPhysicsEnabled`,
`ServerModifyEntity`, and `ServerPlaceSimpleEntityVolume` on `CL13530` with
the patched UE4SS resolver. `ServerPlaceSimpleEntityVolume` is treated as a
replayable native placement path using the CL13530-reflected `0xE4` placement
buffer layout. The `SetPlaceAsPhysics*` hooks are diagnostic side-channel
captures; they are not replayable prefab placements. The public API should not
call `BR.World.LoadAdditive` for dynamic vehicles until native paste behavior is
captured and reproduced. Successful captures are also written to
`prefab-native-last.txt` and `prefab-native-captures.ndjson` in the active
UE4SS bridge directory. The live `CL13530` replay contract can be regenerated
with:

```text
node brickadia-ue4ss-re/scripts/capture-prefab-native-diagnostics.js --dir <bridge_dir>
```

That diagnostic checks the replay ABI contracts. A healthy current server
reports `server_paste_contract=matches-live-reflection` and
`server_place_contract=matches-live-reflection`, with
`server_place_simple_entity_volume_contract=matches-live-reflection` when the
simple entity-volume placement path is available.

Current additive-path warning: forcing copied vehicle metadata to
`bIsPhysicsGrid=true` can crash `BR.World.LoadAdditive` during prefab metadata
load. Dynamic vehicle support should stay on the native placement/capture path.

Current hash evidence: `BRPrefabHash` appears to be `BLAKE3(raw .brz archive
bytes)`. The old logged hash
`07C8E4AD16AC2B85B7FBE8637C9929AD9326ECA7384219F05937BD0F464BB7AD`
matches the raw-file BLAKE3 of gallery prefab
`8c04e0ee-87b3-4eef-b5de-659c60f1e9ac.brz`. Use
`brickadia-ue4ss-re/scripts/prefab-hash-report.js` to regenerate the current
hash/cache report.

Current reflected `ServerPastePrefab` shape: `BRPrefabHash` at offset `0x00`
for `0x20` bytes, `bWithOwnership` at `0x20`, `bInTemp` at `0x21`, and
`BRPrefabDetachedPasteInfo` at `0x28` for `0x18` bytes. The paste info carries
target object pointer, `GridOffset`, and `PlacementOrientation`.

`ServerPlaceCurrentPrefab` is also replayable on `CL13530`. Its reflected
parameter buffer is `0xDF` bytes: placement state at `0x00`, primary
`FIntVector` grid at `0x80`, placement vector at `0x90`, orientation at
`0xA8`, extra grid-like `FIntVector` parameters at `0xAC`, `0xB8`, `0xC4`, and
`0xD0`, then three bool parameters at `0xDC..0xDE`. Offset/grid replay adjusts
all five known grid-like vectors plus `PlacementState.Transform.Translation`
and `PlacementVector` by the same delta.

`ServerPlaceSimpleEntityVolume` is replayable on `CL13530` when captured from a
real client placement. Its reflected parameter buffer is `0xE4` bytes:
placement state at `0x00`, entity class/object pointer at `0x80`,
orientation/flags bytes at `0x88`, primary `FIntVector` grid at `0x8C`,
placement vector at `0x98`, a bool-like parameter at `0xB0`, and extra
grid-like `FIntVector` parameters at `0xB4`, `0xC0`, `0xCC`, and `0xD8`.
Offset/grid replay adjusts all five known grid-like vectors plus
`PlacementState.Transform.Translation` and `PlacementVector` by the same delta.

The current internal replay path preserves the captured native parameter memory
layout and calls `ProcessEvent` through
`OmeggaUnsafeProcessEventWithParamBytes`. Once a normal client paste has fired
and the captured player-controller context is still valid, repeat that exact
paste with:

```text
Omegga.Bridge.ReplayLastPrefabNativeCapture
```

To move the replay away from the captured paste position, pass a relative grid
offset or an absolute grid:

```text
Omegga.Bridge.ReplayLastPrefabNativeCapture offset 2000 0 500
Omegga.Bridge.ReplayLastPrefabNativeCapture grid 4000 0 800
```

There is also an experimental hash-driven paste command for testing the
`ServerPastePrefab` route without a captured parameter buffer:

```text
Omegga.Bridge.PastePrefabHash <64hex_hash> grid <x> <y> <z> [orientation] [ownership=1] [temp=0] [target=0|last] [dry-run]
```

The helper script can compute the hash from a `.brz` and send that command:

```powershell
node brickadia-ue4ss-re/scripts/paste-prefab-hash.js `
  --brz "C:\Users\tycox\AppData\Local\Brickadia\Saved\GalleryCache\Prefabs\044a0003-4d2b-4484-b9e6-1b93cbc06b68.brz" `
  --grid 3000 0 700 `
  --orientation 0 `
  --target 0 `
  --dry-run 1
```

`dry-run` only builds and validates the 64-byte `ServerPastePrefab` parameter
buffer. A real call still needs a valid player-controller context and the
matching prefab cache entry to exist inside Brickadia's native cache; otherwise
the native RPC cannot materialize a dynamic vehicle.

During live testing, the helper script can wait for the next client paste and
replay it if it is a `ServerPastePrefab`, `ServerPlaceCurrentPrefab`, or
`ServerPlaceSimpleEntityVolume` capture.
Use `--expected-kind any` to stop and report other native paste paths, such as
`ServerPasteEntity`, instead of waiting for the wrong hook. Upload/capture
handshake events and `SetPlaceAsPhysics*` toggle events are ignored while the
watcher waits for a replayable paste call. Use
`--require-player 1` when testing on a freshly restarted dedicated server so the
tool will not replay stale/no-player state:

```text
node brickadia-ue4ss-re/scripts/wait-prefab-native-capture-replay.js --dir <bridge_dir> --expected-kind any --require-player 1 --replay-args "offset 2000 0 500" --status-path <bridge_dir>/prefab-native-watch-status.json
```

The status file is updated periodically with `waiting-for-player`,
`waiting-for-capture`, or the final replay/capture result. It also includes a
`watcher_session_id`, `started_at`, `status_seq`, and `pid` so stale watcher
state after a server restart is detectable. Final watcher output includes
`decoded_capture`, which summarizes replayable prefab buffers and
object-reference calls such as `ServerPasteEntity`.

By default the watcher also performs a dry-run `PastePrefabHash` check after a
real `ServerPastePrefab` capture. That confirms the captured hash can be turned
back into a direct native paste command without spawning an extra overlapping
vehicle. Use `--post-hash-paste 1` only when intentionally testing a real
second paste by hash.

Use the readiness probe for a concise preflight or post-paste check:

```text
node brickadia-ue4ss-re/scripts/prefab-native-readiness.js --dir <bridge_dir>
```

When `prefab-native-watch-status.json` exists, readiness includes a `watcher`
block with the watcher status, heartbeat age, and whether the watcher PID is
still alive.

This is intentionally not the public API yet. It can replay captured
`ServerPastePrefab` and `ServerPlaceCurrentPrefab` calls, but it does not yet
materialize an arbitrary `.brz` into Brickadia's native prefab cache without a
preceding client-side paste. Native captures are labeled `source=client` or
`source=replay`; replay prefers the latest client capture when available. Avoid
broad runtime object scans for vehicle debugging on `CL13530`; use readiness,
hook state, and capture decode instead.

Once a normal client paste has fired, decode the saved capture with:

```text
node brickadia-ue4ss-re/scripts/decode-prefab-native-capture.js --dir <bridge_dir>
```

## `Omegga.Prefabs.LoadClipboard(options)`

Convenience wrapper that builds a world bundle from the current clipboard
archive, then loads it.

Status: `Draft`

### Parameters

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `name` | `string` | No | `"Clipboard"` | Staged bundle name without `.brdb`. |
| `source` | `string` | No | User temp clipboard path | `.brz` archive to build from. |
| `position` | `table` | Yes |  | `{ x, y, z }` spawn position. |
| `orientation` | `integer` | No | `0` | Brickadia orientation value. |
| `environment` | `string` | No | `"Plate"` | World environment for the generated `.brdb`. |
| `overwrite` | `boolean` | No | `true` | Rebuilds the staged clipboard bundle. |
| `validateEntities` | `boolean` | No | `true` | Includes entity diagnostics in the result. |

### Example

```lua
local result = Omegga.Prefabs.LoadClipboard({
  name = "PrefabBridge_ClipboardDynamic",
  position = { x = 2000, y = 0, z = 300 },
  orientation = 16,
})
```

### Success Result

```lua
{
  ok = true,
  code = "OK",
  message = "Clipboard prefab loaded",
  data = {
    bundle = {
      name = "PrefabBridge_ClipboardDynamic",
      path = "C:/.../Saved/Worlds/PrefabBridge_ClipboardDynamic.brdb",
    },
    load = {
      verifiedLog = true,
      position = { x = 2000, y = 0, z = 300 },
      orientation = 16,
    },
    entitySummary = {
      hasDynamicActors = true,
      types = {
        "BP_Entity_Wheel_Deep1_C",
        "BrickGridDynamicActor",
      },
    },
  },
}
```

## `Omegga.Prefabs.DescribeArchive(options)`

Reads a `.brz` or `.brdb` archive and returns metadata useful before loading.

Status: `Draft`

### Parameters

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `path` | `string` | Yes |  | Full path to `.brz` or `.brdb`. |
| `includeEntities` | `boolean` | No | `true` | Decodes entity chunks when possible. |
| `includeFiles` | `boolean` | No | `false` | Includes the named-file list. |

### Example

```lua
local info = Omegga.Prefabs.DescribeArchive({
  path = "C:/Users/tycox/AppData/Local/Brickadia/Saved/Temp/Clipboard.brz",
  includeEntities = true,
})
```

### Success Result

```lua
{
  ok = true,
  code = "OK",
  message = "Archive described",
  data = {
    brickCount = 566,
    hasWorldMetadata = false,
    hasPrefabMetadata = true,
    entitySummary = {
      hasDynamicActors = true,
      dynamicActorCount = 4,
      types = {
        "BP_Entity_Wheel_Deep1_C",
        "BrickGridDynamicActor",
      },
    },
  },
}
```

## Vehicle Notes

Vehicle loading is not guaranteed by the presence of entity chunks alone.
Observed clipboard data can include `BrickGridDynamicActor` entries and still
collapse after loading. Treat these diagnostics as preflight information, not a
promise that physics relationships are correct.

The API should expose entity summaries so callers can decide whether a prefab is
worth attempting before loading it into a live server.
