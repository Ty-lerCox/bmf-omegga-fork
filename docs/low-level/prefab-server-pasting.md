# Prefab Server Pasting Low-Level Notes

This document captures the current Windows dedicated-server prefab loading path.
It is intentionally low level: it describes the bridge pieces we have today and
the constraints that matter before wrapping them in a safer Lua/Omegga API.

## Scope

The current goal is to paste a Brickadia prefab into a running dedicated server
without using a normal interactive console. The staged-world additive path can
load bricks and some entities through `BR.World.LoadAdditive`, but it does not
instantiate dynamic vehicle prefabs as proper physics/dynamic actors. For
dynamic vehicles, the active path is now Brickadia's native prefab paste/placer
RPC flow, captured through UE4SS `RegisterHook` from the Omegga bridge.

The current build target is the Windows server/client generation around
`CL13530`. If Brickadia updates again, assume signatures and vtable assumptions
need to be re-verified before relying on this path.

## Important Paths

- Reverse-engineering repo:
  `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re`
- Omegga repo:
  `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master`
- UE4SS source:
  `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS`
- OmeggaBridge Lua template:
  `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\templates\windows-ue4ss\ue4ss\Mods\OmeggaBridge\Scripts\main.lua`
- Installed OmeggaBridge Lua:
  `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\Mods\OmeggaBridge\Scripts\main.lua`
- Installed UE4SS DLL:
  `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\UE4SS.dll`
- Server world directory:
  `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Worlds`
- Bridge test directory for port `7799`:
  `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799`

## Runtime Layers

The current path has four layers.

1. A Node/PowerShell test harness writes JSON-RPC-style requests to
   `inbox.ndjson` in the bridge session directory.
2. `OmeggaBridge` Lua polls that file from inside UE4SS and dispatches requests
   on the server side.
3. UE4SS C++ exposes native helpers as Lua globals. For prefab loading, the
   additive helper is `OmeggaExecuteConsoleManagerInput`; the native replay
   helper is `OmeggaUnsafeProcessEventWithParamBytes`.
4. The bridge writes responses to `outbox.ndjson`, plus logs under the server
   data and UE4SS log locations.

This is not yet a stable public API. It is a low-level control path that we can
later wrap with a narrower Lua surface such as `Omegga.Prefabs.LoadWorld(...)`.

## Native Prefab Hook Path

`BR.World.LoadAdditive` is not authoritative for dynamic vehicles. It can place
the archive contents, but observed catalog/gallery vehicle loads stayed static
or lost dynamic actor/physics behavior. The current investigation therefore
uses native hooks to capture Brickadia's real prefab placement calls from a
normal client action.

The patched UE4SS build resolves `RegisterHook` targets through
`FindObjects(..., GFunctionName, ...)` when `StaticFindObject` cannot resolve a
full UFunction path. That fallback is required on `CL13530`, where short
function lookup can find UFunctions but `StaticFindObject` often returns a null
wrapper for paths such as:

```text
/Script/Brickadia.BRPlayerController:ServerPastePrefab
/Script/Brickadia.BRTool_Placer:ServerPlaceCurrentPrefab
```

Start a clean hooked server:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
.\brickadia-ue4ss-re\scripts\start-bridge-test-server.ps1 -EnableUnsafeProbes -VerifyWaitSeconds 25
```

Install the native hooks:

```powershell
node .\brickadia-ue4ss-re\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.InstallPrefabNativeHooks all" `
  --wait-ms 6000
```

Check the armed hook state:

```powershell
node .\brickadia-ue4ss-re\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.DescribePrefabNativeHooks 24" `
  --wait-ms 4000
```

For a concise current-state check before or after a live paste attempt, run:

```powershell
node .\brickadia-ue4ss-re\scripts\prefab-native-readiness.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799"
```

`status=ready-for-client-paste` means the bridge is reachable, required hooks
are registered, at least one player is connected, and no client paste has been
captured yet. `status=ready-waiting-for-player` means the same hook/runtime
preflight passed, but no player is connected yet. A captured non-prefab native
path, such as `ServerPasteEntity`, is reported separately. Readiness also
includes `vehicle_replay_verdict`, the same classification reported by
`verify-prefab-native-vehicle-replay.js`; once a watcher run finishes, readiness
can report `vehicle-replay-coherent` or `vehicle-replay-unverified` directly.

On CL13530, leave `--dump-actors` off during normal paste testing. It is an
explicit diagnostic opt-in because reflected actor/location inspection can wedge
or crash this UE4SS build. Use it only after the paste flow itself is stable.

The readiness output also includes a `watcher` block when
`prefab-native-watch-status.json` exists. `watcher.process_alive=true` and
`watcher.status.status=waiting-for-player` means the background capture watcher
is armed and will begin polling native hook state after a player connects.

As of `2026-05-31T21:01:25Z`, the following hooks registered on the local
test server:

- `ServerPastePrefab`
- `ServerPlaceCurrentPrefab`
- `ServerUploadPrefab`
- `ClientUploadPrefab`
- `ServerPasteBrick`
- `ServerPasteEntity`
- `HandleAttachedPlacement`
- `SetPlaceAsPhysicsAvailable`
- `SetPlaceAsPhysicsEnabled`
- `ServerModifyEntity`
- `ServerPlaceSimpleEntityVolume`
- `ClientNotifyPrefabCaptureComplete`
- `ClientNotifyPrefabCaptureFailed`

After a real client places a prefab through Brickadia's normal catalog/paste UI,
capture the last native call:

```powershell
node .\brickadia-ue4ss-re\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.DescribeLastPrefabNativeCapture" `
  --wait-ms 4000
