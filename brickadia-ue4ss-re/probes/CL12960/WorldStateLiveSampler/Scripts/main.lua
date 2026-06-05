local MOD_NAME = "WorldStateLiveSampler"
local DEFAULT_TRACE_PATH = "Mods/" .. MOD_NAME .. "/runtime/mod.log"
local DEFAULT_SNAPSHOT_PATH = "Mods/" .. MOD_NAME .. "/runtime/latest-snapshot.json"
local DEFAULT_HISTORY_PATH = "Mods/" .. MOD_NAME .. "/runtime/history.jsonl"
local TRACE_PATH = os.getenv("OMEGGA_UE4SS_WORLD_STATE_LOG") or DEFAULT_TRACE_PATH
local SNAPSHOT_PATH = os.getenv("OMEGGA_UE4SS_WORLD_STATE_SNAPSHOT") or DEFAULT_SNAPSHOT_PATH
local HISTORY_PATH = os.getenv("OMEGGA_UE4SS_WORLD_STATE_HISTORY") or DEFAULT_HISTORY_PATH
local INTERVAL_MS = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_INTERVAL_MS") or "750") or 750
local START_DELAY_MS = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_START_DELAY_MS") or "1500") or 1500
local CENTER_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_CENTER") or "0,0,0"
local EXTENT_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_EXTENT") or "100,100,100"
local CANDIDATE_CLASSES_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_CLASSES")
  or "GameModeBase,GameStateBase,GameSession,PlayerController,BP_PlayerController_C,BP_PlayerState_C,Tool_Selector_C,BP_ToolPreviewActor_C,BrickGrid,BrickGridActor,BrickGridComponent,BrickGridDynamicActor,Entity_DynamicBrickGrid,BrickBuildingTemplate,BrickGridPreviewActor,BrickGridPreviewActor_C,BP_BrickGrid_C,BRWorldManager,BRWorldSerializer,BrickPrefabs,BRBundleArchive,BRChatCommandWorldSubsystem,BRBundleTransferComponent,BRGizmoManagerComponent,BRPrefabCache,BRPrefabCacheInMemoryPrefab,BRPrefabHashAndMetadata,BRPrefabDetachedPasteInfo"
local TARGET_FUNCTIONS_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_FUNCTIONS")
  or "ServerPlaceCurrentPrefab,ServerPastePrefab,ApplyPrefabState,PrefabCaptureBricks,PrefabCaptureComponents,PrefabCaptureEntities,PrefabCaptureWires,ClientNotifyPrefabCaptureComplete,ClientNotifyPrefabCaptureFailed,GetPendingWorldBundle,RequestLoadWorldAdditive,ClientLoadWorldAccepted,ClientLoadWorldRejected,ServerUploadPrefab,ClientUploadPrefab"
local TARGET_PROPERTIES_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_PROPERTIES")
  or "PendingWorldBundle,CachedWorldBundle,CachedPrefabBundle,SavedWorldBundle,CurrentWorldBundle,WorldSerializer,CurrentTemplate,CurrentSelectionBoxGrid,PrefabInfo,PrefabMetadata,PrefabCounts,PrefabArchive,PrefabsInProgress,BundleType,Metadata,Counts,DetachedPasteInfo,GridOffset,PlacementOrientation,Cache"
local TARGET_NATIVE_CALLS_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_NATIVE_CALLS")
  or "BRWorldManager:GetPendingWorldBundle,BRBundleTransferComponent:GetPendingWorldBundle,BRWorldManager:GetCurrentBundleState,BRBundleTransferComponent:GetCurrentBundleState,BRWorldManager:GetGlobalBrickGrid,BRWorldManager:GetGlobalBrickGridActor,BrickGridActor:GetBrickCount,BrickGridActor:GetBrickGrid,BrickGridComponent:GetBrickCount,BrickGridComponent:GetBrickGrid,BrickGridDynamicActor:GetBrickCount,BrickGridDynamicActor:GetBrickGrid,BRBundleArchive:GetBrickCount,BRBundleArchive:CountBricksAndComponents,Tool_Selector_C:HasSelection,Tool_Selector_C:HasSelectionBox,Tool_Selector_C:GetCurrentSelectionState,Tool_Selector_C:GetSelectionLayers,BP_ToolPreviewActor_C:GetPlaceable"
local SURFACE_SCAN_CLASSES_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_SURFACE_CLASSES")
  or "PlayerController,BP_PlayerController_C,BRWorldManager,BRPrefabCache,BrickGridActor,BrickGridComponent,BrickGridDynamicActor,BRBundleArchive,BRPrefabCacheInMemoryPrefab,BRPrefabHashAndMetadata,BRPrefabDetachedPasteInfo"
local SURFACE_SCAN_KEYWORDS_RAW = os.getenv("OMEGGA_UE4SS_WORLD_STATE_SURFACE_KEYWORDS")
  or "grid,brick,chunk,bundle,prefab,entity,owner,position,relative,component,metadata,archive,serializer,cache"
local SURFACE_SCAN_MAX_MATCHES = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_SURFACE_MAX_MATCHES") or "24") or 24
local SURFACE_SCAN_MAX_DEPTH = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_SURFACE_MAX_DEPTH") or "2") or 2
local PROPERTY_ARRAY_SAMPLE_LIMIT = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_ARRAY_SAMPLE_LIMIT") or "3") or 3
local MAX_RECENT_TRANSITIONS = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_MAX_TRANSITIONS") or "25") or 25
local MAX_CANDIDATE_OBJECT_RECORDS = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_MAX_CANDIDATE_OBJECTS") or "96") or 96
local MAX_CAPTURE_ALIAS_EDGES = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_MAX_CAPTURE_ALIAS_EDGES") or "24") or 24
local MAX_CAPTURE_ALIAS_HANDLES = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_MAX_CAPTURE_ALIAS_HANDLES") or "16") or 16
local REPEATED_ALIAS_MIN_COUNT = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_REPEATED_ALIAS_MIN_COUNT") or "2") or 2
local REPLAY_PROPERTY_ONLY_MIN_TRIGGER_COUNT = tonumber(
  os.getenv("OMEGGA_UE4SS_WORLD_STATE_REPLAY_PROPERTY_ONLY_MIN_TRIGGER_COUNT") or "6"
) or 6
local REPLAY_BURST_CAPTURE_BUDGET = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_STATE_REPLAY_BURST_CAPTURE_BUDGET") or "4")
  or 4
local replay_count_keys
local normalize_replay_handle
local replay_object_identity
local replay_alias_member_sort_key
local canonical_replay_alias_key
local build_replay_capture_phase
local build_replay_alias_graph
local record_replay_alias_edges
local build_replay_alias_history_snapshot
local TARGET_CLASS_PROPERTY_MAP = {
  Tool_Selector_C = { "CurrentTemplate", "CurrentSelectionBoxGrid", "PrefabInfo", "PrefabCounts" },
  BP_ToolPreviewActor_C = { "CurrentTemplate", "CurrentSelectionBoxGrid", "Grid", "GridIndex" },
  BrickGridPreviewActor = { "Grid", "GridIndex", "GridCellSize" },
  BRWorldManager = {
    "PendingWorldBundle",
    "CachedWorldBundle",
    "CachedPrefabBundle",
    "SavedWorldBundle",
    "CurrentWorldBundle",
    "WorldSerializer",
    "PrefabArchive",
    "PrefabsInProgress",
    "BundleType",
  },
  BRBundleArchive = {
    "PrefabInfo",
    "PrefabMetadata",
    "PrefabCounts",
    "PrefabArchive",
    "BundleType",
    "NumBricks",
    "BrickCount",
    "NumComponents",
    "ComponentCount",
    "ChunkOffsets",
    "ChunkSizes",
    "BricksInChunk",
    "OwnerIndices",
    "OriginalOwnerIndices",
    "RelativePositions",
    "EntityTypes",
    "ComponentTypes",
  },
  BRBundleTransferComponent = {
    "PendingWorldBundle",
    "CachedWorldBundle",
    "SavedWorldBundle",
    "CurrentWorldBundle",
    "PrefabArchive",
    "PrefabsInProgress",
    "BundleType",
  },
  BRGizmoManagerComponent = { "CurrentSelectionBoxGrid", "Grid", "GridIndex" },
  BRPrefabCache = { "PrefabsInProgress", "CachedPrefabBundle", "PrefabArchive", "Cache" },
  BRPrefabCacheInMemoryPrefab = { "PrefabArchive", "Metadata", "Counts", "DetachedPasteInfo" },
  BRPrefabHashAndMetadata = { "Metadata", "Counts", "DetachedPasteInfo" },
  BRPrefabDetachedPasteInfo = { "GridOffset", "PlacementOrientation" },
  BrickGridActor = { "Grid", "GridIndex", "GridCellSize", "NumBricks", "BrickCount" },
  BrickGridComponent = { "Grid", "GridIndex", "GridCellSize", "NumBricks", "BrickCount", "NumComponents", "ComponentCount" },
  BrickGridDynamicActor = {
    "Grid",
    "GridIndex",
    "GridCellSize",
    "NumBricks",
    "BrickCount",
    "NumComponents",
    "ComponentCount",
    "ChunkOffsets",
    "ChunkSizes",
    "BricksInChunk",
    "OwnerIndices",
    "OriginalOwnerIndices",
    "RelativePositions",
    "Orientations",
    "MaterialIndices",
    "ColorsAndAlphas",
    "EntityType",
    "EntityTypes",
    "ComponentTypes",
    "PrefabInfo",
    "PrefabMetadata",
    "PrefabCounts",
    "Owner",
  },
  Entity_DynamicBrickGrid = {
    "Grid",
    "GridIndex",
    "GridCellSize",
    "NumBricks",
    "BrickCount",
    "NumComponents",
    "ComponentCount",
    "EntityType",
    "EntityTypes",
    "PrefabInfo",
    "PrefabMetadata",
    "PrefabCounts",
    "Owner",
  },
}
local REPLAY_CAPTURE_CLASSES = {
  BRWorldManager = true,
  BRBundleTransferComponent = true,
  BRBundleArchive = true,
  BrickGridActor = true,
  BrickGridComponent = true,
  BrickGridDynamicActor = true,
}
local REPLAY_CAPTURE_TRIGGER_CLASSES = {
  BRBundleArchive = true,
  BRBundleTransferComponent = true,
  BrickGridDynamicActor = true,
  BrickGridComponent = true,
  BrickGridActor = true,
}
local REPLAY_CAPTURE_TRIGGER_PROPERTIES = {
  BRBundleTransferComponent = {
    PendingWorldBundle = true,
    CurrentWorldBundle = true,
    CachedWorldBundle = true,
    SavedWorldBundle = true,
    PrefabArchive = true,
    PrefabsInProgress = true,
  },
  BRWorldManager = {
    PendingWorldBundle = true,
    CurrentWorldBundle = true,
    CachedWorldBundle = true,
    SavedWorldBundle = true,
    PrefabArchive = true,
    PrefabsInProgress = true,
  },
  BRBundleArchive = {
    ChunkOffsets = true,
    ChunkSizes = true,
    OwnerIndices = true,
    RelativePositions = true,
    PrefabMetadata = true,
    PrefabInfo = true,
  },
}

local state = {
  retained_callbacks = {},
  initgamestate_hook_count = 0,
  selected_initgamestate_hook_count = nil,
  latest_hook_context = nil,
  latest_context_resolver = nil,
  cached_world = nil,
  cached_persistent_level = nil,
  cached_game_mode = nil,
  cached_game_state = nil,
  cached_game_session = nil,
  cached_game_instance = nil,
  ready = false,
  loop_started = false,
  ready_logged = false,
  candidate_state = {},
  native_call_state = {},
  property_probe_state = {},
  replay_property_trigger_state = {},
  replay_property_only_armed = true,
  replay_burst_remaining = 0,
  replay_surface_capture_signature = nil,
  latest_replay_surface_capture = nil,
  surface_probe_state = {},
  recent_transitions = {},
}

local function normalize_parent(path)
  local normalized = tostring(path or ""):gsub("/", "\\")
  return normalized:match("^(.*)\\[^\\]+$")
end

local function ensure_parent(path)
  local parent = normalize_parent(path)
  if parent and parent ~= "" then
    os.execute('if not exist "' .. parent .. '" mkdir "' .. parent .. '"')
  end
end

local function append_file(path, value)
  ensure_parent(path)
  local handle = io.open(path, "a")
  if not handle then
    return false
  end
  handle:write(value)
  handle:close()
  return true
