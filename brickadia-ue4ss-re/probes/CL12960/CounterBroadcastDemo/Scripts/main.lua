local MOD_NAME = "CounterBroadcastDemo"
local DEFAULT_STATE_PATH = "Mods/" .. MOD_NAME .. "/runtime/count.txt"
local DEFAULT_TRACE_PATH = "Mods/" .. MOD_NAME .. "/runtime/mod.log"
local STATE_PATH = os.getenv("OMEGGA_UE4SS_COUNTER_BROADCAST_STATE") or DEFAULT_STATE_PATH
local TRACE_PATH = os.getenv("OMEGGA_UE4SS_COUNTER_BROADCAST_LOG") or DEFAULT_TRACE_PATH
local BRIDGE_INBOX_PATH = os.getenv("OMEGGA_UE4SS_INBOX") or ""
local BRIDGE_OUTBOX_PATH = os.getenv("OMEGGA_UE4SS_OUTBOX") or ""
local BRIDGE_STATUS_PATH = os.getenv("OMEGGA_UE4SS_STATUS") or ""
local INTERVAL_MS = tonumber(os.getenv("OMEGGA_UE4SS_COUNTER_BROADCAST_INTERVAL_MS") or "3000") or 3000
local POLL_INTERVAL_MS = tonumber(os.getenv("OMEGGA_UE4SS_COUNTER_BROADCAST_POLL_MS") or "250") or 250
local START_DELAY_MS = tonumber(os.getenv("OMEGGA_UE4SS_COUNTER_BROADCAST_START_DELAY_MS") or "12000") or 12000

