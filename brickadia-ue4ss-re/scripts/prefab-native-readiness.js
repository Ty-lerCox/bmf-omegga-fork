#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { diagnose, summarizeReport } = require('./diagnose-prefab-vehicle-structure.js');
const { evaluateWatcherPayload } = require('./verify-prefab-native-vehicle-replay.js');
const {
  CONTINUE_CAPTURE_KINDS,
  DEFAULT_POST_DUMP_ACTORS,
  summarizeActorDump,
} = require('./wait-prefab-native-capture-replay.js');

const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_BRIDGE_DIR = path.resolve(
  REPO_ROOT,
  '..',
  'omegga-master',
  'omegga-master',
  'data',
  'ue4ss-bridge-test-7799',
);
const REPLAYABLE_CAPTURE_KINDS = new Set([
  'ServerPastePrefab',
  'ServerPlaceCurrentPrefab',
  'ServerPlaceSimpleEntityVolume',
]);
const SEND_RPC = path.join(__dirname, 'send-bridge-rpc.js');

function usage() {
  console.error([
    'usage: node prefab-native-readiness.js [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>       UE4SS bridge directory',
    '  --wait-ms <ms>           Bridge wait timeout per RPC, default 6000',
    '  --source-brz <path>      Optional source prefab to sanity-check',
    '  --check-players <0|1>    Also call players.list, default 0',
    '  --dump-actors <0|1>      Include a targeted dynamic-vehicle actor dump summary',
    `  --actor-classes <list>   Classes for --dump-actors, default ${DEFAULT_POST_DUMP_ACTORS}`,
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

function runOptionalRpc(bridgeDir, method, extraArgs, waitMs) {
  try {
    return {
      ...runRpc(bridgeDir, method, extraArgs, waitMs),
      unavailable: false,
      error: null,
    };
  } catch (error) {
    let response = null;
    if (error && typeof error.stdout === 'string' && error.stdout.trim()) {
      try {
        response = JSON.parse(error.stdout);
      } catch (_parseError) {
        response = { raw_stdout: error.stdout };
      }
    }
    return {
      response,
      unavailable: true,
      error: String(error && error.message ? error.message : error),
    };
  }
}

function runConsole(bridgeDir, command, waitMs) {
  const response = runRpc(bridgeDir, 'console.exec', ['--command-raw', command], waitMs);
  return {
    response,
    lines: (response.chunks || []).map((chunk) => chunk.line || ''),
  };
}

function runOptionalConsole(bridgeDir, command, waitMs) {
  try {
    return {
      ...runConsole(bridgeDir, command, waitMs),
      unavailable: false,
      error: null,
    };
  } catch (error) {
    let response = null;
    if (error && typeof error.stdout === 'string' && error.stdout.trim()) {
      try {
        response = JSON.parse(error.stdout);
      } catch (_parseError) {
        response = { raw_stdout: error.stdout };
      }
    }
    return {
      response,
      lines: response && Array.isArray(response.chunks)
        ? response.chunks.map((chunk) => chunk.line || '')
        : [],
      unavailable: true,
      error: String(error && error.message ? error.message : error),
    };
  }
}

function boolArg(value, defaultValue) {
  if (value == null) {
    return defaultValue;
  }
  return value === '1' || value.toLowerCase() === 'true' || value.toLowerCase() === 'yes';
}

function readLiveActorDump(bridgeDir, classes, waitMs) {
  const command = `Omegga.Bridge.DumpPrefabActors ${classes}`;
  const dump = runConsole(bridgeDir, command, Math.max(waitMs, 10000));
  return {
    command,
    executor: dump.response.result && dump.response.result.executor,
    success: dump.response.complete && dump.response.complete.success,
    line_count: dump.lines.length,
    summary: summarizeActorDump(dump.lines),
  };
}

function parseKeyValueLines(lines) {
  const out = {};
  for (const line of lines) {
    const match = String(line).match(/^([^=]+)=(.*)$/);
    if (match) {
      out[match[1]] = match[2];
    }
  }
  return out;
}

function parseContextLines(lines) {
  const state = {
    available: null,
    source: null,
    context: null,
    cachedPlayerStates: null,
    findFirst: {},
  };

  for (const line of lines) {
    let match = String(line).match(/^context_available=(true|false|nil)$/);
    if (match) {
      state.available = match[1] === 'true';
      continue;
    }

    match = String(line).match(/^context_source=(.*)$/);
    if (match) {
      state.source = match[1];
      continue;
    }

    match = String(line).match(/^context=(.*)$/);
    if (match) {
      state.context = match[1];
      continue;
    }

    match = String(line).match(/^cached_player_states=(\d+)$/);
    if (match) {
      state.cachedPlayerStates = Number(match[1]);
      continue;
    }

    match = String(line).match(/^find_first\s+([^=]+)=(true|false|nil)(?:\s+object=(.*))?$/);
    if (match) {
      state.findFirst[match[1]] = {
        available: match[2] === 'true',
        object: match[3] || null,
      };
    }
  }

  return state;
}

function parseHookLines(lines) {
  const state = {
    registered: false,
    registeredKinds: {},
    captureEvents: 0,
    lastCapture: null,
    lastClientCapture: null,
    lastReplayableClientCapture: null,
    lastReplayCapture: null,
  };

  for (const line of lines) {
    let match = line.match(/^registered=(true|false)$/);
    if (match) {
      state.registered = match[1] === 'true';
      continue;
    }

    match = line.match(/^registered_kind\s+([^=]+)=(.*)$/);
    if (match) {
      state.registeredKinds[match[1]] = match[2];
      continue;
    }

    match = line.match(/^capture_events=(\d+)$/);
    if (match) {
      state.captureEvents = Number(match[1]);
      continue;
    }

    match = line.match(/^last_capture=([^ ]+)(?: source=(.*))?$/);
    if (match) {
      state.lastCapture = match[1] === '<none>' ? null : { kind: match[1], source: match[2] || null };
      continue;
    }

    match = line.match(/^last_client_capture=(.*)$/);
    if (match) {
      state.lastClientCapture = match[1] === '<none>' ? null : match[1];
      continue;
    }

    match = line.match(/^last_replayable_client_capture=(.*)$/);
    if (match) {
      state.lastReplayableClientCapture = match[1] === '<none>' ? null : match[1];
      continue;
    }

    match = line.match(/^last_replay_capture=(.*)$/);
    if (match) {
      state.lastReplayCapture = match[1] === '<none>' ? null : match[1];
    }
  }

  return state;
}

function fileInfo(filePath) {
  if (!fs.existsSync(filePath)) {
    return { exists: false, bytes: 0, updatedAt: null };
  }
  const stats = fs.statSync(filePath);
  return {
    exists: true,
    bytes: stats.size,
    updatedAt: stats.mtime.toISOString(),
  };
}

function readStatus(bridgeDir) {
  const statusPath = path.join(bridgeDir, 'status.json');
  if (!fs.existsSync(statusPath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(statusPath, 'utf8'));
  } catch (error) {
    return { parse_error: String(error) };
  }
}

function readJsonFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    return { parse_error: String(error) };
  }
}

function processIsAlive(pid) {
  const number = Number(pid);
  if (!Number.isInteger(number) || number <= 0) {
    return null;
  }
  try {
    process.kill(number, 0);
    return true;
  } catch (error) {
    return false;
  }
}

function readLocalBrickadiaProcesses() {
  if (process.platform !== 'win32') {
    return null;
  }

  try {
    const command = [
      '$ErrorActionPreference = "Stop"',
      '$processes = Get-Process | Where-Object { $_.ProcessName -like "Brickadia*" }',
      '$processes | Select-Object Id,ProcessName,MainWindowTitle | ConvertTo-Json -Compress',
    ].join('; ');
    const raw = execFileSync(
      'powershell.exe',
      ['-NoProfile', '-Command', command],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    ).trim();
    if (!raw) {
      return [];
    }
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (error) {
    return {
      error: String(error && error.message ? error.message : error),
    };
  }
}

function readWatcherStatus(bridgeDir) {
  const statusPath = path.join(bridgeDir, 'prefab-native-watch-status.json');
  const status = readJsonFile(statusPath);
  const info = fileInfo(statusPath);
  const updatedAt = status && status.updated_at ? Date.parse(status.updated_at) : NaN;
  const startedAt = status && status.started_at ? Date.parse(status.started_at) : NaN;
  const alive = status ? processIsAlive(status.pid) : null;
  return {
    file: info,
    status,
    process_alive: alive,
    age_ms: Number.isFinite(updatedAt) ? Date.now() - updatedAt : null,
    uptime_ms: Number.isFinite(startedAt) ? Date.now() - startedAt : null,
    stale: Boolean(status && (alive === false || (Number.isFinite(updatedAt) && Date.now() - updatedAt > 30000))),
  };
}

function readSourcePrefabStatus(sourcePath) {
  if (!sourcePath) {
    return null;
  }
  const input = path.resolve(sourcePath);
  try {
    return {
      ok: true,
      ...summarizeReport(diagnose(input)),
    };
  } catch (error) {
    return {
      ok: false,
      input,
      error: String(error && error.message ? error.message : error),
    };
  }
}

function deriveReadinessStatus({
  hookState,
  readyForClientPaste,
  playerCount,
  vehicleReplayVerdict,
}) {
  if (vehicleReplayVerdict && vehicleReplayVerdict.ok) {
    return 'vehicle-replay-coherent';
  }

  if (vehicleReplayVerdict
    && vehicleReplayVerdict.status === 'vehicle-replay-unverified'
    && vehicleReplayVerdict.checks
    && vehicleReplayVerdict.checks.watcherFinished) {
    return 'vehicle-replay-unverified';
  }

  const effectiveClientCapture = hookState.lastReplayableClientCapture || hookState.lastClientCapture;

  if (effectiveClientCapture && !CONTINUE_CAPTURE_KINDS.has(effectiveClientCapture)) {
    return REPLAYABLE_CAPTURE_KINDS.has(effectiveClientCapture)
      ? 'prefab-capture-ready'
      : 'client-capture-non-prefab';
  }

  if (readyForClientPaste) {
    return playerCount === 0 ? 'ready-waiting-for-player' : 'ready-for-client-paste';
  }

  return 'not-ready';
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const bridgeDir = path.resolve(args.dir || DEFAULT_BRIDGE_DIR);
  const waitMs = Math.max(1000, Number(args['wait-ms'] || 6000));
  const sourcePrefab = readSourcePrefabStatus(args['source-brz']);
  const checkPlayers = boolArg(args['check-players'], false);
  const dumpActors = boolArg(args['dump-actors'], false);
  const actorClasses = args['actor-classes'] || DEFAULT_POST_DUMP_ACTORS;

  const ping = runRpc(
    bridgeDir,
    'bridge.ping',
    ['--params-json', JSON.stringify({ nonce: `prefab-readiness-${Date.now()}` })],
    waitMs,
  );
  const hooks = runConsole(bridgeDir, 'Omegga.Bridge.DescribePrefabNativeHooks 12', waitMs);
  const replay = runConsole(bridgeDir, 'Omegga.Bridge.DescribePrefabNativeReplay', waitMs);
  const context = runOptionalConsole(
    bridgeDir,
    'Omegga.Bridge.DescribeServerPastePrefabContext',
    Math.min(waitMs, 2500),
  );
  const players = checkPlayers
    ? runOptionalRpc(bridgeDir, 'players.list', [], waitMs)
    : {
        skipped: true,
        unavailable: false,
        error: null,
      };

  const hookState = parseHookLines(hooks.lines);
  const replayState = parseKeyValueLines(replay.lines);
  const contextState = parseContextLines(context.lines);
  const explicitPlayerCount = players.result && players.result.count != null
    ? Number(players.result.count)
    : null;
  const contextPlayerCount = Number(contextState.cachedPlayerStates);
  const playerCount = Number.isFinite(explicitPlayerCount)
    ? explicitPlayerCount
    : Number.isFinite(contextPlayerCount)
      ? contextPlayerCount
      : null;
  const captureFile = fileInfo(path.join(bridgeDir, 'prefab-native-last.txt'));
  const captureNdjson = fileInfo(path.join(bridgeDir, 'prefab-native-captures.ndjson'));
  const watcher = readWatcherStatus(bridgeDir);
  const vehicleReplayVerdict = evaluateWatcherPayload(watcher.status);
  const liveActorDump = dumpActors
    ? readLiveActorDump(bridgeDir, actorClasses, waitMs)
    : null;
  const localBrickadiaProcesses = readLocalBrickadiaProcesses();

  const requiredKinds = [
    'ServerPastePrefab',
    'ServerPlaceCurrentPrefab',
    'ServerPlaceSimpleEntityVolume',
    'ServerPasteEntity',
    'ServerPasteBrick',
  ];
  const missingRequiredKinds = requiredKinds.filter((kind) => !hookState.registeredKinds[kind]);
  const readyForClientPaste = Boolean(
    ping.result
      && ping.result.pong
      && hookState.registered
      && missingRequiredKinds.length === 0
      && replayState.helper_available === 'true',
  );

  const status = deriveReadinessStatus({
    hookState,
    readyForClientPaste,
    playerCount,
    vehicleReplayVerdict,
  });
  const directHashPasteReady = Boolean(
    ping.result
      && ping.result.pong
      && replayState.helper_available === 'true'
      && contextState.available === true,
  );

  let nextAction = 'Join 127.0.0.1:7799 and paste one vehicle prefab through the normal client UI.';
  if (vehicleReplayVerdict.ok) {
    nextAction = 'Vehicle native replay is coherent according to the watcher verifier; inspect in-game if visual confirmation is still needed.';
  } else if (status === 'vehicle-replay-unverified') {
    nextAction = `Vehicle native replay is not verified: ${vehicleReplayVerdict.reasons.join(' ')}`;
  } else if (hookState.lastReplayableClientCapture) {
    nextAction = 'Replay the retained replayable client prefab capture.';
  } else if (hookState.lastClientCapture && CONTINUE_CAPTURE_KINDS.has(hookState.lastClientCapture)) {
    nextAction = `Ignored ${hookState.lastClientCapture}; keep waiting for ServerPastePrefab, ServerPlaceCurrentPrefab, or ServerPlaceSimpleEntityVolume.`;
  } else if (hookState.lastClientCapture) {
    nextAction = 'Decode or replay the latest client capture.';
  } else if (!vehicleReplayVerdict.ok && readyForClientPaste && playerCount === 0) {
    nextAction = watcher.status && watcher.process_alive
      ? 'Join 127.0.0.1:7799 and paste through the normal client UI; the capture watcher is also polling native hooks in case player_count is stale.'
      : 'Join 127.0.0.1:7799 first; hooks are armed but the server has no connected players.';
  } else if (!hookState.registered && replayState.helper_available === 'true') {
    nextAction = directHashPasteReady
      ? 'Use wait-cached-prefab-hash-paste.js after manually spawning a known-good vehicle, or run wait-paste-prefab-hash.js directly if the target hash is already cached server-side.'
      : 'Start wait-cached-prefab-hash-paste.js, then join 127.0.0.1:7799 and manually spawn a known-good vehicle so the direct hash paste uses the exact server-cached prefab. Native capture hooks are not armed.';
  }
  if (readyForClientPaste && contextState.available === false) {
    nextAction += ' Direct hash paste cannot run yet because no ServerPastePrefab player-controller context is available.';
  }
  if (Array.isArray(localBrickadiaProcesses) && localBrickadiaProcesses.length === 0) {
    nextAction += ' No local Brickadia client process is running.';
  }
  if (sourcePrefab && sourcePrefab.ok && sourcePrefab.bIsPhysicsGrid === false) {
    nextAction += ' The selected source prefab is not marked as a physics grid; use a bIsPhysicsGrid=true gallery prefab or the patched artifact before testing dynamic vehicle behavior.';
  }
  if (sourcePrefab && sourcePrefab.ok === false) {
    nextAction += ' The selected source prefab could not be inspected.';
  }

  console.log(JSON.stringify({
    status,
    bridge_dir: bridgeDir,
    bridge_status: readStatus(bridgeDir),
    ping_ok: Boolean(ping.result && ping.result.pong),
    ready_for_client_paste: readyForClientPaste,
    direct_hash_paste_ready: directHashPasteReady,
    player_count: Number.isFinite(playerCount) ? playerCount : null,
    players: {
      skipped: players.skipped === true,
      unavailable: players.unavailable,
      error: players.error,
      timeout: Boolean(players.response && players.response.timeout),
      executor: players.result && players.result.executor,
    },
    hooks: hookState,
    replay: {
      unsafe_probes: replayState.unsafe_probes || null,
      helper_available: replayState.helper_available || null,
      last_replay: replayState.last_replay || null,
      last_capture: replayState.last_capture || null,
    },
    server_paste_context: {
      executor: context.response && context.response.result && context.response.result.executor,
      unavailable: context.unavailable,
      error: context.error,
      available: contextState.available,
      source: contextState.source,
      context: contextState.context,
      cached_player_states: contextState.cachedPlayerStates,
      find_first: contextState.findFirst,
    },
    local_brickadia_processes: localBrickadiaProcesses,
    files: {
      latest_capture: captureFile,
      capture_ndjson: captureNdjson,
      watcher_status: watcher.file,
      inbox: fileInfo(path.join(bridgeDir, 'inbox.ndjson')),
      outbox: fileInfo(path.join(bridgeDir, 'outbox.ndjson')),
      log: fileInfo(path.join(bridgeDir, 'bridge.log')),
    },
    watcher,
    vehicle_replay_verdict: vehicleReplayVerdict,
    live_actor_dump: liveActorDump,
    source_prefab: sourcePrefab,
    missing_required_hook_kinds: missingRequiredKinds,
    next_action: nextAction,
  }, null, 2));
}

module.exports = {
  deriveReadinessStatus,
  parseContextLines,
  parseHookLines,
  parseKeyValueLines,
  readLiveActorDump,
  readWatcherStatus,
};

if (require.main === module) {
  main();
}
