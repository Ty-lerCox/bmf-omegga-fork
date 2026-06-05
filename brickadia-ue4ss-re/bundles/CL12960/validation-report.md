# CL12960 Validation Report

## Status

- Bundle: `CL12960`
- Brickadia build: `Brickadia EA2 (PC-Shipping-CL12960)`
- Validation state: `staged`
- Omegga Windows object-dependent control: `degraded`

## Stage Results

1. Static validation: passed
2. UE4SS startup validation: passed
3. Object-resolution validation: passed
4. Dumper validation: blocked
5. Omegga re-entry gate: blocked

## Confirmed Working Pieces

- External RE workspace exists and is discoverable by Omegga
- Bundle structure is enforced
- Hook foundation static coverage now passes for all four tracked targets:
  - `UObject::ProcessEvent`: custom Brickadia layout entry present at ordinal `72`; stock UE 5.5 default offset is `0x278`
  - `UEngine::LoadMap`: custom Brickadia layout entry present at ordinal `70`; stock UE 5.5 default offset is `0x4e0`
  - `AGameModeBase::InitGameState`: no Brickadia override yet; currently uses stock UE 5.5 default offset `0x790`, supported by the Discord seed note that Brickadia only adds extra vfuncs in `UObject` and `UEngine`
  - `AActor::BeginPlay`: no Brickadia override yet; currently uses stock UE 5.5 default offset `0x3a0`, supported by the same seed note
- The live `UE4SS.log` now includes runtime hook-address confirmation for all four core targets:
  - `ProcessEvent address 0x7ff75b9d3db0`
  - `GameEngine::LoadMap address 0x7ff75e3804d0`
  - `GameModeBase::InitGameState address 0x7ff75dcabcd0`
  - `AActor::BeginPlay address 0x7ff75d8041c0`
- Current `CL12960` resolver addresses:
  - `FName::FName(wchar_t*) = 0x140237e50`
  - `FName::ToString = 0x1402d5d70`
  - `StaticConstructObject_Internal = 0x140505310`
  - `ConsoleManagerSingleton = 0x140064bb0`
  - `UGameEngine::Tick = 0x1422c3bd0`
  - `GUObjectArray = 0x14768f038`
  - `FUObjectArray::AllocateUObjectIndex = 0x1404f7cb0`
  - `FUObjectArray::FreeUObjectIndex = 0x1404f8020`
  - `GNatives = 0x14768d760` via the staged Brickadia Lua override
- The live second-pass Lua scan now reports:
  - `GNatives address: 0x7ff76304d760 <- Lua Script`
  - `GUObjectArray address: 0x7ff76304f038 <- Lua Script`
- A standalone proof mod scaffold now exists at:
  - `probes/CL12960/BaselineObjectProof`
- The clean stage-3 proof ladder now succeeds:
  - `RemoteUnrealParam:get()` unwraps the `InitGameState` context to a valid UObject wrapper
  - `FindFirstOf("GameEngine")` returns successfully in a proof-only runtime
  - `StaticFindObject("/Script/CoreUObject.Default__Object")` returns successfully through the no-`ToString` long-name path
- The old `FName_Constructor.lua` override is intentionally disabled for `CL12960`.
  - `patternsleuth` already resolves `FName::FName(wchar_t*)` correctly on this build.
  - Leaving the old Lua override enabled destabilizes the second-pass scan before the real unresolved blockers are reported.

## Current Blockers

- `FUObjectHashTables::Get()`
- Dedicated dumper validation has not been rerun yet after the stage-3 lookup fixes
- Omegga re-entry is still gated on stages 1-4, so Windows object-dependent bridge features remain disabled in the product runtime for now
- Clean proof-mod-only sessions still emit a callback-garbage-collector cleanup line after successful probes, so callback stability stays tracked separately from object-resolution correctness
- The longer `StaticFindObjectFast` and `FUObjectHashTables` anchor strings used by stock resolvers are absent on `CL12960`
- The stock resolver family also fails for:
  - `StaticFindObjectFast`
  - `UObject::SkipFunction`
  - `GNativesPatterns`
  - `GNativesViaSkipFunction`
  - `FFrame::Step`
  - `FFrame::StepExplicitProperty`
  - `FFrame::StepViaExec`

## Current Build Anchors

- UTF-16 strings in the live binary:
  - `StaticFindObjectFast = 0x145d372c0`
  - `FUObjectHashTables = 0x145d3eeae`
  - `HashOuter = 0x145d3ed64`
- Ghidra foothold from current anchors:
  - `HashOuter` xrefs into `FUN_14053a860`
  - decompiling that function shows direct access to the Brickadia hash-table globals rather than an obvious stock-style standalone getter
  - that makes `FUObjectHashTables::Get()` look more like a Brickadia-specific resolver problem than a simple missing stock pattern
- Old PDB public symbol hints still worth transferring:
  - `StaticFindObjectFastSafe`
  - `StaticFindObjectChecked`
  - `StaticFindObjectSafe`
  - `FUObjectHashTables::~FUObjectHashTables`
  - `UObject::ProcessConsoleExec`

## Why Omegga Is Frozen

Live probing now shows the main remaining gate is above the stage-3 object proof:

- the hook foundation is runtime-confirmed
- startup and the stage-3 object proof ladder now pass in clean proof-only sessions
- but dumper validation has not been rerun yet, and Windows product re-entry still waits for stages 1-4 to clear as a bundle

Until stage 4 also passes, Windows object-dependent bridge features should remain disabled in the product runtime.
