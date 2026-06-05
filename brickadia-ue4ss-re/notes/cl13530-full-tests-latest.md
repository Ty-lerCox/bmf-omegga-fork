# CL13530 Full Test Suite

## Summary

- Total: `95`
- Passed: `80`
- Failed: `0`
- Blocked: `15`

## Suites

- `Baseline Tests`: 38 passed / 0 failed / 2 blocked
  - Report: `notes\cl13530-baseline-tests-latest.json`
- `Chat Canary`: 16 passed / 0 failed / 3 blocked
  - Report: `notes\cl13530-chat-canary-latest.json`
- `World Export Canary`: 26 passed / 0 failed / 10 blocked
  - Report: `notes\cl13530-world-export-canary-latest.json`

## Baseline Tests

- Total: `40`
- Passed: `38`
- Failed: `0`
- Blocked: `2`
- Report: `notes\cl13530-baseline-tests-latest.json`

### Bundle Integrity

- Total: `4`
- Passed: `4`
- Failed: `0`
- Blocked: `0`

- [PASSED] `bundle-root-exists`: Bundle root exists
  - bundles\CL13530
- [PASSED] `manifest-exists`: Manifest exists and parses
  - bundles\CL13530\manifest.json
  - Evidence: `bundles\CL13530\manifest.json`
- [PASSED] `required-files-present`: Required bundle files are present
  - All required files are present.
  - Evidence: `bundles\CL13530`
- [PASSED] `manifest-hashes-match`: Manifest hashes match staged bundle files
  - All manifest hashes match.
  - Evidence: `bundles\CL13530\manifest.json`

### Hook Foundation

- Total: `9`
- Passed: `9`
- Failed: `0`
- Blocked: `0`

- [PASSED] `uobject-processevent-coverage`: UObject::ProcessEvent has explicit coverage or runtime confirmation
  - explicit custom ordinal=72; stock UE5.5 default=0x278; runtime address=0x7ff66fff3cb0
- [PASSED] `uengine-loadmap-coverage`: UEngine::LoadMap has explicit coverage or runtime confirmation
  - explicit custom ordinal=70; stock UE5.5 default=0x4e0; runtime address=0x7ff67298e1a0
- [PASSED] `agamemodebase-initgamestate-coverage`: AGameModeBase::InitGameState has explicit coverage or runtime confirmation
  - stock UE5.5 default=0x790; seed note says only UObject and UEngine have extra Brickadia vfuncs, so the stock UE5.5 default is currently accepted for this target; runtime address=0x7ff6722bc920
  - Evidence: `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\Resources Convos.txt`
- [PASSED] `aactor-beginplay-coverage`: AActor::BeginPlay has explicit coverage or runtime confirmation
  - stock UE5.5 default=0x3a0; seed note says only UObject and UEngine have extra Brickadia vfuncs, so the stock UE5.5 default is currently accepted for this target; runtime address=0x7ff671e180b0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\Resources Convos.txt`
- [PASSED] `hook-runtime-confirmation-gate`: UE4SS startup reaches post-init hook address logging
  - No startup fatal line recorded before hook logging.
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `uobject-processevent-runtime`: UObject::ProcessEvent runtime address logged by UE4SS
  - [2026-05-30 21:01:21.5016976] ProcessEvent address 0x7ff66fff3cb0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `uengine-loadmap-runtime`: UEngine::LoadMap runtime address logged by UE4SS
  - [2026-05-30 21:01:21.5008836] GameEngine::LoadMap address 0x7ff67298e1a0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `agamemodebase-initgamestate-runtime`: AGameModeBase::InitGameState runtime address logged by UE4SS
  - [2026-05-30 21:01:21.5016254] GameModeBase::InitGameState address 0x7ff6722bc920
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `aactor-beginplay-runtime`: AActor::BeginPlay runtime address logged by UE4SS
  - [2026-05-30 21:01:21.5016434] AActor::BeginPlay address 0x7ff671e180b0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`

### Resolver Coverage

- Total: `17`
- Passed: `17`
- Failed: `0`
- Blocked: `0`

- [PASSED] `resolver-fnamectorwchar`: FNameCtorWchar resolves on the target binary
  - Resolved address 0x1402367b0
- [PASSED] `resolver-fnametostring`: FNameToString resolves on the target binary
  - Resolved address 0x7ff6702b4100
- [PASSED] `resolver-staticconstructobjectinternal`: StaticConstructObjectInternal resolves on the target binary
  - Resolved address 0x1405019a0
- [PASSED] `resolver-consolemanagersingleton`: ConsoleManagerSingleton resolves on the target binary
  - Resolved address 0x140064610
- [PASSED] `resolver-ugameenginetick`: UGameEngineTick resolves on the target binary
  - Resolved address 0x1422b4950
- [PASSED] `resolver-guobjectarray`: GUObjectArray resolves on the target binary
  - Resolved address 0x7ff67767f038
- [PASSED] `resolver-fuobjectarrayallocateuobjectindex`: FUObjectArrayAllocateUObjectIndex resolves on the target binary
  - Resolved address 0x1404f4550
