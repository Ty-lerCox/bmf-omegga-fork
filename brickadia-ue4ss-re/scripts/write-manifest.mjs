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

if (!fs.existsSync(manifestPath)) {
  console.error(`Manifest not found: ${manifestPath}`);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
manifest.files = manifest.files && typeof manifest.files === 'object' ? manifest.files : {};

for (const relativePath of REQUIRED_FILES) {
  const absolutePath = path.join(bundleRoot, ...relativePath.split('/'));
  if (!fs.existsSync(absolutePath)) {
    console.error(`Missing required bundle file: ${relativePath}`);
    process.exit(1);
  }
  manifest.files[relativePath] = sha256(absolutePath);
}

fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
console.log(`Updated manifest hashes for ${bundleId}: ${manifestPath}`);
