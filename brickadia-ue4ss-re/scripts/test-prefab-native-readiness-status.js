#!/usr/bin/env node

const assert = require('assert');
const {
  deriveReadinessStatus,
  parseContextLines,
  parseHookLines,
} = require('./prefab-native-readiness.js');

const emptyHooks = {
  lastClientCapture: null,
};

assert.strictEqual(
  deriveReadinessStatus({
    hookState: emptyHooks,
    readyForClientPaste: true,
    playerCount: 0,
    vehicleReplayVerdict: { ok: false, status: 'waiting-for-player' },
  }),
  'ready-waiting-for-player',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: emptyHooks,
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: { ok: false, status: 'waiting-for-capture' },
  }),
  'ready-for-client-paste',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: { lastClientCapture: 'ServerPastePrefab' },
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: { ok: false, status: 'waiting-for-capture' },
  }),
  'prefab-capture-ready',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: { lastClientCapture: 'ServerPasteEntity' },
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: { ok: false, status: 'waiting-for-capture' },
  }),
  'client-capture-non-prefab',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: { lastClientCapture: 'ClientUploadPrefab' },
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: { ok: false, status: 'waiting-for-replayable-capture' },
  }),
  'ready-for-client-paste',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: {
      lastClientCapture: 'ClientUploadPrefab',
      lastReplayableClientCapture: 'ServerPlaceCurrentPrefab',
    },
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: { ok: false, status: 'waiting-for-replayable-capture' },
  }),
  'prefab-capture-ready',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: { lastClientCapture: 'ServerPastePrefab' },
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: { ok: true, status: 'vehicle-replay-coherent' },
  }),
  'vehicle-replay-coherent',
);

assert.strictEqual(
  deriveReadinessStatus({
    hookState: { lastClientCapture: 'ServerPastePrefab' },
    readyForClientPaste: true,
    playerCount: 1,
    vehicleReplayVerdict: {
      ok: false,
      status: 'vehicle-replay-unverified',
      checks: { watcherFinished: true },
    },
  }),
  'vehicle-replay-unverified',
);

const parsed = parseHookLines([
  'registered=true',
  'registered_kind ServerPastePrefab=/Script/Brickadia.BRPlayerController:ServerPastePrefab',
  'capture_events=1',
  'last_capture=ServerPastePrefab source=client',
  'last_client_capture=ServerPastePrefab',
  'last_replayable_client_capture=ServerPastePrefab',
  'last_replay_capture=ServerPastePrefab replay_id=1',
]);

assert.strictEqual(parsed.registered, true);
assert.strictEqual(
  parsed.registeredKinds.ServerPastePrefab,
  '/Script/Brickadia.BRPlayerController:ServerPastePrefab',
);
assert.strictEqual(parsed.captureEvents, 1);
assert.deepStrictEqual(parsed.lastCapture, { kind: 'ServerPastePrefab', source: 'client' });
assert.strictEqual(parsed.lastClientCapture, 'ServerPastePrefab');
assert.strictEqual(parsed.lastReplayableClientCapture, 'ServerPastePrefab');
assert.strictEqual(parsed.lastReplayCapture, 'ServerPastePrefab replay_id=1');

const parsedContext = parseContextLines([
  'ServerPastePrefab context',
  'context_available=true',
  'context_source=FindFirstOf(BRPlayerController)',
  'context=BP_PlayerController_C /Game/Foo',
  'cached_player_states=1',
  'find_first BRPlayerController=true object=BP_PlayerController_C /Game/Foo',
  'find_first BP_PlayerController_C=false object=nil',
]);

assert.strictEqual(parsedContext.available, true);
assert.strictEqual(parsedContext.source, 'FindFirstOf(BRPlayerController)');
assert.strictEqual(parsedContext.context, 'BP_PlayerController_C /Game/Foo');
assert.strictEqual(parsedContext.cachedPlayerStates, 1);
assert.deepStrictEqual(parsedContext.findFirst.BRPlayerController, {
  available: true,
  object: 'BP_PlayerController_C /Game/Foo',
});
assert.deepStrictEqual(parsedContext.findFirst.BP_PlayerController_C, {
  available: false,
  object: 'nil',
});

const parsedNilContext = parseContextLines([
  'context_available=nil',
  'find_first PlayerController=nil object=nil',
]);
assert.strictEqual(parsedNilContext.available, false);
assert.deepStrictEqual(parsedNilContext.findFirst.PlayerController, {
  available: false,
  object: 'nil',
});

console.log('PASS test-prefab-native-readiness-status');
