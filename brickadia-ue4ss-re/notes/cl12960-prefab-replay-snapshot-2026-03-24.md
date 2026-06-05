# CL12960 Prefab Replay Snapshot

Date: March 24, 2026

## Problem

The goal is to load a prefab, such as the test car, into a dedicated CL12960 Brickadia server without needing a live player client to perform the placement.

In practical terms, we want to:

1. Observe the real runtime path the game uses when a player loads a prefab.
2. Identify the server-side objects and state involved in that load.
3. Capture enough of that state safely to understand the handoff.
4. Eventually replay that load automatically from the dedicated server at startup.

The hard part is that we still do not have decoded brick/prefab payload data. We can see the runtime surface and the additive load path, but the expected prefab fields still resolve through UE4SS as placeholder-style `UObject` userdata wrappers instead of decoded arrays/structs.

## What We Are Testing

The active probe is:

- `WorldStateLiveSampler`
  - Script: `probes/CL12960/WorldStateLiveSampler/Scripts/main.lua`
  - Launcher: `scripts/start-world-state-live-sampler-server.ps1`

The canary/report entrypoint is:

- `scripts/run-world-export-canary-tests.py`
- Output:
  - `notes/cl12960-world-export-canary-latest.json`
  - `notes/cl12960-world-export-canary-latest.md`

The main test groups are:

1. Context resolution
   - Can we resolve `UWorld`, `GameMode`, `GameState`, `GameSession`, and `GameInstance`?

2. Discovery leads
   - Can we find relevant runtime classes and keyword/property/function leads?

3. Prefab native leads
   - Does the binary expose plausible prefab/load/replay functions and classes?

4. Live prefab runtime
   - During a real player-driven prefab load, do the expected runtime objects appear?
   - Can we probe safe native getters?
   - Can we capture replay-side handle/state relationships without crashing the game?

## What We Have Proved

### 1. The additive prefab load path is real and repeatable

The server log repeatedly shows:

- `Caching prefab from serialized data`
- `Loading world additively from bundle`
- `Loading prefab metadata`
- `Spawning entities and grid serializers`
- `Applying brick chunks`
- `World successfully loaded additively`

That means the target behavior is definitely happening on the dedicated server already when a player loads a prefab.

### 2. The right runtime surfaces appear during prefab load

During live car/prefab loads, we repeatedly see:

- `BRWorldManager`
- `BRBundleArchive`
- `BRBundleTransferComponent`
- `BrickGridDynamicActor`
- `BrickGridActor`
- `BrickGridComponent`

That gives us a believable replay-side target surface.

### 3. We have a safe replay-surface capture now

The sampler now records a `latest_replay_surface_capture` whenever prefab-related counts jump, and it can tag the capture by load phase.

This means we can safely snapshot the runtime bundle/load surface when a prefab is loaded, without invoking unsafe upload/accept methods.

### 4. We can diff replay captures across runs

We now have replay-surface history and a diff view across multiple prefab loads.

Current result:

- repeated property aliases across captures: `none yet`
- the latest alias history still does not expose a stable cross-run payload owner
- the handle surface is still churning heavily, especially once late transfer/archive properties enter the window

So we can compare loads now, but the handle surface is still highly volatile.

### 5. The additive load has a staged runtime shape now

The most useful new result from the March 24 evening captures is that the sampler no longer collapses the whole load into a generic transfer label.

The dedicated-server prefab load now resolves as a staged sequence:

1. `2026-03-24 21:20:34 EDT`
   - phase: `grid_component_window`
   - transitions:
     - `BrickGridActor 1 -> 2`
     - `BrickGridComponent 1 -> 4`
     - `BRBundleTransferComponent 0 -> 1`

2. `2026-03-24 21:20:40 EDT`
   - phase: `transfer_window`
   - transition:
     - `BRBundleArchive 0 -> 1`

3. `2026-03-24 21:20:45 EDT`
   - phase: `grid_component_window`
   - transitions:
     - `BrickGridActor 2 -> 14`
     - `BrickGridComponent 4 -> 29`
     - `BrickGridDynamicActor 0 -> 12`

This is important because it means the replay/load target is not just "watch the transfer component and hope."

We now have evidence that the additive handoff has a real grid-side materialization stage, and that stage is visible on dedicated server without invoking unsafe replay methods.

## What We Tested In The Past

### Dead end: `GetBrickGrid`

We spent time testing:

- `BrickGridActor->GetBrickGrid`
- `BrickGridDynamicActor->GetBrickGrid`
- `BrickGridComponent->GetBrickGrid`

Result:

- `BrickGridActor->GetBrickGrid` and `BrickGridDynamicActor->GetBrickGrid` do call through a real path.
- But the returned value is a `placeholder_null_wrapper`, not a decoded grid object.
- That path does not currently give us usable prefab/grid payload data.

Conclusion:

- `GetBrickGrid` is not the extraction path we need.

### Unsafe replay/upload probing

We briefly tried probing names such as:

- `ServerUploadPrefab`
- `ClientUploadPrefab`
- `ClientLoadWorldAccepted`
- `ClientLoadWorldRejected`

Result:

- These are real binary leads.
- But blind zero-arg live probing was unsafe and triggered a `PendingWorldUpload` assertion.

Conclusion:

- Those names remain useful RE leads.
- They are not safe to call blindly in live sessions.

## Where We Are Now

### Current scoreboard

From `notes/cl12960-world-export-canary-latest.md`:

- Total: `36`
- Passed: `30`
- Failed: `0`
- Blocked: `6`

### Current live status

What passes now:

- Context resolution
- Additive prefab load trace
- Runtime prefab/archive surface detection
- Safe replay-surface capture with phase labels
- Replay history diffing
- Binary replay/native lead discovery
- Grid-side additive-load staging on dedicated server

What is still blocked:

1. `world-export-live-grid-getter-decoder-status`
   - `GetBrickGrid` still returns a placeholder wrapper, not a decoded object.

2. `world-export-live-replay-native-surface`
   - Unsafe replay/upload calls are intentionally disabled in live probing.

3. `world-export-live-prefab-property-decoder-status`
   - Expected prefab fields such as `ChunkOffsets`, `ChunkSizes`, `OwnerIndices`, `RelativePositions`, and `PrefabMetadata` are still unresolved placeholder-style userdata wrappers.

### Best current reading

We are no longer lost on whether there is a server-side target.

We do have:

- the real server-side additive prefab load path
- the right runtime classes
- safe capture of replay-side state when a prefab is loaded
- history/diff tooling across multiple loads
- a staged runtime model where grid-side expansion is distinct from later transfer/archive churn

We do not yet have:

- decoded prefab brick payloads
- a stable reusable bundle handle
- proof of headless replay

The current dedicated-server target model is:

- early broker/archive/runtime witnesses:
  - `BRWorldManager`
  - `BRBundleTransferComponent`
  - `BRBundleArchive`
- actual additive materialization surface:
  - `BrickGridActor`
  - `BrickGridComponent`
  - `BrickGridDynamicActor`

That is a stronger model than the earlier "maybe everything important is on `BRBundleTransferComponent`" assumption.

## Biggest Current Risk

The replay-side handles churn heavily across captures.

That means:

- single-load handle matches are not trustworthy by themselves
- one-off alias matches can be misleading
- we need repeated relationships that survive multiple captures before we promote them to real replay signals
- late transfer/archive churn can still overwrite or distract from the earlier grid-side phase if we are not careful about which capture we treat as primary

## Recommended Next Step

Stay on the safe replay-side path, but center the next round on the grid-side additive window instead of treating transfer churn as the whole story.

Priority order:

1. Keep collecting replay-surface captures across repeated prefab loads, but prioritize the `grid_component_window` captures over the final generic "latest" capture.
2. Treat `BrickGridActor`, `BrickGridComponent`, and `BrickGridDynamicActor` as first-class replay targets alongside `BRBundleArchive`.
3. Narrow on relationships that survive from the early grid-side stage into the later archive/transfer stage.
4. Ignore `GetBrickGrid` as a decode target unless new evidence contradicts that.
5. Do not call upload/accept/reject replay methods live without first understanding their required state/arguments.
6. On the static side, keep climbing toward the reflected additive-load entrypoint that lines up with the observed `grid_component_window` stage.

## Current Bottom Line

We have successfully moved from:

- "maybe the server can do this"

to:

- "the server definitely performs additive prefab loads, and we can safely capture the replay-side runtime surface when it does."

But we have not yet crossed into:

- "we can decode the prefab payload and replay it headlessly on startup."

That is still the next major unlock.

The best new news is that the target is clearer now: the dedicated-server additive path is visibly materializing through the grid stack, not just through bundle-transfer bookkeeping.

## 2026-03-25 static additive-request update

- Proved `RequestLoadWorldAdditive` is a reflected `UBRBundleManager` method and corrected the thunk mapping:
  - `FUN_144167890` = `RequestLoadWorldAdditive`
  - `FUN_144167c30` = `RequestTravelToWorld`
- `FUN_144167890` decodes a reflected `String` argument first, then decodes a reflected `Params` argument with defaults, and forwards into `FUN_1446ea340`.
- `FUN_1446ea340` packages a small request record on the heap, binds callback `FUN_1446ea4c0`, and kicks `FUN_1446e9b70(param_1, param_2, 3, 2)`.
- `FUN_1446ea4c0` resolves a world-side receiver and only calls the additive launcher when the async bundle/load result is actually present:
  - `FUN_14473cae0(lVar3, *param_2, param_3, local_88)`
- `FUN_14473cf60` is the lower additive stage runner. It logs both:
  - `Loading world additively from bundle.`
  - `World successfully loaded additively.`
- `FUN_14473cf60` calls `FUN_1447330c0`, which drives the staged prefab serializer path. Confirmed stage order in this lane:
  - `Loading prefab metadata.`
  - `Deserializing entity chunks.`
  - `Spawning entities and grid serializers.`
  - `Creating brick chunk serializers.`
  - `Deserializing brick chunks.`
  - `Applying brick chunks.`
- Post-apply helpers `FUN_144733f20` / `FUN_1447341d0` are move/cleanup-style result transfer helpers, which suggests the additive lane returns a concrete result object rather than just a fire-and-forget status.
- Strong current inference:
  - first reflected arg = additive target string (bundle/world key still not fully named)
  - second reflected arg = `BRLoadWorldAdditiveParams`
  - async callback result supplies the bundle/archive object consumed by the lower additive lane
- Remaining static gap:
  - name and meaning of the `BRLoadWorldAdditiveParams` fields
  - whether the first string is the exact pending bundle key or a higher-level world identifier
- Practical next move if static naming stalls:
  - widen the live sampler around `UBRBundleManager`, especially `GetPendingWorldBundle`, so we can correlate the reflected request owner with the existing grid/archive replay surface.

## 2026-03-25 additive params / bundle-key update

- `FUN_1446e9b70` does not treat the reflected `String` like a file path.
  - It hashes the string and looks it up in an internal table on the bundle-manager side.
  - Current read: the first `RequestLoadWorldAdditive` argument is a bundle/cache key or logical world-load identifier.
- `FUN_1446ea000` confirms the lower world-load plumbing still opens `Meta/World.json` from the resolved bundle object after the keyed lookup succeeds.
- `FUN_1446e9b70` is shared by both:
  - the additive reflected path
  - the transfer-component path
- Transfer-side comparison point:
  - `FUN_1447acbe0` calls `FUN_1446e9b70(uVar4, param_1 + 0x158, 3, *(u8 *)(param_1 + 0x168))`
  - that means the transfer component stores its own keyed string at `+0x158`, and both lanes converge on the same bundle-lookup helper.
- Partial `BRLoadWorldAdditiveParams` field recovery from the reflected data neighborhood:
  - `GlobalGridTarget`
  - `PreviewPart`
  - `bEnforceBuildZonesForGlobalGrid`
  - `bEnforceComponentQuotas`
  - `bAllowAdminGates`
- Strong validation clue from surviving diagnostic string:
  - `(Params.GlobalGridTarget && !Params.PreviewPart) || (!Params.GlobalGridTarget && Params.PreviewPart)`
  - current inference: additive load requires exactly one of `GlobalGridTarget` or `PreviewPart`
- One more nearby validation string exists:
  - `Params.BrickGrid is invalid.`
  - not yet pinned to the same exact validator, but it is a strong candidate for another additive-param constraint.
- Remaining gap:
  - prove the concrete keyed string used by the transfer path (`param_1 + 0x158`) and compare it directly to the reflected additive string argument.

## 2026-03-25 transfer-component world bundle lane update

Static transfer-component work tightened the upload/load staging around the dedicated-server prefab path.

Confirmed reflected BRBundleTransferComponent RPC table entries:
- `ClientLoadWorldAccepted -> FUN_144168b80`
- `ClientLoadWorldRejected -> FUN_144168c20`
- `ClientNotifyNotFound -> FUN_144168d00`
- `ClientSaveWorldFailed -> FUN_144168ef0`
- `ClientUploadPrefab -> FUN_144169080`
- `ServerCancelDownloadRequest -> FUN_1441691e0`
- `ServerNotifyNotFound -> FUN_144169240`
- `ServerRequestDownloadWorldThenLoad -> FUN_144169340`
- `ServerSaveAndSendWorld -> FUN_144169430`
- `ServerUploadPrefab -> FUN_144169530`

Important separation:
- `UserUpload.brz` is constructor-seeded on `BRBundleTransferComponent + 0x1a8`, not the later accepted-load field.
- `FUN_1447a7040` seeds that default name.
- `FUN_1447a9bc0` and `FUN_1447ac640` both consume `param_1 + 0x1a8`.

What `+0x1a8` does:
- `FUN_1446edd00(manager, ..., transfer+0x1a8)` closes/removes an existing bundle entry for that name. If it fails, it reports `Bundle not found.` / `Bundle could not be closed.`
- `FUN_1446913f0(bundle, ..., transfer+0x1a8)` is `BRBundle::SerializeToDisk`, so the same string is used as the disk/bundle name for the world-save lane.
- `FUN_1447ac640` then calls `FUN_1446e9940(..., transfer+0x1a8, param_3, 1, 0, 3)`, so the same name is reused when reopening/loading the saved bundle through the lower world-load helper.

This makes the current model:
1. `ServerSaveAndSendWorld`
2. save result bundle serialized through `BRBundle::SerializeToDisk`
3. bundle name/key in this local upload lane is `UserUpload.brz` at `transfer + 0x1a8`
4. later accepted-load continuation still uses a different transfer-component string field (`+0x158` from the earlier `FUN_1447acbe0` read), so there are at least two distinct bundle-identity stages in play

Other useful confirmations:
- `FUN_1447aaff0` serializes the save-result bundle to an array via `FUN_144691760` (`BRBundle::SerializeToArray`) before building the `PrefabDownload + WORLD` request in `FUN_1447ab1e0`.
- `ServerRequestDownloadWorldThenLoad -> FUN_1447ac1d0` stores an incoming integer at `transfer + 0x178`, flips `transfer + 0x17c = 1`, arms callback `FUN_1447ac420`, and does not itself populate the later accepted-load string.

Current read after this pass:
- `UserUpload.brz` is definitely a real bundle name/key in the local save/send lane, not just a cosmetic filename.
- The later `ClientLoadWorldAccepted` / `FUN_1447acbe0` continuation still appears to consume a second-stage bundle identity that is not trivially the same field.
- The remaining gap is likely either a network/replication handoff or a different manager-side cached bundle field, not the outer transfer RPC thunks.

### BRWorldManager cached-bundle gate note