```

The bridge also persists each successful native paste capture under the bridge
directory:

- `prefab-native-last.txt`: readable detail for the most recent capture.
- `prefab-native-captures.ndjson`: append-only capture records with
  base64-encoded detail text.

Check whether the in-memory replay helper is available and whether the current
session has a replayable capture:

```powershell
node .\brickadia-ue4ss-re\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.DescribePrefabNativeReplay" `
  --wait-ms 4000
```

As of `2026-05-31T18:39:48Z`, the local server reports
`helper_available=true` and `last_capture=<none>`. After a connected client
fires `ServerPastePrefab`, `ServerPlaceCurrentPrefab`, or
`ServerPlaceSimpleEntityVolume`, replay the exact captured native call with:

```powershell
node .\brickadia-ue4ss-re\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.ReplayLastPrefabNativeCapture" `
  --wait-ms 6000
```

To avoid spawning the replay directly on top of the captured vehicle, provide a
grid offset:

```powershell
node .\brickadia-ue4ss-re\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.ReplayLastPrefabNativeCapture offset 2000 0 500" `
  --wait-ms 6000
```

Use `grid x y z [orientation]` instead of `offset dx dy dz [orientation]` to
replace the captured `GridOffset` with an absolute value.

For a live client test, use the capture watcher so the tooling stops as soon as
any native paste path fires. If the client uses `ServerPastePrefab` or
`ServerPlaceCurrentPrefab`, or `ServerPlaceSimpleEntityVolume`, this also
replays it with the requested offset; if the client uses another path such as
`ServerPasteEntity`, it reports that kind instead of waiting indefinitely:

```powershell
node .\brickadia-ue4ss-re\scripts\wait-prefab-native-capture-replay.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --expected-kind any `
  --require-player 1 `
  --replay-args "offset 2000 0 500" `
  --timeout-ms 300000 `
  --poll-ms 1000 `
  --status-path "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799\prefab-native-watch-status.json"
```

While the watcher is running, `prefab-native-watch-status.json` reports whether
it is `waiting-for-player`, `waiting-for-capture`, or has sent a replay command.
With `--require-player 1`, the watcher only polls `players.list` until a player
connects, then starts polling native hook state. The status payload includes
`watcher_session_id`, `started_at`, `status_seq`, `updated_at`, and `pid`, so a
restart or stale watcher can be distinguished from the current capture session.
On `CL13530`, avoid `--require-player 1` unless the player list path is the
specific diagnostic under test. `players.list` can report `count=0`, time out,
or stop bridge progress even while manual testing is in progress. The safer
default is to leave `--require-player` off and let hook/context polling prove
activity.
When a capture arrives, the final watcher JSON also includes `decoded_capture`,
which classifies `ServerPastePrefab`, `ServerPlaceCurrentPrefab`, and
`ServerPlaceSimpleEntityVolume` buffers, plus object-reference captures such as
`ServerPasteEntity` or `HandleAttachedPlacement`. Post-capture actor dumps are
disabled by default on CL13530. To opt into that crash-risk diagnostic, pass:

With `--expected-kind any`, the watcher ignores prefab upload/notification
handshake captures such as `ClientUploadPrefab`, `ServerUploadPrefab`, and
`ClientNotifyPrefabCaptureComplete`, plus diagnostic physics toggle captures
such as `SetPlaceAsPhysicsAvailable` and `SetPlaceAsPhysicsEnabled`; those can
happen before the actual replayable paste call and should not stop the vehicle
test early.
The Lua bridge also retains `last_replayable_client_capture` separately from
`last_client_capture`, so a later upload/notification hook cannot overwrite the
`ServerPastePrefab`, `ServerPlaceCurrentPrefab`, or
`ServerPlaceSimpleEntityVolume` record that replay needs.

```text
BrickGridDynamicActor,Entity_DynamicBrickGrid,BP_Entity_Wheel_Deep1_C,BP_Entity_Wheel_Deep2_C,BP_Entity_Wheel_C
```

