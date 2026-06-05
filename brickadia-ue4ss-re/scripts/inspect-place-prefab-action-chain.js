#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_ANCHORS = path.join(REPO_ROOT, 'notes', 'cl13530-pe-prefab-anchors-latest.json');

const CL13530_PLACE_PREFAB_CHAIN = {
  build: 'CL13530',
  imageBase: 0x140000000,
  methodBlock: 0x146C79D50,
  methodSlots: [
    0x140024180,
    0x14420FE90,
    0x140001000,
    0x1443DC230,
    0x140013CB0,
    0x0,
    0x140045B60,
    0x144211FF0,
    0x144214800,
    0x144214850,
  ],
  expectedDescriptorRefs: [
    0x144214641,
    0x144214674,
    0x1448958A4,
    0x144895CDB,
    0x1448A6869,
  ],
  thinSubmitter: {
    functionStart: 0x1448A5880,
    functionEnd: 0x1448A69F8,
    descriptorWrite: 0x1448A6869,
    submitCall: 0x1448A68BE,
    submitTarget: 0x1443DF4F0,
  },
  submitChain: [
    {
      label: 'queue/context setup to submit stage',
      callsite: 0x1448A68BE,
      target: 0x1443DF4F0,
    },
    {
      label: 'submit stage to owner/context bridge',
      callsite: 0x1443DF734,
      target: 0x1443DF7E0,
    },
    {
      label: 'owner/context bridge to dispatcher',
      callsite: 0x1443DF8F8,
      target: 0x1443E05D0,
    },
    {
      label: 'state submit wrapper to generic record submit',
      callsite: 0x1443E0B4E,
      target: 0x144210120,
    },
  ],
};

function readU16(buf, off) {
  return buf.readUInt16LE(off);
}

function readU32(buf, off) {
  return buf.readUInt32LE(off);
}

function readI32(buf, off) {
  return buf.readInt32LE(off);
}

function readU64(buf, off) {
  return Number(buf.readBigUInt64LE(off));
}

function hex(value, width = 0) {
  if (value === null || value === undefined) {
    return null;
  }
  const text = BigInt(value).toString(16).toUpperCase();
  return `0x${width ? text.padStart(width, '0') : text}`;
}

function parsePe(buf) {
  if (buf.toString('ascii', 0, 2) !== 'MZ') {
    throw new Error('not a PE/MZ file');
  }
  const peOff = readU32(buf, 0x3c);
  if (buf.toString('ascii', peOff, peOff + 4) !== 'PE\u0000\u0000') {
    throw new Error('missing PE signature');
  }

  const fileHeader = peOff + 4;
  const numberOfSections = readU16(buf, fileHeader + 2);
  const sizeOfOptionalHeader = readU16(buf, fileHeader + 16);
  const optional = fileHeader + 20;
  const magic = readU16(buf, optional);
  if (magic !== 0x20b) {
    throw new Error(`unsupported optional header magic 0x${magic.toString(16)}`);
  }

  const imageBase = readU64(buf, optional + 24);
  const sectionTable = optional + sizeOfOptionalHeader;
  const sections = [];
  for (let i = 0; i < numberOfSections; i += 1) {
    const off = sectionTable + i * 40;
    const rawName = buf.subarray(off, off + 8);
    const nul = rawName.indexOf(0);
    const name = rawName.subarray(0, nul >= 0 ? nul : rawName.length).toString('ascii');
    sections.push({
      name,
      virtualSize: readU32(buf, off + 8),
      virtualAddress: readU32(buf, off + 12),
      sizeOfRawData: readU32(buf, off + 16),
      pointerToRawData: readU32(buf, off + 20),
    });
  }

  return { imageBase, sections };
}

function vaToFileOffset(pe, va) {
  const rva = va - pe.imageBase;
  for (const section of pe.sections) {
    const start = section.virtualAddress;
    const end = start + Math.max(section.virtualSize, section.sizeOfRawData);
    if (rva >= start && rva < end) {
      return section.pointerToRawData + (rva - start);
    }
  }
  return null;
}

function fileOffsetToVa(pe, off) {
  for (const section of pe.sections) {
    const start = section.pointerToRawData;
    const end = start + section.sizeOfRawData;
    if (off >= start && off < end) {
      return pe.imageBase + section.virtualAddress + (off - start);
    }
  }
  return null;
}

function findSection(pe, name) {
  return pe.sections.find((section) => section.name === name) || null;
}

function readQwordAtVa(buf, pe, va) {
  const off = vaToFileOffset(pe, va);
  if (off === null || off + 8 > buf.length) {
    return null;
  }
  return readU64(buf, off);
}

