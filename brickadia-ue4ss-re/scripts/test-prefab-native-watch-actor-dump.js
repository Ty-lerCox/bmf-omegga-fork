#!/usr/bin/env node

const assert = require('assert');
const {
  buildPostHashPasteCommand,
  evaluateCapture,
  parseReplayPlacement,
  parseFlagSummary,
  summarizeActorDump,
} = require('./wait-prefab-native-capture-replay.js');

assert.deepStrictEqual(
  parseFlagSummary('valid=true is_class=false transient=false was_loaded=true'),
  {
    valid: true,
    is_class: false,
    transient: false,
    was_loaded: true,
  },
);

const coherentDump = [
  'Prefab actor dump classes=BrickGridDynamicActor,BP_Entity_Wheel_Deep1_C',
  'class BrickGridDynamicActor count=1',
  'actor[1] requested=BrickGridDynamicActor class=BrickGridDynamicActor addr=0x1000 name=Vehicle location=x=1.000 y=2.000 z=3.000 source=RootComponent.RelativeLocation attempts=',
  'actor[1].flags=valid=true is_any_class=false is_class=false cdo=false archetype=false transient=false was_loaded=true',
  'actor[1].raw.RootComponent.address=8192',
  'class BP_Entity_Wheel_Deep1_C count=1',
  'actor[2] requested=BP_Entity_Wheel_Deep1_C class=BP_Entity_Wheel_Deep1_C addr=0x2000 name=Wheel location=x=4.000 y=5.000 z=6.000 source=RootComponent.RelativeLocation attempts=',
  'actor[2].flags=valid=true is_any_class=false is_class=false cdo=false archetype=false transient=false was_loaded=true',
  'actor[2].raw.RootComponent.address=12288',
];

const coherent = summarizeActorDump(coherentDump);
assert.strictEqual(coherent.actorCount, 2);
assert.strictEqual(coherent.classCounts.BrickGridDynamicActor, 1);
assert.strictEqual(coherent.coherentDynamicActorCandidates, 1);
assert.strictEqual(coherent.wheelEntityCandidates, 1);
assert.strictEqual(coherent.unresolvedLocations, 0);
assert.strictEqual(coherent.rootlessActors, 0);
assert.deepStrictEqual(coherent.warnings, []);

const brokenDump = [
  'Prefab actor dump classes=BrickGridDynamicActor,BP_Entity_Wheel_Deep1_C',
  'class BrickGridDynamicActor count=1',
  'actor[1] requested=BrickGridDynamicActor class= . addr=0x1000 name= . location=unresolved source=unresolved attempts=RootComponent=unavailable',
  'actor[1].flags=valid=true is_any_class=false is_class=false cdo=false archetype=false transient=true was_loaded=false',
  'actor[1].raw.RootComponent.address=0',
  'class BP_Entity_Wheel_Deep1_C count=1',
  'actor[2] requested=BP_Entity_Wheel_Deep1_C class=BP_Entity_Wheel_Deep1_C addr=0x2000 name=Wheel location=unresolved source=unresolved attempts=RootComponent=unavailable',
  'actor[2].flags=valid=true is_any_class=false is_class=false cdo=false archetype=false transient=false was_loaded=true',
  'actor[2].raw.RootComponent.address=0',
];

const broken = summarizeActorDump(brokenDump);
assert.strictEqual(broken.actorCount, 2);
assert.strictEqual(broken.coherentDynamicActorCandidates, 0);
assert.strictEqual(broken.wheelEntityCandidates, 1);
assert.strictEqual(broken.unresolvedLocations, 2);
assert.strictEqual(broken.rootlessActors, 2);
assert(broken.warnings.some((warning) => /BrickGridDynamicActor objects were found/.test(warning)));
assert(broken.warnings.some((warning) => /Wheel entities exist/.test(warning)));

const safeCountOnlyDump = [
  'Prefab actor dump classes=BrickGridDynamicActor',
  'location_ufunctions=disabled',
  'object_property_reads=disabled',
  'class BrickGridDynamicActor count=1',
  'actor[1] requested=BrickGridDynamicActor class=BrickGridDynamicActor addr=0x4000 name=Vehicle location=unresolved source=skipped-unsafe-property-read attempts=K2_GetActorLocation=skipped-unsafe-struct-return;GetActorLocation=skipped-unsafe-struct-return;ObjectProperties=skipped-unsafe-property-read',
  'actor[1].flags=valid=true is_any_class=false is_class=false cdo=false archetype=false transient=false was_loaded=true',
  'actor[1].raw.properties=skipped-unsafe-property-read',
];

const safeCountOnly = summarizeActorDump(safeCountOnlyDump);
assert.strictEqual(safeCountOnly.actorCount, 1);
assert.strictEqual(safeCountOnly.classCounts.BrickGridDynamicActor, 1);
assert.strictEqual(safeCountOnly.coherentDynamicActorCandidates, 0);
assert.strictEqual(safeCountOnly.unresolvedLocations, 1);
assert.strictEqual(safeCountOnly.rootlessActors, 0);
assert(safeCountOnly.warnings.some((warning) => /BrickGridDynamicActor objects were found/.test(warning)));

