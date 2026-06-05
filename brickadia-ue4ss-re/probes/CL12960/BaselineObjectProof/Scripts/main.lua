local OUT_PATH = os.getenv("OMEGGA_UE4SS_BASELINE_PROOF_OUT") or "__BASELINE_PROOF_OUT__"
local LOOKUP_PROBE_SET = (os.getenv("OMEGGA_UE4SS_BASELINE_LOOKUPS") or ""):lower()
local LOOKUP_DELAY_MS = tonumber(os.getenv("OMEGGA_UE4SS_BASELINE_LOOKUP_DELAY_MS") or "1500") or 1500
local UNWRAP_PARAMS = (os.getenv("OMEGGA_UE4SS_BASELINE_UNWRAP_PARAMS") or ""):lower()
local state = {
  write_error = nil,
  once = {},
}

print("[BaselineObjectProof] script loaded; output path=" .. tostring(OUT_PATH))

local function ensure_parent()
  local normalized = OUT_PATH:gsub("/", "\\")
  local parent = normalized:match("^(.*)\\[^\\]+$")
  if parent and parent ~= "" then
    os.execute('if not exist "' .. parent .. '" mkdir "' .. parent .. '"')
  end
end

local function escape_json(text)
  return tostring(text)
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
    :gsub("\t", "\\t")
end

