# Bridge API

Low-level bridge interface for sending commands into a Windows Brickadia
dedicated server through Omegga and UE4SS.

Status: `Available`, `Internal`, `Unsafe`

Normal plugins should use the high-level prefab API once it exists. This page
documents the current bridge because it is the working path for prefab loading
today.

## Transport

The bridge uses newline-delimited JSON files in a session directory:

| File | Direction | Description |
| --- | --- | --- |
| `inbox.ndjson` | Host to server | Requests written by Node/Omegga/test scripts. |
| `outbox.ndjson` | Server to host | Results, console chunks, completion messages, and bridge logs. |
| `status.json` | Server status | Bridge readiness and session state. |

The test server on port `7799` commonly uses:

```text
C:/Users/tycox/OneDrive/Documents/GitHub/Brickadia/omegga-master/omegga-master/data/ue4ss-bridge-test-7799
```

## Request Shape

Requests use JSON-RPC-style envelopes:

```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "method": "console.exec",
  "params": {
    "command_raw": "Omegga.Bridge.Echo"
  },
  "command_raw": "Omegga.Bridge.Echo"
}
```

The helper script duplicates parameter fields onto the top-level request for
compatibility with the current Lua bridge parser.

## `console.exec`

Executes a console command inside the server process.

Status: `Available`, `Unsafe`

### Parameters

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `command_raw` | `string` | No | Plain-text command. Used by the test helper. |
| `command_b64` | `string` | No | Base64-encoded command. Preferred when callers need exact transport safety. |

One of `command_raw` or `command_b64` is required.

### Example

```powershell
node .\scripts\send-bridge-rpc.js `
  --dir "C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-bridge-test-7799" `
  --method console.exec `
  --command-raw "Omegga.Bridge.Echo" `
  --wait-ms 15000
```

### Response Events

`console.exec` may produce several outbox entries:

| Event | Description |
| --- | --- |
| `result` | Initial JSON-RPC response for the request. |
| `console.chunk` | Partial output for the command. |
| `console.complete` | Command completion metadata. |
| `bridge.log` | Bridge diagnostic log entry. |

## `Omegga.Bridge.Echo`

Bridge self-test command.

Status: `Available`

### Example

```text
Omegga.Bridge.Echo
```

Expected output:

```text
Omegga bridge self-test ok
```

## `Omegga.Bridge.BMF`

Queues a BMF framework command for the BMF runtime command worker.

Status: `Available`, `Experimental`

### Example

```text
Omegga.Bridge.BMF bmf.status
```

The bridge writes a request under `ue4ss/main/Mods/BMF/runtime/commands` and
returns the request id plus expected response path as `console.chunk` output.
BMF writes the final command output to the matching `.response.txt` file.

## `Omegga.Bridge.DescribeConsoleManager`

Returns diagnostic information for the console manager executor.

Status: `Available`, `Internal`

### Example

```text
Omegga.Bridge.DescribeConsoleManager
```

### Healthy Output

The exact pointer values change per process, but a healthy result should include
non-null values for:

- `initializer`
- `slot`
- `singleton`
- `world`
- `process_input`

The `vtable_offset` should currently be:

```text
0xe0
```

## `Omegga.Bridge.ForceConsoleExecutor`

Routes a command through a specific server-side console executor.

Status: `Available`, `Internal`, `Unsafe`

### Syntax

```text
Omegga.Bridge.ForceConsoleExecutor <executor> <command...>
```

### Executors

| Executor | Status | Notes |
| --- | --- | --- |
| `consolemanager` | Known good | Required for `BR.World.LoadAdditive` in current tests. |
| `engine` | Available | Uses cached `UEngine::Exec` context. |
| `cached` | Available | Uses cached `ProcessConsoleExec` context. |
| `kismet` | Available | Uses `UKismetSystemLibrary::ExecuteConsoleCommand`. |

### Prefab Load Example

```text
Omegga.Bridge.ForceConsoleExecutor consolemanager BR.World.LoadAdditive PrefabBridge_ClipboardDynamic 2000 0 300 16
```

This is the current low-level equivalent of the proposed
`Omegga.Prefabs.LoadWorld(...)` API.

## Native Lua Globals

These functions are registered by the UE4SS C++ layer.

| Function | Status | Description |
| --- | --- | --- |
| `OmeggaExecuteConsoleManagerInput(command, vtableOffset)` | Available, Unsafe | Calls `IConsoleManager::ProcessUserConsoleInput`. |
| `OmeggaDescribeConsoleManager()` | Available, Internal | Returns console manager pointer diagnostics. |
| `OmeggaExecuteCachedEngineExec(command)` | Available, Unsafe | Calls cached engine exec path. |
| `OmeggaExecuteCachedConsoleExec(command)` | Available, Unsafe | Calls cached console exec path. |
| `OmeggaExecuteKismetConsoleCommand(command)` | Available, Unsafe | Calls Kismet console command helper. |

Do not expose these directly to normal plugin authors. They are implementation
details for the high-level API.

## Safety Notes

- `OmeggaExecuteConsoleManagerInput` assumes a valid console manager singleton,
  a valid `UWorld*`, and a matching vtable offset.
- The current `ProcessUserConsoleInput` vtable offset is `0xE0`, but it must be
  rechecked after game updates.
- Missing staged world files can poison Brickadia's bundle cache until restart.
- Repeated additive loads duplicate objects and can overlap physics bodies.
