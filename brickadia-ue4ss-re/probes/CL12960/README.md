# CL12960 Probes

This directory holds standalone proof mods and helper assets for the `CL12960` compatibility baseline.

The first proof target is `BaselineObjectProof`. It is intentionally separate from the Omegga bridge and only checks:

- `RegisterLoadMapPostHook`
- `RegisterInitGameStatePostHook`
- `RegisterBeginPlayPostHook`
- `FindFirstOf("GameEngine")`
- `StaticFindObject("/Script/CoreUObject.Default__Object")`
- `GetFullName()` on hook-returned and lookup-returned objects

Use `scripts/deploy-proof-mod.ps1` to copy it into the live UE4SS runtime without touching Omegga code.

The second proof target is `BaselineChatProof`. It stays on the safer console-broadcast lane first and checks:

- `RegisterInitGameStatePostHook`
- `RegisterBeginPlayPostHook`
- cached chat/console helper availability
- cached command-context availability after `InitGameState`
- non-chat helper execution via `Server.Status`
- repeated `Chat.Broadcast ...` canaries through the managed helpers
- whether the working broadcast path is visible to `ProcessConsoleExec` hooks

Use `scripts/deploy-chat-proof-mod.ps1` to copy it into the live UE4SS runtime and
`scripts/run-cl12960-chat-canary-tests.ps1` to generate the latest chat-canary report.

The third proof target is `WorldExportContextProof`. It stays standalone like the object proof and checks:

- `RegisterInitGameStatePostHook`
- live `UWorld` / `PersistentLevel` / `GameMode` / `GameState` / `GameSession` resolution
- runtime brick-count style properties such as `NumBricks` / `BrickCount`
- keyword-only property discovery on the core world objects for hints like `brick`, `grid`, `owner`, and `component`
- `FindAllOf(...)` scans against a small candidate list of export-relevant runtime classes

Use `scripts/deploy-world-export-context-proof-mod.ps1` to copy it into the live UE4SS runtime and
`scripts/run-cl12960-world-export-canary-tests.ps1` to generate the latest world-export canary report.