local function write_result(kind, payload)
  ensure_parent()

  local parts = {'{"kind":"' .. escape_json(kind) .. '"'}
  for key, value in pairs(payload or {}) do
    local encoded
    if type(value) == "boolean" then
      encoded = value and "true" or "false"
    elseif type(value) == "number" then
      encoded = tostring(value)
    elseif value == nil then
      encoded = "null"
    else
      encoded = '"' .. escape_json(value) .. '"'
    end
    parts[#parts + 1] = '"' .. escape_json(key) .. '":' .. encoded
  end
  parts[#parts + 1] = '"timestamp":"' .. escape_json(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. '"}'
  local line = table.concat(parts, ",") .. "\n"

  local ok, err = pcall(function()
    local handle = assert(io.open(OUT_PATH, "a"))
    handle:write(line)
    handle:close()
  end)

  if not ok and not state.write_error then
    state.write_error = tostring(err)
    print("[BaselineObjectProof] failed to write report: " .. state.write_error)
  elseif ok then
    print("[BaselineObjectProof] wrote result kind=" .. tostring(kind))
  end
end

local function once(key, fn)
  if state.once[key] then
    return
  end
  state.once[key] = true
  local ok, err = pcall(fn)
  if not ok then
    write_result("callback_error", { name = key, error = tostring(err) })
  end
end

local function merge_payload(target, extra)
  for key, value in pairs(extra or {}) do
    target[key] = value
  end
  return target
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

local function describe_value(prefix, value)
  local payload = {
    [prefix .. "_lua_type"] = type(value),
  }
  local type_ok, type_name, type_error = safe_method_call(value, "type")
  payload[prefix .. "_ue_type_ok"] = type_ok
  payload[prefix .. "_ue_type"] = type_ok and tostring(type_name) or nil
  payload[prefix .. "_ue_type_error"] = type_ok and nil or type_error
  return payload
end

local function normalize_probe_set()
  if LOOKUP_PROBE_SET == "" then
    return "none"
  end
  return LOOKUP_PROBE_SET
end

local function lookup_probe_enabled(name)
  if LOOKUP_PROBE_SET == "" or LOOKUP_PROBE_SET == "none" then
    return false
  end
  if LOOKUP_PROBE_SET == "all" then
    return true
  end

  for token in LOOKUP_PROBE_SET:gmatch("[^,%s]+") do
    if token == name then
      return true
    end
  end
  return false
end

local function unwrap_params_enabled()
  return UNWRAP_PARAMS == "1"
    or UNWRAP_PARAMS == "true"
    or UNWRAP_PARAMS == "yes"
    or UNWRAP_PARAMS == "on"
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

  local candidate_type_ok, candidate_type = safe_method_call(candidate, "type")
  if candidate_type_ok and tostring(candidate_type) == "RemoteUnrealParam" then
    return nil, "param_get_failed:" .. tostring(lower_get_value or upper_get_value)
  end

  return candidate, "direct"
end

local function probe_object(kind, candidate, source)
  local payload = {
    source = source,
  }
  merge_payload(payload, describe_value("candidate", candidate))

  if not unwrap_params_enabled() then
    payload.unwrap_enabled = false
    payload.object_resolution_attempted = false
    payload.object_resolution_blocked = true
    payload.success = true
    write_result(kind, payload)
    return
  end

  write_result(kind .. "_unwrap_attempt", merge_payload({
    source = source,
    unwrap_enabled = true,
    object_resolution_attempted = true,
  }, describe_value("candidate", candidate)))

  local object, resolver = resolve_object(candidate)
  if object == nil then
    payload.resolver = resolver
    payload.unwrap_enabled = true
    payload.object_resolution_attempted = true
    payload.success = false
    payload.error = "no object"
    write_result(kind, payload)
    return
  end

  payload.resolver = resolver
  payload.unwrap_enabled = true
  payload.object_resolution_attempted = true
  merge_payload(payload, describe_value("object", object))

  local valid_ok, valid, valid_error = safe_method_call(object, "IsValid")
  payload.is_valid_call_ok = valid_ok
  payload.is_valid = valid_ok and tostring(valid) or nil
  payload.is_valid_error = valid_ok and nil or valid_error

  payload.get_full_name_ok = false
  payload.full_name = nil
  payload.full_name_error = "skipped to keep the unwrap canary focused on object validity"
  payload.success = valid_ok and valid

  write_result(kind, payload)
end

local function run_lookup_probes(trigger)
  once("lookup_" .. trigger, function()
    local probes_requested = lookup_probe_enabled("findfirstof") or lookup_probe_enabled("staticfindobject")
    if not probes_requested then
      write_result("lookup_probes_skipped", {
        source = trigger,
        success = true,
        lookup_probe_set = normalize_probe_set(),
      })
      return
    end

    local function execute_lookup_run()
      once("lookup_run_" .. trigger, function()
        if lookup_probe_enabled("findfirstof") then
          local find_ok, found = pcall(function()
            return FindFirstOf("GameEngine")
          end)
          if find_ok then
            probe_object("lookup_findfirstof", found, trigger)
          else
            write_result("lookup_findfirstof", {
              source = trigger,
              success = false,
              error = tostring(found),
            })
          end
        end

        if lookup_probe_enabled("staticfindobject") then
          local static_ok, static_object = pcall(function()
            return StaticFindObject("/Script/CoreUObject.Default__Object")
          end)
          if static_ok then
            probe_object("lookup_staticfindobject", static_object, trigger)
          else
            write_result("lookup_staticfindobject", {
              source = trigger,
              success = false,
              error = tostring(static_object),
            })
          end
        end
      end)
    end

    if LOOKUP_DELAY_MS <= 0 then
      execute_lookup_run()
      return
    end

    local schedule_ok, schedule_error = pcall(function()
      ExecuteInGameThreadWithDelay(LOOKUP_DELAY_MS, function()
        execute_lookup_run()
      end)
    end)

    if schedule_ok then
      write_result("lookup_probes_scheduled", {
        source = trigger,
        success = true,
        lookup_probe_set = normalize_probe_set(),
        lookup_delay_ms = LOOKUP_DELAY_MS,
      })
    else
      write_result("lookup_probes_schedule_error", {
        source = trigger,
        success = false,
        lookup_probe_set = normalize_probe_set(),
        lookup_delay_ms = LOOKUP_DELAY_MS,
        error = tostring(schedule_error),
      })
    end
  end)
end

write_result("startup", {
  success = true,
  out_path = OUT_PATH,
  lookup_probe_set = normalize_probe_set(),
  lookup_delay_ms = LOOKUP_DELAY_MS,
  unwrap_params = tostring(unwrap_params_enabled()),
  engine_tick_available = tostring(EngineTickAvailable),
  process_event_available = tostring(ProcessEventAvailable),
})

RegisterLoadMapPostHook(function(Engine, WorldContext, URL, PendingGame, Error)
  once("loadmap_hook", function()
    probe_object("hook_loadmap_engine", Engine, "RegisterLoadMapPostHook")
    run_lookup_probes("loadmap")
  end)
end)

RegisterInitGameStatePostHook(function(Context)
  once("initgamestate_hook", function()
    probe_object("hook_initgamestate_context", Context, "RegisterInitGameStatePostHook")
    run_lookup_probes("initgamestate")
  end)
end)

RegisterBeginPlayPostHook(function(Actor)
  once("beginplay_hook", function()
    probe_object("hook_beginplay_actor", Actor, "RegisterBeginPlayPostHook")
    run_lookup_probes("beginplay")
  end)
end)
