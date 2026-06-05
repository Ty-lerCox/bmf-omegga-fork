local OUT_PATH = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_CONTEXT_OUT") or "__WORLD_EXPORT_CONTEXT_OUT__"
local PROBE_DELAY_MS = tonumber(os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_DELAY_MS") or "2500") or 2500
local KEYWORDS_RAW = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_KEYWORDS")
  or "brick,grid,owner,entity,component,prefab,region,selection,template,bundle,serializer,manager,world,paste"
local FUNCTION_HINTS_RAW = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_FUNCTION_HINTS")
  or "brick,grid,owner,entity,component,prefab,region,selection,template,bundle,serializer,manager,chunk,wire,save,load,clear,export,paste,place,apply,upload"
local PROPERTY_NAMES_RAW = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_PROPERTY_NAMES")
  or "NumBricks,BrickCount,NumBricksSaved,NumComponents,ComponentCount,NumWires,WireCount,ChunkOffsets,ChunkSizes,BricksInChunk,OwnerIndices,OriginalOwnerIndices,RelativePositions,Orientations,MaterialIndices,ColorsAndAlphas,CollisionFlags_Player,CollisionFlags_Weapon,CollisionFlags_Interaction,CollisionFlags_Physics,VisibilityFlags,Grid,GridIndex,GridCellSize,EntityType,EntityTypes,ComponentTypes,PlayerArray,Players,PendingWorldBundle,CachedWorldBundle,SavedWorldBundle,CurrentWorldBundle,WorldSerializer,CurrentTemplate,CurrentSelectionBoxGrid,PrefabInfo,PrefabMetadata,PrefabCounts"
local FINDALL_CLASSES_RAW = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_FINDALL_CLASSES")
  or "GameModeBase,GameStateBase,GameSession,PlayerController,BP_PlayerController_C,BP_PlayerState_C,Tool_Selector_C,BP_ToolPreviewActor_C,BrickGrid,BrickGridActor,BrickGridComponent,BrickGridDynamicActor,Entity_DynamicBrickGrid,BrickBuildingTemplate,BrickGridPreviewActor,BrickGridPreviewActor_C,BP_BrickGrid_C,BRWorldManager,BRWorldSerializer,BrickPrefabs,BRBundleArchive,BRChatCommandWorldSubsystem,ChatCommandWorldSubsystem,BP_ChatCommandWorldSubsystem_C,BRBundleTransferComponent,BRGizmoManagerComponent,BRCharacter"
local ALLOW_UNSAFE_REFLECTION = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_UNSAFE_REFLECTION") == "1"
local ALLOW_UNSAFE_PROPERTY_PROBES = os.getenv("OMEGGA_UE4SS_WORLD_EXPORT_UNSAFE_PROPERTY_PROBES") == "1"

local state = {
  once = {},
  write_error = nil,
  retained_callbacks = {},
  latest_init_context = nil,
  latest_probe_objects = nil,
  initgamestate_hook_count = 0,
  selected_initgamestate_hook_count = nil,
}

print("[WorldExportContextProof] script loaded; output path=" .. tostring(OUT_PATH))

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

local function escape_json(text)
  return tostring(text or "")
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
    :gsub("\t", "\\t")
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

local function write_result(kind, payload)
  ensure_parent(OUT_PATH)

  local record = {}
  for key, value in pairs(payload or {}) do
    record[key] = value
  end
  record.kind = kind
  record.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

  local ok, err = pcall(function()
    local handle = assert(io.open(OUT_PATH, "a"))
    handle:write(json_encode(record))
    handle:write("\n")
    handle:close()
  end)

  if not ok and not state.write_error then
    state.write_error = tostring(err)
    print("[WorldExportContextProof] failed to write report: " .. state.write_error)
  elseif ok then
    print("[WorldExportContextProof] wrote result kind=" .. tostring(kind))
  end
end

local function once(key, callback)
  if state.once[key] then
    return
  end
  state.once[key] = true

  local ok, err = pcall(callback)
  if not ok then
    write_result("callback_error", {
      name = key,
      success = false,
      error = tostring(err),
    })
  end
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

local KEYWORDS = parse_csv_list(KEYWORDS_RAW)
local FUNCTION_HINTS = parse_csv_list(FUNCTION_HINTS_RAW)
local TARGET_PROPERTIES = parse_csv_list(PROPERTY_NAMES_RAW)
local FINDALL_CLASSES = parse_csv_list(FINDALL_CLASSES_RAW)

local function contains_any_hint(text, hints)
  local haystack = tostring(text or ""):lower()
  for _, hint in ipairs(hints or {}) do
    if haystack:find(tostring(hint):lower(), 1, true) then
      return true
    end
  end
  return false
end

local function contains_keyword(text)
  return contains_any_hint(text, KEYWORDS)
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

local function is_valid_object(object)
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

local function try_get_first_property_value(object, property_names)
  for _, property_name in ipairs(property_names or {}) do
    local value = try_get_property_value(object, property_name)
    if value ~= nil then
      return value, property_name
    end
  end
  return nil, nil
end

local function resolve_object(candidate)
  if candidate == nil then
    return nil, "nil"
  end

  local lower_get_ok, lower_get_value = pcall(function()
    return candidate:get()
  end)
  if lower_get_ok then
    return lower_get_value, "param_get"
  end

  local upper_get_ok, upper_get_value = pcall(function()
    return candidate:Get()
  end)
  if upper_get_ok then
    return upper_get_value, "param_Get"
  end

  return candidate, "direct"
end

local function get_fname_string(object)
  if not object or type(object.GetFName) ~= "function" then
    return nil
  end

  local name_ok, fname = pcall(function()
    return object:GetFName()
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
  if not object or type(object.GetFullName) ~= "function" then
    return nil
  end

  local full_name_ok, full_name = pcall(function()
    return object:GetFullName()
  end)
  if full_name_ok and full_name and tostring(full_name) ~= "" then
    return tostring(full_name)
  end

  return nil
end

local function get_object_address_string(object)
  if not is_valid_object(object) then
    return nil
  end

  local ok, address = pcall(function()
    return object:GetAddress()
  end)
  if ok and type(address) == "number" then
    return string.format("0x%X", address)
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
    if type(value.GetComparisonIndex) == "function" then
      if type(value.ToString) == "function" then
        local string_ok, string_value = pcall(function()
          return value:ToString()
        end)
        if string_ok and string_value and tostring(string_value) ~= "" then
          return tostring(string_value)
        end
      end

      local index_ok, comparison_index = pcall(function()
        return value:GetComparisonIndex()
      end)
      if index_ok and type(comparison_index) == "number" then
        return string.format("FName#%d", comparison_index)
      end
    end

    local fname_string = get_fname_string(value)
    if fname_string and fname_string ~= "" and not fname_string:match("^FName#%d+$") then
      return fname_string
    end

    if type(value.ToString) == "function" then
      local string_ok, string_value = pcall(function()
        return value:ToString()
      end)
      if string_ok and string_value and tostring(string_value) ~= "" then
        return tostring(string_value)
      end
    end

    local full_name = get_full_name_string(value)
    if full_name and full_name ~= "" then
      return full_name
    end
  end

  return tostring(value)
end

local function value_to_number(value)
  local string_value = value_to_string(value)
  if string_value == nil then
    return nil
  end
  return tonumber(string_value)
end

local function count_array_entries(value)
  if type(value) ~= "table" then
    return nil
  end

  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  return count
end

local object_label

local function render_probe_value(value)
  if is_valid_object(value) then
    return object_label(value)
  end

  local array_count = count_array_entries(value)
  if array_count ~= nil then
    return "table(" .. tostring(array_count) .. ")"
  end

  return value_to_string(value)
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

object_label = function(object)
  if not is_valid_object(object) then
    return nil
  end

  local short_name = get_object_short_name(object, nil)
  local full_name = get_full_name_string(object)
  local address = get_object_address_string(object)

  if full_name and full_name ~= "" and full_name ~= tostring(short_name or "") and address and address ~= "" then
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

  if address and address ~= "" then
    return address
  end

  return tostring(object)
end

local function describe_object(label, object)
  local payload = {
    label = label,
    is_valid = is_valid_object(object),
    success = is_valid_object(object),
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
    payload.class_address = get_object_address_string(class_object)
  end

  return payload
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

local function append_unique_match(matches, seen, value)
  local rendered = tostring(value or "")
  local normalized = rendered:lower()
  if rendered == "" or seen[normalized] then
    return
  end

  seen[normalized] = true
  matches[#matches + 1] = rendered
end

local function schedule_probe(label, delay_ms, callback)
  local wrapped = retain_callback("scheduled_probe_callback_" .. tostring(label or ""), function()
    once("scheduled_probe_" .. tostring(label or ""), callback)
  end)

  if delay_ms and delay_ms > 0 then
    if type(ExecuteInGameThreadAfterFrames) == "function" then
      local frames = math.max(1, math.floor(delay_ms / 100))
      ExecuteInGameThreadAfterFrames(frames, wrapped)
      write_result("scheduled_probe", {
        label = label,
        delay_ms = delay_ms,
        scheduler = "ExecuteInGameThreadAfterFrames",
        frames = frames,
        success = true,
      })
      return true
    end

    if type(ExecuteInGameThreadWithDelay) == "function" then
      ExecuteInGameThreadWithDelay(delay_ms, wrapped)
      write_result("scheduled_probe", {
        label = label,
        delay_ms = delay_ms,
        scheduler = "ExecuteInGameThreadWithDelay",
        success = true,
      })
      return true
    end
  end

  local ok, err = pcall(wrapped)
  write_result("scheduled_probe", {
    label = label,
    delay_ms = delay_ms or 0,
    scheduler = "direct_call",
    success = ok,
    error = ok and nil or tostring(err),
  })
  return ok
end

local function scan_property_keywords(label, object)
  local payload = {
    label = label,
  }
  payload.keyword_list = KEYWORDS

  if not ALLOW_UNSAFE_REFLECTION then
    payload.success = false
    payload.skipped = true
    payload.reason = "unsafe reflection scans are disabled by default on CL12960 because ForEachProperty can crash UE4SS"
    write_result("property_keyword_scan", payload)
    return
  end

  if object == nil or type(object.GetClass) ~= "function" then
    payload.reason = "invalid object"
    write_result("property_keyword_scan", payload)
    return
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
  end

  if not is_valid_object(class_object) or type(class_object.ForEachProperty) ~= "function" then
    payload.success = false
    payload.reason = "class reflection is unavailable"
    write_result("property_keyword_scan", payload)
    return
  end

  local visited = {}
  local matches = {}
  local match_seen = {}
  local scanned_count = 0
  local walk_depth = 0
  local cursor = class_object
  local walk_error = nil
  local callback_error_count = 0
  local callback_errors = {}

  while is_valid_object(cursor) and walk_depth < 8 do
    local cursor_name = object_label(cursor) or ("class-depth-" .. tostring(walk_depth))
    if visited[cursor_name] then
      break
    end
    visited[cursor_name] = true
    walk_depth = walk_depth + 1

    local ok, err = pcall(function()
      cursor:ForEachProperty(function(property)
        local property_ok, property_error = pcall(function()
          scanned_count = scanned_count + 1
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

          if contains_keyword(keyword_haystack) then
            local descriptor = tostring(property_name or "unknown") .. ":" .. tostring(property_class or "unknown")
            if object_class and object_class ~= "" then
              descriptor = descriptor .. "<" .. object_class .. ">"
            elseif struct_name and struct_name ~= "" then
              descriptor = descriptor .. "<" .. struct_name .. ">"
            end
            append_unique_match(matches, match_seen, descriptor)
          end
        end)

        if not property_ok then
          callback_error_count = callback_error_count + 1
          if #callback_errors < 6 then
            callback_errors[#callback_errors + 1] = tostring(property_error)
          end
        end

        return #matches >= 48
      end)
    end)

    if not ok then
      walk_error = tostring(err)
      break
    end

    if #matches >= 48 or type(cursor.GetSuperStruct) ~= "function" then
      break
    end

    local super_ok, super_struct = safe_method_call(cursor, "GetSuperStruct")
    if not super_ok or not is_valid_object(super_struct) then
      break
    end

    cursor = super_struct
  end

  payload.success = walk_error == nil
  payload.scanned_count = scanned_count
  payload.match_count = #matches
  payload.matches = matches
  payload.walk_depth = walk_depth
  payload.error = walk_error
  payload.callback_error_count = callback_error_count
  payload.callback_errors = callback_errors
  write_result("property_keyword_scan", payload)
end

local function scan_function_keywords(label, object)
  local payload = {
    label = label,
  }
  payload.keyword_list = FUNCTION_HINTS

  if not ALLOW_UNSAFE_REFLECTION then
    payload.success = false
    payload.skipped = true
    payload.reason = "unsafe reflection scans are disabled by default on CL12960 because ForEachFunction can crash UE4SS"
    write_result("function_keyword_scan", payload)
    return
  end

  if object == nil or type(object.GetClass) ~= "function" then
    payload.reason = "invalid object"
    write_result("function_keyword_scan", payload)
    return
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
  end

  if not is_valid_object(class_object) or type(class_object.ForEachFunction) ~= "function" then
    payload.success = false
    payload.reason = "function reflection is unavailable"
    write_result("function_keyword_scan", payload)
    return
  end

  local visited = {}
  local matches = {}
  local match_seen = {}
  local scanned_count = 0
  local walk_depth = 0
  local cursor = class_object
  local walk_error = nil
  local callback_error_count = 0
  local callback_errors = {}

  while is_valid_object(cursor) and walk_depth < 8 do
    local cursor_name = object_label(cursor) or ("class-depth-" .. tostring(walk_depth))
    if visited[cursor_name] then
      break
    end
    visited[cursor_name] = true
    walk_depth = walk_depth + 1

    local ok, err = pcall(function()
      cursor:ForEachFunction(function(func)
        local function_ok, function_error = pcall(function()
          scanned_count = scanned_count + 1
          local function_name = get_function_name(func)
          if function_name and contains_any_hint(function_name, FUNCTION_HINTS) then
            append_unique_match(matches, match_seen, function_name)
          end
        end)

        if not function_ok then
          callback_error_count = callback_error_count + 1
          if #callback_errors < 6 then
            callback_errors[#callback_errors + 1] = tostring(function_error)
          end
        end

        return #matches >= 48
      end)
    end)

    if not ok then
      walk_error = tostring(err)
      break
    end

    if #matches >= 48 or type(cursor.GetSuperStruct) ~= "function" then
      break
    end

    local super_ok, super_struct = safe_method_call(cursor, "GetSuperStruct")
    if not super_ok or not is_valid_object(super_struct) then
      break
    end

    cursor = super_struct
  end

  payload.success = walk_error == nil
  payload.scanned_count = scanned_count
  payload.match_count = #matches
  payload.matches = matches
  payload.walk_depth = walk_depth
  payload.error = walk_error
  payload.callback_error_count = callback_error_count
  payload.callback_errors = callback_errors
  write_result("function_keyword_scan", payload)
end

local function scan_named_properties(label, object)
  local payload = {
    label = label,
  }
  payload.property_names = TARGET_PROPERTIES

  if not ALLOW_UNSAFE_PROPERTY_PROBES then
    payload.success = false
    payload.skipped = true
    payload.reason = "unsafe property probes are disabled by default on CL12960 because GetPropertyValue can crash UE4SS during deferred world-export scans"
    write_result("named_property_probe", payload)
    return
  end

  if object == nil or type(object.GetPropertyValue) ~= "function" then
    payload.reason = "invalid object"
    write_result("named_property_probe", payload)
    return
  end

  local hits = {}
  for _, property_name in ipairs(TARGET_PROPERTIES) do
    local value = try_get_property_value(object, property_name)
    if value ~= nil then
      hits[#hits + 1] = {
        name = property_name,
        value = render_probe_value(value),
        number = value_to_number(value),
      }
    end
  end

  payload.success = true
  payload.hit_count = #hits
  payload.hits = hits
  write_result("named_property_probe", payload)
end

local function scan_candidate_classes()
  for _, class_name in ipairs(FINDALL_CLASSES) do
    local payload = {
      class_name = class_name,
    }

    local first_ok, first_result = pcall(function()
      return FindFirstOf(class_name)
    end)
    payload.find_first_success = first_ok and first_result ~= nil
    payload.find_first_error = first_ok and nil or tostring(first_result)

    local ok, results = pcall(function()
      return FindAllOf(class_name)
    end)
    payload.success = ok
    if not ok then
      payload.error = tostring(results)
      payload.count = 0
      payload.samples = {}
      write_result("candidate_class_scan", payload)
      goto continue
    end

    local count = 0
    if type(results) == "table" then
      count = #results
    end

    payload.count = count
    payload.samples = {}
    write_result("candidate_class_scan", payload)

    ::continue::
  end
end

local function record_context_object(label, object)
  write_result("context_object", describe_object(label, object))
end

local function build_probe_objects()
  local hook_context, hook_resolver = resolve_object(state.latest_init_context)
  local world = nil
  local persistent_level = nil
  local game_mode = nil
  local game_state = nil
  local game_instance = nil
  local world_settings = nil
  local game_session = nil

  if is_valid_object(hook_context) then
    if type(hook_context.GetWorld) == "function" then
      local get_world_ok, get_world = pcall(function()
        return hook_context:GetWorld()
      end)
      if get_world_ok then
        world = get_world
      end
    end

    game_mode = hook_context
  end

  if not is_valid_object(game_mode) then
    local find_game_mode_ok, found_game_mode = pcall(function()
      return FindFirstOf("GameModeBase")
    end)
    if find_game_mode_ok then
      game_mode = found_game_mode
    end
  end

  if not is_valid_object(world) and is_valid_object(game_mode) and type(game_mode.GetWorld) == "function" then
    local get_world_ok, get_world = pcall(function()
      return game_mode:GetWorld()
    end)
    if get_world_ok then
      world = get_world
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

  if not is_valid_object(game_state) then
    game_state = try_get_property_value(world, "GameState")
  end

  if not is_valid_object(game_state) then
    local find_game_state_ok, found_game_state = pcall(function()
      return FindFirstOf("GameStateBase")
    end)
    if find_game_state_ok then
      game_state = found_game_state
    end
  end

  if not is_valid_object(persistent_level) then
    persistent_level = try_get_property_value(world, "PersistentLevel")
  end

  if not is_valid_object(game_mode) then
    game_mode = try_get_property_value(world, "AuthorityGameMode") or try_get_property_value(world, "GameMode")
  end

  if not is_valid_object(game_session) then
    game_session = try_get_property_value(game_mode, "GameSession")
  end

  if not is_valid_object(world_settings) then
    world_settings = try_get_property_value(persistent_level, "WorldSettings")
  end

  if not is_valid_object(game_instance) then
    game_instance = try_get_property_value(world, "OwningGameInstance")
      or try_get_property_value(game_mode, "GameInstance")
      or try_get_property_value(game_state, "GameInstance")
  end

  if not is_valid_object(game_instance) then
    local find_game_instance_ok, found_game_instance = pcall(function()
      return FindFirstOf("GameInstance")
    end)
    if find_game_instance_ok then
      game_instance = found_game_instance
    end
  end

  return {
    hook_context = hook_context,
    hook_resolver = hook_resolver,
    probe_objects = {
      { label = "world", object = world },
      { label = "persistent_level", object = persistent_level },
      { label = "game_mode", object = game_mode },
      { label = "game_state", object = game_state },
      { label = "game_session", object = game_session },
      { label = "game_instance", object = game_instance },
      { label = "world_settings", object = world_settings },
    },
  }
end

local function build_safe_scan_objects(probe_objects)
  local safe_labels = {
    game_mode = true,
    game_state = true,
    game_session = true,
    game_instance = true,
  }
  local results = {}
  for _, entry in ipairs(probe_objects or {}) do
    if safe_labels[entry.label] then
      results[#results + 1] = entry
    end
  end
  return results
end

local function run_context_discovery(trigger, phase, probe_source, probe_objects)
  once("context_discovery_" .. trigger .. "_" .. tostring(phase or "scheduled"), function()
    local scan_objects = build_safe_scan_objects(probe_objects)

    write_result("discovery_phase_begin", {
      trigger = trigger,
      phase = phase,
      source = probe_source,
      scan_object_count = #scan_objects,
      success = true,
    })

    scan_candidate_classes()

    for _, entry in ipairs(scan_objects) do
      scan_property_keywords(entry.label, entry.object)
      scan_function_keywords(entry.label, entry.object)
      scan_named_properties(entry.label, entry.object)
    end

    write_result("runtime_counts_probe_begin", {
      source = probe_source,
      trigger = trigger,
      phase = phase,
      success = true,
    })

    if not ALLOW_UNSAFE_PROPERTY_PROBES then
      write_result("runtime_counts", {
        source = probe_source,
        trigger = trigger,
        phase = phase,
        success = false,
        skipped = true,
        reason = "unsafe property probes are disabled by default on CL12960 because deferred GetPropertyValue reads can crash UE4SS",
      })
      return
    end

    local function find_property_across_objects(entries, property_names)
      for _, entry in ipairs(entries) do
        local value, property_name = try_get_first_property_value(entry.object, property_names)
        if value ~= nil then
          return value, property_name, entry.label
        end
      end
      return nil, nil, nil
    end

    local brick_count_value, brick_count_property, brick_count_source = find_property_across_objects(
      scan_objects,
      { "NumBricks", "BrickCount", "NumBricksSaved" }
    )
    local component_count_value, component_count_property, component_count_source = find_property_across_objects(
      scan_objects,
      { "NumComponents", "ComponentCount", "BricksComponentCount", "NumWires", "WireCount" }
    )
    local player_array_value, player_array_property, player_array_source = find_property_across_objects(
      scan_objects,
      { "PlayerArray", "Players" }
    )

    write_result("runtime_counts", {
      source = probe_source,
      trigger = trigger,
      phase = phase,
      success = true,
      brick_count_source = brick_count_source,
      brick_count_property = brick_count_property,
      brick_count = render_probe_value(brick_count_value),
      brick_count_number = value_to_number(brick_count_value),
      component_count_source = component_count_source,
      component_count_property = component_count_property,
      component_count = render_probe_value(component_count_value),
      component_count_number = value_to_number(component_count_value),
      player_array_source = player_array_source,
      player_array_property = player_array_property,
      player_count = count_array_entries(player_array_value),
    })
  end)
end

local function run_context_capture(trigger, phase)
  once("context_capture_" .. trigger .. "_" .. tostring(phase or "scheduled"), function()
    local probe_source = tostring(trigger) .. ":" .. tostring(phase or "scheduled")
    local snapshot = build_probe_objects()
    state.latest_probe_objects = snapshot.probe_objects

    write_result("context_probe_source", {
      source = probe_source,
      trigger = trigger,
      phase = phase,
      success = is_valid_object(snapshot.hook_context),
      resolver = snapshot.hook_resolver,
      context_name = object_label(snapshot.hook_context),
    })

    for _, entry in ipairs(snapshot.probe_objects) do
      record_context_object(entry.label, entry.object)
    end
  end)
end

local function schedule_context_probe(trigger)
  local capture_ok, capture_error = pcall(function()
    run_context_capture(trigger, "hook")
  end)
  if capture_ok then
    write_result("context_probe_scheduled", {
      source = trigger,
      phase = "hook",
      success = true,
      probe_delay_ms = 0,
      scheduler = "hook_capture",
    })
  else
    write_result("context_probe_schedule_error", {
      source = trigger,
      phase = "hook",
      success = false,
      probe_delay_ms = 0,
      scheduler = "hook_capture",
      error = tostring(capture_error),
    })
    return
  end

  local captured_objects = state.latest_probe_objects or {}
  schedule_probe("context_discovery_initial_" .. tostring(trigger), 250, function()
    run_context_discovery(trigger, "scheduled", tostring(trigger) .. ":hook", captured_objects)
  end)

  if PROBE_DELAY_MS and PROBE_DELAY_MS > 0 then
    schedule_probe("context_discovery_followup_" .. tostring(trigger), PROBE_DELAY_MS, function()
      run_context_discovery(trigger, "followup", tostring(trigger) .. ":hook", captured_objects)
    end)
  end
end

write_result("startup", {
  success = true,
  out_path = OUT_PATH,
  probe_delay_ms = PROBE_DELAY_MS,
  keyword_list = KEYWORDS,
  function_hint_list = FUNCTION_HINTS,
  property_name_list = TARGET_PROPERTIES,
  candidate_classes = FINDALL_CLASSES,
  unsafe_reflection_enabled = ALLOW_UNSAFE_REFLECTION,
  unsafe_property_probes_enabled = ALLOW_UNSAFE_PROPERTY_PROBES,
  execute_in_game_thread_with_delay = type(ExecuteInGameThreadWithDelay) == "function",
  execute_in_game_thread_after_frames = type(ExecuteInGameThreadAfterFrames) == "function",
  engine_tick_available = tostring(EngineTickAvailable),
  process_event_available = tostring(ProcessEventAvailable),
})

write_result("scheduler_capabilities", {
  execute_in_game_thread_with_delay = type(ExecuteInGameThreadWithDelay) == "function",
  execute_in_game_thread_after_frames = type(ExecuteInGameThreadAfterFrames) == "function",
})

RegisterInitGameStatePostHook(function(Context)
  state.initgamestate_hook_count = state.initgamestate_hook_count + 1
  local hook_count = state.initgamestate_hook_count
  local is_selected = hook_count >= 2 and state.selected_initgamestate_hook_count == nil

  write_result("hook_event", {
    hook = "RegisterInitGameStatePostHook",
    source = "RegisterInitGameStatePostHook",
    success = true,
    hook_count = hook_count,
    selected_for_probe = is_selected,
    context_name = object_label(Context),
  })

  if is_selected then
    state.selected_initgamestate_hook_count = hook_count
    state.latest_init_context = Context
    schedule_context_probe("initgamestate")
  end
end)

RegisterBeginPlayPostHook(function(Actor)
  once("beginplay_hook", function()
    write_result("hook_event", {
      hook = "RegisterBeginPlayPostHook",
      source = "RegisterBeginPlayPostHook",
      success = true,
      actor_name = object_label(Actor),
    })
  end)
end)
