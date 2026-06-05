#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const Module = require("node:module");

const BRDB_JS_PATH = "C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/dist/util/brdb.js";

function usage() {
  console.error(
    [
      "Usage:",
      "  node inspect-brdb-schema.js <schema-file>",
      "  node inspect-brdb-schema.js <schema-file> <mps-file> <type-name>",
    ].join("\n")
  );
}

function loadBrdbInternals() {
  const source = fs.readFileSync(BRDB_JS_PATH, "utf8");
  const localRequire = Module.createRequire(BRDB_JS_PATH);
  const appended = `${source}
module.exports.__private = {
  readBrdbSchema,
  readBrdbType,
  guidToUuid,
  mpMarker,
  mpString,
  mpInt
};
`;
  const dirname = path.dirname(BRDB_JS_PATH);
  const module = { exports: {} };
  const sandbox = {
    require: localRequire,
    module,
    exports: module.exports,
    __filename: BRDB_JS_PATH,
    __dirname: dirname,
    console,
    Buffer,
    process,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
  };
  vm.runInNewContext(appended, sandbox, { filename: BRDB_JS_PATH });
  return module.exports.__private;
}

function readArrayLen(mpMarker, buffer, offset) {
  const marker = mpMarker(buffer[offset]);
  if (!marker) {
    throw new Error(`Invalid msgpack format byte: ${buffer[offset].toString(16)}`);
  }
  const [kind, value] = marker;
  if (kind === "fixarray") {
    return { length: value, offset: offset + 1 };
  }
  if (kind === "array16") {
    return { length: buffer.readUInt16BE(offset + 1), offset: offset + 3 };
  }
  if (kind === "array32") {
    return { length: buffer.readUInt32BE(offset + 1), offset: offset + 5 };
  }
  throw new Error(`Expected array length, got ${kind}`);
}

function readString(mpString, buffer, offset) {
  const result = mpString(buffer, offset);
  return { value: result.str, offset: result.offset };
}

function readBool(mpMarker, buffer, offset) {
  const marker = mpMarker(buffer[offset]);
  if (!marker) {
    throw new Error(`Invalid msgpack format byte: ${buffer[offset].toString(16)}`);
  }
  const [kind] = marker;
  if (kind === "false") {
    return { value: false, offset: offset + 1 };
  }
  if (kind === "true") {
    return { value: true, offset: offset + 1 };
  }
  throw new Error(`Expected bool, got ${kind}`);
}

function readFloat(mpMarker, buffer, offset, kind) {
  const marker = mpMarker(buffer[offset]);
  if (!marker || marker[0] !== kind) {
    throw new Error(`Expected ${kind}, got ${marker ? marker[0] : "invalid"}`);
  }
  if (kind === "float32") {
    return { value: buffer.readFloatBE(offset + 1), offset: offset + 5 };
  }
  return { value: buffer.readDoubleBE(offset + 1), offset: offset + 9 };
}

function readGuid(buffer, offset) {
  const marker = buffer[offset];
  if (marker !== 0xc4 || buffer[offset + 1] !== 0x10) {
    throw new Error(`Expected bin8 length 16 for BRGuid, got ${marker.toString(16)}`);
  }
  const base = offset + 2;
  return {
    value: {
      A: buffer.readUInt32LE(base),
      B: buffer.readUInt32LE(base + 4),
      C: buffer.readUInt32LE(base + 8),
      D: buffer.readUInt32LE(base + 12),
    },
    offset: base + 16,
  };
}

function readBinary(mpMarker, buffer, offset) {
  const marker = mpMarker(buffer[offset]);
  if (!marker) {
    throw new Error(`Invalid msgpack format byte: ${buffer[offset].toString(16)}`);
  }
  const [kind] = marker;
  let length;
  let cursor = offset + 1;
  if (kind === "bin8") {
    length = buffer.readUInt8(cursor);
    cursor += 1;
  } else if (kind === "bin16") {
    length = buffer.readUInt16BE(cursor);
    cursor += 2;
  } else if (kind === "bin32") {
    length = buffer.readUInt32BE(cursor);
    cursor += 4;
  } else {
    throw new Error(`Expected binary payload, got ${kind}`);
  }
  return {
    value: buffer.subarray(cursor, cursor + length),
    offset: cursor + length,
  };
}

