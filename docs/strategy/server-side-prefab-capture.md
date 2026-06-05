# Server-Side Prefab Capture Strategy

Status: draft
Date: 2026-06-03

## Target

Create a fully server-side prefab workflow:

1. Accept a bounded region as two corners: `x1 y1 z1 x2 y2 z2`.
2. Capture everything in that box into a portable archive, preferably `.brz`.
3. Load that archive later additively, without relying on a player controller, quick slot, clipboard, or client-side prefab cache.
4. Preserve dynamic vehicles/entities when the source region contains them.

## Current Conclusion

The player-controller prefab replay path is the wrong long-term foundation.

It can replay some captured calls, but it depends on live player/controller
state, cached prefab data, and Brickadia's client placement pipeline. It also
does not explain how to save a server-side box into a reusable archive.

`BR.World.LoadAdditive` is the required headless load path. Full
`BR.World.Load` can be useful for unrelated diagnostics, but it does not satisfy
the product requirement because it replaces the current world. Current tests
show additive loading does not yet recreate the same dynamic vehicle/physics
state as a normal catalog/gallery placement. Treat additive vehicle support as
unproven until the proof gates below pass.

Transport note, 2026-06-03: `BR.World.SaveAs` and `BR.World.LoadAdditive`
work through the UE4SS `consolemanager` executor even while CL13530
object-dependent control is degraded. An empty `TransportProbe_*` bundle saved
to disk and loaded additively without replacing the active world. The remaining
proof is vehicle/entity semantics, not basic command transport.

## Proof Gates

### 1. Additive Vehicle Persistence

Place a known-good drivable vehicle in a clean server, then save the current
server world to a bundle:

```text
BR.World.SaveAs "VehiclePersistenceProbe"
```

Then load that same saved bundle additively into a clean area of the current
server world:

```text
BR.World.LoadAdditive VehiclePersistenceProbe 20000 0 1000 0
```

Pass condition: the additively loaded vehicle is a drivable, independent
dynamic actor.

Why this matters: if Brickadia's own additive world loader cannot materialize a
vehicle from a saved world bundle, then a box-to-BRZ exporter cannot rely on
`BR.World.LoadAdditive` for vehicles. The work must move to a native
server-side action/transaction path that creates the dynamic actor state.

### 2. Entity Graph or Bounded World Extraction

If additive vehicle persistence passes, save the world to `.brdb` and build an
extractor that copies only the requested vehicle/entity graph. Coordinate bounds
are useful for brick-only prefabs, but vehicles should be selected by saved
entity ID because the dynamic actor, wheel entities, component chunks, and wire
chunks are the real persistence boundary.

For a selected dynamic actor, the extractor should resolve:

- selected `World/0/Entities/...` rows
- related entities from `JointEntityReferences`
- brick grids whose grid IDs are related entity IDs
- component chunks whose joint references touch the graph
- wire chunks attached to related grids, including `RemoteWireSources`
- dependency schemas and generated metadata

The extractor must preserve references across bricks, components, wires, and
entities. For vehicles, the entity graph is part of the prefab, not optional
metadata.

### 3. Archive Writer

Write the bounded extracted bundle as `.brz` and `.brdb`.

The `.brz` writer must:

- rebuild the BRZ index
- recompute BLAKE3 blob hashes
- preserve compression method per blob
- preserve schema files and folder layout
- generate correct metadata counts

The `.brdb` writer is useful for server testing because Brickadia can load
world bundles directly from `Saved/Worlds`.

### 4. Additive Headless Load

Load the bounded archive without player controller state:

```text
BR.World.LoadAdditive <bundle_name> <x> <y> <z> <orientation>
```

If additive load preserves bricks but not dynamic vehicles, the next path is a
native server-side world/action submitter that consumes the same extracted
bundle data but commits it through Brickadia's authoritative dynamic actor
creation path.

## Near-Term Implementation Shape

Expose two command/API layers:

```text
/saveprefab car x1 y1 z1 x2 y2 z2
/listentities
/saveentity car <persistentEntityId>
/spawnprefab car x y z
```

Current implementation status:

- `/savebrickregion <name> x1 y1 z1 x2 y2 z2` writes a brick-only `.brs`
  through `Bricks.SaveRegion`.
- `/saveprefab <name> x1 y1 z1 x2 y2 z2` writes a full-world `.brdb`
  snapshot and records the requested bounding box in
  `artifacts/coordinate-prefabs.json`.
- `/listentities` writes a full-world `.brdb` snapshot, inspects saved entity
  chunks, and records dynamic actor graph candidates.
- `/saveentity <name> <persistentEntityId>` writes a full-world `.brdb`
  snapshot and records the selected entity graph in
  `artifacts/saved-entities.json`.
- The bounded `.brdb/.brz` extractor is still required before `/saveprefab`
  or `/saveentity` produces a truly cropped, vehicle-capable archive.

Internally:

1. Convert corners to center/extent for any legacy `Bricks.SaveRegion` fallback.
2. Save or snapshot the whole server world to `.brdb`.
3. Resolve either a bounded brick set or an entity graph from the saved world.
4. Extract a BRZ/BRDB bundle from the saved world.
5. Load from disk with `BR.World.LoadAdditive`.

The legacy BRS path can be kept for brick-only prefabs, but it must not be
treated as vehicle-capable.

## Short-Term Fallback

The client-worker broker can remain as a temporary usability path for spawning
vehicles through the real client placement pipeline. It is not the final
server-side prefab architecture.
