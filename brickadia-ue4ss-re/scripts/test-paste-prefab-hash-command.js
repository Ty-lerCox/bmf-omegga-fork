#!/usr/bin/env node

const assert = require('assert');
const {
  buildCommand,
  isRawLastPlaceSeed,
  normalizeHash,
  parseArgs,
  parseRawProcessEventCaptureLines,
} = require('./paste-prefab-hash.js');

const HASH = '27d46e8288751fda6794e734276438a6ded430cd8d3fbe4e122b79a34e3d9b0d';

assert.strictEqual(
  normalizeHash(` ${HASH.slice(0, 32)}-${HASH.slice(32)} `),
  HASH.toUpperCase(),
);

const options = parseArgs([
  '--hash',
  HASH,
  '--grid',
  '3000',
  '0',
  '700',
  '--orientation',
  '4',
  '--target',
  'last',
  '--paste-seed',
  'hex:ABCD',
  '--ownership',
  '1',
  '--temp',
  '0',
  '--dry-run',
  '1',
]);

assert.deepStrictEqual(options.grid, ['3000', '0', '700']);
assert.strictEqual(options.orientation, '4');
assert.strictEqual(options.target, 'last');
assert.strictEqual(options.pasteSeed, 'hex:ABCD');
assert.strictEqual(options.dryRun, true);
assert.strictEqual(
  buildCommand(options),
  `Omegga.Bridge.PastePrefabHash ${HASH.toUpperCase()} grid 3000 0 700 4 ownership=1 temp=0 target=last pasteseed=hex:ABCD dry-run`,
);

const placeOptions = parseArgs([
  '--hash',
  HASH,
  '--grid',
  '3000',
  '0',
  '700',
  '--orientation',
  '4',
  '--place-current-prefab',
  '1',
  '--place-only',
  '1',
  '--place-seed',
  'rawlast',
]);

assert.strictEqual(placeOptions.placeCurrentPrefab, true);
assert.strictEqual(placeOptions.placeOnly, true);
assert.strictEqual(placeOptions.placeSeed, 'rawlast');
assert.strictEqual(
  buildCommand(placeOptions),
  `Omegga.Bridge.PasteAndPlacePrefabHash ${HASH.toUpperCase()} grid 3000 0 700 4 ownership=1 temp=0 target=0 placeseed=rawlast placeonly=1`,
);
assert.strictEqual(isRawLastPlaceSeed('rawlast'), true);
assert.strictEqual(isRawLastPlaceSeed('default'), false);

const seededPasteOptions = parseArgs([
  '--hash',
  HASH,
  '--grid',
  '1',
  '2',
  '3',
  '--paste-seed',
  'hex:ABCD',
]);
assert.strictEqual(seededPasteOptions.targetSpecified, false);
assert.strictEqual(
  buildCommand(seededPasteOptions),
  `Omegga.Bridge.PastePrefabHash ${HASH.toUpperCase()} grid 1 2 3 pasteseed=hex:ABCD`,
);

const rawCapture = parseRawProcessEventCaptureLines([
  'raw_process_event_capture',
  'target_label=ServerPlaceCurrentPrefab',
  'source=client',
  'param_bytes=223',
  'param_hex=ABCD',
  'raw_replay_layout=ServerPlaceCurrentPrefab',
]);
assert.strictEqual(rawCapture.targetLabel, 'ServerPlaceCurrentPrefab');
assert.strictEqual(rawCapture.source, 'client');
assert.strictEqual(rawCapture.paramBytes, 223);
assert.strictEqual(rawCapture.paramHex, 'ABCD');

assert.throws(
  () => parseArgs(['--hash', HASH, '--brz', 'x.brz', '--grid', '0', '0', '0']),
  /expected exactly one/,
);

console.log('PASS test-paste-prefab-hash-command');