const nativeCaptureWithUnreliablePlayerCount = evaluateCapture(
  {
    captureEvents: 1,
    lastClientCapture: 'ServerPastePrefab',
  },
  0,
  {
    existingOk: false,
    expectedKind: 'any',
    stopOnOtherKind: true,
  },
);
assert.strictEqual(nativeCaptureWithUnreliablePlayerCount.ready, true);
assert.strictEqual(nativeCaptureWithUnreliablePlayerCount.replayable, true);
assert.strictEqual(nativeCaptureWithUnreliablePlayerCount.capturedKind, 'ServerPastePrefab');

const simpleEntityVolumeCapture = evaluateCapture(
  {
    captureEvents: 1,
    lastClientCapture: 'ServerPlaceSimpleEntityVolume',
  },
  0,
  {
    existingOk: false,
    expectedKind: 'any',
    stopOnOtherKind: true,
  },
);
assert.strictEqual(simpleEntityVolumeCapture.ready, true);
assert.strictEqual(simpleEntityVolumeCapture.replayable, true);
assert.strictEqual(simpleEntityVolumeCapture.capturedKind, 'ServerPlaceSimpleEntityVolume');

const uploadHandshakeCapture = evaluateCapture(
  {
    captureEvents: 1,
    lastClientCapture: 'ClientUploadPrefab',
  },
  0,
  {
    existingOk: false,
    expectedKind: 'any',
    stopOnOtherKind: true,
  },
);
assert.strictEqual(uploadHandshakeCapture.ready, false);
assert.strictEqual(uploadHandshakeCapture.ignored, true);
assert.match(uploadHandshakeCapture.reason, /continuing to wait/);

const placeAsPhysicsToggleCapture = evaluateCapture(
  {
    captureEvents: 1,
    lastClientCapture: 'SetPlaceAsPhysicsEnabled',
  },
  0,
  {
    existingOk: false,
    expectedKind: 'any',
    stopOnOtherKind: true,
  },
);
assert.strictEqual(placeAsPhysicsToggleCapture.ready, false);
assert.strictEqual(placeAsPhysicsToggleCapture.ignored, true);
assert.match(placeAsPhysicsToggleCapture.reason, /continuing to wait/);

const retainedReplayableCapture = evaluateCapture(
  {
    captureEvents: 2,
    lastClientCapture: 'ClientUploadPrefab',
    lastReplayableClientCapture: 'ServerPlaceCurrentPrefab',
  },
  0,
  {
    existingOk: false,
    expectedKind: 'any',
    stopOnOtherKind: true,
  },
);
assert.strictEqual(retainedReplayableCapture.ready, true);
assert.strictEqual(retainedReplayableCapture.replayable, true);
assert.strictEqual(retainedReplayableCapture.capturedKind, 'ServerPlaceCurrentPrefab');

const terminalEntityCapture = evaluateCapture(
  {
    captureEvents: 1,
    lastClientCapture: 'ServerPasteEntity',
  },
  0,
  {
    existingOk: false,
    expectedKind: 'any',
    stopOnOtherKind: true,
  },
);
assert.strictEqual(terminalEntityCapture.ready, true);
assert.strictEqual(terminalEntityCapture.replayable, false);
assert.strictEqual(terminalEntityCapture.capturedKind, 'ServerPasteEntity');

assert.deepStrictEqual(
  parseReplayPlacement([
    'Replay last prefab native capture',
    'final_grid=3100,0,900',
    'final_orientation=4',
  ]),
  {
    grid: { x: 3100, y: 0, z: 900 },
    orientation: 4,
  },
);

const hashPastePlan = buildPostHashPasteCommand(
  {
    decoded: {
      serverPastePrefab: {
        hash_hex: '000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F',
        bWithOwnership: true,
        bInTemp: false,
        pasteInfo: {
          gridOffset: { x: 3000, y: 0, z: 700 },
          placementOrientation: 2,
        },
      },
    },
  },
  {
    lines: [
      'Replay last prefab native capture',
      'final_grid=3100,0,900',
      'final_orientation=4',
    ],
  },
  {
    postHashPaste: 'dry-run',
    postHashPasteTarget: 'last',
  },
);
assert.strictEqual(hashPastePlan.status, 'ready');
assert.strictEqual(hashPastePlan.mode, 'dry-run');
assert.deepStrictEqual(hashPastePlan.grid, { x: 3100, y: 0, z: 900 });
assert.strictEqual(
  hashPastePlan.command,
  'Omegga.Bridge.PastePrefabHash 000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F grid 3100 0 900 4 ownership=1 temp=0 target=last dry-run',
);

const skippedHashPastePlan = buildPostHashPasteCommand(
  { decoded: { serverPastePrefab: null } },
  null,
  { postHashPaste: 'dry-run', postHashPasteTarget: 'last' },
);
assert.strictEqual(skippedHashPastePlan.status, 'skipped');

console.log('PASS test-prefab-native-watch-actor-dump');
