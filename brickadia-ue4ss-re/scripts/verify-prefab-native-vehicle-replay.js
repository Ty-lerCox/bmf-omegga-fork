#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { CONTINUE_CAPTURE_KINDS } = require('./wait-prefab-native-capture-replay.js');

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
    'usage: node verify-prefab-native-vehicle-replay.js [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>       Bridge directory, default local 7799 test bridge',
    '  --status <path>          Watcher status/output JSON path',
    '                           default <bridge_dir>/prefab-native-watch-status.json',
    '  --strict <0|1>           Exit non-zero unless vehicle replay is coherent, default 0',
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
  return value === '1' || value.toLowerCase() === 'true' || value.toLowerCase() === 'yes';
}

function parseReplayLines(lines) {
  const out = {
    ok: null,
    result: null,
    function: null,
    kind: null,
    replayMode: null,
    originalGrid: null,
    finalGrid: null,
    gridDelta: null,
    rawLines: lines || [],
  };

  for (const line of lines || []) {
    let match = line.match(/^ok=(true|false)$/);
    if (match) {
      out.ok = match[1] === 'true';
      continue;
    }

    match = line.match(/^result=(.*)$/);
    if (match) {
      out.result = match[1];
      continue;
    }

    match = line.match(/^function=(.*)$/);
    if (match) {
      out.function = match[1];
      continue;
    }

    match = line.match(/^kind=(.*)$/);
    if (match) {
      out.kind = match[1];
      continue;
    }

    match = line.match(/^replay_mode=(.*)$/);
    if (match) {
      out.replayMode = match[1];
      continue;
    }

    match = line.match(/^(original_grid|final_grid|grid_delta)=(-?\d+),(-?\d+),(-?\d+)$/);
    if (match) {
      out[match[1].replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())] = {
        x: Number(match[2]),
        y: Number(match[3]),
        z: Number(match[4]),
      };
    }
  }

  return out;
}

function parseHashPasteLines(lines) {
  const out = {
    ok: null,
    result: null,
    function: null,
    kind: null,
    hash: null,
    grid: null,
    dryRun: null,
    rawLines: lines || [],
  };

  for (const line of lines || []) {
    let match = line.match(/^ok=(true|false)$/);
    if (match) {
      out.ok = match[1] === 'true';
      continue;
    }

    match = line.match(/^result=(.*)$/);
    if (match) {
      out.result = match[1];
      continue;
    }

    match = line.match(/^function=(.*)$/);
    if (match) {
      out.function = match[1];
      continue;
    }

    match = line.match(/^kind=(.*)$/);
    if (match) {
      out.kind = match[1];
      continue;
    }

    match = line.match(/^hash=([0-9A-Fa-f]{64})$/);
    if (match) {
      out.hash = match[1].toUpperCase();
      continue;
    }

    match = line.match(/^grid=(-?\d+),(-?\d+),(-?\d+)$/);
    if (match) {
      out.grid = {
        x: Number(match[1]),
        y: Number(match[2]),
        z: Number(match[3]),
      };
      continue;
    }

    match = line.match(/^dry_run=(true|false)$/);
    if (match) {
      out.dryRun = match[1] === 'true';
    }
  }

  return out;
}

