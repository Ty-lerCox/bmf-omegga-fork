#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_BRIDGE_DIR = path.resolve(
  REPO_ROOT,
  '..',
  'omegga-master',
  'omegga-master',
  'data',
  'ue4ss-bridge-test-7799',
);

function usage() {
  console.error([
    'usage: node decode-prefab-native-capture.js [options]',
    '',
    'Options:',
    '  --capture <path|->       Capture text path, or - for stdin',
    '  --ndjson <path>          Capture NDJSON path; decodes the last detail_b64 record',
    '  --dir <bridge_dir>       Bridge dir; defaults to prefab-native-last.txt in that dir',
    '  --out-json <path>        Optional decoded JSON output path',
  ].join('\n'));
  process.exit(2);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) {
      usage();
    }
    const key = arg.slice(2);
    const value = argv[i + 1];
    if (value == null || value.startsWith('--')) {
      usage();
    }
    out[key] = value;
    i += 1;
  }
  return out;
}

function readText(filePath) {
  if (filePath === '-') {
    return fs.readFileSync(0, 'utf8');
  }
  return fs.readFileSync(filePath, 'utf8');
}

function readLatestNdjsonDetail(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const records = fs.readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        return null;
      }
    })
    .filter(Boolean);

  for (let index = records.length - 1; index >= 0; index -= 1) {
    const record = records[index];
    if (record.detail_b64) {
      return Buffer.from(record.detail_b64, 'base64').toString('utf8');
    }
  }
  return null;
}

function loadCaptureText(args) {
  if (args.capture) {
    return {
      source: args.capture === '-' ? 'stdin' : path.resolve(args.capture),
      text: readText(args.capture),
    };
  }

  if (args.ndjson) {
    const ndjsonPath = path.resolve(args.ndjson);
    return {
      source: ndjsonPath,
      text: readLatestNdjsonDetail(ndjsonPath),
    };
  }

  const bridgeDir = path.resolve(args.dir || DEFAULT_BRIDGE_DIR);
  const latestPath = path.join(bridgeDir, 'prefab-native-last.txt');
  if (fs.existsSync(latestPath)) {
    return {
      source: latestPath,
      text: readText(latestPath),
    };
  }

  const ndjsonPath = path.join(bridgeDir, 'prefab-native-captures.ndjson');
  return {
    source: ndjsonPath,
    text: readLatestNdjsonDetail(ndjsonPath),
  };
}

function setNested(target, dottedKey, value) {
  const parts = dottedKey.split('.');
  let cursor = target;
  for (let index = 0; index < parts.length - 1; index += 1) {
    const part = parts[index];
    if (!cursor[part] || typeof cursor[part] !== 'object') {
      cursor[part] = {};
    }
    cursor = cursor[part];
  }
  cursor[parts[parts.length - 1]] = value;
}

function parseCapture(text) {
  const lines = String(text || '').split(/\r?\n/).filter(Boolean);
  const capture = {
    kind: null,
    hook: null,
    timestamp: null,
    context: null,
    arg_count: null,
    args: {},
    lines,
  };

  for (const line of lines) {
    const header = line.match(/^Prefab native capture:\s*(.*)$/);
    if (header) {
      capture.kind = header[1].trim();
      continue;
    }

    const keyValue = line.match(/^([^=]+)=(.*)$/);
    if (!keyValue) {
      continue;
    }

    const key = keyValue[1].trim();
    const value = keyValue[2];
    if (key === 'hook') capture.hook = value;
    if (key === 'timestamp') capture.timestamp = value;
    if (key === 'context') capture.context = value;
    if (key === 'arg_count') capture.arg_count = Number(value);

    const arg = key.match(/^arg\[(\d+)\]\.(.+)$/);
    if (arg) {
      const index = Number(arg[1]);
      capture.args[index] = capture.args[index] || {};
      if (arg[2] === 'lua_type') {
        const combined = value.match(/^(.*?)\s+resolver=(.*)$/);
        if (combined) {
          capture.args[index].lua_type = combined[1];
          capture.args[index].resolver = combined[2];
          continue;
        }
      }
      setNested(capture.args[index], arg[2], value);
    }
  }

  return capture;
}

