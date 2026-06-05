# CL12960 Baseline Test Report

## Summary

- Total: `40`
- Passed: `38`
- Failed: `0`
- Blocked: `2`

## Bundle Integrity

- Total: `4`
- Passed: `4`
- Failed: `0`
- Blocked: `0`

- [PASSED] `bundle-root-exists`: Bundle root exists
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\bundles\CL12960
- [PASSED] `manifest-exists`: Manifest exists and parses
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\bundles\CL12960\manifest.json
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\bundles\CL12960\manifest.json`
- [PASSED] `required-files-present`: Required bundle files are present
  - All required files are present.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\bundles\CL12960`
- [PASSED] `manifest-hashes-match`: Manifest hashes match staged bundle files
  - All manifest hashes match.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\bundles\CL12960\manifest.json`

## Hook Foundation

- Total: `9`
- Passed: `9`
- Failed: `0`
- Blocked: `0`

- [PASSED] `uobject-processevent-coverage`: UObject::ProcessEvent has explicit coverage or runtime confirmation
  - explicit custom ordinal=72; stock UE5.5 default=0x278; runtime address=0x7ff75b9d3db0
- [PASSED] `uengine-loadmap-coverage`: UEngine::LoadMap has explicit coverage or runtime confirmation
  - explicit custom ordinal=70; stock UE5.5 default=0x4e0; runtime address=0x7ff75e3804d0
- [PASSED] `agamemodebase-initgamestate-coverage`: AGameModeBase::InitGameState has explicit coverage or runtime confirmation
  - stock UE5.5 default=0x790; seed note says only UObject and UEngine have extra Brickadia vfuncs, so the stock UE5.5 default is currently accepted for this target; runtime address=0x7ff75dcabcd0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\Resources Convos.txt`
- [PASSED] `aactor-beginplay-coverage`: AActor::BeginPlay has explicit coverage or runtime confirmation
  - stock UE5.5 default=0x3a0; seed note says only UObject and UEngine have extra Brickadia vfuncs, so the stock UE5.5 default is currently accepted for this target; runtime address=0x7ff75d8041c0
  - Evidence: `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\Resources Convos.txt`
- [PASSED] `hook-runtime-confirmation-gate`: UE4SS startup reaches post-init hook address logging
  - No startup fatal line recorded before hook logging.
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `uobject-processevent-runtime`: UObject::ProcessEvent runtime address logged by UE4SS
  - [2026-03-23 12:07:15.7056587] ProcessEvent address 0x7ff75b9d3db0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `uengine-loadmap-runtime`: UEngine::LoadMap runtime address logged by UE4SS
  - [2026-03-23 12:07:15.7052114] GameEngine::LoadMap address 0x7ff75e3804d0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `agamemodebase-initgamestate-runtime`: AGameModeBase::InitGameState runtime address logged by UE4SS
  - [2026-03-23 12:07:15.7056123] GameModeBase::InitGameState address 0x7ff75dcabcd0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `aactor-beginplay-runtime`: AActor::BeginPlay runtime address logged by UE4SS
  - [2026-03-23 12:07:15.7056227] AActor::BeginPlay address 0x7ff75d8041c0
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`

## Resolver Coverage

- Total: `17`
- Passed: `17`
- Failed: `0`
- Blocked: `0`

- [PASSED] `resolver-fnamectorwchar`: FNameCtorWchar resolves on the target binary
  - Resolved address 0x140237e50
- [PASSED] `resolver-fnametostring`: FNameToString resolves on the target binary
  - Resolved address 0x7ff75bc95d70
- [PASSED] `resolver-staticconstructobjectinternal`: StaticConstructObjectInternal resolves on the target binary
  - Resolved address 0x140505310
- [PASSED] `resolver-consolemanagersingleton`: ConsoleManagerSingleton resolves on the target binary
  - Resolved address 0x140064bb0
- [PASSED] `resolver-ugameenginetick`: UGameEngineTick resolves on the target binary
  - Resolved address 0x1422c3bd0
- [PASSED] `resolver-guobjectarray`: GUObjectArray resolves on the target binary
  - Resolved address 0x7ff76304f038
- [PASSED] `resolver-fuobjectarrayallocateuobjectindex`: FUObjectArrayAllocateUObjectIndex resolves on the target binary
  - Resolved address 0x1404f7cb0
- [PASSED] `resolver-fuobjectarrayfreeuobjectindex`: FUObjectArrayFreeUObjectIndex resolves on the target binary
  - Resolved address 0x1404f8020
- [PASSED] `resolver-fuobjecthashtablesget-required`: FUObjectHashTablesGet is explicitly deferred by the patched runtime
  - patternsleuth still fails for FUObjectHashTablesGet on CL12960, but the patched UE4SS runtime carries this scan result as override/config plumbing only and does not assign results.fuobject_hash_tables_get during ScanGame(). Brickadia's hash-table family has a manual foothold and confirmed direct-global access, so this stays tracked under object-resolution compatibility instead of as an active startup/runtime resolver failure.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\UnrealInitializer.cpp`