That result is stored as `post_actor_dump` in the final watcher JSON. Its
summary is meant to separate a coherent dynamic vehicle candidate from the
broken state where wheel entities exist but the `BrickGridDynamicActor` has no
resolved location or root component.

The replay command only runs under `OMEGGA_UE4SS_UNSAFE_PROBES=1`, only replays
known native prefab-placement layouts, and only uses the live captured context
object. It rebuilds the `ProcessEvent` parameter buffer from the hook memory
snapshots, including native padding between parameters. Captures are labeled as
`source=client` or `source=replay`; replay uses the most recent client capture
when one is available, so repeated offset replays do not accidentally drift from
the previous replay capture. For `ServerPlaceCurrentPrefab`, offset/grid replay
adjusts all known grid-like placement vectors plus the reflected placement
double-vector fields by the same delta, not just the primary grid field. Replay
uses the short native function name from the matched layout, such as
`ServerPastePrefab` or `ServerPlaceCurrentPrefab`, instead of falling back to
the hook path.

Decode the latest persisted capture into the current native paste contract:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re
node .\scripts\decode-prefab-native-capture.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799"
```

After the watcher finishes, classify whether the native replay actually
produced a coherent dynamic vehicle candidate:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
node .\brickadia-ue4ss-re\scripts\verify-prefab-native-vehicle-replay.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799"
```

`status=vehicle-replay-coherent` requires a replayable client capture, a
successful native replay, a post-replay actor dump, and at least one coherent
`BrickGridDynamicActor` candidate with no vehicle warnings. `waiting-for-player`
or `waiting-for-capture` means the live test has not reached the native replay
stage yet.

## Source Prefab Sanity Check

Before testing vehicle behavior, verify that the source archive is actually a
physics-grid prefab. A copied clipboard vehicle can contain saved wheel and
`BrickGridDynamicActor` entity records while still declaring
`bIsPhysicsGrid=false`; in that case the paste/additive-load result can look
like a car, but it is not expected to become a movable physics actor.

Inspect the current clipboard:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
node .\brickadia-ue4ss-re\scripts\diagnose-prefab-vehicle-structure.js `
  "C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz" `
  --out-json ".\brickadia-ue4ss-re\notes\clipboard-vehicle-structure-latest.json"
```

Scan cached gallery prefabs for clean physics candidates:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
node .\brickadia-ue4ss-re\scripts\diagnose-prefab-vehicle-structure.js `
  --scan-gallery `
  --out-json ".\brickadia-ue4ss-re\notes\gallery-prefab-physics-scan-latest.json"
```

For a controlled clipboard-derived test input, rebuild the `.brz` with repaired
physics metadata and fresh archive hashes:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
node .\brickadia-ue4ss-re\scripts\patch-prefab-physics-metadata.js `
  "C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz" `
  ".\brickadia-ue4ss-re\artifacts\Clipboard.physics-meta.brz" `
  --force
```

This patcher does not rewrite entity/chunk payloads. It only repairs
`Meta/Prefab.json` using counts decoded from the archive, sets
`bIsPhysicsGrid=true`, adds an identity `worldRootTransform` when missing, and
recomputes the BRZ index/blob hashes. It is useful for testing whether the
client/native prefab path was rejecting the copied car because of bad prefab
metadata, but it does not prove additive loading can instantiate a dynamic
vehicle.

Do not treat this metadata patch as a safe additive-load fix. On
`2026-05-31`, loading an opt-in physics-metadata-patched `.brdb` generated from
the copied car reached `Loading prefab metadata` and then crashed the dedicated
server with `Assertion failed: Index == TypeIndex` in `TVariant.h:148`. The
default `.brz -> .brdb` builder therefore preserves `bIsPhysicsGrid=false`;
physics metadata patching is explicit and diagnostic only.

As of `2026-05-31`, the copied `Clipboard.brz` had 11 saved entities and joint
references but `bIsPhysicsGrid=false`, so it is not a clean dynamic-vehicle
source. Better native-paste candidates in the local gallery cache include
`Expedition Truck` (`044a0003-4d2b-4484-b9e6-1b93cbc06b68.brz`) and
`1986 Toyota Sprinter Trueno AE86`
(`8c04e0ee-87b3-4eef-b5de-659c60f1e9ac.brz`), both with
`bIsPhysicsGrid=true`, wheel entities, `BrickGridDynamicActor`, and matching
joint references.

