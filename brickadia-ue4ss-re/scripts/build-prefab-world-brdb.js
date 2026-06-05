#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const Database = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/better-sqlite3');
const { blake3 } = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/@noble/hashes/blake3.js');
const { convertBrzToBrdb } = require('./convert-brz-to-brdb.js');
const { diagnose } = require('./diagnose-prefab-vehicle-structure.js');
const { patchMetadata } = require('./patch-prefab-physics-metadata.js');

const ENTITY_CHUNK_WORLD_SIZE = 500;

function readBlobJson(db, filePath) {
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
    content = zlib.zstdDecompressSync(content, {
      maxOutputLength: row.size_uncompressed,
      params: {},
    });
  }
  return JSON.parse(content.toString('utf8'));
}

function listFiles(db, prefix) {
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
    WHERE folder_path.path || '/' || files.name LIKE ?
    ORDER BY path
  `).all(`${prefix}%`).map((row) => row.path);
}

function readBlob(db, filePath) {
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
    SELECT blobs.blob_id, blobs.compression, blobs.size_uncompressed, blobs.content
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
    content = zlib.zstdDecompressSync(content, {
      maxOutputLength: row.size_uncompressed,
      params: {},
    });
  }
  return { ...row, content };
}

function writeBlob(db, blobId, compression, content) {
  const compressed = compression === 1
    ? zlib.zstdCompressSync(content, { params: {} })
    : content;
  const hash = Buffer.from(blake3(content));
  db.prepare(`
    UPDATE blobs
    SET size_uncompressed = ?, size_compressed = ?, hash = ?, content = ?
    WHERE blob_id = ?
  `).run(content.length, compressed.length, hash, compressed, blobId);
}

function readMsgpackMarker(buffer, offset) {
  const byte = buffer[offset];
  if (byte <= 0x7f) return { kind: 'fixpos', offset: offset + 1 };
  if (byte >= 0xe0) return { kind: 'fixneg', offset: offset + 1 };
  if ((byte & 0xe0) === 0xa0) return { kind: 'fixstr', length: byte & 0x1f, offset: offset + 1 };
  if ((byte & 0xf0) === 0x90) return { kind: 'fixarray', length: byte & 0x0f, offset: offset + 1 };
  if ((byte & 0xf0) === 0x80) return { kind: 'fixmap', length: byte & 0x0f, offset: offset + 1 };
  switch (byte) {
    case 0xc0: return { kind: 'nil', offset: offset + 1 };
    case 0xc2:
    case 0xc3: return { kind: 'bool', offset: offset + 1 };
    case 0xc4: return { kind: 'bin8', length: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xc5: return { kind: 'bin16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xc6: return { kind: 'bin32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xca: return { kind: 'float32', offset: offset + 5 };
    case 0xcb: return { kind: 'float64', offset: offset + 9 };
    case 0xcc: return { kind: 'uint8', offset: offset + 2 };
    case 0xcd: return { kind: 'uint16', offset: offset + 3 };
    case 0xce: return { kind: 'uint32', offset: offset + 5 };
    case 0xcf: return { kind: 'uint64', offset: offset + 9 };
    case 0xd0: return { kind: 'int8', offset: offset + 2 };
    case 0xd1: return { kind: 'int16', offset: offset + 3 };
    case 0xd2: return { kind: 'int32', offset: offset + 5 };
    case 0xd3: return { kind: 'int64', offset: offset + 9 };
    case 0xd9: return { kind: 'str8', length: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xda: return { kind: 'str16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdb: return { kind: 'str32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xdc: return { kind: 'array16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdd: return { kind: 'array32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xde: return { kind: 'map16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdf: return { kind: 'map32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    default:
      throw new Error(`Unsupported msgpack marker 0x${byte.toString(16)} at ${offset}`);
  }
}

function readMsgpackInt(buffer, offset) {
  const byte = buffer[offset];
  if (byte <= 0x7f) return { value: byte, offset: offset + 1 };
  if (byte >= 0xe0) return { value: byte - 0x100, offset: offset + 1 };
  switch (byte) {
    case 0xcc:
      return { value: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xcd:
      return { value: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xce:
      return { value: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xd0:
      return { value: buffer.readInt8(offset + 1), offset: offset + 2 };
    case 0xd1:
      return { value: buffer.readInt16BE(offset + 1), offset: offset + 3 };
    case 0xd2:
      return { value: buffer.readInt32BE(offset + 1), offset: offset + 5 };
    default:
      throw new Error(`Expected msgpack integer at ${offset}, got 0x${byte.toString(16)}`);
  }
}

function encodeMsgpackInt(value) {
  if (Number.isInteger(value) && value >= 0 && value <= 0x7f) {
    return Buffer.from([value]);
  }
  if (Number.isInteger(value) && value >= -32 && value < 0) {
    return Buffer.from([0x100 + value]);
  }
  if (Number.isInteger(value) && value >= 0 && value <= 0xff) {
    return Buffer.from([0xcc, value]);
  }
  if (Number.isInteger(value) && value >= 0 && value <= 0xffff) {
    const out = Buffer.alloc(3);
    out[0] = 0xcd;
    out.writeUInt16BE(value, 1);
    return out;
  }
  if (Number.isInteger(value) && value >= 0 && value <= 0xffffffff) {
    const out = Buffer.alloc(5);
    out[0] = 0xce;
    out.writeUInt32BE(value, 1);
    return out;
  }
  if (Number.isInteger(value) && value >= -0x80 && value < 0) {
    const out = Buffer.alloc(2);
    out[0] = 0xd0;
    out.writeInt8(value, 1);
    return out;
  }
  if (Number.isInteger(value) && value >= -0x8000 && value < -0x80) {
    const out = Buffer.alloc(3);
    out[0] = 0xd1;
    out.writeInt16BE(value, 1);
    return out;
  }
  if (Number.isInteger(value) && value >= -0x80000000 && value < -0x8000) {
    const out = Buffer.alloc(5);
    out[0] = 0xd2;
    out.writeInt32BE(value, 1);
    return out;
  }
  throw new Error(`Cannot encode msgpack integer: ${value}`);
}

function encodeMsgpackArrayHeader(length) {
  if (length >= 0 && length <= 15) {
    return Buffer.from([0x90 | length]);
  }
  if (length <= 0xffff) {
    const out = Buffer.alloc(3);
    out[0] = 0xdc;
    out.writeUInt16BE(length, 1);
    return out;
  }
  const out = Buffer.alloc(5);
  out[0] = 0xdd;
  out.writeUInt32BE(length, 1);
  return out;
}

function readMsgpackBinary(buffer, offset) {
  const marker = readMsgpackMarker(buffer, offset);
  if (!marker.kind.startsWith('bin')) {
    throw new Error(`Expected msgpack binary at ${offset}, got ${marker.kind}`);
  }
  return {
    value: buffer.subarray(marker.offset, marker.offset + marker.length),
    offset: marker.offset + marker.length,
  };
}

function encodeMsgpackBinary(value) {
  const payload = Buffer.from(value || []);
  if (payload.length <= 0xff) {
    return Buffer.concat([Buffer.from([0xc4, payload.length]), payload]);
  }
  if (payload.length <= 0xffff) {
    const header = Buffer.alloc(3);
    header[0] = 0xc5;
    header.writeUInt16BE(payload.length, 1);
    return Buffer.concat([header, payload]);
  }
  const header = Buffer.alloc(5);
  header[0] = 0xc6;
  header.writeUInt32BE(payload.length, 1);
  return Buffer.concat([header, payload]);
}

function skipMsgpackValue(buffer, offset) {
  const marker = readMsgpackMarker(buffer, offset);
  if (marker.kind.startsWith('bin') || marker.kind.includes('str')) {
    return marker.offset + marker.length;
  }
  if (marker.kind.includes('array')) {
    let cursor = marker.offset;
    for (let i = 0; i < marker.length; i++) {
      cursor = skipMsgpackValue(buffer, cursor);
    }
    return cursor;
  }
  if (marker.kind.includes('map')) {
    let cursor = marker.offset;
    for (let i = 0; i < marker.length * 2; i++) {
      cursor = skipMsgpackValue(buffer, cursor);
    }
    return cursor;
  }
  return marker.offset;
}

function readMsgpackArrayHeader(buffer, offset) {
  const marker = readMsgpackMarker(buffer, offset);
  if (!marker.kind.includes('array')) {
    throw new Error(`Expected msgpack array at ${offset}, got ${marker.kind}`);
  }
  return marker;
}

function skipMsgpackArray(buffer, offset, valuesPerItem = 1) {
  const header = readMsgpackArrayHeader(buffer, offset);
  let cursor = header.offset;
  for (let i = 0; i < header.length * valuesPerItem; i++) {
    cursor = skipMsgpackValue(buffer, cursor);
  }
  return { length: header.length, offset: cursor };
}

function isZeroVector(vector) {
  return !vector || (!vector.x && !vector.y && !vector.z);
}

function readEntityChunkIndex(buffer) {
  let cursor = 0;
  const nextPersistentIndex = readMsgpackInt(buffer, cursor);
  cursor = nextPersistentIndex.offset;
  const chunkHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = chunkHeader.offset;
  const chunks = [];
  for (let i = 0; i < chunkHeader.length; i++) {
    const x = readMsgpackInt(buffer, cursor);
    const y = readMsgpackInt(buffer, x.offset);
    const z = readMsgpackInt(buffer, y.offset);
    cursor = z.offset;
    chunks.push({
      x: x.value,
      y: y.value,
      z: z.value,
    });
  }
  const countHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = countHeader.offset;
  const counts = [];
  for (let i = 0; i < countHeader.length; i++) {
    const count = readMsgpackInt(buffer, cursor);
    cursor = count.offset;
    counts.push(count.value);
  }
  return {
    nextPersistentIndex: nextPersistentIndex.value,
    chunks,
    counts,
  };
}

function encodeEntityChunkIndex(index) {
  const parts = [
    encodeMsgpackInt(index.nextPersistentIndex),
    encodeMsgpackArrayHeader(index.chunks.length),
  ];
  for (const chunk of index.chunks) {
    parts.push(encodeMsgpackInt(chunk.x));
    parts.push(encodeMsgpackInt(chunk.y));
    parts.push(encodeMsgpackInt(chunk.z));
  }
  parts.push(encodeMsgpackArrayHeader(index.counts.length));
  for (const count of index.counts) {
    parts.push(encodeMsgpackInt(count));
  }
  return Buffer.concat(parts);
}

function readBrickChunkIndex(buffer) {
  let cursor = 0;
  const chunkHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = chunkHeader.offset;
  const chunks = [];
  for (let i = 0; i < chunkHeader.length; i++) {
    const x = readMsgpackInt(buffer, cursor);
    const y = readMsgpackInt(buffer, x.offset);
    const z = readMsgpackInt(buffer, y.offset);
    cursor = z.offset;
    chunks.push({ x: x.value, y: y.value, z: z.value });
  }

  const offsetHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = offsetHeader.offset;
  const offsets = [];
  for (let i = 0; i < offsetHeader.length; i++) {
    const x = readMsgpackInt(buffer, cursor);
    const y = readMsgpackInt(buffer, x.offset);
    const z = readMsgpackInt(buffer, y.offset);
    cursor = z.offset;
    offsets.push({ x: x.value, y: y.value, z: z.value });
  }

  const sizeHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = sizeHeader.offset;
  const chunkSizes = [];
  for (let i = 0; i < sizeHeader.length; i++) {
    const size = readMsgpackInt(buffer, cursor);
    cursor = size.offset;
    chunkSizes.push(size.value);
  }

  const brickHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = brickHeader.offset;
  const numBricks = [];
  for (let i = 0; i < brickHeader.length; i++) {
    const count = readMsgpackInt(buffer, cursor);
    cursor = count.offset;
    numBricks.push(count.value);
  }

  const componentHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = componentHeader.offset;
  const numComponents = [];
  for (let i = 0; i < componentHeader.length; i++) {
    const count = readMsgpackInt(buffer, cursor);
    cursor = count.offset;
    numComponents.push(count.value);
  }

  const wireHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = wireHeader.offset;
  const numWires = [];
  for (let i = 0; i < wireHeader.length; i++) {
    const count = readMsgpackInt(buffer, cursor);
    cursor = count.offset;
    numWires.push(count.value);
  }

  return {
    chunks,
    offsets,
    chunkSizes,
    numBricks,
    numComponents,
    numWires,
  };
}

function encodeBrickChunkIndex(index) {
  const parts = [encodeMsgpackArrayHeader(index.chunks.length)];
  for (const chunk of index.chunks) {
    parts.push(encodeMsgpackInt(chunk.x));
    parts.push(encodeMsgpackInt(chunk.y));
    parts.push(encodeMsgpackInt(chunk.z));
  }
  parts.push(encodeMsgpackArrayHeader(index.offsets.length));
  for (const offset of index.offsets) {
    parts.push(encodeMsgpackInt(offset.x));
    parts.push(encodeMsgpackInt(offset.y));
    parts.push(encodeMsgpackInt(offset.z));
  }
  parts.push(encodeMsgpackArrayHeader(index.chunkSizes.length));
  for (const size of index.chunkSizes) {
    parts.push(encodeMsgpackInt(size));
  }
  parts.push(encodeMsgpackArrayHeader(index.numBricks.length));
  for (const count of index.numBricks) {
    parts.push(encodeMsgpackInt(count));
  }
  parts.push(encodeMsgpackArrayHeader(index.numComponents.length));
  for (const count of index.numComponents) {
    parts.push(encodeMsgpackInt(count));
  }
  parts.push(encodeMsgpackArrayHeader(index.numWires.length));
  for (const count of index.numWires) {
    parts.push(encodeMsgpackInt(count));
  }
  return Buffer.concat(parts);
}

function readWirePortTarget(buffer, cursor) {
  const brickIndex = readMsgpackInt(buffer, cursor);
  const componentTypeIndex = readMsgpackInt(buffer, brickIndex.offset);
  const portIndex = readMsgpackInt(buffer, componentTypeIndex.offset);
  return {
    value: {
      brickIndexInChunk: brickIndex.value,
      componentTypeIndex: componentTypeIndex.value,
      portIndex: portIndex.value,
    },
    offset: portIndex.offset,
  };
}

function readWireChunk(buffer) {
  let cursor = 0;
  const remoteSourceHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = remoteSourceHeader.offset;
  const remoteWireSources = [];
  for (let i = 0; i < remoteSourceHeader.length; i++) {
    const gridPersistentIndex = readMsgpackInt(buffer, cursor);
    const x = readMsgpackInt(buffer, gridPersistentIndex.offset);
    const y = readMsgpackInt(buffer, x.offset);
    const z = readMsgpackInt(buffer, y.offset);
    const portTarget = readWirePortTarget(buffer, z.offset);
    cursor = portTarget.offset;
    remoteWireSources.push({
      gridPersistentIndex: gridPersistentIndex.value,
      chunkIndex: { x: x.value, y: y.value, z: z.value },
      ...portTarget.value,
    });
  }

  const localSourceHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = localSourceHeader.offset;
  const localWireSources = [];
  for (let i = 0; i < localSourceHeader.length; i++) {
    const source = readWirePortTarget(buffer, cursor);
    cursor = source.offset;
    localWireSources.push(source.value);
  }

  const remoteTargetHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = remoteTargetHeader.offset;
  const remoteWireTargets = [];
  for (let i = 0; i < remoteTargetHeader.length; i++) {
    const target = readWirePortTarget(buffer, cursor);
    cursor = target.offset;
    remoteWireTargets.push(target.value);
  }

  const localTargetHeader = readMsgpackArrayHeader(buffer, cursor);
  cursor = localTargetHeader.offset;
  const localWireTargets = [];
  for (let i = 0; i < localTargetHeader.length; i++) {
    const target = readWirePortTarget(buffer, cursor);
    cursor = target.offset;
    localWireTargets.push(target.value);
  }

  const pendingPropagationFlags = readMsgpackBinary(buffer, cursor);
  return {
    remoteWireSources,
    localWireSources,
    remoteWireTargets,
    localWireTargets,
    pendingPropagationFlags: pendingPropagationFlags.value,
  };
}

function encodeWirePortTarget(target) {
  return Buffer.concat([
    encodeMsgpackInt(target.brickIndexInChunk),
    encodeMsgpackInt(target.componentTypeIndex),
    encodeMsgpackInt(target.portIndex),
  ]);
}

function encodeWireChunk(chunk) {
  const parts = [encodeMsgpackArrayHeader(chunk.remoteWireSources.length)];
  for (const source of chunk.remoteWireSources) {
    parts.push(encodeMsgpackInt(source.gridPersistentIndex));
    parts.push(encodeMsgpackInt(source.chunkIndex.x));
    parts.push(encodeMsgpackInt(source.chunkIndex.y));
    parts.push(encodeMsgpackInt(source.chunkIndex.z));
    parts.push(encodeWirePortTarget(source));
  }
  parts.push(encodeMsgpackArrayHeader(chunk.localWireSources.length));
  for (const source of chunk.localWireSources) {
    parts.push(encodeWirePortTarget(source));
  }
  parts.push(encodeMsgpackArrayHeader(chunk.remoteWireTargets.length));
  for (const target of chunk.remoteWireTargets) {
    parts.push(encodeWirePortTarget(target));
  }
  parts.push(encodeMsgpackArrayHeader(chunk.localWireTargets.length));
  for (const target of chunk.localWireTargets) {
    parts.push(encodeWirePortTarget(target));
  }
  parts.push(encodeMsgpackBinary(chunk.pendingPropagationFlags));
  return Buffer.concat(parts);
}

function getFileRow(db, filePath) {
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
    SELECT files.file_id
    FROM files
    JOIN folder_path ON files.parent_id = folder_path.folder_id
    WHERE folder_path.path || '/' || files.name = ?
  `).get(filePath);
  return row || null;
}

