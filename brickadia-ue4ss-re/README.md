# Brickadia UE4SS Compatibility Workspace

This workspace is the source of truth for Brickadia-specific UE4SS compatibility work.

The current target is `Brickadia EA2 (PC-Shipping-CL13530)`. Omegga consumes only the compatibility bundle artifacts from this workspace. It does not treat ad hoc runtime probing as proof that Windows object-dependent control is safe.

## Layout

- `bundles/CL13530`
  - staged compatibility bundle for the current Brickadia server build, seeded from `CL12960` and awaiting fresh validation
  - includes the staged `VTableLayout.ini`, Brickadia custom game config, signature files, and validation reports
- `bundles/CL12960`
  - prior compatibility bundle for the old Brickadia build
  - includes the staged `VTableLayout.ini`, Brickadia custom game config, signature files, and validation reports
- `scripts/write-manifest.mjs`
  - recomputes the bundle file hash map in `manifest.json`
- `scripts/validate-bundle.mjs`
  - validates bundle structure, required files, and manifest hashes
- `scripts/run-baseline-tests.py`
  - renders a pass/fail/blocked scoreboard for the current evidence snapshot
- `scripts/run-cl12960-baseline-tests.ps1`
  - one-command wrapper that refreshes `CL12960` evidence and writes the latest baseline test reports
- `scripts/render-community-roadmap.py`
  - turns the current baseline test results into a community-friendly roadmap markdown report
- `scripts/run-cl12960-community-roadmap.ps1`
  - refreshes the baseline test suite and writes the latest community roadmap report
- `notes/CL12960-baseline.md`
  - provenance and current blockers for the `CL12960` baseline

## Current State

- The `CL13530` bundle exists and is consumable by Omegga.
- The `CL13530` bundle is **staged**, not validated.
- The copied `CL12960` signatures and layout must be rerun through the baseline ladder before Windows object-dependent control can be enabled.

Until those pass the baseline ladder, Omegga should remain degraded for Windows object-dependent features.

## Baseline Ladder

1. Static bundle validation
2. UE4SS startup validation
3. Object-resolution validation
4. Dumper validation
5. Omegga re-entry gate

The first product canary after the baseline passes is still bridge-originated `chat.broadcast`.

## Seed Inputs

The following inputs are seed material and must be revalidated on the current target bundle:

- `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\5.5.4-0+UE5-Brickadia.usmap`
- `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\BrickadiaSteam-Win64-Shipping.pdb`
- `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\VTableLayout.ini`
- `C:\Users\tycox\OneDrive\Documents\Downloads\older data from discord server\Resources Convos.txt`

## Tooling

- UE baseline: `C:\Program Files\Epic Games\UE_5.5`
- Patched UE4SS fork: `C:\Users\tycox\Tools\reverse-engineering\RE-UE4SS`
- Static tooling: Ghidra, x64dbg, Patternsleuth, `binfold`, `usmap2json`

## Workflow

1. Update or confirm the bundle files under the current target, currently `bundles/CL13530`.
2. Run:

```powershell
node .\scripts\write-manifest.mjs --bundle CL13530
node .\scripts\validate-bundle.mjs --bundle CL13530
```

3. Port or run the live baseline/proof scripts for the current target before promoting the bundle. The existing `run-cl12960-*` scripts are prior-target wrappers and should not be treated as CL13530 proof without updating their probe and report paths.

4. Record findings in:
   - `bundles/CL13530/validation-report.json`
   - `bundles/CL13530/validation-report.md`
   - `notes/CL13530-baseline.md`
   - `notes/cl13530-baseline-tests-latest.json`
   - `notes/cl13530-baseline-tests-latest.md`
   - `notes/cl13530-community-roadmap.md`

5. Only mark `manifest.json` as `validated: true` after stages 1-4 are actually passing on the target CL.
