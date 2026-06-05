#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const vm = require('vm');
const Module = require('module');
const Database = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/better-sqlite3');
const {
  readBrickChunkIndex,
  readEntityChunkIndex,
} = require('./build-prefab-world-brdb.js');

const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..');
const BRDB_JS_PATH = path.join(
  WORKSPACE_ROOT,
  'omegga-master',
  'omegga-master',
  'dist',
  'util',
  'brdb.js',
);

function usage() {
  console.error(
    [
      'Usage:',
      '  node list-world-entities.js <input.brdb> [--out-json <path>] [--entity-id <id>]',
      '',
      'Lists saved entity records from a Brickadia world bundle.',
    ].join('\n'),
  );
}

function parseArgs(argv) {
  const out = { input: null, outJson: null, entityId: null };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--out-json') {
      const value = argv[i + 1];
      if (!value || value.startsWith('--')) {
        usage();
        process.exit(2);
      }
      out.outJson = path.resolve(value);
      i++;
      continue;
    }
    if (arg === '--entity-id') {
      const value = argv[i + 1];
      if (!value || value.startsWith('--') || !Number.isFinite(Number(value))) {
        usage();
        process.exit(2);
      }
      out.entityId = Math.round(Number(value));
      i++;
      continue;
    }
    if (!arg.startsWith('--') && !out.input) {
      out.input = path.resolve(arg);
      continue;
    }
    usage();
    process.exit(2);
  }
  if (!out.input) {
    usage();
    process.exit(2);
  }
  return out;
}

function loadBrdbInternals() {
  const source = fs.readFileSync(BRDB_JS_PATH, 'utf8');
  const localRequire = Module.createRequire(BRDB_JS_PATH);
  const module = { exports: {} };
  const sandbox = {
    require: localRequire,
    module,
    exports: module.exports,
    __filename: BRDB_JS_PATH,
    __dirname: path.dirname(BRDB_JS_PATH),
    console,
    Buffer,
    process,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
  };
  vm.runInNewContext(
    `${source}\nmodule.exports.__private = { readBrdbSchema };\n`,
    sandbox,
    { filename: BRDB_JS_PATH },
  );
  return module.exports.__private;
}

function readBundleFile(db, filePath) {
  const row = db
    .prepare(
      `WITH RECURSIVE folder_path(folder_id, path) AS (
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
        AND files.deleted_at IS NULL`,
    )
    .get(filePath);
  if (!row) return null;
  if (row.compression === 1) {
    return zlib.zstdDecompressSync(row.content, {
      maxOutputLength: row.size_uncompressed,
      params: {},
    });
  }
  return row.content;
}

function listBundleFiles(db, prefix = '') {
  return db
    .prepare(
      `WITH RECURSIVE folder_path(folder_id, path) AS (
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
        AND files.deleted_at IS NULL
      ORDER BY path`,
    )
    .all(`${prefix}%`)
    .map(row => row.path);
}