function fileExists(db, filePath) {
  return Boolean(getFileRow(db, filePath));
}

function updateFileName(db, filePath, newName) {
  const row = getFileRow(db, filePath);
  if (!row) {
    throw new Error(`Cannot rename missing file: ${filePath}`);
  }
  db.prepare('UPDATE files SET name = ? WHERE file_id = ?').run(newName, row.file_id);
}

function applyFileRenames(db, renames) {
  const uniqueRenames = renames.filter((rename) => rename.oldName !== rename.newName);
  const tempNames = uniqueRenames.map((rename, index) => ({
    ...rename,
    tempName: `.__prefab_move_${process.pid}_${Date.now()}_${index}_${rename.oldName}`,
  }));
  for (const rename of tempNames) {
    updateFileName(db, `${rename.dir}/${rename.oldName}`, rename.tempName);
  }
  for (const rename of tempNames) {
    updateFileName(db, `${rename.dir}/${rename.tempName}`, rename.newName);
  }
}

function translateBrickChunkIndexes(db, vector) {
  if (isZeroVector(vector)) {
    return { grids: 0, chunks: 0 };
  }

  const indexPaths = listFiles(db, 'World/0/Bricks/Grids/')
    .filter((filePath) => /\/ChunkIndex\.mps$/.test(filePath));
  const entries = indexPaths.map((indexPath) => ({
    indexPath,
    indexBlob: readBlob(db, indexPath),
  })).filter((entry) => entry.indexBlob);
  let chunkCount = 0;
  const blobWrites = new Map();
  const chunkDeltaByGrid = new Map();

  for (const { indexPath, indexBlob } of entries) {
    const parsed = readBrickChunkIndex(indexBlob.content);
    const gridDir = path.posix.dirname(indexPath);
    const gridPersistentIndex = Number(gridDir.match(/\/Grids\/(\d+)$/)?.[1]);
    const renames = [];
    let gridDelta = null;

    for (let i = 0; i < parsed.chunks.length; i++) {
      const oldChunk = parsed.chunks[i];
      const oldOffset = parsed.offsets[i];
      const size = parsed.chunkSizes[i];
      if (!oldOffset || !Number.isFinite(size) || size <= 0) {
        throw new Error(`Invalid brick chunk index entry in ${indexPath}`);
      }

      const nextChunk = {
        x: oldChunk.x + Math.round(vector.x / size),
        y: oldChunk.y + Math.round(vector.y / size),
        z: oldChunk.z + Math.round(vector.z / size),
      };
      const chunkDelta = {
        x: nextChunk.x - oldChunk.x,
        y: nextChunk.y - oldChunk.y,
        z: nextChunk.z - oldChunk.z,
      };
      if (!gridDelta) {
        gridDelta = chunkDelta;
      } else if (
        gridDelta.x !== chunkDelta.x ||
        gridDelta.y !== chunkDelta.y ||
        gridDelta.z !== chunkDelta.z
      ) {
        throw new Error(`Inconsistent brick chunk delta in ${indexPath}`);
      }

      const oldName = `${oldChunk.x}_${oldChunk.y}_${oldChunk.z}.mps`;
      const newName = `${nextChunk.x}_${nextChunk.y}_${nextChunk.z}.mps`;
      for (const subdir of ['Chunks', 'Components', 'Wires']) {
        const dir = `${gridDir}/${subdir}`;
        if (fileExists(db, `${dir}/${oldName}`)) {
          renames.push({ dir, oldName, newName });
        }
      }

      parsed.chunks[i] = nextChunk;
      chunkCount++;
    }

    if (Number.isFinite(gridPersistentIndex) && gridDelta) {
      chunkDeltaByGrid.set(gridPersistentIndex, gridDelta);
    }
    applyFileRenames(db, renames);
    if (!blobWrites.has(indexBlob.blob_id)) {
      blobWrites.set(indexBlob.blob_id, {
        compression: indexBlob.compression,
        content: encodeBrickChunkIndex(parsed),
      });
    }
  }

  for (const [blobId, write] of blobWrites) {
    writeBlob(db, blobId, write.compression, write.content);
  }

  translateWireChunkReferences(db, chunkDeltaByGrid);

  return { grids: indexPaths.length, chunks: chunkCount };
}

