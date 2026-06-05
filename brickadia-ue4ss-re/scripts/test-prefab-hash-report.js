#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { hashPrefab, buildReport } = require('./prefab-hash-report.js');

const LOCALAPPDATA = process.env.LOCALAPPDATA;
if (!LOCALAPPDATA) {
  throw new Error('LOCALAPPDATA is not set');
}

const AE86_PREFAB = path.join(
  LOCALAPPDATA,
  'Brickadia',
  'Saved',
  'GalleryCache',
  'Prefabs',
  '8c04e0ee-87b3-4eef-b5de-659c60f1e9ac.brz',
);
const KNOWN_LOGGED_PREFAB_HASH = '07C8E4AD16AC2B85B7FBE8637C9929AD9326ECA7384219F05937BD0F464BB7AD';

function main() {
  assert(fs.existsSync(AE86_PREFAB), `Missing known gallery prefab: ${AE86_PREFAB}`);
  const ae86 = hashPrefab(AE86_PREFAB);
  assert.strictEqual(ae86.brPrefabHashCandidate, KNOWN_LOGGED_PREFAB_HASH);
  assert.strictEqual(ae86.hashBasis, 'blake3(raw .brz archive bytes)');
  assert.strictEqual(ae86.summary.bIsPhysicsGrid, true);
  assert(ae86.summary.entityTypes.includes('BrickGridDynamicActor'));
  assert(ae86.summary.jointEntityReferences > 0);

  const report = buildReport({ inputs: [AE86_PREFAB], scanGallery: false, clipboard: false });
  assert.strictEqual(report.prefabs.length, 1);
  assert.strictEqual(report.prefabs[0].brPrefabHashCandidate, KNOWN_LOGGED_PREFAB_HASH);
  assert.strictEqual(report.hashInference.status, 'strong-local-evidence');

  console.log('PASS test-prefab-hash-report');
}

main();
