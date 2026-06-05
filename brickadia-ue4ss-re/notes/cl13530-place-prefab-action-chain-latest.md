# CL13530 PlacePrefab Action Chain

Generated: `2026-06-01`

## Current Blocker

The reflected replay path is not sufficient for server-side vehicle prefab placement.

- `ServerPastePrefab` raw replay returns `ok=true`.
- `ServerPlaceCurrentPrefab` raw replay returns `ok=true`.
- Vehicle actor counts remain unchanged after replay.
- A focused `HandleAttachedPlacement` UFunction hook does not fire during replay.

That makes the current blocker the native action/transaction path, not hash bytes, placement grid, height, or the captured RPC context.

## Static Chain

`node .\scripts\inspect-place-prefab-action-chain.js --summary` verifies the current CL13530 native chain:

```text
PlacePrefab action chain CL13530
ok=true
method_block=0x146C79D50
descriptor_refs=0x144214641,0x144214674,0x1448958A4,0x144895CDB,0x1448A6869
thin_submitter=0x1448A5880-0x1448A69F8
submit_call=0x1448A68BE->0x1443DF4F0
```

Confirmed `BrickAction_PlacePrefab` method block:

| Offset | Value | Meaning |
| --- | --- | --- |
| `+0x00` | `0x140024180` | descriptor slot |
| `+0x08` | `0x14420FE90` | `BrickAction_PlacePrefab` registration/name lane |
| `+0x10` | `0x140001000` | descriptor slot |
| `+0x18` | `0x1443DC230` | PlacePrefab action apply/additive lane |
| `+0x20` | `0x140013CB0` | descriptor slot |
| `+0x28` | `0x0` | null slot |
| `+0x30` | `0x140045B60` | descriptor slot |
| `+0x38` | `0x144211FF0` | descriptor slot |
| `+0x40` | `0x144214800` | constructor/helper slot |
| `+0x48` | `0x144214850` | constructor/helper slot |

Confirmed submit chain:

| Callsite | Target | Role |
| --- | --- | --- |
| `0x1448A68BE` | `0x1443DF4F0` | queue/context setup to shared submit stage |
| `0x1443DF734` | `0x1443DF7E0` | submit stage to owner/context bridge |
| `0x1443DF8F8` | `0x1443E05D0` | owner/context bridge to dispatcher |
| `0x1443E0B4E` | `0x144210120` | state submit wrapper to generic record submit |

## Next Target

The next implementation target should be a guarded native bridge into the prepared `BrickAction_PlacePrefab` action submitter family, not another `ProcessEvent` replay of `ServerPlaceCurrentPrefab`.

The currently strongest CL13530 candidate is the thin submitter function range `0x1448A5880-0x1448A69F8`, especially the descriptor-write and submit call around `0x1448A6869 -> 0x1448A68BE`.