A second useful static clue landed from `BRWorldManager.cpp`:
- assert string: `CachedWorldBundle->GetState() == EBRBundleState::OpenOrOpening || CachedWorldBundle->GetState() == EBRBundleState::ClosedOrClosingTransient`
- source breadcrumb: `C:/BR/Sync/Release-EA2/Source/Brickadia/Core/Worlds/BRWorldManager.cpp:804`
- direct callsite decompiled from `FUN_1447356c0`

Why this matters:
- the world-manager side is explicitly asserting a valid cached-bundle state before it falls into the lower staged world/prefab load work and `FUN_1447330c0`.
- that makes `UBRWorldManager::CachedWorldBundle` a first-class live target for the next capture, not just a background property.
- current inference: the transfer/component lane likely prepares or hands off bundle identity, but the world-manager cached-bundle state is one of the concrete manager-side preconditions for the later load stage.

## 2026-03-25 live bundle-property capture after focused car spawn

The focused live capture answered the world-manager question directly.

Server log sequence from the fresh run:
- `2026-03-25 14:14:34` local log timestamp: `Caching prefab from serialized data`
- `2026-03-25 14:14:37` local log timestamp: first additive load burst
- `2026-03-25 14:14:40` local log timestamp: second additive load burst
- both bursts reached `World successfully loaded additively`

Most important live result:
- the sampler now surfaced bundle-property names on both `BRBundleTransferComponent` and `BRWorldManager` during the same replay/load window.

`BRBundleTransferComponent` properties observed changing in the replay burst:
- `CachedWorldBundle`
- `CurrentWorldBundle`
- `PendingWorldBundle`
- `PrefabArchive`
- `PrefabsInProgress`
- `SavedWorldBundle`

`BRWorldManager` properties observed changing in the replay burst:
- `CachedWorldBundle`
- `CurrentWorldBundle`
- `PendingWorldBundle`
- `PrefabArchive`
- `PrefabsInProgress`
- `SavedWorldBundle`
- `WorldSerializer`

Concrete replay capture evidence from the latest burst (`capture_index=18`):
- `BRBundleTransferComponent.CachedWorldBundle` changed
- `BRBundleTransferComponent.PendingWorldBundle` changed
- `BRBundleTransferComponent.SavedWorldBundle` changed
- `BRWorldManager.CachedWorldBundle` changed
- `BRWorldManager.PendingWorldBundle` changed
- `BRWorldManager.SavedWorldBundle` changed
- archive-side chunk arrays changed at the same time (`ChunkOffsets`, `ChunkSizes`, `OwnerIndices`, `PrefabInfo`, `PrefabMetadata`, `RelativePositions`)

Why this matters:
- the dedicated-server prefab load is now visibly coupling archive-side chunk movement with world-bundle state movement on both the transfer component and the world manager.
- this strongly upgrades the earlier cached-bundle inference: `BRWorldManager::CachedWorldBundle` is not just a static code clue, it is active in the real prefab replay window.
- strongest current inference: the earlier anonymous accepted-load string read on `BRBundleTransferComponent` is likely one of the reflected bundle-identity properties now confirmed live, with `PendingWorldBundle` the leading candidate and `CachedWorldBundle` the next candidate. This is still an inference, not a proof.

Net effect on the RE plan:
- we no longer need to treat the bundle-identity surface as opaque.
- next work should center on mapping the accepted-load native field use to one of the now-confirmed reflected names (`PendingWorldBundle`, `CachedWorldBundle`, `SavedWorldBundle`, `CurrentWorldBundle`) instead of hunting blind offsets.

## 2026-03-25 accepted-load field mapping update

- Fresh live replay capture after the focused car spawn surfaced the first clean reflected bundle-identity property set on both `BRBundleTransferComponent` and `BRWorldManager`: `CachedWorldBundle`, `CurrentWorldBundle`, `PendingWorldBundle`, `PrefabArchive`, `PrefabsInProgress`, and `SavedWorldBundle`. `BRWorldManager` also surfaced `WorldSerializer` in the same replay window.
- Static decompile now proves the accepted-load worker `FUN_1447acbe0` is the real consumer of the transfer-component bundle key. The `ClientLoadWorldAccepted` wrapper `FUN_144168b80` just increments the RPC refcount and forwards into `FUN_1447acbe0`.
- `FUN_1447acbe0` checks the transfer-component gate byte at `+0x170`, then calls `FUN_1446e9b70(uVar4, param_1 + 0x158, 3, *(undefined1 *)(param_1 + 0x168))`.
- That means the accepted path is definitively feeding a string field at `BRBundleTransferComponent + 0x158` plus a small flag byte at `+0x168` into the shared bundle lookup/load helper. This is distinct from the previously pinned local upload/save bundle name at `BRBundleTransferComponent + 0x1a8` (`UserUpload.brz`).
- Strongest current inference: the accepted-load field at `+0x158` is one of the newly surfaced world-bundle identity properties, with `PendingWorldBundle` as the lead candidate and `CachedWorldBundle` as the next candidate. This is still an inference, not a proof.
- World-manager metadata also tightened. The `UBRWorldManager` reflected field table anchored at `CachedWorldBundle` (`146da7090`) includes sibling entries for `QueuedWorldSaves`, `QueuedPrefabCaptures`, `RemoteWorldContainer`, and `CachedPrefabBundle`.
- This strengthens the earlier `BRWorldManager.cpp:804` assertion read: `BRWorldManager::CachedWorldBundle` is not just a passive observer field, but a real precondition surface on the world-manager side of the additive load.

## 2026-03-25 prefab cache surface reinterpretation

- The live replay-side `PrefabArchive` / `PrefabsInProgress` names should no longer be treated as automatically belonging directly to `BRWorldManager` or `BRBundleTransferComponent`.
- Static symbol recovery tightened the cache hierarchy:
  - `CachedPrefabBundle` is a reflected `UBRWorldManager` field (`s_CachedPrefabBundle_146da7030`).
  - `PrefabsInProgress` is a reflected `UBRPrefabCache` field (`u_BRPrefabCache_146c54b62`, `s_PrefabsInProgress_146c54b7e`).
  - `PrefabArchive` is a reflected `BRPrefabCacheInMemoryPrefab` field (`u_UBRPrefabCacheInMemoryPrefab_146c54748`, `s_PrefabArchive_146c547c8`).
- This means the earlier live surface is best modeled as a cache/object chain rather than a flat owner field list.
- The current working hierarchy is:
  - `UBRWorldManager.CachedPrefabBundle`
  - some path into `UBRPrefabCache`
  - `UBRPrefabCacheInMemoryPrefab.PrefabArchive`
- `ClientLoadWorldAccepted` remains separate from that cache-side clarification. The accepted-load worker `FUN_1447acbe0` still consumes a transfer-component-owned field block at `+0x158/+0x168/+0x170`, and the teardown side for that block is now pinned to `FUN_144169810`.
- New transfer-component lifecycle read:
  - `FUN_1447a7040` zeroes the gate byte at `+0x170` during init.
  - `FUN_1447acbe0` checks `+0x170` and consumes the bundle-key-like field at `+0x158` plus the flag byte at `+0x168`.
  - `FUN_144169810` tears down the same field block and clears `+0x170` on cleanup.
- Strongest next inference target: determine whether the transfer-component `+0x158` field is copied into bundle-manager pending state or remains a distinct transient accepted-load key.

## 2026-03-25 transfer/download lane separation update

- `FUN_1447acdb0` success does not jump straight into the additive grid load path. It first hands off into `FUN_1447ad980` after `FUN_14472adf0` and `FUN_144691760` (`BRBundle::SerializeToArray`).
- `FUN_1447ad980` builds a `PrefabDownload` request with kind `WORLD`, allocates four continuations, and submits the request through the manager recovered from the transfer-component-owned object chain rooted at `+0x98`.
- The same `PrefabDownload` / `WORLD` request shape also appears in `FUN_1447ab1e0` and in `thunk_FUN_1447a7c20`, so this is a shared transfer/download orchestration lane rather than a one-off accepted-load edge case.
- The small callbacks make the state split explicit:
  - `FUN_1447a8140` writes `+0xe0`, clears `+0xe8`, and sets `+0xf0 = 1`
  - `FUN_1447a8160` clears `+0xf0`
  - `FUN_1447a8180` writes `+0xe8` when `+0xf0` is set
  - `FUN_1447ab710` turns the same `+0xf0` state into the `WorldUploadRejected` timeout/report path
- Current read: the accepted-load / upload flow and the additive prefab flow share lower bundle/cache plumbing, but this transfer-side `PrefabDownload` lane is still not the dedicated-server additive executor. It is a staging/download state machine that sits upstream of the real additive load stages.
- Strong inference: `thunk_FUN_1447a7c20 @ 1447a8130` is either `ServerRequestDownloadWorldThenLoad` itself or a very close wrapper in that same reflected RPC block. I do not want to overstate that as proof until I pin the surrounding registration table cleanly.

## 2026-03-25 next static target after the lane split

- Pin the reflected name/owner of `thunk_FUN_1447a7c20 @ 1447a8130` from the surrounding registration table.
- Identify the concrete manager/container behind the transfer-component `+0x98` chain that owns the `PrefabDownload` request submit (`FUN_14467e600`).
- Keep the additive-side focus on `UBRBundleManager::RequestLoadWorldAdditive -> FUN_1446ea340 -> FUN_14473cae0 -> FUN_14473cf60 -> FUN_1447330c0`, since that remains the only confirmed bridge into the dedicated-server grid/materialization stages.

## 2026-03-25 transfer-component RPC map correction

- The `UBRBundleTransferComponent` reflected RPC/name table is now pinned from the class data blob:
  - `ClientLoadWorldAccepted` -> `144168b80`
  - `ClientLoadWorldRejected` -> `144168c20`
  - `ClientNotifyNotFound` -> `144168d00`
  - `ClientSaveWorldFailed` -> `144168ef0`
  - `ClientUploadPrefab` -> `144169080`
  - `ServerCancelDownloadRequest` -> `1441691e0`
  - `ServerNotifyNotFound` -> `144169240`
  - `ServerRequestDownloadWorldThenLoad` -> `144169340`
  - `ServerSaveAndSendWorld` -> `144169430`
  - `ServerUploadPrefab` -> `144169530`
- This corrects the earlier overreach around `1447a8130`: that thunk is not the reflected `ServerRequestDownloadWorldThenLoad` entry. The actual reflected entry is `144169340`.

## 2026-03-25 request-token bridge into archive deserialize

- `ServerRequestDownloadWorldThenLoad` (`144169340`) forwards into `FUN_1447ac1d0` after marshaling a single reflected argument.
- `FUN_1447ac1d0` is an async gated request setup path:
  - stores the request token/id at `BRBundleTransferComponent + 0x178`
  - sets in-flight gate `+0x17c = 1`
  - registers an async handle at `+0x180`
  - binds `FUN_1447ac420` as the cleanup callback
- `ServerCancelDownloadRequest` (`1441691e0`) goes directly to `FUN_1447ac4e0`, which clears `+0x17c` and unregisters `+0x180`.
- The important bridge is in the `WORLD` branch of `FUN_1447a8ef0`:
  - when the request gate `+0x17c` is set, it consumes the stored token from `+0x178`
  - clears `+0x17c`
  - creates/seeds an archive via `FUN_1446913d0`
  - keeps the archive alive in the `+0x198/+0x1a0/+0x1a4` cluster
  - launches `FUN_144691a10` (`BRBundle::DeserializeFromArray` queue)
- Strong inference: `ClientUploadPrefab` is the reflected entry that feeds the `FUN_1447a8ef0` path, because its wrapper (`144169080`) marshals a payload plus a `bShowProgressBar` boolean, and `FUN_1447a8ef0` is the matching transfer handler that carries a third boolean argument down into `FUN_144691a10(..., param_3)`.
- Strong inference: `ClientNotifyNotFound` is the simple clear-and-stop side represented by the `WORLD`/`+0x17c` early-clear pattern in `FUN_1447aa140`.

## 2026-03-25 current interpretation after the bridge

- The transfer-component download/request lane is now modeled more concretely:
  - reflected server request starts async request state (`ServerRequestDownloadWorldThenLoad`)
  - request token/gate lives in `+0x178/+0x17c/+0x180`
  - `WORLD` upload/result handling can consume that request state and turn it into a real bundle/archive deserialize queue (`FUN_1447a8ef0`)
- This still sits upstream of the dedicated-server additive prefab stages. The confirmed additive executor remains:
  - `UBRBundleManager::RequestLoadWorldAdditive`
  - `FUN_1446ea340`
  - `FUN_14473cae0`
  - `FUN_14473cf60`
  - `FUN_1447330c0`

## 2026-03-25 upload-wrapper correction: ClientUploadPrefab and ServerUploadPrefab converge on FUN_1447a7c20

New static work tightened the transfer/upload side and corrected an earlier overreach.

Confirmed reflected wrappers and vtable slots:
- `ClientUploadPrefab` reflected wrapper is `FUN_144169080`.
  - It decodes a 32-byte payload struct plus a bool (`bShowProgressBar`).
  - It dispatches through `(**(code **)(*param_1 + 0x4d0))(param_1, local_38, local_3c != 0)`.
- `ServerUploadPrefab` reflected wrapper is `FUN_144169530`.
  - It decodes the same 32-byte payload struct.
  - It dispatches through `(**(code **)(*param_1 + 0x4d8))(param_1, local_38)`.

`UBRBundleTransferComponent` constructor `FUN_1447a7040` sets the primary vtable to `146b928e0`, so those slots resolve to:
- `146b928e0 + 0x4d0 = 146b92db0 -> 1447a8130`
- `146b928e0 + 0x4d8 = 146b92db8 -> 1447a7c10`

Decompile results:
- `1447a8130` is `thunk_FUN_1447a7c20 @ 1447a8130`.
- `1447a7c10` is a tiny wrapper:
  - `FUN_1447a7c20(param_1, param_2, 0);`

So the corrected model is:
- `ClientUploadPrefab -> FUN_144169080 -> vtable slot +0x4d0 -> thunk_FUN_1447a7c20 @ 1447a8130`
- `ServerUploadPrefab -> FUN_144169530 -> vtable slot +0x4d8 -> FUN_1447a7c10 -> FUN_1447a7c20(param_3 = 0)`

This upgrades an earlier inference into proof: both upload wrappers converge on the same core implementation, `FUN_1447a7c20`. The client wrapper carries the progress-bar bool; the server wrapper forces that bool off.

Behavior of `FUN_1447a7c20` at current resolution:
- looks up a payload/state object via `FUN_14439ce60(...)`
- resolves a manager/container through the transfer-component-owned `+0x98` chain
- validates the world-side object reached through `+0x538`
- allocates callback objects using:
  - `FUN_1447a8140`
  - `FUN_1447a8160`
  - `FUN_1447a8180`
- submits the request through `FUN_14467e600(...)`
- hard-fails if the source payload length at `lVar6 + 0x100` is not positive

Search result upgrade:
- `FindFunctionsCallingAddressInRange.java 1447a7c20 144000000 145000000` matched only:
  - `FUN_1447a7c10`
  - `thunk_FUN_1447a7c20 @ 1447a8130`

So, within the searched image range, `FUN_1447a7c20` is the canonical shared upload core for the reflected prefab-upload wrappers.

