#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

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

const RAW_CAPTURE_TARGETS = [
  'ServerPastePrefab',
  'ServerPlaceCurrentPrefab',
  'ServerPlaceSimpleEntityVolume',
  'RequestLoadWorldAdditive',
  'ApplyPrefabState',
  'ClientLoadWorldAccepted',
  'ClientLoadWorldRejected',
  'CommitPlacement',
  'HandleAttachedPlacement',
  'ServerPasteEntity',
  'ServerModifyEntity',
  'SetPlaceAsPhysicsEnabled',
];

function usage() {
  console.error([
    'usage: node wait-raw-native-prefab-replay.js [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>       UE4SS bridge directory',
    '  --place-grid <x,y,z>      Grid for ServerPlaceCurrentPrefab replay, default 120,60,96',
    '  --paste-args <text>       Args after ReplayLastRawNativeFunctionCapture ServerPastePrefab, default exact',
    '  --timeout-ms <ms>         Total wait timeout, default 900000',
    '  --poll-ms <ms>            Poll interval, default 1000',
    '  --wait-ms <ms>            Bridge wait timeout per RPC, default 8000',
    '  --status-path <path|0>    Periodic status JSON path, default <bridge_dir>/raw-native-prefab-replay-status.json',
    '  --status-interval-ms <ms> Status write interval, default 5000',
    '  --server-log <path>       Brickadia server log, default inferred from bridge dir',
    '  --arm <0|1>               Arm raw capture before polling, default 1',
    '  --dry-run <0|1>           Do not replay after capture, default 0',
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

function boolArg(value, defaultValue) {
  if (value == null) {
    return defaultValue;
  }
  return /^(1|true|yes|on)$/i.test(String(value));
}

function numberArg(value, defaultValue, name) {
  if (value == null) {
    return defaultValue;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`${name} must be a non-negative number`);
  }
  return parsed;
}

function parseGrid(value) {
  const match = String(value || '').trim().match(/^(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)$/);
  if (!match) {
    throw new Error('--place-grid must have form x,y,z');
  }
  return {
    x: Number(match[1]),
    y: Number(match[2]),
    z: Number(match[3]),
  };
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function writeStatus(filePath, payload) {
  if (!filePath) {
    return;
  }
  const status = {
    ...payload,
    updated_at: new Date().toISOString(),
    pid: process.pid,
  };
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, `${JSON.stringify(status, null, 2)}\n`, 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function runRpc(bridgeDir, method, extraArgs, waitMs) {
  const raw = execFileSync(
    process.execPath,
    [
      SEND_RPC,
      '--dir',
      bridgeDir,
      '--method',
      method,
      ...extraArgs,
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

function runConsole(bridgeDir, command, waitMs) {
  const response = runRpc(bridgeDir, 'console.exec', ['--command-raw', command], waitMs);
  return {
    command,
    response,
    accepted: response.result && response.result.accepted === true,
    executor: response.result && response.result.executor,
    completeSuccess: response.complete && response.complete.success === true,
    lines: (response.chunks || []).map((chunk) => chunk.line || ''),
  };
}

function parseKeyValueLines(lines) {
  const values = {};
  for (const line of lines || []) {
    const match = String(line).match(/^([^=]+)=(.*)$/);
    if (match) {
      values[match[1]] = match[2];
    }
  }
  return values;
}

function parseHistory(lines) {
  const history = [];
  for (const line of lines || []) {
    const match = String(line).match(
      /^history\[(\d+)\]=seq=(\d+)\s+source=([^ ]*)\s+label=([^ ]*)\s+function=(.*?)\s+context_pointer=([^ ]*)\s+bytes=(\d+)$/,
    );
    if (!match) {
      continue;
    }
    history.push({
      index: Number(match[1]),
      sequence: Number(match[2]),
      source: match[3],
      label: match[4],
      function: match[5],
      contextPointer: match[6],
      bytes: Number(match[7]),
      raw: line,
    });
  }
  return history;
}

function summarizeRawCapture(describe) {
  const values = parseKeyValueLines(describe.lines);
  const history = parseHistory(describe.lines);
  const clientPaste = history.find((entry) => entry.source === 'client' && entry.label === 'ServerPastePrefab');
  const clientPlace = history.find((entry) => entry.source === 'client' && entry.label === 'ServerPlaceCurrentPrefab');
  return {
    enabled: values.enabled === 'true',
    historyCount: Number(values.history_count || history.length || 0),
    lastCapture: values.last_capture || null,
    targetFunctionHooks: Number(values.target_function_hooks || 0),
    processEventHookActive: values.process_event_hook_active === 'true',
    history,
    clientPaste,
    clientPlace,
    ready: Boolean(clientPaste && clientPlace),
  };
}

function readLogSize(serverLog) {
  try {
    return fs.statSync(serverLog).size;
  } catch (_) {
    return 0;
  }
}

function readLogSince(serverLog, startOffset) {
  try {
    const fd = fs.openSync(serverLog, 'r');
    const stat = fs.fstatSync(fd);
    const start = Math.max(0, Math.min(startOffset || 0, stat.size));
    const length = stat.size - start;
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, start);
    fs.closeSync(fd);
    return buffer.toString('utf8');
  } catch (error) {
    return '';
  }
}

function extractPrefabLogEvidence(text) {
  const lines = String(text || '').split(/\r?\n/).filter(Boolean);
  return lines.filter((line) => (
    line.includes('LogBrickPrefabs:')
    || line.includes('RequestLoadWorldAdditive')
    || line.includes('ClientLoadWorldAccepted')
    || line.includes('ClientLoadWorldRejected')
  ));
}

function main() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(String(error));
    usage();
  }

  let options;
  try {
    const bridgeDir = path.resolve(args.dir || DEFAULT_BRIDGE_DIR);
    options = {
      bridgeDir,
      placeGrid: parseGrid(args['place-grid'] || '120,60,96'),
      pasteArgs: args['paste-args'] || 'exact',
      timeoutMs: numberArg(args['timeout-ms'], 900000, '--timeout-ms'),
      pollMs: Math.max(50, numberArg(args['poll-ms'], 1000, '--poll-ms')),
      waitMs: Math.max(1000, numberArg(args['wait-ms'], 8000, '--wait-ms')),
      statusPath: args['status-path'] === '0'
        ? null
        : path.resolve(args['status-path'] || path.join(bridgeDir, 'raw-native-prefab-replay-status.json')),
      statusIntervalMs: Math.max(250, numberArg(args['status-interval-ms'], 5000, '--status-interval-ms')),
      serverLog: path.resolve(args['server-log'] || path.join(bridgeDir, '..', 'Saved', 'Logs', 'Brickadia.log')),
      arm: boolArg(args.arm, true),
      dryRun: boolArg(args['dry-run'], false),
    };
  } catch (error) {
    console.error(String(error));
    process.exit(2);
  }

  const startedAt = new Date().toISOString();
  const deadline = Date.now() + options.timeoutMs;
  let lastStatusAt = 0;
  let statusSeq = 0;
  let lastSummary = null;

  const emitStatus = (status, extra = {}, force = false) => {
    const now = Date.now();
    if (!force && now - lastStatusAt < options.statusIntervalMs) {
      return;
    }
    lastStatusAt = now;
    statusSeq += 1;
    writeStatus(options.statusPath, {
      status,
      seq: statusSeq,
      started_at: startedAt,
      bridge_dir: options.bridgeDir,
      place_grid: options.placeGrid,
      dry_run: options.dryRun,
      last_summary: lastSummary,
      ...extra,
    });
  };

  try {
    if (options.arm) {
      const armCommand = `Omegga.Bridge.ArmRawProcessEventCapture ${RAW_CAPTURE_TARGETS.join(' ')}`;
      const armResult = runConsole(options.bridgeDir, armCommand, options.waitMs);
      emitStatus('armed-waiting-for-capture', { arm: armResult }, true);
    }

    while (Date.now() < deadline) {
      const describe = runConsole(
        options.bridgeDir,
        'Omegga.Bridge.DescribeRawProcessEventCapture',
        options.waitMs,
      );
      lastSummary = summarizeRawCapture(describe);

      if (!lastSummary.ready) {
        emitStatus('waiting-for-client-vehicle-spawn', {
          describe,
          missing: {
            ServerPastePrefab: !lastSummary.clientPaste,
            ServerPlaceCurrentPrefab: !lastSummary.clientPlace,
          },
        });
        sleep(options.pollMs);
        continue;
      }

      if (options.dryRun) {
        emitStatus('capture-ready-dry-run', { describe }, true);
        process.stdout.write(`${JSON.stringify({
          status: 'capture-ready-dry-run',
          bridge_dir: options.bridgeDir,
          summary: lastSummary,
          describe,
        }, null, 2)}\n`);
        return;
      }

      const logOffset = readLogSize(options.serverLog);
      const pasteReplay = runConsole(
        options.bridgeDir,
        `Omegga.Bridge.ReplayLastRawNativeFunctionCapture ServerPastePrefab ${options.pasteArgs}`,
        options.waitMs,
      );
      sleep(750);
      const placeReplay = runConsole(
        options.bridgeDir,
        `Omegga.Bridge.ReplayLastRawNativeFunctionCapture ServerPlaceCurrentPrefab grid ${options.placeGrid.x} ${options.placeGrid.y} ${options.placeGrid.z}`,
        options.waitMs,
      );
      sleep(3000);
      const replayDescribe = runConsole(
        options.bridgeDir,
        'Omegga.Bridge.DescribeRawProcessEventCapture',
        options.waitMs,
      );
      const logText = readLogSince(options.serverLog, logOffset);
      const prefabLogEvidence = extractPrefabLogEvidence(logText);

      const result = {
        status: 'replayed',
        bridge_dir: options.bridgeDir,
        server_log: options.serverLog,
        summary: lastSummary,
        paste_replay: pasteReplay,
        place_replay: placeReplay,
        replay_summary: summarizeRawCapture(replayDescribe),
        replay_describe: replayDescribe,
        prefab_log_evidence: prefabLogEvidence,
      };
      emitStatus('replayed', result, true);
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
      return;
    }

    const timeoutResult = {
      status: 'timeout',
      bridge_dir: options.bridgeDir,
      timeout_ms: options.timeoutMs,
      last_summary: lastSummary,
    };
    emitStatus('timeout', timeoutResult, true);
    process.stdout.write(`${JSON.stringify(timeoutResult, null, 2)}\n`);
    process.exitCode = 1;
  } catch (error) {
    const failure = {
      status: 'error',
      bridge_dir: options.bridgeDir,
      error: String(error && error.stack ? error.stack : error),
      last_summary: lastSummary,
    };
    emitStatus('error', failure, true);
    console.error(JSON.stringify(failure, null, 2));
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  parseGrid,
  parseHistory,
  parseKeyValueLines,
  summarizeRawCapture,
  extractPrefabLogEvidence,
};
