#!/usr/bin/env node

const assert = require('assert');
const { execFileSync } = require('child_process');
const path = require('path');

const decodeScript = path.join(__dirname, 'decode-prefab-native-capture.js');

function decode(text) {
  return JSON.parse(execFileSync(
    process.execPath,
    [decodeScript, '--capture', '-'],
    {
      input: text,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    },
  ));
}

function hex(buffer) {
  return Array.from(buffer)
    .map((byte) => byte.toString(16).toUpperCase().padStart(2, '0'))
    .join(' ');
}

const entityCapture = [
  'Prefab native capture: ServerPasteEntity',
  'source=client',
  'hook=/Script/Brickadia.BRPlayerController:ServerPasteEntity',
  'timestamp=2026-05-31T19:00:00Z',
  'context=BP_PlayerController_C /Game/Test',
  'arg_count=1',
  'arg[1].lua_type=userdata resolver=param_get',
  'arg[1].value=Entity_DynamicBrickGrid /Game/Test.Vehicle',
  'arg[1].raw.address=4096',
  'arg[1].raw.size=8',
  'arg[1].raw.bytes=78 56 34 12 00 00 00 00',
  'arg[1].class=Entity_DynamicBrickGrid',
  '',
].join('\n');

const decodedEntity = decode(entityCapture);
assert.strictEqual(decodedEntity.status, 'decoded');
assert.strictEqual(decodedEntity.capture.kind, 'ServerPasteEntity');
assert.strictEqual(decodedEntity.decoded.objectReferenceCapture.function, 'ServerPasteEntity');
assert.strictEqual(decodedEntity.decoded.objectReferenceCapture.objectRefs.length, 1);
assert.strictEqual(decodedEntity.decoded.objectReferenceCapture.objectRefs[0].pointer, '0x12345678');
assert.strictEqual(decodedEntity.decoded.objectReferenceCapture.objectRefs[0].class, 'Entity_DynamicBrickGrid');

const attachedCapture = [
  'Prefab native capture: HandleAttachedPlacement',
  'source=client',
  'hook=/Script/Brickadia.BRTool_Placer:HandleAttachedPlacement',
  'timestamp=2026-05-31T19:00:00Z',
  'context=BRTool_Placer /Game/Test',
  'arg_count=2',
  'arg[1].lua_type=userdata resolver=param_get',
  'arg[1].value=Entity_DynamicBrickGrid /Game/Test.Root',
  'arg[1].raw.address=8192',
  'arg[1].raw.size=8',
  'arg[1].raw.bytes=01 00 00 00 00 00 00 00',
  'arg[1].class=Entity_DynamicBrickGrid',
  'arg[2].lua_type=userdata resolver=param_get',
  'arg[2].value=BrickGridDynamicActor /Game/Test.Child',
  'arg[2].raw.address=8200',
  'arg[2].raw.size=8',
  'arg[2].raw.bytes=02 00 00 00 00 00 00 00',
  'arg[2].class=BrickGridDynamicActor',
  '',
].join('\n');

const decodedAttached = decode(attachedCapture);
assert.strictEqual(decodedAttached.status, 'decoded');
assert.strictEqual(decodedAttached.decoded.objectReferenceCapture.function, 'HandleAttachedPlacement');
assert.deepStrictEqual(
  decodedAttached.decoded.objectReferenceCapture.contract.objectRefs.map((ref) => ref.offset),
  ['0x0', '0x8'],
);
assert.strictEqual(decodedAttached.decoded.objectReferenceCapture.objectRefs[1].class, 'BrickGridDynamicActor');

const serverPasteCaptureWithSkippedProperties = [
  'Prefab native capture: ServerPastePrefab',
  'source=client',
  'hook=/Script/Brickadia.BRPlayerController:ServerPastePrefab',
  'timestamp=2026-05-31T20:00:00Z',
  'context=BP_PlayerController_C /Game/Test',
  'arg_count=4',
  'arg[1].lua_type=userdata resolver=direct',
  'arg[1].value=',
  'arg[1].raw.address=12288',
  'arg[1].raw.size=32',
  'arg[1].raw.bytes=00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F',
  'arg[1].properties=skipped-unsafe-property-read',
  'arg[2].lua_type=boolean resolver=direct',
  'arg[2].value=true',
  'arg[2].raw.bytes=01',
  'arg[3].lua_type=boolean resolver=direct',
  'arg[3].value=false',
  'arg[3].raw.bytes=00',
  'arg[4].lua_type=userdata resolver=direct',
  'arg[4].value=',
  'arg[4].raw.address=12320',
  'arg[4].raw.size=24',
  'arg[4].raw.bytes=22 22 22 22 11 11 11 11 B8 0B 00 00 00 00 00 00 BC 02 00 00 04 00 00 00',
  'arg[4].properties=skipped-unsafe-property-read',
  '',
].join('\n');

