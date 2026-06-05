#!/usr/bin/env node

const path = require('path');
const { execFileSync } = require('child_process');
const { hashPrefab } = require('./prefab-hash-report.js');

const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_BRIDGE_DIR = path.resolve(
  REPO_ROOT,
  '..',
  'omegga-master',
  'omegga-master',
  'data',
  'ue4ss-bridge-test-7799',
);
const SEND_RPC = path.join(__dirname, 'send-bridge-rpc.js');

function usage() {
  console.error([
    'usage: node paste-prefab-hash.js (--hash <64hex> | --brz <file.brz>) --grid <x> <y> <z> [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>       UE4SS bridge directory',
    '  --orientation <0-255>    Placement orientation, default 0',
    '  --target <0|last|hex>    PasteInfo target pointer, default 0',
    '  --paste-seed <seed>      ServerPastePrefab seed: hex:<param_hex>',
    '  --ownership <0|1>        bWithOwnership, default 1',
    '  --temp <0|1>             bInTemp, default 0',
    '  --dry-run <0|1>          Build the native buffer without invoking ProcessEvent, default 0',
    '  --place-current-prefab <0|1>  Also invoke ServerPlaceCurrentPrefab after ServerPastePrefab, default 0',
    '  --place-only <0|1>     With --place-current-prefab, skip ServerPastePrefab and only place current prefab',
    '  --place-seed <seed>      ServerPlaceCurrentPrefab seed: default, last, rawlast, or hex:<param_hex>',
    '  --place-adjust <mode>    ServerPlaceCurrentPrefab adjustment: primary or full, default primary',
    '  --wait-ms <ms>           Bridge wait timeout, default 10000',
  ].join('\n'));
  process.exit(2);
}

function takeValue(argv, index, label) {
  const value = argv[index + 1];
  if (value == null || value.startsWith('--')) {
    throw new Error(`missing value for ${label}`);
  }
  return value;
}

function parseArgs(argv) {
  const out = {
    bridgeDir: DEFAULT_BRIDGE_DIR,
    hash: null,
    brz: null,
    grid: null,
    orientation: '0',
    orientationSpecified: false,
    target: '0',
    targetSpecified: false,
    pasteSeed: null,
    ownership: '1',
    ownershipSpecified: false,
    temp: '0',
    tempSpecified: false,
    dryRun: false,
    placeCurrentPrefab: false,
    placeOnly: false,
    placeSeed: 'default',
    placeAdjust: 'primary',
    waitMs: 10000,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--dir') {
      out.bridgeDir = path.resolve(takeValue(argv, i, arg));
      i += 1;
    } else if (arg === '--hash') {
      out.hash = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--brz') {
      out.brz = path.resolve(takeValue(argv, i, arg));
      i += 1;
    } else if (arg === '--grid') {
      const x = takeValue(argv, i, arg);
      const y = takeValue(argv, i + 1, arg);
      const z = takeValue(argv, i + 2, arg);
      out.grid = [x, y, z];
      i += 3;
    } else if (arg === '--orientation') {
      out.orientation = takeValue(argv, i, arg);
      out.orientationSpecified = true;
      i += 1;
    } else if (arg === '--target') {
      out.target = takeValue(argv, i, arg);
      out.targetSpecified = true;
      i += 1;
    } else if (arg === '--paste-seed' || arg === '--paste-param-hex') {
      out.pasteSeed = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--ownership') {
      out.ownership = takeValue(argv, i, arg);
      out.ownershipSpecified = true;
      i += 1;
    } else if (arg === '--temp') {
      out.temp = takeValue(argv, i, arg);
      out.tempSpecified = true;
      i += 1;
    } else if (arg === '--dry-run') {
      out.dryRun = takeValue(argv, i, arg) !== '0';
      i += 1;
    } else if (arg === '--place-current-prefab' || arg === '--paste-and-place') {
      out.placeCurrentPrefab = takeValue(argv, i, arg) !== '0';
      i += 1;
    } else if (arg === '--place-only') {
      out.placeOnly = takeValue(argv, i, arg) !== '0';
      i += 1;
    } else if (arg === '--place-seed' || arg === '--place-param-hex') {
      out.placeSeed = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--place-adjust') {
      out.placeAdjust = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--wait-ms') {
      out.waitMs = Number(takeValue(argv, i, arg));
      i += 1;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }

  if ((out.hash ? 1 : 0) + (out.brz ? 1 : 0) !== 1) {
    throw new Error('expected exactly one of --hash or --brz');
  }
  if (!out.grid) {
    throw new Error('missing --grid x y z');
  }
  if (!Number.isFinite(out.waitMs) || out.waitMs <= 0) {
    throw new Error('--wait-ms must be positive');
  }

  return out;
}

function normalizeHash(hash) {
  const clean = String(hash || '').replace(/[^0-9a-fA-F]/g, '').toUpperCase();
  if (clean.length !== 64) {
    throw new Error('prefab hash must be exactly 64 hex characters');
  }
  return clean;
}

