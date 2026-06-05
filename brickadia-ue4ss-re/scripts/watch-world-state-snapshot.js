const fs = require('node:fs');
const path = require('node:path');

const brs = require(
  path.resolve(
    __dirname,
    '..',
    '..',
    'omegga-master',
    'omegga-master',
    'node_modules',
    'brs-js'
  )
);

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next && !next.startsWith('--')) {
      args[key] = next;
      index += 1;
    } else {
      args[key] = '1';
    }
  }
  return args;
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function appendTrace(filePath, message) {
  ensureParent(filePath);
  const line = `${new Date().toISOString()} [WorldStateLiveSampler] ${message}\n`;
  fs.appendFileSync(filePath, line);
  process.stdout.write(line);
}

function writeJsonAtomic(filePath, value) {
  ensureParent(filePath);
  const tempPath = `${filePath}.tmp`;
  fs.writeFileSync(tempPath, JSON.stringify(value, null, 2));
  fs.renameSync(tempPath, filePath);
}

function parseVector(raw, fallback) {
  if (!raw) return fallback;
  const values = String(raw)
    .split(/[,\s]+/)
    .map(token => token.trim())
    .filter(Boolean)
    .map(Number);
  if (values.length !== 3 || values.some(value => Number.isNaN(value))) {
    return fallback;
  }
  return values;
}

function vectorObject(values) {
  const [x = 0, y = 0, z = 0] = Array.isArray(values) ? values : [];
  return { x, y, z };
}

function colorObject(value, colors) {
  if (Array.isArray(value)) {
    const [r = 255, g = 255, b = 255, a = 255] = value;
    return { r, g, b, a };
  }

  if (typeof value === 'number' && Array.isArray(colors) && Array.isArray(colors[value])) {
    const [r = 255, g = 255, b = 255, a = 255] = colors[value];
    return { r, g, b, a };
  }

  return null;
}

function collisionObject(value) {
  if (typeof value === 'boolean') {
    return {
      player: value,
      weapon: value,
      interact: value,
      tool: value,
      physics: value,
    };
  }

  if (value && typeof value === 'object') {
    return {
      player: value.player ?? true,
      weapon: value.weapon ?? true,
      interact: value.interaction ?? value.interact ?? true,
      tool: value.tool ?? true,
      physics: value.physics ?? true,
    };
  }

  return {
    player: true,
    weapon: true,
    interact: true,
    tool: true,
    physics: true,
  };
}

function directionName(value) {
  return (
    ['XPositive', 'XNegative', 'YPositive', 'YNegative', 'ZPositive', 'ZNegative'][value] ??
    `Unknown(${value ?? 'nil'})`
  );
}

function rotationName(value) {
  return ['Deg0', 'Deg90', 'Deg180', 'Deg270'][value] ?? `Unknown(${value ?? 'nil'})`;
}

function assetKind(assetName) {
  return String(assetName || '').startsWith('PB_') ? 'procedural' : 'static';
}

function normalizeOwner(owner, ownerIndex) {
  if (!owner || typeof owner !== 'object') {
    return null;
  }

  return {
    owner_index: typeof ownerIndex === 'number' ? ownerIndex : null,
    user_id: owner.id ?? null,
    user_name: owner.name ?? null,
    display_name: owner.display_name ?? owner.displayName ?? owner.name ?? null,
    brick_count: owner.bricks ?? null,
  };
}

function toHistogramEntries(map, keyName) {
  return Array.from(map.entries())
    .map(([key, count]) => ({ [keyName]: key, count }))
    .sort((left, right) => right.count - left.count || String(left[keyName]).localeCompare(String(right[keyName])));
}

function countComponentAssignments(components) {
  if (!components || typeof components !== 'object') {
    return 0;
  }

  return Object.values(components).reduce((total, component) => {
    const brickIndices = Array.isArray(component?.brick_indices) ? component.brick_indices.length : 0;
    return total + brickIndices;
  }, 0);
}

