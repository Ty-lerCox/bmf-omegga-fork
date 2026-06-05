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
const DEFAULT_NOTES_DIR = path.join(REPO_ROOT, 'notes');
const SEND_RPC = path.join(__dirname, 'send-bridge-rpc.js');

function usage() {
  console.error([
    'usage: node capture-prefab-native-diagnostics.js [options]',
    '',
    'Options:',
    '  --dir <bridge_dir>       UE4SS bridge directory',
    '  --out-json <path>        JSON output path',
    '  --out-md <path>          Markdown output path',
    '  --wait-ms <ms>           Bridge wait timeout per command',
    '  --check-players <0|1>    Also call players.list, default 0',
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
  const text = String(value).toLowerCase();
  return text === '1' || text === 'true' || text === 'yes' || text === 'on';
}

function runRpc(bridgeDir, method, extraArgs, waitMs) {
  const args = [
    SEND_RPC,
    '--dir',
    bridgeDir,
    '--method',
    method,
    '--wait-ms',
    String(waitMs),
    ...extraArgs,
  ];
  const raw = execFileSync(process.execPath, args, {
    cwd: REPO_ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(raw);
}

function runConsole(bridgeDir, command, waitMs) {
  const response = runRpc(
    bridgeDir,
    'console.exec',
    ['--command-raw', command],
    waitMs,
  );
  return {
    command,
    response,
    lines: (response.chunks || []).map((chunk) => chunk.line),
  };
}

function readIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return fs.readFileSync(filePath, 'utf8');
}

function tailLines(text, count) {
  if (!text) {
    return [];
  }
  return text.split(/\r?\n/).filter(Boolean).slice(-count);
}

function parseFunctionSchema(lines) {
  const schema = {
    hits: [],
    raw_lines: lines,
  };
  let currentHit = null;
  let currentParam = null;
  const hitPattern = /^hit\[(\d+)\] addr=(\S+) full=(.*?) outer=(.*?) flags=(\S+) \[(.*?)\] num_parms=(\d+) parms_size=(\S+) return_offset=(\S+)/;
  const paramPattern = /^\s*param\[(\d+)\]\s+([^:]+):(.+?) offset=(\S+) size=(\S+) flags=(\S+) \[(.*?)\] class_cast=(\S+)/;
  const structPattern = /^\s+struct\s+(.+?)\s+size=(\S+)/;
  const fieldPattern = /^\s+field\[(\d+)\]\s+([^:]+):(.+?) offset=(\S+) size=(\S+) flags=(\S+) \[(.*?)\] class_cast=(\S+)/;

  for (const line of lines) {
    const hit = line.match(hitPattern);
    if (hit) {
      currentHit = {
        index: Number(hit[1]),
        address: hit[2],
        full: hit[3],
        outer: hit[4],
        flags_hex: hit[5],
        flags: hit[6] ? hit[6].split('|') : [],
        num_parms: Number(hit[7]),
        parms_size: hit[8],
        return_offset: hit[9],
        params: [],
      };
      schema.hits.push(currentHit);
      currentParam = null;
      continue;
    }

    const param = line.match(paramPattern);
    if (param && currentHit) {
      currentParam = {
        index: Number(param[1]),
        reflected_name: param[2],
        reflected_type: param[3],
        offset: param[4],
        size: param[5],
        flags_hex: param[6],
        flags: param[7] ? param[7].split('|') : [],
        class_cast: param[8],
        structs: [],
        fields: [],
      };
      currentHit.params.push(currentParam);
      continue;
    }

    const struct = line.match(structPattern);
    if (struct && currentParam) {
      currentParam.structs.push({ label: struct[1], size: struct[2] });
      continue;
    }

    const field = line.match(fieldPattern);
    if (field && currentParam) {
      currentParam.fields.push({
        index: Number(field[1]),
        reflected_name: field[2],
        reflected_type: field[3],
        offset: field[4],
        size: field[5],
        flags_hex: field[6],
        flags: field[7] ? field[7].split('|') : [],
        class_cast: field[8],
      });
    }
  }

  return schema;
}

function serverPasteReplayContract(schema) {
  const hit = schema.hits[0];
  const params = hit ? hit.params : [];
  const matchesExpected =
    hit &&
    hit.num_parms === 4 &&
    hit.parms_size === '0x40' &&
    params[0] &&
    params[0].offset === '0x0' &&
    params[0].size === '0x20' &&
    params[1] &&
    params[1].offset === '0x20' &&
    params[1].size === '0x1' &&
    params[2] &&
    params[2].offset === '0x21' &&
    params[2].size === '0x1' &&
    params[3] &&
    params[3].offset === '0x28' &&
    params[3].size === '0x18';

  return {
    status: matchesExpected ? 'matches-live-reflection' : 'schema-mismatch',
    source: 'Live UE4SS reflection plus static CL12960/CL13530 notes',
    function: 'ServerPastePrefab',
    parms_size: hit ? hit.parms_size : null,
    params: [
      { index: 1, name: 'Hash', type: 'BRPrefabHash', offset: '0x0', size: '0x20' },
      { index: 2, name: 'bWithOwnership', type: 'bool', offset: '0x20', size: '0x1' },
      { index: 3, name: 'bInTemp', type: 'bool', offset: '0x21', size: '0x1' },
      {
        index: 4,
        name: 'PasteInfo',
        type: 'BRPrefabDetachedPasteInfo',
        offset: '0x28',
        size: '0x18',
        fields: [
          { name: 'TargetObject', type: 'UObject*', offset: '0x0', size: '0x8' },
          { name: 'GridOffset', type: 'FIntVector', offset: '0x8', size: '0xC' },
          { name: 'PlacementOrientation', type: 'uint8/enum', offset: '0x14', size: '0x1' },
        ],
      },
    ],
  };
}

function prefabUploadContract(schema, functionName) {
  const hit = schema.hits[0];
  const params = hit ? hit.params : [];
  const expected = functionName === 'ClientUploadPrefab'
    ? [
        { index: 1, name: 'Hash', type: 'BRPrefabHash', offset: '0x0', size: '0x20' },
        { index: 2, name: 'bAllowUpload', type: 'bool', offset: '0x20', size: '0x1' },
      ]
    : [
        { index: 1, name: 'Hash', type: 'BRPrefabHash', offset: '0x0', size: '0x20' },
      ];
  const expectedSize = functionName === 'ClientUploadPrefab' ? '0x21' : '0x20';
  const mismatches = [];

  if (!hit) {
    mismatches.push(`${functionName} reflection produced no hit`);
  } else {
    if (hit.num_parms !== expected.length) {
      mismatches.push(`expected ${expected.length} params, got ${hit.num_parms}`);
    }
    if (!sameHex(hit.parms_size, expectedSize)) {
      mismatches.push(`expected parms_size ${expectedSize}, got ${hit.parms_size}`);
    }
    for (const spec of expected) {
      const reflected = params[spec.index - 1];
      if (!reflected) {
        mismatches.push(`missing param ${spec.index} ${spec.name}`);
        continue;
      }
      if (!sameHex(reflected.offset, spec.offset)) {
        mismatches.push(`${spec.name} expected offset ${spec.offset}, got ${reflected.offset}`);
      }
      if (!sameHex(reflected.size, spec.size)) {
        mismatches.push(`${spec.name} expected size ${spec.size}, got ${reflected.size}`);
      }
    }
  }

  return {
    status: mismatches.length === 0 ? 'matches-live-reflection' : 'schema-mismatch',
    source: 'Live UE4SS reflection',
    function: functionName,
    parms_size: hit ? hit.parms_size : null,
    params: expected,
    mismatches,
  };
}

function sameHex(actual, expected) {
  if (actual == null || expected == null) {
    return false;
  }
  const actualNumber = Number.parseInt(String(actual).replace(/^0x/i, ''), 16);
  const expectedNumber = Number.parseInt(String(expected).replace(/^0x/i, ''), 16);
  return Number.isFinite(actualNumber) && actualNumber === expectedNumber;
}

function serverPlaceReplayContract(schema) {
  const hit = schema.hits[0];
  const params = hit ? hit.params : [];
  const expected = [
    { index: 1, name: 'PlacementState', type: 'placement-state struct', offset: '0x0', size: '0x80' },
    { index: 2, name: 'PrimaryGrid', type: 'FIntVector', offset: '0x80', size: '0xC' },
    { index: 3, name: 'PlacementVector', type: 'placement vector struct', offset: '0x90', size: '0x18' },
    { index: 4, name: 'Orientation', type: 'uint8/enum', offset: '0xA8', size: '0x1' },
    { index: 5, name: 'ExtraGrid5', type: 'FIntVector', offset: '0xAC', size: '0xC' },
    { index: 6, name: 'ExtraGrid6', type: 'FIntVector', offset: '0xB8', size: '0xC' },
    { index: 7, name: 'ExtraGrid7', type: 'FIntVector', offset: '0xC4', size: '0xC' },
    { index: 8, name: 'ExtraGrid8', type: 'FIntVector', offset: '0xD0', size: '0xC' },
    { index: 9, name: 'Bool9', type: 'bool', offset: '0xDC', size: '0x1' },
    { index: 10, name: 'Bool10', type: 'bool', offset: '0xDD', size: '0x1' },
    { index: 11, name: 'Bool11', type: 'bool', offset: '0xDE', size: '0x1' },
  ];
  const mismatches = [];

  if (!hit) {
    mismatches.push('ServerPlaceCurrentPrefab reflection produced no hit');
  } else {
    if (hit.num_parms !== 11) {
      mismatches.push(`expected 11 params, got ${hit.num_parms}`);
    }
    if (!sameHex(hit.parms_size, '0xDF')) {
      mismatches.push(`expected parms_size 0xDF, got ${hit.parms_size}`);
    }
    for (const spec of expected) {
      const reflected = params[spec.index - 1];
      if (!reflected) {
        mismatches.push(`missing param ${spec.index} ${spec.name}`);
        continue;
      }
      if (!sameHex(reflected.offset, spec.offset)) {
        mismatches.push(`${spec.name} expected offset ${spec.offset}, got ${reflected.offset}`);
      }
      if (!sameHex(reflected.size, spec.size)) {
        mismatches.push(`${spec.name} expected size ${spec.size}, got ${reflected.size}`);
      }
    }
  }

  return {
    status: mismatches.length === 0 ? 'matches-live-reflection' : 'schema-mismatch',
    source: 'Live UE4SS reflection plus static CL13530 notes',
    function: 'ServerPlaceCurrentPrefab',
    parms_size: hit ? hit.parms_size : null,
    adjusted_grid_params: ['PrimaryGrid', 'ExtraGrid5', 'ExtraGrid6', 'ExtraGrid7', 'ExtraGrid8'],
    adjusted_vector_params: ['PlacementState.Transform.Translation', 'PlacementVector'],
    params: expected,
    mismatches,
  };
}

function serverPlaceSimpleEntityVolumeContract(schema) {
  const hit = schema.hits[0];
  const params = hit ? hit.params : [];
  const expected = [
    { index: 1, name: 'PlacementState', type: 'placement-state struct', offset: '0x0', size: '0x80' },
    { index: 2, name: 'EntityClass', type: 'UObject*', offset: '0x80', size: '0x8' },
    { index: 3, name: 'OrientationBytes', type: '4-byte orientation/flags struct', offset: '0x88', size: '0x4' },
    { index: 4, name: 'PrimaryGrid', type: 'FIntVector', offset: '0x8C', size: '0xC' },
    { index: 5, name: 'PlacementVector', type: 'placement vector struct', offset: '0x98', size: '0x18' },
    { index: 6, name: 'BoolLikeParam', type: 'bool', offset: '0xB0', size: '0x1' },
    { index: 7, name: 'ExtraGrid7', type: 'FIntVector', offset: '0xB4', size: '0xC' },
    { index: 8, name: 'ExtraGrid8', type: 'FIntVector', offset: '0xC0', size: '0xC' },
    { index: 9, name: 'ExtraGrid9', type: 'FIntVector', offset: '0xCC', size: '0xC' },
    { index: 10, name: 'ExtraGrid10', type: 'FIntVector', offset: '0xD8', size: '0xC' },
  ];
  const mismatches = [];

  if (!hit) {
    mismatches.push('ServerPlaceSimpleEntityVolume reflection produced no hit');
  } else {
    if (hit.num_parms !== 10) {
      mismatches.push(`expected 10 params, got ${hit.num_parms}`);
    }
    if (!sameHex(hit.parms_size, '0xE4')) {
      mismatches.push(`expected parms_size 0xE4, got ${hit.parms_size}`);
    }
    for (const spec of expected) {
      const reflected = params[spec.index - 1];
      if (!reflected) {
        mismatches.push(`missing param ${spec.index} ${spec.name}`);
        continue;
      }
      if (!sameHex(reflected.offset, spec.offset)) {
        mismatches.push(`${spec.name} expected offset ${spec.offset}, got ${reflected.offset}`);
      }
      if (!sameHex(reflected.size, spec.size)) {
        mismatches.push(`${spec.name} expected size ${spec.size}, got ${reflected.size}`);
      }
    }
  }

  return {
    status: mismatches.length === 0 ? 'matches-live-reflection' : 'schema-mismatch',
    source: 'Live UE4SS reflection plus inferred CL13530 replay layout',
    function: 'ServerPlaceSimpleEntityVolume',
    parms_size: hit ? hit.parms_size : null,
    adjusted_grid_params: ['PrimaryGrid', 'ExtraGrid7', 'ExtraGrid8', 'ExtraGrid9', 'ExtraGrid10'],
    adjusted_vector_params: ['PlacementState.Transform.Translation', 'PlacementVector'],
    params: expected,
    mismatches,
  };
}

function singleBoolEventContract(schema, functionName) {
  const hit = schema.hits[0];
  const param = hit && hit.params[0];
  const mismatches = [];

  if (!hit) {
    mismatches.push(`${functionName} reflection produced no hit`);
  } else {
    if (hit.num_parms !== 1) {
      mismatches.push(`expected 1 param, got ${hit.num_parms}`);
    }
    if (!sameHex(hit.parms_size, '0x1')) {
      mismatches.push(`expected parms_size 0x1, got ${hit.parms_size}`);
    }
    if (!param) {
      mismatches.push('missing bool param');
    } else {
      if (!sameHex(param.offset, '0x0')) {
        mismatches.push(`bool expected offset 0x0, got ${param.offset}`);
      }
      if (!sameHex(param.size, '0x1')) {
        mismatches.push(`bool expected size 0x1, got ${param.size}`);
      }
    }
  }

  return {
    status: mismatches.length === 0 ? 'matches-live-reflection' : 'schema-mismatch',
    source: 'Live UE4SS reflection',
    function: functionName,
    parms_size: hit ? hit.parms_size : null,
    params: [{ index: 1, name: 'bEnabled', type: 'bool', offset: '0x0', size: '0x1' }],
    mismatches,
  };
}

function serverModifyEntityContract(schema) {
  const hit = schema.hits[0];
  const params = hit ? hit.params : [];
  const expected = [
    { index: 1, name: 'Entity', type: 'UObject*', offset: '0x0', size: '0x8' },
    { index: 2, name: 'ModifyPayload', type: 'struct containing array', offset: '0x8', size: '0x10' },
  ];
  const mismatches = [];

  if (!hit) {
    mismatches.push('ServerModifyEntity reflection produced no hit');
  } else {
    if (hit.num_parms !== 2) {
      mismatches.push(`expected 2 params, got ${hit.num_parms}`);
    }
    if (!sameHex(hit.parms_size, '0x18')) {
      mismatches.push(`expected parms_size 0x18, got ${hit.parms_size}`);
    }
    for (const spec of expected) {
      const reflected = params[spec.index - 1];
      if (!reflected) {
        mismatches.push(`missing param ${spec.index} ${spec.name}`);
        continue;
      }
      if (!sameHex(reflected.offset, spec.offset)) {
        mismatches.push(`${spec.name} expected offset ${spec.offset}, got ${reflected.offset}`);
      }
      if (!sameHex(reflected.size, spec.size)) {
        mismatches.push(`${spec.name} expected size ${spec.size}, got ${reflected.size}`);
      }
    }
  }

  return {
    status: mismatches.length === 0 ? 'matches-live-reflection' : 'schema-mismatch',
    source: 'Live UE4SS reflection',
    function: 'ServerModifyEntity',
    parms_size: hit ? hit.parms_size : null,
    params: expected,
    mismatches,
  };
}

function decodeCaptureNdjson(text) {
  if (!text) {
    return [];
  }
  return text
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      try {
        const parsed = JSON.parse(line);
        if (parsed.detail_b64) {
          parsed.detail = Buffer.from(parsed.detail_b64, 'base64').toString('utf8');
        }
        return parsed;
      } catch (error) {
        return { parse_error: String(error), raw: line };
      }
    });
}

function renderMarkdown(report) {
  const lines = [];
  lines.push('# CL13530 Prefab Native Diagnostics');
  lines.push('');
  lines.push(`Generated: \`${report.generated_at}\``);
  lines.push(`Bridge: \`${report.bridge_dir}\``);
  lines.push(`Players: \`${report.players.count}\``);
  lines.push('');
  lines.push('## Hook State');
  lines.push('');
  for (const line of report.hooks.lines.filter((value) => /registered_kind|capture_events|last_capture/.test(value))) {
    lines.push(`- ${line}`);
  }
  lines.push('');
  lines.push('## ServerPastePrefab Replay Contract');
  lines.push('');
  lines.push(`Status: \`${report.server_paste_replay_contract.status}\``);
  lines.push(`Parameter buffer size: \`${report.server_paste_replay_contract.parms_size || 'unknown'}\``);
  lines.push('');
  lines.push('| Index | Name | Type | Offset | Size |');
  lines.push('| --- | --- | --- | --- | --- |');
  for (const param of report.server_paste_replay_contract.params) {
    lines.push(`| ${param.index} | ${param.name} | ${param.type} | \`${param.offset}\` | \`${param.size}\` |`);
    if (param.fields) {
      for (const field of param.fields) {
        lines.push(`|  | ${param.name}.${field.name} | ${field.type} | \`${field.offset}\` | \`${field.size}\` |`);
      }
    }
  }
  lines.push('');
  lines.push('## Live Reflection: ServerPastePrefab');
  lines.push('');
  lines.push('```text');
  lines.push(...report.server_paste_schema.raw_lines);
  lines.push('```');
  lines.push('');
  lines.push('## Prefab Upload RPC Contracts');
  lines.push('');
  lines.push(`ServerUploadPrefab: \`${report.server_upload_contract.status}\`, parameter buffer size \`${report.server_upload_contract.parms_size || 'unknown'}\`.`);
  lines.push(`ClientUploadPrefab: \`${report.client_upload_contract.status}\`, parameter buffer size \`${report.client_upload_contract.parms_size || 'unknown'}\`.`);
  lines.push('');
  lines.push('| Function | Index | Name | Type | Offset | Size |');
  lines.push('| --- | --- | --- | --- | --- | --- |');
  for (const contract of [report.server_upload_contract, report.client_upload_contract]) {
    for (const param of contract.params) {
      lines.push(`| ${contract.function} | ${param.index} | ${param.name} | ${param.type} | \`${param.offset}\` | \`${param.size}\` |`);
    }
  }
  lines.push('');
  lines.push('These RPCs are hash/cache driven. `ServerUploadPrefab` does not expose a raw archive-byte payload parameter.');
  lines.push('');
  lines.push('### Live Reflection: ServerUploadPrefab');
  lines.push('');
  lines.push('```text');
  lines.push(...report.server_upload_schema.raw_lines);
  lines.push('```');
  lines.push('');
  lines.push('### Live Reflection: ClientUploadPrefab');
  lines.push('');
  lines.push('```text');
  lines.push(...report.client_upload_schema.raw_lines);
  lines.push('```');
  lines.push('');
  lines.push('## Live Reflection: ServerPlaceCurrentPrefab');
  lines.push('');
  lines.push('```text');
  lines.push(...report.server_place_schema.raw_lines);
  lines.push('```');
  lines.push('');
  lines.push('## ServerPlaceCurrentPrefab Replay Contract');
  lines.push('');
  lines.push(`Status: \`${report.server_place_replay_contract.status}\``);
  lines.push(`Parameter buffer size: \`${report.server_place_replay_contract.parms_size || 'unknown'}\``);
  if (report.server_place_replay_contract.mismatches.length > 0) {
    lines.push('');
    lines.push('Mismatches:');
    for (const mismatch of report.server_place_replay_contract.mismatches) {
      lines.push(`- ${mismatch}`);
    }
  }
  lines.push('');
  lines.push('| Index | Name | Type | Offset | Size | Replay offset behavior |');
  lines.push('| --- | --- | --- | --- | --- | --- |');
  for (const param of report.server_place_replay_contract.params) {
    const adjusted = report.server_place_replay_contract.adjusted_grid_params.includes(param.name)
      ? 'adjusted by replay delta'
      : '';
    lines.push(`| ${param.index} | ${param.name} | ${param.type} | \`${param.offset}\` | \`${param.size}\` | ${adjusted} |`);
  }
  lines.push('');
  lines.push('Additional replay-adjusted vector fields:');
  for (const param of report.server_place_replay_contract.adjusted_vector_params) {
    lines.push(`- ${param}`);
  }
  lines.push('');
  lines.push('## Live Reflection: ServerPlaceSimpleEntityVolume');
  lines.push('');
  lines.push('```text');
  lines.push(...report.server_place_simple_entity_volume_schema.raw_lines);
  lines.push('```');
  lines.push('');
  lines.push('## ServerPlaceSimpleEntityVolume Replay Contract');
  lines.push('');
  lines.push(`Status: \`${report.server_place_simple_entity_volume_contract.status}\``);
  lines.push(`Parameter buffer size: \`${report.server_place_simple_entity_volume_contract.parms_size || 'unknown'}\``);
  if (report.server_place_simple_entity_volume_contract.mismatches.length > 0) {
    lines.push('');
    lines.push('Mismatches:');
    for (const mismatch of report.server_place_simple_entity_volume_contract.mismatches) {
      lines.push(`- ${mismatch}`);
    }
  }
  lines.push('');
  lines.push('| Index | Name | Type | Offset | Size | Replay offset behavior |');
  lines.push('| --- | --- | --- | --- | --- | --- |');
  for (const param of report.server_place_simple_entity_volume_contract.params) {
    const adjusted = report.server_place_simple_entity_volume_contract.adjusted_grid_params.includes(param.name)
      ? 'adjusted by replay delta'
      : '';
    lines.push(`| ${param.index} | ${param.name} | ${param.type} | \`${param.offset}\` | \`${param.size}\` | ${adjusted} |`);
  }
  lines.push('');
  lines.push('Additional replay-adjusted vector fields:');
  for (const param of report.server_place_simple_entity_volume_contract.adjusted_vector_params) {
    lines.push(`- ${param}`);
  }
  lines.push('');
  lines.push('## Physics Side-Channel Function Reflection');
  lines.push('');
  lines.push(`SetPlaceAsPhysicsAvailable: \`${report.set_place_as_physics_available_contract.status}\`, parameter buffer size \`${report.set_place_as_physics_available_contract.parms_size || 'unknown'}\`.`);
  lines.push(`SetPlaceAsPhysicsEnabled: \`${report.set_place_as_physics_enabled_contract.status}\`, parameter buffer size \`${report.set_place_as_physics_enabled_contract.parms_size || 'unknown'}\`.`);
  lines.push(`ServerModifyEntity: \`${report.server_modify_entity_contract.status}\`, parameter buffer size \`${report.server_modify_entity_contract.parms_size || 'unknown'}\`.`);
  lines.push('');
  lines.push('These are captured for diagnosis. `SetPlaceAsPhysics*` are not replayable prefab placements.');
  lines.push('');
  lines.push('## Last Native Capture');
  lines.push('');
  lines.push('```text');
  lines.push(...report.last_capture.lines);
  lines.push('```');
  lines.push('');
  lines.push('## Capture Files');
  lines.push('');
  lines.push(`- Latest detail: \`${report.capture_files.latest_path}\` (${report.capture_files.latest_exists ? 'present' : 'missing'})`);
  lines.push(`- Capture log: \`${report.capture_files.ndjson_path}\` (${report.capture_files.ndjson_count} records)`);
  return `${lines.join('\n')}\n`;
}

const args = parseArgs(process.argv.slice(2));
const bridgeDir = path.resolve(args.dir || DEFAULT_BRIDGE_DIR);
const waitMs = Number(args['wait-ms'] || 8000);
const checkPlayers = boolArg(args['check-players'], false);
const outJson = path.resolve(args['out-json'] || path.join(DEFAULT_NOTES_DIR, 'cl13530-prefab-native-diagnostics-latest.json'));
const outMd = path.resolve(args['out-md'] || path.join(DEFAULT_NOTES_DIR, 'cl13530-prefab-native-diagnostics-latest.md'));

fs.mkdirSync(path.dirname(outJson), { recursive: true });
fs.mkdirSync(path.dirname(outMd), { recursive: true });

const hooks = runConsole(bridgeDir, 'Omegga.Bridge.DescribePrefabNativeHooks 24', waitMs);
const serverPaste = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject ServerPastePrefab 3 12', waitMs);
const serverPlace = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject ServerPlaceCurrentPrefab 3 12', waitMs);
const serverPlaceSimpleEntityVolume = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject ServerPlaceSimpleEntityVolume 3 20', waitMs);
const serverUpload = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject ServerUploadPrefab 3 12', waitMs);
const clientUpload = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject ClientUploadPrefab 3 12', waitMs);
const setPlaceAsPhysicsAvailable = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject SetPlaceAsPhysicsAvailable 3 12', waitMs);
const setPlaceAsPhysicsEnabled = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject SetPlaceAsPhysicsEnabled 3 12', waitMs);
const serverModifyEntity = runConsole(bridgeDir, 'Omegga.Bridge.DescribeFunctionObject ServerModifyEntity 3 12', waitMs);
const lastCapture = runConsole(bridgeDir, 'Omegga.Bridge.DescribeLastPrefabNativeCapture', waitMs);
const players = checkPlayers
  ? runRpc(bridgeDir, 'players.list', [], waitMs)
  : { skipped: true, result: null };

const latestPath = path.join(bridgeDir, 'prefab-native-last.txt');
const ndjsonPath = path.join(bridgeDir, 'prefab-native-captures.ndjson');
const latestText = readIfExists(latestPath);
const ndjsonText = readIfExists(ndjsonPath);
const captureRecords = decodeCaptureNdjson(ndjsonText);

const serverPasteSchema = parseFunctionSchema(serverPaste.lines);
const serverPlaceSchema = parseFunctionSchema(serverPlace.lines);
const serverPlaceSimpleEntityVolumeSchema = parseFunctionSchema(serverPlaceSimpleEntityVolume.lines);
const serverUploadSchema = parseFunctionSchema(serverUpload.lines);
const clientUploadSchema = parseFunctionSchema(clientUpload.lines);
const setPlaceAsPhysicsAvailableSchema = parseFunctionSchema(setPlaceAsPhysicsAvailable.lines);
const setPlaceAsPhysicsEnabledSchema = parseFunctionSchema(setPlaceAsPhysicsEnabled.lines);
const serverModifyEntitySchema = parseFunctionSchema(serverModifyEntity.lines);
const report = {
  generated_at: new Date().toISOString(),
  bridge_dir: bridgeDir,
  players: {
    count: players.result ? players.result.count : null,
    response: players,
  },
  hooks,
  server_paste_schema: serverPasteSchema,
  server_place_schema: serverPlaceSchema,
  server_place_simple_entity_volume_schema: serverPlaceSimpleEntityVolumeSchema,
  server_upload_schema: serverUploadSchema,
  client_upload_schema: clientUploadSchema,
  set_place_as_physics_available_schema: setPlaceAsPhysicsAvailableSchema,
  set_place_as_physics_enabled_schema: setPlaceAsPhysicsEnabledSchema,
  server_modify_entity_schema: serverModifyEntitySchema,
  server_paste_replay_contract: serverPasteReplayContract(serverPasteSchema),
  server_place_replay_contract: serverPlaceReplayContract(serverPlaceSchema),
  server_place_simple_entity_volume_contract: serverPlaceSimpleEntityVolumeContract(serverPlaceSimpleEntityVolumeSchema),
  server_upload_contract: prefabUploadContract(serverUploadSchema, 'ServerUploadPrefab'),
  client_upload_contract: prefabUploadContract(clientUploadSchema, 'ClientUploadPrefab'),
  set_place_as_physics_available_contract: singleBoolEventContract(setPlaceAsPhysicsAvailableSchema, 'SetPlaceAsPhysicsAvailable'),
  set_place_as_physics_enabled_contract: singleBoolEventContract(setPlaceAsPhysicsEnabledSchema, 'SetPlaceAsPhysicsEnabled'),
  server_modify_entity_contract: serverModifyEntityContract(serverModifyEntitySchema),
  last_capture: lastCapture,
  capture_files: {
    latest_path: latestPath,
    latest_exists: latestText != null,
    latest_tail: tailLines(latestText, 80),
    ndjson_path: ndjsonPath,
    ndjson_exists: ndjsonText != null,
    ndjson_count: captureRecords.length,
    latest_record: captureRecords[captureRecords.length - 1] || null,
  },
};

fs.writeFileSync(outJson, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
fs.writeFileSync(outMd, renderMarkdown(report), 'utf8');

console.log(JSON.stringify({
  out_json: outJson,
  out_md: outMd,
  players: report.players.count,
  server_paste_contract: report.server_paste_replay_contract.status,
  server_place_contract: report.server_place_replay_contract.status,
  server_place_simple_entity_volume_contract: report.server_place_simple_entity_volume_contract.status,
  server_upload_contract: report.server_upload_contract.status,
  client_upload_contract: report.client_upload_contract.status,
  set_place_as_physics_available_contract: report.set_place_as_physics_available_contract.status,
  set_place_as_physics_enabled_contract: report.set_place_as_physics_enabled_contract.status,
  server_modify_entity_contract: report.server_modify_entity_contract.status,
  server_place_mismatches: report.server_place_replay_contract.mismatches,
  server_place_simple_entity_volume_mismatches: report.server_place_simple_entity_volume_contract.mismatches,
  captures: report.capture_files.ndjson_count,
}, null, 2));
