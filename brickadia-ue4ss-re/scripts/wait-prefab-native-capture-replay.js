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
const REPLAYABLE_CAPTURE_KINDS = new Set([
  'ServerPastePrefab',
  'ServerPlaceCurrentPrefab',
  'ServerPlaceSimpleEntityVolume',
]);
const CONTINUE_CAPTURE_KINDS = new Set([
  'ServerUploadPrefab',
  'ClientUploadPrefab',
  'ClientNotifyPrefabCaptureComplete',
  'ClientNotifyPrefabCaptureFailed',
  'CapturePrefab',
  'ApplyPrefabState',
  'CommitPlacement',
  'PreviewPlacement',
  'SetPlaceAsPhysicsAvailable',
  'SetPlaceAsPhysicsEnabled',
]);
const DEFAULT_POST_DUMP_ACTORS = [
  'BrickGridDynamicActor',
  'Entity_DynamicBrickGrid',
  'BP_Entity_Wheel_Deep1_C',
  'BP_Entity_Wheel_Deep2_C',
  'BP_Entity_Wheel_C',
].join(',');
const SEND_RPC = path.join(__dirname, 'send-bridge-rpc.js');
const DECODE_CAPTURE = path.join(__dirname, 'decode-prefab-native-capture.js');

function usage() {
  console.error([
    'usage: node wait-prefab-native-capture-replay.js [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>       UE4SS bridge directory',
    '  --expected-kind <kind>    Client capture kind to wait for, or "any"',
    '                           default: "ServerPastePrefab"',
    '  --stop-on-other-kind <0|1>',
    '                           Stop and report if a different client paste kind arrives',
    '                           default: 1',
    '  --replay-args <text>     Args after ReplayLastPrefabNativeCapture',
    '                           default: "offset 2000 0 500"',
    '  --timeout-ms <ms>        Total wait timeout, default 300000',
    '  --poll-ms <ms>           Poll interval, default 1000',
    '  --wait-ms <ms>           Bridge wait timeout per RPC, default 6000',
    '  --existing-ok <0|1>      Replay an already-present client capture, default 0',
    '  --require-player <0|1>   Wait for at least one connected player before replay, default 0',
    '  --status-path <path|0>    Periodic status JSON path, default <bridge_dir>/prefab-native-watch-status.json',
    '  --status-interval-ms <ms> Status write interval, default 5000',
    '  --dry-run <0|1>          Do not run replay after capture, default 0',
    '  --post-hash-paste <0|1|dry-run>',
    '                           After ServerPastePrefab capture, test PastePrefabHash, default dry-run',
    '  --post-hash-paste-target <0|last|hex>',
    '                           PasteInfo target for post hash paste, default last',
    '  --post-dump-actors <classes|0>',
    '                           Dump actor classes after capture/replay, default 0',
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

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function boolArg(value, defaultValue) {
  if (value == null) {
    return defaultValue;
  }
  return value === '1' || value.toLowerCase() === 'true' || value.toLowerCase() === 'yes';
}

function stringArg(value, defaultValue) {
  if (value == null) {
    return defaultValue;
  }
  return String(value);
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

function postHashPasteModeArg(value, defaultValue) {
  const text = String(value == null ? defaultValue : value).toLowerCase();
  if (text === '0' || text === 'false' || text === 'no' || text === 'off' || text === 'none') {
    return '0';
  }
  if (text === 'dry-run' || text === 'dryrun' || text === 'dry') {
    return 'dry-run';
  }
  if (text === '1' || text === 'true' || text === 'yes' || text === 'on') {
    return '1';
  }
  throw new Error('--post-hash-paste must be 0, 1, or dry-run');
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

function readBridgeStatus(bridgeDir) {
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

function normalizeKind(value) {
  const text = String(value || '').trim();
  return text === '<none>' ? '' : text;
}

function kindMatches(actual, expected) {
  const actualKind = normalizeKind(actual).toLowerCase();
  const expectedKind = normalizeKind(expected).toLowerCase();
  return expectedKind === 'any' || actualKind === expectedKind;
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
    lines: (response.chunks || []).map((chunk) => chunk.line || ''),
  };
}

function decodeLatestCapture(bridgeDir) {
  const replayableLatestPath = path.join(bridgeDir, 'prefab-native-last-replayable.txt');
  const args = fs.existsSync(replayableLatestPath)
    ? [DECODE_CAPTURE, '--capture', replayableLatestPath]
    : [DECODE_CAPTURE, '--dir', bridgeDir];
  try {
    return JSON.parse(execFileSync(
      process.execPath,
      args,
      {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      },
    ));
  } catch (error) {
    return {
      status: 'decode-error',
      error: String(error && error.stderr ? error.stderr : error),
    };
  }
}

function parseFlagSummary(text) {
  const flags = {};
  for (const token of String(text || '').trim().split(/\s+/)) {
    const match = token.match(/^([^=]+)=(true|false)$/);
    if (match) {
      flags[match[1]] = match[2] === 'true';
    }
  }
  return flags;
}

function summarizeActorDump(lines) {
  const summary = {
    classCounts: {},
    actors: [],
    actorCount: 0,
    requestedCounts: {},
    coherentDynamicActorCandidates: 0,
    wheelEntityCandidates: 0,
    unresolvedLocations: 0,
    rootlessActors: 0,
    transientActors: 0,
    loadedActors: 0,
    warnings: [],
  };
  const actorsByIndex = new Map();

  const ensureActor = (index) => {
    if (!actorsByIndex.has(index)) {
      actorsByIndex.set(index, { index });
    }
    return actorsByIndex.get(index);
  };

  for (const line of lines || []) {
    let match = line.match(/^class\s+([^ ]+)\s+count=(\d+)$/);
    if (match) {
      summary.classCounts[match[1]] = Number(match[2]);
      continue;
    }

    match = line.match(
      /^actor\[(\d+)\]\s+requested=([^ ]+)\s+class=(.*?)\s+addr=([^ ]*)\s+name=(.*?)\s+location=(.*?)\s+source=([^ ]*)\s+attempts=(.*)$/,
    );
    if (match) {
      const actor = ensureActor(Number(match[1]));
      actor.requested = match[2];
      actor.class = match[3].trim();
      actor.addr = match[4];
      actor.name = match[5].trim();
      actor.location = match[6].trim();
      actor.locationSource = match[7];
      actor.locationAttempts = match[8];
      continue;
    }

    match = line.match(/^actor\[(\d+)\]\.flags=(.*)$/);
    if (match) {
      ensureActor(Number(match[1])).flags = parseFlagSummary(match[2]);
      continue;
    }

    match = line.match(/^actor\[(\d+)\]\.raw\.([^.]+)\.address=(.*)$/);
    if (match) {
      const actor = ensureActor(Number(match[1]));
      actor.rawAddresses = actor.rawAddresses || {};
      actor.rawAddresses[match[2]] = Number(match[3]);
    }
  }

  summary.actors = Array.from(actorsByIndex.values()).sort((left, right) => left.index - right.index);
  summary.actorCount = summary.actors.length;

  for (const actor of summary.actors) {
    if (actor.requested) {
      summary.requestedCounts[actor.requested] = (summary.requestedCounts[actor.requested] || 0) + 1;
    }

    const flags = actor.flags || {};
    const rootAddress = actor.rawAddresses && actor.rawAddresses.RootComponent;
    const isCdoOrArchetype = flags.cdo === true || flags.archetype === true || flags.is_class === true || flags.is_any_class === true;
    const hasResolvedLocation = actor.location && actor.location !== 'unresolved';
    const hasRootComponent = rootAddress == null || rootAddress !== 0;
    const isUsableInstance = flags.valid === true && !isCdoOrArchetype;

    if (!hasResolvedLocation) {
      summary.unresolvedLocations += 1;
    }
    if (rootAddress === 0) {
      summary.rootlessActors += 1;
    }
    if (flags.transient === true) {
      summary.transientActors += 1;
    }
    if (flags.was_loaded === true) {
      summary.loadedActors += 1;
    }
    if (actor.requested === 'BrickGridDynamicActor' && isUsableInstance && hasResolvedLocation && hasRootComponent) {
      summary.coherentDynamicActorCandidates += 1;
    }
    if (/Wheel/.test(actor.requested || '') && isUsableInstance) {
      summary.wheelEntityCandidates += 1;
    }
  }

  if ((summary.classCounts.BrickGridDynamicActor || 0) > 0 && summary.coherentDynamicActorCandidates === 0) {
    summary.warnings.push('BrickGridDynamicActor objects were found, but none had both a resolved location and non-null root component.');
  }
  if (summary.wheelEntityCandidates > 0 && summary.coherentDynamicActorCandidates === 0) {
    summary.warnings.push('Wheel entities exist without a coherent dynamic grid actor candidate.');
  }

  return summary;
}

function dumpPostReplayActors(bridgeDir, classes, waitMs) {
  if (!classes) {
    return null;
  }
  const command = `Omegga.Bridge.DumpPrefabActors ${classes}`;
  const dump = runConsole(bridgeDir, command, Math.max(waitMs, 6000));
  return {
    command,
    executor: dump.response.result && dump.response.result.executor,
    success: dump.response.complete && dump.response.complete.success,
    lines: dump.lines,
    summary: summarizeActorDump(dump.lines),
  };
}

function parseGridText(value) {
  const match = String(value || '').match(/^(-?\d+),(-?\d+),(-?\d+)$/);
  if (!match) {
    return null;
  }
  return {
    x: Number(match[1]),
    y: Number(match[2]),
    z: Number(match[3]),
  };
}

function parseReplayPlacement(lines) {
  const placement = {
    grid: null,
    orientation: null,
  };

  for (const line of lines || []) {
    let match = line.match(/^(?:final_grid|grid)=(-?\d+),(-?\d+),(-?\d+)$/);
    if (match) {
      placement.grid = {
        x: Number(match[1]),
        y: Number(match[2]),
        z: Number(match[3]),
      };
      continue;
    }

    match = line.match(/^(?:final_orientation|orientation)=(\d+)$/);
    if (match) {
      placement.orientation = Number(match[1]);
    }
  }

  return placement;
}

function buildPostHashPasteCommand(decodedCapture, replay, options) {
  if (options.postHashPaste === '0') {
    return {
      status: 'disabled',
      reason: 'post hash paste disabled',
    };
  }

  const serverPaste = decodedCapture
    && decodedCapture.decoded
    && decodedCapture.decoded.serverPastePrefab;
  if (!serverPaste || !serverPaste.hash_hex) {
    return {
      status: 'skipped',
      reason: 'latest replayable capture is not ServerPastePrefab or has no decoded hash',
    };
  }

  const replayPlacement = parseReplayPlacement(replay ? replay.lines : []);
  const fallbackGrid = serverPaste.pasteInfo && serverPaste.pasteInfo.gridOffset
    ? serverPaste.pasteInfo.gridOffset
    : null;
  const grid = replayPlacement.grid || fallbackGrid;
  if (!grid) {
    return {
      status: 'skipped',
      reason: 'no placement grid available for PastePrefabHash',
      hash: serverPaste.hash_hex,
    };
  }

  const orientation = replayPlacement.orientation != null
    ? replayPlacement.orientation
    : serverPaste.pasteInfo && serverPaste.pasteInfo.placementOrientation != null
      ? serverPaste.pasteInfo.placementOrientation
      : 0;
  const withOwnership = serverPaste.bWithOwnership === false ? '0' : '1';
  const inTemp = serverPaste.bInTemp === true ? '1' : '0';
  const target = options.postHashPasteTarget || 'last';
  const commandParts = [
    'Omegga.Bridge.PastePrefabHash',
    serverPaste.hash_hex,
    'grid',
    String(grid.x),
    String(grid.y),
    String(grid.z),
    String(orientation),
    `ownership=${withOwnership}`,
    `temp=${inTemp}`,
    `target=${target}`,
  ];
  if (options.postHashPaste === 'dry-run') {
    commandParts.push('dry-run');
  }

  return {
    status: 'ready',
    mode: options.postHashPaste,
    hash: serverPaste.hash_hex,
    grid,
    orientation,
    target,
    command: commandParts.join(' '),
  };
}

function readPlayerCount(bridgeDir, waitMs) {
  const response = runRpc(bridgeDir, 'players.list', [], waitMs);
  const count = response.result && response.result.count != null
    ? Number(response.result.count)
    : null;
  return Number.isFinite(count) ? count : null;
}

function maybeReadPlayerCount(options) {
  if (!options.requirePlayer) {
    return null;
  }
  return readPlayerCount(options.bridgeDir, options.waitMs);
}

function parseHookState(lines) {
  const state = {
    registered: false,
    captureEvents: 0,
    lastCapture: null,
    lastCaptureSource: null,
    lastClientCapture: null,
    lastReplayableClientCapture: null,
    lastReplayCapture: null,
    rawLines: lines,
  };

  for (const line of lines) {
    let match = line.match(/^registered=(true|false)$/);
    if (match) {
      state.registered = match[1] === 'true';
      continue;
    }

    match = line.match(/^capture_events=(\d+)/);
    if (match) {
      state.captureEvents = Number(match[1]);
      continue;
    }

    match = line.match(/^last_capture=([^ ]+)(?: source=(.*))?$/);
    if (match) {
      state.lastCapture = match[1] === '<none>' ? null : match[1];
      state.lastCaptureSource = match[2] || null;
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

function evaluateCapture(state, initialCaptureEvents, options) {
  const capturedKind = normalizeKind(state.lastReplayableClientCapture || state.lastClientCapture);
  if (!capturedKind) {
    return { ready: false };
  }

  const isNewEnough = options.existingOk || state.captureEvents > initialCaptureEvents;
  if (!isNewEnough) {
    return { ready: false };
  }

  const matched = kindMatches(capturedKind, options.expectedKind);
  const expectedAny = normalizeKind(options.expectedKind).toLowerCase() === 'any';
  const replayable = REPLAYABLE_CAPTURE_KINDS.has(capturedKind);
  if (expectedAny && !replayable && CONTINUE_CAPTURE_KINDS.has(capturedKind)) {
    return {
      ready: false,
      ignored: true,
      capturedKind,
      replayable: false,
      reason: `captured ${capturedKind}, continuing to wait for a replayable prefab paste`,
    };
  }
  if (!matched && !options.stopOnOtherKind) {
    return { ready: false };
  }

  return {
    ready: true,
    matched,
    capturedKind,
    replayable: matched && replayable,
    reason: matched
      ? 'matched expected client capture kind'
      : `captured ${capturedKind}, expected ${options.expectedKind}`,
  };
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
      expectedKind: stringArg(args['expected-kind'], 'ServerPastePrefab'),
      stopOnOtherKind: boolArg(args['stop-on-other-kind'], true),
      replayArgs: args['replay-args'] || 'offset 2000 0 500',
      timeoutMs: numberArg(args['timeout-ms'], 300000, '--timeout-ms'),
      pollMs: Math.max(50, numberArg(args['poll-ms'], 1000, '--poll-ms')),
      waitMs: Math.max(1000, numberArg(args['wait-ms'], 6000, '--wait-ms')),
      existingOk: boolArg(args['existing-ok'], false),
      requirePlayer: boolArg(args['require-player'], false),
      statusPath: args['status-path'] === '0'
        ? null
        : path.resolve(args['status-path'] || path.join(bridgeDir, 'prefab-native-watch-status.json')),
      statusIntervalMs: Math.max(250, numberArg(args['status-interval-ms'], 5000, '--status-interval-ms')),
      dryRun: boolArg(args['dry-run'], false),
      postHashPaste: postHashPasteModeArg(args['post-hash-paste'], 'dry-run'),
      postHashPasteTarget: stringArg(args['post-hash-paste-target'], 'last'),
      postDumpActors: args['post-dump-actors'] === '0' || args['post-dump-actors'] == null
        ? null
        : stringArg(args['post-dump-actors'], DEFAULT_POST_DUMP_ACTORS),
    };
  } catch (error) {
    console.error(String(error));
    process.exit(2);
  }

  const initial = parseHookState(
    runConsole(options.bridgeDir, 'Omegga.Bridge.DescribePrefabNativeHooks 12', options.waitMs).lines,
  );
  const initialCaptureEvents = options.existingOk ? -1 : initial.captureEvents;
  const deadline = Date.now() + options.timeoutMs;
  const startedAt = new Date().toISOString();
  const watcherSessionId = `${process.pid}-${Date.now().toString(36)}`;
  let observed = initial;
  let observedPlayerCount = maybeReadPlayerCount(options);
  let playerSeen = Number.isFinite(observedPlayerCount) && observedPlayerCount > 0;
  let lastStatusAt = 0;
  let statusSeq = 0;

  const emitStatus = (status, extra = {}, force = false) => {
    const now = Date.now();
    if (!force && now - lastStatusAt < options.statusIntervalMs) {
      return;
    }
    lastStatusAt = now;
    statusSeq += 1;
    const bridgeStatus = readBridgeStatus(options.bridgeDir);
    writeStatus(options.statusPath, {
      status,
      watcher_session_id: watcherSessionId,
      started_at: startedAt,
      status_seq: statusSeq,
      bridge_dir: options.bridgeDir,
      bridge_status_updated_at: bridgeStatus && bridgeStatus.updated_at
        ? bridgeStatus.updated_at
        : null,
      bridge_status_session: bridgeStatus && bridgeStatus.session
        ? bridgeStatus.session
        : null,
      expected_kind: options.expectedKind,
      stop_on_other_kind: options.stopOnOtherKind,
      require_player: options.requirePlayer,
      replay_args: options.replayArgs,
      dry_run: options.dryRun,
      post_hash_paste: options.postHashPaste,
      post_hash_paste_target: options.postHashPasteTarget,
      post_dump_actors: options.postDumpActors,
      timeout_ms: options.timeoutMs,
      poll_ms: options.pollMs,
      wait_ms: options.waitMs,
      player_count: observedPlayerCount,
      player_seen: playerSeen,
      initial_capture_events: initialCaptureEvents,
      observed_capture_events: observed.captureEvents,
      last_client_capture: observed.lastClientCapture,
      last_replayable_client_capture: observed.lastReplayableClientCapture,
      last_replay_capture: observed.lastReplayCapture,
      ...extra,
    });
  };

  const pollHookCapture = () => {
    const hookResult = runConsole(options.bridgeDir, 'Omegga.Bridge.DescribePrefabNativeHooks 12', options.waitMs);
    observed = parseHookState(hookResult.lines);
    return evaluateCapture(observed, initialCaptureEvents, options);
  };

  emitStatus(playerSeen ? 'waiting-for-capture' : 'waiting-for-player', {}, true);

  while (Date.now() <= deadline) {
    observedPlayerCount = maybeReadPlayerCount(options);
    if (Number.isFinite(observedPlayerCount) && observedPlayerCount > 0) {
      playerSeen = true;
    }
    const capture = pollHookCapture();
    if (options.requirePlayer && (!Number.isFinite(observedPlayerCount) || observedPlayerCount <= 0)) {
      if (!capture.ready) {
        emitStatus('waiting-for-player');
        sleep(options.pollMs);
        continue;
      }
      playerSeen = true;
    }

    emitStatus('waiting-for-capture');

    if (capture.ready) {
      const replayCommand = `Omegga.Bridge.ReplayLastPrefabNativeCapture ${options.replayArgs}`.trim();
      const replay = options.dryRun || !capture.replayable
        ? null
        : runConsole(options.bridgeDir, replayCommand, Math.max(options.waitMs, 10000));
      const finalHooks = parseHookState(
        runConsole(options.bridgeDir, 'Omegga.Bridge.DescribePrefabNativeHooks 12', options.waitMs).lines,
      );
      const replayState = runConsole(options.bridgeDir, 'Omegga.Bridge.DescribePrefabNativeReplay', options.waitMs);
      const decodedCapture = decodeLatestCapture(options.bridgeDir);
      const postHashPastePlan = buildPostHashPasteCommand(decodedCapture, replay, options);
      const postHashPasteResult = postHashPastePlan.status === 'ready'
        ? runConsole(options.bridgeDir, postHashPastePlan.command, Math.max(options.waitMs, 10000))
        : null;
      const postActorDump = dumpPostReplayActors(options.bridgeDir, options.postDumpActors, options.waitMs);

      const output = {
        status: options.dryRun
          ? 'capture-ready-dry-run'
          : capture.replayable
            ? 'replay-command-sent'
            : 'capture-ready-non-replayable',
        watcher_session_id: watcherSessionId,
        started_at: startedAt,
        bridge_dir: options.bridgeDir,
        expected_kind: options.expectedKind,
        stop_on_other_kind: options.stopOnOtherKind,
        require_player: options.requirePlayer,
        player_count: observedPlayerCount,
        player_seen: playerSeen,
        capture,
        replay_command: replayCommand,
        initial,
        observed,
        replay: replay
          ? {
            executor: replay.response.result && replay.response.result.executor,
            success: replay.response.complete && replay.response.complete.success,
            lines: replay.lines,
          }
          : null,
        final_hooks: finalHooks,
        replay_state_lines: replayState.lines,
        decoded_capture: decodedCapture,
        post_hash_paste: {
          ...postHashPastePlan,
          executor: postHashPasteResult && postHashPasteResult.response.result
            ? postHashPasteResult.response.result.executor
            : null,
          success: postHashPasteResult && postHashPasteResult.response.complete
            ? postHashPasteResult.response.complete.success
            : null,
          lines: postHashPasteResult ? postHashPasteResult.lines : null,
        },
        post_actor_dump: postActorDump,
      };
      writeStatus(options.statusPath, output);
      console.log(JSON.stringify(output, null, 2));
      return;
    }

    sleep(options.pollMs);
  }

  const output = {
    status: options.requirePlayer && !playerSeen ? 'timeout-no-player' : 'timeout',
    watcher_session_id: watcherSessionId,
    started_at: startedAt,
    bridge_dir: options.bridgeDir,
    timeout_ms: options.timeoutMs,
    require_player: options.requirePlayer,
    player_count: observedPlayerCount,
    player_seen: playerSeen,
    initial,
    observed,
    post_dump_actors: options.postDumpActors,
    post_hash_paste: options.postHashPaste,
    post_hash_paste_target: options.postHashPasteTarget,
    next_action: options.requirePlayer && !playerSeen
      ? 'Join the server first, then paste a prefab through the normal client path.'
      : 'Join the server and paste a prefab through the normal client path.',
  };
  writeStatus(options.statusPath, output);
  console.log(JSON.stringify(output, null, 2));
  process.exit(1);
}

module.exports = {
  DEFAULT_POST_DUMP_ACTORS,
  parseHookState,
  evaluateCapture,
  parseFlagSummary,
  buildPostHashPasteCommand,
  parseReplayPlacement,
  parseGridText,
  summarizeActorDump,
  CONTINUE_CAPTURE_KINDS,
  REPLAYABLE_CAPTURE_KINDS,
};

if (require.main === module) {
  main();
}