end

local function write_file(path, value)
  ensure_parent(path)
  local temp_path = path .. ".tmp"
  local handle = io.open(temp_path, "w")
  if not handle then
    return false
  end
  handle:write(value)
  handle:close()
  os.remove(path)
  local ok = os.rename(temp_path, path)
  if not ok then
    local fallback = io.open(path, "w")
    if not fallback then
      return false
    end
    fallback:write(value)
    fallback:close()
    os.remove(temp_path)
  end
  return true
end

local function trace(message)
  local rendered = "[" .. MOD_NAME .. "] " .. tostring(message)
  print(rendered)
  append_file(TRACE_PATH, os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. rendered .. "\n")
end

local function retain_callback(key, callback)
  state.retained_callbacks[tostring(key or "")] = callback
  return callback
end

local function parse_csv_list(raw)
  local results = {}
  local seen = {}
  for token in tostring(raw or ""):gmatch("[^,%s]+") do
    local cleaned = tostring(token):match("^%s*(.-)%s*$")
    if cleaned ~= "" then
      local normalized = cleaned:lower()
      if not seen[normalized] then
        seen[normalized] = true
        results[#results + 1] = cleaned
      end
    end
  end
  return results
end

local function parse_vector3(raw, fallback)
  local values = {}
  for token in tostring(raw or ""):gmatch("[^,%s]+") do
    local parsed = tonumber(token)
    if parsed == nil then
      return fallback
    end
    values[#values + 1] = parsed
  end

  if #values ~= 3 then
    return fallback
  end

  return values
end

local function parse_native_call_targets(raw)
  local results = {}
  local seen = {}
  for token in tostring(raw or ""):gmatch("[^,;%s]+") do
    local class_name, function_name = tostring(token):match("^([^:]+):(.+)$")
    class_name = tostring(class_name or ""):match("^%s*(.-)%s*$")
    function_name = tostring(function_name or ""):match("^%s*(.-)%s*$")
    if class_name ~= "" and function_name ~= "" then
      local normalized = string.lower(class_name .. ":" .. function_name)
      if not seen[normalized] then
        seen[normalized] = true
        results[#results + 1] = {
          class_name = class_name,
          function_name = function_name,
        }
      end
    end
  end
  return results
end

local CANDIDATE_CLASSES = parse_csv_list(CANDIDATE_CLASSES_RAW)
local TARGET_FUNCTIONS = parse_csv_list(TARGET_FUNCTIONS_RAW)
local TARGET_PROPERTIES = parse_csv_list(TARGET_PROPERTIES_RAW)
local TARGET_NATIVE_CALLS = parse_native_call_targets(TARGET_NATIVE_CALLS_RAW)
local GRID_HANDLE_PROPERTY_NAMES = {
  "BrickCount",
  "NumBricks",
  "GridIndex",
  "GridCellSize",
}
local GRID_HANDLE_FUNCTION_NAMES = {
  "GetBrickCount",
  "GetGridIndex",
  "GetGridCellSize",
}
local SURFACE_SCAN_CLASSES = parse_csv_list(SURFACE_SCAN_CLASSES_RAW)
local SURFACE_SCAN_KEYWORDS = parse_csv_list(SURFACE_SCAN_KEYWORDS_RAW)
local REGION_CENTER = parse_vector3(CENTER_RAW, { 0, 0, 0 })
local REGION_EXTENT = parse_vector3(EXTENT_RAW, { 100, 100, 100 })

local function vector_object(values)
  return {
    x = values[1] or 0,
    y = values[2] or 0,
    z = values[3] or 0,
  }
end

local function escape_json(text)
  return tostring(text or "")
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
    :gsub("\t", "\\t")
end

local function truncate_text(value, max_length)
  local rendered = tostring(value or "")
  local limit = tonumber(max_length) or 240
  if #rendered <= limit then
    return rendered
  end
  return rendered:sub(1, limit - 3) .. "..."
end

local function is_array(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end

  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end

  return true
end

local function json_encode(value)
  local value_type = type(value)
  if value == nil then
    return "null"
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "number" then
    return tostring(value)
  elseif value_type == "string" then
    return '"' .. escape_json(value) .. '"'
  elseif value_type == "table" then
    local parts = {}
    if is_array(value) then
      for index = 1, #value do
        parts[#parts + 1] = json_encode(value[index])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end

    for key, inner_value in pairs(value) do
      parts[#parts + 1] = '"' .. escape_json(key) .. '":' .. json_encode(inner_value)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  return '"' .. escape_json(tostring(value)) .. '"'
end

local function write_snapshot(payload)
  local ok = write_file(SNAPSHOT_PATH, json_encode(payload) .. "\n")
  if not ok then
    trace("failed to write snapshot to " .. tostring(SNAPSHOT_PATH))
  end
end

local function append_history_record(payload)
  local ok = append_file(HISTORY_PATH, json_encode(payload) .. "\n")
  if not ok then
    trace("failed to append history to " .. tostring(HISTORY_PATH))
  end
end

local function safe_method_call(value, method_name)
  if value == nil then
    return false, nil, "nil receiver"
  end

  local ok, result = pcall(function()
    return value[method_name](value)
  end)
  if ok then
    return true, result, nil
  end

  return false, nil, tostring(result)
end

local count_array_entries
local describe_object
local resolve_reflection_class_object
local render_compact_value_sample

local function is_valid_object(object)
  local object_type = type(object)
  if object_type ~= "userdata" and object_type ~= "table" then
    return false
  end

  return object and type(object.IsValid) == "function" and object:IsValid()
end

local function try_get_property_value(object, property_name)
  if not is_valid_object(object) then
    return nil
  end

  local ok, value = pcall(function()
    return object:GetPropertyValue(property_name)
  end)
  if not ok or value == nil then
    return nil
  end

  return value
end

local function resolve_object(candidate)
  local diagnostics = {}
  if candidate == nil then
    return nil, "nil", diagnostics
  end

  local lower_get_ok, lower_get_value = pcall(function()
    return candidate:get()
  end)
  diagnostics.lower_get = {
    ok = lower_get_ok,
  }
  if lower_get_ok then
    diagnostics.lower_get.result = render_compact_value_sample(lower_get_value)
  else
    diagnostics.lower_get.error = truncate_text(lower_get_value, 160)
  end
  if lower_get_ok then
    return lower_get_value, "param_get", diagnostics
  end

  local upper_get_ok, upper_get_value = pcall(function()
    return candidate:Get()
  end)
  diagnostics.upper_get = {
    ok = upper_get_ok,
  }
  if upper_get_ok then
    diagnostics.upper_get.result = render_compact_value_sample(upper_get_value)
  else
    diagnostics.upper_get.error = truncate_text(upper_get_value, 160)
  end
  if upper_get_ok then
    return upper_get_value, "param_Get", diagnostics
  end

  return candidate, "direct", diagnostics
end

local function get_fname_string(object)
  if not object then
    return nil
  end

  local method_ok, get_fname = pcall(function()
    return object.GetFName
  end)
  if not method_ok or type(get_fname) ~= "function" then
    return nil
  end

  local name_ok, fname = pcall(function()
    return get_fname(object)
  end)
  if not name_ok or not fname then
    return nil
  end

  if type(fname.ToString) == "function" then
    local string_ok, rendered = pcall(function()
      return fname:ToString()
    end)
    if string_ok and rendered and tostring(rendered) ~= "" then
      return tostring(rendered)
    end
  end

  if type(fname.GetComparisonIndex) == "function" then
    local index_ok, comparison_index = pcall(function()
      return fname:GetComparisonIndex()
    end)
    if index_ok and type(comparison_index) == "number" then
      return string.format("FName#%d", comparison_index)
    end
  end

  return nil
end

local function get_full_name_string(object)
  if not object then
    return nil
  end

  local method_ok, get_full_name = pcall(function()
    return object.GetFullName
  end)
  if not method_ok or type(get_full_name) ~= "function" then
    return nil
  end

  local ok, value = pcall(function()
    return get_full_name(object)
  end)
  if ok and value and tostring(value) ~= "" then
    return tostring(value)
  end

  return nil
end

local function get_object_address_string(object)
  if not is_valid_object(object) then
    return nil
  end

  local ok, address = pcall(function()
    return tostring(object)
  end)
  if ok then
    local address_text = tostring(address or "")
    local match = address_text:match("0x[0-9A-Fa-f]+") or address_text:match("(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)")
    if match and match ~= "" then
      if not match:match("^0x") then
        match = "0x" .. match
      end
      return string.lower(match)
    end
  end

  return nil
end

local function value_to_string(value)
  if value == nil then
    return nil
  end

  local value_type = type(value)
  if value_type == "string" or value_type == "number" or value_type == "boolean" then
    return tostring(value)
  end

  if value_type == "userdata" then
    if type(value.ToString) == "function" then
      local string_ok, string_value = pcall(function()
        return value:ToString()
      end)
      if string_ok and string_value and tostring(string_value) ~= "" then
        return tostring(string_value)
      end
    end

    if type(value.GetComparisonIndex) == "function" then
      local index_ok, comparison_index = pcall(function()
        return value:GetComparisonIndex()
      end)
      if index_ok and type(comparison_index) == "number" then
        return string.format("FName#%d", comparison_index)
      end
    end
  end

  return tostring(value)
end

local function call_value_method(value, method_name)
  local ok, result = pcall(function()
    local method = value and value[method_name]
    if type(method) ~= "function" then
      error("missing method " .. tostring(method_name))
    end
    return method(value)
  end)

  return ok, result
end

render_compact_value_sample = function(value)
  if is_valid_object(value) then
    return {
      kind = "object",
      object = describe_object("sample", value),
    }
  end

  local rendered = truncate_text(value_to_string(value), 120)
  return {
    kind = type(value),
    value = rendered,
  }
end

local function collect_metatable_keys(value, limit)
  local meta_ok, meta = pcall(getmetatable, value)
  if not meta_ok or type(meta) ~= "table" then
    return meta_ok, meta, nil
  end

  local keys = {}
  local max_keys = tonumber(limit) or 8
  for key in pairs(meta) do
    keys[#keys + 1] = tostring(key)
    if #keys >= max_keys then
      break
    end
  end
  table.sort(keys)
  return true, meta, keys
end

local function infer_userdata_wrapper_kind(meta_keys)
  if type(meta_keys) ~= "table" or #meta_keys == 0 then
    return nil
  end

  local keyset = {}
  for _, key in ipairs(meta_keys) do
    keyset[tostring(key)] = true
  end

  if keyset.GetArrayNum and keyset.GetArrayMax and keyset.GetArrayDataAddress then
    return "TArray"
  end

  if keyset.ForEachProperty and keyset.GetPropertyAddress then
    return "UScriptStruct"
  end

  if keyset.GetPropertyClass and keyset.GetClass then
    return "ObjectProperty"
  end

  if keyset.GetStruct and keyset.GetClass then
    return "StructProperty"
  end

  if keyset.GetInner and keyset.GetClass then
    return "ArrayProperty"
  end

  if keyset.GetProperty and keyset.ReflectedObject then
    return "UObjectReflection"
  end

  if keyset.GetFullName and keyset.GetClass and keyset.IsValid then
    return "UObjectLike"
  end

  return "userdata_with_metatable"
end

local function render_userdata_probe_value(value)
  if type(value) ~= "userdata" then
    return nil
  end
  if is_valid_object(value) then
    return nil
  end

  local payload = {
    kind = "userdata",
    value = truncate_text(value_to_string(value), 160),
    probe_mode = "observe_only",
    note = "native userdata handle observed; method probing disabled for stability",
  }

  local meta_ok, meta, meta_keys = collect_metatable_keys(value, 12)
  payload.has_metatable = meta_ok and meta ~= nil
  if meta_ok and meta ~= nil then
    payload.metatable_lua_type = type(meta)
  end
  if meta_keys ~= nil then
    payload.metatable_keys = meta_keys
    payload.wrapper_kind = infer_userdata_wrapper_kind(meta_keys)
  end

  local wrapper_type_ok, wrapper_type = call_value_method(value, "type")
  if wrapper_type_ok and type(wrapper_type) == "string" and wrapper_type ~= "" then
    payload.ue4ss_type = wrapper_type
    if payload.wrapper_kind == nil then
      payload.wrapper_kind = wrapper_type
    end
  end

  if payload.ue4ss_type == "TArray" then
    local array_num_ok, array_num = call_value_method(value, "GetArrayNum")
    if array_num_ok and type(array_num) == "number" then
      payload.array_num = array_num
    end

    local array_max_ok, array_max = call_value_method(value, "GetArrayMax")
    if array_max_ok and type(array_max) == "number" then
      payload.array_max = array_max
    end

    local array_data_ok, array_data = call_value_method(value, "GetArrayDataAddress")
    if array_data_ok and type(array_data) == "number" then
      payload.array_data_address = string.format("0x%X", array_data)
    end
  end

  return payload
end

local function render_wrapper_probe_value(value)
  if type(value) ~= "table" then
    return nil
  end

  local payload = {
    kind = "wrapper_table",
    count = count_array_entries(value),
    string_value = truncate_text(value_to_string(value), 160),
  }

  local meta_ok, meta, meta_keys = collect_metatable_keys(value, 8)
  payload.has_metatable = meta_ok and meta ~= nil
  if meta_keys ~= nil then
    payload.metatable_keys = meta_keys
  end

  local sample_indexes = {}
  for index = 1, PROPERTY_ARRAY_SAMPLE_LIMIT do
    local index_ok, index_value = pcall(function()
      return value[index]
    end)
    if index_ok and index_value ~= nil then
      sample_indexes[#sample_indexes + 1] = {
        index = index - 1,
        sample = render_compact_value_sample(index_value),
      }
    end
  end
  if #sample_indexes > 0 then
    payload.index_samples = sample_indexes
  end

  return payload
end

local function render_property_probe_value(value)
  if is_valid_object(value) then
    return {
      kind = "object",
      object = describe_object("value", value),
    }
  end

  local userdata_probe = render_userdata_probe_value(value)
  if userdata_probe ~= nil then
    return userdata_probe
  end

  local wrapper_probe = render_wrapper_probe_value(value)
  if wrapper_probe ~= nil then
    return wrapper_probe
  end

  if type(value) == "table" then
    local array_count = count_array_entries(value)
    return {
      kind = "table",
      count = array_count,
    }
  end

  return {
    kind = "scalar",
    lua_type = type(value),
    value = truncate_text(value_to_string(value), 160),
  }
end

local function render_native_call_result(value)
  if value == nil then
    return {
      kind = "nil",
    }
  end

  local resolved_value, resolved_via, resolve_attempts = resolve_object(value)
  if resolved_via ~= "direct" and is_valid_object(resolved_value) then
    return {
      kind = "object",
      resolved_via = resolved_via,
      resolve_attempts = resolve_attempts,
      object = describe_object("value", resolved_value),
    }
  end

  if resolved_via ~= "direct" then
    return {
      kind = "resolved_wrapper",
      resolved_via = resolved_via,
      resolve_attempts = resolve_attempts,
      original = render_property_probe_value(value),
      resolved_value = render_property_probe_value(resolved_value),
    }
  end

  local rendered = render_property_probe_value(value)
  if type(rendered) == "table" and resolve_attempts ~= nil then
    rendered.resolve_attempts = resolve_attempts
  end
  return rendered
end

local function extract_short_name(full_name)
  local match = tostring(full_name or ""):match("%.([%w_]+)$")
  if match and match ~= "" then
    return match
  end
  return tostring(full_name or "")
end

local function extract_terminal_name(full_name, fallback)
  local normalized = tostring(full_name or ""):gsub("^%s*[%w_]+%s+", "")
  local tail = normalized:match("[:.]([%w_]+)$")
  if tail and tail ~= "" then
    return tail
  end

  local short_name = extract_short_name(normalized)
  if short_name and short_name ~= "" and short_name ~= normalized then
    return short_name
  end

  return fallback or normalized
end

local function get_object_short_name(object, fallback)
  if not is_valid_object(object) then
    return fallback or "nil"
  end

  local short_name = get_fname_string(object)
  if not short_name or short_name == "" or short_name:match("^FName#%d+$") then
    local full_name = get_full_name_string(object)
    local terminal_name = extract_terminal_name(full_name, nil)
    if terminal_name and terminal_name ~= "" then
      short_name = terminal_name
    end
  end

  if short_name and short_name ~= "" then
    return short_name
  end

  local address = get_object_address_string(object)
  if address and address ~= "" then
    return address
  end

  return fallback or "nil"
end

local function object_label(object)
  if not is_valid_object(object) then
    return nil
  end

  local short_name = get_object_short_name(object, nil)
  local full_name = get_full_name_string(object)
  local address = get_object_address_string(object)

  if full_name and full_name ~= "" and address and address ~= "" then
    return full_name .. "@" .. address
  end

  if short_name and short_name ~= "" and address and address ~= "" then
    return short_name .. "@" .. address
  end

  if full_name and full_name ~= "" then
    return full_name
  end

  if short_name and short_name ~= "" then
    return short_name
  end

  return tostring(object)
end

local function contains_surface_keyword(text)
  local haystack = string.lower(tostring(text or ""))
  if haystack == "" then
    return false
  end

  for _, keyword in ipairs(SURFACE_SCAN_KEYWORDS) do
    local needle = string.lower(tostring(keyword or ""))
    if needle ~= "" and string.find(haystack, needle, 1, true) then
      return true
    end
  end

  return false
end

local function get_property_name(property)
  if not is_valid_object(property) then
    return nil
  end

  local fname_ok, fname = safe_method_call(property, "GetFName")
  if fname_ok and fname and type(fname.ToString) == "function" then
    local string_ok, string_value = pcall(function()
      return fname:ToString()
    end)
    if string_ok and string_value and tostring(string_value) ~= "" then
      return tostring(string_value)
    end
  end

  local string_value = value_to_string(property)
  if string_value and string_value ~= "" then
    return string_value
  end

  return nil
end

local function get_property_class_name(property)
  if not property or type(property.GetClass) ~= "function" then
    return "unknown"
  end

  local ok, property_class = pcall(function()
    return property:GetClass()
  end)
  if ok and is_valid_object(property_class) then
    return get_object_short_name(property_class, "unknown")
  end

  return "unknown"
end

local function get_object_property_class_name(property)
  if not property or type(property.GetPropertyClass) ~= "function" then
    return nil
  end

  local ok, property_class = pcall(function()
    return property:GetPropertyClass()
  end)
  if ok and is_valid_object(property_class) then
    return get_object_short_name(property_class, nil)
  end

  return nil
end

local function get_struct_property_name(property)
  if not property or type(property.GetStruct) ~= "function" then
    return nil
  end

  local ok, struct = pcall(function()
    return property:GetStruct()
  end)
  if ok and is_valid_object(struct) then
    return get_object_short_name(struct, nil)
  end

  return nil
end

local function find_reflected_property(object, property_name)
  if not is_valid_object(object) then
    return nil, "invalid receiver"
  end

  local reflection_ok, reflection, reflection_error = safe_method_call(object, "Reflection")
  if not reflection_ok or reflection == nil then
    return nil, reflection_error or "reflection unavailable"
  end

  if type(reflection.GetProperty) ~= "function" then
    return nil, "reflection GetProperty is unavailable"
  end

  local ok, property = pcall(function()
    return reflection:GetProperty(property_name)
  end)
  if not ok then
    return nil, tostring(property)
  end
  if not is_valid_object(property) then
    return nil, "property metadata unavailable"
  end

  return property, nil
end

local function find_iterated_property(object, property_name)
  local class_object = resolve_reflection_class_object(object)
  if not is_valid_object(class_object) then
    return nil, "reflection class unavailable"
  end
  if type(class_object.ForEachProperty) ~= "function" then
    return nil, "ForEachProperty is unavailable"
  end

  local target_name = string.lower(tostring(property_name or ""))
  local matched_property = nil
  local callback_key = "find_iterated_property:" .. tostring(target_name)
  local iterator_callback = retain_callback(callback_key, function(property)
    local candidate_name = string.lower(tostring(get_property_name(property) or ""))
    local candidate_tail = string.lower(tostring(extract_terminal_name(candidate_name, candidate_name) or ""))
    local exact_match = candidate_name == target_name or candidate_tail == target_name
    local contains_match = candidate_name:find(target_name, 1, true) ~= nil
      or target_name:find(candidate_name, 1, true) ~= nil
      or candidate_tail:find(target_name, 1, true) ~= nil
    if exact_match or contains_match then
      matched_property = property
      return true
    end
  end)
  local ok, err = pcall(function()
    class_object:ForEachProperty(iterator_callback)
  end)
  if not ok then
    return nil, tostring(err)
  end
  if not is_valid_object(matched_property) then
    return nil, "property metadata unavailable"
  end

  return matched_property, nil
end

local function describe_reflected_property(object, property_name)
  local property, reason = find_reflected_property(object, property_name)
  if not is_valid_object(property) then
    property, reason = find_iterated_property(object, property_name)
    if not is_valid_object(property) then
      return {
        available = false,
        reason = reason,
      }
    end
  end

  return {
    available = true,
    reflected_name = get_property_name(property) or property_name,
    property_class = get_property_class_name(property),
    object_property_class = get_object_property_class_name(property),
    struct_property_name = get_struct_property_name(property),
  }
end

local function get_function_name(func)
  if not is_valid_object(func) then
    return nil
  end

  local short_name = get_object_short_name(func, nil)
  if short_name and short_name ~= "" then
    return short_name
  end

  local full_name = get_full_name_string(func)
  if full_name and full_name ~= "" then
    return extract_terminal_name(full_name, full_name)
  end

  return nil
end

local function find_named_function_hit(object, function_name)
  if not is_valid_object(object) then
    return nil, "invalid receiver"
  end

  local class = object:GetClass()
  if not is_valid_object(class) then
    return nil, "class unavailable"
  end
  if type(class.ForEachFunction) ~= "function" then
    return nil, "ForEachFunction unavailable"
  end

  local expected = string.lower(tostring(function_name or ""))
  local hit = nil
  local callback_key = "find_named_function_hit:" .. tostring(get_object_address_string(class) or tostring(class)) .. ":" .. expected
  local function_callback = retain_callback(callback_key, function(func)
    if not is_valid_object(func) then
      return false
    end

    local candidate_name = string.lower(tostring(get_function_name(func) or ""))
    if candidate_name == expected then
      hit = func
      return true
    end

    local candidate_full_name = string.lower(tostring(get_full_name_string(func) or ""))
    local candidate_tail = string.lower(tostring(extract_terminal_name(candidate_full_name, candidate_full_name) or ""))
    if candidate_tail == expected then
      hit = func
      return true
    end

    return false
  end)

  local ok, err = pcall(function()
    class:ForEachFunction(function_callback)
  end)
  if not ok then
    return nil, tostring(err)
  end
  if not is_valid_object(hit) then
    return nil, "function not found"
  end

  return hit, nil
end

local function append_unique_match(matches, seen, value)
  local rendered = tostring(value or "")
  local normalized = string.lower(rendered)
  if rendered == "" or seen[normalized] then
    return
  end

  seen[normalized] = true
  matches[#matches + 1] = rendered
end

resolve_reflection_class_object = function(object)
  if not is_valid_object(object) then
    return nil
  end

  local class_object = object
  if type(object.IsClass) == "function" then
    local is_class_ok, is_class = pcall(function()
      return object:IsClass()
    end)
    if not is_class_ok or not is_class then
      local get_class_ok, resolved_class = safe_method_call(object, "GetClass")
      if get_class_ok and is_valid_object(resolved_class) then
        class_object = resolved_class
      end
    end
  elseif type(object.GetClass) == "function" then
    local get_class_ok, resolved_class = safe_method_call(object, "GetClass")
    if get_class_ok and is_valid_object(resolved_class) then
      class_object = resolved_class
    end
  end

  if is_valid_object(class_object) then
    return class_object
  end

  return nil
end

local function scan_surface_property_matches(class_object)
  local payload = {
    available = is_valid_object(class_object) and type(class_object.ForEachProperty) == "function",
    scanned_count = 0,
    match_count = 0,
    matches = {},
    walk_depth = 0,
    callback_error_count = 0,
    callback_errors = {},
  }
  if not payload.available then
    payload.success = false
    payload.reason = "property reflection is unavailable"
    return payload
  end

  local visited = {}
  local seen = {}
  local cursor = class_object
  local walk_error = nil

  while is_valid_object(cursor) and payload.walk_depth < SURFACE_SCAN_MAX_DEPTH do
    local cursor_name = object_label(cursor) or ("class-depth-" .. tostring(payload.walk_depth))
    if visited[cursor_name] then
      break
    end
    visited[cursor_name] = true
    payload.walk_depth = payload.walk_depth + 1

    local callback_key = "surface_property_scan:" .. tostring(cursor_name)
    local property_callback = retain_callback(callback_key, function(property)
      local property_ok, property_error = pcall(function()
        payload.scanned_count = payload.scanned_count + 1
        local property_name = get_property_name(property)
        local property_class = get_property_class_name(property)
        local object_class = get_object_property_class_name(property)
        local struct_name = get_struct_property_name(property)
        local keyword_haystack = table.concat({
          tostring(property_name or ""),
          tostring(property_class or ""),
          tostring(object_class or ""),
          tostring(struct_name or ""),
        }, " ")

        if contains_surface_keyword(keyword_haystack) then
          local descriptor = tostring(property_name or "unknown") .. ":" .. tostring(property_class or "unknown")
          if object_class and object_class ~= "" then
            descriptor = descriptor .. "<" .. object_class .. ">"
          elseif struct_name and struct_name ~= "" then
            descriptor = descriptor .. "<" .. struct_name .. ">"
          end
          append_unique_match(payload.matches, seen, descriptor)
        end
      end)

      if not property_ok then
        payload.callback_error_count = payload.callback_error_count + 1
        if #payload.callback_errors < 6 then
          payload.callback_errors[#payload.callback_errors + 1] = tostring(property_error)
        end
      end

      return #payload.matches >= SURFACE_SCAN_MAX_MATCHES
    end)

    local ok, err = pcall(function()
      cursor:ForEachProperty(property_callback)
    end)

    if not ok then
      walk_error = tostring(err)
      break
    end

    if #payload.matches >= SURFACE_SCAN_MAX_MATCHES or type(cursor.GetSuperStruct) ~= "function" then
      break
    end

    local super_ok, super_struct = safe_method_call(cursor, "GetSuperStruct")
    if not super_ok or not is_valid_object(super_struct) then
      break
    end

    cursor = super_struct
  end

  table.sort(payload.matches)
  payload.match_count = #payload.matches
  payload.success = walk_error == nil
  payload.error = walk_error
  return payload
end

local function scan_surface_function_matches(class_object)
  local payload = {
    available = is_valid_object(class_object) and type(class_object.ForEachFunction) == "function",
    scanned_count = 0,
    match_count = 0,
    matches = {},
    walk_depth = 0,
    callback_error_count = 0,
    callback_errors = {},
  }
  if not payload.available then
    payload.success = false
    payload.reason = "function reflection is unavailable"
    return payload
  end

  local visited = {}
  local seen = {}
  local cursor = class_object
  local walk_error = nil

  while is_valid_object(cursor) and payload.walk_depth < SURFACE_SCAN_MAX_DEPTH do
    local cursor_name = object_label(cursor) or ("class-depth-" .. tostring(payload.walk_depth))
    if visited[cursor_name] then
      break
    end
    visited[cursor_name] = true
    payload.walk_depth = payload.walk_depth + 1

    local callback_key = "surface_function_scan:" .. tostring(cursor_name)
    local function_callback = retain_callback(callback_key, function(func)
      local function_ok, function_error = pcall(function()
        payload.scanned_count = payload.scanned_count + 1
        local function_name = get_function_name(func)
        if function_name and contains_surface_keyword(function_name) then
          append_unique_match(payload.matches, seen, function_name)
        end
      end)

      if not function_ok then
        payload.callback_error_count = payload.callback_error_count + 1
        if #payload.callback_errors < 6 then
          payload.callback_errors[#payload.callback_errors + 1] = tostring(function_error)
        end
      end

      return #payload.matches >= SURFACE_SCAN_MAX_MATCHES
    end)

    local ok, err = pcall(function()
      cursor:ForEachFunction(function_callback)
    end)

    if not ok then
      walk_error = tostring(err)
      break
    end

    if #payload.matches >= SURFACE_SCAN_MAX_MATCHES or type(cursor.GetSuperStruct) ~= "function" then
      break
    end

    local super_ok, super_struct = safe_method_call(cursor, "GetSuperStruct")
    if not super_ok or not is_valid_object(super_struct) then
      break
    end

    cursor = super_struct
  end

  table.sort(payload.matches)
  payload.match_count = #payload.matches
  payload.success = walk_error == nil
  payload.error = walk_error
  return payload
end

local function perform_surface_probe(class_name, object)
  local class_object = resolve_reflection_class_object(object)
  local payload = {
    class_name = class_name,
    scanned_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    keyword_list = SURFACE_SCAN_KEYWORDS,
    object = describe_object(class_name, object),
    class_object = describe_object(class_name .. "_class", class_object),
  }

  if not is_valid_object(object) then
    payload.success = false
    payload.reason = "target object unavailable"
    return payload
  end

  if not is_valid_object(class_object) then
    payload.success = false
    payload.reason = "class object unavailable"
    return payload
  end

  payload.property_scan = scan_surface_property_matches(class_object)
  payload.function_scan = scan_surface_function_matches(class_object)
  payload.success = payload.property_scan.success == true and payload.function_scan.success == true
  return payload
end

describe_object = function(label, object)
  local payload = {
    label = label,
    is_valid = is_valid_object(object),
  }

  if not is_valid_object(object) then
    payload.lua_type = type(object)
    return payload
  end

  payload.object_name = object_label(object)
  payload.object_short_name = get_object_short_name(object, nil)
  payload.object_address = get_object_address_string(object)
  local class_ok, class_object = safe_method_call(object, "GetClass")
  payload.class_lookup_ok = class_ok
  if class_ok and is_valid_object(class_object) then
    payload.class_name = object_label(class_object)
    payload.class_short_name = get_object_short_name(class_object, nil)
  end

  return payload
end

count_array_entries = function(value)
  if type(value) ~= "table" then
    return nil
  end

  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  return count
end

local function schedule_probe(label, delay_ms, callback)
  local wrapped = retain_callback("scheduled_probe:" .. tostring(label or ""), callback)

  if delay_ms and delay_ms > 0 then
    if type(ExecuteInGameThreadAfterFrames) == "function" then
      local frames = math.max(1, math.floor(delay_ms / 100))
      ExecuteInGameThreadAfterFrames(frames, wrapped)
      return true
    end

    if type(ExecuteInGameThreadWithDelay) == "function" then
      ExecuteInGameThreadWithDelay(delay_ms, wrapped)
      return true
    end
  end

  local ok, err = pcall(wrapped)
  if not ok then
    trace("scheduled probe failed label=" .. tostring(label) .. " error=" .. tostring(err))
  end
  return ok
end

local function capture_context_objects(context_candidate)
  local hook_context, hook_resolver = resolve_object(context_candidate)
  local world = nil
  local persistent_level = nil
  local game_mode = nil
  local game_state = nil
  local game_session = nil
  local game_instance = nil

  if is_valid_object(hook_context) then
    local world_ok, resolved_world = safe_method_call(hook_context, "GetWorld")
    if world_ok and is_valid_object(resolved_world) then
      world = resolved_world
    end
  end

  if not is_valid_object(world) then
    local find_world_ok, found_world = pcall(function()
      return FindFirstOf("World")
    end)
    if find_world_ok then
      world = found_world
    end
  end

  if is_valid_object(world) then
    persistent_level = try_get_property_value(world, "PersistentLevel")
    game_mode = try_get_property_value(world, "AuthorityGameMode") or try_get_property_value(world, "GameMode")
    game_state = try_get_property_value(world, "GameState")
    game_instance = try_get_property_value(world, "OwningGameInstance")
  end

  if is_valid_object(game_mode) then
    game_session = try_get_property_value(game_mode, "GameSession")
    if not is_valid_object(game_instance) then
      game_instance = try_get_property_value(game_mode, "GameInstance")
    end
  end

  if not is_valid_object(game_instance) and is_valid_object(game_state) then
    game_instance = try_get_property_value(game_state, "GameInstance")
  end

  return {
    hook_context = hook_context,
    resolver = hook_resolver,
    world = world,
    persistent_level = persistent_level,
    game_mode = game_mode,
    game_state = game_state,
    game_session = game_session,
    game_instance = game_instance,
  }
end

local function build_context_snapshot()
  local hook_context = state.latest_hook_context
  local hook_resolver = state.latest_context_resolver
  local world = state.cached_world
  local persistent_level = state.cached_persistent_level
  local game_mode = state.cached_game_mode
  local game_state = state.cached_game_state
  local game_session = state.cached_game_session
  local game_instance = state.cached_game_instance

  local objects = {
    describe_object("hook_context", hook_context),
    describe_object("world", world),
    describe_object("persistent_level", persistent_level),
    describe_object("game_mode", game_mode),
    describe_object("game_state", game_state),
    describe_object("game_session", game_session),
    describe_object("game_instance", game_instance),
  }

  return {
    resolver = hook_resolver,
    objects = objects,
  }
end

local function scan_candidate_class(class_name)
  local payload = {
    class_name = class_name,
    count = 0,
    find_first_success = false,
    sample = nil,
    objects = {},
  }

  local seen_addresses = {}
  local function record_candidate_object(candidate)
    if not is_valid_object(candidate) then
      return
    end

    local described = describe_object(class_name, candidate)
    local address = tostring(described.object_address or "")
    if address == "" or seen_addresses[address] then
      return
    end

    seen_addresses[address] = true
    payload.objects[#payload.objects + 1] = described
  end

  local first_ok, first_result = pcall(function()
    return FindFirstOf(class_name)
  end)
  payload.find_first_success = first_ok and is_valid_object(first_result)
  payload.find_first_error = first_ok and nil or tostring(first_result)
  if payload.find_first_success then
    payload.sample = describe_object(class_name, first_result)
    record_candidate_object(first_result)
  end

  local all_ok, results = pcall(function()
    return FindAllOf(class_name)
  end)
  payload.success = all_ok
  if not all_ok then
    payload.error = tostring(results)
    return payload
  end

  if type(results) == "table" then
    payload.count = count_array_entries(results)
    if payload.sample == nil then
      for _, candidate in pairs(results) do
        if is_valid_object(candidate) then
          payload.sample = describe_object(class_name, candidate)
          break
        end
      end
    end

    for _, candidate in pairs(results) do
      if #payload.objects >= MAX_CANDIDATE_OBJECT_RECORDS then
        break
      end
      record_candidate_object(candidate)
    end
  end

  return payload
end

local function build_focus_surface(candidate_results, ordered_classes)
  local by_name = {}
  for _, result in ipairs(candidate_results or {}) do
    by_name[result.class_name] = result
  end

  local surface = {}
  for _, class_name in ipairs(ordered_classes or {}) do
    local result = by_name[class_name]
    if result then
      surface[#surface + 1] = {
        class_name = class_name,
        count = result.count or 0,
        find_first_success = result.find_first_success == true,
        sample = result.sample and result.sample.object_name or nil,
      }
    end
  end
  return surface
end

local function push_recent_transition(entry)
  state.recent_transitions[#state.recent_transitions + 1] = entry
  while #state.recent_transitions > MAX_RECENT_TRANSITIONS do
    table.remove(state.recent_transitions, 1)
  end
end

local function record_candidate_transitions(candidate_results)
  local next_state = {}
  local transitions = {}
  local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

  for _, result in ipairs(candidate_results or {}) do
    local class_name = tostring(result.class_name or "")
    local current_sample = result.sample and (result.sample.object_name or result.sample.object_short_name) or nil
    local current_state = {
      count = result.count or 0,
      sample = current_sample,
    }
    next_state[class_name] = current_state

    local previous = state.candidate_state[class_name]
    local previous_count = previous and previous.count or 0
    local previous_sample = previous and previous.sample or nil
    local count_changed = previous == nil or previous_count ~= current_state.count
    local sample_changed = previous ~= nil and previous_sample ~= current_state.sample and current_state.count > 0

    local should_record_initial_zero = previous == nil and current_state.count == 0 and current_state.sample == nil
    if (count_changed or sample_changed) and not should_record_initial_zero then
      local entry = {
        kind = "candidate_transition",
        timestamp = timestamp,
        class_name = class_name,
        previous_count = previous_count,
        current_count = current_state.count,
        previous_sample = previous_sample,
        current_sample = current_state.sample,
      }
      transitions[#transitions + 1] = entry
      push_recent_transition(entry)
      append_history_record(entry)
      trace(
        "candidate transition "
          .. class_name
          .. " count="
          .. tostring(previous_count)
          .. "->"
          .. tostring(current_state.count)
          .. " sample="
          .. tostring(current_state.sample or "nil")
      )
    end
  end

  state.candidate_state = next_state
  return transitions
end

local function find_first_live_object(class_name)
  local ok, result = pcall(function()
    return FindFirstOf(class_name)
  end)
  if ok and is_valid_object(result) then
    return result
  end
  return nil
end

local function attach_direct_member_probe(payload, object, function_name)
  local raw_result = nil
  local direct_lookup_ok, direct_member = pcall(function()
    return object[function_name]
  end)
  payload.direct_member_lookup_ok = direct_lookup_ok
  payload.direct_member_lua_type = direct_lookup_ok and type(direct_member) or nil
  if not direct_lookup_ok then
    payload.direct_method_lookup_error = truncate_text(direct_member, 240)
    return raw_result
  end

  if direct_member == nil then
    payload.direct_method_available = false
    return raw_result
  end

  payload.direct_member = render_native_call_result(direct_member)
  if is_valid_object(direct_member) then
    payload.direct_function_object = describe_object("direct_function", direct_member)
    payload.direct_method_available = true
    local direct_ok, direct_result = pcall(function()
      return object:CallFunction(direct_member)
    end)
    payload.direct_call_ok = direct_ok
    if direct_ok then
      raw_result = direct_result
      payload.direct_result = render_native_call_result(direct_result)
    else
      payload.direct_error = truncate_text(direct_result, 240)
    end
  elseif type(direct_member) == "function" then
    payload.direct_method_available = true
    local direct_ok, direct_result, direct_error = safe_method_call(object, function_name)
    payload.direct_call_ok = direct_ok
    if direct_ok then
      raw_result = direct_result
      payload.direct_result = render_native_call_result(direct_result)
    else
      payload.direct_error = truncate_text(direct_error, 240)
    end
  else
    payload.direct_method_available = false
  end

  return raw_result
end

local function attach_resolved_function_probe(payload, object, function_name)
  local raw_result = nil
  local resolved_func, resolved_func_error = find_named_function_hit(object, function_name)
  if is_valid_object(resolved_func) then
    payload.call_function_available = true
    payload.resolved_function = describe_object("resolved_function", resolved_func)

    local call_function_ok, call_function_result = pcall(function()
      return object:CallFunction(resolved_func)
    end)
    payload.call_function_ok = call_function_ok
    if call_function_ok then
      raw_result = call_function_result
      payload.call_function_result = render_native_call_result(call_function_result)
    else
      payload.call_function_error = truncate_text(call_function_result, 240)
    end
  else
    payload.call_function_available = false
    payload.resolved_function_error = truncate_text(resolved_func_error, 240)
  end

  return raw_result
end

local function probe_grid_handle_surface(value, source_label)
  if value == nil then
    return nil
  end

  local payload = {
    source = source_label,
    handle = render_property_probe_value(value),
    handle_address = get_object_address_string(value),
  }

  local wrapper_type_ok, wrapper_type = call_value_method(value, "type")
  if wrapper_type_ok and type(wrapper_type) == "string" and wrapper_type ~= "" then
    payload.ue4ss_type = wrapper_type
  end

  local is_valid_ok, is_valid_value, is_valid_error = safe_method_call(value, "IsValid")
  payload.is_valid_call = {
    ok = is_valid_ok,
  }
  if is_valid_ok then
    payload.is_valid_call.value = tostring(is_valid_value)
  else
    payload.is_valid_call.error = truncate_text(is_valid_error, 160)
  end

  local full_name_ok, full_name_value, full_name_error = safe_method_call(value, "GetFullName")
  payload.full_name_call = {
    ok = full_name_ok,
  }
  if full_name_ok then
    payload.full_name_call.value = truncate_text(value_to_string(full_name_value), 160)
  else
    payload.full_name_call.error = truncate_text(full_name_error, 160)
  end

  local property_results = {}
  for _, property_name in ipairs(GRID_HANDLE_PROPERTY_NAMES) do
    local property_ok, property_value = pcall(function()
      return value:GetPropertyValue(property_name)
    end)
    local entry = {
      property_name = property_name,
      ok = property_ok,
    }
    if property_ok then
      entry.value = render_native_call_result(property_value)
    else
      entry.error = truncate_text(property_value, 160)
    end
    property_results[#property_results + 1] = entry
  end
  payload.properties = property_results

  local function_results = {}
  if type(OmeggaCallFunctionByNameWithArguments) == "function" then
    for _, function_name in ipairs(GRID_HANDLE_FUNCTION_NAMES) do
      local helper_ok, did_succeed, output_or_error = pcall(
        OmeggaCallFunctionByNameWithArguments,
        value,
        function_name,
        value
      )
      local entry = {
        function_name = function_name,
        helper_ok = helper_ok,
      }
      if helper_ok then
        entry.success = did_succeed ~= false
        entry.output = truncate_text(value_to_string(output_or_error), 160)
        if entry.output == "" then
          entry.output = nil
        end
        if did_succeed == false then
          entry.reason = entry.output or "native call returned false"
        end
      else
        entry.reason = truncate_text(tostring(output_or_error), 160)
      end
      function_results[#function_results + 1] = entry
    end
  end
  payload.functions = function_results

  local handle_kind = type(payload.handle) == "table" and payload.handle.kind or type(value)
  local handle_wrapper_kind = type(payload.handle) == "table"
      and tostring(payload.handle.wrapper_kind or payload.handle.ue4ss_type or payload.ue4ss_type or "")
    or tostring(payload.ue4ss_type or "")
  local invalid_handle = payload.is_valid_call
      and payload.is_valid_call.ok == true
      and string.lower(tostring(payload.is_valid_call.value or "")) == "false"
  local empty_full_name = payload.full_name_call
      and payload.full_name_call.ok == true
      and tostring(payload.full_name_call.value or "") == ""
  local placeholder_property_count = 0
  for _, entry in ipairs(property_results) do
    local rendered = entry.value
    if entry.ok and type(rendered) == "table" and rendered.kind == "userdata" then
      local rendered_wrapper = tostring(rendered.wrapper_kind or rendered.ue4ss_type or "")
      if rendered_wrapper == "UObject" then
        placeholder_property_count = placeholder_property_count + 1
      end
    end
  end

  payload.handle_kind = handle_kind
  payload.handle_wrapper_kind = handle_wrapper_kind
  payload.placeholder_property_count = placeholder_property_count
  payload.property_count = #property_results
  payload.decoded_handle_available = false

  if handle_kind == "object" and payload.is_valid_call and payload.is_valid_call.ok == true and tostring(payload.is_valid_call.value) == "true" then
    payload.handle_status = "decoded_object"
    payload.decoded_handle_available = true
  elseif handle_kind == "userdata"
      and handle_wrapper_kind == "UObject"
      and invalid_handle
      and empty_full_name
      and #property_results > 0
      and placeholder_property_count == #property_results then
    payload.handle_status = "placeholder_null_wrapper"
    payload.reason =
      "getter returned an invalid unnamed UObject wrapper whose sampled properties are all placeholder UObject handles"
  elseif invalid_handle and empty_full_name then
    payload.handle_status = "invalid_wrapper"
    payload.reason = "getter returned an invalid unnamed wrapper"
  else
    payload.handle_status = "opaque_handle"
  end

  return payload
end

local function run_native_call_probes()
  local probes = {}
  for _, target in ipairs(TARGET_NATIVE_CALLS) do
    local probe_key = tostring(target.class_name) .. ":" .. tostring(target.function_name)
    local object = find_first_live_object(target.class_name)
    local payload = {
      target_class_name = target.class_name,
      function_name = target.function_name,
      helper_available = type(OmeggaCallFunctionByNameWithArguments) == "function",
      object = describe_object(target.class_name, object),
    }

    if not payload.helper_available then
      payload.success = false
      payload.reason = "native helper unavailable"
    elseif not is_valid_object(object) then
      payload.success = false
      payload.reason = "target object unavailable"
    else
      local direct_raw_result = nil
      local call_function_raw_result = nil
      local helper_ok, did_succeed, output_or_error = pcall(
        OmeggaCallFunctionByNameWithArguments,
        object,
        target.function_name,
        object
      )
      payload.call_ok = helper_ok
      payload.success = helper_ok and did_succeed ~= false
      payload.output = truncate_text(value_to_string(output_or_error), 240)
      if payload.output == "" then
        payload.output = nil
      end
      if not helper_ok then
        payload.reason = truncate_text(output_or_error, 240)
      elseif did_succeed == false then
        payload.reason = payload.output or "native call returned false"
      end

      direct_raw_result = attach_direct_member_probe(payload, object, target.function_name)
      call_function_raw_result = attach_resolved_function_probe(payload, object, target.function_name)

      if payload.direct_call_ok == true or payload.call_function_ok == true then
        payload.success = true
        if payload.reason == "native call returned false" then
          payload.reason = nil
        end
      end

      if target.function_name == "GetBrickGrid" then
        if direct_raw_result ~= nil then
          payload.grid_handle_followup = probe_grid_handle_surface(direct_raw_result, "direct_result")
        elseif call_function_raw_result ~= nil then
          payload.grid_handle_followup = probe_grid_handle_surface(call_function_raw_result, "call_function_result")
        end
        if payload.grid_handle_followup ~= nil then
          payload.result_interpretation = payload.grid_handle_followup.handle_status
          payload.decoded_result_available = payload.grid_handle_followup.decoded_handle_available
        end
      end
    end

    local summary_key = json_encode({
      success = payload.success,
      output = payload.output,
      reason = payload.reason,
      direct_method_available = payload.direct_method_available,
      direct_member_lua_type = payload.direct_member_lua_type,
      direct_member = payload.direct_member,
      direct_call_ok = payload.direct_call_ok,
      direct_error = payload.direct_error,
      direct_result = payload.direct_result,
      call_function_available = payload.call_function_available,
      call_function_ok = payload.call_function_ok,
      call_function_error = payload.call_function_error,
      call_function_result = payload.call_function_result,
      resolved_function_error = payload.resolved_function_error,
      grid_handle_followup = payload.grid_handle_followup,
      result_interpretation = payload.result_interpretation,
      decoded_result_available = payload.decoded_result_available,
    })
    if state.native_call_state[probe_key] ~= summary_key then
      state.native_call_state[probe_key] = summary_key
      append_history_record({
        kind = "native_call_probe",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        target_class_name = payload.target_class_name,
        function_name = payload.function_name,
        success = payload.success,
        reason = payload.reason,
        output = payload.output,
        direct_method_available = payload.direct_method_available,
        direct_member_lua_type = payload.direct_member_lua_type,
        direct_member = payload.direct_member,
        direct_function_object = payload.direct_function_object,
        direct_call_ok = payload.direct_call_ok,
        direct_error = payload.direct_error,
        direct_result = payload.direct_result,
        call_function_available = payload.call_function_available,
        call_function_ok = payload.call_function_ok,
        call_function_error = payload.call_function_error,
        call_function_result = payload.call_function_result,
        resolved_function = payload.resolved_function,
        resolved_function_error = payload.resolved_function_error,
        grid_handle_followup = payload.grid_handle_followup,
        result_interpretation = payload.result_interpretation,
        decoded_result_available = payload.decoded_result_available,
        object_name = payload.object and payload.object.object_name or nil,
      })
      trace(
        "native call probe "
          .. tostring(payload.target_class_name)
          .. "->"
          .. tostring(payload.function_name)
          .. " success="
          .. tostring(payload.success)
          .. " detail="
          .. tostring(payload.output or payload.reason or "nil")
          .. " direct="
          .. tostring(
            payload.direct_call_ok and (payload.direct_result and payload.direct_result.kind or "nil")
              or payload.direct_error
              or payload.direct_method_available
          )
          .. " callfunc="
          .. tostring(
            payload.call_function_ok and (payload.call_function_result and payload.call_function_result.kind or "nil")
              or payload.call_function_error
              or payload.resolved_function_error
              or payload.call_function_available
          )
          .. " interpretation="
          .. tostring(payload.result_interpretation or "none")
      )
    end

    probes[#probes + 1] = payload
  end
  return probes
end

local function run_target_property_probes()
  local probes = {}

  for class_name, property_names in pairs(TARGET_CLASS_PROPERTY_MAP) do
    local object = find_first_live_object(class_name)
    if is_valid_object(object) then
      local values = {}
      for _, property_name in ipairs(property_names) do
        local reflection = describe_reflected_property(object, property_name)
        local ok, value = pcall(function()
          return object:GetPropertyValue(property_name)
        end)
        if ok and value ~= nil or reflection.available then
          local entry = {
            property_name = property_name,
            reflection = reflection,
          }
          if ok and value ~= nil then
            entry.value = render_property_probe_value(value)
          else
            entry.value = nil
            entry.value_missing = true
          end
          if not ok then
            entry.value_error = truncate_text(value, 160)
          end
          values[#values + 1] = entry
        end
      end

      table.sort(values, function(left, right)
        return tostring(left.property_name) < tostring(right.property_name)
      end)

      local payload = {
        class_name = class_name,
        object = describe_object(class_name, object),
        values = values,
      }

      local summary_key = json_encode(values)
      if state.property_probe_state[class_name] ~= summary_key then
        state.property_probe_state[class_name] = summary_key
        append_history_record({
          kind = "property_probe",
          timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          class_name = class_name,
          object_name = payload.object and payload.object.object_name or nil,
          values = values,
        })
        trace(
          "property probe "
            .. tostring(class_name)
            .. " values="
            .. tostring(#values)
        )
      end

      probes[#probes + 1] = payload
    end
  end

  table.sort(probes, function(left, right)
    return tostring(left.class_name) < tostring(right.class_name)
  end)

  return probes
end

local function run_surface_probes()
  local probes = {}

  for _, class_name in ipairs(SURFACE_SCAN_CLASSES) do
    local cached = state.surface_probe_state[class_name]
    if cached then
      probes[#probes + 1] = cached
    else
      local object = find_first_live_object(class_name)
      if is_valid_object(object) then
        local payload = perform_surface_probe(class_name, object)
        state.surface_probe_state[class_name] = payload
        append_history_record({
          kind = "surface_probe",
          timestamp = payload.scanned_at,
          class_name = class_name,
          success = payload.success,
          reason = payload.reason,
          object_name = payload.object and payload.object.object_name or nil,
          property_match_count = payload.property_scan and payload.property_scan.match_count or 0,
          function_match_count = payload.function_scan and payload.function_scan.match_count or 0,
          property_matches = payload.property_scan and payload.property_scan.matches or nil,
          function_matches = payload.function_scan and payload.function_scan.matches or nil,
        })
        trace(
          "surface probe "
            .. tostring(class_name)
            .. " success="
            .. tostring(payload.success)
            .. " properties="
            .. tostring(payload.property_scan and payload.property_scan.match_count or 0)
            .. " functions="
            .. tostring(payload.function_scan and payload.function_scan.match_count or 0)
        )
        probes[#probes + 1] = payload
      else
        probes[#probes + 1] = {
          class_name = class_name,
          pending = true,
          success = false,
          reason = "target object unavailable",
          keyword_list = SURFACE_SCAN_KEYWORDS,
          object = describe_object(class_name, object),
        }
      end
    end
  end

  table.sort(probes, function(left, right)
    return tostring(left.class_name) < tostring(right.class_name)
  end)

  return probes
end

local function build_observations(candidate_results)
  local counts = {}
  for _, result in ipairs(candidate_results) do
    counts[result.class_name] = result.count or 0
  end

  local observations = {}
  if (counts.BRWorldManager or 0) > 0 then
    observations[#observations + 1] = "BRWorldManager is live; native prefab/world-management surface exists in this runtime."
  end
  if (counts.BrickGridActor or 0) > 0 or (counts.BrickGridComponent or 0) > 0 then
    observations[#observations + 1] = "BrickGridActor and BrickGridComponent are live; runtime brick-grid state is reachable without commands."
  end
  if (counts.Tool_Selector_C or 0) == 0 and (counts.BrickBuildingTemplate or 0) == 0 then
    observations[#observations + 1] = "Selector/template objects are not live in headless startup alone; they likely require an active player selection flow."
  end
  if (counts.BrickGridDynamicActor or 0) == 0 and (counts.Entity_DynamicBrickGrid or 0) == 0 then
    observations[#observations + 1] = "Dynamic brick-grid entities are not present in this idle startup snapshot yet."
  end
  if (counts.BRBundleArchive or 0) > 0 and (counts.BrickGridDynamicActor or 0) > 0 then
    observations[#observations + 1] = "BRBundleArchive and BrickGridDynamicActor are both live; additive prefab/entity load surfaces are active for native probing."
  end
  observations[#observations + 1] = "Location filtering is not applied yet because native brick-by-brick export is still unresolved."
  return observations
end

local function extract_handle_address(rendered_value)
  if type(rendered_value) ~= "table" then
    return nil
  end

  if rendered_value.kind == "object" and type(rendered_value.object) == "table" then
    local address = tostring(rendered_value.object.object_address or "")
    if address == "" then
      return nil
    end
    return string.lower(address)
  end

  if rendered_value.kind == "userdata" then
    local value_text = tostring(rendered_value.value or "")
    local address = value_text:match("0x[0-9A-Fa-f]+") or value_text:match("(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)")
    if address == nil or address == "" then
      return nil
    end
    if not address:match("^0x") then
      address = "0x" .. address
    end
    return string.lower(address)
  end

  return nil
end

local function append_handle_index_entry(index, address, payload)
  if type(address) ~= "string" or address == "" then
    return
  end

  local normalized = string.lower(address)
  index[normalized] = index[normalized] or {}
  index[normalized][#index[normalized] + 1] = payload
end

local function build_property_handle_index(property_probes)
  local index = {}
  for _, probe in ipairs(property_probes or {}) do
    for _, entry in ipairs(probe.values or {}) do
      local address = extract_handle_address(entry.value)
      append_handle_index_entry(index, address, {
        source_kind = "property_value",
        class_name = probe.class_name,
        property_name = entry.property_name,
        object_name = probe.object and probe.object.object_name or nil,
      })
    end
  end
  return index
end

local function build_candidate_handle_index(candidate_results)
  local index = {}
  for _, result in ipairs(candidate_results or {}) do
    for _, candidate_object in ipairs(result.objects or {}) do
      append_handle_index_entry(index, candidate_object.object_address, {
        source_kind = "candidate_object",
        class_name = result.class_name,
        object_name = candidate_object.object_name,
        sample_kind = "find_all_object",
      })
    end
  end
  return index
end

local function build_native_probe_handle_index(native_call_probes)
  local index = {}
  for _, probe in ipairs(native_call_probes or {}) do
    local probe_key = tostring(probe.target_class_name or "?") .. ":" .. tostring(probe.function_name or "?")
    append_handle_index_entry(index, probe.object and probe.object.object_address or nil, {
      source_kind = "native_target_object",
      probe_key = probe_key,
      class_name = probe.target_class_name,
      function_name = probe.function_name,
      object_name = probe.object and probe.object.object_name or nil,
    })
    append_handle_index_entry(index, extract_handle_address(probe.direct_member), {
      source_kind = "native_direct_member",
      probe_key = probe_key,
      class_name = probe.target_class_name,
      function_name = probe.function_name,
      object_name = probe.object and probe.object.object_name or nil,
    })
    append_handle_index_entry(index, extract_handle_address(probe.direct_result), {
      source_kind = "native_direct_result",
      probe_key = probe_key,
      class_name = probe.target_class_name,
      function_name = probe.function_name,
      object_name = probe.object and probe.object.object_name or nil,
    })
    append_handle_index_entry(index, extract_handle_address(probe.call_function_result), {
      source_kind = "native_call_function_result",
      probe_key = probe_key,
      class_name = probe.target_class_name,
      function_name = probe.function_name,
      object_name = probe.object and probe.object.object_name or nil,
    })
  end
  return index
end

local function merge_handle_indexes(target, source)
  for address, entries in pairs(source or {}) do
    target[address] = target[address] or {}
    for _, entry in ipairs(entries) do
      target[address][#target[address] + 1] = entry
    end
  end
end

local function collect_handle_matches(handle_index, address, excluded_probe_key, excluded_source_kind)
  if type(address) ~= "string" or address == "" then
    return nil
  end

  local matches = {}
  for _, entry in ipairs(handle_index[string.lower(address)] or {}) do
    local same_probe = excluded_probe_key ~= nil and entry.probe_key == excluded_probe_key
    local same_source = excluded_source_kind ~= nil and entry.source_kind == excluded_source_kind
    if not (same_probe and same_source) then
      matches[#matches + 1] = entry
    end
  end

  if #matches == 0 then
    return nil
  end

  return matches
end

local function collect_property_handle_matches(handle_index, address, class_name, property_name)
  if type(address) ~= "string" or address == "" then
    return nil
  end

  local matches = {}
  for _, entry in ipairs(handle_index[string.lower(address)] or {}) do
    local same_property = entry.source_kind == "property_value"
      and tostring(entry.class_name or "") == tostring(class_name or "")
      and tostring(entry.property_name or "") == tostring(property_name or "")
    if not same_property then
      matches[#matches + 1] = entry
    end
  end

  if #matches == 0 then
    return nil
  end

  return matches
end

local function correlate_property_probe_handles(property_probes, candidate_results, native_call_probes)
  local handle_index = {}
  merge_handle_indexes(handle_index, build_property_handle_index(property_probes))
  merge_handle_indexes(handle_index, build_candidate_handle_index(candidate_results))
  merge_handle_indexes(handle_index, build_native_probe_handle_index(native_call_probes))

  for _, probe in ipairs(property_probes or {}) do
    for _, entry in ipairs(probe.values or {}) do
      local value_address = extract_handle_address(entry.value)
      if value_address then
        entry.value_address = value_address
        entry.value_matches = collect_property_handle_matches(
          handle_index,
          value_address,
          probe.class_name,
          entry.property_name
        )
      end
    end
  end
end

local function correlate_native_call_handles(native_call_probes, property_probes, candidate_results)
  local handle_index = {}
  merge_handle_indexes(handle_index, build_property_handle_index(property_probes))
  merge_handle_indexes(handle_index, build_candidate_handle_index(candidate_results))
  merge_handle_indexes(handle_index, build_native_probe_handle_index(native_call_probes))
  for _, probe in ipairs(native_call_probes or {}) do
    local probe_key = tostring(probe.target_class_name or "?") .. ":" .. tostring(probe.function_name or "?")
    local direct_result_address = extract_handle_address(probe.direct_result)
    if direct_result_address then
      probe.direct_result_address = direct_result_address
      probe.direct_result_matches = collect_handle_matches(
        handle_index,
        direct_result_address,
        probe_key,
        "native_direct_result"
      )
    end

    local direct_member_address = extract_handle_address(probe.direct_member)
    if direct_member_address then
      probe.direct_member_address = direct_member_address
      probe.direct_member_matches = collect_handle_matches(
        handle_index,
        direct_member_address,
        probe_key,
        "native_direct_member"
      )
    end

    local call_function_result_address = extract_handle_address(probe.call_function_result)
    if call_function_result_address then
      probe.call_function_result_address = call_function_result_address
      probe.call_function_result_matches = collect_handle_matches(
        handle_index,
        call_function_result_address,
        probe_key,
        "native_call_function_result"
      )
    end
  end
end

local function replay_capture_has_count_trigger(transitions)
  local triggers = {}
  for _, entry in ipairs(transitions or {}) do
    local class_name = tostring(entry.class_name or "")
    local previous_count = tonumber(entry.previous_count or 0) or 0
    local current_count = tonumber(entry.current_count or 0) or 0
    if REPLAY_CAPTURE_TRIGGER_CLASSES[class_name] and previous_count ~= current_count then
      triggers[#triggers + 1] = {
        class_name = class_name,
        previous_count = previous_count,
        current_count = current_count,
        previous_sample = entry.previous_sample,
        current_sample = entry.current_sample,
        kind = "count_transition",
      }
    end
  end
  return triggers
end

local function replay_capture_has_property_trigger(property_probes)
  local triggers = {}
  local next_state = {}

  for _, probe in ipairs(property_probes or {}) do
    local class_name = tostring(probe.class_name or "")
    local watched_properties = REPLAY_CAPTURE_TRIGGER_PROPERTIES[class_name]
    if watched_properties then
      for _, entry in ipairs(probe.values or {}) do
        local property_name = tostring(entry.property_name or "")
        if watched_properties[property_name] then
          local property_key = class_name .. "." .. property_name
          local current_value_address = normalize_replay_handle(entry.value_address)
            or tostring(entry.value_address or "")
          if current_value_address ~= "" then
            next_state[property_key] = current_value_address

            local previous_value_address = tostring(state.replay_property_trigger_state[property_key] or "")
            if previous_value_address ~= "" and previous_value_address ~= current_value_address then
              triggers[#triggers + 1] = {
                kind = "property_transition",
                class_name = class_name,
                property_name = property_name,
                previous_value_address = previous_value_address,
                current_value_address = current_value_address,
              }
            end
          end
        end
      end
    end
  end

  state.replay_property_trigger_state = next_state
  return triggers
end

local function summarize_handle_match(entry)
  local payload = {
    source_kind = entry.source_kind,
    class_name = entry.class_name,
  }
  if entry.property_name ~= nil then
    payload.property_name = entry.property_name
  end
  if entry.function_name ~= nil then
    payload.function_name = entry.function_name
  end
  if entry.probe_key ~= nil then
    payload.probe_key = entry.probe_key
  end
  if entry.object_name ~= nil then
    payload.object_name = truncate_text(entry.object_name, 120)
  end
  if entry.sample_kind ~= nil then
    payload.sample_kind = entry.sample_kind
  end
  return payload
end

local function summarize_property_capture_entry(entry)
  local rendered = entry.value or {}
  local payload = {
    property_name = entry.property_name,
    kind = rendered.kind,
    wrapper_kind = rendered.wrapper_kind or rendered.ue4ss_type,
    value_address = entry.value_address,
    value = rendered.value,
  }

  if entry.reflection and entry.reflection.available == true then
    payload.reflection = {
      reflected_name = entry.reflection.reflected_name,
      property_class = entry.reflection.property_class,
      object_property_class = entry.reflection.object_property_class,
      struct_property_name = entry.reflection.struct_property_name,
    }
  end

  if entry.value_matches and #entry.value_matches > 0 then
    local matches = {}
    for index, match in ipairs(entry.value_matches) do
      if index > 4 then
        break
      end
      matches[#matches + 1] = summarize_handle_match(match)
    end
    payload.match_count = #entry.value_matches
    payload.matches = matches
  end

  return payload
end

local function summarize_native_probe_for_capture(probe)
  local payload = {
    target_class_name = probe.target_class_name,
    function_name = probe.function_name,
    success = probe.success,
    reason = probe.reason,
    result_interpretation = probe.result_interpretation,
  }

  if probe.direct_result_address ~= nil then
    payload.direct_result_address = probe.direct_result_address
  end
  if probe.call_function_result_address ~= nil then
    payload.call_function_result_address = probe.call_function_result_address
  end

  if probe.direct_result_matches and #probe.direct_result_matches > 0 then
    local matches = {}
    for index, match in ipairs(probe.direct_result_matches) do
      if index > 4 then
        break
      end
      matches[#matches + 1] = summarize_handle_match(match)
    end
    payload.direct_result_matches = matches
  end

  if probe.call_function_result_matches and #probe.call_function_result_matches > 0 then
    local matches = {}
    for index, match in ipairs(probe.call_function_result_matches) do
      if index > 4 then
        break
      end
      matches[#matches + 1] = summarize_handle_match(match)
    end
    payload.call_function_result_matches = matches
  end

  return payload
end

local function maybe_capture_replay_surface(property_probes, native_call_probes, transitions)
  local count_triggers = replay_capture_has_count_trigger(transitions)
  local property_triggers = replay_capture_has_property_trigger(property_probes)
  local triggers = {}
  local capture_gate = nil
  local burst_budget_after_capture = tonumber(state.replay_burst_remaining or 0) or 0

  if #count_triggers > 0 then
    state.replay_burst_remaining = REPLAY_BURST_CAPTURE_BUDGET
    capture_gate = "count_transition"
    burst_budget_after_capture = state.replay_burst_remaining
  elseif (tonumber(state.replay_burst_remaining or 0) or 0) > 0 and #property_triggers > 0 then
    state.replay_burst_remaining = math.max((tonumber(state.replay_burst_remaining or 0) or 0) - 1, 0)
    capture_gate = "count_burst"
    burst_budget_after_capture = state.replay_burst_remaining
  elseif state.replay_property_only_armed and #property_triggers >= REPLAY_PROPERTY_ONLY_MIN_TRIGGER_COUNT then
    state.replay_property_only_armed = false
    capture_gate = "property_preburst"
    burst_budget_after_capture = tonumber(state.replay_burst_remaining or 0) or 0
  end

  if not capture_gate then
    return state.latest_replay_surface_capture
  end

  for _, trigger in ipairs(count_triggers) do
    triggers[#triggers + 1] = trigger
  end
  for _, trigger in ipairs(property_triggers) do
    triggers[#triggers + 1] = trigger
  end

  if #triggers == 0 then
    return state.latest_replay_surface_capture
  end

  local capture = {
    kind = "replay_surface_capture",
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    capture_gate = capture_gate,
    burst_budget_after_capture = burst_budget_after_capture,
    trigger_transitions = count_triggers,
    property_triggers = property_triggers,
    classes = {},
    native_probes = {},
  }

  for _, probe in ipairs(property_probes or {}) do
    if REPLAY_CAPTURE_CLASSES[tostring(probe.class_name or "")] then
      local class_entry = {
        class_name = probe.class_name,
        object = probe.object,
        properties = {},
      }
      for _, entry in ipairs(probe.values or {}) do
        class_entry.properties[#class_entry.properties + 1] = summarize_property_capture_entry(entry)
      end
      capture.classes[#capture.classes + 1] = class_entry
    end
  end

  for _, probe in ipairs(native_call_probes or {}) do
    local class_name = tostring(probe.target_class_name or "")
    if REPLAY_CAPTURE_CLASSES[class_name] then
      capture.native_probes[#capture.native_probes + 1] = summarize_native_probe_for_capture(probe)
    end
  end

  table.sort(capture.classes, function(left, right)
    return tostring(left.class_name) < tostring(right.class_name)
  end)
  table.sort(capture.native_probes, function(left, right)
    local left_key = tostring(left.target_class_name or "") .. ":" .. tostring(left.function_name or "")
    local right_key = tostring(right.target_class_name or "") .. ":" .. tostring(right.function_name or "")
    return left_key < right_key
  end)

  state.replay_capture_sequence = (state.replay_capture_sequence or 0) + 1
  capture.capture_index = state.replay_capture_sequence
  capture.capture_phase = build_replay_capture_phase(triggers)
  state.latest_replay_capture_phase = capture.capture_phase

  local alias_edges, alias_handles, alias_summary = build_replay_alias_graph(property_probes)
  capture.alias_summary = alias_summary
  capture.alias_handles = alias_handles
  capture.alias_edges = alias_edges
  capture.repeated_alias_edges = record_replay_alias_edges(alias_edges)

  local signature = json_encode(capture)
  if state.replay_surface_capture_signature ~= signature then
    state.replay_surface_capture_signature = signature
    state.latest_replay_surface_capture = capture
    append_history_record(capture)

    local trigger_fragments = {}
    for _, trigger in ipairs(triggers) do
      if tostring(trigger.kind or "") == "property_transition" then
        trigger_fragments[#trigger_fragments + 1] = tostring(trigger.class_name)
          .. "."
          .. tostring(trigger.property_name)
          .. "="
          .. tostring(trigger.previous_value_address)
          .. "->"
          .. tostring(trigger.current_value_address)
      else
        trigger_fragments[#trigger_fragments + 1] = tostring(trigger.class_name)
          .. "="
          .. tostring(trigger.previous_count)
          .. "->"
          .. tostring(trigger.current_count)
      end
    end
    trace(
      "replay surface capture gate="
        .. tostring(capture.capture_gate or "count_transition")
        .. " phase="
        .. tostring(capture.capture_phase and capture.capture_phase.name or "count_transition")
        .. " "
        .. table.concat(trigger_fragments, ", ")
    )
  end

  return state.latest_replay_surface_capture
end

replay_count_keys = function(map)
  local count = 0
  for _ in pairs(map or {}) do
    count = count + 1
  end
  return count
end

normalize_replay_handle = function(raw_value)
  if type(raw_value) ~= "string" then
    return nil
  end

  local hex = raw_value:match("UObject:%s*([0-9A-Fa-f]+)")
    or raw_value:match("0[xX]([0-9A-Fa-f]+)")
    or raw_value:match("@0[xX]?([0-9A-Fa-f]+)")
  if not hex then
    return nil
  end

  return "0x" .. string.upper(hex)
end

replay_object_identity = function(object_name)
  local normalized = normalize_replay_handle(object_name)
  if normalized then
    return normalized
  end

  return tostring(object_name or "unknown_object"):gsub("%s+", "")
end

replay_alias_member_sort_key = function(member)
  return tostring(member.property_path or "") .. "@" .. tostring(member.object_id or "")
end

canonical_replay_alias_key = function(left_path, right_path)
  local left_value = tostring(left_path or "")
  local right_value = tostring(right_path or "")
  if left_value > right_value then
    left_value, right_value = right_value, left_value
  end
  return left_value .. " <-> " .. right_value
end

build_replay_capture_phase = function(triggers)
  local phase_name = "count_transition"
  local trigger_fragments = {}

  for _, trigger in ipairs(triggers or {}) do
    local class_name = tostring(trigger.class_name or "")
    if tostring(trigger.kind or "") == "property_transition" then
      local property_name = tostring(trigger.property_name or "")
      trigger_fragments[#trigger_fragments + 1] = class_name
        .. "."
        .. property_name
        .. "="
        .. tostring(trigger.previous_value_address)
        .. "->"
        .. tostring(trigger.current_value_address)

      if phase_name ~= "grid_component_window"
        and phase_name ~= "dynamic_grid_window"
        and phase_name ~= "grid_expansion_window"
        and class_name == "BRBundleTransferComponent"
      then
        phase_name = "transfer_window"
      elseif phase_name ~= "transfer_window"
        and phase_name ~= "grid_component_window"
        and phase_name ~= "dynamic_grid_window"
        and phase_name ~= "grid_expansion_window"
        and class_name == "BRWorldManager"
      then
        phase_name = "world_manager_bundle_window"
      elseif phase_name ~= "transfer_window"
        and phase_name ~= "world_manager_bundle_window"
        and phase_name ~= "grid_component_window"
        and phase_name ~= "dynamic_grid_window"
        and phase_name ~= "grid_expansion_window"
        and class_name == "BRBundleArchive"
      then
        phase_name = "bundle_archive_window"
      end
    else
      local previous_count = tonumber(trigger.previous_count or 0) or 0
      local current_count = tonumber(trigger.current_count or 0) or 0

      trigger_fragments[#trigger_fragments + 1] = class_name
        .. "="
        .. tostring(previous_count)
        .. "->"
        .. tostring(current_count)

      if class_name == "BrickGridComponent" and current_count > previous_count then
        phase_name = "grid_component_window"
      elseif phase_name ~= "grid_component_window" and class_name == "BRBundleTransferComponent" and current_count > 0 then
        phase_name = "transfer_window"
      elseif phase_name ~= "transfer_window" and phase_name ~= "grid_component_window" and class_name == "BRBundleArchive" and current_count > 0 then
        phase_name = "bundle_archive_window"
      elseif phase_name == "count_transition" and class_name == "BrickGridDynamicActor" and current_count > previous_count then
        phase_name = "dynamic_grid_window"
      elseif phase_name == "count_transition" and class_name == "BrickGridActor" and current_count > previous_count then
        phase_name = "grid_expansion_window"
      end
    end
  end

  return {
    name = phase_name,
    triggers = trigger_fragments,
  }
end

build_replay_alias_graph = function(property_probes)
  local handle_groups = {}
  local alias_edges = {}
  local alias_handles = {}
  local seen_edge_keys = {}

  for _, probe in ipairs(property_probes or {}) do
    local class_name = tostring(probe.class_name or "")
    local object_id = replay_object_identity(probe.object_name)

    for _, property_value in ipairs(probe.values or {}) do
      local handle = normalize_replay_handle(property_value and property_value.value and property_value.value.value)
        or normalize_replay_handle(property_value and property_value.value and property_value.value.object_address)
        or normalize_replay_handle(
          property_value and property_value.value and property_value.value.object and property_value.value.object.object_address
        )

      if handle then
        local property_name = tostring(property_value.property_name or "unknown_property")
        local group = handle_groups[handle]
        if not group then
          group = {}
          handle_groups[handle] = group
        end

        group[#group + 1] = {
          class_name = class_name,
          object_id = object_id,
          object_name = tostring(probe.object_name or ""),
          property_name = property_name,
          property_path = class_name .. "." .. property_name,
        }
      end
    end
  end

  for handle, members in pairs(handle_groups) do
    if #members > 1 then
      table.sort(members, function(left, right)
        return replay_alias_member_sort_key(left) < replay_alias_member_sort_key(right)
      end)

      if #alias_handles < MAX_CAPTURE_ALIAS_HANDLES then
        alias_handles[#alias_handles + 1] = {
          handle = handle,
          members = members,
        }
      end

      for left_index = 1, #members - 1 do
        for right_index = left_index + 1, #members do
          local left_member = members[left_index]
          local right_member = members[right_index]
          local edge_key = canonical_replay_alias_key(left_member.property_path, right_member.property_path)

          if not seen_edge_keys[edge_key] then
            seen_edge_keys[edge_key] = true

            if #alias_edges < MAX_CAPTURE_ALIAS_EDGES then
              alias_edges[#alias_edges + 1] = {
                key = edge_key,
                handle = handle,
                left = left_member.property_path,
                right = right_member.property_path,
                left_object = left_member.object_id,
                right_object = right_member.object_id,
                left_class = left_member.class_name,
                right_class = right_member.class_name,
                left_property = left_member.property_name,
                right_property = right_member.property_name,
              }
            end
          end
        end
      end
    end
  end

  table.sort(alias_handles, function(left, right)
    return tostring(left.handle or "") < tostring(right.handle or "")
  end)
  table.sort(alias_edges, function(left, right)
    return tostring(left.key or "") < tostring(right.key or "")
  end)

  return alias_edges, alias_handles, {
    observed_handle_count = replay_count_keys(handle_groups),
    aliased_handle_count = #alias_handles,
    alias_edge_count = #alias_edges,
  }
end

record_replay_alias_edges = function(alias_edges)
  state.replay_alias_edge_counts = state.replay_alias_edge_counts or {}

  local repeated_edges = {}
  local seen_this_capture = {}

  for _, alias_edge in ipairs(alias_edges or {}) do
    local edge_key = tostring(alias_edge.key or "")
    if edge_key ~= "" and not seen_this_capture[edge_key] then
      seen_this_capture[edge_key] = true

      local seen_count = (state.replay_alias_edge_counts[edge_key] or 0) + 1
      state.replay_alias_edge_counts[edge_key] = seen_count

      if seen_count >= REPEATED_ALIAS_MIN_COUNT then
        repeated_edges[#repeated_edges + 1] = {
          key = edge_key,
          left = alias_edge.left,
          right = alias_edge.right,
          seen_count = seen_count,
          latest_handle = alias_edge.handle,
        }
      end
    end
  end

  table.sort(repeated_edges, function(left, right)
    local left_count = tonumber(left.seen_count or 0) or 0
    local right_count = tonumber(right.seen_count or 0) or 0
    if left_count ~= right_count then
      return left_count > right_count
    end
    return tostring(left.key or "") < tostring(right.key or "")
  end)

  return repeated_edges
end

build_replay_alias_history_snapshot = function()
  local repeated_edges = {}
  local unique_edge_count = 0

  for edge_key, seen_count in pairs(state.replay_alias_edge_counts or {}) do
    unique_edge_count = unique_edge_count + 1
    if seen_count >= REPEATED_ALIAS_MIN_COUNT then
      local left, right = tostring(edge_key):match("^(.-) <-> (.+)$")
      repeated_edges[#repeated_edges + 1] = {
        key = edge_key,
        left = left,
        right = right,
        seen_count = seen_count,
      }
    end
  end

  table.sort(repeated_edges, function(left, right)
    local left_count = tonumber(left.seen_count or 0) or 0
    local right_count = tonumber(right.seen_count or 0) or 0
    if left_count ~= right_count then
      return left_count > right_count
    end
    return tostring(left.key or "") < tostring(right.key or "")
  end)

  local limited_repeated_edges = {}
  for index = 1, math.min(#repeated_edges, MAX_CAPTURE_ALIAS_EDGES) do
    limited_repeated_edges[#limited_repeated_edges + 1] = repeated_edges[index]
  end

  return {
    capture_count = state.replay_capture_sequence or 0,
    unique_edge_count = unique_edge_count,
    repeated_edge_count = #repeated_edges,
    repeated_edges = limited_repeated_edges,
    last_capture_phase = state.latest_replay_capture_phase,
  }
end

local function build_snapshot()
  local context = build_context_snapshot()
  local candidate_results = {}
  local live_candidates = {}

  for _, class_name in ipairs(CANDIDATE_CLASSES) do
    local result = scan_candidate_class(class_name)
    candidate_results[#candidate_results + 1] = result
    if (result.count or 0) > 0 or result.find_first_success then
      live_candidates[#live_candidates + 1] = {
        class_name = class_name,
        count = result.count or 0,
        sample = result.sample and result.sample.object_name or nil,
      }
    end
  end

  local transitions = record_candidate_transitions(candidate_results)
  local native_call_probes = run_native_call_probes()
  local property_probes = run_target_property_probes()
  local surface_probes = run_surface_probes()
  correlate_native_call_handles(native_call_probes, property_probes, candidate_results)
  correlate_property_probe_handles(property_probes, candidate_results, native_call_probes)
  local latest_replay_surface_capture = maybe_capture_replay_surface(property_probes, native_call_probes, transitions)
  local player_surface = build_focus_surface(candidate_results, {
    "PlayerController",
    "BP_PlayerController_C",
    "BP_PlayerState_C",
    "BRCharacter",
  })
  local selection_surface = build_focus_surface(candidate_results, {
    "Tool_Selector_C",
    "BP_ToolPreviewActor_C",
    "BrickBuildingTemplate",
    "BrickGridPreviewActor",
    "BrickGridPreviewActor_C",
    "BrickGridDynamicActor",
    "Entity_DynamicBrickGrid",
  })
  local prefab_surface = build_focus_surface(candidate_results, {
    "BRWorldManager",
    "BRWorldSerializer",
    "BrickPrefabs",
    "BRBundleArchive",
    "BRPrefabCache",
    "BRPrefabCacheInMemoryPrefab",
    "BRPrefabHashAndMetadata",
    "BRPrefabDetachedPasteInfo",
    "BrickGridActor",
    "BrickGridComponent",
  })

  return {
    status = "ok",
    updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    source = "native-runtime-sampler",
    history_path = HISTORY_PATH,
    hook_count = state.initgamestate_hook_count,
    selected_hook_count = state.selected_initgamestate_hook_count,
    region = {
      center = vector_object(REGION_CENTER),
      extent = vector_object(REGION_EXTENT),
      filter_status = "not_applied_yet",
      filter_reason = "runtime brick enumeration by location still needs a native prefab/grid reader",
    },
    context = context,
    candidate_counts = candidate_results,
    live_candidates = live_candidates,
    recent_transitions = state.recent_transitions,
    cycle_transitions = transitions,
    player_surface = player_surface,
    selection_surface = selection_surface,
    prefab_surface = prefab_surface,
    target_function_leads = TARGET_FUNCTIONS,
    target_property_leads = TARGET_PROPERTIES,
    native_call_targets = TARGET_NATIVE_CALLS,
    surface_scan_classes = SURFACE_SCAN_CLASSES,
    surface_scan_keywords = SURFACE_SCAN_KEYWORDS,
    native_call_probes = native_call_probes,
    property_probes = property_probes,
    surface_probes = surface_probes,
    latest_replay_surface_capture = latest_replay_surface_capture,
    replay_alias_history = build_replay_alias_history_snapshot(),
    observations = build_observations(candidate_results),
  }
end

local function run_snapshot_cycle()
  if not state.ready then
    write_snapshot({
      status = "waiting_for_context",
      updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      source = "native-runtime-sampler",
      history_path = HISTORY_PATH,
      hook_count = state.initgamestate_hook_count,
      selected_hook_count = state.selected_initgamestate_hook_count,
      region = {
        center = vector_object(REGION_CENTER),
        extent = vector_object(REGION_EXTENT),
      },
      candidate_classes = CANDIDATE_CLASSES,
      native_call_targets = TARGET_NATIVE_CALLS,
      note = "waiting for the selected InitGameState hook before scanning native runtime objects",
    })
    return true
  end

  local ok, snapshot_or_error = pcall(build_snapshot)
  if not ok then
    trace("snapshot build failed: " .. tostring(snapshot_or_error))
    write_snapshot({
      status = "error",
      updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      source = "native-runtime-sampler",
      history_path = HISTORY_PATH,
      error = tostring(snapshot_or_error),
      candidate_classes = CANDIDATE_CLASSES,
      native_call_targets = TARGET_NATIVE_CALLS,
    })
    return true
  end

  write_snapshot(snapshot_or_error)

  if not state.ready_logged then
    state.ready_logged = true
    trace("native sampler ready; snapshot_path=" .. tostring(SNAPSHOT_PATH))
  end

  return true
end

local function start_poll_loop()
  if state.loop_started then
    return true
  end
  state.loop_started = true

  local callback_key = "world_state_native_sampler_poll"
  local function loop_callback()
    return retain_callback(callback_key, function()
      local ok, keep_running_or_error = pcall(run_snapshot_cycle)
      if not ok then
        trace("native sampler poller crashed: " .. tostring(keep_running_or_error))
        return false
      end
      return keep_running_or_error == false
    end)
  end

  if type(LoopInGameThreadAfterFrames) == "function" then
    local frames = math.max(1, math.floor(INTERVAL_MS / 100))
    LoopInGameThreadAfterFrames(frames, loop_callback())
    trace("started native sampler via LoopInGameThreadAfterFrames interval_ms=" .. tostring(INTERVAL_MS))
    return true
  end

  if type(LoopInGameThreadWithDelay) == "function" then
    LoopInGameThreadWithDelay(INTERVAL_MS, loop_callback())
    trace("started native sampler via LoopInGameThreadWithDelay interval_ms=" .. tostring(INTERVAL_MS))
    return true
  end

  if type(LoopAsync) == "function" then
    LoopAsync(INTERVAL_MS, loop_callback())
    trace("started native sampler via LoopAsync interval_ms=" .. tostring(INTERVAL_MS))
    return true
  end

  trace("failed to start native sampler: no supported repeating scheduler")
  return false
end

ensure_parent(TRACE_PATH)
trace(
  "script loaded; trace_path="
    .. tostring(TRACE_PATH)
    .. " snapshot_path="
    .. tostring(SNAPSHOT_PATH)
    .. " history_path="
    .. tostring(HISTORY_PATH)
    .. " interval_ms="
    .. tostring(INTERVAL_MS)
)

write_snapshot({
  status = "starting",
  updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  source = "native-runtime-sampler",
  history_path = HISTORY_PATH,
  region = {
    center = vector_object(REGION_CENTER),
    extent = vector_object(REGION_EXTENT),
  },
  candidate_classes = CANDIDATE_CLASSES,
  target_function_leads = TARGET_FUNCTIONS,
  target_property_leads = TARGET_PROPERTIES,
  native_call_targets = TARGET_NATIVE_CALLS,
  note = "command-driven SaveRegion sampling is disabled; this sampler only records native runtime discovery state",
})

start_poll_loop()

RegisterInitGameStatePostHook(function(Context)
  state.initgamestate_hook_count = state.initgamestate_hook_count + 1
  local hook_count = state.initgamestate_hook_count

  if hook_count >= 2 then
    local captured = capture_context_objects(Context)
    state.latest_hook_context = captured.hook_context
    state.latest_context_resolver = captured.resolver
    state.cached_world = captured.world
    state.cached_persistent_level = captured.persistent_level
    state.cached_game_mode = captured.game_mode
    state.cached_game_state = captured.game_state
    state.cached_game_session = captured.game_session
    state.cached_game_instance = captured.game_instance
  end

  trace(
    "RegisterInitGameStatePostHook fired hook_count="
      .. tostring(hook_count)
      .. " selected="
      .. tostring(hook_count >= 2)
      .. " context="
      .. tostring(object_label(resolve_object(Context)))
  )

  if hook_count >= 2 and state.selected_initgamestate_hook_count == nil then
    state.selected_initgamestate_hook_count = hook_count
    schedule_probe("native_sampler_initial_snapshot", START_DELAY_MS, function()
      state.ready = true
      run_snapshot_cycle()
    end)
  end
end)