function findRipRefs(buf, pe, targetVa) {
  const text = findSection(pe, '.text');
  if (!text) {
    return [];
  }

  const out = [];
  const start = text.pointerToRawData;
  const end = start + text.sizeOfRawData;
  for (let off = start; off + 7 <= end; off += 1) {
    const b0 = buf[off];
    const b1 = buf[off + 1];
    const b2 = buf[off + 2];
    let len = 0;
    let op = null;
    if ((b0 === 0x48 || b0 === 0x4c) && (b1 === 0x8d || b1 === 0x8b) && ((b2 & 0xc7) === 0x05)) {
      len = 7;
      op = b1 === 0x8d ? 'lea' : 'mov';
    } else if ((b0 === 0x48 || b0 === 0x4c) && b1 === 0x89 && ((b2 & 0xc7) === 0x05)) {
      len = 7;
      op = 'store';
    }
    if (!len) {
      continue;
    }
    const instructionVa = fileOffsetToVa(pe, off);
    const disp = readI32(buf, off + 3);
    const resolved = instructionVa + len + disp;
    if (resolved === targetVa) {
      out.push({
        instruction_va: instructionVa,
        instruction_va_hex: hex(instructionVa),
        op,
        bytes: buf.subarray(off, off + len).toString('hex').toUpperCase(),
      });
    }
  }
  return out;
}

function directCallTargetAt(buf, pe, callsiteVa) {
  const off = vaToFileOffset(pe, callsiteVa);
  if (off === null || off + 5 > buf.length) {
    return null;
  }
  if (buf[off] !== 0xe8) {
    return null;
  }
  return callsiteVa + 5 + readI32(buf, off + 1);
}

function findDirectCalls(buf, pe, targetVa) {
  const text = findSection(pe, '.text');
  if (!text) {
    return [];
  }
  const out = [];
  const start = text.pointerToRawData;
  const end = start + text.sizeOfRawData;
  for (let off = start; off + 5 <= end; off += 1) {
    if (buf[off] !== 0xe8) {
      continue;
    }
    const instructionVa = fileOffsetToVa(pe, off);
    const target = instructionVa + 5 + readI32(buf, off + 1);
    if (target === targetVa) {
      out.push(instructionVa);
    }
  }
  return out;
}

function parsePdataFunctions(buf, pe) {
  const pdata = findSection(pe, '.pdata');
  if (!pdata) {
    return [];
  }
  const out = [];
  const start = pdata.pointerToRawData;
  const end = start + pdata.sizeOfRawData;
  for (let off = start; off + 12 <= end; off += 12) {
    const beginRva = readU32(buf, off);
    const endRva = readU32(buf, off + 4);
    const unwindRva = readU32(buf, off + 8);
    if (!beginRva || !endRva || endRva <= beginRva) {
      continue;
    }
    out.push({
      begin: pe.imageBase + beginRva,
      end: pe.imageBase + endRva,
      unwind: pe.imageBase + unwindRva,
    });
  }
  return out;
}

function functionForVa(functions, va) {
  return functions.find((entry) => entry.begin <= va && va < entry.end) || null;
}

function readDefaultExeFromAnchors(anchorsPath = DEFAULT_ANCHORS) {
  const text = fs.readFileSync(anchorsPath, 'utf8');
  const parsed = JSON.parse(text);
  if (!parsed.exe) {
    throw new Error(`anchor file does not contain exe: ${anchorsPath}`);
  }
  return parsed.exe;
}

function addAssertion(assertions, name, ok, detail = '') {
  assertions.push({ name, ok: ok === true, detail });
}

