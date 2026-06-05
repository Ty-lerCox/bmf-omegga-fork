#!/usr/bin/env node

const assert = require('assert');
const {
  evaluateWatcherPayload,
  parseHashPasteLines,
  parseReplayLines,
} = require('./verify-prefab-native-vehicle-replay.js');

assert.deepStrictEqual(
  parseReplayLines([
    'Replay last prefab native capture',
    'kind=ServerPastePrefab',
    'function=ServerPastePrefab',
    'replay_mode=offset',
    'ok=true',
    'result=true',
    'original_grid=1,2,3',
    'final_grid=11,22,33',
    'grid_delta=10,20,30',
  ]),
  {
    ok: true,
    result: 'true',
    function: 'ServerPastePrefab',
    kind: 'ServerPastePrefab',
    replayMode: 'offset',
    originalGrid: { x: 1, y: 2, z: 3 },
    finalGrid: { x: 11, y: 22, z: 33 },
    gridDelta: { x: 10, y: 20, z: 30 },
    rawLines: [
      'Replay last prefab native capture',
      'kind=ServerPastePrefab',
      'function=ServerPastePrefab',
      'replay_mode=offset',
      'ok=true',
      'result=true',
      'original_grid=1,2,3',
      'final_grid=11,22,33',
      'grid_delta=10,20,30',
    ],
  },
);

assert.deepStrictEqual(
  parseHashPasteLines([
    'Paste prefab hash native',
    'kind=ServerPastePrefab',
    'function=ServerPastePrefab',
    'hash=000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F',
    'grid=3000,0,700',
    'dry_run=true',
    'ok=true',
    'result=dry-run',
  ]),
  {
    ok: true,
    result: 'dry-run',
    function: 'ServerPastePrefab',
    kind: 'ServerPastePrefab',
    hash: '000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F',
    grid: { x: 3000, y: 0, z: 700 },
    dryRun: true,
    rawLines: [
      'Paste prefab hash native',
      'kind=ServerPastePrefab',
      'function=ServerPastePrefab',
      'hash=000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F',
      'grid=3000,0,700',
      'dry_run=true',
      'ok=true',
      'result=dry-run',
    ],
  },
);

const waiting = evaluateWatcherPayload({
  status: 'waiting-for-player',
  player_count: 0,
  player_seen: false,
  observed_capture_events: 0,
  last_client_capture: null,
});
assert.strictEqual(waiting.status, 'waiting-for-player');
assert.strictEqual(waiting.ok, false);
assert(waiting.reasons.some((reason) => /waiting for a connected player/.test(reason)));

const ignoredUpload = evaluateWatcherPayload({
  status: 'waiting-for-capture',
  player_count: 1,
  player_seen: true,
  observed_capture_events: 1,
  last_client_capture: 'ClientUploadPrefab',
});
assert.strictEqual(ignoredUpload.status, 'waiting-for-replayable-capture');
assert.strictEqual(ignoredUpload.ok, false);
assert(ignoredUpload.reasons.some((reason) => /ignored ClientUploadPrefab/.test(reason)));

const retainedReplayable = evaluateWatcherPayload({
  status: 'waiting-for-capture',
  player_count: 1,
  player_seen: true,
  observed_capture_events: 2,
  last_client_capture: 'ClientUploadPrefab',
  last_replayable_client_capture: 'ServerPastePrefab',
});
assert.strictEqual(retainedReplayable.status, 'prefab-capture-ready');
assert.strictEqual(retainedReplayable.ok, false);
assert(retainedReplayable.reasons.some((reason) => /retained replayable ServerPastePrefab/.test(reason)));

const coherent = evaluateWatcherPayload({
  status: 'replay-command-sent',
  capture: {
    capturedKind: 'ServerPlaceSimpleEntityVolume',
    replayable: true,
  },
  replay: {
    success: true,
    lines: [
      'Replay last prefab native capture',
      'kind=ServerPlaceSimpleEntityVolume',
      'function=ServerPlaceSimpleEntityVolume',
      'replay_mode=offset',
      'ok=true',
      'result=true',
    ],
  },
  post_actor_dump: {
    summary: {
      coherentDynamicActorCandidates: 1,
      warnings: [],
    },
  },
  post_hash_paste: {
    status: 'skipped',
    success: null,
    lines: null,
  },
});
assert.strictEqual(coherent.status, 'vehicle-replay-coherent');
assert.strictEqual(coherent.ok, true);
assert.deepStrictEqual(coherent.reasons, []);
assert.strictEqual(coherent.hash_paste.status, 'skipped');

const broken = evaluateWatcherPayload({
  status: 'replay-command-sent',
  capture: {
    capturedKind: 'ServerPastePrefab',
    replayable: true,
  },
  replay: {
    success: true,
    lines: [
      'Replay last prefab native capture',
      'kind=ServerPastePrefab',
      'function=ServerPastePrefab',
      'replay_mode=offset',
      'ok=true',
      'result=true',
    ],
  },
  post_actor_dump: {
    summary: {
      coherentDynamicActorCandidates: 0,
      warnings: ['Wheel entities exist without a coherent dynamic grid actor candidate.'],
    },
  },
});
assert.strictEqual(broken.status, 'vehicle-replay-unverified');
assert.strictEqual(broken.ok, false);
assert(broken.reasons.some((reason) => /no coherent BrickGridDynamicActor/.test(reason)));
assert(broken.reasons.some((reason) => /warnings/.test(reason)));

console.log('PASS test-verify-prefab-native-vehicle-replay');
