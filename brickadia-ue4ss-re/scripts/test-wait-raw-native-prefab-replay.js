#!/usr/bin/env node

const assert = require('assert');
const {
  extractPrefabLogEvidence,
  parseGrid,
  parseHistory,
  summarizeRawCapture,
} = require('./wait-raw-native-prefab-replay.js');

assert.deepStrictEqual(parseGrid('120,60,96'), { x: 120, y: 60, z: 96 });
assert.deepStrictEqual(parseGrid('-2, -20, 32'), { x: -2, y: -20, z: 32 });
assert.throws(() => parseGrid('120 60 96'), /--place-grid/);

const lines = [
  'raw_process_event_capture',
  'enabled=true',
  'target_function_hooks=11',
  'history_count=2',
  'last_capture=/Script/Brickadia.BRTool_Placer:ServerPlaceCurrentPrefab',
  'history[1]=seq=1 source=client label=ServerPastePrefab function=/Script/Brickadia.BRPlayerController:ServerPastePrefab context_pointer=0x0000000000000001 bytes=64',
  'history[2]=seq=2 source=client label=ServerPlaceCurrentPrefab function=/Script/Brickadia.BRTool_Placer:ServerPlaceCurrentPrefab context_pointer=0x0000000000000002 bytes=223',
];

const history = parseHistory(lines);
assert.strictEqual(history.length, 2);
assert.strictEqual(history[0].label, 'ServerPastePrefab');
assert.strictEqual(history[0].bytes, 64);
assert.strictEqual(history[1].label, 'ServerPlaceCurrentPrefab');
assert.strictEqual(history[1].bytes, 223);

const summary = summarizeRawCapture({ lines });
assert.strictEqual(summary.ready, true);
assert.strictEqual(summary.enabled, true);
assert.strictEqual(summary.historyCount, 2);
assert.strictEqual(summary.clientPaste.sequence, 1);
assert.strictEqual(summary.clientPlace.sequence, 2);

const evidence = extractPrefabLogEvidence([
  '[2026.06.01] LogBrickPrefabs: Caching prefab from serialized data (Hash=ABC, DataSize=1 bytes)',
  '[2026.06.01] LogBRWorldManager: not relevant',
  '[2026.06.01] ClientLoadWorldAccepted',
].join('\n'));

assert.strictEqual(evidence.length, 2);
assert(evidence[0].includes('LogBrickPrefabs'));
assert(evidence[1].includes('ClientLoadWorldAccepted'));

console.log('PASS test-wait-raw-native-prefab-replay');