Model correction relative to earlier notes:
- the old `ClientUploadPrefab -> FUN_1447a71e0 -> FUN_1447a7310 -> FUN_1447a8ef0` story is too loose and should no longer be treated as proved.
- the upload-wrapper side is now firmly anchored on `FUN_1447a7c20`.
- relation between `FUN_1447a7c20` and the separate `FUN_1447a71e0 / FUN_1447a7310 / FUN_1447a8ef0` lane is still unresolved.

## 2026-03-25 cache-population bridge: raw prefab bytes feed a hash-keyed prefab cache before shared upload consumption

New static work connected the previously separate-looking upload/cache lanes.

### 1. The reflected upload key is a real 32-byte hash lookup key

`FUN_14439ce60(longlong param_1, uint *param_2)` is a hash-table lookup over eight `uint32` words:
- probes a hash bucket table
- compares all 32 bytes directly against a stored 32-byte key in each record
- on match, returns the object pointer stored at record offset `+0x20`
- uses record offset `+0x28` as the next-chain index

So the 32-byte reflected upload argument is not prefab bytes. It is a real 256-bit cache key.

This matches the nearby reflection evidence around `ClientUploadPrefab`:
- `PrefabHash`
- `bShowProgressBar`

Current read: the reflected `ClientUploadPrefab` struct arg is effectively a `PrefabHash`-style 32-byte key.

### 2. There is a lower native path that hashes raw bytes and populates the keyed cache

`FUN_14439c410(longlong param_1, undefined8 *param_2, longlong *param_3)` is a much more important bridge than it first appeared.

Observed behavior:
- treats `param_2` as raw buffer + size
- copies the incoming bytes into a temporary object
- calls `FUN_1400957e0(local_850, &local_870)` to derive a 32-byte value in `local_870`
- checks for an existing cache entry with `FUN_14439ca00(param_1, &local_870)`
- cache hit path:
  - resolves the object back out through `FUN_14439ce60(param_1, &local_870)`
  - returns that object through the callback in `param_3`
- cache miss path:
  - allocates/creates a new object
  - seeds a bundle/archive with the raw bytes via `FUN_1446913d0(...)`
  - queues `FUN_144691a10(...)` on those bytes
  - stores the object into the cache-owned structures
  - packages callback state that includes the original bytes and the 32-byte hash

Current read:
- `FUN_14439c410` is a real `serialized prefab bytes -> hashed cached prefab object` path.
- the 32-byte key consumed later by reflected upload is derived from raw prefab bytes earlier in this lower native lane.

### 3. The old `FUN_1447a8ef0` lane is now bridged into that cache-population path

Caller scan for `FUN_14439c410` found:
- `FUN_1447a8ef0`
- `FUN_14481a2f0`
- `FUN_14481a570`

The important match is `FUN_1447a8ef0`.

That means:
- `FUN_1447a8ef0` is a direct producer for the hash-keyed prefab-cache objects.
- this corrects the old mental split between the `1447a8ef0` lane and the shared upload-key lane.
- they are related like this instead:
  - `FUN_1447a8ef0` feeds raw serialized bytes into `FUN_14439c410`
  - `FUN_14439c410` hashes/populates/returns cached prefab objects
  - `FUN_1447a7c20` later consumes those cached objects by 32-byte key using `FUN_14439ce60`

### 4. The submit primitives are now cleanly separated

Caller scan for `FUN_14467df20`:
- only `FUN_1447a7310`

Caller scan for `FUN_14467e600`:
- `FUN_1447a7c20`
- `FUN_1447ab1e0`
- `FUN_1447ad980`

So:
- `FUN_14467df20` is the private keyed submit path used by the `FUN_1447a7310` lane.
- `FUN_14467e600` is the shared queue/submit primitive used by the transfer-prefab family that includes `FUN_1447a7c20`.
- the two dispatcher families are genuinely different; they should not be merged into one model.

### 5. Cache-object naming evidence still points at prefab cache ownership

Previously recovered reflected names still line up with the new behavior:
- `UBRPrefabCache`
- `PrefabsInProgress`
- `Cache`
- `UBRPrefabCacheInMemoryPrefab`
- `PrefabArchive`

Current inference from the combined evidence:
- `FUN_14439c410` / `FUN_14439ce60` are very likely operating on the `UBRPrefabCache` / in-memory prefab cache layer.
- This is not yet proved from a class method owner label, but the field names and behavior line up strongly.

### Resulting model correction

Earlier model that is no longer good enough:
- "Call `ClientUploadPrefab`/`ServerUploadPrefab` and maybe they carry prefab bytes."

Current better model:
- raw serialized prefab bytes first enter a lower cache-population path (`FUN_14439c410`)
- that path hashes the bytes and builds/returns a cached prefab object
- reflected upload wrappers (`ClientUploadPrefab` / `ServerUploadPrefab`) operate later on the derived 32-byte `PrefabHash`-style key through shared core `FUN_1447a7c20`

This is important for the headless goal because it says the reflected upload wrappers alone are not sufficient unless the keyed prefab-cache object already exists. A true headless solution likely needs either:
- the lower cache-population path from raw bytes, or
- the additive bundle-manager executor path with the right already-populated state.

## 2026-03-25 class-owner proof in the prefab-cache path

The cache model is now backed by reflected class accessors, not just structural guesses.

### 1. `FUN_1442207c0` is the reflected class accessor for `BRPrefabCacheInMemoryPrefab`

Decompile of `FUN_1442207c0` shows:
- `FUN_140377fa0(L"/Script/Brickadia", L"BRPrefabCacheInMemoryPrefab", &DAT_14786fac0, ...)`

So `FUN_1442207c0()` is the class accessor for `/Script/Brickadia.BRPrefabCacheInMemoryPrefab`.

This lines up with the previously recovered reflected field:
- `PrefabArchive`

### 2. `FUN_144164aa0` is the reflected class accessor for `BRBundleArchive`

Decompile of `FUN_144164aa0` shows:
- `FUN_140377fa0(L"/Script/Brickadia", L"BRBundleArchive", &DAT_147865088, ...)`

So `FUN_144164aa0()` is the class accessor for `/Script/Brickadia.BRBundleArchive`.

### 3. `FUN_14439c410` cache miss path now has concrete class names

With those accessors resolved, the miss path in `FUN_14439c410` becomes much clearer:
- create/obtain a `BRBundleArchive` via `FUN_144164aa0`
- seed that archive with raw bytes and queue `FUN_144691a10`
- create a `BRPrefabCacheInMemoryPrefab` via `FUN_1442207c0`
- store the archive pointer into the new object at `+0xf0`
- append the new cache object into the parent cache-owned array at `param_1 + 0x38`
- package callback state that carries the 32-byte hash

Given the reflected field table recovered earlier (`PrefabArchive` on `BRPrefabCacheInMemoryPrefab`), the `+0xf0` store is now very likely the archive attachment for that cache object.

### 4. `FUN_14439bbf0` is a sibling helper that wraps an existing archive into `BRPrefabCacheInMemoryPrefab`

`FUN_14439bbf0` also calls `FUN_1442207c0`, and its behavior is now clearer:
- takes an existing archive object in `param_2`
- creates a `BRPrefabCacheInMemoryPrefab`
- stores `param_2` into the new object at `+0xf0`
- appends that object into the parent cache-owned array at `param_1 + 0x38`
- serializes the archive with `FUN_144691760(param_2, &local_e8)`
- packages callback state that includes the archive and copied key material from `param_3`

Caller scan for `FUN_1442207c0` found only:
- `FUN_14439bbf0`
- `FUN_14439c410`

So the `BRPrefabCacheInMemoryPrefab` construction logic is tightly localized around this cache layer.

Caller scan for `FUN_14439bbf0` found:
- `FUN_1448b2180`
- `FUN_1448b3ff0`

Current read:
- `FUN_14439bbf0` is the sibling "already have archive, wrap it into cache object" helper.
- `FUN_14439c410` is the "have raw bytes, create archive, then wrap into cache object" helper.

### 5. What this means for the headless goal

This is the strongest cache-side model so far:
- raw serialized prefab bytes can be turned into `BRBundleArchive`
- that archive can be wrapped into `BRPrefabCacheInMemoryPrefab`
- the resulting cache object is tracked by the parent prefab-cache layer
- later reflected upload wrappers consume that cache via the derived 32-byte key

So the headless path is looking less like "call upload RPCs with bytes" and more like:
- populate the prefab cache from raw serialized data
- then either consume by hash through the shared upload core
- or bridge from the cache object directly into the additive load path

## 2026-03-25 local `.brz` import path: raw bytes -> prefab cache -> hash handoff

A strong headless-relevant static path surfaced outside the transfer/RPC lane.

### 1. `FUN_14481a2f0` is a non-transfer caller of the raw-bytes bridge

Decompile of `FUN_14481a2f0` shows:
- constructs/requests something `.brz`-shaped via:
  - `FUN_14002eaf0(..., L".brz")`
  - `FUN_14467f940(..., auStack_78)`
- on success, builds a callback object whose target is `FUN_14481a700`
- then directly calls:
  - `FUN_14439c410(uVar5, auStack_78, &uStack_88)`

Current read:
- `FUN_14481a2f0` is a local `.brz` import flow that feeds raw prefab bytes into the same `FUN_14439c410` cache-population bridge already identified.
- This is much closer to a headless local-prefab path than the reflected upload RPC lane.

### 2. `FUN_14481a700` bridges the finished cache object into a hash-based handoff

`FUN_14481a700(param_1, param_2, param_3, param_4)` receives the result of the local import/cache build.

Observed behavior:
- `lVar2 = *param_2` is the completed prefab-cache object
- checks policy/permission gates with `FUN_1447ea3d0(...)`
- validates the prefab against server/client rules with:
  - `FUN_14439afb0(lVar2, lVar6, auStack_68)`
- on success, forwards the hash field at the prefab-cache object to:
  - `FUN_144264d70(param_1, lVar2 + 0x28, param_3, param_4, lVar2 + 0xd8)`

That is important because the earlier cache work already showed:
- `FUN_14439c090` / `FUN_14439d4f0` compute/store the prefab hash on the cache object
- `FUN_14439e310` dedupes/inserts by that same hash region

So `lVar2 + 0x28` is now a strongly evidenced prefab-hash handoff field on the completed `BRPrefabCacheInMemoryPrefab` object.

### 3. `FUN_144264d70` is a narrow wrapper around a virtual handoff using the prefab hash

Decompile of `FUN_144264d70` shows:
- copies 32 bytes from `param_2` into a local struct (`local_58/uStack_50/uStack_48/uStack_40`)
- includes the two boolean/byte flags (`param_3`, `param_4`)
- includes callback/context from `param_5`
- then dispatches through:
  - `(**(code **)(*param_1 + 0x280))(param_1, uVar1, &local_58)`

Caller scan for `FUN_144264d70` in `144000000-145000000` found only:
- `FUN_14481a700`

So, within the searched range, this handoff is currently unique to the local `.brz` import completion path.

### 4. Why this matters for the headless goal

This gives a new, cleaner model than the earlier upload-RPC-first approach:
- local `.brz` bytes can enter through `FUN_14481a2f0`
- raw bytes are converted into `BRBundleArchive` + `BRPrefabCacheInMemoryPrefab` via `FUN_14439c410`
- the finished cache object is validated in `FUN_14481a700`
- the hash at `cacheObject + 0x28` is then handed into `FUN_144264d70`

So there is now a concrete local path that looks like:
- `.brz` bytes -> prefab cache object -> prefab hash handoff

This does not yet prove direct additive-load execution, but it does identify a much more headless-friendly bridge than the network/transfer component path.

Current working interpretation:
- if we can reproduce the `FUN_14439c410` + `FUN_14481a700` style local-import path headlessly, we may be able to build the exact cache state and hash handoff that the higher upload/use path expects, without relying on the manual in-game capture/upload UI.

## 2026-03-25 owner-surface note: local `.brz` import appears tool-driven, but the reusable lower bridge is still `FUN_14439c410`

Further tracing clarified where the local `.brz` import entry lives.

### 1. `FUN_144264d70` remains a narrow unique handoff

Caller scan for `FUN_144264d70` in `144000000-145000000` found only:
- `FUN_14481a700`

So the hash handoff discovered in the previous checkpoint is not a broad shared helper in the searched range. It is still uniquely reached from the local import completion path.

### 2. `FUN_14480c7c0` conditionally triggers the `.brz` import entry

Decompile of `FUN_14480c7c0` shows:
- it is a larger state/update method on some owner object with many fields and virtual calls
- near the end it checks a local flag region around:
  - `param_1 + 0x163`
  - `param_1 + 0xb19`
  - `param_1 + 0xb1a`
- when that flag is set, it calls:
  - `FUN_14481a2f0(param_1, *(byte *)(param_1 + 0xb1a))`

That strongly suggests the local `.brz` import path is initiated from a tool/controller state machine, not from a bare free-standing utility.

### 3. Interpretation for headless work

This is an important nuance:
- the top-level local `.brz` import entry (`FUN_14481a2f0`) appears client/tool-driven
- but the lower raw-bytes bridge (`FUN_14439c410`) remains the reusable core

So the current best headless-relevant split is:
- tool/UI wrapper layer:
  - `FUN_14480c7c0`
  - `FUN_14481a2f0`
  - `FUN_14481a700`
- lower reusable cache/build layer:
  - `FUN_14439c410`
  - `FUN_14439ca00`
  - `FUN_14439ce60`
  - `FUN_14439d4f0`
  - `FUN_14439e310`

Current read:
- the top-level local import surface itself is probably not the direct dedicated-server entry we want
- but it gives a concrete reference implementation for the exact lower cache-building steps we may be able to reproduce headlessly without the tool/UI layer

## 2026-03-25 static checkpoint: local cache import converges on ServerPastePrefab

New correction and bridge:

- The local prefab-cache/import path does not end in a vague controller utility. It converges on `ABRPlayerController::ServerPastePrefab`.
- `FUN_144264d70` is the reflected wrapper for `ServerPastePrefab`.
  - It resolves a `UFunction` token through `FUN_1404dfb20(param_1, DAT_147873330)`.
  - It then dispatches through the controller's reflected event slot at `vtable + 0x280`, i.e. the generic `ProcessEvent`-style lane.
- `FUN_144267610` is the `ABRPlayerController` registration block that seeds `DAT_147873330` with the name `ServerPastePrefab`.
- The native registrar table at `146caf5d0` pairs `ServerPastePrefab` with `FUN_144264e80`, so `FUN_144264e80` is the native exec thunk for that RPC.

`ServerPastePrefab` parameter surface is now much clearer:

- Nearby reflected strings show the RPC parameter names:
  - `bWithOwnership`
  - `bInTemp`
  - `PasteInfo`
- `FUN_144264e80` decodes:
  - a 32-byte prefab hash
  - `bWithOwnership`
  - `bInTemp`
  - a trailing `PasteInfo` payload/struct
- Raw instruction dump shows the exec thunk finishes by calling the controller implementation through `vtable + 0xf50`, so the native path is:
  - reflected RPC wrapper
  - native exec thunk
  - controller virtual implementation

This gives the cleanest client/tool-side chain so far:

- local `.brz` / local provider input
- `-> FUN_14439c410` (raw bytes to archive-backed prefab cache object)
- `-> FUN_14439d4f0 / FUN_14439e310` (finalize and dedupe by 32-byte hash)
- `-> FUN_14481a700` (validate finished cache object)
- `-> FUN_144264d70` (`ABRPlayerController::ServerPastePrefab`)

Strong current inference:

