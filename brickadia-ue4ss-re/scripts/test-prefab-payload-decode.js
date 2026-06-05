#!/usr/bin/env node
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { extractArchive, parseBrz } = require('./inspect-brz.js');

const LOCALAPPDATA = process.env.LOCALAPPDATA;
if (!LOCALAPPDATA) {
  throw new Error('LOCALAPPDATA is not set');
}

const INSPECT_SCHEMA = path.join(__dirname, 'inspect-brdb-schema.js');
const CLIPBOARD_BRZ = path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'Temp', 'Clipboard.brz');
const GALLERY_DIR = path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'GalleryCache', 'Prefabs');
const PREFERRED_GALLERY = '86e67da3-58dd-4af6-8193-f17076cf8227.brz';

function decode(schemaPath, dataPath, typeName) {
  const raw = execFileSync('node', [INSPECT_SCHEMA, schemaPath, dataPath, typeName], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  const parsed = JSON.parse(raw);
  if (!parsed.decoded || !parsed.decoded.value) {
    throw new Error(`Decode failed for ${typeName}: ${raw}`);
  }
  return parsed.decoded.value;
}

function sum(list, field) {
  return (list || []).reduce((acc, item) => {
    if (typeof item === 'number') {
      return acc + item;
    }
    return acc + ((item && item[field]) || 0);
  }, 0);
}

function listRelativeFiles(rootDir) {
  const results = [];
  function walk(currentDir) {
    for (const entry of fs.readdirSync(currentDir, { withFileTypes: true })) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else {
        results.push(path.relative(rootDir, fullPath).replace(/\\/g, '/'));
      }
    }
  }
  walk(rootDir);
  return results;
}

function extractBrz(brzPath, prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  extractArchive(parseBrz(brzPath), dir);
  return dir;
}