function translateWireChunkReferences(db, chunkDeltaByGrid) {
  if (!chunkDeltaByGrid.size) {
    return { chunks: 0, remoteSources: 0 };
  }

  const wirePaths = listFiles(db, 'World/0/Bricks/Grids/')
    .filter((filePath) => /\/Wires\/.+\.mps$/.test(filePath));
  const entries = wirePaths.map((filePath) => ({
    filePath,
    blob: readBlob(db, filePath),
  })).filter((entry) => entry.blob);
  const blobWrites = new Map();
  let remoteSources = 0;

  for (const { blob } of entries) {
    if (blobWrites.has(blob.blob_id)) {
      continue;
    }
    const parsed = readWireChunk(blob.content);
    let changed = false;
    for (const source of parsed.remoteWireSources) {
      const delta = chunkDeltaByGrid.get(source.gridPersistentIndex);
      if (!delta) {
        continue;
      }
      source.chunkIndex = {
        x: source.chunkIndex.x + delta.x,
        y: source.chunkIndex.y + delta.y,
        z: source.chunkIndex.z + delta.z,
      };
      changed = true;
      remoteSources++;
    }
    if (changed) {
      blobWrites.set(blob.blob_id, {
        compression: blob.compression,
        content: encodeWireChunk(parsed),
      });
    }
  }

  for (const [blobId, write] of blobWrites) {
    writeBlob(db, blobId, write.compression, write.content);
  }

  return { chunks: blobWrites.size, remoteSources };
}