- `PasteInfo` is likely the `BRPrefabDetachedPasteInfo` struct surfaced elsewhere in the binary.
- This means the local/client path is not just 'upload bytes'; it is 'materialize cache entry, then invoke the actual prefab paste RPC by prefab hash plus paste options/info'.
- That makes `ServerPastePrefab` a much more plausible bridge between the cache-builder lane and the dedicated-server prefab materialization path than the earlier transfer-component upload story.

### 2026-03-25 follow-up: `BRPrefabDetachedPasteInfo` field surface

The nearby reflected metadata for `BRPrefabDetachedPasteInfo` now exposes at least two concrete field names:

- `GridOffset`
- `PlacementOrientation`

It also surfaces `DetachedPasteInfo` as a named member on the nearby `BRPrefabHashAndMetadata`-related metadata slab.

Current read:

- `ServerPastePrefab(Hash, bWithOwnership, bInTemp, PasteInfo)` is very likely carrying a detached-paste placement struct rather than an opaque callback token.
- `PasteInfo` is therefore much more plausibly `BRPrefabDetachedPasteInfo`, with at least:
  - grid offset / placement target information
  - placement orientation information

That makes the emerging headless call shape materially clearer:

- prefab hash
- ownership/temp flags
- detached-paste placement info

This is a better match for the observed client-side paste/import surface than the earlier transfer-component upload theory.

## 2026-03-25 additive params correction: `BRLoadWorldAdditiveParams` layout is now much tighter

The additive-side params block is no longer just inferred from a reflected string slab. The lower loader now exposes enough concrete field copies to map most of the struct.

### 1. `FUN_14473cf60` copies the additive params in a stable order

`FUN_14473cf60` copies the incoming params block (`param_4`) into a local request record like this:

- `+0x00` -> `local_630 = *param_4`
- `+0x08` -> `local_628 = param_4[1]`
- `+0x10` -> `local_620 = *(uint32 *)(param_4 + 2)`
- `+0x14` -> `local_61c = *(byte *)((longlong)param_4 + 0x14)`
- `+0x18` -> `local_638 = param_4[3]`
- `+0x20` -> `local_63c = *(uint32 *)(param_4 + 4)`
- `+0x24` -> `local_61b = *(byte *)((longlong)param_4 + 0x24)`
- `+0x25` -> `local_61a = *(byte *)((longlong)param_4 + 0x25)`
- `+0x26` -> `local_619 = *(byte *)((longlong)param_4 + 0x26)`

That gives the real additive params layout shape:

- `+0x00` = target pointer A
- `+0x08..+0x13` = 12-byte placement offset block
- `+0x14` = 1-byte orientation
- `+0x18` = target pointer B
- `+0x20` = 32-bit scalar field
- `+0x24`, `+0x25`, `+0x26` = three trailing flag bytes

### 2. The mutual-exclusion validation in `FUN_14473cae0` matches the two target pointers

`FUN_14473cae0` still begins with:

- `if ((param_3[3] == 0) == (*param_3 == 0)) ...`

That is the native form of the earlier reflected validation string:

- `(Params.GlobalGridTarget && !Params.PreviewPart) || (!Params.GlobalGridTarget && Params.PreviewPart)`

So the two mutually-exclusive target-like fields are now pinned to:

- `+0x00`
- `+0x18`

### 3. `FUN_1447176c0` uses the `+0x00` target lane

The local additive helper:

- builds `Worlds/<name>.brdb`
- parses 3-4 integer tokens
- resolves a registry-owned object through `FUN_144385e10(param_2)` and `+0xf8`
- passes that object at params offset `+0x00`
- leaves the `+0x18` target slot zero

That means `FUN_1447176c0` is exercising the first target lane, not the preview-side lane.

### 4. `FUN_144867650` uses the `+0x18` target lane

The new decompile of `FUN_144867650` is the crucial discriminator.

In its additive branch it builds params like:

- `+0x00 = 0`
- `+0x08..+0x14 = default offset/orientation`
- `+0x18 = param_1`
- `+0x20 = -1`
- `+0x24..+0x26 = 0, 1, 1`

then calls:

- `FUN_14473cae0(uVar6, param_1[0x36], &local_c8, local_88)`

So `FUN_144867650` is a concrete native caller that proves the second target slot at `+0x18` is the preview-side target.

Current mapping:

- `+0x00 = GlobalGridTarget`
- `+0x18 = PreviewPart`

### 5. Strong new inference: `BrickGrid` sits at `+0x20`

The earlier default tail looked strange when treated as only three bools:

- `0xffffffff`
- `0x100`
- `1`

But the lower copy pattern plus the validation string `Params.BrickGrid is invalid.` now make a cleaner model:

- `+0x20 = BrickGrid`
- `+0x24 = bEnforceBuildZonesForGlobalGrid`
- `+0x25 = bEnforceComponentQuotas`
- `+0x26 = bAllowAdminGates`

That makes the default additive tail decode sanely as:

- `BrickGrid = -1`
- `bEnforceBuildZonesForGlobalGrid = 0`
- `bEnforceComponentQuotas = 1`
- `bAllowAdminGates = 1`

This fits both the reflected string evidence and the concrete byte copies much better than the older ‚Äúthree impossible bool values‚Äù interpretation.

### 6. Current additive params model

Best current field map for `BRLoadWorldAdditiveParams`:

- `+0x00 = GlobalGridTarget`
- `+0x08..+0x13 = Offset`
- `+0x14 = Orientation`
- `+0x18 = PreviewPart`
- `+0x20 = BrickGrid` (strong inference)
- `+0x24 = bEnforceBuildZonesForGlobalGrid`
- `+0x25 = bEnforceComponentQuotas`
- `+0x26 = bAllowAdminGates`

### 7. Implication for headless work

This is a real improvement over the earlier additive model:

- we now know the native lower loader accepts two different placement/target modes
- the local `.brdb` additive helper uses the `GlobalGridTarget` lane
- the preview-side native caller uses the `PreviewPart` lane
- the params tail now has a plausible `BrickGrid` slot instead of an opaque packed blob

Current read:

- if headless autoload is going to come from the additive path, the best near-term target is still the local `.brdb` / `GlobalGridTarget` lane, not the preview-side lane
- but we are no longer guessing at the placement struct shape while we do it

## 2026-03-25 external archive unlock: real `.brz` samples match the native `World/0/...` loader paths

New external evidence landed from `brz.md` plus real archive samples on disk.

### 1. `brz.md` confirms the outer archive format

The creator note in [brz.md](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brz.md) documents the outer container as:

- magic `BRZ`
- format version byte
- compression method byte
- decompressed/compressed index lengths
- 32-byte BLAKE3 hash of the decompressed index
- compressed index payload
- numbered blobs, each with its own compression method, lengths, and BLAKE3 hash

That means `.brz` is a straightforward named-file archive format, not an opaque monolith.

### 2. A new local inspector script now parses `.brz`

Added:

- [inspect-brz.js](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\inspect-brz.js)

Current capabilities:

- parse the BRZ header
- zstd-decompress the index
- reconstruct folder and file paths from the index tables
- list all files, blob ids, compression methods, and sizes
- optionally extract the archive contents to a directory

This is now a concrete external analysis tool for prefab archives independent of the UE4SS runtime wrapper layer.

### 3. Real `.brz` files exist locally

Relevant sample locations found on disk:

- `C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz`
- `C:\Users\tycox\AppData\Local\Brickadia\Saved\GalleryCache\Prefabs\*.brz`

So prefab archives are not hypothetical or only network-side. They are materialized locally in the client cache/temp surface.

### 4. `Clipboard.brz` already matches the static loader path

Running the new inspector on:

- `C:\Users\tycox\AppData\Local\Brickadia\Saved\Temp\Clipboard.brz`

produced:

- `Meta/Prefab.json`
- `World/0/Owners.mps`
- `World/0/GlobalData.mps`
- `World/0/Entities/ChunkIndex.mps`
- `World/0/Bricks/Grids/1/ChunkIndex.mps`
- `World/0/Bricks/Grids/1/Chunks/-1_0_0.mps`

That is the exact same shape as the native loader strings already recovered statically:

- `World/0/Bricks/Grids/%d/ChunkIndex.mps`
- `World/0/Bricks/Grids/%d/Chunks/%s.mps`

So the `.brz` archive contents now externally confirm the additive/grid serializer file layout, not just the high-level bundle idea.

### 5. A larger cached prefab sample exposes the full payload surface

Running the inspector on:

- `C:\Users\tycox\AppData\Local\Brickadia\Saved\GalleryCache\Prefabs\86e67da3-58dd-4af6-8193-f17076cf8227.brz`

produced:

- `Meta/Prefab.json`
- `Meta/Bundle.json`
- `Meta/Thumbnail.png`
- `World/0/Owners.mps`
- `World/0/GlobalData.mps`
- `World/0/Entities/ChunkIndex.mps`
- `World/0/Entities/Chunks/0_0_0.mps`
- `World/0/Bricks/Grids/1/ChunkIndex.mps`
- `World/0/Bricks/Grids/1/Chunks/-1_-1_-1.mps`
- `World/0/Bricks/Grids/1/Components/-1_-1_-1.mps`
- `World/0/Bricks/Grids/1/Wires/-1_-1_-1.mps`

That is a direct external match for the static chunk pipeline:

- entity chunk index
- entity chunks
- brick chunk index
- brick chunks
- component chunks
- wire chunks

This is the cleanest evidence so far that the archive-on-disk structure and the dedicated-server additive load path are describing the same payload model.

### 6. Metadata example from the cached prefab sample

Extracting the sample archive showed:

- `Meta/Bundle.json`
  - `type = "Prefab"`
  - `iD = "86e67da3-58dd-4af6-8193-f17076cf8227"`
  - `name = "HL2 Jeep"`
- `Meta/Prefab.json`
  - `brickCount = 566`
  - `componentCount = 13`
  - `entityCount = 4`
  - `wireCount = 8`
  - `addedGlobalGridOffset = { x: -1, y: -1, z: 5 }`
  - pivot/bounds metadata
  - `worldRootTransform`

That matters because we now have a real external source for:

- prefab identity
- placement metadata
- counts
- world/grid offset metadata

without needing those values to survive UE4SS property decoding first.

### 7. Headless implication

This changes the situation materially.

Before:

- we had strong static/native evidence for additive load and cache seeding
- but the reusable payload on disk was still abstract

Now:

- we have a documented outer prefab archive format
- a working extractor
- real local `.brz` samples
- and those samples contain the exact `World/0/...` paths named by the native additive loader

Current read:

- the shortest headless path may now involve external archive exploitation, not just more runtime wrapper decoding
- two concrete directions are now available:
  - drive the native `.brz` bytes-to-cache lane with a known local archive
  - or compare `.brz` contents against `.brdb` world loading to see whether the additive `Worlds/<name>.brdb` helper can be fed an equivalent extracted/converted bundle surface

## 2026-03-25 container bridge note: `.brdb` and `.brz` share the same logical file namespace

The first `.brdb` comparison now says the archive surfaces are not just similar in spirit. They expose the same logical payload namespace.

### 1. `Tutorial.brdb` is a folder/file/blob container

Using the existing `better-sqlite3` dependency from Omegga against:

- `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Content\Worlds\Tutorial.brdb`

shows the schema:

- `folders(folder_id, parent_id, name, created_at, deleted_at)`
- `files(file_id, parent_id, name, content_id, created_at, deleted_at)`

So `.brdb` is not a bespoke world-only blob. It is also a named file container backed by relational tables plus blob storage.

### 2. Reconstructed `Tutorial.brdb` paths match the `.brz` namespace

A recursive folder-path query over `Tutorial.brdb` produced entries like:

- `Meta/Bundle.json`
- `Meta/World.json`
- `Meta/Screenshot.jpg`
- `World/0/Bricks/ChunkIndexShared.schema`
- `World/0/Bricks/ChunksShared.schema`
- `World/0/Bricks/ComponentsShared.schema`
- `World/0/Bricks/Grids/1/ChunkIndex.mps`
- `World/0/Bricks/Grids/1/Chunks/<coord>.mps`
- `World/0/Bricks/Grids/1/Components/<coord>.mps`
- `World/0/Bricks/Grids/1/Wires/<coord>.mps`

That is the same path family already observed in:

- `Clipboard.brz`
- cached gallery prefab `.brz` samples
- the native additive loader string references

### 3. Why this matters

This is the strongest archive/container bridge found so far:

- `.brz` = documented outer archive with named files and blob tables
- `.brdb` = SQLite-backed named file container with blob ids
- both expose `Meta/...` and `World/0/...` payload trees
- both match the native entity/grid/chunk/component/wire file naming conventions

Current read:

- the native additive loader and the native prefab bundle/cache lane are no longer pointing at two obviously different payload universes
- they look like two containerizations of the same logical bundle surface

### 4. Practical implication for headless work

This makes the next technical directions much sharper:

- compare a parsed `.brz` prefab against a `.brdb` world at the file/path and metadata level
- test whether a prefab archive can be transformed into the `.brdb`-style container surface expected by the local additive helper
- keep the native `.brz` bytes-to-cache lane in parallel, since the archive structure is now externally understood enough to feed and inspect deliberately

## 2026-03-25: payload decoder and prefab->world bridge unlock

### Payload decoder is now materially useful

The new local decoder/test path crossed the important line from "opaque archive surface" to "real prefab payload recovery":

- Added [inspect-brz.js](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\inspect-brz.js) earlier in the session for BRZ outer-container parsing/extraction.
- Added [test-prefab-payload-decode.js](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\test-prefab-payload-decode.js).
- `test-prefab-payload-decode.js` now passes against real local archives:
  - `Clipboard.brz`
  - `86e67da3-58dd-4af6-8193-f17076cf8227.brz`

Passing payload assertions now prove:

- `Clipboard.brz` decodes into a 4-brick payload with owner/global/chunk-index data.
- The gallery prefab decodes into:
  - `566` bricks
  - `13` components
  - `4` entities
  - `8` wires
- Those decoded counts match `Meta/Prefab.json` exactly.

Important decoded payload surfaces recovered from real `.mps` files:

- `BRSavedBrickChunkSoA`
  - `BrickTypeIndices`
  - `OwnerIndices`
  - `RelativePositions`
  - `Orientations`
  - `MaterialIndices`
  - `ColorsAndAlphas`
- `BRSavedComponentChunkSoA`
  - `ComponentTypeCounters`
  - `ComponentBrickIndices`
  - `JointBrickIndices`
  - `JointEntityReferences`
  - joint relative offsets/rotations
- `BRSavedEntityChunkSoA`
  - `TypeCounters`
  - `PersistentIndices`
  - `OwnerIndices`
  - `Locations`
  - `Rotations`
- `BRSavedWireChunkSoA`
  - `LocalWireSources`
  - `LocalWireTargets`
  - `PendingPropagationFlags`

There is still a small trailing schema-decoder miss (`Expected array length, got fixpos`) at the tail of several chunk decodes, but it is no longer blocking payload recovery. We already have the core brick/component/entity/wire state in a reusable form.

### Prefab -> world container bridge is now implemented and tested

I compared a real tutorial world `.brdb` against a converted gallery prefab `.brdb` and the metadata gap is very small:

- tutorial world meta files:
  - `Meta/Bundle.json`
  - `Meta/World.json`
  - `Meta/Screenshot.jpg`
- prefab meta files:
  - `Meta/Bundle.json`
  - `Meta/Prefab.json`
  - `Meta/Thumbnail.png`

Key result:

- the `World/0/...` payload namespace already matches
- the obvious world-side metadata additions are:
  - `Meta/Bundle.json` with `type = "World"`
  - `Meta/World.json` (tutorial sample only needed `{ "environment": "Plate" }`)