Regenerate the live CL13530 native prefab diagnostic snapshot:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re
node .\scripts\capture-prefab-native-diagnostics.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799"
```

As of `2026-05-31T21:04:28Z`, that snapshot is in:

- `brickadia-ue4ss-re\notes\cl13530-prefab-native-diagnostics-latest.md`
- `brickadia-ue4ss-re\notes\cl13530-prefab-native-diagnostics-latest.json`

The diagnostic snapshot validates the replay ABI contracts against live
reflection. On the current server, `ServerPastePrefab`,
`ServerPlaceCurrentPrefab`, and `ServerPlaceSimpleEntityVolume` all report
`matches-live-reflection`. The snapshot also records `ServerUploadPrefab`,
`ClientUploadPrefab`, `SetPlaceAsPhysicsAvailable`,
`SetPlaceAsPhysicsEnabled`, and `ServerModifyEntity`; the upload path is
hash/cache driven rather than a raw archive-byte RPC, and the `SetPlaceAsPhysics*`
hooks are diagnostic toggles rather than replayable placements.

The live reflected `ServerPastePrefab` parameter buffer matches the static
model:

| Offset | Size | Meaning |
| --- | --- | --- |
| `0x00` | `0x20` | `BRPrefabHash` |
| `0x20` | `0x01` | `bWithOwnership` |
| `0x21` | `0x01` | `bInTemp` |
| `0x28` | `0x18` | `BRPrefabDetachedPasteInfo` |
| `0x28 + 0x00` | `0x08` | paste target object pointer |
| `0x28 + 0x08` | `0x0c` | `GridOffset` / `FIntVector` |
| `0x28 + 0x14` | `0x01` | `PlacementOrientation` |

### Prefab Hash Evidence

`ServerPastePrefab` is hash/cache driven. The best current local evidence says
the 32-byte `BRPrefabHash` is `BLAKE3(raw .brz archive bytes)`.

The known CL12960 log hash
`07C8E4AD16AC2B85B7FBE8637C9929AD9326ECA7384219F05937BD0F464BB7AD`
matches the raw-file BLAKE3 of this local gallery cache file:

```text
C:\Users\tycox\AppData\Local\Brickadia\Saved\GalleryCache\Prefabs\8c04e0ee-87b3-4eef-b5de-659c60f1e9ac.brz
```

Regenerate a hash/cache report with:

```powershell
node .\brickadia-ue4ss-re\scripts\prefab-hash-report.js `
  --clipboard `
  --scan-gallery `
  --out-json ".\brickadia-ue4ss-re\notes\prefab-hash-report-latest.json"
```

This does not by itself place a vehicle. It gives the native paste/cache path
the exact hash material it needs once the server-side in-memory cache import or
a real client upload/capture is available.

### Direct Hash Paste Probe

The bridge now exposes a narrow `ServerPastePrefab` probe that builds the
reflected `0x40`-byte parameter buffer from a known prefab hash:

```text
Omegga.Bridge.PastePrefabHash <64hex_hash> grid <x> <y> <z> [orientation] [ownership=1] [temp=0] [target=0|last] [dry-run]
```

Use the wrapper when starting from a `.brz` file:

```powershell
node .\brickadia-ue4ss-re\scripts\paste-prefab-hash.js `
  --brz "C:\Users\tycox\AppData\Local\Brickadia\Saved\GalleryCache\Prefabs\044a0003-4d2b-4484-b9e6-1b93cbc06b68.brz" `
  --grid 3000 0 700 `
  --orientation 0 `
  --target 0 `
  --dry-run 1
```

`--dry-run 1` proves command parsing and buffer construction without calling
native `ProcessEvent`. A non-dry run still requires a live player-controller
context and a matching native prefab-cache entry. If a real
`ServerPastePrefab` capture is available, `target=last` reuses the captured
`BRPrefabDetachedPasteInfo` target pointer; otherwise `target=0` leaves that
field null for diagnostics.

For the current CL13530 direct-hash path, prefer the safe wait harness over the
native capture watcher:

```powershell
node .\brickadia-ue4ss-re\scripts\wait-paste-prefab-hash.js `
  --brz "C:\Users\tycox\AppData\Local\Brickadia\Saved\GalleryCache\Prefabs\044a0003-4d2b-4484-b9e6-1b93cbc06b68.brz" `
  --grid 9000 0 1400 `
  --orientation 0 `
  --target 0 `
  --timeout-ms 300000
```

That script polls `Omegga.Bridge.DescribeServerPastePrefabContext`, writes
`prefab-hash-paste-status.json` under the bridge directory, and only calls
`PastePrefabHash` after a valid player-controller context exists. It skips
`players.list` and post-paste actor dumps by default on CL13530; use explicit
opt-in flags for those diagnostics after the paste path is already stable.

For vehicle prefabs, prefer proving the exact server-cached hash first instead
of guessing from a local `.brz`. Start this before manually spawning a known-good
drivable catalog/gallery vehicle:

```powershell
node .\brickadia-ue4ss-re\scripts\wait-cached-prefab-hash-paste.js `
  --grid 12000 0 2400 `
  --orientation 0 `
  --target 0 `
  --timeout-ms 300000
```