function numericTypeSize(typeName) {
  switch (typeName) {
    case "u8":
    case "i8":
    case "bool":
      return 1;
    case "u16":
    case "i16":
      return 2;
    case "u32":
    case "i32":
    case "f32":
      return 4;
    case "u64":
    case "i64":
    case "f64":
      return 8;
    default:
      return null;
  }
}

function readPackedNumeric(buffer, offset, typeName) {
  switch (typeName) {
    case "u8":
      return { value: buffer.readUInt8(offset), offset: offset + 1 };
    case "i8":
      return { value: buffer.readInt8(offset), offset: offset + 1 };
    case "bool":
      return { value: buffer.readUInt8(offset) !== 0, offset: offset + 1 };
    case "u16":
      return { value: buffer.readUInt16LE(offset), offset: offset + 2 };
    case "i16":
      return { value: buffer.readInt16LE(offset), offset: offset + 2 };
    case "u32":
      return { value: buffer.readUInt32LE(offset), offset: offset + 4 };
    case "i32":
      return { value: buffer.readInt32LE(offset), offset: offset + 4 };
    case "f32":
      return { value: buffer.readFloatLE(offset), offset: offset + 4 };
    case "u64":
      return { value: Number(buffer.readBigUInt64LE(offset)), offset: offset + 8 };
    case "i64":
      return { value: Number(buffer.readBigInt64LE(offset)), offset: offset + 8 };
    case "f64":
      return { value: buffer.readDoubleLE(offset), offset: offset + 8 };
    default:
      throw new Error(`Unsupported packed numeric type: ${typeName}`);
  }
}

function tryDecodePackedStruct(mpMarker, buffer, offset, struct) {
  const props = Object.entries(struct.props);
  const expectedSize = packedStructSize(struct);
  if (expectedSize == null) {
    return null;
  }

  const packed = readBinary(mpMarker, buffer, offset);
  if (packed.value.length !== expectedSize) {
    return null;
  }

  const value = {};
  let cursor = 0;
  for (const [propName, prop] of props) {
    const decoded = readPackedNumeric(packed.value, cursor, prop.ty);
    value[propName] = decoded.value;
    cursor = decoded.offset;
  }
  return { value, offset: packed.offset };
}

function packedStructSize(struct) {
  const props = Object.entries(struct.props);
  if (
    props.length === 0 ||
    props.some(([, prop]) => prop.kind !== "literal" || numericTypeSize(prop.ty) == null)
  ) {
    return null;
  }
  return props.reduce((sum, [, prop]) => sum + numericTypeSize(prop.ty), 0);
}

function decodePackedStructArray(buffer, struct, count) {
  const props = Object.entries(struct.props);
  const itemSize = packedStructSize(struct);
  const items = [];
  let cursor = 0;
  for (let i = 0; i < count; i++) {
    const value = {};
    for (const [propName, prop] of props) {
      const decoded = readPackedNumeric(buffer, cursor, prop.ty);
      value[propName] = decoded.value;
      cursor = decoded.offset;
    }
    items.push(value);
  }
  return { items, itemSize };
}

