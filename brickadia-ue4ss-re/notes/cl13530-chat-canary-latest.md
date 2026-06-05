# CL13530 Chat Canary Report

## Summary

- Total: `19`
- Passed: `16`
- Failed: `0`
- Blocked: `3`

## Chat Probe Foundation

- Total: `7`
- Passed: `6`
- Failed: `0`
- Blocked: `1`

- [PASSED] `chat-proof-output-exists`: BaselineChatProof wrote an output report
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-output-parses`: BaselineChatProof output parses as JSONL
  - All chat proof lines parsed successfully.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-startup`: BaselineChatProof startup marker was recorded
  - C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-game-thread-scheduler`: A game-thread scheduler is available for chat probes
  - ExecuteInGameThread=True; ExecuteInGameThreadWithDelay=True; ExecuteInGameThreadAfterFrames=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-helper-capabilities`: The minimum chat helper surface is available
  - HasCachedCommandContext=True; ExecuteKismetConsoleCommand=True; ExecuteCachedEngineExec=True; ExecuteCachedConsoleExec=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-initgamestate-hook`: InitGameState fired during the chat proof session
  - Observed 1 InitGameState hook event(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [BLOCKED] `chat-proof-beginplay-hook`: BeginPlay fired during the chat proof session
  - RegisterBeginPlayPostHook did not fire during the short headless proof session, so this remains characterization only rather than a chat blocker.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`

## Console Broadcast Canaries

- Total: `8`
- Passed: `6`
- Failed: `0`
- Blocked: `2`

- [PASSED] `chat-proof-cached-command-context`: A cached command context becomes available during the chat proof
  - Observed cached command context in 4 context snapshot(s).
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-nonchat-console-probe`: A non-chat console command succeeds through the managed helpers
  - Successful executor(s): cached_console_exec, kismet_console_command
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-broadcast-console-canary`: At least one console broadcast canary succeeds
  - Successful executor(s): kismet_console_command
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-broadcast-repeat-canary`: Two console broadcast canaries succeed in one session
  - Successful broadcast commands: Chat.Broadcast Hello from BaselineChatProof #1, Chat.Broadcast Hello from BaselineChatProof #2
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [BLOCKED] `chat-proof-processconsoleexec-intercept`: The current chat broadcast path is observable via ProcessConsoleExec hooks
  - A broadcast succeeded, and the live counter demo confirms the visible path is now typed/native, so bypassing ProcessConsoleExec is treated as expected characterization.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-native-broadcast-canary`: A native typed-chat broadcast canary is ready to run
  - Stage 3 object-resolution validation is passing, so the direct typed-chat canary can become active.
  - Evidence: `validation-report.json`
- [BLOCKED] `chat-player-intercept-live-stimulus`: A live player-chat stimulus was present to test interception
  - The standalone chat proof session does not inject a real player chat message yet, so player-chat interception remains a later canary.
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`
- [PASSED] `chat-proof-broadcast-rounds-finished`: The scheduled chat broadcast rounds completed
  - Completed round(s): 1, 2
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\probes\CL13530\output\baseline-chat-proof.jsonl`

## Native Broadcast Demo

- Total: `4`
- Passed: `4`
- Failed: `0`
- Blocked: `0`

- [PASSED] `chat-demo-live-evidence-exists`: CounterBroadcastDemo captured live native chat evidence
  - mod.log=C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\mod.log; chat-trace.log=C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log`
- [PASSED] `chat-native-visible-delivery-canary`: A live native typed-chat delivery path was observed
  - Observed typed/native delivery via PushChatMessage; latest route=PushChatMessage
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log`
- [PASSED] `chat-native-broadcast-all-clients`: The current native chat path is server-wide across connected players
  - Observed server-wide chat function(s): PushChatMessage
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-counter-broadcast-demo\chat-trace.log`
- [PASSED] `chat-demo-live-session-metadata`: CounterBroadcastDemo recorded live session metadata
  - connect_address=127.0.0.1:7777; verified=True
  - Evidence: `C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\counter-broadcast-demo-live.json`