New bridge artifacts:

- Added [build-prefab-world-brdb.js](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\build-prefab-world-brdb.js)
  - converts a prefab `.brz` into a world-shaped `.brdb`
  - rewrites `Meta/Bundle.json` as a world bundle
  - injects `Meta/World.json`
  - preserves `Meta/Prefab.json` and the original `World/0/...` payload files
- Added [test-prefab-world-bridge.js](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\test-prefab-world-bridge.js)
  - currently passes on the HL2 Jeep prefab sample
  - verifies the output contains:
    - `Meta/Bundle.json`
    - `Meta/World.json`
    - `Meta/Prefab.json`
    - real `World/0/Bricks/...` payload files
    - real `World/0/Entities/...` payload files
  - verifies the bridged bundle reports:
    - `bundleType = World`
    - `environment = Plate`
    - `brickCount = 566`

### Current interpretation

This materially improves the headless picture in two ways:

1. We now have actual reusable prefab payload recovery from local `.brz` archives instead of only live UE4SS placeholder surfaces.
2. We now have a concrete additive-load candidate artifact generator (`prefab .brz -> world-shaped .brdb`) for testing against the `UBRBundleManager::RequestLoadWorldAdditive` lane.

This does **not** prove the server will accept the bridged `.brdb` as-is, but it is the first concrete local artifact that looks shaped for that additive path instead of only for controller-side paste-by-hash.

## 2026-03-25: live OmeggaBridge command channel + additive console-exec crash

### OmeggaBridge runtime path issue is now understood

The bridge mod was loading in fresh dedicated-server runs, but it initially looked dead because no fresh `outbox/status` files appeared in the sampler data directory.

What is actually happening:

- `UE4SS.log` confirms `OmeggaBridge` loads and starts its inbox poller on fresh runs.
- The default bridge runtime path is relative (`Mods/OmeggaBridge/runtime`).
- In practice, that resolved under `.../Brickadia/Binaries/Win64/Mods/OmeggaBridge/runtime`, not the `ue4ss/main/Mods/...` tree and not the sampler data dir.
- If that runtime directory does not already exist, the bridge has nowhere to write `outbox.ndjson` / `bridge.log`.

Once I pre-created a dedicated bridge runtime dir and launched the server with `OMEGGA_UE4SS_BRIDGE_DIR=<that dir>`, the bridge channel came up immediately and worked.

Verified live RPCs on isolated test server:

- `bridge.ping` round-trips successfully
- `console.exec "Server.Status"` succeeds and returns chunked output

That means we now have a real live runtime command channel for controlled server-side experiments, without needing the samplerís missing `call_function_available` path.

### `RequestLoadWorldAdditive` is not just a dead string

On an isolated dedicated server (`Plate`, port `7792`) with the live bridge channel active, I sent:

- `console.exec "RequestLoadWorldAdditive PrefabBridge_HL2Jeep"`

Where:

- `PrefabBridge_HL2Jeep.brdb` was the bridged prefab world candidate already staged under `.../Brickadia/Content/Worlds/PrefabBridge_HL2Jeep.brdb`

Observed result:

- the bridge accepted and scheduled the command through `ProcessConsoleExec`
- the server then crashed with:
  - `EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000010`
- callstack in `Brickadia.log` shows the failure running through:
  - `UE4SS.dll!RC::Unreal::UObject::ProcessConsoleExec()`
  - delayed Lua action / engine tick callback path

Important interpretation:

- this command is **not** being cleanly rejected as an unknown console string
- it is reaching a real engine-side console-exec path strongly enough to crash the dedicated server when invoked in this form
- that is the strongest live evidence so far that `RequestLoadWorldAdditive` is executable through a console/exec-style surface, but our target object/argument shape is still wrong for safe use

This does **not** prove the command is the final headless solution, but it moves it well above pure string/symbol speculation.

### Net effect on the autoload picture

We now have three real pieces together:

1. decoded reusable prefab payload from `.brz`
2. a generated world-shaped `.brdb` additive candidate artifact
3. a verified live command channel that can drive console-exec experiments, plus a first `RequestLoadWorldAdditive` crash proving the name crosses into real execution instead of being ignored

The next RE task is no longer ìfind any way to touch the additive path.î
It is now:

- identify the correct `ProcessConsoleExec` target/context for `RequestLoadWorldAdditive`
- identify the minimum safe argument shape so the command does not dereference null and crash the server

## 2026-03-25: live `BRBundleManager` reflected-invocation boundary on isolated bridge server

I built a small isolated bridge harness for repeated live invocation experiments:

- [start-bridge-test-server.ps1](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\start-bridge-test-server.ps1)
- [send-bridge-rpc.js](C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\send-bridge-rpc.js)

The harness now reliably starts a fresh dedicated server on `127.0.0.1:7799` with:

- `OmeggaBridge` enabled
- conflicting sampler/proof mods disabled
- isolated runtime dir `...\ue4ss-bridge-test-7799`
- unsafe probes and `CallFunctionByNameWithArguments` trace hook enabled

### Live results

On the fresh isolated server, I added an emulated bridge command:

- `Omegga.Bridge.BundleManagerCallByName <command>`

That command finds the live `BRBundleManager` instance and then tries both:

1. `OmeggaCallFunctionByNameWithArguments(object, command, executor)` across several executors
2. raw member lookup + `object:CallFunction(member, ...)`

Observed results:

- `BRBundleManager` is definitely live on the dedicated server.
- `DescribeObjectName BRBundleManager` reports `hits=1`.
- `BundleManagerCallByName GetPendingWorldBundle`:
  - `CallFunctionByNameWithArguments` returned `false` for every executor attempted.
  - raw member lookup succeeded and surfaced a real userdata member object for `GetPendingWorldBundle`.
  - raw `CallFunction` then failed with:
    - `[UFunction::call_ufunction_from_lua] Tried calling function without both UFunction and calling context`
- `BundleManagerCallByName RequestLoadWorldAdditive PrefabBridge_HL2Jeep`:
  - same result shape as above.
  - `CallFunctionByNameWithArguments` returned `false` for every executor attempted.
  - raw member lookup also surfaced a real userdata member object for `RequestLoadWorldAdditive`.
  - raw `CallFunction` failed with the same missing `UFunction` / calling-context error.

### Interpretation

This is a useful narrowing step.

What it now strongly suggests is:

- `RequestLoadWorldAdditive` is reachable as a reflected member on the live `BRBundleManager` object.
- generic console-exec / `ProcessConsoleExec` is not the right invocation primitive for it.
- generic `CallFunctionByNameWithArguments` is also not sufficient here, at least from the bridge contexts tried so far.
- naive raw `object[FunctionName]` lookup is not enough to produce a valid `UFunction` + calling-context pair for `CallFunction`.

So the live problem is no longer ìfind the ownerî or ìprove the member exists.î
It is now:

- obtain the correct `UFunction` object / invocation context pairing for `BRBundleManager` methods, or
- bypass the reflected invocation surface and drive the lower native additive path directly.

### Follow-up: reflected member wrappers exist, but `BRBundleManager` function walk is empty in the live bridge context

I pushed the live bridge experiments farther after the first `BundleManagerCallByName` result.

Additional observations from the isolated `7799` bridge server:

- raw member lookup on the live `BRBundleManager` object resolves both:
  - `GetPendingWorldBundle`
  - `RequestLoadWorldAdditive`
- those members come back as userdata objects, not plain Lua functions
- attempting `object:CallFunction(member, ...)` on those raw member objects fails with:
  - `[UFunction::call_ufunction_from_lua] Tried calling function without both UFunction and calling context`

I then ported the sampler-style `class:ForEachFunction(...)` resolver into the bridge and added:

- `Omegga.Bridge.DescribeBundleManagerFunctions <limit>`

Live result:

- `DescribeBundleManagerFunctions 20` returned:
  - `hits=1` for the live `BRBundleManager` object
  - `enumerated=0` for the class function walk

Interpretation:

- the live bridge can see bundle-manager member wrappers by name
- but in this context it is **not** getting a usable reflected function list from `BRBundleManager:GetClass():ForEachFunction(...)`
- so the bridge currently has no clean way to turn those wrappers into a verified `UFunction` object for `CallFunction`

That is a stronger boundary than before.
The problem is no longer ìmaybe the member name is wrong.î
It is now much closer to:

- `BRBundleManager` member wrappers are visible, but the live bridge reflection surface is insufficient to invoke them safely
- the next likely solution is a lower native invocation route, or a different owning/context object that exposes the additive path through a callable reflected surface

## 2026-03-25 additive caller split is now concrete

The bridge reflection surface looks effectively closed for `UBRBundleManager` work:

- direct live member wrappers on `BRBundleManager` still surface as invalid placeholder `UObject` wrappers
- `CallFunctionByNameWithArguments` still returns `false`
- direct `object:CallFunction(member, ...)` still fails with missing `UFunction` / calling-context pairing
- `RegisterHook` also fails for:
  - `/Script/Brickadia.BRBundleManager:RequestLoadWorldAdditive`
  - `/Script/Brickadia.BRBundleManager:GetPendingWorldBundle`
- current read: in this UE4SS live context, those bundle-manager UFunctions are not materially discoverable/callable by reflection even though member wrappers exist by name

The lower native side is much better now.

Caller scan for `FUN_14473cae0` across `144000000-146000000` found three callers:

- `FUN_1446ea4c0`
- `FUN_1443f6f00`
- `FUN_144867650`

That is important because it splits the additive executor into three concrete families instead of one blurry lane.

### `FUN_144867650` is the preview-side caller

`FUN_144867650` builds the additive params in the `PreviewPart` shape and then calls `FUN_14473cae0` directly.

Observed native param layout in that caller:

- `+0x00 = 0`
- `+0x08 = DAT_1476bed58`
- `+0x10 = DAT_1476bed60`
- `+0x14 = 0x10`
- `+0x18 = param_1`
- `+0x20 = 0xffffffff`
- `+0x24 = 0`
- `+0x25 = 1`
- `+0x26 = 1`

Then it calls:

- `FUN_14473cae0(uVar5, *(param_1 + 0x1b0), &local_c8, local_88)`

So this is now strong proof that the preview-side native lane uses:

- `GlobalGridTarget = 0`
- `PreviewPart = param_1`

which matches the earlier inference but is now backed by the actual caller.

### `FUN_1443f6f00` is the global-grid caller

`FUN_1443f6f00` is a much heavier permission/validation/apply lane, but the additive call inside it is exactly what we needed.

Right before `FUN_14473cae0`, it builds the params like this:

- `+0x00 = local_1e8`
- `+0x08 = *(param_1 + 0x20)`
- `+0x10 = *(param_1 + 0x28)`
- `+0x14 = *(param_1 + 0x2c)`
- `+0x18 = 0`
- `+0x20 = uVar8`
- `+0x24 = param_6[7] ^ 1`
- `+0x25 = param_6[1] ^ 1`
- `+0x26 = param_6[0xb]`

Then it calls:

- `FUN_14473cae0(uVar10, *( *(param_1 + 0x18) + 0xf0), local_168, local_1c8)`

That is the cleanest proof so far that the non-preview lane is the `GlobalGridTarget` lane.

Current best read on the params block:

- `+0x00..+0x14` is the full `GlobalGridTarget` object/handle payload, not just a bare pointer
- `+0x18..+0x20` is the mutually-exclusive `PreviewPart` / related payload slot
- `+0x24..+0x26` are the three additive gating booleans

This means the earlier layout guess was directionally right but too simple. The mutually-exclusive fields are object payload blocks, not plain naked pointers.

### Why this matters for headless work

The real additive executor now has three concrete caller families:

1. bundle-manager async request lane:
   - `FUN_144167890`
   - `FUN_1446ea340`
   - `FUN_1446ea4c0`
   - `FUN_14473cae0`

2. preview-side native lane:
   - `FUN_144867650`
   - `FUN_14473cae0`

3. global-grid native paste/apply lane:
   - `FUN_1443f6f00`
   - `FUN_14473cae0`

For headless prefab autoload, the most promising direction is still the non-preview `GlobalGridTarget` lane, because `FUN_1443f6f00` now proves a native caller exists that reaches the additive executor without using the preview-part shape.

## 2026-03-25 late checkpoint: `BrickAction_PlacePrefab` descriptor tables and generic dispatch

New helper:
- Added `GhidraDumpQwords.java` to dump qword tables directly from Ghidra headless.

What is now proved:
- `146c6c500` is a real descriptor/constructor table for the `BrickAction_PlacePrefab` family.
- The first entries are:
  - `146c6c500 -> 144231fb0`
  - `146c6c508 -> 144231ff0`
- The tiny constructors confirm the action object is only about `0x30` bytes and defaults `+0x2c = 0x10`.
- The `BrickAction_PlacePrefab` method block at `146c6c5d0` now dumps as:
  - `+0x00 -> 140024240`
  - `+0x08 -> 14422d690` (`BrickAction_PlacePrefab` name registration)
  - `+0x10 -> 140001000`
  - `+0x18 -> 1443f6f00` (the previously pinned `GlobalGridTarget` additive lane into `14473cae0`)
  - `+0x20 -> 140013db0`
  - `+0x28 -> 0`
  - `+0x30 -> 140045d70`
  - `+0x38 -> 14422f970`
  - `+0x40 -> 144232180`
  - `+0x48 -> 1442321d0`
- There are no direct xrefs to the slot address `146c6c5e8` and no direct xrefs to the constructor table base `146c6c500`.
- Current inference from that negative result: the `PlacePrefab` action is reached through a generic descriptor-driven action/transaction system, not via direct static calls to the slot/function addresses.

Important correction on the known paste-hit lane:
- `14483aa90` is still part of the `ServerPastePrefab` cache-hit path, but it is broader orchestration than a direct place/apply call.
- Its direct callees are:
  - `1447c6500`
  - `14483aed0`
  - `14483a660`
- `14483aed0` batch-initializes up to 10 records of size `0x108` at `param_1 + 0x1e0`, copies/normalizes each slot with `144172df0`, and feeds each record through `14423b660`.
- `14423b660` is a generic record copier/importer: it clones one `0x108` record into a large local structure and forwards it into `140510400(...)`.
- `14483a660 -> 144839790` and `14483aed0 -> 1448390e0` looked promising at first, but one of the shared helpers under them (`144838d20`) is a keyed listener/cache-dispatch utility, not a `PlacePrefab` executor.
- `144838d20` hashes a key, looks up queued listeners, and on miss builds a new listener entry via `14249d290(...)`; it also gates on a reflected class accessor from `14423b230`, so this branch is cache/listener infrastructure, not the actual action apply path.

Current read:
- The confirmed additive `GlobalGridTarget` path still lives inside `BrickAction_PlacePrefab` (`1443f6f00`).
- The missing bridge is now best modeled as a generic action/transaction dispatcher that selects methods out of the `146c6c5d0` block.
- The known `ServerPastePrefab -> 14481b240 -> 14483aa90` lane is still relevant, but the functions immediately below `14483aa90` are mostly request/setup/container work rather than the final `PlacePrefab` slot invocation.
- Best next static target: find the generic descriptor-driven dispatch that consumes the `146c6c500` / `146c6c5d0` tables and actually invokes the `+0x18` `PlacePrefab` method.

## 2026-03-25 later checkpoint: `PlacePrefab` queue-builder to submit bridge

New helpers:
- Added `GhidraFindRefsToRange.java` for operand refs into an arbitrary address range.
- Added `GhidraFindIndirectCallsByDisp.java` to scan indirect CALL/JMP instructions by displacement.
- Added `GhidraDumpInstructionWindow.java` for local instruction windows around critical callsites.