The script watches `Saved\Logs\Brickadia.log` from the current end of file,
waits for `LogBrickPrefabs: Caching prefab from serialized data (...)` followed
by `World successfully loaded additively`, then runs the same safe
`wait-paste-prefab-hash.js` context gate with the captured hash. This is the
current best path for testing whether server-side paste can reproduce a vehicle
that the normal client/native path has already proven is movable.

Current CL13530 evidence:

- Manual client spawn of a drivable vehicle cached hash
  `047F7BB17B6464F0393E38ACB8DBDD2B72DC153CCD359C3C6BBD743E8D34187A`
  at `2026-06-01T01:07:27Z`, then loaded additively at `01:07:29Z` and
  `01:07:30Z`.
- Direct `PastePrefabHash` dry-run against that cached hash succeeded with
  `context_source=player-state-owner`.
- Direct non-dry-run `PastePrefabHash ... grid 12000 0 2400 ... target=0`
  returned `ok=true`, `result=true`, and
  `ProcessEvent ... bytes=64 parms_size=0x40` at `2026-06-01T01:08:30Z`.
- The dedicated server process stayed alive afterward and no new crash folder
  was created. In-game visual/drivability verification of that second direct
  paste is still the required pass/fail gate.

On CL13530, do not use `Omegga.Bridge.InstallPrefabNativeHooks all` for this
direct test. UE4SS Lua `RegisterHook` can crash while pushing prefab struct
parameters before the Lua callback runs. The current bridge installer skips
known unsafe struct-param hooks by default; pass `unsafe` only for an
intentional crash-risk capture experiment.

The live capture watcher now runs that same hash paste path in dry-run mode
after a real `ServerPastePrefab` capture:

```text
--post-hash-paste dry-run --post-hash-paste-target last
```

That keeps the normal replay result clean while verifying the newly decoded
hash can be used to build a direct paste command. Use `--post-hash-paste 1`
only for an intentional real second paste after cache/context have been proven.

The live reflected `ServerPlaceCurrentPrefab` parameter buffer is also
replayable:

| Offset | Size | Meaning |
| --- | --- | --- |
| `0x00` | `0x80` | placement-state struct |
| `0x80` | `0x0c` | primary grid / `FIntVector` |
| `0x90` | `0x18` | placement vector |
| `0xA8` | `0x01` | orientation |
| `0xAC` | `0x0c` | extra grid-like parameter |
| `0xB8` | `0x0c` | extra grid-like parameter |
| `0xC4` | `0x0c` | extra grid-like parameter |
| `0xD0` | `0x0c` | extra grid-like parameter |
| `0xDC` | `0x01` | bool |
| `0xDD` | `0x01` | bool |
| `0xDE` | `0x01` | bool |

Offset replay adjusts the primary grid field, the four extra grid-like fields,
`PlacementState.Transform.Translation`, and `PlacementVector` for
`ServerPlaceCurrentPrefab` by the same delta. This keeps the native placement
state together, but it is still a replay contract rather than a guarantee that
arbitrary copied `.brz` data will become a native dynamic vehicle without a real
client-side native prefab capture.

The live reflected `ServerPlaceSimpleEntityVolume` parameter buffer is now also
treated as replayable. This matters if catalog vehicles use the simple entity
volume placement path instead of the prefab placement path:

| Offset | Size | Meaning |
| --- | --- | --- |
| `0x00` | `0x80` | placement-state struct |
| `0x80` | `0x08` | entity class/object pointer |
| `0x88` | `0x04` | orientation/flags bytes |
| `0x8C` | `0x0c` | primary grid / `FIntVector` |
| `0x98` | `0x18` | placement vector |
| `0xB0` | `0x01` | bool-like parameter |
| `0xB4` | `0x0c` | extra grid-like parameter |
| `0xC0` | `0x0c` | extra grid-like parameter |
| `0xCC` | `0x0c` | extra grid-like parameter |
| `0xD8` | `0x0c` | extra grid-like parameter |

Offset replay adjusts the primary grid field, the four extra grid-like fields,
`PlacementState.Transform.Translation`, and `PlacementVector` for
`ServerPlaceSimpleEntityVolume` by the same delta.

Avoid broad runtime object scans while debugging this path. Commands such as
`Omegga.Bridge.DescribePrefabRuntime` with broad class lists have previously
hung or killed the test server on `CL13530`; prefer hook state, capture decode,
and readiness probes.

This is a replay contract, not a complete headless implementation. The replay
path can repeat a native paste once a client has created a valid capture; the
missing pieces are still native-cache materialization for arbitrary `.brz` bytes
and a durable controller/player context for invoking the server RPC path without
a preceding client paste.

## Command Execution Path

Several console execution paths exist in the bridge:

- `engine`
- `cached`
- `kismet`
- `consolemanager`

The path that currently works for `BR.World.LoadAdditive` is `consolemanager`.
The Lua bridge command is:

```text
Omegga.Bridge.ForceConsoleExecutor consolemanager <command...>
```

For prefab loading, that becomes:

```text
Omegga.Bridge.ForceConsoleExecutor consolemanager BR.World.LoadAdditive <world_name> <x> <y> <z> <orientation>
```

The implementation lives in the OmeggaBridge Lua template:

- `OmeggaForceConsoleExecutor(...)` dispatches to the requested executor.
- `Omegga.Bridge.DescribeConsoleManager` calls the native diagnostic helper.
- `Omegga.Bridge.ForceConsoleExecutor ...` is parsed and routed through
  `OmeggaForceConsoleExecutor(...)`.

## Console Manager Native Helper

UE4SS exposes:

```lua
OmeggaExecuteConsoleManagerInput(command, vtableOffset)
```

The default `vtableOffset` is `0xE0`, which is the observed
`IConsoleManager::ProcessUserConsoleInput` slot for this engine build.

The native helper does this:

1. Resolves the console manager singleton.
2. Reads the `ProcessUserConsoleInput` function pointer from the singleton's
   vtable at offset `0xE0`.
3. Finds an active `UWorld`.
4. Calls `ProcessUserConsoleInput(consoleManager, command, outputDevice, world)`.

`Omegga.Bridge.DescribeConsoleManager` is the main diagnostic command. A healthy
result should show non-null values for `initializer`, `slot`, `singleton`,
`world`, and `process_input`.

The `ConsoleManagerSingleton` signature is slightly misleading: PatternSleuth
finds the initializer function, not the singleton object itself. The UE4SS side
caches that initializer address, then scans the initializer bytes to find the
RIP-relative slot that stores the singleton pointer.

## World Context

`ProcessUserConsoleInput` must receive a real `UWorld*`. Calling it with a null
world crashed during testing, with the process reading through a null-relative
field near `+0x1d8`.

The current UE4SS build caches world candidates from normal engine paths,
including map load/game-state paths and actor `GetWorld()` paths. The console
manager helper uses the cached world first, then falls back to an active-world
scan.

One known annoyance: object names are degraded in this setup. Diagnostics may
show a non-null world pointer while `world_name` is not useful. Trust pointer
presence and the follow-up server log more than `GetFullName()` output.

## Prefab Artifact Flow

Brickadia prefab archives and world bundles use a named-file layout with paths
such as:

- `Meta/Bundle.json`
- `Meta/Prefab.json`
- `World/0/Bricks/...`
- `World/0/Entities/...`

The source clipboard/gallery file is a `.brz` archive. The server additive-load
path expects a world bundle in `.brdb` form under the server's `Saved\Worlds`
directory.

The conversion script is:

```powershell
node .\brickadia-ue4ss-re\scripts\build-prefab-world-brdb.js `
  "C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz" `
  "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Worlds\PrefabBridge_ClipboardDynamic.brdb" `
  Plate
```

`build-prefab-world-brdb.js` converts `.brz` to `.brdb`, then rewrites metadata
so the bundle looks like a world bundle:

- `Meta/Bundle.json` gets `type: "World"`.
- `Meta/World.json` is written with the selected environment, usually `Plate`.
- `Meta/Prefab.json` is preserved by default. Use `--patch-physics-metadata`
  only for isolated diagnostics; it can crash additive loading for copied
  dynamic vehicles.

For the current dynamic vehicle clipboard, the active candidate is the simplest
world conversion with no archive chunk rewrite:

```powershell
node .\scripts\build-prefab-world-brdb.js `
  "C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz" `
  "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Worlds\PrefabBridge_ClipboardDynamic_NoRewrite_2000_0_1000.brdb" `
  Plate
```

The matching load command still carries the world-space additive offset:

```powershell
node .\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.ForceConsoleExecutor consolemanager BR.World.LoadAdditive PrefabBridge_ClipboardDynamic_NoRewrite_2000_0_1000 2000 0 1000 16" `
  --wait-ms 60000