function translateEntityChunkIndex(db, vector) {
  if (isZeroVector(vector)) {
    return { chunks: 0 };
  }

  const indexBlob = readBlob(db, 'World/0/Entities/ChunkIndex.mps');
  if (!indexBlob) {
    return { chunks: 0 };
  }

  const parsed = readEntityChunkIndex(indexBlob.content);
  const renames = [];
  for (const chunk of parsed.chunks) {
    const next = {
      x: chunk.x + vector.x,
      y: chunk.y + vector.y,
      z: chunk.z + vector.z,
    };

    const oldName = `${chunk.x}_${chunk.y}_${chunk.z}.mps`;
    const newName = `${next.x}_${next.y}_${next.z}.mps`;
    if (fileExists(db, `World/0/Entities/Chunks/${oldName}`)) {
      renames.push({ dir: 'World/0/Entities/Chunks', oldName, newName });
    }
    chunk.x = next.x;
    chunk.y = next.y;
    chunk.z = next.z;
  }

  applyFileRenames(db, renames);
  writeBlob(db, indexBlob.blob_id, indexBlob.compression, encodeEntityChunkIndex(parsed));
  return { chunks: parsed.chunks.length };
}

function entityChunkOffsetFromPlacementOffset(vector) {
  if (isZeroVector(vector)) {
    return null;
  }
  return {
    x: Math.round(vector.x / ENTITY_CHUNK_WORLD_SIZE),
    y: Math.round(vector.y / ENTITY_CHUNK_WORLD_SIZE),
    z: Math.round(vector.z / ENTITY_CHUNK_WORLD_SIZE),
  };
}