function chooseGallerySample() {
  const candidates = [];
  const preferredPath = path.join(GALLERY_DIR, PREFERRED_GALLERY);
  if (fs.existsSync(preferredPath)) {
    candidates.push(preferredPath);
  }
  for (const name of fs.readdirSync(GALLERY_DIR)) {
    if (!name.endsWith('.brz')) continue;
    const full = path.join(GALLERY_DIR, name);
    if (full !== preferredPath) {
      candidates.push(full);
    }
  }
  for (const candidate of candidates) {
    const tempDir = extractBrz(candidate, 'prefab-gallery-');
    const files = listRelativeFiles(tempDir);
    const hasNeededFiles = files.includes('Meta/Prefab.json') &&
      files.includes('World/0/Bricks/ChunkIndexShared.schema') &&
      files.includes('World/0/Bricks/ChunksShared.schema') &&
      files.includes('World/0/Bricks/ComponentsShared.schema') &&
      files.includes('World/0/Bricks/WiresShared.schema') &&
      files.includes('World/0/Entities/ChunksShared.schema') &&
      files.some((p) => /^World\/0\/Bricks\/Grids\/\d+\/Chunks\/.+\.mps$/.test(p)) &&
      files.some((p) => /^World\/0\/Bricks\/Grids\/\d+\/Components\/.+\.mps$/.test(p)) &&
      files.some((p) => /^World\/0\/Bricks\/Grids\/\d+\/Wires\/.+\.mps$/.test(p)) &&
      files.some((p) => /^World\/0\/Entities\/Chunks\/.+\.mps$/.test(p));
    if (hasNeededFiles) {
      return { brzPath: candidate, tempDir, files };
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  throw new Error('No gallery prefab sample with chunk/component/wire/entity payloads was found');
}

function findFirst(files, regex) {
  const match = files.find((file) => regex.test(file));
  if (!match) {
    throw new Error(`Missing file matching ${regex}`);
  }
  return match;
}

function runClipboardChecks() {
  assert(fs.existsSync(CLIPBOARD_BRZ), `Missing clipboard archive: ${CLIPBOARD_BRZ}`);
  const tempDir = extractBrz(CLIPBOARD_BRZ, 'prefab-clipboard-');
  try {
    const files = listRelativeFiles(tempDir);
    const owners = decode(
      path.join(tempDir, 'World', '0', 'Owners.schema'),
      path.join(tempDir, 'World', '0', 'Owners.mps'),
      'BRSavedOwnerTableSoA'
    );
    const globalData = decode(
      path.join(tempDir, 'World', '0', 'GlobalData.schema'),
      path.join(tempDir, 'World', '0', 'GlobalData.mps'),
      'BRSavedGlobalDataSoA'
    );
    const brickChunkIndexPath = findFirst(files, /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/);
    const gridId = brickChunkIndexPath.match(/^World\/0\/Bricks\/Grids\/(\d+)\//)[1];
    const brickChunkPath = findFirst(files, new RegExp(`^World/0/Bricks/Grids/${gridId}/Chunks/.+\\.mps$`));
    const chunkIndex = decode(
      path.join(tempDir, 'World', '0', 'Bricks', 'ChunkIndexShared.schema'),
      path.join(tempDir, brickChunkIndexPath),
      'BRSavedBrickChunkIndexSoA'
    );
    const chunk = decode(
      path.join(tempDir, 'World', '0', 'Bricks', 'ChunksShared.schema'),
      path.join(tempDir, brickChunkPath),
      'BRSavedBrickChunkSoA'
    );
    const entityChunkIndex = decode(
      path.join(tempDir, 'World', '0', 'Entities', 'ChunkIndex.schema'),
      path.join(tempDir, 'World', '0', 'Entities', 'ChunkIndex.mps'),
      'BRSavedEntityChunkIndexSoA'
    );
    const indexedBrickCount = sum(chunkIndex.NumBricks || []);
    const indexedEntityCount = sum(entityChunkIndex.NumEntities || []);

    assert(owners.UserNames.length > 0);
    assert(owners.DisplayNames.length > 0);
    assert((owners.BrickCounts[0] || 0) > 0);
    assert((globalData.ProceduralBrickAssetNames || []).length > 0);
    assert(indexedBrickCount > 0);
    assert(chunk.BrickTypeIndices.length > 0);
    assert.strictEqual(chunk.OwnerIndices.length, chunk.BrickTypeIndices.length);
    assert.strictEqual(chunk.ColorsAndAlphas.length, chunk.BrickTypeIndices.length);

    if (indexedEntityCount > 0) {
      const entityChunkPath = findFirst(files, /^World\/0\/Entities\/Chunks\/.+\.mps$/);
      const entityChunk = decode(
        path.join(tempDir, 'World', '0', 'Entities', 'ChunksShared.schema'),
        path.join(tempDir, entityChunkPath),
        'BRSavedEntityChunkSoA'
      );
      assert.strictEqual(sum(entityChunk.TypeCounters, 'NumEntities'), indexedEntityCount);
    }

    return {
      sample: 'clipboard',
      grid: gridId,
      bricks: indexedBrickCount,
      sampleChunkBricks: chunk.BrickTypeIndices.length,
      entities: indexedEntityCount,
      owners: owners.UserNames.length,
      materials: globalData.MaterialAssetNames.length,
      chunkCount: chunkIndex.NumBricks.length,
    };
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function runGalleryChecks() {
  const { brzPath, tempDir, files } = chooseGallerySample();
  try {
    const prefabMeta = JSON.parse(fs.readFileSync(path.join(tempDir, 'Meta', 'Prefab.json'), 'utf8'));
    const brickChunkPath = findFirst(files, /^World\/0\/Bricks\/Grids\/\d+\/Chunks\/.+\.mps$/);
    const componentChunkPath = findFirst(files, /^World\/0\/Bricks\/Grids\/\d+\/Components\/.+\.mps$/);
    const wireChunkPath = findFirst(files, /^World\/0\/Bricks\/Grids\/\d+\/Wires\/.+\.mps$/);
    const entityChunkPath = findFirst(files, /^World\/0\/Entities\/Chunks\/.+\.mps$/);
    const brickChunkIndexPath = findFirst(files, /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/);

    const brickChunkIndex = decode(
      path.join(tempDir, 'World', '0', 'Bricks', 'ChunkIndexShared.schema'),
      path.join(tempDir, brickChunkIndexPath),
      'BRSavedBrickChunkIndexSoA'
    );
    const brickChunk = decode(
      path.join(tempDir, 'World', '0', 'Bricks', 'ChunksShared.schema'),
      path.join(tempDir, brickChunkPath),
      'BRSavedBrickChunkSoA'
    );
    const componentChunk = decode(
      path.join(tempDir, 'World', '0', 'Bricks', 'ComponentsShared.schema'),
      path.join(tempDir, componentChunkPath),
      'BRSavedComponentChunkSoA'
    );
    const wireChunk = decode(
      path.join(tempDir, 'World', '0', 'Bricks', 'WiresShared.schema'),
      path.join(tempDir, wireChunkPath),
      'BRSavedWireChunkSoA'
    );
    const entityChunk = decode(
      path.join(tempDir, 'World', '0', 'Entities', 'ChunksShared.schema'),
      path.join(tempDir, entityChunkPath),
      'BRSavedEntityChunkSoA'
    );

    const componentCount = sum(componentChunk.ComponentTypeCounters, 'NumInstances');
    const entityCount = sum(entityChunk.TypeCounters, 'NumEntities');
    const wireSourceCount = (wireChunk.LocalWireSources || []).length + (wireChunk.RemoteWireSources || []).length;
    const wireTargetCount = (wireChunk.LocalWireTargets || []).length + (wireChunk.RemoteWireTargets || []).length;

    assert.strictEqual(sum(brickChunkIndex.NumBricks || []), prefabMeta.brickCount);
    assert.strictEqual(sum(brickChunkIndex.NumComponents || []), prefabMeta.componentCount);
    assert.strictEqual(sum(brickChunkIndex.NumWires || []), prefabMeta.wireCount);
    assert.strictEqual(brickChunk.BrickTypeIndices.length, prefabMeta.brickCount);
    assert.strictEqual(brickChunk.OwnerIndices.length, prefabMeta.brickCount);
    assert.strictEqual(brickChunk.ColorsAndAlphas.length, prefabMeta.brickCount);
    assert.strictEqual(componentCount, prefabMeta.componentCount);
    assert.strictEqual(entityCount, prefabMeta.entityCount);
    assert.strictEqual(wireSourceCount, prefabMeta.wireCount);
    assert.strictEqual(wireTargetCount, prefabMeta.wireCount);

    return {
      sample: path.basename(brzPath),
      bricks: prefabMeta.brickCount,
      components: componentCount,
      entities: entityCount,
      wires: wireSourceCount,
    };
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function main() {
  const clipboard = runClipboardChecks();
  const gallery = runGalleryChecks();
  console.log(JSON.stringify({ clipboard, gallery }, null, 2));
}

main();
