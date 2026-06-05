#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const {
  isRawLastPlaceSeed,
  parseRawProcessEventCaptureLines,
} = require('./paste-prefab-hash.js');

const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_BRIDGE_DIR = path.resolve(
  REPO_ROOT,
  '..',
  'omegga-master',
  'omegga-master',
  'data',
  'ue4ss-bridge-test-7799',
);
const DEFAULT_BRICKADIA_LOG = path.resolve(
  REPO_ROOT,
  '..',
  'omegga-master',
  'omegga-master',
  'data',
  'Saved',
  'Logs',
  'Brickadia.log',
);
const WAIT_PASTE = path.join(__dirname, 'wait-paste-prefab-hash.js');
const SEND_RPC = path.join(__dirname, 'send-bridge-rpc.js');
const RAW_PLACE_SEED_CAPTURE_TARGETS = [
  'ServerPastePrefab',
  'ServerPlaceCurrentPrefab',
  'ServerUploadPrefab',
  'ClientUploadPrefab',
  'ClientNotifyPrefabCaptureComplete',
  'ClientNotifyPrefabCaptureFailed',
];

function usage() {
  console.error([
    'usage: node wait-cached-prefab-hash-paste.js --grid <x> <y> <z> [options]',
    '',
    'Start this before manually spawning a known-good vehicle prefab. The script',
    'waits for the server to cache that prefab, then pastes the same cached hash.',
    '',
    'Options:',
    '  --dir <bridge_dir>              UE4SS bridge directory',
    '  --log <Brickadia.log>           Server log path',
    '  --grid <x> <y> <z>              Direct paste target grid',
    '  --orientation <0-255>           Placement orientation, default 0',
    '  --target <0|last|hex>           PasteInfo target pointer, default 0',
    '  --paste-seed <seed>             ServerPastePrefab seed: hex:<param_hex>',
    '  --ownership <0|1>               bWithOwnership, default 1',
    '  --temp <0|1>                    bInTemp, default 0',
    '  --dry-run <0|1>                 Build buffer without ProcessEvent, default 0',
    '  --place-current-prefab <0|1>    Also invoke ServerPlaceCurrentPrefab after ServerPastePrefab, default 0',
    '  --place-seed <seed>             ServerPlaceCurrentPrefab seed: default, last, rawlast, or hex:<param_hex>',
    '  --place-adjust <mode>           ServerPlaceCurrentPrefab adjustment: primary or full, default primary',
    '  --from-current-end <0|1>        Ignore older log lines, default 1',
    '  --require-additive-load <0|1>   Wait for additive load success, default 1',
    '  --timeout-ms <ms>               Total wait for cache/log/context, default 300000',
    '  --poll-ms <ms>                  Poll interval, default 1000',
    '  --wait-ms <ms>                  Bridge wait timeout per RPC, default 10000',
    '  --status-path <file.json>       Status file, default <bridge_dir>/cached-prefab-hash-paste-status.json',
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

function boolArg(value, defaultValue) {
  if (value == null) {
    return defaultValue;
  }
  const text = String(value).toLowerCase();
  return text === '1' || text === 'true' || text === 'yes' || text === 'on';
}

function positiveInt(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${label} must be positive`);
  }
  return Math.floor(parsed);
}

function parseArgs(argv) {
  const out = {
    bridgeDir: DEFAULT_BRIDGE_DIR,
    logPath: DEFAULT_BRICKADIA_LOG,
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
    placeSeed: 'default',
    placeAdjust: 'primary',
    fromCurrentEnd: true,
    requireAdditiveLoad: true,
    timeoutMs: 300000,
    pollMs: 1000,
    waitMs: 10000,
    statusPath: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--dir') {
      out.bridgeDir = path.resolve(takeValue(argv, i, arg));
      i += 1;
    } else if (arg === '--log') {
      out.logPath = path.resolve(takeValue(argv, i, arg));
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
      out.dryRun = boolArg(takeValue(argv, i, arg), false);
      i += 1;
    } else if (arg === '--place-current-prefab' || arg === '--paste-and-place') {
      out.placeCurrentPrefab = boolArg(takeValue(argv, i, arg), false);
      i += 1;
    } else if (arg === '--place-seed' || arg === '--place-param-hex') {
      out.placeSeed = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--place-adjust') {
      out.placeAdjust = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--from-current-end') {
      out.fromCurrentEnd = boolArg(takeValue(argv, i, arg), true);
      i += 1;
    } else if (arg === '--require-additive-load') {
      out.requireAdditiveLoad = boolArg(takeValue(argv, i, arg), true);
      i += 1;
    } else if (arg === '--timeout-ms') {
      out.timeoutMs = positiveInt(takeValue(argv, i, arg), arg);
      i += 1;
    } else if (arg === '--poll-ms') {
      out.pollMs = positiveInt(takeValue(argv, i, arg), arg);
      i += 1;
    } else if (arg === '--wait-ms') {
      out.waitMs = positiveInt(takeValue(argv, i, arg), arg);
      i += 1;
    } else if (arg === '--status-path') {
      out.statusPath = path.resolve(takeValue(argv, i, arg));
      i += 1;
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }

  if (!out.grid) {
    throw new Error('missing --grid x y z');
  }
  if (!out.statusPath) {
    out.statusPath = path.join(out.bridgeDir, 'cached-prefab-hash-paste-status.json');
  }

  return out;
}

function parseCacheLine(line) {
  const text = String(line || '');
  let match = text.match(
    /LogBrickPrefabs: Caching prefab from serialized data \(Hash=([0-9A-Fa-f]{64}), DataSize=(\d+) bytes\)/,
  );
  if (!match) {
    match = text.match(
      /LogBrickPrefabs: Serialization complete \(Hash=([0-9A-Fa-f]{64}), Size=(\d+) bytes\)/,
    );
  }
  if (!match) {
    match = text.match(
      /LogBrickPrefabs: Added prefab to cache \(Hash=([0-9A-Fa-f]{64}), Size=(\d+) bytes/,
    );
  }
  if (!match) {
    return null;
  }
  return {
    hash: match[1].toUpperCase(),
    dataSize: Number(match[2]),
    line,
  };
}

function parseAdditiveSuccessLine(line) {
  return String(line || '').includes('LogBRWorldManager: World successfully loaded additively.')
    ? { line }
    : null;
}

function parseLogEvents(text) {
  const events = [];
  for (const line of String(text || '').split(/\r?\n/)) {
    const cache = parseCacheLine(line);
    if (cache) {
      events.push({ type: 'cache', ...cache });
      continue;
    }
    const additive = parseAdditiveSuccessLine(line);
    if (additive) {
      events.push({ type: 'additive-success', ...additive });
    }
  }
  return events;
}

function readNewLogText(logPath, offset) {
  if (!fs.existsSync(logPath)) {
    return { text: '', offset: 0 };
  }
  const stat = fs.statSync(logPath);
  const safeOffset = stat.size < offset ? 0 : offset;
  const fd = fs.openSync(logPath, 'r');
  try {
    const length = stat.size - safeOffset;
    if (length <= 0) {
      return { text: '', offset: stat.size };
    }
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, safeOffset);
    return { text: buffer.toString('utf8'), offset: stat.size };
  } finally {
    fs.closeSync(fd);
  }
}

function writeStatus(statusPath, status) {
  fs.mkdirSync(path.dirname(statusPath), { recursive: true });
  fs.writeFileSync(statusPath, `${JSON.stringify(status, null, 2)}\n`);
}

function runConsole(bridgeDir, command, waitMs) {
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
      cwd: REPO_ROOT,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  return JSON.parse(raw);
}

function armRawPlaceSeedCapture(options) {
  if (!options.placeCurrentPrefab || !isRawLastPlaceSeed(options.placeSeed)) {
    return null;
  }
  const command = `Omegga.Bridge.ArmRawProcessEventCapture ${RAW_PLACE_SEED_CAPTURE_TARGETS.join(' ')}`;
  const response = runConsole(options.bridgeDir, command, options.waitMs);
  return {
    command,
    executor: response.result && response.result.executor,
    complete_success: response.complete && response.complete.success,
    lines: (response.chunks || []).map((chunk) => chunk.line || ''),
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function runWaitPaste(options, cached) {
  const args = [
    WAIT_PASTE,
    '--dir',
    options.bridgeDir,
    '--hash',
    cached.hash,
    '--grid',
    ...options.grid,
    '--timeout-ms',
    String(options.timeoutMs),
    '--poll-ms',
    String(options.pollMs),
    '--wait-ms',
    String(options.waitMs),
    '--post-dump-actors',
    '0',
  ];
  if (options.dryRun) {
    args.push('--dry-run', '1');
  }
  if (!options.pasteSeed || options.orientationSpecified || options.orientation !== '0') {
    args.push('--orientation', options.orientation);
  }
  if (!options.pasteSeed || options.ownershipSpecified || options.ownership !== '1') {
    args.push('--ownership', options.ownership);
  }
  if (!options.pasteSeed || options.tempSpecified || options.temp !== '0') {
    args.push('--temp', options.temp);
  }
  if (!options.pasteSeed || options.targetSpecified || options.target !== '0') {
    args.push('--target', options.target);
  }
  if (options.placeCurrentPrefab) {
    args.push('--place-current-prefab', '1');
  }
  if (options.pasteSeed) {
    args.push('--paste-seed', options.pasteSeed);
  }
  if (options.placeSeed && options.placeSeed !== 'default') {
    args.push('--place-seed', options.placeSeed);
  }
  if (options.placeAdjust && options.placeAdjust !== 'primary') {
    args.push('--place-adjust', options.placeAdjust);
  }

  const raw = execFileSync(process.execPath, args, {
    cwd: path.resolve(__dirname, '..', '..'),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(raw);
}

async function waitForCachedPrefab(options) {
  const startedAt = Date.now();
  let offset = 0;
  if (options.fromCurrentEnd && fs.existsSync(options.logPath)) {
    offset = fs.statSync(options.logPath).size;
  }

  let cached = null;
  let additiveSuccess = null;

  for (;;) {
    const { text, offset: nextOffset } = readNewLogText(options.logPath, offset);
    offset = nextOffset;
    for (const event of parseLogEvents(text)) {
      if (event.type === 'cache') {
        cached = {
          hash: event.hash,
          dataSize: event.dataSize,
          line: event.line,
          observed_at: new Date().toISOString(),
        };
        additiveSuccess = null;
      } else if (event.type === 'additive-success' && cached) {
        additiveSuccess = {
          line: event.line,
          observed_at: new Date().toISOString(),
        };
      }
    }

    const elapsedMs = Date.now() - startedAt;
    const status = {
      status: cached && (!options.requireAdditiveLoad || additiveSuccess)
        ? 'cached-prefab-ready'
        : 'waiting-for-cached-prefab',
      updated_at: new Date().toISOString(),
      elapsed_ms: elapsedMs,
      timeout_ms: options.timeoutMs,
      log_path: options.logPath,
      log_offset: offset,
      require_additive_load: options.requireAdditiveLoad,
      cached_prefab: cached,
      additive_success: additiveSuccess,
    };
    writeStatus(options.statusPath, status);

    if (status.status === 'cached-prefab-ready') {
      return status;
    }
    if (elapsedMs >= options.timeoutMs) {
      return {
        ...status,
        status: 'timeout-waiting-for-cached-prefab',
      };
    }

    await sleep(options.pollMs);
  }
}

function readRawPlaceSeedCapture(options) {
  const response = runConsole(
    options.bridgeDir,
    'Omegga.Bridge.DescribeRawProcessEventCapture',
    options.waitMs,
  );
  const lines = (response.chunks || []).map((chunk) => chunk.line || '');
  const capture = parseRawProcessEventCaptureLines(lines);
  const cleanHex = String(capture.paramHex || '').replace(/[^0-9a-fA-F]/g, '').toUpperCase();
  return {
    ready: (
      capture.targetLabel === 'ServerPlaceCurrentPrefab'
      && capture.replayLayout === 'ServerPlaceCurrentPrefab'
      && capture.source === 'client'
      && capture.paramBytes === 0xdf
      && cleanHex.length === 0xdf * 2
    ),
    target_label: capture.targetLabel,
    last_capture: capture.lastCapture,
    source: capture.source,
    param_bytes: Number.isFinite(capture.paramBytes) ? capture.paramBytes : null,
    replay_layout: capture.replayLayout,
    param_hex_length: cleanHex.length,
    executor: response.result && response.result.executor,
  };
}

async function waitForRawPlaceSeedCapture(options, cacheStatus, rawCaptureArm) {
  if (!options.placeCurrentPrefab || !isRawLastPlaceSeed(options.placeSeed)) {
    return null;
  }

  const startedAt = Date.now();
  let lastStatus = null;
  for (;;) {
    let capture = null;
    let error = null;
    try {
      capture = readRawPlaceSeedCapture(options);
    } catch (readError) {
      error = String(readError && readError.message ? readError.message : readError);
    }

    const elapsedMs = Date.now() - startedAt;
    lastStatus = {
      status: capture && capture.ready
        ? 'raw-place-seed-ready'
        : 'waiting-for-raw-place-seed',
      updated_at: new Date().toISOString(),
      elapsed_ms: elapsedMs,
      timeout_ms: options.timeoutMs,
      raw_place_seed_capture_arm: rawCaptureArm,
      cache: cacheStatus,
      capture,
      error,
    };
    writeStatus(options.statusPath, lastStatus);

    if (lastStatus.status === 'raw-place-seed-ready') {
      return lastStatus;
    }
    if (elapsedMs >= options.timeoutMs) {
      return {
        ...lastStatus,
        status: 'timeout-waiting-for-raw-place-seed',
      };
    }

    await sleep(options.pollMs);
  }
}

async function run(options) {
  let rawCaptureArm = null;
  try {
    rawCaptureArm = armRawPlaceSeedCapture(options);
  } catch (error) {
    return {
      ok: false,
      result: 'failed-to-arm-raw-place-seed-capture',
      status_path: options.statusPath,
      error: String(error && error.message ? error.message : error),
    };
  }

  const cacheStatus = await waitForCachedPrefab(options);
  if (cacheStatus.status !== 'cached-prefab-ready') {
    writeStatus(options.statusPath, {
      ...cacheStatus,
      raw_place_seed_capture_arm: rawCaptureArm,
    });
    return {
      ok: false,
      result: cacheStatus.status,
      status_path: options.statusPath,
      cache: cacheStatus,
      raw_place_seed_capture_arm: rawCaptureArm,
    };
  }

  const rawPlaceSeedStatus = await waitForRawPlaceSeedCapture(options, cacheStatus, rawCaptureArm);
  if (rawPlaceSeedStatus && rawPlaceSeedStatus.status !== 'raw-place-seed-ready') {
    writeStatus(options.statusPath, rawPlaceSeedStatus);
    return {
      ok: false,
      result: rawPlaceSeedStatus.status,
      status_path: options.statusPath,
      cache: cacheStatus,
      raw_place_seed_capture_arm: rawCaptureArm,
      raw_place_seed_capture: rawPlaceSeedStatus,
    };
  }

  const paste = runWaitPaste(options, cacheStatus.cached_prefab);
  const result = {
    ok: Boolean(paste.ok),
    result: paste.result || null,
    status_path: options.statusPath,
    cache: cacheStatus,
    raw_place_seed_capture_arm: rawCaptureArm,
    raw_place_seed_capture: rawPlaceSeedStatus,
    paste,
  };
  writeStatus(options.statusPath, {
    status: result.ok ? 'paste-complete' : 'paste-failed',
    updated_at: new Date().toISOString(),
    ...result,
  });
  return result;
}

async function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(String(error && error.message ? error.message : error));
    usage();
  }

  try {
    process.stdout.write(`${JSON.stringify(await run(options), null, 2)}\n`);
  } catch (error) {
    console.error(String(error && error.message ? error.message : error));
    process.exit(1);
  }
}

module.exports = {
  parseAdditiveSuccessLine,
  parseArgs,
  parseCacheLine,
  parseLogEvents,
};

if (require.main === module) {
  main();
}
