#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.error('usage: node send-bridge-rpc.js --dir <bridge_dir> --method <jsonrpc_method> [--params-json <json>] [--command-raw <text>] [--wait-ms <ms>] [--poll-ms <ms>] [--include-logs <0|1>] [--lock <0|1>] [--lock-wait-ms <ms>]');
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

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function processIsAlive(pid) {
  const value = Number(pid);
  if (!Number.isInteger(value) || value <= 0) {
    return false;
  }
  try {
    process.kill(value, 0);
    return true;
  } catch (error) {
    return false;
  }
}

function readLockOwner(lockPath) {
  const ownerPath = path.join(lockPath, 'owner.json');
  if (!fs.existsSync(ownerPath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(ownerPath, 'utf8'));
  } catch (error) {
    return { parse_error: String(error) };
  }
}

function acquireDirectoryLock(lockPath, timeoutMs, pollMs, staleMs) {
  const deadline = Date.now() + Math.max(0, timeoutMs);
  const owner = {
    pid: process.pid,
    started_at: new Date().toISOString(),
  };

  while (Date.now() <= deadline) {
    try {
      fs.mkdirSync(lockPath);
      fs.writeFileSync(path.join(lockPath, 'owner.json'), `${JSON.stringify(owner, null, 2)}\n`, 'utf8');
      return () => {
        try {
          const current = readLockOwner(lockPath);
          if (!current || current.pid === process.pid) {
            fs.rmSync(lockPath, { recursive: true, force: true });
          }
        } catch (error) {
          // Best-effort cleanup only.
        }
      };
    } catch (error) {
      if (!error || error.code !== 'EEXIST') {
        throw error;
      }
      const current = readLockOwner(lockPath);
      const startedAt = current && current.started_at ? Date.parse(current.started_at) : NaN;
      const stale = !current
        || current.parse_error
        || !processIsAlive(current.pid)
        || (Number.isFinite(startedAt) && Date.now() - startedAt > staleMs);
      if (stale) {
        fs.rmSync(lockPath, { recursive: true, force: true });
        continue;
      }
      sleep(Math.max(25, pollMs));
    }
  }

  throw new Error(`Timed out waiting for bridge RPC lock: ${lockPath}`);
}

function readNdjson(filePath, startOffset = 0) {
  if (!fs.existsSync(filePath)) {
    return [];
  }
  const bytes = fs.readFileSync(filePath);
  const offset = Math.max(0, Math.min(Number(startOffset) || 0, bytes.length));
  const text = bytes.subarray(offset).toString('utf8');
  return text
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        return { parse_error: String(error), raw: line };
      }
    });
}

function decodeBase64Fields(value) {
  if (Array.isArray(value)) {
    return value.map(decodeBase64Fields);
  }
  if (!value || typeof value !== 'object') {
    return value;
  }

  const out = {};
  for (const [key, inner] of Object.entries(value)) {
    out[key] = decodeBase64Fields(inner);
    if (key.endsWith('_b64') && typeof inner === 'string') {
      const decodedKey = key.slice(0, -4);
      try {
        out[decodedKey] = Buffer.from(inner, 'base64').toString('utf8');
      } catch (error) {
        out[decodedKey] = `base64 decode failed: ${error}`;
      }
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
if (!args.dir || !args.method) {
  usage();
}

const bridgeDir = path.resolve(args.dir);
const inboxPath = path.join(bridgeDir, 'inbox.ndjson');
const outboxPath = path.join(bridgeDir, 'outbox.ndjson');
const waitMs = Number(args['wait-ms'] || 15000);
const pollMs = Number(args['poll-ms'] || 100);
const lockEnabled = args.lock == null
  || args.lock === '1'
  || String(args.lock).toLowerCase() === 'true';
const lockWaitMs = Number(args['lock-wait-ms'] || Math.max(waitMs + 15000, 30000));
const includeLogs = args['include-logs'] == null
  || args['include-logs'] === '1'
  || String(args['include-logs']).toLowerCase() === 'true';
let params = {};
let releaseBridgeLock = null;

process.on('exit', () => {
  if (releaseBridgeLock) {
    releaseBridgeLock();
    releaseBridgeLock = null;
  }
});

if (args['params-json']) {
  try {
    params = JSON.parse(args['params-json']);
  } catch (error) {
    console.error(`invalid --params-json: ${error}`);
    process.exit(2);
  }
}

if (args['command-raw']) {
  params.command_raw = args['command-raw'];
  params.command = args['command-raw'];
}

fs.mkdirSync(bridgeDir, { recursive: true });
if (!fs.existsSync(inboxPath)) {
  fs.writeFileSync(inboxPath, '', 'utf8');
}
if (!fs.existsSync(outboxPath)) {
  fs.writeFileSync(outboxPath, '', 'utf8');
}

if (lockEnabled) {
  const lockPath = path.join(bridgeDir, '.send-bridge-rpc.lock');
  releaseBridgeLock = acquireDirectoryLock(
    lockPath,
    lockWaitMs,
    Math.min(Math.max(pollMs, 50), 1000),
    Math.max(lockWaitMs * 2, 120000),
  );
}

const outboxStartOffset = fs.statSync(outboxPath).size;
const id = Date.now() * 1000 + (process.pid % 1000);
const request = {
  jsonrpc: '2.0',
  id,
  method: args.method,
  params,
};
if (params && typeof params === 'object' && !Array.isArray(params)) {
  for (const [key, value] of Object.entries(params)) {
    if (!(key in request)) {
      request[key] = value;
    }
  }
}

fs.appendFileSync(inboxPath, `${JSON.stringify(request)}\n`, 'utf8');

const deadline = Date.now() + waitMs;
let lastSnapshot = [];

while (Date.now() < deadline) {
  const entries = readNdjson(outboxPath, outboxStartOffset);
  lastSnapshot = entries;

  let result = null;
  let error = null;
  let complete = null;
  const chunks = [];
  const logs = [];

  for (const entry of entries) {
    const decoded = decodeBase64Fields(entry);
    if (decoded.id === id && Object.prototype.hasOwnProperty.call(decoded, 'result')) {
      result = decoded.result;
    }
    if (decoded.id === id && Object.prototype.hasOwnProperty.call(decoded, 'error')) {
      error = decoded.error;
    }
    if (decoded.method === 'console.chunk' && decoded.params && decoded.params.request_id === id) {
      chunks.push(decoded.params);
    }
    if (decoded.method === 'console.complete' && decoded.params && decoded.params.request_id === id) {
      complete = decoded.params;
    }
    if (includeLogs && decoded.method === 'bridge.log') {
      logs.push(decoded.params);
    }
  }

  const payload = {
    id,
    request,
    result,
    error,
    chunks,
    complete,
    logs,
    inbox_path: inboxPath,
    outbox_path: outboxPath,
  };

  if (error || (result && args.method !== 'console.exec') || (result && complete)) {
    console.log(JSON.stringify(payload, null, 2));
    if (releaseBridgeLock) {
      releaseBridgeLock();
      releaseBridgeLock = null;
    }
    process.exit(error ? 1 : 0);
  }

  sleep(pollMs);
}

console.log(JSON.stringify({
  id,
  request,
  timeout: true,
  entries_seen: lastSnapshot.length,
  inbox_path: inboxPath,
  outbox_path: outboxPath,
}, null, 2));
if (releaseBridgeLock) {
  releaseBridgeLock();
  releaseBridgeLock = null;
}
process.exit(1);