function getRootFolderId(db) {
  const row = db.prepare('SELECT folder_id FROM folders WHERE parent_id IS NULL LIMIT 1').get();
  if (!row) {
    throw new Error('BRDB does not contain a root folder');
  }
  return row.folder_id;
}

function ensureFolder(db, parentId, name) {
  const existing = db.prepare('SELECT folder_id FROM folders WHERE parent_id IS ? AND name = ? AND deleted_at IS NULL LIMIT 1').get(parentId, name);
  if (existing) {
    return existing.folder_id;
  }
  const nextId = (db.prepare('SELECT COALESCE(MAX(folder_id), 0) + 1 AS nextId FROM folders').get().nextId);
  db.prepare('INSERT INTO folders (folder_id, parent_id, name, created_at, deleted_at) VALUES (?, ?, ?, ?, NULL)').run(nextId, parentId, name, 1);
  return nextId;
}

function ensureFolderPath(db, folderPath) {
  const parts = folderPath.split('/').filter(Boolean);
  if (parts.length === 0 || (parts.length === 1 && parts[0] === '.')) {
    return null;
  }
  let currentId = null;
  for (const part of parts) {
    currentId = ensureFolder(db, currentId, part);
  }
  return currentId;
}

function writeJsonFile(db, filePath, value) {
  const parentPath = path.posix.dirname(filePath);
  const fileName = path.posix.basename(filePath);
  const parentId = ensureFolderPath(db, parentPath);
  const jsonBuffer = Buffer.from(JSON.stringify(value, null, 2), 'utf8');
  const nextBlobId = db.prepare('SELECT COALESCE(MAX(blob_id), 0) + 1 AS nextId FROM blobs').get().nextId;
  db.prepare(`
    INSERT INTO blobs (blob_id, compression, size_uncompressed, size_compressed, delta_base_id, hash, content)
    VALUES (?, 0, ?, ?, NULL, ?, ?)
  `).run(nextBlobId, jsonBuffer.length, jsonBuffer.length, null, jsonBuffer);

  const existing = db.prepare('SELECT file_id FROM files WHERE parent_id = ? AND name = ? AND deleted_at IS NULL LIMIT 1').get(parentId, fileName);
  if (existing) {
    db.prepare('UPDATE files SET content_id = ? WHERE file_id = ?').run(nextBlobId, existing.file_id);
    return;
  }
  const nextFileId = db.prepare('SELECT COALESCE(MAX(file_id), 0) + 1 AS nextId FROM files').get().nextId;
  db.prepare('INSERT INTO files (file_id, parent_id, name, content_id, created_at, deleted_at) VALUES (?, ?, ?, ?, ?, NULL)').run(nextFileId, parentId, fileName, nextBlobId, 1);
}