What landed:
- Range refs into the `BrickAction_PlacePrefab` block confirmed the only code writing that descriptor pointer is still:
  - `144231fb0`
  - `144231ff0`
  - `1448a4410`
  - `1448b5100`
- No useful refs landed on the packed `145c0f510-145c0f590` registry range.
- Broad indirect-call search for displacement `+0x18` in both `144800000-144900000` and `144000000-145000000` found `0` matches, so the final action-method bridge is not showing up as a simple `CALL [reg+0x18]` pattern.

Important local bridge:
- `14422d920` is a generic record-submit wrapper:
  - clones a large caller-provided record blob
  - forwards it into `140510400(param_1, &local_d0)`
- `14422d920` has a single direct caller in this neighborhood:
  - `1443fb630`
- `1443fb630` is a local state-machine / queue-commit helper that:
  - works on fields like `+0x110/+0x118/+0x120/+0x128/+0x130/+0x138/+0x140`
  - then dispatches to `14422d920(*(DAT_146d778c8[state-1]) + param_1, ...)`
- `1443fb630` is called by `1443fa4d0`
- `1443fa4d0` does the key local bridge work:
  - validates current state
  - resolves a context/object from `param_1 + 0xa0`
  - derives a key with `1443fb1c0` and `14466d2a0`
  - fires callback/listener dispatch via `1443fb2e0`
  - then calls `1443fb630(param_1, 1)` to submit
- `1443fb2e0` is not the record builder; it is a listener/callback dispatcher over a queued structure and should not be treated as the final place executor.

Most important bridge to the `PlacePrefab` writers:
- `1443fa1e0` calls `1443fa4d0`
- both heavy `PlacePrefab` writer functions call `1443fa1e0` directly:
  - `1448a4410 -> 1443fa1e0` at `1448a5ced`
  - `1448b5100 -> 1443fa1e0` at `1448b613e`
- That gives us a concrete bridge:
  - `PlacePrefab` descriptor-writer
  - -> local queue/context setup
  - -> `1443fa1e0`
  - -> `1443fa4d0`
  - -> `1443fb630`
  - -> `14422d920`
  - -> generic `140510400` submit

Instruction-window evidence for `1448b5100`:
- It allocates/links a node-like buffer under fields on `RBX`:
  - `+0x40`
  - `+0x48`
  - `+0x5a`
  - `+0x5c`
  - `+0x60`
- Then it writes the `BrickAction_PlacePrefab` descriptor into the aligned node payload:
  - `LEA RAX,[146c6c5d0]`
  - `MOV [RCX],RAX`
  - zeroes the body
  - sets `+0x2c = 0x10`
  - stores an object/pointer at `+0x18`
- Immediately after that setup, it calls `1443fa1e0`.
- Current inference: `1448b5100` is directly constructing the queue node plus embedded `BrickAction_PlacePrefab` object before the generic submit path runs.

Instruction-window evidence for `1448a4410`:
- The callsite into `1443fa1e0` is structurally similar, but this wrapper is feeding more string/object-building helpers immediately before submit (`14012fa40`, `1400e2d60`, `1400e2de0`) rather than the explicit low-level node-allocation pattern seen in `1448b5100`.
- So `1448a4410` is likely a sibling higher-level `PlacePrefab` wrapper, while `1448b5100` is currently the clearest low-level constructor/submit lane.

Current read:
- We no longer just know that `1448a4410` / `1448b5100` write the `PlacePrefab` descriptor.
- We now know they bridge into a concrete local submit pipeline ending in `140510400`.
- `1448b5100` is the strongest headless-native lead right now because it visibly constructs the queue node and embedded `BrickAction_PlacePrefab` object before submission.
- Best next target: keep climbing outward from `1448b5100` / `1443fa1e0` and identify which caller/context prepares the exact fields needed for a server-usable `PlacePrefab` submission.

## 2026-03-25 native PlacePrefab split checkpoint

- Switched the headless Ghidra note workflow to `-readOnly -noanalysis`; this fixes the repeated project-lock/reanalysis churn and makes the call/window dumps usable again.
- `FUN_144815870` is now confirmed as a large orchestrator that calls `FUN_1443fa1e0` twice:
  - first at `144816db3`
  - second at `1448177b7`
- Both `144815870` callsites use the same submit shape:
  - `RCX = *(RDI + 0x988)`
  - `RDX = R15`
  - `R8B = 1`
  - `R9D = 0`
- The two `144815870` submit calls are preceded by different request/payload builders (`144931270`, `1449310d0`, stack record assembly, string builders around `146dc1a4c` plus differing literal slabs), so this looks like one higher wrapper producing multiple concrete `PlacePrefab` submissions rather than one monolithic direct paste body.
- `FUN_1448b2e30` is a much thinner direct `FUN_1443fa1e0` submitter:
  - queue/list state on `+0x40/+0x48/+0x5c`
  - allocate `0x7ff0`
  - immediate `CALL FUN_1443fa1e0` at `1448b350c`
- The `1448b2e30` call window matches the earlier `1448b5100` shape closely, but without the larger outer orchestration. Current read: `1448b2e30` is one of the cleanest low-level native queue-node + submit bodies we have.
- Important model correction: the `14480ff90` call near `1448b350c` belongs to the next function, `FUN_1448b3590`, not to `FUN_1448b2e30`.
- `FUN_1448b3590` is therefore a separate higher wrapper / pre-submit validator layer, not the tiny submitter itself.
- `FUN_1448b3590` builds a three-part string/object payload from literals at:
  - `146dce480`
  - `146dcde86`
  - `146dce42a`
- It then calls:
  - `FUN_14480ff90(context, DAT_147883c28, builtPayload, 0)` at `1448b365f`
- `FUN_14480ff90` returns a boolean gate and is shared by:
  - `FUN_14425dc80`
  - `FUN_1447c1380`
  - `FUN_1447c2100`
  - `FUN_1448aff00`
  - `FUN_1448afff0`
  - `FUN_1448b05c0`
  - `FUN_1448b0cc0`
  - `FUN_1448b3590`
- After the `14480ff90` gate succeeds, `FUN_1448b3590` resolves/compares several object surfaces:
  - `FUN_14427c870`
  - `FUN_144734d70`
  - `FUN_142955470`
  - plus reads through `object + 0x968`
- Current read: `1448b3590` is establishing contextual ownership/selection/state before some later placement lane, not directly doing the `FUN_1443fa1e0` submit itself.
- `FUN_14489bec0` is a useful family marker: callers are
  - `FUN_1448a1780`
  - `FUN_1448a2d30`
  - `FUN_1448a4410`
- That reinforces that the `1448a1780/1448a2d30/1448a4410` cluster is one higher-level PlacePrefab family distinct from the smaller `1448b2e30` submit body.
- Working model now:
  - higher orchestration/wrapper families: `144815870`, `1448a2d30`, `1448a4410`, `1448b3590`
  - thin low-level submit bodies: `1448b2e30`, `1448b5100`
  - common native submit chain: `1443fa1e0 -> 1443fa4d0 -> 1443fb630 -> 14422d920 -> 140510400`
- Best next static target: identify who consumes the successful `14480ff90` gate and eventually chooses between the thin submit bodies (`1448b2e30` / `1448b5100`) so we can stop chasing wrapper layers and target the smallest server-safe native invocation surface.

## 2026-03-25 table-backed selector checkpoint

- Hard address xrefs now confirm the thin submitters live in data, not just code:
  - `FUN_1448b2e30` refs:
    - `147b0c604`
    - `145c1f1a4`
    - `146d0d398`
  - `FUN_1448b5100` refs:
    - `147b0c658`
    - `145c1f1b8`
    - code refs from `FUN_1448b3ff0` at `1448b4bdb` / `1448b4be2`
- `FUN_1443f6f00` still shows the same descriptor-style pattern:
  - direct data ref at `146c6c5e8`
- New strong table recovery:
  - qwords at `146d0d380` decode to a contiguous function table:
    - `146d0d380 -> FUN_1448b6460`
    - `146d0d388 -> FUN_1448b6370`
    - `146d0d390 -> FUN_1448b3590`
    - `146d0d398 -> FUN_1448b2e30`
    - `146d0d3a0 -> FUN_1448b1cf0`
    - `146d0d3a8 -> FUN_1448b0cc0`
    - `146d0d3b0 -> FUN_1448b05c0`
    - `146d0d3b8 -> FUN_1448afff0`
- Current read: `146d0d380` is a real method/descriptor family table for the `1448afff0 -> 1448b3590 -> 1448b2e30` lane.
- This explains why `FUN_1448b2e30` had no direct code callers in the earlier dump: it is very likely reached through this table-driven dispatch surface.
- Important parallel-path recovery:
  - `FUN_1448b3ff0` directly installs `FUN_1448b5100` into a small heap object, then hands that object into the prefab-cache wrap path.
- `FUN_1448b3ff0` window around `1448b4bdb` now shows:
  - allocate/init a small object at `R14`
  - store callback/continuation pointer:
    - `LEA RAX,[FUN_1448b5100]`
    - `MOV [R14 + 0x30], RAX`
  - then call `FUN_14439bbf0(RBX, ..., &local_28, &local_40)`
- Same window also touches the reflected prefab-cache entry type:
  - `FUN_1442209e0` (`/Script/Brickadia.BRPrefabCacheInMemoryPrefab` class accessor)
- Current read on `FUN_1448b3ff0`:
  - it is not the simple action-table lane
  - it is a prefab-cache-backed callback/continuation constructor
  - `FUN_1448b5100` is the continuation it installs for the later step
- That gives us two distinct but related native prefab-placement families now:
  - table-backed action family:
    - `146d0d380`
    - `FUN_1448afff0`
    - `FUN_1448b3590`
    - `FUN_1448b2e30`
  - prefab-cache callback family:
    - `FUN_1448b3ff0`
    - `FUN_14439bbf0`
    - callback pointer `FUN_1448b5100`
- This makes `FUN_1448b3ff0` the best bridge yet between:
  - server-side prefab cache materialization
  - and a later native placement continuation
- Best next target:
  - climb from `FUN_1448b3ff0` into its tail-jump continuation at `FUN_1448b5010`
  - and compare that callback-backed family against the table family at `146d0d380`
  - goal: find the smallest point where a prepared cache entry becomes a real placement request

## 2026-03-25 callback-object refinement checkpoint

- `FUN_1448b5010` is now identified as the tail-jump target from `FUN_1448b3ff0`.
- Important correction: `FUN_1448b5010` is not the placement continuation.
  - direct calls are only small helper/report-style functions:
    - `1400e97c0`
    - `140237da0`
    - `140035ca0`
    - `1401332a0`
  - caller dump shows only:
    - `FUN_1448b3ff0`
- Current read: `FUN_1448b5010` is the small post-branch/report/log helper that `FUN_1448b3ff0` tail-jumps into on one path, not the real native placement executor.
- The callback object vtable swap remains the more important clue:
  - `FUN_1448b3ff0` first allocates a generic shell using vtable `145d4eb80`
  - then swaps the object to vtable `146db2880`
  - installs callback pointer `FUN_1448b5100` at `[object + 0x30]`
- Address xrefs for `146db2880` now show it is a shared callback/handler type, not unique to `FUN_1448b3ff0`:
  - `FUN_1448b3ff0`
  - `FUN_1447875d0`
  - `FUN_144787650`
  - `FUN_14473be00`
  - `FUN_144739070`
- That is important because the `14473...` region overlaps the additive-load/native prefab area we already care about.
- Current read:
  - `146db2880` is likely a reusable callback/continuation object type
  - `FUN_1448b5100` is one installed callback for the prefab-cache-backed lane
  - sibling constructors in the `144739070` / `14473be00` region may show the same object layout with different installed callbacks, which is the best route to understanding how to drive this family safely
- Best next target:
  - compare the `146db2880` sibling constructors (`144739070`, `14473be00`, `1447875d0`, `144787650`) against `FUN_1448b3ff0`
  - goal: recover the generic callback-object layout and identify which callback member actually transitions into placement vs. just reporting/logging

## 2026-03-25 passing callback-family test + additive ladder checkpoint

- Added a real regression test:
  - `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\scripts\test-prefab-callback-family.ps1`
- It passes now:
  - `PASS test-prefab-callback-family`
- The test currently locks these invariants into the repo:
  - shared callback vtable `146db2880`
  - `FUN_1448b3ff0` installs callback `FUN_1448b5100`
  - `FUN_144739070` installs callback `FUN_14473be00`
  - `FUN_14473be00` installs callback `FUN_14473c3f0`
- New additive-side callback ladder:
  - `FUN_144739070`
    - allocates generic shell with `145d4eb80`
    - swaps to callback vtable `146db2880`
    - stores `FUN_14473be00` at `[object + 0x30]`
    - calls `FUN_14439bf90(...)`
  - `FUN_14473be00`
    - allocates generic shell with `145d4eb80`
    - swaps to callback vtable `146db2880`
    - stores `FUN_14473c3f0` at `[object + 0x30]`
    - calls `FUN_14439bf90(...)`
- Parallel cache-side callback lane remains:
  - `FUN_1448b3ff0`
    - swaps to callback vtable `146db2880`
    - stores `FUN_1448b5100` at `[object + 0x30]`
    - calls `FUN_14439bbf0(...)`
- This is a strong structural split:
  - additive-side/shared async handoff lane: `FUN_14439bf90`
  - cache-wrap/archive lane: `FUN_14439bbf0`
- Important correction:
  - `FUN_1448b5010` is only the small tail/report helper for one `FUN_1448b3ff0` branch, not the real placement continuation.
- Current best read:
  - `146db2880` is a reusable callback/continuation object type
  - `FUN_14439bf90` is likely the more important async bridge for the additive/native family
  - `FUN_14473c3f0` is now the best callback target to keep climbing if the goal is the real runtime load/placement step
- Best next target:
  - inspect `FUN_14439bf90` and compare it directly against `FUN_14439bbf0`
  - confirm whether `FUN_14439bf90` is the async callback registration/handoff that turns prepared world/prefab state into the next-stage native callback invocation

## 2026-03-25 - shared async handoff and cache-finalization boundary

The callback-family model is now strong enough to lock with passing tests.

Shared handoff:
- `FUN_14439bf90` is the shared async handoff helper.
- It is reached from both cache-seeding families:
  - `FUN_14439bbf0` (archive-wrap lane)
  - `FUN_14439c410` (raw-bytes lane)
- It is also reached from the additive-side callback ladder:
  - `FUN_144739070`
  - `FUN_14473be00`
- `FUN_14439bf90` has a single direct callee of interest: `FUN_1443c1260`.

Lane-specific installed callbacks:
- `FUN_14439bbf0` installs callback `FUN_14439c090` before handing off through `FUN_14439bf90`.
- `FUN_14439c410` installs callback `FUN_14439cf70` before handing off through `FUN_14439bf90`.
- `FUN_144739070` installs callback `FUN_14473be00` before handing off through `FUN_14439bf90`.
- `FUN_14473be00` installs callback `FUN_14473c3f0` before handing off through `FUN_14439bf90`.

Per-lane split, then reconvergence:
- Archive-wrap callback lane:
  - `FUN_14439c090`
  - unique helper `FUN_14439d280`
  - shared helpers `FUN_14439d370 -> FUN_14439d4f0`
- Raw-bytes callback lane:
  - `FUN_14439cf70`
  - unique helpers `FUN_14439e190` and `FUN_14439e280`
  - shared helpers `FUN_14439d370 -> FUN_14439d4f0`