function hexToBuffer(hexText) {
  const bytes = String(hexText || '').match(/[0-9a-fA-F]{2}/g) || [];
  return Buffer.from(bytes.map((byte) => Number.parseInt(byte, 16)));
}

function firstBytes(arg) {
  if (!arg) return null;
  const raw = arg.raw && arg.raw.bytes ? hexToBuffer(arg.raw.bytes) : null;
  if (raw && raw.length > 0) return raw;
  const resolved = arg.resolved && arg.resolved.bytes ? hexToBuffer(arg.resolved.bytes) : null;
  if (resolved && resolved.length > 0) return resolved;
  return null;
}

function parseBooleanArg(arg) {
  const text = arg && typeof arg.value === 'string' ? arg.value.toLowerCase() : '';
  if (text === 'true') return true;
  if (text === 'false') return false;

  const bytes = firstBytes(arg);
  if (!bytes || bytes.length < 1) return null;
  return bytes[0] !== 0;
}

function pointerHex(buffer, offset) {
  if (!buffer || buffer.length < offset + 8) return null;
  return `0x${buffer.readBigUInt64LE(offset).toString(16).toUpperCase()}`;
}

function decodeObjectReferenceCapture(capture) {
  const objectReferenceKinds = new Set([
    'ServerPasteEntity',
    'ServerPasteBrick',
    'HandleAttachedPlacement',
  ]);
  if (!objectReferenceKinds.has(capture.kind)) {
    return null;
  }

  return {
    function: capture.kind,
    contract: {
      parms_size: capture.kind === 'HandleAttachedPlacement' ? '0x10' : '0x8',
      objectRefs: Object.keys(capture.args)
        .map((index) => Number(index))
        .sort((left, right) => left - right)
        .map((index) => ({ arg: index, offset: `0x${((index - 1) * 8).toString(16).toUpperCase()}`, size: '0x8' })),
    },
    objectRefs: Object.entries(capture.args)
      .map(([index, arg]) => {
        const bytes = firstBytes(arg);
        return {
          arg: Number(index),
          value: arg.value || null,
          class: arg.class || null,
          pointer: bytes && bytes.length >= 8 ? pointerHex(bytes, 0) : null,
          byte_count: bytes ? bytes.length : 0,
        };
      })
      .sort((left, right) => left.arg - right.arg),
  };
}

function decodeServerPastePrefab(capture) {
  const identity = `${capture.kind || ''} ${capture.hook || ''}`;
  if (!/ServerPastePrefab/.test(identity)) {
    return null;
  }

  const warnings = [];
  const hash = firstBytes(capture.args[1]);
  const pasteInfo = firstBytes(capture.args[4]);
  if (!hash || hash.length < 32) {
    warnings.push('arg[1] does not contain a full 0x20 BRPrefabHash byte block');
  }
  if (!pasteInfo || pasteInfo.length < 0x15) {
    warnings.push('arg[4] does not contain enough bytes for BRPrefabDetachedPasteInfo');
  }

  const decoded = {
    function: 'ServerPastePrefab',
    contract: {
      parms_size: '0x40',
      hash: { arg: 1, offset: '0x00', size: '0x20' },
      bWithOwnership: { arg: 2, offset: '0x20', size: '0x01' },
      bInTemp: { arg: 3, offset: '0x21', size: '0x01' },
      pasteInfo: { arg: 4, offset: '0x28', size: '0x18' },
    },
    hash_hex: hash && hash.length >= 32 ? hash.subarray(0, 32).toString('hex').toUpperCase() : null,
    bWithOwnership: parseBooleanArg(capture.args[2]),
    bInTemp: parseBooleanArg(capture.args[3]),
    pasteInfo: {
      target_pointer: pasteInfo && pasteInfo.length >= 8 ? pointerHex(pasteInfo, 0) : null,
      gridOffset: pasteInfo && pasteInfo.length >= 0x14 ? {
        x: pasteInfo.readInt32LE(0x08),
        y: pasteInfo.readInt32LE(0x0C),
        z: pasteInfo.readInt32LE(0x10),
      } : null,
      placementOrientation: pasteInfo && pasteInfo.length >= 0x15 ? pasteInfo.readUInt8(0x14) : null,
    },
    warnings,
  };

  return decoded;
}