const decodedPaste = decode(serverPasteCaptureWithSkippedProperties);
assert.strictEqual(decodedPaste.status, 'decoded');
assert.strictEqual(decodedPaste.decoded.serverPastePrefab.function, 'ServerPastePrefab');
assert.strictEqual(
  decodedPaste.decoded.serverPastePrefab.hash_hex,
  '000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F',
);
assert.strictEqual(decodedPaste.decoded.serverPastePrefab.bWithOwnership, true);
assert.strictEqual(decodedPaste.decoded.serverPastePrefab.bInTemp, false);
assert.deepStrictEqual(decodedPaste.decoded.serverPastePrefab.pasteInfo.gridOffset, { x: 3000, y: 0, z: 700 });
assert.strictEqual(decodedPaste.decoded.serverPastePrefab.pasteInfo.placementOrientation, 4);
assert.strictEqual(decodedPaste.decoded.serverPastePrefab.pasteInfo.target_pointer, '0x1111111122222222');

const simplePlacementState = Buffer.alloc(0x80);
simplePlacementState.writeDoubleLE(1.5, 0x30);
simplePlacementState.writeDoubleLE(2.5, 0x38);
simplePlacementState.writeDoubleLE(3.5, 0x40);
const simpleEntityClass = Buffer.alloc(0x08);
simpleEntityClass.writeBigUInt64LE(0x0102030405060708n, 0);
const simpleOrientationBytes = Buffer.from([4, 0, 0, 0]);
const simplePrimaryGrid = Buffer.alloc(0x0C);
simplePrimaryGrid.writeInt32LE(3000, 0);
simplePrimaryGrid.writeInt32LE(0, 4);
simplePrimaryGrid.writeInt32LE(700, 8);
const simplePlacementVector = Buffer.alloc(0x18);
simplePlacementVector.writeDoubleLE(10, 0);
simplePlacementVector.writeDoubleLE(20, 8);
simplePlacementVector.writeDoubleLE(30, 16);
const simpleExtraGrid = Buffer.alloc(0x0C);
simpleExtraGrid.writeInt32LE(1, 0);
simpleExtraGrid.writeInt32LE(2, 4);
simpleExtraGrid.writeInt32LE(3, 8);

const simpleEntityVolumeCapture = [
  'Prefab native capture: ServerPlaceSimpleEntityVolume',
  'source=client',
  'hook=/Script/Brickadia.BRTool_Placer:ServerPlaceSimpleEntityVolume',
  'timestamp=2026-05-31T20:30:00Z',
  'context=BRTool_Placer /Game/Test',
  'arg_count=10',
  'arg[1].lua_type=userdata resolver=direct',
  'arg[1].raw.address=16384',
  'arg[1].raw.size=128',
  `arg[1].raw.bytes=${hex(simplePlacementState)}`,
  'arg[2].lua_type=userdata resolver=direct',
  'arg[2].raw.address=16512',
  'arg[2].raw.size=8',
  `arg[2].raw.bytes=${hex(simpleEntityClass)}`,
  'arg[3].lua_type=userdata resolver=direct',
  'arg[3].raw.address=16520',
  'arg[3].raw.size=4',
  `arg[3].raw.bytes=${hex(simpleOrientationBytes)}`,
  'arg[4].lua_type=userdata resolver=direct',
  'arg[4].raw.address=16524',
  'arg[4].raw.size=12',
  `arg[4].raw.bytes=${hex(simplePrimaryGrid)}`,
  'arg[5].lua_type=userdata resolver=direct',
  'arg[5].raw.address=16536',
  'arg[5].raw.size=24',
  `arg[5].raw.bytes=${hex(simplePlacementVector)}`,
  'arg[6].lua_type=boolean resolver=direct',
  'arg[6].value=true',
  'arg[6].raw.address=16560',
  'arg[6].raw.size=1',
  'arg[6].raw.bytes=01',
  ...[7, 8, 9, 10].flatMap((index) => [
    `arg[${index}].lua_type=userdata resolver=direct`,
    `arg[${index}].raw.address=${16564 + ((index - 7) * 12)}`,
    `arg[${index}].raw.size=12`,
    `arg[${index}].raw.bytes=${hex(simpleExtraGrid)}`,
  ]),
  '',
].join('\n');

const decodedSimpleEntityVolume = decode(simpleEntityVolumeCapture);
assert.strictEqual(decodedSimpleEntityVolume.status, 'decoded');
assert.strictEqual(
  decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.function,
  'ServerPlaceSimpleEntityVolume',
);
assert.strictEqual(decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.entityClass_pointer, '0x102030405060708');
assert.deepStrictEqual(decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.primaryGrid, { x: 3000, y: 0, z: 700 });
assert.strictEqual(decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.orientation, 4);
assert.strictEqual(decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.boolLikeParam, true);
assert.deepStrictEqual(decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.placementVector, { x: 10, y: 20, z: 30 });
assert.deepStrictEqual(
  decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.placementStateTranslation,
  { x: 1.5, y: 2.5, z: 3.5 },
);
assert.strictEqual(decodedSimpleEntityVolume.decoded.serverPlaceSimpleEntityVolume.extraGridLikeParams.length, 4);

console.log('PASS test-prefab-native-capture-decode');