function inspectPlacePrefabActionChain(exePath, options = {}) {
  const expected = options.expected || CL13530_PLACE_PREFAB_CHAIN;
  const buf = fs.readFileSync(exePath);
  const pe = parsePe(buf);
  const functions = parsePdataFunctions(buf, pe);
  const assertions = [];

  addAssertion(
    assertions,
    'image base matches CL13530',
    pe.imageBase === expected.imageBase,
    `${hex(pe.imageBase)} expected ${hex(expected.imageBase)}`,
  );

  const methodSlots = expected.methodSlots.map((expectedValue, index) => {
    const va = expected.methodBlock + index * 8;
    const actual = readQwordAtVa(buf, pe, va);
    const ok = actual === expectedValue;
    addAssertion(
      assertions,
      `BrickAction_PlacePrefab method slot +${hex(index * 8)}`,
      ok,
      `${hex(actual)} expected ${hex(expectedValue)}`,
    );
    return {
      offset: hex(index * 8),
      va: hex(va),
      actual: hex(actual),
      expected: hex(expectedValue),
      ok,
    };
  });

  const descriptorRefs = findRipRefs(buf, pe, expected.methodBlock);
  const descriptorRefSet = new Set(descriptorRefs.map((ref) => ref.instruction_va));
  for (const refVa of expected.expectedDescriptorRefs) {
    addAssertion(
      assertions,
      `descriptor ref ${hex(refVa)} exists`,
      descriptorRefSet.has(refVa),
      `refs=${descriptorRefs.map((ref) => ref.instruction_va_hex).join(',')}`,
    );
  }

  const submitChain = expected.submitChain.map((edge) => {
    const actualTarget = directCallTargetAt(buf, pe, edge.callsite);
    const ok = actualTarget === edge.target;
    addAssertion(
      assertions,
      `call ${edge.label}`,
      ok,
      `${hex(edge.callsite)} -> ${hex(actualTarget)} expected ${hex(edge.target)}`,
    );
    return {
      label: edge.label,
      callsite: hex(edge.callsite),
      actual_target: hex(actualTarget),
      expected_target: hex(edge.target),
      ok,
    };
  });

  const submitterFunction = functionForVa(functions, expected.thinSubmitter.descriptorWrite);
  addAssertion(
    assertions,
    'thin submitter pdata start',
    submitterFunction && submitterFunction.begin === expected.thinSubmitter.functionStart,
    submitterFunction
      ? `${hex(submitterFunction.begin)}-${hex(submitterFunction.end)} expected ${hex(expected.thinSubmitter.functionStart)}-${hex(expected.thinSubmitter.functionEnd)}`
      : 'no pdata function found',
  );
  addAssertion(
    assertions,
    'thin submitter pdata end',
    submitterFunction && submitterFunction.end === expected.thinSubmitter.functionEnd,
    submitterFunction
      ? `${hex(submitterFunction.begin)}-${hex(submitterFunction.end)} expected ${hex(expected.thinSubmitter.functionStart)}-${hex(expected.thinSubmitter.functionEnd)}`
      : 'no pdata function found',
  );

  const directSubmitCallers = findDirectCalls(buf, pe, expected.thinSubmitter.submitTarget);
  addAssertion(
    assertions,
    'thin submitter calls shared submit target',
    directSubmitCallers.includes(expected.thinSubmitter.submitCall),
    `callers=${directSubmitCallers.map((value) => hex(value)).join(',')}`,
  );

  const ok = assertions.every((assertion) => assertion.ok);
  return {
    ok,
    build: expected.build,
    exe: path.resolve(exePath),
    image_base: hex(pe.imageBase),
    method_block: {
      va: hex(expected.methodBlock),
      slots: methodSlots,
    },
    descriptor_refs: descriptorRefs,
    thin_submitter: {
      function_start: hex(expected.thinSubmitter.functionStart),
      function_end: hex(expected.thinSubmitter.functionEnd),
      pdata_function: submitterFunction
        ? {
            begin: hex(submitterFunction.begin),
            end: hex(submitterFunction.end),
            unwind: hex(submitterFunction.unwind),
          }
        : null,
      descriptor_write: hex(expected.thinSubmitter.descriptorWrite),
      submit_call: hex(expected.thinSubmitter.submitCall),
      submit_target: hex(expected.thinSubmitter.submitTarget),
      direct_submit_callers: directSubmitCallers.map((value) => hex(value)),
    },
    submit_chain: submitChain,
    assertions,
  };
}

function usage() {
  console.error([
    'usage: inspect-place-prefab-action-chain.js [options]',
    '',
    'Options:',
    '  --exe <path>       BrickadiaServer-Win64-Shipping.exe path',
    '  --anchors <path>   Anchor JSON containing an exe path',
    '  --out-json <path>  Write full JSON report',
    '  --summary          Print compact text summary',
  ].join('\n'));
  process.exit(2);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--summary') {
      args.summary = true;
      continue;
    }
    if (!arg.startsWith('--')) {
      usage();
    }
    const key = arg.slice(2);
    const value = argv[i + 1];
    if (value == null || value.startsWith('--')) {
      usage();
    }
    args[key] = value;
    i += 1;
  }
  return args;
}

function renderSummary(report) {
  const failed = report.assertions.filter((assertion) => !assertion.ok);
  const lines = [
    `PlacePrefab action chain ${report.build}`,
    `ok=${report.ok}`,
    `exe=${report.exe}`,
    `method_block=${report.method_block.va}`,
    `descriptor_refs=${report.descriptor_refs.map((ref) => ref.instruction_va_hex).join(',')}`,
    `thin_submitter=${report.thin_submitter.function_start}-${report.thin_submitter.function_end}`,
    `submit_call=${report.thin_submitter.submit_call}->${report.thin_submitter.submit_target}`,
  ];
  if (failed.length > 0) {
    lines.push('failed_assertions=');
    for (const assertion of failed) {
      lines.push(`- ${assertion.name}: ${assertion.detail}`);
    }
  }
  return `${lines.join('\n')}\n`;
}

function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const anchorsPath = path.resolve(args.anchors || DEFAULT_ANCHORS);
  const exePath = path.resolve(args.exe || readDefaultExeFromAnchors(anchorsPath));
  const report = inspectPlacePrefabActionChain(exePath);
  if (args['out-json']) {
    fs.mkdirSync(path.dirname(path.resolve(args['out-json'])), { recursive: true });
    fs.writeFileSync(path.resolve(args['out-json']), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  }
  if (args.summary) {
    process.stdout.write(renderSummary(report));
  } else {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  }
  process.exitCode = report.ok ? 0 : 1;
  return report;
}

if (require.main === module) {
  main();
}

module.exports = {
  CL13530_PLACE_PREFAB_CHAIN,
  directCallTargetAt,
  findDirectCalls,
  findRipRefs,
  inspectPlacePrefabActionChain,
  parsePe,
  readDefaultExeFromAnchors,
  renderSummary,
};
