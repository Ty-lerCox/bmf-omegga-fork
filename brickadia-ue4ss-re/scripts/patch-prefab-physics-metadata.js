#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { blake3 } = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/@noble/hashes/blake3.js');
const { parseBrz, decompressChunk } = require('./inspect-brz.js');
const { diagnose, summarizeReport } = require('./diagnose-prefab-vehicle-structure.js');

function usage() {
  console.error([
    'usage: node patch-prefab-physics-metadata.js <input.brz> <output.brz> [options]',
    '',
    'Options:',
    '  --force                Overwrite output if it already exists',
    '  --identity-world-root  Add identity worldRootTransform when missing',
    '  --no-world-root        Do not add worldRootTransform when missing',
    '  --dry-run              Print the planned metadata without writing',
  ].join('\n'));
  process.exit(2);
}

function parseArgs(argv) {
  const out = {
    force: false,
    dryRun: false,
    identityWorldRoot: true,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--force') {
      out.force = true;
      continue;
    }
    if (arg === '--dry-run') {
      out.dryRun = true;
      continue;
    }
    if (arg === '--identity-world-root') {
      out.identityWorldRoot = true;
      continue;
    }
    if (arg === '--no-world-root') {
      out.identityWorldRoot = false;
      continue;
    }
    if (!arg.startsWith('--') && !out.input) {
      out.input = path.resolve(arg);
      continue;
    }
    if (!arg.startsWith('--') && !out.output) {
      out.output = path.resolve(arg);
      continue;
    }
    usage();
  }
  if (!out.input || (!out.output && !out.dryRun)) {
    usage();
  }
  return out;
}

function encodeInt32Array(values) {
  const buffer = Buffer.alloc(values.length * 4);
  values.forEach((value, index) => buffer.writeInt32LE(value, index * 4));
  return buffer;
}

function encodeUInt16Array(values) {
  const buffer = Buffer.alloc(values.length * 2);
  values.forEach((value, index) => buffer.writeUInt16LE(value, index * 2));
  return buffer;
}

function encodeStrings(values) {
  return Buffer.concat(values.map((value) => Buffer.from(value, 'utf8')));
}

function buildIndexData(parsed, blobRecords) {
  return Buffer.concat([
    encodeInt32Array([parsed.index.numFolders, parsed.index.numFiles, parsed.index.numBlobs]),
    encodeInt32Array(parsed.index.folderParents),
    encodeUInt16Array(parsed.index.folderNames.map((name) => Buffer.byteLength(name, 'utf8'))),
    encodeStrings(parsed.index.folderNames),
    encodeInt32Array(parsed.index.fileParents),
    encodeInt32Array(parsed.index.fileContentIds),
    encodeUInt16Array(parsed.index.fileNames.map((name) => Buffer.byteLength(name, 'utf8'))),
    encodeStrings(parsed.index.fileNames),
    Buffer.from(blobRecords.map((blob) => blob.compressionMethod)),
    encodeInt32Array(blobRecords.map((blob) => blob.decompressedLength)),
    encodeInt32Array(blobRecords.map((blob) => blob.compressedLength)),
    Buffer.concat(blobRecords.map((blob) => blob.hash)),
  ]);
}

function compressPayload(method, content) {
  if (method === 0) {
    return content;
  }
  if (method === 1) {
    return zlib.zstdCompressSync(content, { params: {} });
  }
  throw new Error(`Unsupported BRZ compression method: ${method}`);
}

function compressIndex(method, content) {
  return compressPayload(method, content);
}

function identityWorldRootTransform() {
  return {
    rotation: { x: 0, y: 0, z: 0, w: 1 },
    translation: { x: 0, y: 0, z: 0 },
    scale3D: { x: 1, y: 1, z: 1 },
  };
}

function sumReports(list, field) {
  return (list || []).reduce((acc, item) => acc + (Number(item && item[field]) || 0), 0);
}