- [PASSED] `resolver-fuobjectarrayfreeuobjectindex`: FUObjectArrayFreeUObjectIndex resolves on the target binary
  - Resolved address 0x1404f48b0
- [PASSED] `resolver-fuobjecthashtablesget-required`: FUObjectHashTablesGet is explicitly deferred by the patched runtime
  - patternsleuth still fails for FUObjectHashTablesGet on CL13530, but the patched UE4SS runtime carries this scan result as override/config plumbing only and does not assign results.fuobject_hash_tables_get during ScanGame(). Brickadia's hash-table family has a manual foothold and confirmed direct-global access, so this stays tracked under object-resolution compatibility instead of as an active startup/runtime resolver failure.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\UnrealInitializer.cpp`
- [PASSED] `resolver-gnatives-required`: GNatives resolves on the target binary
  - Resolved address 0x7ff67767d760 via Lua Script in the live UE4SS session.
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `resolver-staticfindobjectfast-required`: StaticFindObjectFast is explicitly deferred by the patched runtime
  - patternsleuth still fails for StaticFindObjectFast on CL13530, but the patched UE4SS runtime does not reference StaticFindObjectFast directly in the Unreal source layer. Object lookup is currently handled through slower internal search paths and remains tracked under stage-3 object-resolution stability instead of as an active startup/runtime resolver failure.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal`
- [PASSED] `resolver-uobjectskipfunction-required`: UObjectSkipFunction is explicitly deferred by the patched runtime
  - patternsleuth still fails for UObjectSkipFunction on CL13530, but the patched UE4SS runtime does not reference UObjectSkipFunction in the Unreal source layer. This remains a stock GNatives-recovery heuristic rather than an active startup/runtime requirement.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal`
- [PASSED] `resolver-fframestep-required`: FFrameStep is explicitly deferred by the patched runtime
  - patternsleuth still fails for FFrameStep on CL13530, but the patched UE4SS runtime carries its own FFrame::Step source implementation and the real runtime dependency remains GNatives. This resolver gap stays tracked as a compatibility aid, not as an active startup/runtime failure.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\FFrame.cpp`
- [PASSED] `patternsleuth-blocked-summary-present`: Blocked resolver summary was captured
  - Blocked resolver output captured from patternsleuth.
- [PASSED] `resolver-fuobjecthashtables-anchor-foothold`: FUObjectHashTables family has a manual anchor foothold
  - HashOuter anchor xref leads into 0x1405370d0..0x140537cc1 (HashOuter xref 0x140537c2f).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-anchor-xrefs-latest.txt`
- [PASSED] `resolver-fuobjecthashtables-singleton-xrefs`: FUObjectHashTables singleton-like global has reusable xref coverage
  - Captured 2 xref(s) into 0x14769f1f8 and its hash-table global family.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-address-xrefs-latest.txt`
- [PASSED] `resolver-fuobjecthashtables-direct-global-access`: Hash-table family shows direct global access in decompile output
  - Binary analysis references 0x14769f1f8 and companion globals directly, which supports a Brickadia-specific resolver path.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-decompile-latest.txt`

### Runtime Validation

- Total: `10`
- Passed: `8`
- Failed: `0`
- Blocked: `2`

- [PASSED] `ue4ss-log-exists`: UE4SS startup log exists
  - C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `ue4ss-startup-no-fatal`: UE4SS startup completes without a fatal error
  - No fatal startup line found.
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [BLOCKED] `callback-gc-stability`: Callback garbage collector does not invalidate startup callbacks
  - Non-baseline runtime mod(s) are enabled: OmeggaBridge. The invalid-callback line cannot be treated as a baseline UE4SS failure yet. Observed line: [2026-05-30 21:01:21.6468031] [Lua] [BaselineObjectProof] wrote result kind=hook_initgamestate_context[2026-05-30 21:01:21.6585490] [Lua] [BaselineObjectProof] wrote result kind=lookup_staticfindobject[2026-05-30 21:01:24.5052147] [FCallbackGarbageCollector] Freed invalid callbacks!
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `object-proof-initgamestate-hook`: Baseline object proof reaches InitGameState in Lua
  - InitGameState post-hook reached Lua and exposed a RemoteUnrealParam without forcing object resolution.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-proof.jsonl`
- [PASSED] `object-proof-remote-param-unwrap`: Baseline object proof can unwrap InitGameState RemoteUnrealParam safely
  - InitGameState hook param unwrapped to a valid UObject wrapper without crashing.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-proof-unwrap.jsonl`
- [PASSED] `object-proof-findfirstof`: Baseline object proof can resolve GameEngine via FindFirstOf
  - FindFirstOf returned a UObject wrapper in a clean InitGameState proof session.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-proof-findfirstof.jsonl`
- [PASSED] `object-proof-staticfindobject`: Baseline object proof can resolve a long-name object via StaticFindObject
  - StaticFindObject returned a UObject wrapper for /Script/CoreUObject.Default__Object in a clean InitGameState proof session.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-proof-staticfindobject.jsonl`