function normalizeBundle(bundle, fallbackName, bundleType = 'World') {
  const id = bundle?.id || bundle?.iD || '00000000-0000-0000-0000-000000000000';
  const type = bundleType === 'preserve'
    ? (bundle?.type || 'World')
    : bundleType;
  return {
    type,
    id,
    name: bundle?.name || fallbackName || '',
    version: bundle?.version || '',
    tags: Array.isArray(bundle?.tags) ? bundle.tags : [],
    authors: Array.isArray(bundle?.authors)
      ? bundle.authors.map((author) => ({
          id: author.id || author.iD || '00000000-0000-0000-0000-000000000000',
          name: author.name || '',
        }))
      : [],
    createdAt: bundle?.createdAt || '0001.01.01-00.00.00',
    updatedAt: bundle?.updatedAt || bundle?.createdAt || '0001.01.01-00.00.00',
    description: bundle?.description || '',
    dependencies: Array.isArray(bundle?.dependencies) ? bundle.dependencies : [],
    gameVersion: bundle?.gameVersion || '',
  };
}

function shouldPatchPhysicsMetadata(report, prefabMeta) {
  return Boolean(
    report
      && prefabMeta
      && prefabMeta.bIsPhysicsGrid !== true
      && report.entity
      && report.entity.total_entities > 0
      && report.joints
      && report.joints.total_joint_entity_references > 0,
  );
}

