#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

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
  return buf.readBigUInt64LE(off);
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
  const imageBase = Number(readU64(buf, optional + 24));
  const sectionTable = optional + sizeOfOptionalHeader;
  const sections = [];
  for (let i = 0; i < numberOfSections; i++) {
    const off = sectionTable + i * 40;
    const rawName = buf.subarray(off, off + 8);
    const nul = rawName.indexOf(0);
    const name = rawName.subarray(0, nul >= 0 ? nul : rawName.length).toString('ascii');
    const virtualSize = readU32(buf, off + 8);
    const virtualAddress = readU32(buf, off + 12);
    const sizeOfRawData = readU32(buf, off + 16);
    const pointerToRawData = readU32(buf, off + 20);
    sections.push({ name, virtualSize, virtualAddress, sizeOfRawData, pointerToRawData });
  }
  return { imageBase, sections };
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

function findAll(buf, needle, limit = Infinity) {
  const out = [];
  let at = 0;
  while (out.length < limit) {
    const found = buf.indexOf(needle, at);
    if (found < 0) break;
    out.push(found);
    at = found + 1;
  }
  return out;
}

function utf16le(s) {
  return Buffer.from(s, 'utf16le');
}

function qwordBytes(n) {
  const b = Buffer.alloc(8);
  b.writeBigUInt64LE(BigInt(n));
  return b;
}

function hex(n, width = 0) {
  if (n === null || n === undefined) return null;
  const s = (typeof n === 'bigint' ? n : BigInt(n)).toString(16).toUpperCase();
  return `0x${width ? s.padStart(width, '0') : s}`;
}

function sectionForOffset(pe, off) {
  for (const section of pe.sections) {
    if (off >= section.pointerToRawData && off < section.pointerToRawData + section.sizeOfRawData) {
      return section.name;
    }
  }
  return null;
}

function readQwordWindow(buf, pe, centerOff, qwordsBefore = 4, qwordsAfter = 8) {
  const start = Math.max(0, centerOff - qwordsBefore * 8);
  const aligned = start - (start % 8);
  const end = Math.min(buf.length - 8, centerOff + qwordsAfter * 8);
  const rows = [];
  for (let off = aligned; off <= end; off += 8) {
    if (off < 0 || off + 8 > buf.length) continue;
    const value = Number(readU64(buf, off));
    const valueOff = vaToFileOffset(pe, value);
    rows.push({
      file_offset: hex(off),
      va: hex(fileOffsetToVa(pe, off)),
      value: hex(value),
      value_section: valueOff === null ? null : sectionForOffset(pe, valueOff),
      value_file_offset: valueOff === null ? null : hex(valueOff),
      marker: off === centerOff ? 'ref' : ''
    });
  }
  return rows;
}

function scanRipRefs(buf, pe, targets) {
  const text = pe.sections.find((s) => s.name === '.text');
  if (!text) return [];
  const targetSet = new Map(targets.map((target) => [target.va, target]));
  const out = [];
  const start = text.pointerToRawData;
  const end = start + text.sizeOfRawData;
  for (let off = start; off + 7 <= end; off++) {
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
    if (!len) continue;
    const instVa = fileOffsetToVa(pe, off);
    const disp = readI32(buf, off + 3);
    const targetVa = instVa + len + disp;
    const target = targetSet.get(targetVa);
    if (target) {
      out.push({
        instruction_va: hex(instVa),
        file_offset: hex(off),
        op,
        target_name: target.name,
        target_encoding: target.encoding,
        target_va: hex(targetVa)
      });
    }
  }
  return out;
}

function usage() {
  console.error('usage: scan-pe-prefab-anchors.js <BrickadiaServer-Win64-Shipping.exe> [out.json]');
  process.exit(2);
}

const exePath = process.argv[2];
const outPath = process.argv[3];
if (!exePath) usage();

const buf = fs.readFileSync(exePath);
const pe = parsePe(buf);

const names = [
  'BrickAction_PlacePrefab',
  'ServerPastePrefab',
  'ServerPlaceCurrentPrefab',
  'ServerPlaceSimpleEntityVolume',
  'BRPrefabDetachedPasteInfo',
  'BRLoadWorldAdditiveParams',
  'RequestLoadWorldAdditive',
  'BRPrefabCacheInMemoryPrefab',
  'CachedPrefabBundle',
  'World successfully loaded additively',
  'Loading world additively from bundle',
  'GlobalGridTarget',
  'PreviewPart'
];

const stringHits = [];
for (const name of names) {
  for (const [encoding, needle] of [
    ['ascii', Buffer.from(name, 'ascii')],
    ['utf16le', utf16le(name)]
  ]) {
    const hits = findAll(buf, needle, 64);
    for (const off of hits) {
      const va = fileOffsetToVa(pe, off);
      stringHits.push({
        name,
        encoding,
        file_offset: hex(off),
        va: hex(va),
        section: sectionForOffset(pe, off)
      });
    }
  }
}

const refTargets = stringHits
  .filter((hit) => hit.va)
  .map((hit) => ({ ...hit, va: Number(BigInt(hit.va)) }));

const qwordRefs = [];
for (const target of refTargets) {
  const refs = findAll(buf, qwordBytes(target.va), 256);
  for (const refOff of refs) {
    qwordRefs.push({
      target_name: target.name,
      target_encoding: target.encoding,
      target_va: hex(target.va),
      ref_file_offset: hex(refOff),
      ref_va: hex(fileOffsetToVa(pe, refOff)),
      ref_section: sectionForOffset(pe, refOff),
      qword_window: readQwordWindow(buf, pe, refOff)
    });
  }
}

const ripRefs = scanRipRefs(buf, pe, refTargets);

const result = {
  exe: path.resolve(exePath),
  image_base: hex(pe.imageBase),
  sections: pe.sections,
  string_hits: stringHits,
  qword_refs: qwordRefs,
  rip_refs: ripRefs
};

const json = JSON.stringify(result, null, 2);
if (outPath) {
  fs.writeFileSync(outPath, json + '\n');
}
console.log(json);