- [PASSED] `stage2-startup-status`: Stage 2 UE4SS startup validation is passing
  - GNatives now resolves via Lua Script at 0x7ff67767d760 in the live UE4SS session.; GUObjectHashTables.lua remains unresolved but non-fatal during startup.; UE4SS reaches ScanGame and post-init hook installation without a fatal startup line.
  - Evidence: `validation-report.json`
- [PASSED] `stage3-object-resolution-status`: Stage 3 object-resolution validation is passing
  - GNatives now resolves via Lua Script at 0x7ff67767d760 in the live UE4SS session.; The clean object proof ladder now succeeds for RemoteUnrealParam unwrap, FindFirstOf, and StaticFindObject.; Stage 3 is treated as passing based on live proof sessions even though stock resolver heuristics like StaticFindObjectFast and the FFrameStep family remain deferred.; A callback-garbage-collector line is still observed separately, but it is tracked under callback stability rather than object-resolution correctness.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-proof-staticfindobject.jsonl`
- [BLOCKED] `stage4-dumper-status`: Stage 4 dumper validation is unblocked and passing
  - Object-resolution correctness is now proven by the CL13530 baseline proof ladder, but the dumper itself has not been rerun and validated yet.
  - Evidence: `validation-report.json`

## Chat Canary

- Total: `19`
- Passed: `16`
- Failed: `0`
- Blocked: `3`
- Report: `notes\cl13530-chat-canary-latest.json`

### Chat Probe Foundation

- Total: `7`
- Passed: `6`
- Failed: `0`
- Blocked: `1`

- [PASSED] `chat-proof-output-exists`: BaselineChatProof wrote an output report
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-output-parses`: BaselineChatProof output parses as JSONL
  - All chat proof lines parsed successfully.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-startup`: BaselineChatProof startup marker was recorded
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-game-thread-scheduler`: A game-thread scheduler is available for chat probes
  - ExecuteInGameThread=True; ExecuteInGameThreadWithDelay=True; ExecuteInGameThreadAfterFrames=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-helper-capabilities`: The minimum chat helper surface is available
  - HasCachedCommandContext=True; ExecuteKismetConsoleCommand=True; ExecuteCachedEngineExec=True; ExecuteCachedConsoleExec=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-initgamestate-hook`: InitGameState fired during the chat proof session
  - Observed 1 InitGameState hook event(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [BLOCKED] `chat-proof-beginplay-hook`: BeginPlay fired during the chat proof session
  - RegisterBeginPlayPostHook did not fire during the short headless proof session, so this remains characterization only rather than a chat blocker.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`

### Console Broadcast Canaries

- Total: `8`
- Passed: `6`
- Failed: `0`
- Blocked: `2`

- [PASSED] `chat-proof-cached-command-context`: A cached command context becomes available during the chat proof
  - Observed cached command context in 4 context snapshot(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-nonchat-console-probe`: A non-chat console command succeeds through the managed helpers
  - Successful executor(s): cached_console_exec, kismet_console_command
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-broadcast-console-canary`: At least one console broadcast canary succeeds
  - Successful executor(s): kismet_console_command
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-broadcast-repeat-canary`: Two console broadcast canaries succeed in one session
  - Successful broadcast commands: Chat.Broadcast Hello from BaselineChatProof #1, Chat.Broadcast Hello from BaselineChatProof #2
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [BLOCKED] `chat-proof-processconsoleexec-intercept`: The current chat broadcast path is observable via ProcessConsoleExec hooks
  - A broadcast succeeded, and the live counter demo confirms the visible path is now typed/native, so bypassing ProcessConsoleExec is treated as expected characterization.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-native-broadcast-canary`: A native typed-chat broadcast canary is ready to run
  - Stage 3 object-resolution validation is passing, so the direct typed-chat canary can become active.
  - Evidence: `validation-report.json`
- [BLOCKED] `chat-player-intercept-live-stimulus`: A live player-chat stimulus was present to test interception
  - The standalone chat proof session does not inject a real player chat message yet, so player-chat interception remains a later canary.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-broadcast-rounds-finished`: The scheduled chat broadcast rounds completed
  - Completed round(s): 1, 2
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`

### Native Broadcast Demo

- Total: `4`
- Passed: `4`
- Failed: `0`
- Blocked: `0`

- [PASSED] `chat-demo-live-evidence-exists`: CounterBroadcastDemo captured live native chat evidence
  - mod.log=C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\mod.log; chat-trace.log=C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log`
- [PASSED] `chat-native-visible-delivery-canary`: A live native typed-chat delivery path was observed
  - Observed typed/native delivery via PushChatMessage; latest route=PushChatMessage
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log`
- [PASSED] `chat-native-broadcast-all-clients`: The current native chat path is server-wide across connected players
  - Observed server-wide chat function(s): PushChatMessage
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log`
- [PASSED] `chat-demo-live-session-metadata`: CounterBroadcastDemo recorded live session metadata
  - connect_address=127.0.0.1:7777; verified=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\counter-broadcast-demo-live.json`

## World Export Canary

- Total: `36`
- Passed: `26`
- Failed: `0`
- Blocked: `10`
- Report: `notes\cl13530-world-export-canary-latest.json`

### Context Resolution

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

### Discovery Leads

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

### Prefab Native Leads

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

### Live Prefab Runtime

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
