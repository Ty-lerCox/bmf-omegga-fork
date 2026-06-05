import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REQUIRED_FILES = [
  'VTableLayout.ini',
  'CustomGameConfigs/Brickadia/UE4SS-settings.ini',
  'CustomGameConfigs/Brickadia/UE4SS_Signatures/CallFunctionByNameWithArguments.lua',
  'CustomGameConfigs/Brickadia/UE4SS_Signatures/FName_ToString.lua',
  'CustomGameConfigs/Brickadia/UE4SS_Signatures/GNatives.lua',
  'CustomGameConfigs/Brickadia/UE4SS_Signatures/GUObjectArray.lua',
  'CustomGameConfigs/Brickadia/UE4SS_Signatures/GUObjectHashTables.lua',
  'validation-report.json',
  'validation-report.md',
];

function argValue(flag, fallback) {
  const index = process.argv.indexOf(flag);
  if (index === -1 || index + 1 >= process.argv.length) return fallback;
  return process.argv[index + 1];
}

function sha256(filepath) {
  return createHash('sha256')
    .update(fs.readFileSync(filepath))
    .digest('hex');
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(argValue('--workspace', path.resolve(scriptDir, '..')));
const bundleId = argValue('--bundle', 'CL12960');
const bundleRoot = path.join(workspaceRoot, 'bundles', bundleId);
const manifestPath = path.join(bundleRoot, 'manifest.json');

const errors = [];
const warnings = [];

if (!fs.existsSync(bundleRoot)) {
  errors.push(`Bundle root is missing: ${bundleRoot}`);
}

let manifest = null;
if (!fs.existsSync(manifestPath)) {
  errors.push(`Manifest is missing: ${manifestPath}`);
} else {
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  } catch (error) {
    errors.push(`Failed to parse manifest: ${error.message}`);
  }
}

if (manifest) {
  for (const field of [
    'brickadia_cl',
    'brickadia_version_string',
    'ue_baseline',
    'ue4ss_commit',
    'validated',
    'validation_timestamp',
    'files',
  ]) {
    if (!(field in manifest)) errors.push(`Manifest is missing field ${field}.`);
  }

  if (String(manifest.brickadia_cl) !== bundleId.replace(/^CL/i, '')) {
    errors.push(
      `Manifest brickadia_cl ${String(manifest.brickadia_cl)} does not match bundle ${bundleId}.`,
    );
  }

  if (manifest.validated !== true) {
    warnings.push(`Bundle ${bundleId} is staged but not validated.`);
  }
}

for (const relativePath of REQUIRED_FILES) {
  const absolutePath = path.join(bundleRoot, ...relativePath.split('/'));
  if (!fs.existsSync(absolutePath)) {
    errors.push(`Missing required file: ${relativePath}`);
    continue;
  }

  const expectedHash = manifest?.files?.[relativePath];
  if (!expectedHash) {
    errors.push(`Manifest hash missing for ${relativePath}`);
    continue;
  }

  const actualHash = sha256(absolutePath);
  if (actualHash !== expectedHash) {
    errors.push(`Hash mismatch for ${relativePath}`);
  }
}

const report = {
  bundle_id: bundleId,
  workspace_root: workspaceRoot,
  bundle_root: bundleRoot,
  ok: errors.length === 0,
  validated: errors.length === 0 && manifest?.validated === true,
  errors,
  warnings,
};

console.log(JSON.stringify(report, null, 2));
if (errors.length > 0) process.exit(1);