Shared finalization boundary:
- `FUN_14439d370` is called by both `FUN_14439c090` and `FUN_14439cf70`.
- `FUN_14439d4f0` is also called by both `FUN_14439c090` and `FUN_14439cf70`.
- `FUN_14439d4f0` then calls `FUN_14439e310` with:
  - `RCX = RSI`
  - `RDX = &stack_struct`
  - `R8B = 1`
- This is the best current cache-finalization/dedupe boundary below the two lane-specific callbacks.

Interpretation:
- raw `.brz` bytes and existing-archive wrap use different short callback branches,
- but both reconverge into a shared cache-finalization path before later prefab application/use layers.
- This is currently the clearest reusable server-side seam for headless cache seeding.

Regression coverage:
- `scripts/test-prefab-callback-family.ps1`
- `scripts/test-prefab-shared-async-handoff.ps1`
- both passing on 2026-03-25.

## 2026-03-25 - selector insert path below cache finalization

The finalized cache path is now pinned one layer deeper.

Selector-local bridge:
- `FUN_14439e310` calls `FUN_1443c23c0`.
- `FUN_1443c23c0` is still only reached from `FUN_14439e310`.
- `FUN_1443c2520` is only reached from `FUN_1443c23c0`.

`FUN_1443c23c0` behavior:
- stages a temporary selector record by copying a `0x20` byte payload into a fresh node
- copies the auxiliary pointer into `node + 0x20`
- initializes `node + 0x28 = -1`
- passes:
  - `RCX = selector container`
  - `EDX = staged record key/hash-ish dword`
  - `R8 = temp node`
  - `R9 = &stack_out_index`
  - stack arg = caller-owned output/context pointer
- branches on the boolean result from `FUN_1443c2520`
- on failure, computes a larger selector-table size, writes it to `container + 0x48`, and calls `FUN_1407fffe0`
- then updates the ring/slot arrays and writes the chosen selector index back to the caller output pointer

`FUN_1443c2520` behavior:
- looks like the real selector slot probe/commit helper
- probes a selector table rooted at:
  - inline arrays near `+0x10/+0x38`
  - optional heap arrays at `+0x20/+0x40`
  - mask/size field at `+0x48`
- uses a bitset/occupancy check before comparing candidate slots
- compares the staged `0x20` byte record against an existing slot using `VPTEST`
- on success:
  - copies the staged record into the chosen slot
  - copies the auxiliary pointer into `slot + 0x20`
  - calls `FUN_1403a0af0` for bookkeeping
  - writes the committed slot index back through the out-index pointer
  - returns `AL = 1`
- on failure returns `AL = 0`

Interpretation:
- the finalized prefab-cache path now reaches a concrete selector insertion/update layer, not just logging helpers
- `FUN_1443c23c0 -> FUN_1443c2520` is currently the clearest bridge from cache-finalized prefab state into a selected record/index that later prefab application code can consume
- this is a stronger headless lead than the earlier `14439e620/14439e6b0` diagnostic tail helpers

Regression coverage:
- `scripts/test-prefab-callback-family.ps1`
- `scripts/test-prefab-shared-async-handoff.ps1`
- `scripts/test-prefab-cache-finalization-orchestration.ps1`
- `scripts/test-prefab-finalization-helper-split.ps1`
- `scripts/test-prefab-selector-insert-path.ps1`
- all passing on 2026-03-25

## 2026-03-25: cache-entry archive bridge and first post-selector consumer

New passing regressions:
- `test-prefab-cache-entry-archive-bridge.ps1`
- `test-prefab-post-selector-consumer.ps1`

What this locked down:
- `FUN_14439d370` is the converged archive bridge beneath both cache-seeding lanes:
  - callers: `FUN_14439c090` and `FUN_14439cf70`
  - reads `BRPrefabCacheInMemoryPrefab.PrefabArchive` from `+0xf0`
  - hands the archive-derived helper into the converged working-record region at `+0x38`
- `FUN_14475f3c0` is a first real downstream consumer under `FUN_14439d4f0`:
  - caller: `FUN_14439d4f0`
  - shares the downstream cleanup family via `FUN_1443c2640`
  - zeroes a 4-output cluster up front
  - drives processing from the working-record count at `+0x178`

Current green stack:
- `test-prefab-callback-family.ps1`
- `test-prefab-shared-async-handoff.ps1`
- `test-prefab-cache-finalization-orchestration.ps1`
- `test-prefab-finalization-helper-split.ps1`
- `test-prefab-selector-insert-path.ps1`
- `test-prefab-selector-helper-roles.ps1`
- `test-prefab-cache-entry-archive-bridge.ps1`
- `test-prefab-post-selector-consumer.ps1`

## 2026-03-25: shared finalizer surface below additive/prefab convergence

New passing regression:
- `test-prefab-shared-finalizer-surface.ps1`

What this locked down:
- `FUN_14473d890` is shared between the prefab-cache consumer path and the additive-side family:
  - callers/xrefs include `FUN_14439d4f0`, `FUN_14473cf60`, and `FUN_144739070`
- its visible prologue is a retained-object sweep over a dense slot block:
  - `+0x588`
  - `+0x558`
  - `+0x548`
  - `+0x538`
  - `+0x528`
  - `+0x518`
- the sweep uses the shared release helper `FUN_14008a1e0`
- deeper in the function it also uses `TryAcquireSRWLockExclusive` / `ReleaseSRWLockExclusive`, so this is synchronized cleanup/finalization state, not a tiny leaf helper

## 2026-03-25: additive caller split closed back into the shared runner

New passing regressions:
- `test-prefab-additive-stage-runner.ps1`
- `test-prefab-additive-caller-split.ps1`

What this locked down:
- `FUN_14473cae0` is the shared additive coordinator:
  - callers include `FUN_144867650` (`PreviewPart`), `FUN_1443f6f00` (`GlobalGridTarget`), and `FUN_1446ea4c0` (reflected bundle-manager callback lane)
  - it enforces the mutually-exclusive target shape by checking `[R8]` vs `[R8 + 0x18]` before delegating to `FUN_14473cf60`
- `FUN_14473cf60` is the shared additive-stage runner:
  - only caller is `FUN_14473cae0`
  - invokes `FUN_1447330c0` for prefab serializer/materialization work
  - later invokes `FUN_14473d890` for shared finalization
- caller-shape split is now concrete under test:
  - `FUN_1443f6f00` stages a `GlobalGridTarget` block at `[RSP + 0xd0]` and policy flags at `[RSP + 0xf4..0xf6]`
  - `FUN_144867650` clears the `GlobalGridTarget` slot and instead stages `PreviewPart` through `[RSP + 0x58]`, with its params/result block rooted at `[RSP + 0x80]`
  - both then call `FUN_14473cae0`

## 2026-03-25 update: preview-family bridge and handoff locked under regression

New passing regressions:
- `test-prefab-preview-external-bridges.ps1`
- `test-prefab-preview-family-handoff.ps1`

Current green stack is now `15/15`.

What got pinned:
- `FUN_1442a6090` now has concrete external code-side bridges, not just packed-table membership.
- `FUN_144866e40` is the small preview-side bridge:
  - seeds a local one-entry carrier through `FUN_140237e50`
  - calls `FUN_1442a6090` twice
  - combines the paired results through `FUN_1417ad070`
  - dispatches the combined result into `FUN_1429d7320`
- `FUN_14489e260` is the heavier orchestration-side bridge:
  - reacquires owner/context through `FUN_144862ff0`
  - calls `FUN_1442a6090` in a first packaging phase
  - packages that result through `FUN_14059f290`
  - hands it into `FUN_14486b520`
  - later calls `FUN_14486bd00` and `FUN_1442a6090` again in a selector/membership phase
  - validates the second bridge result against the indexed slot table via `[RAX + 0x38]` / `[RCX + RDX*0x8]`
- `FUN_14486b520` is now the tested handoff between the packed preview family and the vtable-style preview family:
  - callers include `FUN_14489e260` and `FUN_1442a6fb0`
  - consumes packed-family selector state through `FUN_1442a5210`
  - creates/acquires the vtable-style preview object through `FUN_144885710`
  - resolves a second selector-backed object through `FUN_144266c20`
  - normalizes it through `FUN_14466d2a0`
  - stores bridged state at `+0x2c0` / `+0x2c8`
  - commits through `FUN_140b9c7d0` with `R8D = 3`
- `FUN_14486bd00` remains a small selector-state feeder used by both:
  - `FUN_14489e260`
  - `FUN_1442a6ec0`

Current read:
- the packed preview-family branch and the older vtable-style preview branch are no longer separate stories
- they reconverge through `FUN_14486b520`
- that makes the next upward target much narrower: the first owner above `FUN_14489e260` / `FUN_1442a6fb0` that can drive this now-tested preview handoff

## 2026-03-25 update: preview owner ladder now reaches a higher control tree

New passing regressions:
- `test-prefab-preview-owner-wrapper-ladder.ps1`
- `test-prefab-preview-higher-owner-hierarchy.ps1`

Current green stack is now `17/17`.

What got pinned:
- `FUN_1447c6030` is now a tested stack-packaging owner wrapper above the preview-family handoff:
  - stages a large mixed request block from `RSI + 0x10 .. 0x100` onto the stack
  - passes `RCX = RDI`, `RDX = &stackRequest`, `R8D = EBX`
  - then calls `FUN_14489e260`
- `FUN_1447c65e0` and `FUN_1447c7b70` are the next higher preview-owner wrappers above `FUN_1447c6030`
- `FUN_1447b4ff0` is the first higher control-tree owner above those wrappers:
  - calls `FUN_1447c65e0`
  - calls `FUN_1447c74e0`
  - is itself called by `FUN_1447b4290`
- `FUN_1447c74e0` is the second mid-owner splitter under `FUN_1447b4ff0`:
  - calls `FUN_1447c7b70` twice across two phases
  - calls `FUN_1447c8920`
- `FUN_1447c8920` and `FUN_1447c8b00` both feed back into `FUN_1447c65e0`

Useful structural read from the higher owner window:
- `FUN_1447b4ff0` reads retained preview state from `this + 0x8a8`
- gates on `this + 0x170 == 3`
- stages option bytes from `this + 0xac4` and `this + 0xac5`
- calls `FUN_1447c65e0`
- retains results at `this + 0xd50` and vector payload at `this + 0xd58`
- then falls into `FUN_1447c74e0` as the second branch when needed

Current read:
- the preview path is no longer just a family graph
- it is a tested ladder:
  - `FUN_1447b4290`
  - `FUN_1447b4ff0`
  - `FUN_1447c74e0` / `FUN_1447c65e0`
  - `FUN_1447c7b70` / `FUN_1447c8920` / `FUN_1447c8b00`
  - `FUN_1447c6030`
  - `FUN_14489e260`
  - `FUN_14486b520`
  - preview-family handoff
- that makes `FUN_1447b4290` the next upward target on this branch

## 2026-03-25 update: 1447b4290 is now locked as a data-backed top-owner seam

New passing regression:
- `test-prefab-preview-top-owner-table-anchor.ps1`

What got pinned:
- `FUN_1447b4290` is now regression-backed as the current top-owner candidate on the preview branch:
  - direct call `1447b45de -> FUN_1447b4ff0`
  - gated by `this + 0x850`
  - followed by the paired `this + 0x739` / `this + 0x73a` continuation gates
- `FUN_1447b4290` is anchored in two data tables at once:
  - qword table entry `146ba46d0 -> 1447b4290`
  - packed dword candidate entry `147b073cc -> 047b4290 candidate=1447b4290`
- the adjacent qword table cluster includes:
  - `141e698b0`
  - `141e4a670`
  - `141e478d0`
  - `142698450`
  - `1447b4290`
  - `1447b3aa0`
- both table ranges are now checked as data-only from the instruction-reference side:
  - `146ba46b0-146ba4730`
  - `147b073b0-147b073f0`
  - `GhidraFindRefsToRange` reports `no instruction references found` for both

Current read:
- `FUN_1447b4290` is no longer just ìthe next function upî
- it is the current top-owner seam for this preview branch, and it is being selected through data-backed dispatch state rather than ordinary code callers
- that makes the next upward task narrower: identify the owner/dispatcher that selects these table slots, instead of climbing by ordinary call xrefs

## 2026-03-26 update: packed-family metadata above the top-owner seam is now regression-backed

New passing regression:
- `test-prefab-preview-packed-dispatch-family.ps1`

Current green stack is now `19/19`.

What got pinned:
- the region at `145c1d540-145c1d5a0` is now a tested packed dispatch-family block above the previously locked `FUN_1447b4290` seam
- it includes at least these candidate sibling entries in the scanned window:
  - `145c1d548 -> 047afe60 candidate=1447afe60`
  - `145c1d55c -> 047b3aa0 candidate=1447b3aa0`
  - `145c1d570 -> 047b71b0 candidate=1447b71b0`
  - `145c1d584 -> 047b8110 candidate=1447b8110`
  - `145c1d598 -> 047b84f0 candidate=1447b84f0`
- the entire packed-family range `145c1d540-145c1d5a0` is now checked as data-only from the instruction-reference side:
  - `GhidraFindRefsToRange` reports `no instruction references found`
- `FUN_1447b71b0` is the most relevant sibling sampled so far:
  - `1447b72b8 -> FUN_144844100`
  - `1447b734e -> FUN_144266c20`
  - `1447b7379 -> FUN_14480da80`

Current read:
- `FUN_1447b4290` is not sitting under one isolated hidden caller
- it lives inside a broader packed control/dispatch family with multiple sibling handlers
- the next upward target is now the selector that chooses among these packed-family entries, not just the qword or dword slot itself

## 2026-03-26 update: packed-family sibling 1447b71b0 shares the same owner-state control surface

New passing regression:
- `test-prefab-preview-packed-family-owner-shape.ps1`

Current green stack is now `20/20`.

What got pinned:
- `FUN_1447b71b0` is no longer just a sibling in the packed-family metadata block
- it operates on the same kind of owner/control surface as the `FUN_1447b4290` preview branch
- key owner-side surfaces now regression-backed in the `1447b71b0` windows:
  - `LEA RBX,[RCX + 0x648]`
  - `MOV R13,qword ptr [RDI + 0x840]`
  - `CMP byte ptr [RDI + 0x851],0x1`
  - `CMP RSI,qword ptr [RDI + 0x2e0]`
  - `VADDSS XMM0,XMM6,dword ptr [RDI + 0x854]`
  - `VMOVSS XMM1,dword ptr [RDI + 0x858]`
- the sibling branch also preserves the selector/apply-style handoff sequence:
  - `CALL 0x144844100`
  - `CALL 0x144266c20`
  - `CALL 0x14480da80`

Current read:
- the packed-family block above `FUN_1447b4290` is not a separate subsystem
- at least one sibling (`FUN_1447b71b0`) clearly shares the same owner/state control tree and selector-style object validation surfaces
- the next upward target is now the selector/owner object that chooses between these same-family handlers, not a missing caller for only one branch

## 2026-03-26 update: 144844100 is now locked as a shared control bridge across multiple caller families

New passing regression:
- `test-prefab-preview-shared-bridge-caller-split.ps1`

Current green stack is now `21/21`.

What got pinned:
- `FUN_144844100` is not a one-branch helper
- its caller set now regression-backed includes at least:
  - `1447b72b8 <- FUN_1447b71b0`
  - `14480c49b <- FUN_14480c390`
  - `14427da8b <- FUN_14427d8d0`
