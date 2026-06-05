#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { extractArchive, parseBrz } = require('./inspect-brz.js');

const LOCALAPPDATA = process.env.LOCALAPPDATA || '';
const DEFAULT_CLIPBOARD = LOCALAPPDATA
  ? path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'Temp', 'Clipboard.brz')
  : null;
const DEFAULT_GALLERY_DIR = LOCALAPPDATA
  ? path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'GalleryCache', 'Prefabs')
  : null;
const INSPECT_SCHEMA = path.join(__dirname, 'inspect-brdb-schema.js');

function usage() {
  console.error([
    'usage: node diagnose-prefab-vehicle-structure.js [input.brz] [options]',
    '',
    'Options:',
    '  --out-json <path>   Optional JSON report path',
    '  --scan-gallery [dir]  List local gallery prefabs with physics/entity summaries',
  ].join('\n'));
  process.exit(2);
}

function parseArgs(argv) {
  const out = { input: null, scanGallery: false, galleryDir: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--scan-gallery') {
      out.scanGallery = true;
      const value = argv[i + 1];
      if (value && !value.startsWith('--')) {
        out.galleryDir = value;
        i += 1;
      }
      continue;
    }
    if (!arg.startsWith('--') && !out.input) {
      out.input = arg;
      continue;
    }
    if (arg === '--out-json') {
      const value = argv[i + 1];
      if (!value || value.startsWith('--')) usage();
      out.outJson = value;
      i += 1;
      continue;
    }
    usage();
  }
  out.input = out.input ? path.resolve(out.input) : path.resolve(DEFAULT_CLIPBOARD || '');
  out.galleryDir = path.resolve(out.galleryDir || DEFAULT_GALLERY_DIR || '');
  return out;
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
  return results.sort();
}

function decode(schemaPath, dataPath, typeName) {
  const raw = execFileSync(
    process.execPath,
    [INSPECT_SCHEMA, schemaPath, dataPath, typeName],
    {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    },
  );
  return JSON.parse(raw);
}