function decodeBySchema(brdb, buffer, offset, schema, typeName) {
  const { mpMarker, mpString, mpInt } = brdb;

  switch (typeName) {
    case "bool":
      return readBool(mpMarker, buffer, offset);
    case "str":
      return readString(mpString, buffer, offset);
    case "f32":
      return readFloat(mpMarker, buffer, offset, "float32");
    case "f64":
      return readFloat(mpMarker, buffer, offset, "float64");
    case "u8":
    case "u16":
    case "u32":
    case "u64":
    case "i8":
    case "i16":
    case "i32":
    case "i64": {
      const result = mpInt(buffer, offset);
      return { value: result.num, offset: result.offset };
    }
    default:
      break;
  }

  if (typeName === "BRGuid") {
    return readGuid(buffer, offset);
  }

  if (typeName === "BRSavedBitFlags") {
    const binary = readBinary(mpMarker, buffer, offset);
    return {
      value: {
        Flags: Array.from(binary.value),
      },
      offset: binary.offset,
    };
  }

  const struct = schema.structs[typeName];
  if (!struct) {
    throw new Error(`Unknown schema type: ${typeName}`);
  }

  try {
    const packed = tryDecodePackedStruct(mpMarker, buffer, offset, struct);
    if (packed) {
      return packed;
    }
  } catch (error) {
  }

  const value = {};
  let cursor = offset;
  let fallbackFlatArrayCount = null;
  for (const [propName, prop] of Object.entries(struct.props)) {
    if (prop.kind === "literal") {
      const decoded = decodeBySchema(brdb, buffer, cursor, schema, prop.ty);
      value[propName] = decoded.value;
      cursor = decoded.offset;
      continue;
    }
    if (prop.kind === "array") {
      const header = readArrayLen(mpMarker, buffer, cursor);
      cursor = header.offset;
      const items = [];
      for (let i = 0; i < header.length; i++) {
        const decoded = decodeBySchema(brdb, buffer, cursor, schema, prop.ty);
        items.push(decoded.value);
        cursor = decoded.offset;
      }
      value[propName] = items;
      fallbackFlatArrayCount = items.length;
      continue;
    }
    if (prop.kind === "flatarray") {
      if (fallbackFlatArrayCount == null) {
        throw new Error(`Cannot infer flatarray length for ${propName}`);
      }
      if (prop.ty === "u8") {
        try {
          const binary = readBinary(mpMarker, buffer, cursor);
          value[propName] = Array.from(binary.value);
          cursor = binary.offset;
          continue;
        } catch (error) {
        }
      }
      const flatStruct = schema.structs[prop.ty];
      if (flatStruct) {
        const itemSize = packedStructSize(flatStruct);
        if (itemSize != null) {
          try {
            const binary = readBinary(mpMarker, buffer, cursor);
            if (binary.value.length === itemSize * fallbackFlatArrayCount) {
              const decoded = decodePackedStructArray(
                binary.value,
                flatStruct,
                fallbackFlatArrayCount
              );
              value[propName] = decoded.items;
              cursor = binary.offset;
              continue;
            }
          } catch (error) {
          }
        }
      }
      const items = [];
      for (let i = 0; i < fallbackFlatArrayCount; i++) {
        const decoded = decodeBySchema(brdb, buffer, cursor, schema, prop.ty);
        items.push(decoded.value);
        cursor = decoded.offset;
      }
      value[propName] = items;
      continue;
    }
    throw new Error(`Unsupported property kind: ${prop.kind}`);
  }

  return { value, offset: cursor };
}

function main(argv) {
  if (argv.length < 1) {
    usage();
    process.exitCode = 1;
    return;
  }

  const schemaPath = argv[0];
  const dataPath = argv[1];
  const typeName = argv[2];

  const brdb = loadBrdbInternals();
  const { readBrdbSchema, readBrdbType } = brdb;
  const schemaBuf = fs.readFileSync(schemaPath);
  const schema = readBrdbSchema(schemaBuf);

  const summary = {
    schemaPath,
    enumNames: Object.keys(schema.enums || {}),
    structNames: Object.keys(schema.structs || {}),
  };

  if (!dataPath || !typeName) {
    console.log(JSON.stringify(summary, null, 2));
    return;
  }

  const dataBuf = fs.readFileSync(dataPath);
  let decoded;
  let decodeMode = "readBrdbType";
  try {
    decoded = readBrdbType(dataBuf, 0, schema, typeName);
  } catch (error) {
    decodeMode = "relaxedSchemaDecoder";
    decoded = decodeBySchema(brdb, dataBuf, 0, schema, typeName);
    decoded.error = error.message;
  }
  console.log(
    JSON.stringify(
      {
        ...summary,
        dataPath,
        typeName,
        decodeMode,
        decoded,
      },
      null,
      2
    )
  );
}

if (require.main === module) {
  main(process.argv.slice(2));
}