function readIntVector(buffer) {
  if (!buffer || buffer.length < 0x0C) {
    return null;
  }
  return {
    x: buffer.readInt32LE(0x00),
    y: buffer.readInt32LE(0x04),
    z: buffer.readInt32LE(0x08),
  };
}

function readDoubleVector(buffer, offset = 0) {
  if (!buffer || buffer.length < offset + 0x18) {
    return null;
  }
  return {
    x: buffer.readDoubleLE(offset),
    y: buffer.readDoubleLE(offset + 0x08),
    z: buffer.readDoubleLE(offset + 0x10),
  };
}

function decodeServerPlaceCurrentPrefab(capture) {
  const identity = `${capture.kind || ''} ${capture.hook || ''}`;
  if (!/ServerPlaceCurrentPrefab/.test(identity)) {
    return null;
  }

  const warnings = [];
  const placementState = firstBytes(capture.args[1]);
  const primaryGrid = firstBytes(capture.args[2]);
  const placementVector = firstBytes(capture.args[3]);
  const orientation = firstBytes(capture.args[4]);
  if (!placementState || placementState.length < 0x80) {
    warnings.push('arg[1] does not contain the full 0x80 placement-state block');
  }
  if (!primaryGrid || primaryGrid.length < 0x0C) {
    warnings.push('arg[2] does not contain a full FIntVector primary grid block');
  }
  if (!orientation || orientation.length < 1) {
    warnings.push('arg[4] does not contain the orientation byte');
  }

  const extraGridArgs = [5, 6, 7, 8].map((index) => {
    const bytes = firstBytes(capture.args[index]);
    return {
      arg: index,
      offset: `0x${(index === 5 ? 0xAC : index === 6 ? 0xB8 : index === 7 ? 0xC4 : 0xD0).toString(16).toUpperCase()}`,
      grid: readIntVector(bytes),
      byte_count: bytes ? bytes.length : 0,
    };
  });

  return {
    function: 'ServerPlaceCurrentPrefab',
    contract: {
      parms_size: '0xDF',
      placementState: { arg: 1, offset: '0x00', size: '0x80' },
      primaryGrid: { arg: 2, offset: '0x80', size: '0x0C' },
      placementVector: { arg: 3, offset: '0x90', size: '0x18' },
      orientation: { arg: 4, offset: '0xA8', size: '0x01' },
      extraGridLikeParams: [
        { arg: 5, offset: '0xAC', size: '0x0C' },
        { arg: 6, offset: '0xB8', size: '0x0C' },
        { arg: 7, offset: '0xC4', size: '0x0C' },
        { arg: 8, offset: '0xD0', size: '0x0C' },
      ],
      bools: [
        { arg: 9, offset: '0xDC', size: '0x01' },
        { arg: 10, offset: '0xDD', size: '0x01' },
        { arg: 11, offset: '0xDE', size: '0x01' },
      ],
    },
    placementState_bytes: placementState ? placementState.length : 0,
    primaryGrid: readIntVector(primaryGrid),
    placementVector_bytes: placementVector ? placementVector.length : 0,
    orientation: orientation && orientation.length >= 1 ? orientation.readUInt8(0) : null,
    extraGridLikeParams: extraGridArgs,
    bools: {
      arg9: parseBooleanArg(capture.args[9]),
      arg10: parseBooleanArg(capture.args[10]),
      arg11: parseBooleanArg(capture.args[11]),
    },
    warnings,
  };
}