```

This no-rewrite candidate was loaded on a clean server on `2026-05-31` and the
server log showed `World successfully loaded additively` without wire-port
errors. Visual correctness still needs to be checked in-game.

An entity-only placement variant also loaded without serializer errors, but a
manual in-game check still showed the car body and door separated. Treat that
variant as disproven for visual correctness.

`--placement-offset` is not a simple transform baked into every payload. That
older all-chunk rewrite does this:

- Recomputes BRDB blob hashes with BLAKE3 after every modified blob.
- Moves `World/0/Entities/ChunkIndex.mps` and entity chunk file names by
  500-unit entity chunks.
- Moves brick `Chunk3DIndices` and brick `Chunks`/`Components`/`Wires` file
  names by whole brick chunks. Current clipboard chunk size is `2048`, so
  `x = 2000` moves the brick chunk index by `+1`.
- Preserves brick `ChunkOffsets` exactly as saved. Editing those offsets caused
  Brickadia to reject the load with `Invalid chunk offset ... expected ... for
  non-additive load`.
- Rewrites `RemoteWireSources[].ChunkIndex` inside wire chunks so remote wires
  still point at the moved brick chunks.
- Handles shared BRDB blobs once. Several grid `ChunkIndex.mps` files can point
  at the same blob; mutating shared blobs per file caused accidental double
  placement on some grids.

Do not use the all-chunk or entity-only rewrites for the current dynamic car
clipboard unless you are specifically testing serializer behavior. Both can
load cleanly while still leaving body pieces apart from their dynamic
grid/entity origins.

Important: stage the `.brdb` file in `Saved\Worlds` before the first
`BR.World.LoadAdditive` attempt. A missing-file first load can poison the bundle
cache until a server restart and previously led to an assertion around
`BRWorldManager.cpp:863`.

## Loading A Staged Prefab

Start a test server:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re
.\scripts\start-bridge-test-server.ps1 -Port 7799 -VerifyWaitSeconds 45 -EnableUnsafeProbes
```

Send a load request:

```powershell
node .\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.ForceConsoleExecutor consolemanager BR.World.LoadAdditive PrefabBridge_ClipboardDynamic_NoRewrite_2000_0_1000 2000 0 1000 16" `
  --wait-ms 60000
