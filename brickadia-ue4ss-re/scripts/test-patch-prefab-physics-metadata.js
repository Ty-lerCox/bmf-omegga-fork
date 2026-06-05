#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { blake3 } = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/@noble/hashes/blake3.js');
const { parseBrz, decompressChunk } = require('./inspect-brz.js');
const { diagnose } = require('./diagnose-prefab-vehicle-structure.js');
const {
  buildIndexData,
  patchPrefabPhysicsMetadata,
} = require('./patch-prefab-physics-metadata.js');

const LOCALAPPDATA = process.env.LOCALAPPDATA;
if (!LOCALAPPDATA) {
  throw new Error('LOCALAPPDATA is not set');
}

const CLIPBOARD_BRZ = path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'Temp', 'Clipboard.brz');

function readArchiveJson(parsed, archivePath) {
  const file = parsed.files.find((entry) => entry.path === archivePath);
  assert(file, `Missing archive path: ${archivePath}`);
  const blob = parsed.blobs[file.contentId];
  const content = decompressChunk(blob.compressionMethod, blob.data, blob.decompressedLength);
  return JSON.parse(content.toString('utf8'));
}

function verifyArchiveHashes(archivePath) {
  const parsed = parseBrz(archivePath);
  const blobRecords = parsed.blobs.map((blob) => ({
    compressionMethod: blob.compressionMethod,
    decompressedLength: blob.decompressedLength,
    compressedLength: blob.compressedLength,
    hash: Buffer.from(blob.hash, 'hex'),
  }));
  const indexData = buildIndexData(parsed, blobRecords);
  assert.strictEqual(Buffer.from(blake3(indexData)).toString('hex'), parsed.header.indexHash);

  for (const blob of parsed.blobs) {
    const content = decompressChunk(blob.compressionMethod, blob.data, blob.decompressedLength);
    assert.strictEqual(content.length, blob.decompressedLength);
    assert.strictEqual(Buffer.from(blake3(content)).toString('hex'), blob.hash);
  }
  return parsed;
}

function main() {
  assert(fs.existsSync(CLIPBOARD_BRZ), `Missing clipboard archive: ${CLIPBOARD_BRZ}`);
  const outputPath = path.join(os.tmpdir(), `prefab-physics-meta-${Date.now()}.brz`);
  try {
    patchPrefabPhysicsMetadata(CLIPBOARD_BRZ, outputPath, {
      force: true,
      identityWorldRoot: true,
    });
    const parsed = verifyArchiveHashes(outputPath);
    const report = diagnose(outputPath);
    const meta = readArchiveJson(parsed, 'Meta/Prefab.json');
    const brickCount = report.grids.reduce((acc, grid) => acc + grid.brick_count, 0);
    const componentCount = report.grids.reduce((acc, grid) => acc + grid.component_count, 0);
    const wireCount = report.grids.reduce((acc, grid) => acc + grid.wire_count, 0);

    assert.strictEqual(meta.bIsPhysicsGrid, true);
    assert.strictEqual(meta.bFreezePhysicsGrid, false);
    assert.deepStrictEqual(meta.worldRootTransform, {
      rotation: { x: 0, y: 0, z: 0, w: 1 },
      translation: { x: 0, y: 0, z: 0 },
      scale3D: { x: 1, y: 1, z: 1 },
    });
    assert.strictEqual(meta.brickCount, brickCount);
    assert.strictEqual(meta.componentCount, componentCount);
    assert.strictEqual(meta.entityCount, report.entity.total_entities);
    assert.strictEqual(meta.wireCount, wireCount);
    assert(!report.warnings.some((warning) => /bIsPhysicsGrid=false/.test(warning)));
  } finally {
    fs.rmSync(outputPath, { force: true });
  }

  console.log('PASS test-patch-prefab-physics-metadata');
}

main();