function decodeServerPlaceSimpleEntityVolume(capture) {
  const identity = `${capture.kind || ''} ${capture.hook || ''}`;
  if (!/ServerPlaceSimpleEntityVolume/.test(identity)) {
    return null;
  }

  const warnings = [];
  const placementState = firstBytes(capture.args[1]);
  const entityClass = firstBytes(capture.args[2]);
  const orientationBytes = firstBytes(capture.args[3]);
  const primaryGrid = firstBytes(capture.args[4]);
  const placementVector = firstBytes(capture.args[5]);
  if (!placementState || placementState.length < 0x80) {
    warnings.push('arg[1] does not contain the full 0x80 placement-state block');
  }
  if (!entityClass || entityClass.length < 0x08) {
    warnings.push('arg[2] does not contain the entity class object pointer');
  }
  if (!orientationBytes || orientationBytes.length < 0x04) {
    warnings.push('arg[3] does not contain the 0x4 orientation/flags byte block');
  }
  if (!primaryGrid || primaryGrid.length < 0x0C) {
    warnings.push('arg[4] does not contain a full FIntVector primary grid block');
  }
  if (!placementVector || placementVector.length < 0x18) {
    warnings.push('arg[5] does not contain a full placement vector block');
  }

  const extraGridArgs = [7, 8, 9, 10].map((index) => {
    const bytes = firstBytes(capture.args[index]);
    const offsetByArg = {
      7: 0xB4,
      8: 0xC0,
      9: 0xCC,
      10: 0xD8,
    };
    return {
      arg: index,
      offset: `0x${offsetByArg[index].toString(16).toUpperCase()}`,
      grid: readIntVector(bytes),
      byte_count: bytes ? bytes.length : 0,
    };
  });

  return {
    function: 'ServerPlaceSimpleEntityVolume',
    contract: {
      parms_size: '0xE4',
      placementState: { arg: 1, offset: '0x00', size: '0x80' },
      entityClass: { arg: 2, offset: '0x80', size: '0x08' },
      orientationBytes: { arg: 3, offset: '0x88', size: '0x04' },
      primaryGrid: { arg: 4, offset: '0x8C', size: '0x0C' },
      placementVector: { arg: 5, offset: '0x98', size: '0x18' },
      boolLikeParam: { arg: 6, offset: '0xB0', size: '0x01' },
      extraGridLikeParams: [
        { arg: 7, offset: '0xB4', size: '0x0C' },
        { arg: 8, offset: '0xC0', size: '0x0C' },
        { arg: 9, offset: '0xCC', size: '0x0C' },
        { arg: 10, offset: '0xD8', size: '0x0C' },
      ],
    },
    placementState_bytes: placementState ? placementState.length : 0,
    placementStateTranslation: readDoubleVector(placementState, 0x30),
    entityClass_pointer: entityClass && entityClass.length >= 8 ? pointerHex(entityClass, 0) : null,
    orientationBytes: orientationBytes ? Array.from(orientationBytes.subarray(0, 4)) : null,
    orientation: orientationBytes && orientationBytes.length >= 1 ? orientationBytes.readUInt8(0) : null,
    primaryGrid: readIntVector(primaryGrid),
    placementVector: readDoubleVector(placementVector),
    boolLikeParam: parseBooleanArg(capture.args[6]),
    extraGridLikeParams: extraGridArgs,
    warnings,
  };
}

function summarizeArgs(capture) {
  const out = {};
  for (const [index, arg] of Object.entries(capture.args)) {
    const bytes = firstBytes(arg);
    out[index] = {
      lua_type: arg.lua_type || null,
      resolver: arg.resolver || null,
      value: arg.value || null,
      raw: arg.raw || null,
      resolved: arg.resolved || null,
      byte_count: bytes ? bytes.length : 0,
    };
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const loaded = loadCaptureText(args);
const capture = parseCapture(loaded.text || '');
const serverPastePrefab = decodeServerPastePrefab(capture);
const serverPlaceCurrentPrefab = decodeServerPlaceCurrentPrefab(capture);
const serverPlaceSimpleEntityVolume = decodeServerPlaceSimpleEntityVolume(capture);
const objectReferenceCapture = decodeObjectReferenceCapture(capture);
const result = {
  source: loaded.source,
  status: loaded.text ? 'decoded' : 'no-capture',
  capture: {
    kind: capture.kind,
    hook: capture.hook,
    timestamp: capture.timestamp,
    context: capture.context,
    arg_count: capture.arg_count,
    args: summarizeArgs(capture),
  },
  decoded: {
    serverPastePrefab,
    serverPlaceCurrentPrefab,
    serverPlaceSimpleEntityVolume,
    objectReferenceCapture,
  },
};

const json = `${JSON.stringify(result, null, 2)}\n`;
if (args['out-json']) {
  const outPath = path.resolve(args['out-json']);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, json, 'utf8');
}
process.stdout.write(json);
