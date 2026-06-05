#!/usr/bin/env node

const assert = require('assert');
const path = require('path');
const { parseArgs } = require('./wait-paste-prefab-hash.js');

const HASH = '00'.repeat(32);

{
  const parsed = parseArgs([
    '--hash',
    HASH,
    '--grid',
    '9000',
    '0',
    '1400',
  ]);
  assert.strictEqual(parsed.hash, HASH);
  assert.deepStrictEqual(parsed.grid, ['9000', '0', '1400']);
  assert.strictEqual(parsed.timeoutMs, 300000);
  assert.strictEqual(parsed.pollMs, 1000);
  assert.strictEqual(parsed.checkPlayers, false);
  assert.strictEqual(parsed.postDumpActors, false);
  assert.strictEqual(
    parsed.statusPath,
    path.join(parsed.bridgeDir, 'prefab-hash-paste-status.json'),
  );
}

{
  const parsed = parseArgs([
    '--brz',
    'C:\\tmp\\vehicle.brz',
    '--grid',
    '1',
    '2',
    '3',
    '--dry-run',
    '1',
    '--post-dump-actors',
    '0',
    '--place-current-prefab',
    '1',
    '--paste-seed',
    'hex:ABCD',
    '--place-seed',
    'rawlast',
    '--check-players',
    '1',
    '--timeout-ms',
    '2500',
    '--poll-ms',
    '250',
    '--status-path',
    'C:\\tmp\\status.json',
  ]);
  assert.strictEqual(parsed.brz, path.resolve('C:\\tmp\\vehicle.brz'));
  assert.strictEqual(parsed.dryRun, true);
  assert.strictEqual(parsed.placeCurrentPrefab, true);
  assert.strictEqual(parsed.pasteSeed, 'hex:ABCD');
  assert.strictEqual(parsed.placeSeed, 'rawlast');
  assert.strictEqual(parsed.checkPlayers, true);
  assert.strictEqual(parsed.postDumpActors, false);
  assert.strictEqual(parsed.timeoutMs, 2500);
  assert.strictEqual(parsed.pollMs, 250);
  assert.strictEqual(parsed.statusPath, path.resolve('C:\\tmp\\status.json'));
}

assert.throws(
  () => parseArgs(['--hash', HASH, '--brz', 'C:\\tmp\\vehicle.brz', '--grid', '1', '2', '3']),
  /expected exactly one/,
);
assert.throws(
  () => parseArgs(['--hash', HASH]),
  /missing --grid/,
);

console.log('PASS test-wait-paste-prefab-hash');
