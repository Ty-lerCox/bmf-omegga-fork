#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  CL13530_PLACE_PREFAB_CHAIN,
  inspectPlacePrefabActionChain,
  readDefaultExeFromAnchors,
  renderSummary,
} = require('./inspect-place-prefab-action-chain.js');

const anchorsPath = path.resolve(__dirname, '..', 'notes', 'cl13530-pe-prefab-anchors-latest.json');
const exePath = readDefaultExeFromAnchors(anchorsPath);

if (!fs.existsSync(exePath)) {
  console.log(`SKIP test-inspect-place-prefab-action-chain missing exe ${exePath}`);
  process.exit(0);
}

const report = inspectPlacePrefabActionChain(exePath);

assert.strictEqual(report.ok, true);
assert.strictEqual(report.build, 'CL13530');
assert.strictEqual(report.method_block.va, '0x146C79D50');
assert.strictEqual(report.method_block.slots[3].actual, '0x1443DC230');
assert.strictEqual(report.thin_submitter.submit_call, '0x1448A68BE');
assert.strictEqual(report.thin_submitter.submit_target, '0x1443DF4F0');
assert.ok(report.thin_submitter.direct_submit_callers.includes('0x1448A68BE'));

const refs = new Set(report.descriptor_refs.map((ref) => ref.instruction_va_hex));
for (const va of CL13530_PLACE_PREFAB_CHAIN.expectedDescriptorRefs) {
  assert.ok(refs.has(`0x${va.toString(16).toUpperCase()}`), `missing descriptor ref ${va.toString(16)}`);
}

const summary = renderSummary(report);
assert.match(summary, /ok=true/);
assert.match(summary, /method_block=0x146C79D50/);

console.log('PASS test-inspect-place-prefab-action-chain');
