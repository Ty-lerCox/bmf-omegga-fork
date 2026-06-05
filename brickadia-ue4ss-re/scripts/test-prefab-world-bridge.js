#!/usr/bin/env node
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const Database = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/better-sqlite3');
const {
  buildPrefabWorldBrdb,
  entityChunkOffsetFromPlacementOffset,
  readBrickChunkIndex,
  readEntityChunkIndex,
  readWireChunk,
  shouldPatchPhysicsMetadata,
} = require('./build-prefab-world-brdb.js');

const LOCALAPPDATA = process.env.LOCALAPPDATA;
if (!LOCALAPPDATA) {
  throw new Error('LOCALAPPDATA is not set');
}

const PREFAB_BRZ = path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'GalleryCache', 'Prefabs', '86e67da3-58dd-4af6-8193-f17076cf8227.brz');
const CLIPBOARD_BRZ = path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'Temp', 'Clipboard.brz');

function listFiles(db) {
  return db.prepare(`
    WITH RECURSIVE folder_path(folder_id, path) AS (
      SELECT folder_id, name
      FROM folders
      WHERE parent_id IS NULL
      UNION ALL
      SELECT f.folder_id, folder_path.path || '/' || f.name
      FROM folders f
      JOIN folder_path ON f.parent_id = folder_path.folder_id
    )
    SELECT folder_path.path || '/' || files.name AS path
    FROM files
    JOIN folder_path ON files.parent_id = folder_path.folder_id
    ORDER BY path
  `).all().map((row) => row.path);
}

function readJson(db, filePath) {
  const row = db.prepare(`
    WITH RECURSIVE folder_path(folder_id, path) AS (
      SELECT folder_id, name
      FROM folders
      WHERE parent_id IS NULL
      UNION ALL
      SELECT f.folder_id, folder_path.path || '/' || f.name
      FROM folders f
      JOIN folder_path ON f.parent_id = folder_path.folder_id
    )
    SELECT blobs.compression, blobs.size_uncompressed, blobs.content
    FROM files
    JOIN folder_path ON files.parent_id = folder_path.folder_id
    JOIN blobs ON files.content_id = blobs.blob_id
    WHERE folder_path.path || '/' || files.name = ?
  `).get(filePath);
  if (!row) {
    return null;
  }
  let content = row.content;
  if (row.compression === 1) {
    content = zlib.zstdDecompressSync(content, { maxOutputLength: row.size_uncompressed, params: {} });
  }
  return JSON.parse(content.toString('utf8'));
}

function readBuffer(db, filePath) {
  const row = db.prepare(`
    WITH RECURSIVE folder_path(folder_id, path) AS (
      SELECT folder_id, name
      FROM folders
      WHERE parent_id IS NULL
      UNION ALL
      SELECT f.folder_id, folder_path.path || '/' || f.name
      FROM folders f
      JOIN folder_path ON f.parent_id = folder_path.folder_id
    )
    SELECT blobs.compression, blobs.size_uncompressed, blobs.content
    FROM files
    JOIN folder_path ON files.parent_id = folder_path.folder_id
    JOIN blobs ON files.content_id = blobs.blob_id
    WHERE folder_path.path || '/' || files.name = ?
  `).get(filePath);
  assert(row, `Missing BRDB file: ${filePath}`);
  if (row.compression === 1) {
    return zlib.zstdDecompressSync(row.content, {
      maxOutputLength: row.size_uncompressed,
      params: {},
    });
  }
  return row.content;
}

function assertBrickChunkFilesMatchIndexes(db) {
  const files = listFiles(db);
  const indexPaths = files.filter((p) => /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/.test(p));
  assert(indexPaths.length > 0);
  for (const indexPath of indexPaths) {
    const gridDir = path.posix.dirname(indexPath);
    const index = readBrickChunkIndex(readBuffer(db, indexPath));
    for (let i = 0; i < index.chunks.length; i++) {
      const chunk = index.chunks[i];
      const fileName = `${chunk.x}_${chunk.y}_${chunk.z}.mps`;
      if ((index.numBricks[i] || 0) > 0) {
        assert(files.includes(`${gridDir}/Chunks/${fileName}`), `Missing brick chunk file for ${indexPath}: ${fileName}`);
      }
      if ((index.numComponents[i] || 0) > 0) {
        assert(files.includes(`${gridDir}/Components/${fileName}`), `Missing component chunk file for ${indexPath}: ${fileName}`);
      }
      if ((index.numWires[i] || 0) > 0) {
        assert(files.includes(`${gridDir}/Wires/${fileName}`), `Missing wire chunk file for ${indexPath}: ${fileName}`);
      }
    }
  }
}