```

The current visual-test candidate loaded
`PrefabBridge_ClipboardDynamic_NoRewrite_2000_0_1000` at:

- `2000 0 1000`, orientation `16`

Older exploratory loads used `PrefabBridge_ClipboardDynamic` at:

- `0 0 250`, orientation `16`
- `400 0 250`, orientation `16`
- `2000 0 300`, orientation `16`

Use large offsets for visual tests. Additive loads do not clean up previous
copies, and overlapping vehicles make debugging physics nearly impossible.

## Expected Server Log

After a successful command, `Saved\Logs\Brickadia.log` should include this
sequence in some form:

```text
Opening existing bundle
Loading world additively from bundle
Loading prefab metadata
Spawning entities and grid serializers
Applying brick chunks
World successfully loaded additively
```

Check the log tail with:

```powershell
Get-Content "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Logs\Brickadia.log" -Tail 100
```

## Dynamic Entity And Vehicle Notes

The current conversion preserves the archive files, but it does not invent or
repair vehicle/entity relationships. If the source `.brz` does not contain the
right dynamic actor/entity data, the loaded result will not become a correct
vehicle just because it was converted to a world `.brdb`.

Observed states:

- The older `HL2 Jeep` gallery archive loaded as a static brick body plus wheel
  entities. It did not include a `BrickGridDynamicActor` in the inspected entity
  data.
- The later `Clipboard.brz` captured on `2026-05-31` contained dynamic actor
  entity data. Observed entity struct names included
  `BP_Entity_Wheel_Deep1_C` and `BrickGridDynamicActor`.
- That clipboard could load with entities, but the vehicle could still collapse
  in-game. That suggests the remaining issue is not just "entity present or
  absent"; it may be transform, weld, owner, joint, or reference data that is
  not being preserved correctly by the source copy or by our conversion path.
- A clean zero-offset additive load of `PrefabBridge_ClipboardDynamic` succeeded
  on `2026-05-31`. Large additive placement offsets still appear to split
  dynamic entity payloads from some brick/grid payloads.
- An all-chunk placement load of
  `PrefabBridge_ClipboardDynamic_PlacedChunks_2000_0_500` succeeded cleanly on
  `2026-05-31`, but visual testing showed body pieces could still split from
  the rest of the car.
- An entity-only placement load of
  `PrefabBridge_ClipboardDynamic_EntityOnly_2000_0_1000` succeeded cleanly on
  `2026-05-31` after moving only entity chunk indices/file names and leaving
  brick grid chunk indices local to their dynamic grid entities, but manual
  inspection still showed the body/door separation.
- A no-rewrite load of `PrefabBridge_ClipboardDynamic_NoRewrite_2000_0_1000`
  succeeded cleanly on `2026-05-31`, but manual inspection still showed
  separated dynamic pieces.
- A gallery/catalog vehicle source with `bIsPhysicsGrid: true` also loaded
  additively in the air, but it did not become an entity/physics object in the
  server world. This strongly suggests additive loading bypasses the native
  placement path that creates the dynamic actor/physics object.
- A later additive load placed the vehicle body higher, but the selection still
  was not a physics entity; manually converting it into a physics object caused
  the vehicle to fall apart. Treat this as the same failure mode, not progress
  toward a valid dynamic vehicle paste.
- Directly baking a large world offset into `World/0/Entities/Chunks/*.mps`
  `Locations` is unsafe. A `Z + 500` experiment asserted in
  `TVariant.h:148` while Brickadia was creating entity serializers, which
  suggests those packed locations are local to the entity chunk or coupled to
  type-specific tail data.

Treat additive vehicle correctness as disproven for the current approach. The
next meaningful vehicle test is a normal client catalog/prefab paste with the
native hooks armed, followed by `Omegga.Bridge.DescribeLastPrefabNativeCapture`
or inspection of `prefab-native-last.txt`.

## Current Verification Commands

Focused conversion/unit test:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re
node .\scripts\test-prefab-world-bridge.js
```

Focused physics metadata patch/repack test:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
node .\brickadia-ue4ss-re\scripts\test-patch-prefab-physics-metadata.js
```

Focused native watcher verifier tests:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia
node .\brickadia-ue4ss-re\scripts\test-prefab-native-watch-actor-dump.js
node .\brickadia-ue4ss-re\scripts\test-prefab-native-readiness-status.js
node .\brickadia-ue4ss-re\scripts\test-verify-prefab-native-vehicle-replay.js
```

Focused UE4SS build:

```powershell
cd C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS
cmake --build build_cmake_local_Game__Shipping__Win64 --config Game__Shipping__Win64 --target UE4SS
```

Bridge diagnostic while the server is running:

```powershell
cd C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re
node .\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.DescribeConsoleManager" `
  --wait-ms 30000
```

## Known Failure Modes

- Seed signatures are not enough after a client/server update. Hash tables,
  vtable offsets, and singleton-resolution logic may need regeneration or
  validation.
- A missing first `BR.World.LoadAdditive` request can poison the bundle cache
  until restart.
- Modified `.mps` blobs need their BLAKE3 hash recomputed in the BRDB `blobs`
  row. A stale hash produced `Decompressed blob hash mismatch`.
- Brick `ChunkOffsets` are validator-sensitive. Preserve them; move brick chunk
  indices and file names instead.
- Moving brick chunk indices without moving wire `RemoteWireSources` produced
  `Invalid remote wire source chunk index -1_-1_-1`.
- `consolemanager` is the known-good executor for additive world loading. Other
  executors can succeed for simpler commands but fail to reach this command path.
- The low-level helper is unsafe. It assumes the game thread, a valid world, a
  valid singleton, and a matching vtable offset.
- Additive load tests should use a clean server or large spawn offsets.
- Current diagnostics may show poor object names because name resolution is not
  fully healthy in this setup.
- `DumpPrefabActors` must not call `K2_GetActorLocation` or
  `GetActorLocation` by default on this UE4SS build. Those struct-returning
  UFunction calls crashed the dedicated server in
  `UE4SS.dll!RC::LuaType::push_structproperty()` on `2026-05-31`. The bridge
  now skips them unless `OMEGGA_UE4SS_PREFAB_DUMP_CALL_LOCATION_UFUNCTIONS=1`
  is explicitly set.
- `DumpPrefabActors` and `DescribePrefabRuntime` must also avoid reflected
  object property reads by default on CL13530. Reading `RootComponent`,
  `ReplicatedMovement`, and similar properties can hit the same
  `push_structproperty()` crash path. Set
  `OMEGGA_UE4SS_PREFAB_DUMP_READ_OBJECT_PROPERTIES=1` only for an intentional
  crash-risk diagnostic run.
- Native paste capture keeps `ReadBytesHex()` snapshots for replay, but also
  skips reflected hook-parameter property/vector probes by default. Those
  optional decoded property lines are useful for diagnostics, but they are not
  required for replay and can hit the same unsafe property path.
- Do not use `players.list` as a prerequisite for direct prefab paste
  readiness. On CL13530, `DescribeServerPastePrefabContext` can prove a valid
  player-controller context while `players.list` times out or stops bridge
  progress. The direct hash paste harness and readiness reporter skip it by
  default.
- The bridge Lua main chunk is at UE4SS Lua's 200-local limit. New top-level
  diagnostic switches should be globals or folded into an existing table; adding
  another `local` can prevent the mod from loading before `bridge.log` exists.

## Future Lua API Shape

The eventual high-level API should hide the unsafe pieces above. A reasonable
first shape is:

```lua
Omegga.Prefabs.BuildWorldBundle({
  source = "C:/Users/tycox/AppData/Local/Brickadia/Saved/Temp/Clipboard.brz",
  name = "PrefabBridge_ClipboardDynamic",
  environment = "Plate",
})

Omegga.Prefabs.LoadWorld({
  name = "PrefabBridge_ClipboardDynamic",
  position = { x = 2000, y = 0, z = 300 },
  orientation = 16,
})
```

That wrapper should validate staging before load, reject missing bundle names,
centralize offsets/orientation, provide structured success/failure responses,
and expose an entity-summary diagnostic before attempting vehicle tests.