function patchMetadata(meta, report, options = {}) {
  const patched = JSON.parse(JSON.stringify(meta || {}));
  const grids = report.grids || [];
  patched.brickCount = report.meta?.brickCount ?? sumReports(grids, 'brick_count');
  patched.componentCount = report.meta?.componentCount ?? sumReports(grids, 'component_count');
  patched.entityCount = report.meta?.entityCount ?? report.entity?.total_entities ?? 0;
  patched.wireCount = report.meta?.wireCount ?? sumReports(grids, 'wire_count');
  patched.bIsPhysicsGrid = true;
  if (patched.bFreezePhysicsGrid == null) {
    patched.bFreezePhysicsGrid = false;
  }
  if (!patched.worldRootTransform && options.identityWorldRoot) {
    patched.worldRootTransform = identityWorldRootTransform();
  }
  return patched;
}

function readArchiveJson(parsed, archivePath) {
  const file = parsed.files.find((entry) => entry.path === archivePath);
  if (!file || file.contentId < 0) {
    throw new Error(`Archive is missing ${archivePath}`);
  }
  const blob = parsed.blobs[file.contentId];
  const content = decompressChunk(blob.compressionMethod, blob.data, blob.decompressedLength);
  return {
    file,
    value: JSON.parse(content.toString('utf8')),
  };
}

function writeBrz(parsed, outputPath, updatedBlobContentById) {
  const blobRecords = parsed.blobs.map((blob) => {
    const content = updatedBlobContentById.has(blob.id)
      ? updatedBlobContentById.get(blob.id)
      : decompressChunk(blob.compressionMethod, blob.data, blob.decompressedLength);
    const compressed = compressPayload(blob.compressionMethod, content);
    return {
      id: blob.id,
      compressionMethod: blob.compressionMethod,
      decompressedLength: content.length,
      compressedLength: compressed.length,
      hash: Buffer.from(blake3(content)),
      compressed,
    };
  });

  const indexData = buildIndexData(parsed, blobRecords);
  const compressedIndex = compressIndex(parsed.header.indexCompressionMethod, indexData);
  const header = Buffer.alloc(45);
  header.write('BRZ', 0, 'ascii');
  header.writeUInt8(parsed.header.formatVersion, 3);
  header.writeUInt8(parsed.header.indexCompressionMethod, 4);
  header.writeInt32LE(indexData.length, 5);
  header.writeInt32LE(compressedIndex.length, 9);
  Buffer.from(blake3(indexData)).copy(header, 13);

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, Buffer.concat([
    header,
    compressedIndex,
    ...blobRecords.map((blob) => blob.compressed),
  ]));
}

function patchPrefabPhysicsMetadata(inputPath, outputPath, options = {}) {
  if (!fs.existsSync(inputPath)) {
    throw new Error(`Missing input BRZ: ${inputPath}`);
  }
  if (outputPath && fs.existsSync(outputPath) && !options.force) {
    throw new Error(`Refusing to overwrite existing output: ${outputPath}`);
  }

  const parsed = parseBrz(inputPath);
  const prefabJson = readArchiveJson(parsed, 'Meta/Prefab.json');
  const report = diagnose(inputPath);
  const before = summarizeReport(report);
  const patchedMeta = patchMetadata(prefabJson.value, report, options);
  const updated = new Map([
    [prefabJson.file.contentId, Buffer.from(`${JSON.stringify(patchedMeta, null, '\t')}\n`, 'utf8')],
  ]);

  if (!options.dryRun) {
    writeBrz(parsed, outputPath, updated);
  }

  return {
    input: inputPath,
    output: outputPath || null,
    dryRun: Boolean(options.dryRun),
    before,
    patchedMeta: {
      brickCount: patchedMeta.brickCount,
      componentCount: patchedMeta.componentCount,
      entityCount: patchedMeta.entityCount,
      wireCount: patchedMeta.wireCount,
      bIsPhysicsGrid: patchedMeta.bIsPhysicsGrid,
      bFreezePhysicsGrid: patchedMeta.bFreezePhysicsGrid,
      worldRootTransform: patchedMeta.worldRootTransform || null,
    },
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = patchPrefabPhysicsMetadata(args.input, args.output, args);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildIndexData,
  patchPrefabPhysicsMetadata,
  patchMetadata,
  writeBrz,
};