function assertRemoteWireSourcesMatchIndexes(db) {
  const files = listFiles(db);
  const chunksByGrid = new Map();
  for (const indexPath of files.filter((p) => /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/.test(p))) {
    const gridPersistentIndex = Number(indexPath.match(/\/Grids\/(\d+)\//)[1]);
    const index = readBrickChunkIndex(readBuffer(db, indexPath));
    chunksByGrid.set(
      gridPersistentIndex,
      new Set(index.chunks.map((chunk) => `${chunk.x}_${chunk.y}_${chunk.z}`))
    );
  }

  for (const wirePath of files.filter((p) => /^World\/0\/Bricks\/Grids\/\d+\/Wires\/.+\.mps$/.test(p))) {
    const wireChunk = readWireChunk(readBuffer(db, wirePath));
    for (const source of wireChunk.remoteWireSources) {
      const gridChunks = chunksByGrid.get(source.gridPersistentIndex);
      const chunkName = `${source.chunkIndex.x}_${source.chunkIndex.y}_${source.chunkIndex.z}`;
      assert(gridChunks?.has(chunkName), `Remote wire source in ${wirePath} references missing grid ${source.gridPersistentIndex} chunk ${chunkName}`);
    }
  }
}

function main() {
  assert(fs.existsSync(PREFAB_BRZ), `Missing prefab archive: ${PREFAB_BRZ}`);
  const baseOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-base.brdb`);
  const placedOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-placed.brdb`);
  const preservedOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-preserved.brdb`);
  const clipboardOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-clipboard.brdb`);
  const clipboardPatchedOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-clipboard-patched.brdb`);
  const clipboardBaseOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-clipboard-base.brdb`);
  const clipboardEntityOnlyOutputPath = path.join(os.tmpdir(), `prefab-world-${Date.now()}-clipboard-entity-only.brdb`);
  const placementOffset = { x: 2000, y: 0, z: 500 };
  const entityChunkOffset = entityChunkOffsetFromPlacementOffset(placementOffset);

  buildPrefabWorldBrdb(PREFAB_BRZ, baseOutputPath, { environment: 'Plate', force: true });
  buildPrefabWorldBrdb(PREFAB_BRZ, placedOutputPath, {
    environment: 'Plate',
    force: true,
    placementOffset,
  });
  buildPrefabWorldBrdb(PREFAB_BRZ, preservedOutputPath, {
    environment: 'Plate',
    force: true,
    bundleType: 'preserve',
  });

  const outputPath = placedOutputPath;
  const db = new Database(outputPath, { readonly: true });
  const baseDb = new Database(baseOutputPath, { readonly: true });
  try {
    const files = listFiles(db);
    assertBrickChunkFilesMatchIndexes(db);
    assertRemoteWireSourcesMatchIndexes(db);
    const bundle = readJson(db, 'Meta/Bundle.json');
    const world = readJson(db, 'Meta/World.json');
    const prefab = readJson(db, 'Meta/Prefab.json');

    assert(files.includes('Meta/Bundle.json'));
    assert(files.includes('Meta/World.json'));
    assert(files.includes('Meta/Prefab.json'));
    assert(files.includes('World/0/Bricks/Grids/1/ChunkIndex.mps'));
    assert(files.some((p) => /^World\/0\/Bricks\/Grids\/1\/Chunks\/.+\.mps$/.test(p)));
    assert(files.some((p) => /^World\/0\/Entities\/Chunks\/.+\.mps$/.test(p)));

    assert.strictEqual(bundle.type, 'World');
    assert.strictEqual(bundle.name, 'HL2 Jeep');
    assert.strictEqual(world.environment, 'Plate');
    assert.strictEqual(prefab.brickCount, 566);

    const baseBrickIndexPath = listFiles(baseDb).find((p) => /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/.test(p));
    const placedBrickIndexPath = files.find((p) => /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/.test(p));
    const baseBrickIndex = readBrickChunkIndex(readBuffer(baseDb, baseBrickIndexPath));
    const placedBrickIndex = readBrickChunkIndex(readBuffer(db, placedBrickIndexPath));
    assert.strictEqual(placedBrickIndex.chunks.length, baseBrickIndex.chunks.length);
    assert(placedBrickIndex.chunks.length > 0);

    const baseBrickChunk = baseBrickIndex.chunks[0];
    const baseBrickOffset = baseBrickIndex.offsets[0];
    const baseBrickSize = baseBrickIndex.chunkSizes[0];
    const expectedChunk = {
      x: baseBrickChunk.x + Math.round(placementOffset.x / baseBrickSize),
      y: baseBrickChunk.y + Math.round(placementOffset.y / baseBrickSize),
      z: baseBrickChunk.z + Math.round(placementOffset.z / baseBrickSize),
    };
    assert.strictEqual(placedBrickIndex.chunks[0].x, expectedChunk.x);
    assert.strictEqual(placedBrickIndex.chunks[0].y, expectedChunk.y);
    assert.strictEqual(placedBrickIndex.chunks[0].z, expectedChunk.z);
    assert.strictEqual(placedBrickIndex.offsets[0].x, baseBrickOffset.x);
    assert.strictEqual(placedBrickIndex.offsets[0].y, baseBrickOffset.y);
    assert.strictEqual(placedBrickIndex.offsets[0].z, baseBrickOffset.z);

    const movedBrickName = `${expectedChunk.x}_${expectedChunk.y}_${expectedChunk.z}.mps`;
    assert(files.includes(`World/0/Bricks/Grids/1/Chunks/${movedBrickName}`));
    assert(files.includes(`World/0/Bricks/Grids/1/Components/${movedBrickName}`));
    assert(files.includes(`World/0/Bricks/Grids/1/Wires/${movedBrickName}`));

    const baseIndex = readEntityChunkIndex(readBuffer(baseDb, 'World/0/Entities/ChunkIndex.mps'));
    const placedIndex = readEntityChunkIndex(readBuffer(db, 'World/0/Entities/ChunkIndex.mps'));
    assert.strictEqual(placedIndex.chunks.length, baseIndex.chunks.length);
    assert.strictEqual(placedIndex.chunks[0].x, baseIndex.chunks[0].x + entityChunkOffset.x);
    assert.strictEqual(placedIndex.chunks[0].y, baseIndex.chunks[0].y + entityChunkOffset.y);
    assert.strictEqual(placedIndex.chunks[0].z, baseIndex.chunks[0].z + entityChunkOffset.z);
    assert(files.includes(`World/0/Entities/Chunks/${placedIndex.chunks[0].x}_${placedIndex.chunks[0].y}_${placedIndex.chunks[0].z}.mps`));

    console.log(JSON.stringify({
      outputPath,
      bundleType: bundle.type,
      environment: world.environment,
      brickCount: prefab.brickCount,
      brickChunk: placedBrickIndex.chunks[0],
      entityChunk: placedIndex.chunks[0],
      metaFiles: files.filter((p) => p.startsWith('Meta/')),
    }, null, 2));

    if (fs.existsSync(CLIPBOARD_BRZ)) {
      buildPrefabWorldBrdb(CLIPBOARD_BRZ, clipboardBaseOutputPath, {
        environment: 'Plate',
        force: true,
      });
      buildPrefabWorldBrdb(CLIPBOARD_BRZ, clipboardEntityOnlyOutputPath, {
        environment: 'Plate',
        force: true,
        entityChunkOffset,
      });
      buildPrefabWorldBrdb(CLIPBOARD_BRZ, clipboardOutputPath, {
        environment: 'Plate',
        force: true,
        placementOffset,
      });
      buildPrefabWorldBrdb(CLIPBOARD_BRZ, clipboardPatchedOutputPath, {
        environment: 'Plate',
        force: true,
        patchPhysicsMetadata: true,
      });
      const clipboardBaseDb = new Database(clipboardBaseOutputPath, { readonly: true });
      const clipboardEntityOnlyDb = new Database(clipboardEntityOnlyOutputPath, { readonly: true });
      const clipboardDb = new Database(clipboardOutputPath, { readonly: true });
      const clipboardPatchedDb = new Database(clipboardPatchedOutputPath, { readonly: true });
      try {
        assertBrickChunkFilesMatchIndexes(clipboardEntityOnlyDb);
        assertRemoteWireSourcesMatchIndexes(clipboardEntityOnlyDb);
        assertBrickChunkFilesMatchIndexes(clipboardDb);
        assertRemoteWireSourcesMatchIndexes(clipboardDb);

        const baseFiles = listFiles(clipboardBaseDb);
        const entityOnlyFiles = listFiles(clipboardEntityOnlyDb);
        const baseBrickIndexPaths = baseFiles
          .filter((p) => /^World\/0\/Bricks\/Grids\/\d+\/ChunkIndex\.mps$/.test(p))
          .sort();
        assert(baseBrickIndexPaths.length > 0);
        for (const baseIndexPath of baseBrickIndexPaths) {
          const gridId = baseIndexPath.match(/\/Grids\/(\d+)\//)[1];
          const entityOnlyIndexPath = `World/0/Bricks/Grids/${gridId}/ChunkIndex.mps`;
          const baseBrickIndex = readBrickChunkIndex(readBuffer(clipboardBaseDb, baseIndexPath));
          const entityOnlyBrickIndex = readBrickChunkIndex(readBuffer(clipboardEntityOnlyDb, entityOnlyIndexPath));
          assert.deepStrictEqual(
            entityOnlyBrickIndex.chunks,
            baseBrickIndex.chunks,
            `Entity-only placement should not move brick chunks for grid ${gridId}`
          );
          for (const chunk of baseBrickIndex.chunks) {
            const chunkName = `${chunk.x}_${chunk.y}_${chunk.z}.mps`;
            assert(entityOnlyFiles.includes(`World/0/Bricks/Grids/${gridId}/Chunks/${chunkName}`));
          }
        }

        const clipboardBaseEntityIndex = readEntityChunkIndex(readBuffer(clipboardBaseDb, 'World/0/Entities/ChunkIndex.mps'));
        const clipboardEntityOnlyIndex = readEntityChunkIndex(readBuffer(clipboardEntityOnlyDb, 'World/0/Entities/ChunkIndex.mps'));
        assert.strictEqual(clipboardEntityOnlyIndex.chunks.length, clipboardBaseEntityIndex.chunks.length);
        for (let i = 0; i < clipboardBaseEntityIndex.chunks.length; i++) {
          assert.strictEqual(clipboardEntityOnlyIndex.chunks[i].x, clipboardBaseEntityIndex.chunks[i].x + entityChunkOffset.x);
          assert.strictEqual(clipboardEntityOnlyIndex.chunks[i].y, clipboardBaseEntityIndex.chunks[i].y + entityChunkOffset.y);
          assert.strictEqual(clipboardEntityOnlyIndex.chunks[i].z, clipboardBaseEntityIndex.chunks[i].z + entityChunkOffset.z);
          assert(entityOnlyFiles.includes(`World/0/Entities/Chunks/${clipboardEntityOnlyIndex.chunks[i].x}_${clipboardEntityOnlyIndex.chunks[i].y}_${clipboardEntityOnlyIndex.chunks[i].z}.mps`));
        }

        const clipboardPrefabMeta = readJson(clipboardDb, 'Meta/Prefab.json');
        assert.strictEqual(clipboardPrefabMeta.bIsPhysicsGrid, false);

        const clipboardPatchedPrefabMeta = readJson(clipboardPatchedDb, 'Meta/Prefab.json');
        assert.strictEqual(clipboardPatchedPrefabMeta.bIsPhysicsGrid, true);
        assert.strictEqual(clipboardPatchedPrefabMeta.bFreezePhysicsGrid, false);
        assert(clipboardPatchedPrefabMeta.worldRootTransform, 'Expected opt-in patched dynamic clipboard prefab to include worldRootTransform');
      } finally {
        clipboardBaseDb.close();
        clipboardEntityOnlyDb.close();
        clipboardDb.close();
        clipboardPatchedDb.close();
      }
    }

    assert.strictEqual(
      shouldPatchPhysicsMetadata(
        { entity: { total_entities: 1 }, joints: { total_joint_entity_references: 1 } },
        { bIsPhysicsGrid: false },
      ),
      true,
    );
    assert.strictEqual(
      shouldPatchPhysicsMetadata(
        { entity: { total_entities: 1 }, joints: { total_joint_entity_references: 1 } },
        { bIsPhysicsGrid: true },
      ),
      false,
    );

    const preservedDb = new Database(preservedOutputPath, { readonly: true });
    try {
      const preservedBundle = readJson(preservedDb, 'Meta/Bundle.json');
      const preservedWorld = readJson(preservedDb, 'Meta/World.json');
      assert.strictEqual(preservedBundle.type, 'Prefab');
      assert.strictEqual(preservedBundle.name, 'HL2 Jeep');
      assert.strictEqual(preservedWorld.environment, 'Plate');
    } finally {
      preservedDb.close();
    }
  } finally {
    db.close();
    baseDb.close();
    fs.rmSync(baseOutputPath, { force: true });
    fs.rmSync(placedOutputPath, { force: true });
    fs.rmSync(preservedOutputPath, { force: true });
    fs.rmSync(clipboardOutputPath, { force: true });
    fs.rmSync(clipboardPatchedOutputPath, { force: true });
    fs.rmSync(clipboardBaseOutputPath, { force: true });
    fs.rmSync(clipboardEntityOnlyOutputPath, { force: true });
  }
}

main();
