local OUT_PATH = os.getenv("OMEGGA_UE4SS_CHAT_PROOF_OUT") or "__BASELINE_CHAT_PROOF_OUT__"
local state = {
  write_error = nil,
  once = {},
  process_console_exec_sequence = 0,
}

print("[BaselineChatProof] script loaded; output path=" .. tostring(OUT_PATH))

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
    print("[BaselineChatProof] failed to write report: " .. state.write_error)
  elseif ok then
    print("[BaselineChatProof] wrote result kind=" .. tostring(kind))
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

local function has_global_function(name)
  return type(_G[name]) == "function"
end

local function try_bool(fn)
  if type(fn) ~= "function" then
    return false, nil, "missing"
  end

  local ok, value = pcall(fn)
  if not ok then
    return false, nil, tostring(value)
  end

  return true, value and true or false, nil
end

local function try_string(fn)
  if type(fn) ~= "function" then
    return false, nil, "missing"
  end

  local ok, value = pcall(fn)
  if not ok then
    return false, nil, tostring(value)
  end

  return true, tostring(value or ""), nil
end

local function capture_scheduler_capabilities()
  write_result("scheduler_capabilities", {
    execute_with_delay = has_global_function("ExecuteWithDelay"),
    execute_in_game_thread = has_global_function("ExecuteInGameThread"),
    execute_in_game_thread_with_delay = has_global_function("ExecuteInGameThreadWithDelay"),
    execute_in_game_thread_after_frames = has_global_function("ExecuteInGameThreadAfterFrames"),
  })
end

local function capture_helper_capabilities()
  write_result("helper_capabilities", {
    omegga_has_cached_command_context = has_global_function("OmeggaHasCachedCommandContext"),
    omegga_get_cached_command_context = has_global_function("OmeggaGetCachedCommandContext"),
    omegga_describe_cached_command_context = has_global_function("OmeggaDescribeCachedCommandContext"),
    omegga_has_cached_engine_exec_context = has_global_function("OmeggaHasCachedEngineExecContext"),
    omegga_get_cached_world = has_global_function("OmeggaGetCachedWorld"),
    omegga_describe_cached_world = has_global_function("OmeggaDescribeCachedWorld"),
    omegga_execute_cached_engine_exec = has_global_function("OmeggaExecuteCachedEngineExec"),
    omegga_execute_cached_console_exec = has_global_function("OmeggaExecuteCachedConsoleExec"),
    omegga_execute_kismet_console_command = has_global_function("OmeggaExecuteKismetConsoleCommand"),
    register_process_console_exec_pre_hook = has_global_function("RegisterProcessConsoleExecPreHook"),
    register_process_console_exec_post_hook = has_global_function("RegisterProcessConsoleExecPostHook"),
  })
end

local function capture_context_snapshot(trigger)
  local has_cmd_ok, has_cmd_value, has_cmd_error = try_bool(OmeggaHasCachedCommandContext)
  local has_engine_ok, has_engine_value, has_engine_error = try_bool(OmeggaHasCachedEngineExecContext)

  write_result("context_snapshot", {
    trigger = trigger,
    has_cached_command_context_call_ok = has_cmd_ok,
    has_cached_command_context = has_cmd_ok and has_cmd_value or nil,
    has_cached_command_context_error = has_cmd_ok and nil or has_cmd_error,
    has_cached_engine_exec_context_call_ok = has_engine_ok,
    has_cached_engine_exec_context = has_engine_ok and has_engine_value or nil,
    has_cached_engine_exec_context_error = has_engine_ok and nil or has_engine_error,
  })
end

local function register_process_console_exec_hooks()
  local registrations = {
    { hook = "RegisterProcessConsoleExecPreHook", phase = "pre" },
    { hook = "RegisterProcessConsoleExecPostHook", phase = "post" },
  }

  for _, registration in ipairs(registrations) do
    local hook_name = registration.hook
    local phase = registration.phase
    local hook_fn = _G[hook_name]

    if type(hook_fn) ~= "function" then
      write_result("hook_registration", {
        hook = hook_name,
        phase = phase,
        success = false,
        error = "missing",
      })
    else
      local ok, err = pcall(function()
        hook_fn(function(Context, Cmd, CommandParts, Ar, Executor)
          if type(Cmd) ~= "string" or not Cmd:match("^Chat%.") then
            return
          end

          state.process_console_exec_sequence = state.process_console_exec_sequence + 1
          write_result("process_console_exec_observed", {
            hook = hook_name,
            phase = phase,
            cmd = Cmd,
            command_parts_count = type(CommandParts) == "table" and #CommandParts or 0,
            sequence = state.process_console_exec_sequence,
          })
        end)
      end)

      write_result("hook_registration", {
        hook = hook_name,
        phase = phase,
        success = ok,
        error = ok and nil or tostring(err),
      })
    end
  end
end

local function record_attempt(kind, trigger, label, executor, command, payload)
  local base = {
    trigger = trigger,
    label = label,
    executor = executor,
    command = command,
  }

  for key, value in pairs(payload or {}) do
    base[key] = value
  end

  write_result(kind, base)
end