function resolveHash(options) {
  if (options.hash) {
    return normalizeHash(options.hash);
  }
  return hashPrefab(options.brz).brPrefabHashCandidate;
}

function isRawLastPlaceSeed(placeSeed) {
  return [
    'rawlast',
    'lastraw',
    'raw-capture',
    'last-raw-capture',
  ].includes(String(placeSeed || '').toLowerCase());
}

function parseRawProcessEventCaptureLines(lines) {
  const state = {};
  for (const line of lines || []) {
    const match = String(line || '').match(/^([^=]+)=(.*)$/);
    if (!match) {
      continue;
    }
    state[match[1]] = match[2];
  }
  return {
    state,
    targetLabel: state.target_label || '',
    lastCapture: state.last_capture || '',
    source: state.source || '',
    paramHex: state.param_hex || '',
    paramBytes: Number(state.param_bytes),
    replayLayout: state.raw_replay_layout || '',
  };
}

function runBridgeConsole(bridgeDir, command, waitMs) {
  const raw = execFileSync(
    process.execPath,
    [
      SEND_RPC,
      '--dir',
      bridgeDir,
      '--method',
      'console.exec',
      '--command-raw',
      command,
      '--wait-ms',
      String(waitMs),
      '--include-logs',
      '0',
    ],
    {
      cwd: path.resolve(__dirname, '..', '..'),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  return JSON.parse(raw);
}

function resolveDynamicPlaceSeed(options) {
  if (!options.placeCurrentPrefab || !isRawLastPlaceSeed(options.placeSeed)) {
    return options;
  }

  const response = runBridgeConsole(
    options.bridgeDir,
    'Omegga.Bridge.DescribeRawProcessEventCapture',
    options.waitMs,
  );
  const lines = (response.chunks || []).map((chunk) => chunk.line || '');
  const capture = parseRawProcessEventCaptureLines(lines);
  const cleanHex = String(capture.paramHex || '').replace(/[^0-9a-fA-F]/g, '').toUpperCase();
  if (
    capture.targetLabel !== 'ServerPlaceCurrentPrefab'
    || capture.replayLayout !== 'ServerPlaceCurrentPrefab'
    || capture.source !== 'client'
    || capture.paramBytes !== 0xdf
    || cleanHex.length !== 0xdf * 2
  ) {
    throw new Error(
      [
        'rawlast place seed is not a recent client ServerPlaceCurrentPrefab capture',
        `target=${capture.targetLabel || capture.lastCapture || '<none>'}`,
        `source=${capture.source || '<none>'}`,
        `bytes=${Number.isFinite(capture.paramBytes) ? capture.paramBytes : '<none>'}`,
      ].join('; '),
    );
  }

  return {
    ...options,
    placeSeed: `hex:${cleanHex}`,
  };
}

function buildCommand(options) {
  const hash = resolveHash(options);
  const parts = [
    options.placeCurrentPrefab
      ? 'Omegga.Bridge.PasteAndPlacePrefabHash'
      : 'Omegga.Bridge.PastePrefabHash',
    hash,
    'grid',
    ...options.grid.map(String),
  ];
  if (!options.pasteSeed || options.orientationSpecified || options.orientation !== '0') {
    parts.push(String(options.orientation));
  }
  if (!options.pasteSeed || options.ownershipSpecified || options.ownership !== '1') {
    parts.push(`ownership=${options.ownership}`);
  }
  if (!options.pasteSeed || options.tempSpecified || options.temp !== '0') {
    parts.push(`temp=${options.temp}`);
  }
  if (!options.pasteSeed || options.targetSpecified || options.target !== '0') {
    parts.push(`target=${options.target}`);
  }
  if (options.pasteSeed) {
    parts.push(`pasteseed=${options.pasteSeed}`);
  }
  if (options.placeCurrentPrefab && options.placeSeed && options.placeSeed !== 'default') {
    parts.push(`placeseed=${options.placeSeed}`);
  }
  if (options.placeCurrentPrefab && options.placeOnly) {
    parts.push('placeonly=1');
  }
  if (options.placeCurrentPrefab && options.placeAdjust && options.placeAdjust !== 'primary') {
    parts.push(`placeadjust=${options.placeAdjust}`);
  }
  if (options.dryRun) {
    parts.push('dry-run');
  }
  return parts.join(' ');
}

function run(options) {
  const command = buildCommand(resolveDynamicPlaceSeed(options));
  return runBridgeConsole(options.bridgeDir, command, options.waitMs);
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(String(error && error.message ? error.message : error));
    usage();
  }
  process.stdout.write(`${JSON.stringify(run(options), null, 2)}\n`);
}

module.exports = {
  buildCommand,
  isRawLastPlaceSeed,
  normalizeHash,
  parseRawProcessEventCaptureLines,
  parseArgs,
  resolveDynamicPlaceSeed,
};

if (require.main === module) {
  main();
}
