#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { blake3 } = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/@noble/hashes/blake3.js');
const { sha256 } = require('C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/node_modules/@noble/hashes/sha2.js');
const { parseBrz, decompressChunk } = require('./inspect-brz.js');
const { diagnose, summarizeReport } = require('./diagnose-prefab-vehicle-structure.js');

const LOCALAPPDATA = process.env.LOCALAPPDATA || '';
const DEFAULT_GALLERY_DIR = LOCALAPPDATA
  ? path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'GalleryCache', 'Prefabs')
  : null;
const DEFAULT_CLIPBOARD = LOCALAPPDATA
  ? path.join(LOCALAPPDATA, 'Brickadia', 'Saved', 'Temp', 'Clipboard.brz')
  : null;

function usage() {
  console.error([
    'usage: node prefab-hash-report.js [input.brz ...] [options]',
    '',
    'Options:',
    '  --scan-gallery [dir]  Include .brz files from the gallery cache',
    '  --clipboard           Include the current Brickadia temp Clipboard.brz',
    '  --out-json <path>     Write JSON report to a file',
  ].join('\n'));
  process.exit(2);
}

function parseArgs(argv) {
  const out = {
    inputs: [],
    scanGallery: false,
    galleryDir: null,
    clipboard: false,
    outJson: null,
  };

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
    if (arg === '--clipboard') {
      out.clipboard = true;
      continue;
    }
    if (arg === '--out-json') {
      const value = argv[i + 1];
      if (!value || value.startsWith('--')) {
        usage();
      }
      out.outJson = value;
      i += 1;
      continue;
    }
    if (!arg.startsWith('--')) {
      out.inputs.push(arg);
      continue;
    }
    usage();
  }

  return out;
}

function hex(bytes) {
  return Buffer.from(bytes).toString('hex').toUpperCase();
}

function archiveNameFromSummary(filePath, summary) {
  if (summary && summary.name) {
    return summary.name;
  }
  return path.basename(filePath, path.extname(filePath));
}

function hashPrefab(inputPath) {
  const resolved = path.resolve(inputPath);
  const raw = fs.readFileSync(resolved);
  const parsed = parseBrz(resolved);
  const indexCompressed = raw.subarray(45, 45 + parsed.header.indexCompressedLength);
  const payloadCompressed = raw.subarray(45 + parsed.header.indexCompressedLength);
  const decompressedBlobs = Buffer.concat(parsed.blobs.map((blob) => (
    decompressChunk(blob.compressionMethod, blob.data, blob.decompressedLength)
  )));
  let summary = null;
  let diagnoseError = null;
  try {
    summary = summarizeReport(diagnose(resolved));
  } catch (error) {
    diagnoseError = String(error && error.message ? error.message : error);
  }

  return {
    input: resolved,
    file: path.basename(resolved),
    name: archiveNameFromSummary(resolved, summary),
    bytes: raw.length,
    brPrefabHashCandidate: hex(blake3(raw)),
    hashBasis: 'blake3(raw .brz archive bytes)',
    supportingHashes: {
      rawSha256: hex(sha256(raw)),
      payloadCompressedBlake3: hex(blake3(payloadCompressed)),
      decompressedBlobsBlake3: hex(blake3(decompressedBlobs)),
      indexBlake3FromHeader: parsed.header.indexHash.toUpperCase(),
    },
    archive: {
      formatVersion: parsed.header.formatVersion,
      files: parsed.index.numFiles,
      folders: parsed.index.numFolders,
      blobs: parsed.index.numBlobs,
      indexCompressedLength: parsed.header.indexCompressedLength,
      indexDecompressedLength: parsed.header.indexDecompressedLength,
    },
    summary,
    diagnoseError,
  };
}

function collectInputs(args) {
  const inputs = args.inputs.map((input) => path.resolve(input));
  if (args.clipboard) {
    if (!DEFAULT_CLIPBOARD) {
      throw new Error('LOCALAPPDATA is not set; cannot resolve Clipboard.brz');
    }
    inputs.push(DEFAULT_CLIPBOARD);
  }
  if (args.scanGallery) {
    const galleryDir = path.resolve(args.galleryDir || DEFAULT_GALLERY_DIR || '');
    if (!galleryDir || !fs.existsSync(galleryDir)) {
      throw new Error(`Missing gallery prefab directory: ${galleryDir}`);
    }
    for (const entry of fs.readdirSync(galleryDir).sort()) {
      if (/\.brz$/i.test(entry)) {
        inputs.push(path.join(galleryDir, entry));
      }
    }
  }
  return Array.from(new Set(inputs));
}

function buildReport(args) {
  const inputs = collectInputs(args);
  if (inputs.length === 0) {
    usage();
  }
  return {
    generatedAt: new Date().toISOString(),
    hashInference: {
      brPrefabHashCandidate: 'blake3(raw .brz archive bytes)',
      evidence: 'The CL12960 logged cache hash 07C8E4AD16AC2B85B7FBE8637C9929AD9326ECA7384219F05937BD0F464BB7AD matches raw BLAKE3 of local gallery prefab 8c04e0ee-87b3-4eef-b5de-659c60f1e9ac.brz.',
      status: 'strong-local-evidence',
    },
    prefabs: inputs.map(hashPrefab),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const report = buildReport(args);
  const json = `${JSON.stringify(report, null, 2)}\n`;
  if (args.outJson) {
    const outputPath = path.resolve(args.outJson);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, json, 'utf8');
  }
  process.stdout.write(json);
}

module.exports = {
  buildReport,
  hashPrefab,
};

if (require.main === module) {
  main();
}
