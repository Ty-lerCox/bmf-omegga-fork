# Brickadia Windows Modding Progress

_Tracked build: `CL12960`_

## At A Glance

- Working checks: `25`
- In progress: `6`
- Waiting on earlier fixes: `2`
- Total checks tracked: `33`

## What's Working

- The compatibility bundle is assembled correctly and its file checks are all passing (4 of 4 bundle checks).
- The core startup hooks are now mapped for this build (9 passing hook-foundation checks so far).
- Several lower-level engine building blocks are already identified (9 passing resolver checks so far).
- Startup logs and baseline reports are being captured reliably (3 passing runtime checks so far).

## Current Focus

- Restore the engine path used to find live game objects
  Why this matters: Until object lookup works, anything that depends on finding live game objects stays unreliable.
  Next step: Trace the hash-table family and recover the getter used by this build.

## Priority 1: Core Startup Hooks

- No open startup-hook work right now.

## Priority 2: Object Lookup And Scripting Support

- Restore the engine path used to find live game objects
  Why it matters: Until object lookup works, anything that depends on finding live game objects stays unreliable.
- Restore the engine path used to call built-in game functions
  Why it matters: Until this is restored, built-in script/native execution support stays incomplete.
- Recover fast object lookup for this build
  Why it matters: This is part of the object lookup family that later modding work depends on.
- Recover a missing script execution helper
  Why it matters: This is a lower-level scripting helper still missing from the current build coverage.
- Recover the frame-stepping path used by scripts
  Why it matters: This is another low-level scripting helper that has to come back before deeper script support is trustworthy.

## Priority 3: Stability And Validation

- Make object access stable instead of crash-prone
  Why it matters: This is the roll-up check for whether object access is safe enough to build on.

## Waiting On Earlier Fixes

- Callback garbage collector does not invalidate startup callbacks
  Waiting on: an earlier prerequisite
- Unblock the automatic dumper and richer tooling stage
  Waiting on: Make object access stable instead of crash-prone

## Up Next

- Restore the engine path used to call built-in game functions
  Next step: Trace the script/native dispatch path and recover the current table address from the live binary.
- Recover fast object lookup for this build
  Next step: Revisit fast object lookup after the startup blockers above it are cleared.

## What This Means

- The Windows wrapper and reporting side are already in place.
- The remaining work is inside the game/engine compatibility layer, not the launcher or UI layer.
- The near-term job is to finish the remaining resolver work, then stabilize startup and object lookup.

## For Technical Readers

- Detailed engineering report: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\cl12960-baseline-tests-latest.md`
- Detailed bundle status: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\bundles\CL12960\validation-report.md`