- the bridge itself preserves a stable internal shape:
  - `144844171 -> FUN_1421f4310`
  - `1448441ff -> FUN_144286c80`
- `FUN_14480c390` is now the clearest non-packed-family caller sampled so far:
  - anchors a sibling owner-side object surface at `+0x858`
  - stages a second owner-side state surface at `+0x8b8`
  - folds threshold state from `+0x8b0`
  - stages a local request/result block and calls `FUN_144844100`
  - then continues into later preview-side helpers including `FUN_144188fc0` and `FUN_1441707f0`

Current read:
- `FUN_144844100` is the strongest shared control bridge above the packed-family sibling layer so far
- it links multiple caller families into the same selector/apply-style control surface
- the next upward target is no longer just the packed table selector itself
- it is the common selector contract around `FUN_144844100` and the object returned through `FUN_1421f4310`

## 2026-03-26 update: shared bridge selector contract is now regression-backed

New passing regression:
- `test-prefab-preview-shared-bridge-selector-contract.ps1`

Current green stack is now `22/22`.

What got pinned:
- `FUN_144286c80` is now locked as an exclusive downstream handoff under the shared bridge:
  - current caller set count is `1`
  - caller: `1448441ff <- FUN_144844100`
- the selector contract inside `FUN_144844100` is now much tighter:
  - input gate requires `[RDX]` and `[RDX + 0x8]`
  - candidate resolution goes through `FUN_1421f4310`
  - candidate record uses:
    - index at `+0x38`
    - membership pointer table rooted at container `+0x30`
  - validated downstream handoff then rebases owner/context through `+0x4b8` before calling `FUN_144286c80`
- `FUN_14427d8d0` is now confirmed as another caller that stages the same shared-bridge call contract from a local scratch block:
  - `R9 <- [RSP + 0x40]`
  - `R8 <- [RSP + 0x48]`
  - stack cell at `[RSP + 0x30]`
  - `RCX <- RDI`
  - then `CALL 0x144844100`
  - return value is consumed as a success byte via `MOV byte ptr [RSI],AL`

Current read:
- the most useful seam above the packed-family handlers is now the `FUN_144844100 -> FUN_1421f4310 -> FUN_144286c80` selector/apply contract
- that is a better upward target than the raw packed dispatch tables themselves
- the next practical task is to characterize the object returned by `FUN_1421f4310` and the rebased owner/context path at `+0x4b8`

## 2026-03-26 update: selector lookup and exclusive downstream dispatch are now both regression-backed

New passing regression:
- `test-prefab-preview-selector-lookup-and-downstream-dispatch.ps1`

Current green stack is now `23/23`.

What got pinned:
- `FUN_1421f4310` is now modeled as a real hashed selector lookup, not just a generic helper:
  - bucket base at `+0x68`
  - optional bucket override at `+0x70`
  - bucket mask/count at `+0x78`
  - membership bitset override at `+0x50`
  - selector count at `+0x58`
  - record table at `+0x30`
  - record key compare against `R14`
  - record payload returned from `record + 0x8`
  - chained next-slot field at `record + 0x10`
- `FUN_144286c80` is now modeled as the exclusive downstream dispatcher after selector validation:
  - resolves a downstream dispatch root through `FUN_1404dfb20`
  - normalizes it through `FUN_14037fdf0`
  - branches on status/mode byte `[RAX + 0xd4] & 0x80`
  - preserves the bridge payload on stack at `+0x30/+0x40/+0x48/+0x50`
  - then dispatches through a virtual helper path selected from the owner/context object
- the two virtual downstream paths now visible in that branch are:
  - vtable `+0x378`
  - vtable `+0x280`

Current read:
- the cleanest live RE seam above the packed-family control branches is now:
  - `FUN_144844100`
  - `FUN_1421f4310`
  - `FUN_144286c80`
- the next practical target is the object/class behind the selector record returned by `FUN_1421f4310`, plus the rebased owner/context lane that chooses between the `+0x378` and `+0x280` virtual paths

## 2026-03-26 update: preview detour narrowed; cache-entry archive bridge locked

- Added and passed `test-prefab-preview-state-reconcile-tail.ps1`.
- Added and passed `test-prefab-global-gridtarget-cache-entry-archive-bridge.ps1`.
- `FUN_14480da80` is now better modeled as a shared preview/state-reconcile tail, not the headless additive executor:
  - only current caller is `FUN_1447b71b0`
  - it reuses the same preview-state container/query/build lane already visible in `FUN_14480c390`
  - shared tail includes `FUN_141e43a80 -> FUN_14298a490 -> FUN_14298a980`, plus the same callback shell/vtable swap and result-table dispatch
- `FUN_1443f6f00` now has a tighter headless-relevant bridge:
  - resolves owner/context through `FUN_142959410` and `FUN_142955470`
  - resolves selector candidates through `FUN_144734d70`
  - rebases through `+0x820`
  - sources a cached prefab/cache-entry object from `+0x18`
  - reads `PrefabArchive` from that entry at `+0xf0`
  - stages the `GlobalGridTarget` params block at `[RSP + 0xd0]`
  - stages the additive result/work block at `[RSP + 0x70]`
  - hands `PrefabArchive + GlobalGridTarget params` into `FUN_14473cae0`
- Current best read:
  - the preview-family branch has been narrowed and is less likely to be the shortest headless path
  - the strongest server-side seam is now `cached prefab entry -> PrefabArchive (+0xf0) -> GlobalGridTarget caller (1443f6f00) -> 14473cae0`

## 2026-03-26 update: native submitters and additive share an owner/context seam

- Added and passed `test-prefab-submit-and-additive-share-owner-context-seam.ps1`.
- `FUN_1443fa1e0` is now locked as a real bridge from the thin native submitters into the shared owner/context layer:
  - callers include `FUN_1448b2e30` and `FUN_1448b5100`
  - it preserves the staging/context object at `+0x138`
  - then hands into `FUN_1443fa4d0`
- `FUN_1443fa4d0` and `FUN_1443f6f00` now have a regression-backed shared seam:
  - both rebase through `+0x820`
  - both call `FUN_142955470`
- After that shared seam, the branches split cleanly:
  - submit-side branch: `FUN_1443fa4d0 -> FUN_1443fb1c0 -> FUN_1443fb2e0 -> FUN_1443fb630`
  - additive-side branch: `FUN_1443f6f00 -> cached prefab entry (+0x18) -> PrefabArchive (+0xf0) -> FUN_14473cae0`
- Current best read:
  - the native `PlacePrefab` submit family and the additive `GlobalGridTarget` family are not disconnected stories
  - they converge on a shared owner/context layer before diverging into submit-vs-additive execution
  - that shared seam is now one of the strongest remaining targets for a headless invoke path

## 2026-03-26 update: higher submit wrapper also funnels into the same seam

- Added and passed `test-prefab-higher-submit-wrapper-shares-owner-context-seam.ps1`.
- `FUN_144815870` is now regression-backed as a higher submit orchestrator above the thinner native submitters:
  - it rebases through the same `+0x820` owner/context block
  - it calls `FUN_142955470`
  - then it pivots into owner-local state sourced from the resolved object at:
    - `+0x2a0`
    - `+0x2a8`
- The higher wrapper now has two proven submit handoff sites:
  - `144816db3 -> FUN_1443fa1e0`
  - `1448177b7 -> FUN_1443fa1e0`
- Both submit sites use the same call shape:
  - `RCX = [RDI + 0x988]`
  - `RDX = R15`
  - `R8B = 1`
  - `R9D = 0`
- Current best read:
  - `FUN_144815870` is not incidental setup around the seam
  - it is a real higher-level submit wrapper that reuses the same owner/context resolution and then issues repeated submit-side handoffs through `FUN_1443fa1e0`

## 2026-03-26 update: higher submit wrapper shares a qword table with ServerPastePrefab

- Added and passed `test-prefab-submit-orchestrator-shares-qword-table-with-serverpaste.ps1`.
- A new direct reference probe now shows `FUN_144815870` is not floating on its own:
  - `GhidraListReferencesToAddress 144815870` reports a real data entry at `146cb1938`
- Dumping the surrounding qword block at `146cb1900` gives a controller-family-looking run:
  - `146cb1910 -> FUN_14481ae60`
  - `146cb1918 -> FUN_1448193b0`
  - `146cb1920 -> FUN_144819060`
  - `146cb1928 -> FUN_144818bf0`
  - `146cb1930 -> FUN_144818a40`
  - `146cb1938 -> FUN_144815870`
  - `146cb1940 -> FUN_1448156d0`
- Current best read:
  - `FUN_144815870` sits in the same structural qword-table family as the native `ServerPastePrefab` implementation `FUN_14481ae60`
  - that makes the higher wrapper much more likely to be a sibling controller-family handler than an unrelated helper

## 2026-03-26 update: controller-family qword table now has a regression-backed branch split

- Added and passed `test-prefab-controller-qword-table-branch-split.ps1`.
- The immediate qword-table family around `FUN_14481ae60` now splits cleanly into two useful buckets:
  - headless-relevant seam bucket:
    - `FUN_144815870`
    - `FUN_1448156d0`
  - sibling branch bucket:
    - `FUN_144819060`
    - `FUN_1448193b0`
- `FUN_1448156d0` now has a locked post-seam shape:
  - rebases through `+0x820`
  - calls `FUN_142955470`
  - then diverges into `FUN_1441bd030 -> FUN_144619190 -> FUN_144661420 -> FUN_14440aa50`
  - notably does **not** call `FUN_1443fa1e0`
- `FUN_144819060` and `FUN_1448193b0` do **not** enter `FUN_142955470` and do **not** submit through `FUN_1443fa1e0`.
- Current best read:
  - the controller-family table is no longer a blurry set of siblings
  - the only immediate entries still worth pursuing for headless prefab work are `FUN_144815870` and `FUN_1448156d0`

## 2026-03-26 update: helper subfamily before the submit orchestrator is BotSpawn-specific

- Added and passed `test-prefab-botspawn-helper-subfamily.ps1`.
- A new address-description pass pinned the narrow helper `FUN_1441bd030` to reflected BotSpawn data:
  - `/Script/Brickadia`
  - `Engine`
  - `UBrickComponentType_BotSpawn`
- That means the helper subfamily rooted at:
  - `FUN_1448154d0`
  - `FUN_1448156d0`
  is not a generic prefab-submit backbone.
- Both of those helpers call `FUN_1441bd030`, but `FUN_144815870` does not.
- Current best read:
  - `FUN_1448154d0` and `FUN_1448156d0` are controller-family siblings that route through a BotSpawn-specific reflected helper chain
  - `FUN_144815870` remains the stronger headless-prefab submit target because it stays outside that BotSpawn subfamily

## 2026-03-26 update: non-BotSpawn controller-family branch split is now pinned too

- Added and passed `test-prefab-controller-non-botspawn-branch-split.ps1`.
- `FUN_144818bf0` is not BotSpawn noise, but it still diverges away from the prefab submit bridge:
  - rebases through `+0x100`
  - calls `FUN_142955470`
  - then peels into `FUN_141b9cbb0`
  - and runs the paired helper/materialization path:
    - `FUN_1447f0e50 -> FUN_144602330`
    - `FUN_1447f37c0 -> FUN_144602330`
- `FUN_144815870` stays distinct inside the same non-BotSpawn slice:
  - it does not use `FUN_141b9cbb0`
  - it does not use `FUN_1447f0e50` or `FUN_1447f37c0`
  - it still issues direct submit handoffs through `FUN_1443fa1e0`
- Current best read:
  - the immediate non-BotSpawn table slice has at least two real sub-branches
  - `FUN_144815870` remains the strongest direct headless-prefab submit target
  - `FUN_144818bf0` is a comparison/selector sibling, not the submit lane

## 2026-03-26 ServerPastePrefab vs higher-submit branch split checkpoint

- Added and passed `test-prefab-serverpaste-vs-submit-orchestrator-branch-split.ps1`.
- `FUN_14481ae60` (native `ServerPastePrefab`) and `FUN_144815870` both enter the same owner/context seam:
  - `+0x820`
  - `FUN_142955470`
- After that seam, they diverge cleanly:
  - `FUN_14481ae60` goes through prefab-cache lookup and paste-hit/miss handling:
    - `FUN_14439ce60`
    - cache-hit `FUN_14481b240`
    - cache-miss/hash-acquire `FUN_1447a7750`
  - `FUN_144815870` does not use those helpers and instead issues direct thin-submit handoffs through `FUN_1443fa1e0`.
- Current best read:
  - `FUN_144815870` looks like a pre-resolved/native submit sibling in the same controller-family table as `ServerPastePrefab`, not just a cosmetic wrapper around the hash-driven paste path.
  - That makes its request-object builders and preconditions the best current target for a true headless invoke path.
- Neighbor triage update:
  - `FUN_144818a40` remains a side branch centered on `FUN_144833730` and `FUN_1441707f0`, not the direct submit seam.
  - `FUN_144814de0` is only a tiny helper around `FUN_1400e97c0`, so it is not the table-level feeder we want.

## 2026-03-26 submit-request builder split checkpoint

- Added and passed `test-prefab-submit-orchestrator-request-builder-split.ps1`.
- Added and passed `test-prefab-request-builder-helper-role-split.ps1`.
- `FUN_144815870` does not have one monolithic submit shape; it has at least two tested variants:
  - richer variant:
    - `FUN_141e439b0`
    - `FUN_144931270`
    - `FUN_1449310d0`
    - explicit staged fields including `+0x3b0 = 2` and float payload at `+0x3b8`
    - then thin-submit `FUN_1443fa1e0`
  - simpler variant:
    - `FUN_1449310d0`
    - no `FUN_144931270`
    - no richer `+0x3b0` / `+0x3b8` staged fields
    - then thin-submit `FUN_1443fa1e0`
- Helper-role split is now clearer:
  - `FUN_1449310d0` is the common request-fragment builder shared across multiple controller-family handlers (`144815870`, `14481ede0`, `14481f4d0`, `1448203b0`, `144820c60`).
  - `FUN_144931270` is the richer sidecar builder with owner-side helper calls (`FUN_1447f0e50`, `FUN_1447f6ee0`) and a narrower caller surface.
- Current best read:
  - the simpler `FUN_144815870` variant that only depends on `FUN_1449310d0` is the best first headless-native target.
  - if we can characterize the minimum request object expected by that variant, we may be able to avoid the richer sidecar lane entirely.

## 2026-03-26 common request-builder contract checkpoint

- Added and passed `test-prefab-common-request-builder-contract.ps1`.
- `FUN_1449310d0` now has a tighter contract:
  - nullable source guard on `RDX`
  - non-null path duplicates/normalizes the source through `FUN_14466d2a0` twice
  - then finishes through `FUN_144931140` with `R8D = 0`
  - null path falls back through shared string/helper `0x145c563ac -> FUN_14002e8e0`
- `FUN_144931140` repeats that contract at the richer finish layer:
  - nullable source guard
  - two staging string/object builders via `FUN_14002eaf0`
  - intermediate extraction via `FUN_14481e060` and `FUN_142735ef0`
  - secondary normalization via `FUN_144931580`
  - final emission via `FUN_144931460`
  - same null fallback through `FUN_14002e8e0`
- Current best read:
  - the simplest tested headless-native target is still the `FUN_144815870` submit variant that only depends on `FUN_1449310d0`.
  - the missing piece is the minimum non-null source object that makes `FUN_1449310d0 -> FUN_144931140` produce a valid request fragment without needing the richer `FUN_144931270` sidecar lane.