function summarizeSave(saveData, options) {
  const brickAssets = Array.isArray(saveData.brick_assets) ? saveData.brick_assets : [];
  const materials = Array.isArray(saveData.materials) ? saveData.materials : [];
  const physicalMaterials = Array.isArray(saveData.physical_materials) ? saveData.physical_materials : [];
  const colors = Array.isArray(saveData.colors) ? saveData.colors : [];
  const owners = Array.isArray(saveData.brick_owners) ? saveData.brick_owners : [];
  const bricks = Array.isArray(saveData.bricks) ? saveData.bricks : [];
  const components = saveData.components && typeof saveData.components === 'object' ? saveData.components : {};
  const wires = Array.isArray(saveData.wires) ? saveData.wires : [];
  const assetHistogram = new Map();
  const ownerHistogram = new Map();
  let minPosition = null;
  let maxPosition = null;

  const brickRecords = bricks.slice(0, options.maxBricks).map((brick, index) => {
    const assetName = brickAssets[brick.asset_name_index] ?? `Asset#${brick.asset_name_index ?? -1}`;
    const ownerIndex = typeof brick.owner_index === 'number' ? brick.owner_index : null;
    const owner = ownerIndex != null && ownerIndex > 0 ? owners[ownerIndex - 1] : owners[ownerIndex ?? -1];
    const normalizedOwner = normalizeOwner(owner, ownerIndex);
    const position = Array.isArray(brick.position) ? brick.position : [0, 0, 0];

    assetHistogram.set(assetName, (assetHistogram.get(assetName) ?? 0) + 1);
    const ownerKey =
      normalizedOwner?.display_name ??
      normalizedOwner?.user_name ??
      (ownerIndex != null ? `Owner#${ownerIndex}` : 'Unowned');
    ownerHistogram.set(ownerKey, (ownerHistogram.get(ownerKey) ?? 0) + 1);

    if (!minPosition) {
      minPosition = [...position];
      maxPosition = [...position];
    } else {
      for (let axis = 0; axis < 3; axis += 1) {
        minPosition[axis] = Math.min(minPosition[axis], position[axis] ?? 0);
        maxPosition[axis] = Math.max(maxPosition[axis], position[axis] ?? 0);
      }
    }

    return {
      index,
      asset_name: assetName,
      asset_kind: assetKind(assetName),
      size: vectorObject(brick.size),
      position: vectorObject(position),
      direction: directionName(brick.direction),
      rotation: rotationName(brick.rotation),
      visible: brick.visibility !== false,
      collision: collisionObject(brick.collision),
      owner_index: ownerIndex,
      owner: normalizedOwner,
      color: colorObject(brick.color, colors),
      material: materials[brick.material_index] ?? null,
      physical_material: physicalMaterials[brick.physical_index] ?? null,
      material_intensity: brick.material_intensity ?? null,
      component_names: Object.keys(brick.components ?? {}),
      components: brick.components ?? {},
    };
  });

  return {
    status: 'ok',
    updated_at: new Date().toISOString(),
    source_save_path: options.savePath,
    source_save_size: options.saveSize,
    source_save_mtime: options.saveMtime,
    region: {
      center: vectorObject(options.center),
      extent: vectorObject(options.extent),
    },
    map: saveData.map ?? null,
    description: saveData.description ?? '',
    author: saveData.author ?? null,
    host: saveData.host ?? null,
    brick_count: saveData.brick_count ?? bricks.length,
    exported_brick_count: bricks.length,
    owner_count: owners.length,
    asset_count: brickAssets.length,
    material_count: materials.length,
    component_type_count: Object.keys(components).length,
    component_assignment_count: countComponentAssignments(components),
    wire_count: wires.length,
    bounds: minPosition && maxPosition ? { min: vectorObject(minPosition), max: vectorObject(maxPosition) } : null,
    owners: owners.map((owner, index) => normalizeOwner(owner, index + 1)),
    owner_histogram: toHistogramEntries(ownerHistogram, 'owner'),
    asset_histogram: toHistogramEntries(assetHistogram, 'asset_name'),
    bricks_truncated: bricks.length > options.maxBricks,
    bricks_in_snapshot: brickRecords.length,
    bricks: brickRecords,
  };
}

const args = parseArgs(process.argv.slice(2));
const savePath = args.savePath;
const snapshotPath = args.snapshotPath;
const tracePath = args.tracePath || path.resolve(process.cwd(), 'world-state-live-sampler.log');
const pollMs = Number(args.pollMs || 1000);
const settleMs = Number(args.settleMs || 750);
const center = parseVector(args.center, [0, 0, 0]);
const extent = parseVector(args.extent, [100, 100, 100]);
const maxBricks = Number(args.maxBricks || 512);

if (!savePath || !snapshotPath) {
  throw new Error('watch-world-state-snapshot.js requires --savePath and --snapshotPath');
}

let lastProcessedSignature = null;
let pendingSignature = null;
let pendingSince = 0;
let lastStatus = '';

function writeStatus(status, extra = {}) {
  const payload = {
    status,
    updated_at: new Date().toISOString(),
    source_save_path: savePath,
    region: {
      center: vectorObject(center),
      extent: vectorObject(extent),
    },
    ...extra,
  };
  writeJsonAtomic(snapshotPath, payload);
  lastStatus = status;
}

function processLatestSave() {
  let stat;
  try {
    stat = fs.statSync(savePath);
  } catch (error) {
    if (lastStatus !== 'waiting_for_first_save') {
      writeStatus('waiting_for_first_save');
      appendTrace(tracePath, `waiting for first save at ${savePath}`);
    }
    pendingSignature = null;
    return;
  }

  const signature = `${stat.size}:${stat.mtimeMs}`;
  if (signature === lastProcessedSignature) {
    return;
  }

  if (signature !== pendingSignature) {
    pendingSignature = signature;
    pendingSince = Date.now();
    appendTrace(tracePath, `observed save change size=${stat.size} mtime=${stat.mtimeMs}`);
    return;
  }

  if (Date.now() - pendingSince < settleMs) {
    return;
  }

  try {
    const saveData = brs.read(fs.readFileSync(savePath));
    const snapshot = summarizeSave(saveData, {
      savePath,
      saveSize: stat.size,
      saveMtime: new Date(stat.mtimeMs).toISOString(),
      center,
      extent,
      maxBricks,
    });
    writeJsonAtomic(snapshotPath, snapshot);
    appendTrace(
      tracePath,
      `wrote snapshot bricks=${snapshot.exported_brick_count} components=${snapshot.component_assignment_count} wires=${snapshot.wire_count}`
    );
    lastProcessedSignature = signature;
    pendingSignature = null;
    lastStatus = 'ok';
  } catch (error) {
    appendTrace(tracePath, `parse failed for ${savePath}: ${error.stack || error.message}`);
  }
}

appendTrace(
  tracePath,
  `watcher starting savePath=${savePath} snapshotPath=${snapshotPath} pollMs=${pollMs} settleMs=${settleMs}`
);
processLatestSave();
setInterval(processLatestSave, pollMs);