function evaluateWatcherPayload(payload) {
  const checks = {
    watcherFinished: false,
    clientCapture: false,
    replayableCapture: false,
    replayCommandSent: false,
    replayRpcSucceeded: false,
    replayNativeOk: false,
    postActorDump: false,
    coherentDynamicActor: false,
    noActorWarnings: false,
    hashPasteCommandSucceeded: false,
    hashPasteNativeOk: false,
  };
  const reasons = [];

  if (!payload || typeof payload !== 'object') {
    return {
      status: 'missing-status',
      ok: false,
      checks,
      reasons: ['watcher status payload is missing or invalid'],
    };
  }

  if (payload.status === 'waiting-for-player' || payload.status === 'waiting-for-capture') {
    if (payload.last_replayable_client_capture) {
      return {
        status: 'prefab-capture-ready',
        ok: false,
        checks,
        reasons: [`watcher retained replayable ${payload.last_replayable_client_capture} but has not replayed it yet`],
        watcher: {
          player_count: payload.player_count,
          player_seen: payload.player_seen,
          observed_capture_events: payload.observed_capture_events,
          last_client_capture: payload.last_client_capture,
          last_replayable_client_capture: payload.last_replayable_client_capture,
        },
      };
    }
    const ignoredHandshake = payload.last_client_capture
      && CONTINUE_CAPTURE_KINDS.has(payload.last_client_capture);
    return {
      status: ignoredHandshake ? 'waiting-for-replayable-capture' : payload.status,
      ok: false,
      checks,
      reasons: [
        ignoredHandshake
          ? `watcher ignored ${payload.last_client_capture} and is waiting for a replayable prefab paste capture`
          : payload.status === 'waiting-for-player'
            ? 'watcher is waiting for a connected player'
            : 'watcher is waiting for a native paste capture',
      ],
      watcher: {
        player_count: payload.player_count,
        player_seen: payload.player_seen,
        observed_capture_events: payload.observed_capture_events,
        last_client_capture: payload.last_client_capture,
        last_replayable_client_capture: payload.last_replayable_client_capture,
      },
    };
  }

  checks.watcherFinished = true;
  checks.clientCapture = Boolean(payload.capture && payload.capture.capturedKind);
  checks.replayableCapture = Boolean(payload.capture && payload.capture.replayable);
  checks.replayCommandSent = payload.status === 'replay-command-sent';
  checks.replayRpcSucceeded = Boolean(payload.replay && payload.replay.success);

  const replayLineState = parseReplayLines(payload.replay ? payload.replay.lines : []);
  checks.replayNativeOk = replayLineState.ok === true;

  const hashPasteLineState = parseHashPasteLines(
    payload.post_hash_paste && payload.post_hash_paste.lines
      ? payload.post_hash_paste.lines
      : [],
  );
  checks.hashPasteCommandSucceeded = Boolean(
    payload.post_hash_paste && payload.post_hash_paste.success === true,
  );
  checks.hashPasteNativeOk = hashPasteLineState.ok === true;

  const actorSummary = payload.post_actor_dump && payload.post_actor_dump.summary
    ? payload.post_actor_dump.summary
    : null;
  checks.postActorDump = Boolean(actorSummary);
  checks.coherentDynamicActor = Boolean(
    actorSummary && Number(actorSummary.coherentDynamicActorCandidates || 0) > 0,
  );
  checks.noActorWarnings = Boolean(
    actorSummary && Array.isArray(actorSummary.warnings) && actorSummary.warnings.length === 0,
  );

  if (!checks.clientCapture) {
    reasons.push('no client native paste capture is present');
  }
  if (!checks.replayableCapture) {
    reasons.push('capture kind is not replayable by the known prefab layouts');
  }
  if (!checks.replayCommandSent) {
    reasons.push(`watcher status is ${payload.status}, not replay-command-sent`);
  }
  if (!checks.replayRpcSucceeded) {
    reasons.push('replay command did not complete successfully at the bridge RPC layer');
  }
  if (!checks.replayNativeOk) {
    reasons.push('native ProcessEvent replay did not report ok=true');
  }
  if (!checks.postActorDump) {
    reasons.push('post-replay actor dump is missing');
  }
  if (checks.postActorDump && !checks.coherentDynamicActor) {
    reasons.push('post-replay actor dump found no coherent BrickGridDynamicActor candidate');
  }
  if (checks.postActorDump && !checks.noActorWarnings) {
    reasons.push('post-replay actor dump reported vehicle coherence warnings');
  }

  const ok = checks.clientCapture
    && checks.replayableCapture
    && checks.replayCommandSent
    && checks.replayRpcSucceeded
    && checks.replayNativeOk
    && checks.postActorDump
    && checks.coherentDynamicActor
    && checks.noActorWarnings;

  return {
    status: ok ? 'vehicle-replay-coherent' : 'vehicle-replay-unverified',
    ok,
    checks,
    reasons,
    capture: payload.capture || null,
    replay: replayLineState,
    hash_paste: payload.post_hash_paste
      ? {
        status: payload.post_hash_paste.status || null,
        mode: payload.post_hash_paste.mode || null,
        success: payload.post_hash_paste.success,
        parsed: hashPasteLineState,
      }
      : null,
    actor_summary: actorSummary,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const bridgeDir = path.resolve(args.dir || DEFAULT_BRIDGE_DIR);
  const statusPath = path.resolve(args.status || path.join(bridgeDir, 'prefab-native-watch-status.json'));
  const strict = boolArg(args.strict, false);

  let payload = null;
  let readError = null;
  try {
    payload = JSON.parse(fs.readFileSync(statusPath, 'utf8'));
  } catch (error) {
    readError = String(error);
  }

  const evaluation = readError
    ? {
      status: 'missing-status',
      ok: false,
      checks: {},
      reasons: [`could not read ${statusPath}: ${readError}`],
    }
    : evaluateWatcherPayload(payload);

  const output = {
    status_path: statusPath,
    bridge_dir: bridgeDir,
    ...evaluation,
  };
  console.log(JSON.stringify(output, null, 2));

  if (strict && !evaluation.ok) {
    process.exit(1);
  }
}

module.exports = {
  parseHashPasteLines,
  parseReplayLines,
  evaluateWatcherPayload,
};

if (require.main === module) {
  main();
}
