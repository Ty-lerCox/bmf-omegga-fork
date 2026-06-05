#!/usr/bin/env node

const assert = require('assert');
const path = require('path');
const {
  parseArgs,
  parseCacheLine,
  parseLogEvents,
} = require('./wait-cached-prefab-hash-paste.js');

const HASH = 'c7ced9479311611da3b75d2b40275bb6299f0506929da41bfae48fd2c083aaf1';

const parsed = parseArgs([
  '--grid',
  '12000',
  '0',
  '2400',
  '--orientation',
  '4',
  '--target',
  '0',
  '--dry-run',
  '1',
  '--place-current-prefab',
  '1',
  '--paste-seed',
  'hex:ABCD',
  '--place-seed',
  'rawlast',
  '--from-current-end',
  '0',
  '--require-additive-load',
  '1',
  '--status-path',
  'C:\\tmp\\cached-status.json',
]);

assert.deepStrictEqual(parsed.grid, ['12000', '0', '2400']);
assert.strictEqual(parsed.orientation, '4');
assert.strictEqual(parsed.dryRun, true);
assert.strictEqual(parsed.placeCurrentPrefab, true);
assert.strictEqual(parsed.pasteSeed, 'hex:ABCD');
assert.strictEqual(parsed.placeSeed, 'rawlast');
assert.strictEqual(parsed.fromCurrentEnd, false);
assert.strictEqual(parsed.requireAdditiveLoad, true);
assert.strictEqual(parsed.statusPath, path.resolve('C:\\tmp\\cached-status.json'));

const cacheLine = `[2026.06.01-00.49.00:388][722]LogBrickPrefabs: Caching prefab from serialized data (Hash=${HASH.toUpperCase()}, DataSize=217102 bytes)`;
assert.deepStrictEqual(parseCacheLine(cacheLine), {
  hash: HASH.toUpperCase(),
  dataSize: 217102,
  line: cacheLine,
});

const serializationLine = `[2026.06.01-17.39.31:291][643]LogBrickPrefabs: Serialization complete (Hash=${HASH.toUpperCase()}, Size=17675 bytes)`;
assert.deepStrictEqual(parseCacheLine(serializationLine), {
  hash: HASH.toUpperCase(),
  dataSize: 17675,
  line: serializationLine,
});

const addedLine = `[2026.06.01-17.39.31:295][643]LogBrickPrefabs: Added prefab to cache (Hash=${HASH.toUpperCase()}, Size=17675 bytes, TotalCacheSize=175026 bytes, CacheCount=2)`;
assert.deepStrictEqual(parseCacheLine(addedLine), {
  hash: HASH.toUpperCase(),
  dataSize: 17675,
  line: addedLine,
});

const events = parseLogEvents([
  cacheLine,
  '[2026.06.01-00.49.01:976][773]LogBRWorldManager: World successfully loaded additively.',
].join('\n'));

assert.strictEqual(events.length, 2);
assert.strictEqual(events[0].type, 'cache');
assert.strictEqual(events[0].hash, HASH.toUpperCase());
assert.strictEqual(events[1].type, 'additive-success');

assert.throws(
  () => parseArgs(['--hash', HASH]),
  /unknown option/,
);
assert.throws(
  () => parseArgs([]),
  /missing --grid/,
);

console.log('PASS test-wait-cached-prefab-hash-paste');
