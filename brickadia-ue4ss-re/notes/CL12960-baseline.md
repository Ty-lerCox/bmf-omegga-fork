# CL12960 Baseline Notes

## Target

- Brickadia build: `Brickadia EA2 (PC-Shipping-CL12960)`
- UE baseline: `5.5`
- UE4SS build: `3.0.1-940-g01e0a584`

## Confirmed Inputs

- Seed `VTableLayout.ini` copied from the Discord dump
- Current staged signatures copied from Omegga's Windows UE4SS template
- Current live binary:
  - `C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe`

## Current Findings

- The Windows object/control blocker is below Omegga.
- UE4SS can start, but object-param and lookup-heavy flows still fail on `CL12960`.
- Hook foundation is now both statically covered and runtime-confirmed in the live log:
  - `UObject::ProcessEvent` has an explicit Brickadia custom-layout entry in `VTableLayout.ini` at ordinal `72`
  - `UEngine::LoadMap` has an explicit Brickadia custom-layout entry in `VTableLayout.ini` at ordinal `70`
  - `AGameModeBase::InitGameState` is not explicitly overridden in Brickadia's custom layout, but the Discord seed note says Brickadia only adds extra vfuncs in `UObject` and `UEngine`, so the stock UE `5.5` generated offset `0x790` is currently accepted as static coverage
  - `AActor::BeginPlay` is not explicitly overridden in Brickadia's custom layout, but the same seed note currently supports accepting the stock UE `5.5` generated offset `0x3a0` as static coverage
  - `ProcessEvent address 0x7ff6f61d3db0`
  - `GameEngine::LoadMap address 0x7ff6f8b804d0`
  - `GameModeBase::InitGameState address 0x7ff6f84abcd0`
  - `AActor::BeginPlay address 0x7ff6f80041c0`
  - startup no longer hard-stops on `GUObjectHashTables.lua` / `GNatives.lua` returning `nil`
  - the staged Lua overrides now degrade those unresolved scans through the normal scan path instead of throwing an early nil-return fatal startup exception
  - the old `FName_Constructor.lua` override is intentionally disabled for `CL12960` because it destabilizes the second-pass scan before the real unresolved blockers are surfaced
  - the latest `FCallbackGarbageCollector` invalid-callback line came from a runtime with `OmeggaBridge` enabled, so it is not yet treated as a clean baseline-only failure
- The current unresolved prerequisites are:
  - `GNatives`
  - `FUObjectHashTables::Get()`
  - Brickadia's `StaticFindObject` / object lookup path used by object marshaling
- Current confirmed resolver addresses on `CL12960`:
  - `FName::FName(wchar_t*) = 0x140237e50`
  - `FName::ToString = 0x1402d5d70`
  - `StaticConstructObject_Internal = 0x140505310`
  - `ConsoleManagerSingleton = 0x140064bb0`
  - `UGameEngine::Tick = 0x1422c3bd0`
  - `GUObjectArray = 0x14768f038`
  - `FUObjectArray::AllocateUObjectIndex = 0x1404f7cb0`
  - `FUObjectArray::FreeUObjectIndex = 0x1404f8020`
- `FName::FName(wchar_t*)` should stay on the `patternsleuth` path for `CL12960`.
  - The old `FName_Constructor.lua` override destabilizes the second-pass scan.
  - Disabling that override leaves `FNameCtorWchar` resolved correctly and exposes the real remaining blockers: `GNatives` and `FUObjectHashTables::Get()`.
- Resolver families that currently fail outright on this build:
  - `FUObjectHashTablesGet`
  - `StaticFindObjectFast`
  - `GNatives`
  - `UObjectSkipFunction`
  - `GNativesViaSkipFunction`
  - `GNativesPatterns`
  - `FFrameStep`
  - `FFrameStepExplicitProperty`
  - `FFrameStepViaExec`
- Current UTF-16 anchors in the live binary:
  - `StaticFindObjectFast = 0x145d372c0`
  - `FUObjectHashTables = 0x145d3eeae`
  - `HashOuter = 0x145d3ed64`
- Current Ghidra foothold from those anchors:
  - `HashOuter` currently xrefs into `FUN_14053a860`
  - decompiling `FUN_14053a860` shows direct access to the Brickadia hash-table globals around `DAT_14768f1f8`, `DAT_14768f220`, and related buckets
  - this suggests Brickadia may not expose the stock-style standalone `FUObjectHashTables::Get()` shape that patternsleuth expects, so the next pass should validate whether we need a Brickadia-specific resolver strategy instead of just a missing stock pattern
- Stock resolver anchor strings missing from the live binary:
  - the longer `StaticFindObjectFast` warning string used by patternsleuth is absent on `CL12960`
  - the longer `FUObjectHashTables` statistics string used by patternsleuth is absent on `CL12960`
- Old PDB public symbol hints recovered so far:
  - `StaticFindObjectFastSafe`
  - `StaticFindObjectChecked`
  - `StaticFindObjectSafe`
  - `FUObjectHashTables::~FUObjectHashTables`
  - `UObject::ProcessConsoleExec`

## Crash Pattern

The failure path seen during live probing runs is consistent with object-resolution instability:

- `RemoteUnrealParam`
- `UObject::GetFullName()`
- `StaticFindObject_InternalSlow()`
- `FName::ToString()`

This means the remaining work is primarily compatibility-pack and object-layer RE, not Omegga bridge routing.

## Latest Runtime Progress

- The baseline test scoreboard is now expected to improve once the runtime report is refreshed with the cleaned startup classification.
- `hook-runtime-confirmation-gate` now passes.
- `ue4ss-startup-no-fatal` now passes.
- `stage2-startup-status` now tracks startup health only; unresolved core resolvers stay in `Resolver Coverage`.
- The four core runtime hook-address checks now pass.
- The next concrete resolver focus is `FUObjectHashTables::Get()`.
- The next live startup stability check should be rerun with `BaselineObjectProof` or no product mod enabled.

## Implemented RE Artifacts

- Repeatable evidence collector:
  - `scripts/collect-cl12960-evidence.py`
- Targeted Ghidra helpers for anchor/xref work:
  - `scripts/run-ghidra-anchor-xrefs.ps1`
  - `scripts/run-ghidra-function-calls.ps1`
  - `scripts/run-ghidra-decompile.ps1`
- Standalone proof mod scaffold:
  - `probes/CL12960/BaselineObjectProof`
- Proof-mod deployment helper:
  - `scripts/deploy-proof-mod.ps1`
- Latest captured evidence snapshot:
  - `notes/cl12960-evidence-latest.json`

## Immediate Next Manual RE Tasks

1. Recover `FUObjectHashTables::Get()` from the hash-table family using the current `FUObjectHashTables` / `HashOuter` anchors and old destructor hint.
2. Recover `GNatives` by following the script VM dispatch path rather than the failed stock patterns.
3. Re-run `omegga ue4ss validate`.
4. Only after `GNatives` and `FUObjectHashTables::Get()` stop failing, deploy `BaselineObjectProof` and test hook-param/object safety.

## Expected Evidence Before Validation

- `UE4SS.log` has no unresolved `GNatives` or `FUObjectHashTables::Get()`
- hook callbacks can receive object params without crashing
- `FindFirstOf`, `StaticFindObject`, and basic object-name access are stable
- dumper/type generation path completes
- only then should the Windows bridge chat canary be re-enabled