local function attempt_command(kind, trigger, label, executor, command, fn)
  if type(fn) ~= "function" then
    record_attempt(kind, trigger, label, executor, command, {
      available = false,
      skipped = true,
      success = false,
      error = "missing",
    })
    return false
  end

  local ok, success, output = pcall(fn, command)
  if not ok then
    record_attempt(kind, trigger, label, executor, command, {
      available = true,
      call_ok = false,
      success = false,
      error = tostring(success),
    })
    return false
  end

  record_attempt(kind, trigger, label, executor, command, {
    available = true,
    call_ok = true,
    success = success and true or false,
    output = output or "",
  })
  return success and true or false
end

local function attempt_nonchat_console_probe(trigger)
  once("nonchat_console_probe_" .. trigger, function()
    local command = "Server.Status"
    capture_context_snapshot(trigger .. "_nonchat")
    attempt_command(
      "command_attempt",
      trigger,
      "server_status_engine_exec",
      "cached_engine_exec",
      command,
      OmeggaExecuteCachedEngineExec
    )
    attempt_command(
      "command_attempt",
      trigger,
      "server_status_cached_console_exec",
      "cached_console_exec",
      command,
      OmeggaExecuteCachedConsoleExec
    )
    attempt_command(
      "command_attempt",
      trigger,
      "server_status_kismet_console_command",
      "kismet_console_command",
      command,
      OmeggaExecuteKismetConsoleCommand
    )
  end)
end

local function attempt_broadcast_sequence(trigger, sequence)
  local command = "Chat.Broadcast Hello from BaselineChatProof #" .. tostring(sequence)
  capture_context_snapshot(trigger .. "_broadcast_" .. tostring(sequence))

  local accepted = attempt_command(
    "broadcast_attempt",
    trigger,
    "broadcast_engine_exec_" .. tostring(sequence),
    "cached_engine_exec",
    command,
    OmeggaExecuteCachedEngineExec
  )

  record_attempt(
    "broadcast_attempt",
    trigger,
    "broadcast_cached_console_exec_" .. tostring(sequence),
    "cached_console_exec",
    command,
    {
      available = has_global_function("OmeggaExecuteCachedConsoleExec"),
      skipped = true,
      success = false,
      error = "skipped because ProcessConsoleExec crashes on Chat.* for this Brickadia build",
    }
  )

  if not accepted then
    accepted = attempt_command(
      "broadcast_attempt",
      trigger,
      "broadcast_kismet_console_command_" .. tostring(sequence),
      "kismet_console_command",
      command,
      OmeggaExecuteKismetConsoleCommand
    )
  else
    record_attempt(
      "broadcast_attempt",
      trigger,
      "broadcast_kismet_console_command_" .. tostring(sequence),
      "kismet_console_command",
      command,
      {
        available = has_global_function("OmeggaExecuteKismetConsoleCommand"),
        skipped = true,
        success = false,
        error = "skipped because an earlier executor already accepted the broadcast command",
      }
    )
  end

  write_result("broadcast_round_complete", {
    trigger = trigger,
    sequence = sequence,
    success = accepted,
  })
end

local function schedule_probe(label, delay_ms, callback)
  local wrapped = function()
    once("scheduled_probe_" .. label, callback)
  end

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

    if type(ExecuteWithDelay) == "function" then
      ExecuteWithDelay(delay_ms, wrapped)
      write_result("scheduled_probe", {
        label = label,
        delay_ms = delay_ms,
        scheduler = "ExecuteWithDelay",
        success = true,
      })
      return true
    end
  end

  if type(ExecuteInGameThread) == "function" then
    ExecuteInGameThread(wrapped)
    write_result("scheduled_probe", {
      label = label,
      delay_ms = delay_ms or 0,
      scheduler = "ExecuteInGameThread",
      success = true,
    })
    return true
  end

  if type(ExecuteInGameThreadAfterFrames) == "function" then
    ExecuteInGameThreadAfterFrames(1, wrapped)
    write_result("scheduled_probe", {
      label = label,
      delay_ms = delay_ms or 0,
      scheduler = "ExecuteInGameThreadAfterFrames",
      frames = 1,
      success = true,
    })
    return true
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

local function schedule_chat_rounds(trigger)
  once("chat_rounds_scheduled", function()
    schedule_probe(trigger .. "_context_snapshot", 500, function()
      capture_context_snapshot(trigger .. "_scheduled")
    end)

    schedule_probe(trigger .. "_nonchat_probe", 1500, function()
      attempt_nonchat_console_probe(trigger)
    end)

    schedule_probe(trigger .. "_broadcast_round_1", 3000, function()
      attempt_broadcast_sequence(trigger, 1)
    end)
    schedule_probe(trigger .. "_broadcast_round_2", 6000, function()
      attempt_broadcast_sequence(trigger, 2)
    end)
  end)
end

write_result("startup", {
  success = true,
  out_path = OUT_PATH,
})
capture_scheduler_capabilities()
capture_helper_capabilities()
register_process_console_exec_hooks()

RegisterInitGameStatePostHook(function(Context)
  once("initgamestate_hook", function()
    write_result("hook_event", {
      hook = "RegisterInitGameStatePostHook",
      success = true,
    })
    schedule_chat_rounds("initgamestate")
  end)
end)

RegisterBeginPlayPostHook(function(Actor)
  once("beginplay_hook", function()
    write_result("hook_event", {
      hook = "RegisterBeginPlayPostHook",
      success = true,
    })
    schedule_chat_rounds("beginplay")
  end)
end)