function marker(buffer, offset) {
  const byte = buffer[offset];
  if (byte <= 0x7f) return { kind: 'fixpos', value: byte, offset: offset + 1 };
  if (byte >= 0xe0) return { kind: 'fixneg', value: byte - 0x100, offset: offset + 1 };
  if ((byte & 0xe0) === 0xa0) return { kind: 'fixstr', length: byte & 0x1f, offset: offset + 1 };
  if ((byte & 0xf0) === 0x90) return { kind: 'fixarray', length: byte & 0x0f, offset: offset + 1 };
  if ((byte & 0xf0) === 0x80) return { kind: 'fixmap', length: byte & 0x0f, offset: offset + 1 };
  switch (byte) {
    case 0xc0:
      return { kind: 'nil', value: null, offset: offset + 1 };
    case 0xc2:
      return { kind: 'bool', value: false, offset: offset + 1 };
    case 0xc3:
      return { kind: 'bool', value: true, offset: offset + 1 };
    case 0xc4:
      return { kind: 'bin', length: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xc5:
      return { kind: 'bin', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xc6:
      return { kind: 'bin', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xca:
      return { kind: 'float32', offset: offset + 1 };
    case 0xcb:
      return { kind: 'float64', offset: offset + 1 };
    case 0xcc:
      return { kind: 'uint8', offset: offset + 1 };
    case 0xcd:
      return { kind: 'uint16', offset: offset + 1 };
    case 0xce:
      return { kind: 'uint32', offset: offset + 1 };
    case 0xcf:
      return { kind: 'uint64', offset: offset + 1 };
    case 0xd0:
      return { kind: 'int8', offset: offset + 1 };
    case 0xd1:
      return { kind: 'int16', offset: offset + 1 };
    case 0xd2:
      return { kind: 'int32', offset: offset + 1 };
    case 0xd3:
      return { kind: 'int64', offset: offset + 1 };
    case 0xd9:
      return { kind: 'str', length: buffer.readUInt8(offset + 1), offset: offset + 2 };
    case 0xda:
      return { kind: 'str', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdb:
      return { kind: 'str', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    case 0xdc:
      return { kind: 'array', length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
    case 0xdd:
      return { kind: 'array', length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
    default:
      throw new Error(`Unsupported msgpack marker 0x${byte.toString(16)} at ${offset}`);
  }
}

function readArrayLen(buffer, offset) {
  const head = marker(buffer, offset);
  if (head.kind === 'fixarray' || head.kind === 'array') {
    return { length: head.length, offset: head.offset };
  }
  throw new Error(`Expected array length at ${offset}, got ${head.kind}`);
}

function readBin(buffer, offset) {
  const head = marker(buffer, offset);
  if (head.kind !== 'bin') {
    throw new Error(`Expected binary at ${offset}, got ${head.kind}`);
  }
  return {
    value: buffer.subarray(head.offset, head.offset + head.length),
    offset: head.offset + head.length,
  };
}

function readString(buffer, offset) {
  const head = marker(buffer, offset);
  if (head.kind !== 'fixstr' && head.kind !== 'str') {
    throw new Error(`Expected string at ${offset}, got ${head.kind}`);
  }
  return {
    value: buffer.subarray(head.offset, head.offset + head.length).toString('utf8'),
    offset: head.offset + head.length,
  };
}

function readInt(buffer, offset) {
  const head = marker(buffer, offset);
  switch (head.kind) {
    case 'fixpos':
    case 'fixneg':
      return { value: head.value, offset: head.offset };
    case 'uint8':
      return { value: buffer.readUInt8(head.offset), offset: head.offset + 1 };
    case 'uint16':
      return { value: buffer.readUInt16BE(head.offset), offset: head.offset + 2 };
    case 'uint32':
      return { value: buffer.readUInt32BE(head.offset), offset: head.offset + 4 };
    case 'uint64':
      return { value: Number(buffer.readBigUInt64BE(head.offset)), offset: head.offset + 8 };
    case 'int8':
      return { value: buffer.readInt8(head.offset), offset: head.offset + 1 };
    case 'int16':
      return { value: buffer.readInt16BE(head.offset), offset: head.offset + 2 };
    case 'int32':
      return { value: buffer.readInt32BE(head.offset), offset: head.offset + 4 };
    case 'int64':
      return { value: Number(buffer.readBigInt64BE(head.offset)), offset: head.offset + 8 };
    default:
      throw new Error(`Expected integer at ${offset}, got ${head.kind}`);
  }
}

function readFloat(buffer, offset, ty) {
  const head = marker(buffer, offset);
  if (ty === 'f32' && head.kind === 'float32') {
    return { value: buffer.readFloatBE(head.offset), offset: head.offset + 4 };
  }
  if (ty === 'f64' && head.kind === 'float64') {
    return { value: buffer.readDoubleBE(head.offset), offset: head.offset + 8 };
  }
  throw new Error(`Expected ${ty} at ${offset}, got ${head.kind}`);
}

function readFlatType(buffer, offset, schema, ty) {
  switch (ty) {
    case 'u8':
      return { value: buffer.readUInt8(offset), offset: offset + 1 };
    case 'u16':
      return { value: buffer.readUInt16LE(offset), offset: offset + 2 };
    case 'u32':
      return { value: buffer.readUInt32LE(offset), offset: offset + 4 };
    case 'u64':
      return { value: Number(buffer.readBigUInt64LE(offset)), offset: offset + 8 };
    case 'i8':
      return { value: buffer.readInt8(offset), offset: offset + 1 };
    case 'i16':
      return { value: buffer.readInt16LE(offset), offset: offset + 2 };
    case 'i32':
      return { value: buffer.readInt32LE(offset), offset: offset + 4 };
    case 'i64':
      return { value: Number(buffer.readBigInt64LE(offset)), offset: offset + 8 };
    case 'f32':
      return { value: buffer.readFloatLE(offset), offset: offset + 4 };
    case 'f64':
      return { value: buffer.readDoubleLE(offset), offset: offset + 8 };
    default: {
      if (schema.enums[ty]) {
        const decoded = readFlatType(buffer, offset, schema, 'u8');
        return { value: schema.enums[ty][decoded.value] || decoded.value, offset: decoded.offset };
      }
      const struct = schema.structs[ty];
      if (!struct) throw new Error(`Unknown flat type ${ty}`);
      const value = {};
      let cursor = offset;
      for (const [name, prop] of Object.entries(struct.props)) {
        if (prop.kind !== 'literal') {
          throw new Error(`Expected flat literal for ${ty}.${name}, got ${prop.kind}`);
        }
        const decoded = readFlatType(buffer, cursor, schema, prop.ty);
        value[name] = decoded.value;
        cursor = decoded.offset;
      }
      return { value, offset: cursor };
    }
  }
}

function flatTypeSize(schema, ty) {
  switch (ty) {
    case 'u8':
    case 'i8':
      return 1;
    case 'u16':
    case 'i16':
      return 2;
    case 'u32':
    case 'i32':
    case 'f32':
      return 4;
    case 'u64':
    case 'i64':
    case 'f64':
      return 8;
    default: {
      if (schema.enums[ty]) return 1;
      const struct = schema.structs[ty];
      if (!struct) throw new Error(`Unknown flat type ${ty}`);
      return Object.values(struct.props).reduce((sum, prop) => {
        if (prop.kind !== 'literal') {
          throw new Error(`Expected flat literal for ${ty}, got ${prop.kind}`);
        }
        return sum + flatTypeSize(schema, prop.ty);
      }, 0);
    }
  }
}

function readType(buffer, offset, schema, ty) {
  if (/^[ui](8|16|32|64)$/.test(ty)) return readInt(buffer, offset);
  if (ty === 'f32' || ty === 'f64') return readFloat(buffer, offset, ty);
  if (ty === 'str') return readString(buffer, offset);
  if (schema.enums[ty]) {
    const decoded = readInt(buffer, offset);
    return { value: schema.enums[ty][decoded.value] || decoded.value, offset: decoded.offset };
  }

  const struct = schema.structs[ty];
  if (!struct) throw new Error(`Unknown type ${ty}`);
  const value = {};
  let cursor = offset;
  for (const [name, prop] of Object.entries(struct.props)) {
    if (prop.kind === 'literal') {
      const decoded = readType(buffer, cursor, schema, prop.ty);
      value[name] = decoded.value;
      cursor = decoded.offset;
    } else if (prop.kind === 'array') {
      const header = readArrayLen(buffer, cursor);
      cursor = header.offset;
      const items = [];
      for (let i = 0; i < header.length; i++) {
        const decoded = readType(buffer, cursor, schema, prop.ty);
        items.push(decoded.value);
        cursor = decoded.offset;
      }
      value[name] = items;
    } else if (prop.kind === 'flatarray') {
      const decoded = readBin(buffer, cursor);
      cursor = decoded.offset;
      const itemSize = flatTypeSize(schema, prop.ty);
      if (decoded.value.length % itemSize !== 0) {
        throw new Error(`${ty}.${name} flatarray has ${decoded.value.length} bytes, not divisible by ${itemSize}`);
      }
      const items = [];
      let flatCursor = 0;
      while (flatCursor < decoded.value.length) {
        const item = readFlatType(decoded.value, flatCursor, schema, prop.ty);
        items.push(item.value);
        flatCursor = item.offset;
      }
      value[name] = items;
    } else {
      throw new Error(`Unsupported schema property ${ty}.${name}: ${prop.kind}`);
    }
  }
  return { value, offset: cursor };
}

function entityTypeNames(schema) {
  return Object.keys(schema.structs).filter(name =>
    !name.startsWith('BRSaved') && name !== 'Quat4f' && name !== 'Vector3f',
  );
}

function bitIsSet(flags, index) {
  const byte = flags?.Flags?.[Math.floor(index / 8)] ?? 0;
  return Boolean(byte & (1 << (index % 8)));
}

function uniqueSortedNumbers(values) {
  return Array.from(new Set((values || [])
    .map(value => Number(value))
    .filter(value => Number.isFinite(value))))
    .sort((left, right) => left - right);
}

function sumNumbers(values) {
  return (values || []).reduce((sum, value) => sum + (Number(value) || 0), 0);
}

function componentTypeNames(schema) {
  const genericStructs = new Set([
    'Color',
    'IntVector',
    'Quat4f',
    'Rotator3f',
    'Vector3f',
  ]);
  return Object.keys(schema.structs).filter(name =>
    !name.startsWith('BRSaved') && !genericStructs.has(name),
  );
}

function typeRanges(counters, typeNames, countField) {
  let rowStart = 0;
  return (counters || []).map(counter => {
    const count = Number(counter[countField]) || 0;
    const range = {
      typeIndex: Number(counter.TypeIndex),
      typeName: typeNames[Number(counter.TypeIndex)] || `type#${counter.TypeIndex}`,
      start: rowStart,
      end: rowStart + count - 1,
      count,
    };
    rowStart += count;
    return range;
  });
}

function componentChunkSummary(db, schema, typeNames, componentPath) {
  const decoded = readType(
    readBundleFile(db, componentPath),
    0,
    schema,
    'BRSavedComponentChunkSoA',
  ).value;
  const jointRefs = decoded.JointEntityReferences || [];
  return {
    path: componentPath,
    typeCounters: decoded.ComponentTypeCounters || [],
    typeRanges: typeRanges(
      decoded.ComponentTypeCounters || [],
      typeNames,
      'NumInstances',
    ),
    componentBrickIndexCount: decoded.ComponentBrickIndices?.length || 0,
    jointBrickIndices: decoded.JointBrickIndices || [],
    jointEntityReferences: jointRefs,
    uniqueJointEntityReferences: uniqueSortedNumbers(jointRefs),
    microchipBrickGridReferences: uniqueSortedNumbers(
      decoded.MicrochipBrickGridReferences || [],
    ),
  };
}

function summarizeBrickGrids(db, files, readBrdbSchema) {
  const componentSchemaBuffer = readBundleFile(
    db,
    'World/0/Bricks/ComponentsShared.schema',
  );
  const componentSchema = componentSchemaBuffer
    ? readBrdbSchema(componentSchemaBuffer)
    : null;
  const componentNames = componentSchema ? componentTypeNames(componentSchema) : [];
  const gridIds = uniqueSortedNumbers(files
    .map(file => {
      const match = file.match(/^World\/0\/Bricks\/Grids\/(\d+)\/ChunkIndex\.mps$/);
      return match ? Number(match[1]) : null;
    })
    .filter(value => value != null));

  return gridIds.map(gridId => {
    const gridRoot = `World/0/Bricks/Grids/${gridId}`;
    const chunkIndexPath = `${gridRoot}/ChunkIndex.mps`;
    const indexBuffer = readBundleFile(db, chunkIndexPath);
    const index = indexBuffer
      ? readBrickChunkIndex(indexBuffer)
      : {
        chunks: [],
        offsets: [],
        chunkSizes: [],
        numBricks: [],
        numComponents: [],
        numWires: [],
      };
    const componentPaths = files.filter(file =>
      file.startsWith(`${gridRoot}/Components/`) && file.endsWith('.mps'),
    );
    const componentChunks = componentSchema
      ? componentPaths.map(componentPath =>
        componentChunkSummary(db, componentSchema, componentNames, componentPath),
      )
      : [];
    return {
      gridId,
      chunkIndexPath,
      chunks: index.chunks || [],
      offsets: index.offsets || [],
      chunkSizes: index.chunkSizes || [],
      brickCount: sumNumbers(index.numBricks),
      componentCount: sumNumbers(index.numComponents),
      wireCount: sumNumbers(index.numWires),
      brickChunkPaths: files.filter(file =>
        file.startsWith(`${gridRoot}/Chunks/`) && file.endsWith('.mps'),
      ),
      componentChunkPaths: componentPaths,
      wireChunkPaths: files.filter(file =>
        file.startsWith(`${gridRoot}/Wires/`) && file.endsWith('.mps'),
      ),
      componentChunks,
    };
  });
}

function buildEntityGraph(seedEntityId, entities, brickGrids) {
  const entitiesById = new Map(entities.map(entity => [
    Number(entity.persistentIndex ?? entity.id),
    entity,
  ]));
  const relatedEntityIds = new Set([Number(seedEntityId)]);
  const relatedGridIds = new Set();
  const componentChunkPaths = new Set();
  let changed = true;

  while (changed) {
    changed = false;
    for (const grid of brickGrids) {
      const gridMatchesEntity = relatedEntityIds.has(Number(grid.gridId));
      if (gridMatchesEntity && !relatedGridIds.has(grid.gridId)) {
        relatedGridIds.add(grid.gridId);
        changed = true;
      }

      const gridAlreadyRelated = relatedGridIds.has(grid.gridId);
      if (gridAlreadyRelated && entitiesById.has(Number(grid.gridId)) && !relatedEntityIds.has(Number(grid.gridId))) {
        relatedEntityIds.add(Number(grid.gridId));
        changed = true;
      }
      for (const component of grid.componentChunks || []) {
        const refs = component.uniqueJointEntityReferences || [];
        const componentReferencesGraph = refs.some(ref =>
          relatedEntityIds.has(Number(ref)),
        );
        if (!gridMatchesEntity && !gridAlreadyRelated && !componentReferencesGraph) {
          continue;
        }

        if (!relatedGridIds.has(grid.gridId)) {
          relatedGridIds.add(grid.gridId);
          changed = true;
        }
        componentChunkPaths.add(component.path);
        for (const ref of refs) {
          const numericRef = Number(ref);
          if (Number.isFinite(numericRef) && !relatedEntityIds.has(numericRef)) {
            relatedEntityIds.add(numericRef);
            changed = true;
          }
        }
      }
    }
  }

  const sortedEntityIds = uniqueSortedNumbers(Array.from(relatedEntityIds));
  const sortedGridIds = uniqueSortedNumbers(Array.from(relatedGridIds));
  const relatedGrids = brickGrids.filter(grid => sortedGridIds.includes(grid.gridId));
  return {
    seedEntityId: Number(seedEntityId),
    seedEntity: entitiesById.get(Number(seedEntityId)) || null,
    status: sortedGridIds.length > 0
      ? 'resolved-by-joint-references'
      : 'no-related-grid-found',
    relatedEntityIds: sortedEntityIds,
    relatedEntities: sortedEntityIds
      .map(id => entitiesById.get(id))
      .filter(Boolean),
    missingEntityIds: sortedEntityIds.filter(id => !entitiesById.has(id)),
    relatedGridIds: sortedGridIds,
    relatedGrids,
    chunkPaths: {
      brick: relatedGrids.flatMap(grid => grid.brickChunkPaths || []),
      component: Array.from(componentChunkPaths).sort(),
      wire: relatedGrids.flatMap(grid => grid.wireChunkPaths || []),
    },
  };
}

function summarizeEntityGraph(graph) {
  return {
    seedEntityId: graph.seedEntityId,
    seedEntity: graph.seedEntity,
    status: graph.status,
    relatedEntityIds: graph.relatedEntityIds,
    missingEntityIds: graph.missingEntityIds,
    relatedGridIds: graph.relatedGridIds,
    chunkPathCounts: {
      brick: graph.chunkPaths.brick.length,
      component: graph.chunkPaths.component.length,
      wire: graph.chunkPaths.wire.length,
    },
  };
}

function buildDynamicActorGraphs(entities, brickGrids) {
  return entities
    .filter(entity => entity.typeName === 'BrickGridDynamicActor')
    .map(entity => buildEntityGraph(
      Number(entity.persistentIndex ?? entity.id),
      entities,
      brickGrids,
    ))
    .map(summarizeEntityGraph);
}

function averageLocations(locations) {
  const valid = locations.filter(location =>
    location &&
    Number.isFinite(Number(location.X)) &&
    Number.isFinite(Number(location.Y)) &&
    Number.isFinite(Number(location.Z)),
  );
  if (valid.length === 0) return null;
  return {
    X: valid.reduce((sum, location) => sum + Number(location.X), 0) / valid.length,
    Y: valid.reduce((sum, location) => sum + Number(location.Y), 0) / valid.length,
    Z: valid.reduce((sum, location) => sum + Number(location.Z), 0) / valid.length,
  };
}

function buildDynamicActorGroups(dynamicActorGraphs) {
  const groups = new Map();
  for (const graph of dynamicActorGraphs) {
    const relatedEntityIds = uniqueSortedNumbers(graph.relatedEntityIds || []);
    const relatedGridIds = uniqueSortedNumbers(graph.relatedGridIds || []);
    const key = JSON.stringify({ relatedEntityIds, relatedGridIds });
    const existing = groups.get(key) || {
      seedEntityIds: [],
      seedEntities: [],
      statuses: new Set(),
      relatedEntityIds,
      missingEntityIds: uniqueSortedNumbers(graph.missingEntityIds || []),
      relatedGridIds,
      chunkPathCounts: graph.chunkPathCounts || { brick: 0, component: 0, wire: 0 },
    };

    existing.seedEntityIds.push(Number(graph.seedEntityId));
    if (graph.seedEntity) existing.seedEntities.push(graph.seedEntity);
    if (graph.status) existing.statuses.add(graph.status);
    groups.set(key, existing);
  }

  return Array.from(groups.values())
    .sort((a, b) => Math.min(...a.seedEntityIds) - Math.min(...b.seedEntityIds))
    .map((group, index) => {
      const seedEntityIds = uniqueSortedNumbers(group.seedEntityIds);
      const seedEntities = group.seedEntities.sort((a, b) =>
        Number(a.persistentIndex ?? a.id) - Number(b.persistentIndex ?? b.id),
      );
      return {
        groupId: index + 1,
        seedEntityIds,
        seedEntities,
        status: Array.from(group.statuses).sort().join(',') || 'unknown',
        relatedEntityIds: group.relatedEntityIds,
        missingEntityIds: group.missingEntityIds,
        relatedGridIds: group.relatedGridIds,
        relatedEntityCount: group.relatedEntityIds.length,
        relatedGridCount: group.relatedGridIds.length,
        center: averageLocations(seedEntities.map(entity => entity.location)),
        chunkPathCounts: group.chunkPathCounts,
      };
    });
}

function summarizeEntities(inputPath, options = {}) {
  const { readBrdbSchema } = loadBrdbInternals();
  const db = new Database(inputPath, { readonly: true, fileMustExist: true });
  try {
    const files = listBundleFiles(db);
    const indexBuffer = readBundleFile(db, 'World/0/Entities/ChunkIndex.mps');
    if (!indexBuffer) {
      return { input: inputPath, entityIndex: null, entities: [] };
    }

    const entityIndex = readEntityChunkIndex(indexBuffer);
    const schema = readBrdbSchema(readBundleFile(db, 'World/0/Entities/ChunksShared.schema'));
    const typeNames = entityTypeNames(schema);
    const chunkPaths = files.filter(file => /^World\/0\/Entities\/Chunks\/.+\.mps$/.test(file));
    const entities = [];

    for (const chunkPath of chunkPaths) {
      const match = chunkPath.match(/\/(-?\d+)_(-?\d+)_(-?\d+)\.mps$/);
      const chunk = match
        ? { x: Number(match[1]), y: Number(match[2]), z: Number(match[3]) }
        : null;
      const decoded = readType(
        readBundleFile(db, chunkPath),
        0,
        schema,
        'BRSavedEntityChunkSoA',
      ).value;

      let rowStart = 0;
      const ranges = (decoded.TypeCounters || []).map(counter => {
        const count = Number(counter.NumEntities) || 0;
        const range = {
          typeIndex: Number(counter.TypeIndex),
          typeName: typeNames[Number(counter.TypeIndex)] || `type#${counter.TypeIndex}`,
          start: rowStart,
          end: rowStart + count - 1,
          count,
        };
        rowStart += count;
        return range;
      });

      for (const range of ranges) {
        for (let row = range.start; row <= range.end; row++) {
          entities.push({
            id: decoded.PersistentIndices?.[row],
            persistentIndex: decoded.PersistentIndices?.[row],
            row,
            chunk,
            chunkPath,
            typeIndex: range.typeIndex,
            typeName: range.typeName,
            ownerIndex: decoded.OwnerIndices?.[row],
            originalOwnerIndex: decoded.OriginalOwnerIndices?.[row],
            location: decoded.Locations?.[row] || null,
            rotation: decoded.Rotations?.[row] || null,
            weldParent: bitIsSet(decoded.WeldParentFlags, row),
            physicsLocked: bitIsSet(decoded.PhysicsLockedFlags, row),
            physicsSleeping: bitIsSet(decoded.PhysicsSleepingFlags, row),
            weldParentIndex: decoded.WeldParentIndices?.[row] ?? null,
          });
        }
      }
    }

    const brickGrids = summarizeBrickGrids(db, files, readBrdbSchema);
    const dynamicActorGraphs = buildDynamicActorGraphs(entities, brickGrids);
    const dynamicActorGroups = buildDynamicActorGroups(dynamicActorGraphs);
    const selectedEntityGraph = Number.isFinite(Number(options.entityId))
      ? buildEntityGraph(Number(options.entityId), entities, brickGrids)
      : null;

    return {
      input: inputPath,
      entityIndex,
      typeNames,
      entities,
      brickGrids,
      dynamicActorGraphs,
      dynamicActorGroups,
      selectedEntityGraph,
    };
  } finally {
    db.close();
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = summarizeEntities(args.input, { entityId: args.entityId });
  if (args.outJson) {
    fs.mkdirSync(path.dirname(args.outJson), { recursive: true });
    fs.writeFileSync(args.outJson, `${JSON.stringify(result, null, 2)}\n`);
  }
  console.log(JSON.stringify(result, null, 2));
}

module.exports = {
  summarizeEntities,
};

if (require.main === module) {
  main();
}
