# CL13530 World Export Canary Report

## Summary

- Total: `36`
- Passed: `26`
- Failed: `0`
- Blocked: `10`

## Context Resolution

- Total: `12`
- Passed: `11`
- Failed: `0`
- Blocked: `1`

- [PASSED] `world-export-output-exists`: WorldExportContextProof wrote an output report
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-output-parses`: WorldExportContextProof output parses as JSONL
  - All world-export proof lines parsed successfully.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-startup`: WorldExportContextProof startup marker was recorded
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-scheduler`: A delayed game-thread scheduler is available for the export canary
  - ExecuteInGameThreadWithDelay=True; ExecuteInGameThreadAfterFrames=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-initgamestate-hook`: InitGameState fired during the world-export proof session
  - Observed RegisterInitGameStatePostHook.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-world-resolved`: The live UWorld can be resolved
  -  .@0x23C8AA1C800
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-persistent_level-resolved`: The persistent level can be resolved
  -  .:@0x23C8B6BED80
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-game_mode-resolved`: The live game mode can be resolved
  -  .:.@0x23C89C46A00
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-game_state-resolved`: The live game state can be resolved
  -  .:.@0x23C89495000
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-game_session-resolved`: The live game session can be resolved
  -  .:.@0x23C89C46680
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-game_instance-resolved`: The live game instance can be resolved
  -  .:@0x23C8A917200
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [BLOCKED] `world-export-runtime-brick-count`: A runtime brick count is readable from the live server state
  - No NumBricks/BrickCount property was readable in the current proof session.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`

## Discovery Leads

- Total: `6`
- Passed: `5`
- Failed: `0`
- Blocked: `1`

- [PASSED] `world-export-property-keyword-scan`: Keyword property scans ran against the core world objects
  - Observed 8 property keyword scan record(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-function-keyword-scan`: Keyword function scans ran against the core world objects
  - Observed 8 function keyword scan record(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-named-property-probe`: Explicit build/export property probes ran against the core world objects
  - Observed 8 named property probe record(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [BLOCKED] `world-export-property-keyword-leads`: The core world objects expose build/export-related leads
  - No property, function, or named-property build/export leads were found on the scanned world objects yet. Closest runtime candidates: BRChatCommandWorldSubsystem=1 (FindFirstOf), BrickGridActor=1 (FindFirstOf), BrickGridComponent=1 (FindFirstOf), BRWorldManager=1 (FindFirstOf), BP_BrickGrid_C=0 (FindFirstOf), BP_ChatCommandWorldSubsystem_C=0 (FindFirstOf).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-candidate-class-scan`: Candidate runtime classes were scanned with FindAllOf
  - Observed 54 candidate class scan record(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-live-candidates`: At least one live runtime candidate relevant to export work was found
  - Live candidates: BRChatCommandWorldSubsystem=1 (FindFirstOf), BrickGridActor=1 (FindFirstOf), BrickGridComponent=1 (FindFirstOf), BRWorldManager=1 (FindFirstOf), BP_BrickGrid_C=0 (FindFirstOf), BP_ChatCommandWorldSubsystem_C=0 (FindFirstOf), BRBundleArchive=0 (FindFirstOf), BRBundleTransferComponent=0 (FindFirstOf), BRGizmoManagerComponent=0 (FindFirstOf), BrickBuildingTemplate=0 (FindFirstOf)
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`

## Prefab Native Leads

- Total: `6`
- Passed: `5`
- Failed: `0`
- Blocked: `1`

- [PASSED] `world-export-brworldmanager-live`: The live BRWorldManager object resolves during the proof session
  - BRWorldManager=1
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-runtime-grid-surface`: The runtime brick-grid surface is present without using commands
  - BrickGridActor=1, BrickGridComponent=1, BrickGridDynamicActor=0, Entity_DynamicBrickGrid=0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [BLOCKED] `world-export-selector-surface`: Selector/template runtime objects are discoverable when a player selection exists
  - Tool_Selector_C=0, BrickBuildingTemplate=0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\world-export-context-proof.jsonl`
- [PASSED] `world-export-prefab-binary-leads`: The server binary exposes prefab/world-manager native leads for future call-by-name work
  - BRWorldManager, BRWorldSerializer, BrickPrefabs, BRBundleArchive, PrefabArchive, PendingWorldBundle, CachedWorldBundle, SavedWorldBundle, RequestLoadWorldAdditive, ClientLoadWorldAccepted, ClientLoadWorldRejected, ServerUploadPrefab, ClientUploadPrefab, BRLoadWorldAdditiveParams, ServerPlaceCurrentPrefab, ServerPastePrefab, PrefabCaptureBricks, PrefabCaptureComponents, PrefabCaptureEntities, PrefabCaptureWires, ApplyPrefabState
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe`
- [PASSED] `world-export-prefab-native-call-surface`: The binary exposes candidate native prefab call names
  - ServerPlaceCurrentPrefab, ServerPastePrefab, PrefabCaptureBricks, PrefabCaptureComponents, PrefabCaptureEntities, PrefabCaptureWires, ApplyPrefabState
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe`
- [PASSED] `world-export-prefab-replay-binary-surface`: The binary exposes candidate additive-load and prefab replay method names
  - RequestLoadWorldAdditive, ClientLoadWorldAccepted, ClientLoadWorldRejected, ServerUploadPrefab, ClientUploadPrefab, PrefabArchive, BRLoadWorldAdditiveParams
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe`

## Live Prefab Runtime

- Total: `12`
- Passed: `5`
- Failed: `0`
- Blocked: `7`

- [PASSED] `world-export-live-prefab-sampler-output`: The live prefab sampler produced a parseable snapshot
  - Snapshot updated_at=2026-03-25T21:45:43Z; sampler_started_at=2026-03-25T17:39:13.2390261-04:00
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [BLOCKED] `world-export-live-prefab-additive-load-trace`: The server log shows the additive prefab load path end-to-end
  - The expected additive prefab load sequence was not fully observed in the live server log.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Logs\Brickadia.log`
- [BLOCKED] `world-export-live-prefab-runtime-surface`: Live runtime prefab/archive objects appear after a player-driven load
  - BRWorldManager=1, BRBundleArchive=0, BrickGridDynamicActor=0, BRBundleTransferComponent=0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [PASSED] `world-export-live-replay-surface-capture`: A safe replay-surface capture is recorded when prefab runtime counts change
  - selected_phase=grid_component_window; latest_phase=world_manager_bundle_window; triggers=BrickGridActor 0->1, BrickGridComponent 0->1; classes=BRWorldManager props=9 aliased=0, BrickGridActor props=5 aliased=0, BrickGridComponent props=7 aliased=1; native=BRBundleArchive->CountBricksAndComponents success=False, BRBundleArchive->GetBrickCount success=False, BRBundleTransferComponent->GetCurrentBundleState success=False, BRBundleTransferComponent->GetPendingWorldBundle success=False, BRWorldManager->GetCurrentBundleState success=False, BRWorldManager->GetGlobalBrickGrid success=False
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [PASSED] `world-export-live-replay-capture-diff`: Replay-surface history can be diffed across multiple prefab loads
  - captures=6; selected_phase=grid_component_window; latest_phase=world_manager_bundle_window; selected_property_aliases=none; repeated_property_aliases=none_yet; repeated_alias_edges=0; stable_replay_properties=0; churning_replay_properties=9
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\history.jsonl`
- [PASSED] `world-export-live-native-call-probes`: Live native call probes ran against the bundle/world-manager replay surface
  - BrickGridActor->GetBrickGrid success=True interpretation=placeholder_null_wrapper; BrickGridComponent->GetBrickCount success=True; BP_ToolPreviewActor_C->GetPlaceable success=False reason=target object unavailable; BRBundleArchive->CountBricksAndComponents success=False reason=target object unavailable; BRBundleArchive->GetBrickCount success=False reason=target object unavailable; BRBundleTransferComponent->GetCurrentBundleState success=False reason=target object unavailable; BRBundleTransferComponent->GetPendingWorldBundle success=False reason=target object unavailable; BRWorldManager->GetCurrentBundleState success=False reason=native call returned false; BRWorldManager->GetGlobalBrickGrid success=False reason=native call returned false; BRWorldManager->GetGlobalBrickGridActor success=False reason=native call returned false; BRWorldManager->GetPendingWorldBundle success=False reason=native call returned false; BrickGridActor->GetBrickCount success=False reason=native call returned false; BrickGridComponent->GetBrickGrid success=False reason=native call returned false; BrickGridDynamicActor->GetBrickCount success=False reason=target object unavailable; BrickGridDynamicActor->GetBrickGrid success=False reason=target object unavailable; Tool_Selector_C->GetCurrentSelectionState success=False reason=target object unavailable; Tool_Selector_C->GetSelectionLayers success=False reason=target object unavailable; Tool_Selector_C->HasSelection success=False reason=target object unavailable; Tool_Selector_C->HasSelectionBox success=False reason=target object unavailable
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [BLOCKED] `world-export-live-grid-getter-decoder-status`: Live GetBrickGrid returns a decoded grid object instead of a placeholder wrapper
  - BrickGridActor->GetBrickGrid success=True interpretation=placeholder_null_wrapper; BrickGridComponent->GetBrickGrid success=False interpretation=unknown reason=native call returned false; BrickGridDynamicActor->GetBrickGrid success=False interpretation=unknown reason=target object unavailable
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [BLOCKED] `world-export-live-replay-native-surface`: Live additive-load replay candidates are being probed on the runtime bundle surface
  - Unsafe live replay calls are intentionally disabled in the sampler right now because zero-arg probing of upload/accept methods can trip PendingWorldUpload assertions. The replay path is still tracked as a binary/runtime lead, just not invoked blindly.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [PASSED] `world-export-live-surface-scan-status`: Live prefab classes were surface-scanned for reflected property/function leads
  - BRWorldManager property_matches=0 function_matches=0 property_error=...4\ue4ss\main\Mods\WorldStateLiveSampler\Scripts\main.lua:1290: [Lua::call_function] lua_pcall returned LUA_ERRRUN => attempt to call a nil value function_error=...4\ue4ss\main\Mods\WorldStateLiveSampler\Scripts\main.lua:1367: [Lua::call_function] lua_pcall returned LUA_ERRRUN => attempt to call a nil value; BRBundleArchive property_matches=0 function_matches=0; BrickGridDynamicActor property_matches=0 function_matches=0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [BLOCKED] `world-export-live-prefab-property-surface`: The live prefab/archive objects expose the expected chunk and prefab property names
  - The live prefab/archive property probes did not expose the expected chunk/prefab field names yet.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [BLOCKED] `world-export-live-prefab-property-decoder-status`: Expected live prefab property values decode beyond observe-only userdata handles
  - No expected prefab property hits were available to classify yet.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
- [BLOCKED] `world-export-headless-prefab-replay-surface`: The server-side runtime surface for future headless prefab replay is present
  - The runtime surfaces needed for a future headless replay target are not all present in this live capture yet.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json`
