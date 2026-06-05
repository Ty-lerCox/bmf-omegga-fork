#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const {
  buildCommand,
  normalizeHash,
  resolveDynamicPlaceSeed,
} = require('./paste-prefab-hash.js');
const {
  DEFAULT_POST_DUMP_ACTORS,
} = require('./wait-prefab-native-capture-replay.js');
const {
  parseContextLines,
  parseKeyValueLines,
  readLiveActorDump,
} = require('./prefab-native-readiness.js');

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
    'usage: node wait-paste-prefab-hash.js (--hash <64hex> | --brz <file.brz>) --grid <x> <y> <z> [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>          UE4SS bridge directory',
    '  --orientation <0-255>       Placement orientation, default 0',
    '  --target <0|last|hex>       PasteInfo target pointer, default 0',
    '  --paste-seed <seed>         ServerPastePrefab seed: hex:<param_hex>',
    '  --ownership <0|1>           bWithOwnership, default 1',
    '  --temp <0|1>                bInTemp, default 0',
    '  --dry-run <0|1>             Build the native buffer without invoking ProcessEvent, default 0',
    '  --place-current-prefab <0|1>  Also invoke ServerPlaceCurrentPrefab after ServerPastePrefab, default 0',
    '  --place-seed <seed>         ServerPlaceCurrentPrefab seed: default, last, rawlast, or hex:<param_hex>',
    '  --place-adjust <mode>       ServerPlaceCurrentPrefab adjustment: primary or full, default primary',
    '  --timeout-ms <ms>           Total wait for player-controller context, default 300000',
    '  --poll-ms <ms>              Context polling interval, default 1000',
    '  --wait-ms <ms>              Bridge wait timeout per RPC, default 10000',
    '  --status-path <file.json>   Status file, default <bridge_dir>/prefab-hash-paste-status.json',
    '  --check-players <0|1>       Also call players.list while polling, default 0',
    '  --post-dump-actors <0|1>    Dump dynamic vehicle actors after paste, default 0',
    `  --actor-classes <list>      Actor classes for dump, default ${DEFAULT_POST_DUMP_ACTORS}`,
    '  --post-delay-ms <ms>        Delay before actor dump, default 2500',
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
  return text === '1' || text === 'true' || text === 'yes';
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
    placeSeed: 'default',
    placeAdjust: 'primary',
    timeoutMs: 300000,
    pollMs: 1000,
    waitMs: 10000,
    statusPath: null,
    checkPlayers: false,
    postDumpActors: false,
    actorClasses: DEFAULT_POST_DUMP_ACTORS,
    postDelayMs: 2500,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--dir') {
      out.bridgeDir = path.resolve(takeValue(argv, i, arg));
      i += 1;
    } else if (arg === '--hash') {
      out.hash = normalizeHash(takeValue(argv, i, arg));
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
    } else if (arg === '--timeout-ms') {
      out.timeoutMs = positiveInt(takeValue(argv, i, arg), '--timeout-ms');
      i += 1;
    } else if (arg === '--poll-ms') {
      out.pollMs = positiveInt(takeValue(argv, i, arg), '--poll-ms');
      i += 1;
    } else if (arg === '--wait-ms') {
      out.waitMs = positiveInt(takeValue(argv, i, arg), '--wait-ms');
      i += 1;
    } else if (arg === '--status-path') {
      out.statusPath = path.resolve(takeValue(argv, i, arg));
      i += 1;
    } else if (arg === '--check-players') {
      out.checkPlayers = boolArg(takeValue(argv, i, arg), false);
      i += 1;
    } else if (arg === '--post-dump-actors') {
      out.postDumpActors = boolArg(takeValue(argv, i, arg), true);
      i += 1;
    } else if (arg === '--actor-classes') {
      out.actorClasses = takeValue(argv, i, arg);
      i += 1;
    } else if (arg === '--post-delay-ms') {
      out.postDelayMs = positiveInt(takeValue(argv, i, arg), '--post-delay-ms');
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
  if (!out.statusPath) {
    out.statusPath = path.join(out.bridgeDir, 'prefab-hash-paste-status.json');
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

function runConsole(bridgeDir, command, waitMs) {
  const response = runRpc(bridgeDir, 'console.exec', ['--command-raw', command], waitMs);
  return {
    response,
    lines: (response.chunks || []).map((chunk) => chunk.line || ''),
  };
}

function readPlayers(bridgeDir, waitMs) {
  try {
    const response = runRpc(bridgeDir, 'players.list', [], waitMs);
    const count = Number(response.result && response.result.count);
    return {
      unavailable: false,
      count: Number.isFinite(count) ? count : null,
      executor: response.result && response.result.executor,
    };
  } catch (error) {
    return {
      unavailable: true,
      count: null,
      error: String(error && error.message ? error.message : error),
    };
  }
}

function writeStatus(statusPath, status) {
  fs.mkdirSync(path.dirname(statusPath), { recursive: true });
  fs.writeFileSync(statusPath, `${JSON.stringify(status, null, 2)}\n`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForContext(options) {
  const startedAt = Date.now();
  let lastStatus = null;

  for (;;) {
    let contextProbe = null;
    let contextState = {
      available: false,
      source: null,
      context: null,
      cachedPlayerStates: null,
      findFirst: {},
    };
    let contextError = null;

    try {
      contextProbe = runConsole(
        options.bridgeDir,
        'Omegga.Bridge.DescribeServerPastePrefabContext',
        options.waitMs,
      );
      contextState = parseContextLines(contextProbe.lines);
    } catch (error) {
      contextError = String(error && error.message ? error.message : error);
    }

    const players = options.checkPlayers
      ? readPlayers(options.bridgeDir, options.waitMs)
      : {
          skipped: true,
          count: null,
          reason: 'players.list is not required for ServerPastePrefab context readiness',
        };
    const elapsedMs = Date.now() - startedAt;
    lastStatus = {
      status: contextState.available ? 'context-ready' : 'waiting-for-context',
      updated_at: new Date().toISOString(),
      elapsed_ms: elapsedMs,
      timeout_ms: options.timeoutMs,
      bridge_dir: options.bridgeDir,
      players,
      server_paste_context: {
        available: contextState.available,
        source: contextState.source,
        context: contextState.context,
        cached_player_states: contextState.cachedPlayerStates,
        find_first: contextState.findFirst,
        error: contextError,
        executor: contextProbe && contextProbe.response.result && contextProbe.response.result.executor,
      },
    };
    writeStatus(options.statusPath, lastStatus);

    if (contextState.available) {
      return lastStatus;
    }

    if (elapsedMs >= options.timeoutMs) {
      return {
        ...lastStatus,
        status: 'timeout-waiting-for-context',
      };
    }

    await sleep(options.pollMs);
  }
}

async function run(options) {
  const contextStatus = await waitForContext(options);
  if (contextStatus.status !== 'context-ready') {
    writeStatus(options.statusPath, contextStatus);
    return {
      ok: false,
      result: 'timeout-waiting-for-context',
      status_path: options.statusPath,
      context: contextStatus,
    };
  }

  const command = buildCommand(resolveDynamicPlaceSeed(options));
  const paste = runConsole(options.bridgeDir, command, options.waitMs);
  const pasteState = parseKeyValueLines(paste.lines);
  const result = {
    ok: pasteState.ok === 'true',
    result: pasteState.result || null,
    status_path: options.statusPath,
    command,
    context: contextStatus,
    paste: {
      executor: paste.response.result && paste.response.result.executor,
      complete_success: paste.response.complete && paste.response.complete.success,
      state: pasteState,
      lines: paste.lines,
    },
    live_actor_dump: null,
  };

  if (options.postDumpActors) {
    await sleep(options.postDelayMs);
    try {
      result.live_actor_dump = readLiveActorDump(
        options.bridgeDir,
        options.actorClasses,
        Math.max(options.waitMs, 10000),
      );
    } catch (error) {
      result.live_actor_dump = {
        error: String(error && error.message ? error.message : error),
      };
    }
  }

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

  const result = await run(options);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exitCode = result.ok ? 0 : 1;
}

module.exports = {
  parseArgs,
  run,
  waitForContext,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(String(error && error.stack ? error.stack : error));
    process.exit(1);
  });
}