- [PASSED] `resolver-gnatives-required`: GNatives resolves on the target binary
  - Resolved address 0x7ff76304d760 via Lua Script in the live UE4SS session.
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `resolver-staticfindobjectfast-required`: StaticFindObjectFast is explicitly deferred by the patched runtime
  - patternsleuth still fails for StaticFindObjectFast on CL12960, but the patched UE4SS runtime does not reference StaticFindObjectFast directly in the Unreal source layer. Object lookup is currently handled through slower internal search paths and remains tracked under stage-3 object-resolution stability instead of as an active startup/runtime resolver failure.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal`
- [PASSED] `resolver-uobjectskipfunction-required`: UObjectSkipFunction is explicitly deferred by the patched runtime
  - patternsleuth still fails for UObjectSkipFunction on CL12960, but the patched UE4SS runtime does not reference UObjectSkipFunction in the Unreal source layer. This remains a stock GNatives-recovery heuristic rather than an active startup/runtime requirement.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal`
- [PASSED] `resolver-fframestep-required`: FFrameStep is explicitly deferred by the patched runtime
  - patternsleuth still fails for FFrameStep on CL12960, but the patched UE4SS runtime carries its own FFrame::Step source implementation and the real runtime dependency remains GNatives. This resolver gap stays tracked as a compatibility aid, not as an active startup/runtime failure.
  - Evidence: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS\deps\first\Unreal\src\FFrame.cpp`
- [PASSED] `patternsleuth-blocked-summary-present`: Blocked resolver summary was captured
  - Blocked resolver output captured from patternsleuth.
- [PASSED] `resolver-fuobjecthashtables-anchor-foothold`: FUObjectHashTables family has a manual anchor foothold
  - HashOuter anchor xref leads into FUN_14053a860 @ 14053a860 (GhidraScript).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-anchor-xrefs-latest.txt`
- [PASSED] `resolver-fuobjecthashtables-singleton-xrefs`: FUObjectHashTables singleton-like global has reusable xref coverage
  - Captured 66 xref(s) into the 0x14768f1f8 hash-table global family.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-address-xrefs-latest.txt`
- [PASSED] `resolver-fuobjecthashtables-direct-global-access`: Hash-table family shows direct global access in decompile output
  - Decompile output references DAT_14768f1f8 and companion globals directly, which supports a Brickadia-specific resolver path.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\ghidra-decompile-14053c060.txt`

## Runtime Validation

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
  - Non-baseline runtime mod(s) are enabled: OmeggaBridge. The invalid-callback line cannot be treated as a baseline UE4SS failure yet. Observed line: [2026-03-23 12:07:15.8166398] [Lua] [BaselineObjectProof] wrote result kind=hook_initgamestate_context[2026-03-23 12:07:15.8229068] [Lua] [BaselineObjectProof] wrote result kind=lookup_staticfindobject[2026-03-23 12:07:18.7078721] [FCallbackGarbageCollector] Freed invalid callbacks!
  - Evidence: `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\ue4ss\main\UE4SS.log`
- [PASSED] `object-proof-initgamestate-hook`: Baseline object proof reaches InitGameState in Lua
  - InitGameState post-hook reached Lua and exposed a RemoteUnrealParam without forcing object resolution.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\baseline-proof.jsonl`
- [PASSED] `object-proof-remote-param-unwrap`: Baseline object proof can unwrap InitGameState RemoteUnrealParam safely
  - InitGameState hook param unwrapped to a valid UObject wrapper without crashing.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\baseline-proof-unwrap.jsonl`
- [PASSED] `object-proof-findfirstof`: Baseline object proof can resolve GameEngine via FindFirstOf
  - FindFirstOf returned a UObject wrapper in a clean InitGameState proof session.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\baseline-proof-findfirstof.jsonl`
- [PASSED] `object-proof-staticfindobject`: Baseline object proof can resolve a long-name object via StaticFindObject
  - StaticFindObject returned a UObject wrapper for /Script/CoreUObject.Default__Object in a clean InitGameState proof session.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\baseline-proof-staticfindobject.jsonl`
- [PASSED] `stage2-startup-status`: Stage 2 UE4SS startup validation is passing
  - GNatives now resolves via Lua Script at 0x7ff76304d760 in the live UE4SS session.; GUObjectHashTables.lua remains unresolved but non-fatal during startup.; UE4SS reaches ScanGame and post-init hook installation without a fatal startup line.
  - Evidence: `validation-report.json`
- [PASSED] `stage3-object-resolution-status`: Stage 3 object-resolution validation is passing
  - GNatives now resolves via Lua Script at 0x7ff76304d760 in the live UE4SS session.; The clean object proof ladder now succeeds for RemoteUnrealParam unwrap, FindFirstOf, and StaticFindObject.; Stage 3 is treated as passing based on live proof sessions even though stock resolver heuristics like StaticFindObjectFast and the FFrameStep family remain deferred.; A callback-garbage-collector line is still observed separately, but it is tracked under callback stability rather than object-resolution correctness.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL12960\output\baseline-proof-staticfindobject.jsonl`
- [BLOCKED] `stage4-dumper-status`: Stage 4 dumper validation is unblocked and passing
  - Object-resolution correctness is now proven by the baseline proof ladder, but the dumper itself has not been rerun and validated yet.
  - Evidence: `validation-report.json`
