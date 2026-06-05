# CL13530 Validation Report

## Status

- Bundle: `CL13530`
- Brickadia build: `Brickadia EA2 (PC-Shipping-CL13530)`
- Validation state: `staged`
- Omegga Windows object-dependent control: `degraded`

## Stage Results

1. Static validation: passed
2. UE4SS startup validation: passed
3. Object-resolution validation: passed
4. Dumper validation: blocked
5. Omegga re-entry gate: blocked

## Notes

- The public dedicated server app updated to Steam build `23487010` on `2026-05-30T16:42:56Z`.
- This bundle started from `CL12960`, but the CL13530 startup and baseline object proof ladder now pass with the patched Brickadia UE4SS runtime.
- `GUObjectHashTables` remains explicitly deferred by the runtime; it is no longer a fatal startup blocker.
- Keep object-dependent Windows control degraded until the CL13530 chat/world canaries and dumper policy are refreshed.

## Current CL13530 Findings

- `node .\scripts\validate-bundle.mjs --bundle CL13530` passes static bundle validation.
- `npm start -- ue4ss validate` detects `Brickadia EA2 (PC-Shipping-CL13530)` and selects bundle `CL13530`.
- The patched Brickadia UE4SS runtime downgrades the unresolved `GUObjectHashTables` Lua scan to a degraded startup signal instead of a fatal error.
- Live UE4SS scan output resolves:
  - `GNatives = 0x7ff66fddd760`
  - `GUObjectArray = 0x7ff66fddf038`
  - `CallFunctionByNameWithArguments = 0x7ff668c1bad0`
- UE4SS reaches `ScanGame`, installs hook logging, starts `OmeggaBridge`, and executes bridge command canaries.
- The CL13530 baseline object proof ladder writes fresh proof output under `probes/CL13530/output`.
- Baseline report: `notes/cl13530-baseline-tests-latest.md` (`38 passed / 0 failed / 2 blocked`).
- Current expanded full-suite report: `notes/cl13530-full-tests-latest.md` (`80 passed / 0 failed / 15 blocked`).
- Stage 4 remains blocked only because the dumper has not been rerun and validated.