local state = {
  count = 0,
  started = false,
  start_attempts = 0,
  retained_callbacks = {},
  remaining_ms = 0,
  bridge_ready = false,
  bridge_hello_seen = false,
  bridge_outbox_offset = 0,
  bridge_next_request_id = 2000,
  pending_broadcast = nil,
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
  local handle = io.open(path, "w")
  if not handle then
    return false
  end

  handle:write(value)
  handle:close()
  return true
end

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end

  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function json_escape(text)
  return tostring(text or "")
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
    :gsub("\t", "\\t")
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(input)
  local data = tostring(input or "")
  local output = {}
  local index = 1

  while index <= #data do
    local byte1 = data:byte(index) or 0
    local byte2 = data:byte(index + 1)
    local byte3 = data:byte(index + 2)
    local chunk = byte1 * 65536 + (byte2 or 0) * 256 + (byte3 or 0)

    local char1 = math.floor(chunk / 262144) % 64 + 1
    local char2 = math.floor(chunk / 4096) % 64 + 1
    local char3 = math.floor(chunk / 64) % 64 + 1
    local char4 = chunk % 64 + 1

    output[#output + 1] = BASE64_ALPHABET:sub(char1, char1)
    output[#output + 1] = BASE64_ALPHABET:sub(char2, char2)
    output[#output + 1] = byte2 and BASE64_ALPHABET:sub(char3, char3) or "="
    output[#output + 1] = byte3 and BASE64_ALPHABET:sub(char4, char4) or "="

    index = index + 3
  end

  return table.concat(output)
end

local function truncate_for_trace(text, max_len)
  local rendered = tostring(text or "")
  local limit = tonumber(max_len) or 240
  if #rendered <= limit then
    return rendered
  end

  return rendered:sub(1, limit) .. "...(truncated)"
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

local function load_count()
  local raw = read_file(STATE_PATH)
  local parsed = tonumber(raw)
  state.count = math.max(0, math.floor(parsed or 0))
  trace("loaded persisted count=" .. tostring(state.count) .. " from " .. STATE_PATH)
end

local function save_count()
  write_file(STATE_PATH, tostring(state.count) .. "\n")
end

local function has_cached_command_context()
  if type(OmeggaHasCachedCommandContext) ~= "function" then
    return false, "helper missing"
  end

  local ok, value = pcall(OmeggaHasCachedCommandContext)
  if not ok then
    return false, tostring(value)
  end

  return value and true or false, "ok"
end

local function has_bridge_transport()
  return BRIDGE_INBOX_PATH ~= "" and BRIDGE_OUTBOX_PATH ~= "" and BRIDGE_STATUS_PATH ~= ""
end

local function refresh_bridge_ready_state()
  local status_raw = read_file(BRIDGE_STATUS_PATH) or ""
  local outbox_raw = read_file(BRIDGE_OUTBOX_PATH) or ""
  state.bridge_hello_seen = outbox_raw:find("\"method\":\"bridge.hello\"", 1, true) ~= nil
  state.bridge_ready = status_raw:find("\"state\":\"running\"", 1, true) ~= nil and state.bridge_hello_seen
  return state.bridge_ready
end

local function finish_pending_broadcast(success, detail)
  local pending = state.pending_broadcast
  if not pending then
    return
  end

  if success then
    state.count = pending.count
    save_count()
    trace(
      "broadcast #"
        .. tostring(state.count)
        .. " accepted by bridge method="
        .. tostring(pending.method or "chat.broadcast")
        .. " detail="
        .. truncate_for_trace(detail or pending.detail or "", 320)
    )
  else
    trace(
      "broadcast #"
        .. tostring(pending.count)
        .. " failed via bridge detail="
        .. truncate_for_trace(detail or pending.detail or "unknown", 320)
    )
  end

  state.pending_broadcast = nil
end

local function handle_bridge_outbox_line(line)
  if type(line) ~= "string" or line == "" then
    return
  end

  if line:find("\"method\":\"bridge.hello\"", 1, true) then
    if not state.bridge_hello_seen then
      trace("observed bridge hello on shared outbox")
    end
    state.bridge_hello_seen = true
    return
  end

  local pending = state.pending_broadcast
  if not pending then
    return
  end

  local response_id = tonumber(line:match("\"id\":(%d+)"))
  if response_id and response_id == pending.id then
    if line:find("\"accepted\":true", 1, true) then
      pending.accepted = true
      pending.detail = line:match("\"executor\":\"([^\"]+)\"") or "accepted"
    else
      pending.detail = line:match("\"message\":\"([^\"]*)\"")
        or line:match("\"data\":\"([^\"]*)\"")
        or pending.detail
    end
    return
  end

  local request_id = tonumber(line:match("\"request_id\":(%d+)"))
  if not request_id or request_id ~= pending.id then
    return
  end

  local success = line:find("\"success\":true", 1, true) ~= nil
  local detail = line:match("\"executor\":\"([^\"]+)\"")
    or line:match("\"detail\":\"([^\"]*)\"")
    or line:match("\"message\":\"([^\"]*)\"")
    or pending.detail

  finish_pending_broadcast(success, detail)
end

local function process_bridge_outbox()
  if not has_bridge_transport() then
    return
  end

  refresh_bridge_ready_state()
  local contents = read_file(BRIDGE_OUTBOX_PATH) or ""
  if state.bridge_outbox_offset > #contents then
    state.bridge_outbox_offset = 0
  end

  if #contents <= state.bridge_outbox_offset then
    return
  end

  local next_chunk = contents:sub(state.bridge_outbox_offset + 1)
  state.bridge_outbox_offset = #contents
  for line in next_chunk:gmatch("[^\r\n]+") do
    handle_bridge_outbox_line(line)
  end
end

local function submit_bridge_broadcast_request()
  if not has_bridge_transport() then
    trace("broadcast skipped because bridge inbox/outbox/status paths are unavailable")
    return false
  end

  if state.pending_broadcast then
    return false
  end

  local next_count = state.count + 1
  local message = string.format("[%s] broadcast #%d", MOD_NAME, next_count)
  local request_id = state.bridge_next_request_id
  state.bridge_next_request_id = state.bridge_next_request_id + 1

  local payload = string.format(
    "{\"jsonrpc\":\"2.0\",\"id\":%d,\"method\":\"chat.broadcast\",\"params\":{\"message_b64\":\"%s\"}}\n",
    request_id,
    base64_encode(message)
  )

  local appended = append_file(BRIDGE_INBOX_PATH, payload)
  if not appended then
    trace("failed to append bridge request for broadcast #" .. tostring(next_count))
    return false
  end

  state.pending_broadcast = {
    id = request_id,
    count = next_count,
    message = message,
    method = "chat.broadcast",
    requested_at = os.time(),
    detail = "",
  }
  trace(
    "submitted bridge chat.broadcast request id="
      .. tostring(request_id)
      .. " message="
      .. message
  )
  return true
end

local function maybe_start_counter_broadcasts()
  if state.started then
    return true
  end

  state.start_attempts = state.start_attempts + 1
  if not has_bridge_transport() then
    if state.start_attempts <= 5 or state.start_attempts % 20 == 0 then
      trace("waiting for bridge transport paths attempt=" .. tostring(state.start_attempts))
    end
    return true
  end

  local bridge_ready = refresh_bridge_ready_state()
  local has_context, detail = has_cached_command_context()
  if not bridge_ready or not has_context then
    if state.start_attempts <= 5 or state.start_attempts % 20 == 0 then
      trace(
        "waiting for bridge/context readiness attempt="
          .. tostring(state.start_attempts)
          .. " bridge_ready="
          .. tostring(bridge_ready)
          .. " detail="
          .. tostring(detail)
      )
    end
    return true
  end

  load_count()
  state.started = true
  state.remaining_ms = 0
  trace(
    "counter broadcast bridge/context ready interval_ms="
      .. tostring(INTERVAL_MS)
      .. " poll_interval_ms="
      .. tostring(POLL_INTERVAL_MS)
      .. " start_delay_ms="
      .. tostring(START_DELAY_MS)
  )
  state.remaining_ms = START_DELAY_MS
  trace("counter broadcast waiting through startup grace period before first send")
  return true
end

local function run_poll_cycle()
  process_bridge_outbox()

  if not maybe_start_counter_broadcasts() then
    return true
  end

  if not state.started then
    return true
  end

  if state.pending_broadcast and os.time() - (state.pending_broadcast.requested_at or os.time()) >= 15 then
    finish_pending_broadcast(false, "bridge response timeout")
  end

  if state.pending_broadcast then
    return true
  end

  state.remaining_ms = state.remaining_ms - POLL_INTERVAL_MS
  if state.remaining_ms > 0 then
    return true
  end

  state.remaining_ms = INTERVAL_MS
  local sent = submit_bridge_broadcast_request()
  if not sent then
    trace("bridge broadcast request did not submit; will retry")
  end
  return true
end

local function start_poll_loop()
  local callback_key = "counter_broadcast_poll"

  local function loop_callback()
    return retain_callback(callback_key, function()
      local ok, keep_running_or_error = pcall(run_poll_cycle)
      if not ok then
        trace("counter broadcast poller crashed: " .. tostring(keep_running_or_error))
        return true
      end

      return keep_running_or_error == false
    end)
  end

  if type(LoopAsync) == "function" then
    LoopAsync(POLL_INTERVAL_MS, loop_callback())
    trace("started counter broadcast poller via LoopAsync poll_interval_ms=" .. tostring(POLL_INTERVAL_MS))
    return true
  end

  if type(LoopInGameThreadAfterFrames) == "function" then
    local frames = math.max(1, math.floor(POLL_INTERVAL_MS / 100))
    LoopInGameThreadAfterFrames(frames, loop_callback())
    trace(
      "started counter broadcast poller via LoopInGameThreadAfterFrames poll_interval_ms="
        .. tostring(POLL_INTERVAL_MS)
        .. " frames="
        .. tostring(frames)
    )
    return true
  end

  if type(LoopInGameThreadWithDelay) == "function" then
    LoopInGameThreadWithDelay(POLL_INTERVAL_MS, loop_callback())
    trace("started counter broadcast poller via LoopInGameThreadWithDelay poll_interval_ms=" .. tostring(POLL_INTERVAL_MS))
    return true
  end

  trace("failed to start counter broadcast poller: no supported repeating scheduler")
  return false
end

ensure_parent(STATE_PATH)
ensure_parent(TRACE_PATH)

trace(
  "script loaded; state_path="
    .. STATE_PATH
    .. " trace_path="
    .. TRACE_PATH
    .. " bridge_inbox_path="
    .. tostring(BRIDGE_INBOX_PATH)
    .. " bridge_outbox_path="
    .. tostring(BRIDGE_OUTBOX_PATH)
)
start_poll_loop()