function buildPrefabWorldBrdb(inputBrzPath, outputBrdbPath, options = {}) {
  const environment = options.environment || 'Plate';
  const force = Boolean(options.force);
  const bundleType = options.bundleType || 'World';
  const patchPhysicsMetadata = options.patchPhysicsMetadata === true;
  const entityChunkOffset = options.entityChunkOffset ||
    entityChunkOffsetFromPlacementOffset(options.placementOffset);
  const sourceName = options.name || path.basename(inputBrzPath, path.extname(inputBrzPath));

  if (!force && fs.existsSync(outputBrdbPath)) {
    throw new Error(`Refusing to overwrite existing output: ${outputBrdbPath}`);
  }

  fs.mkdirSync(path.dirname(outputBrdbPath), { recursive: true });
  const sourcePrefabReport = patchPhysicsMetadata ? diagnose(inputBrzPath) : null;
  convertBrzToBrdb(inputBrzPath, outputBrdbPath);

  const db = new Database(outputBrdbPath);
  try {
    const sourceBundle = readBlobJson(db, 'Meta/Bundle.json');
    const sourcePrefabMeta = readBlobJson(db, 'Meta/Prefab.json');
    const worldBundle = normalizeBundle(sourceBundle, sourceName, bundleType);
    const worldMeta = { environment };

    const tx = db.transaction(() => {
      writeJsonFile(db, 'Meta/Bundle.json', worldBundle);
      writeJsonFile(db, 'Meta/World.json', worldMeta);
      if (shouldPatchPhysicsMetadata(sourcePrefabReport, sourcePrefabMeta)) {
        writeJsonFile(
          db,
          'Meta/Prefab.json',
          patchMetadata(sourcePrefabMeta, sourcePrefabReport, { identityWorldRoot: true }),
        );
      }
      translateBrickChunkIndexes(db, options.placementOffset);
      translateEntityChunkIndex(db, entityChunkOffset);
    });
    tx();
  } finally {
    db.close();
  }

  return outputBrdbPath;
}