function schemaSummary(schemaPath) {
  const raw = execFileSync(
    process.execPath,
    [INSPECT_SCHEMA, schemaPath],
    {
      encoding: 'utf8',
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  return JSON.parse(raw);
}

function sum(list, field) {
  return (list || []).reduce((acc, item) => acc + (typeof item === 'number' ? item : Number(item && item[field]) || 0), 0);
}

function bounds(vectors) {
  if (!vectors || vectors.length === 0) return null;
  const initial = {
    min: { X: Infinity, Y: Infinity, Z: Infinity },
    max: { X: -Infinity, Y: -Infinity, Z: -Infinity },
  };
  return vectors.reduce((acc, vector) => {
    for (const axis of ['X', 'Y', 'Z']) {
      acc.min[axis] = Math.min(acc.min[axis], Number(vector[axis]));
      acc.max[axis] = Math.max(acc.max[axis], Number(vector[axis]));
    }
    return acc;
  }, initial);
}

function readMsgpackMarker(buffer, offset) {
  const byte = buffer[offset];
  if (byte == null) return null;
  if (byte <= 0x7f) return { kind: 'fixpos', value: byte, offset: offset + 1 };
  if (byte >= 0xe0) return { kind: 'fixneg', value: byte - 0x100, offset: offset + 1 };
  if ((byte & 0xe0) === 0xa0) return { kind: 'fixstr', length: byte & 0x1f, offset: offset + 1 };
  if ((byte & 0xf0) === 0x90) return { kind: 'fixarray', length: byte & 0x0f, offset: offset + 1 };
  if ((byte & 0xf0) === 0x80) return { kind: 'fixmap', length: byte & 0x0f, offset: offset + 1 };
  switch (byte) {
    case 0xc0: return { kind: 'nil', offset: offset + 1 };
    case 0xc2: return { kind: 'false', value: false, offset: offset + 1 };
    case 0xc3: return { kind: 'true', value: true, offset: offset + 1 };
    case 0xc4: return { kind: 'bin8', length: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xc5: return { kind: 'bin16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xc6: return { kind: 'bin32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xcc: return { kind: 'uint8', value: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xcd: return { kind: 'uint16', value: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xce: return { kind: 'uint32', value: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xd0: return { kind: 'int8', value: buffer.readInt8(offset + 1), offset: offset + 2 };
    case 0xd1: return { kind: 'int16', value: buffer.readInt16BE(offset + 1), offset: offset + 3 };
    case 0xd2: return { kind: 'int32', value: buffer.readInt32BE(offset + 1), offset: offset + 5 };
    case 0xda: return { kind: 'str16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdb: return { kind: 'str32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xdc: return { kind: 'array16', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdd: return { kind: 'array32', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    default: return { kind: 'unknown', value: byte, offset: offset + 1 };
  }
}

function scanTail(buffer, offset) {
  const markers = [];
  let cursor = offset;
  while (cursor < buffer.length && markers.length < 16) {
    const marker = readMsgpackMarker(buffer, cursor);
    if (!marker) break;
    const entry = {
      offset: cursor,
      kind: marker.kind,
    };
    if (marker.length != null) entry.length = marker.length;
    if (marker.value != null) entry.value = marker.value;
    markers.push(entry);
    if (marker.length != null && (marker.kind.startsWith('bin') || marker.kind.includes('str'))) {
      cursor = marker.offset + marker.length;
    } else {
      cursor = marker.offset;
    }
  }
  return markers;
}

function summarizeEntityTail(chunkBuffer, genericOffset, entityCount) {
  const markers = scanTail(chunkBuffer, genericOffset);
  const blobLengths = markers
    .filter((marker) => marker.kind.startsWith('bin'))
    .map((marker) => marker.length);
  const expectedGenericBlobLengths = [
    entityCount * 12,
    entityCount * 12,
    entityCount * 32,
  ];
  const genericBlobBytes = blobLengths.slice(0, 3).reduce((acc, value) => acc + value, 0);
  let cursor = genericOffset;
  for (const marker of markers.slice(0, 3)) {
    if (!marker.kind.startsWith('bin')) break;
    const parsed = readMsgpackMarker(chunkBuffer, cursor);
    cursor = parsed.offset + parsed.length;
  }
  const customBytes = cursor <= chunkBuffer.length ? chunkBuffer.subarray(cursor) : Buffer.alloc(0);
  return {
    decoded_generic_offset: genericOffset,
    marker_summary: markers,
    blob_lengths: blobLengths,
    expected_generic_blob_lengths: expectedGenericBlobLengths,
    generic_blob_lengths_match: expectedGenericBlobLengths.every((expected, index) => blobLengths[index] === expected),
    custom_tail_bytes_after_generic_blobs: customBytes.length,
    custom_tail_hex: customBytes.subarray(0, 64).toString('hex').toUpperCase(),
    generic_blob_bytes: genericBlobBytes,
  };
}

function inferEntityRanges(entityChunk) {
  const counters = entityChunk.TypeCounters || [];
  const persistent = entityChunk.PersistentIndices || [];
  const locations = entityChunk.Locations || [];
  let cursor = 0;
  return counters.map((counter) => {
    const count = Number(counter.NumEntities) || 0;
    const rangePersistent = persistent.slice(cursor, cursor + count);
    const rangeLocations = locations.slice(cursor, cursor + count);
    cursor += count;
    return {
      type_index: counter.TypeIndex,
      count,
      persistent_indices: rangePersistent,
      location_bounds: bounds(rangeLocations),
      sample_locations: rangeLocations.slice(0, 6),
    };
  });
}

function uniqueSorted(values) {
  return Array.from(new Set((values || []).filter((value) => value != null))).sort((left, right) => left - right);
}

function findFirst(files, regex) {
  return files.find((file) => regex.test(file)) || null;
}

function gridSummary(rootDir, files, gridId, persistentEntitySet) {
  const gridRoot = `World/0/Bricks/Grids/${gridId}`;
  const indexPath = `${gridRoot}/ChunkIndex.mps`;
  const index = decode(
    path.join(rootDir, 'World', '0', 'Bricks', 'ChunkIndexShared.schema'),
    path.join(rootDir, indexPath),
    'BRSavedBrickChunkIndexSoA',
  ).decoded.value;
  const componentPath = findFirst(files, new RegExp(`^${gridRoot}/Components/.+\\.mps$`));
  let component = null;
  if (componentPath) {
    const decoded = decode(
      path.join(rootDir, 'World', '0', 'Bricks', 'ComponentsShared.schema'),
      path.join(rootDir, componentPath),
      'BRSavedComponentChunkSoA',
    ).decoded.value;
    const jointRefs = decoded.JointEntityReferences || [];
    component = {
      path: componentPath,
      type_counters: decoded.ComponentTypeCounters || [],
      component_brick_indices: decoded.ComponentBrickIndices ? decoded.ComponentBrickIndices.length : 0,
      joint_brick_indices: decoded.JointBrickIndices || [],
      joint_entity_references: jointRefs,
      unique_joint_entity_references: uniqueSorted(jointRefs),
      missing_joint_entity_references: uniqueSorted(jointRefs.filter((ref) => !persistentEntitySet.has(ref))),
      microchip_grid_references: uniqueSorted(decoded.MicrochipBrickGridReferences || []),
    };
  }

  return {
    grid_id: Number(gridId),
    chunks: index.Chunk3DIndices || [],
    chunk_offsets: index.ChunkOffsets || [],
    chunk_sizes: index.ChunkSizes || [],
    brick_count: sum(index.NumBricks || []),
    component_count: sum(index.NumComponents || []),
    wire_count: sum(index.NumWires || []),
    component,
  };
}

function diagnose(inputPath) {
  if (!inputPath || !fs.existsSync(inputPath)) {
    throw new Error(`Missing BRZ input: ${inputPath}`);
  }
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'prefab-vehicle-diag-'));
  try {
    extractArchive(parseBrz(inputPath), tempDir);
    const files = listRelativeFiles(tempDir);
    const bundlePath = path.join(tempDir, 'Meta', 'Bundle.json');
    const bundle = fs.existsSync(bundlePath) ? JSON.parse(fs.readFileSync(bundlePath, 'utf8')) : {};
    const metaPath = path.join(tempDir, 'Meta', 'Prefab.json');
    const meta = fs.existsSync(metaPath) ? JSON.parse(fs.readFileSync(metaPath, 'utf8')) : {};

    const entityIndexPath = 'World/0/Entities/ChunkIndex.mps';
    const entityIndex = files.includes(entityIndexPath)
      ? decode(
        path.join(tempDir, 'World', '0', 'Entities', 'ChunkIndex.schema'),
        path.join(tempDir, entityIndexPath),
        'BRSavedEntityChunkIndexSoA',
      ).decoded.value
      : null;

    const entityChunkPath = findFirst(files, /^World\/0\/Entities\/Chunks\/.+\.mps$/);
    let entity = null;
    let persistentEntitySet = new Set();
    if (entityChunkPath) {
      const decodedEntity = decode(
        path.join(tempDir, 'World', '0', 'Entities', 'ChunksShared.schema'),
        path.join(tempDir, entityChunkPath),
        'BRSavedEntityChunkSoA',
      );
      const entityChunk = decodedEntity.decoded.value;
      const entityCount = sum(entityChunk.TypeCounters || [], 'NumEntities');
      persistentEntitySet = new Set(entityChunk.PersistentIndices || []);
      const schema = schemaSummary(path.join(tempDir, 'World', '0', 'Entities', 'ChunksShared.schema'));
      const chunkBuffer = fs.readFileSync(path.join(tempDir, entityChunkPath));
      entity = {
        chunk_path: entityChunkPath,
        schema_struct_names: schema.structNames,
        entity_type_struct_names: schema.structNames.filter((name) => !/^BRSaved/.test(name) && name !== 'Quat4f' && name !== 'Vector3f'),
        total_entities: entityCount,
        type_counters: entityChunk.TypeCounters || [],
        persistent_indices: entityChunk.PersistentIndices || [],
        owner_indices: entityChunk.OwnerIndices || [],
        original_owner_indices: entityChunk.OriginalOwnerIndices || [],
        location_bounds: bounds(entityChunk.Locations || []),
        inferred_type_ranges: inferEntityRanges(entityChunk),
        tail: summarizeEntityTail(chunkBuffer, decodedEntity.decoded.offset, entityCount),
      };
    }

    const gridIds = uniqueSorted(files
      .map((file) => {
        const match = file.match(/^World\/0\/Bricks\/Grids\/(\d+)\/ChunkIndex\.mps$/);
        return match ? Number(match[1]) : null;
      })
      .filter((value) => value != null));
    const grids = gridIds.map((gridId) => gridSummary(tempDir, files, gridId, persistentEntitySet));
    const allJointRefs = grids.flatMap((grid) => (grid.component && grid.component.joint_entity_references) || []);
    const warnings = [];
    if (meta.bIsPhysicsGrid !== true && entity && entity.total_entities > 0 && allJointRefs.length > 0) {
      warnings.push('Prefab contains dynamic entity/joint data, but Meta/Prefab.json has bIsPhysicsGrid=false.');
    }
    const missingJointRefs = uniqueSorted(allJointRefs.filter((ref) => !persistentEntitySet.has(ref)));
    if (missingJointRefs.length > 0) {
      warnings.push(`JointEntityReferences include missing entity ids: ${missingJointRefs.join(',')}.`);
    }
    if (entity && !entity.tail.generic_blob_lengths_match) {
      warnings.push('Entity generic velocity/color tail blob lengths do not match the entity count.');
    }

    return {
      input: inputPath,
      bundle: {
        name: bundle.name || null,
        type: bundle.type || null,
        id: bundle.id || bundle.iD || null,
        gameVersion: bundle.gameVersion || null,
      },
      meta: {
        brickCount: meta.brickCount ?? null,
        componentCount: meta.componentCount ?? null,
        entityCount: meta.entityCount ?? null,
        wireCount: meta.wireCount ?? null,
        bIsPhysicsGrid: meta.bIsPhysicsGrid ?? null,
        bFreezePhysicsGrid: meta.bFreezePhysicsGrid ?? null,
        addedGlobalGridOffset: meta.addedGlobalGridOffset || null,
        worldRootTransform: meta.worldRootTransform || null,
      },
      entity_index: entityIndex,
      entity,
      grids,
      joints: {
        total_joint_entity_references: allJointRefs.length,
        unique_joint_entity_references: uniqueSorted(allJointRefs),
        missing_joint_entity_references: missingJointRefs,
      },
      warnings,
    };
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function summarizeReport(report) {
  const grids = report.grids || [];
  return {
    input: report.input,
    file: path.basename(report.input || ''),
    name: report.bundle?.name || path.basename(report.input || '', path.extname(report.input || '')),
    bIsPhysicsGrid: report.meta?.bIsPhysicsGrid === true,
    brickCount: report.meta?.brickCount ?? sum(grids, 'brick_count'),
    componentCount: report.meta?.componentCount ?? sum(grids, 'component_count'),
    entityCount: report.meta?.entityCount ?? report.entity?.total_entities ?? null,
    wireCount: report.meta?.wireCount ?? sum(grids, 'wire_count'),
    entityTypes: report.entity?.entity_type_struct_names || [],
    jointEntityReferences: report.joints?.total_joint_entity_references || 0,
    warnings: report.warnings || [],
  };
}

function scanGallery(galleryDir) {
  if (!galleryDir || !fs.existsSync(galleryDir)) {
    throw new Error(`Missing gallery prefab directory: ${galleryDir}`);
  }
  const entries = fs.readdirSync(galleryDir)
    .filter((name) => /\.brz$/i.test(name))
    .sort();
  return {
    gallery_dir: galleryDir,
    prefabs: entries.map((name) => summarizeReport(diagnose(path.join(galleryDir, name)))),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const report = args.scanGallery ? scanGallery(args.galleryDir) : diagnose(args.input);
  const json = `${JSON.stringify(report, null, 2)}\n`;
  if (args.outJson) {
    const outPath = path.resolve(args.outJson);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, json, 'utf8');
  }
  process.stdout.write(json);
}

if (require.main === module) {
  main();
}

module.exports = {
  diagnose,
  scanGallery,
  summarizeReport,
};