function usage() {
  console.error('Usage: node build-prefab-world-brdb.js <input.brz> <output.brdb> [environment] [--placement-offset <x> <y> <z>] [--entity-chunk-offset <x> <y> <z>] [--bundle-type <World|Prefab|preserve>] [--patch-physics-metadata]');
}

function readVectorArg(argv, flag) {
  const index = argv.indexOf(flag);
  if (index < 0) {
    return null;
  }
  const values = argv.slice(index + 1, index + 4).map(Number);
  if (values.length !== 3 || values.some((value) => !Number.isFinite(value))) {
    throw new Error(`${flag} requires three numeric values`);
  }
  argv.splice(index, 4);
  return { x: values[0], y: values[1], z: values[2] };
}

function readValueArg(argv, flag) {
  const index = argv.indexOf(flag);
  if (index < 0) {
    return null;
  }
  const value = argv[index + 1];
  if (!value || value.startsWith('--')) {
    throw new Error(`${flag} requires a value`);
  }
  argv.splice(index, 2);
  return value;
}

function normalizeBundleTypeArg(value) {
  if (value == null || value === '') {
    return 'World';
  }
  const lower = String(value).toLowerCase();
  if (lower === 'preserve') {
    return 'preserve';
  }
  if (lower === 'world') {
    return 'World';
  }
  if (lower === 'prefab') {
    return 'Prefab';
  }
  throw new Error(`Unsupported --bundle-type: ${value}`);
}

function main(argv) {
  let entityChunkOffset;
  let placementOffset;
  let bundleType;
  let patchPhysicsMetadata = false;
  try {
    placementOffset = readVectorArg(argv, '--placement-offset');
    entityChunkOffset = readVectorArg(argv, '--entity-chunk-offset');
    bundleType = normalizeBundleTypeArg(readValueArg(argv, '--bundle-type'));
    if (argv.includes('--patch-physics-metadata')) {
      patchPhysicsMetadata = true;
      argv.splice(argv.indexOf('--patch-physics-metadata'), 1);
    }
  } catch (error) {
    console.error(error.message);
    usage();
    process.exitCode = 1;
    return;
  }
  const [inputBrzPath, outputBrdbPath, environment] = argv;
  if (!inputBrzPath || !outputBrdbPath) {
    usage();
    process.exitCode = 1;
    return;
  }
  const out = buildPrefabWorldBrdb(inputBrzPath, outputBrdbPath, {
    environment: environment || 'Plate',
    force: true,
    placementOffset,
    entityChunkOffset,
    bundleType,
    patchPhysicsMetadata,
  });
  console.log(out);
}

module.exports = {
  ENTITY_CHUNK_WORLD_SIZE,
  buildPrefabWorldBrdb,
  entityChunkOffsetFromPlacementOffset,
  readBrickChunkIndex,
  readEntityChunkIndex,
  readWireChunk,
  shouldPatchPhysicsMetadata,
};

if (require.main === module) {
  main(process.argv.slice(2));
}
