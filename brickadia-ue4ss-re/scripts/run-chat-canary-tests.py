import argparse
import json
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class TestResult:
    id: str
    name: str
    status: str
    details: str
    evidence: str | None = None


def summarize(results: list[TestResult]) -> dict:
    summary = {"total": len(results), "passed": 0, "failed": 0, "blocked": 0}
    for result in results:
        if result.status == "passed":
            summary["passed"] += 1
        elif result.status == "failed":
            summary["failed"] += 1
        elif result.status == "blocked":
            summary["blocked"] += 1
    return summary


def emit(section_id: str, name: str, tests: list[TestResult]) -> dict:
    return {
        "id": section_id,
        "name": name,
        "summary": summarize(tests),
        "tests": [asdict(test) for test in tests],
    }


def parse_args():
    parser = argparse.ArgumentParser(description="Render chat canary tests for CL12960.")
    parser.add_argument("--workspace", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--bundle", default="CL12960")
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--write-json")
    parser.add_argument("--write-md")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if any test fails.")
    return parser.parse_args()


def read_json_file(path: Path):
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "utf-16-le", "utf-16-be"):
        try:
            return json.loads(raw.decode(encoding))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    return json.loads(path.read_text(encoding="utf-8", errors="strict"))


def entries_of_kind(entries: list[dict], kind: str) -> list[dict]:
    return [entry for entry in entries if entry.get("kind") == kind]


def latest_of_kind(entries: list[dict], kind: str) -> dict | None:
    matches = entries_of_kind(entries, kind)
    return matches[-1] if matches else None


def bool_field(payload: dict | None, key: str) -> bool:
    return bool(payload and payload.get(key))


def typed_chat_function_names(evidence: dict) -> list[str]:
    counter_demo = evidence.get("counter_broadcast_demo", {})
    mod_log = counter_demo.get("mod_log", {})
    chat_trace = counter_demo.get("chat_trace", {})

    names: set[str] = set()
    for accepted in mod_log.get("accepted_requests", []):
        detail = str(accepted.get("detail", ""))
        if detail.startswith("typed-chat-fast-call-by-name:") and "->" in detail:
            names.add(detail.rsplit("->", 1)[-1].strip())

    for success in chat_trace.get("typed_successes", []):
        function_name = str(success.get("function_name", "")).strip()
        if function_name:
            names.add(function_name)

    return sorted(names)


def latest_typed_chat_function_name(evidence: dict) -> str | None:
    counter_demo = evidence.get("counter_broadcast_demo", {})
    chat_trace = counter_demo.get("chat_trace", {})
    mod_log = counter_demo.get("mod_log", {})

    typed_successes = chat_trace.get("typed_successes", [])
    if typed_successes:
        function_name = str(typed_successes[-1].get("function_name", "")).strip()
        return function_name or None

    accepted_requests = mod_log.get("accepted_requests", [])
    for accepted in reversed(accepted_requests):
        detail = str(accepted.get("detail", ""))
        if detail.startswith("typed-chat-fast-call-by-name:") and "->" in detail:
            function_name = detail.rsplit("->", 1)[-1].strip()
            return function_name or None

    return None


def has_typed_chat_success(evidence: dict) -> bool:
    counter_demo = evidence.get("counter_broadcast_demo", {})
    mod_log = counter_demo.get("mod_log", {})
    chat_trace = counter_demo.get("chat_trace", {})
    return bool(mod_log.get("accepted_requests") or chat_trace.get("typed_successes"))


def build_probe_foundation_tests(evidence: dict) -> list[TestResult]:
    tests: list[TestResult] = []
    chat_proof = evidence.get("chat_proof", {})
    proof_path = chat_proof.get("path")
    entries = chat_proof.get("entries", [])
    parse_errors = chat_proof.get("parse_errors", [])

    startup = latest_of_kind(entries, "startup")
    scheduler = latest_of_kind(entries, "scheduler_capabilities")
    helpers = latest_of_kind(entries, "helper_capabilities")
    hook_events = entries_of_kind(entries, "hook_event")

    tests.append(
        TestResult(
            id="chat-proof-output-exists",
            name="BaselineChatProof wrote an output report",
            status="passed" if chat_proof.get("exists") else "failed",
            details=proof_path if chat_proof.get("exists") else f"Missing chat proof output: {proof_path}",
            evidence=proof_path,
        )
    )

    tests.append(
        TestResult(
            id="chat-proof-output-parses",
            name="BaselineChatProof output parses as JSONL",
            status="passed" if chat_proof.get("exists") and not parse_errors else "failed",
            details="All chat proof lines parsed successfully."
            if chat_proof.get("exists") and not parse_errors
            else "Parse errors: " + "; ".join(
                f"line {item.get('line')}: {item.get('error')}" for item in parse_errors
            )
            if parse_errors
            else "Chat proof output file does not exist.",
            evidence=proof_path,
        )
    )

    tests.append(
        TestResult(
            id="chat-proof-startup",
            name="BaselineChatProof startup marker was recorded",
            status="passed" if startup and startup.get("success") else "failed",
            details=startup.get("out_path")
            if startup and startup.get("success")
            else "No successful startup record was found in the chat proof output.",
            evidence=proof_path,
        )
    )

    game_thread_scheduler_present = any(
        bool_field(scheduler, key)
        for key in (
            "execute_in_game_thread",
            "execute_in_game_thread_with_delay",
            "execute_in_game_thread_after_frames",
        )
    )
    tests.append(
        TestResult(
            id="chat-proof-game-thread-scheduler",
            name="A game-thread scheduler is available for chat probes",
            status="passed" if game_thread_scheduler_present else "failed",
            details=(
                "ExecuteInGameThread="
                f"{bool_field(scheduler, 'execute_in_game_thread')}; "
                "ExecuteInGameThreadWithDelay="
                f"{bool_field(scheduler, 'execute_in_game_thread_with_delay')}; "
                "ExecuteInGameThreadAfterFrames="
                f"{bool_field(scheduler, 'execute_in_game_thread_after_frames')}"
            )
            if scheduler
            else "No scheduler_capabilities record was found.",
            evidence=proof_path,
        )
    )

    required_helpers_present = (
        bool_field(helpers, "omegga_has_cached_command_context")
        and bool_field(helpers, "omegga_execute_kismet_console_command")
    )
    tests.append(
        TestResult(
            id="chat-proof-helper-capabilities",
            name="The minimum chat helper surface is available",
            status="passed" if required_helpers_present else "failed",
            details=(
                "HasCachedCommandContext="
                f"{bool_field(helpers, 'omegga_has_cached_command_context')}; "
                "ExecuteKismetConsoleCommand="
                f"{bool_field(helpers, 'omegga_execute_kismet_console_command')}; "
                "ExecuteCachedEngineExec="
                f"{bool_field(helpers, 'omegga_execute_cached_engine_exec')}; "
                "ExecuteCachedConsoleExec="
                f"{bool_field(helpers, 'omegga_execute_cached_console_exec')}"
            )
            if helpers
            else "No helper_capabilities record was found.",
            evidence=proof_path,
        )
    )

    init_hooks = [event for event in hook_events if event.get("hook") == "RegisterInitGameStatePostHook"]
    beginplay_hooks = [event for event in hook_events if event.get("hook") == "RegisterBeginPlayPostHook"]

    tests.append(
        TestResult(
            id="chat-proof-initgamestate-hook",
            name="InitGameState fired during the chat proof session",
            status="passed" if init_hooks else "failed",
            details=f"Observed {len(init_hooks)} InitGameState hook event(s)."
            if init_hooks
            else "RegisterInitGameStatePostHook did not fire during the proof session.",
            evidence=proof_path,
        )
    )

    tests.append(
        TestResult(
            id="chat-proof-beginplay-hook",
            name="BeginPlay fired during the chat proof session",
            status="passed" if beginplay_hooks else "blocked",
            details=f"Observed {len(beginplay_hooks)} BeginPlay hook event(s)."
            if beginplay_hooks
            else (
                "RegisterBeginPlayPostHook did not fire during the short headless proof session, "
                "so this remains characterization only rather than a chat blocker."
            ),
            evidence=proof_path,
        )
    )

    return tests


def build_console_broadcast_tests(evidence: dict, validation_report: dict) -> list[TestResult]:
    tests: list[TestResult] = []
    chat_proof = evidence.get("chat_proof", {})
    proof_path = chat_proof.get("path")
    entries = chat_proof.get("entries", [])
    stages = validation_report.get("stages", {})

    context_snapshots = entries_of_kind(entries, "context_snapshot")
    command_attempts = entries_of_kind(entries, "command_attempt")
    broadcast_attempts = entries_of_kind(entries, "broadcast_attempt")
    broadcast_rounds = entries_of_kind(entries, "broadcast_round_complete")
    process_console_events = entries_of_kind(entries, "process_console_exec_observed")

    cached_context_hits = [
        snapshot for snapshot in context_snapshots if snapshot.get("has_cached_command_context") is True
    ]
    tests.append(
        TestResult(
            id="chat-proof-cached-command-context",
            name="A cached command context becomes available during the chat proof",
            status="passed" if cached_context_hits else "failed",
            details=(
                f"Observed cached command context in {len(cached_context_hits)} context snapshot(s)."
            )
            if cached_context_hits
            else "No context_snapshot recorded has_cached_command_context=true.",
            evidence=proof_path,
        )
    )

    nonchat_successes = [attempt for attempt in command_attempts if attempt.get("success") is True]
    tests.append(
        TestResult(
            id="chat-proof-nonchat-console-probe",
            name="A non-chat console command succeeds through the managed helpers",
            status="passed" if nonchat_successes else "failed",
            details=(
                "Successful executor(s): "
                + ", ".join(sorted({attempt.get("executor", "unknown") for attempt in nonchat_successes}))
            )
            if nonchat_successes
            else "No command_attempt entry reported success=true.",
            evidence=proof_path,
        )
    )

    successful_broadcasts = [attempt for attempt in broadcast_attempts if attempt.get("success") is True]
    tests.append(
        TestResult(
            id="chat-proof-broadcast-console-canary",
            name="At least one console broadcast canary succeeds",
            status="passed" if successful_broadcasts else "failed",
            details=(
                "Successful executor(s): "
                + ", ".join(sorted({attempt.get("executor", "unknown") for attempt in successful_broadcasts}))
            )
            if successful_broadcasts
            else "No broadcast_attempt entry reported success=true.",
            evidence=proof_path,
        )
    )

    unique_successful_commands = sorted({attempt.get("command") for attempt in successful_broadcasts if attempt.get("command")})
    tests.append(
        TestResult(
            id="chat-proof-broadcast-repeat-canary",
            name="Two console broadcast canaries succeed in one session",
            status="passed" if len(unique_successful_commands) >= 2 else "failed",
            details=(
                f"Successful broadcast commands: {', '.join(unique_successful_commands)}"
            )
            if unique_successful_commands
            else "No successful broadcast command was recorded.",
            evidence=proof_path,
        )
    )

    typed_chat_confirmed = has_typed_chat_success(evidence)
    if process_console_events:
        process_status = "passed"
        process_details = (
            f"Observed {len(process_console_events)} Chat.* ProcessConsoleExec hook event(s)."
        )
    elif successful_broadcasts and typed_chat_confirmed:
        process_status = "blocked"
        process_details = (
            "A broadcast succeeded, and the live counter demo confirms the visible path is now "
            "typed/native, so bypassing ProcessConsoleExec is treated as expected characterization."
        )
    elif successful_broadcasts:
        process_status = "failed"
        process_details = (
            "A broadcast succeeded, but no Chat.* ProcessConsoleExec hook event was observed. "
            "This suggests the current working path bypasses that interception surface."
        )
    else:
        process_status = "blocked"
        process_details = (
            "No successful broadcast was recorded yet, so the ProcessConsoleExec interception signal stays inconclusive."
        )
    tests.append(
        TestResult(
            id="chat-proof-processconsoleexec-intercept",
            name="The current chat broadcast path is observable via ProcessConsoleExec hooks",
            status=process_status,
            details=process_details,
            evidence=proof_path,
        )
    )

    stage3 = stages.get("stage3_object_resolution", {})
    tests.append(
        TestResult(
            id="chat-native-broadcast-canary",
            name="A native typed-chat broadcast canary is ready to run",
            status="passed" if stage3.get("status") == "passed" else "blocked",
            details="Stage 3 object-resolution validation is passing, so the direct typed-chat canary can become active."
            if stage3.get("status") == "passed"
            else (
                "Stage 3 object-resolution is still failing, so direct typed-chat calls remain intentionally deferred. "
                + "; ".join(stage3.get("notes", []))
            ),
            evidence="validation-report.json",
        )
    )

    tests.append(
        TestResult(
            id="chat-player-intercept-live-stimulus",
            name="A live player-chat stimulus was present to test interception",
            status="blocked",
            details=(
                "The standalone chat proof session does not inject a real player chat message yet, so player-chat "
                "interception remains a later canary."
            ),
            evidence=proof_path,
        )
    )

    tests.append(
        TestResult(
            id="chat-proof-broadcast-rounds-finished",
            name="The scheduled chat broadcast rounds completed",
            status="passed" if broadcast_rounds else "failed",
            details=(
                "Completed round(s): "
                + ", ".join(str(round_entry.get("sequence")) for round_entry in broadcast_rounds)
            )
            if broadcast_rounds
            else "No broadcast_round_complete marker was recorded.",
            evidence=proof_path,
        )
    )

    return tests


def build_native_broadcast_demo_tests(evidence: dict) -> list[TestResult]:
    tests: list[TestResult] = []
    counter_demo = evidence.get("counter_broadcast_demo", {})
    mod_log = counter_demo.get("mod_log", {})
    chat_trace = counter_demo.get("chat_trace", {})
    live_info = counter_demo.get("live_info", {})

    mod_log_path = mod_log.get("path")
    chat_trace_path = chat_trace.get("path")
    typed_successes = chat_trace.get("typed_successes", [])
    accepted_requests = mod_log.get("accepted_requests", [])
    function_names = typed_chat_function_names(evidence)
    latest_function_name = latest_typed_chat_function_name(evidence)
    typed_details = [
        accepted for accepted in accepted_requests if str(accepted.get("detail", "")).startswith("typed-chat-fast-call-by-name:")
    ]

    tests.append(
        TestResult(
            id="chat-demo-live-evidence-exists",
            name="CounterBroadcastDemo captured live native chat evidence",
            status="passed" if mod_log.get("exists") and chat_trace.get("exists") else "blocked",
            details=(
                f"mod.log={mod_log_path}; chat-trace.log={chat_trace_path}"
            )
            if mod_log.get("exists") and chat_trace.get("exists")
            else (
                "The counter broadcast demo logs are not both present yet, so live native chat "
                "coverage remains unavailable."
            ),
            evidence=chat_trace_path or mod_log_path,
        )
    )

    tests.append(
        TestResult(
            id="chat-native-visible-delivery-canary",
            name="A live native typed-chat delivery path was observed",
            status="passed" if typed_successes or typed_details else "failed",
            details=(
                "Observed typed/native delivery via "
                + ", ".join(function_names)
                + (
                    f"; latest route={latest_function_name}"
                    if latest_function_name
                    else ""
                )
            )
            if function_names
            else (
                "No typed/native chat delivery success was parsed from the counter demo logs."
            ),
            evidence=chat_trace_path or mod_log_path,
        )
    )

    has_serverwide_path = bool(latest_function_name) and (
        latest_function_name.startswith("Multicast")
        or latest_function_name.startswith("ServerPush")
        or latest_function_name == "PushChatMessage"
    )
    has_client_only_path = bool(latest_function_name) and latest_function_name.startswith("Client")
    tests.append(
        TestResult(
            id="chat-native-broadcast-all-clients",
            name="The current native chat path is server-wide across connected players",
            status="passed"
            if has_serverwide_path
            else "failed"
            if has_client_only_path
            else "blocked",
            details=(
                "Observed server-wide chat function(s): " + ", ".join(function_names)
            )
            if has_serverwide_path
            else (
                "Latest live route is client-targeted: "
                + str(latest_function_name)
                + "; observed history="
                + ", ".join(function_names)
                + ". This matches the current symptom where one player can see the message and another cannot."
            )
            if has_client_only_path
            else (
                "No classified current server-wide or client-targeted typed chat function was observed yet."
            ),
            evidence=chat_trace_path or mod_log_path,
        )
    )

    live_payload = live_info.get("payload")
    tests.append(
        TestResult(
            id="chat-demo-live-session-metadata",
            name="CounterBroadcastDemo recorded live session metadata",
            status="passed" if live_payload and live_info.get("parse_error") is None else "blocked",
            details=(
                "connect_address="
                + str(live_payload.get("connect_address"))
                + "; verified="
                + str(live_payload.get("verified"))
            )
            if live_payload and live_info.get("parse_error") is None
            else (
                "The counter broadcast demo live-session metadata is missing or failed to parse."
            ),
            evidence=live_info.get("path"),
        )
    )

    return tests


def render_markdown(report: dict) -> str:
    lines = [
        f"# {report['bundle_id']} Chat Canary Report",
        "",
        "## Summary",
        "",
        f"- Total: `{report['summary']['total']}`",
        f"- Passed: `{report['summary']['passed']}`",
        f"- Failed: `{report['summary']['failed']}`",
        f"- Blocked: `{report['summary']['blocked']}`",
        "",
    ]

    for section in report["sections"]:
        lines.extend(
            [
                f"## {section['name']}",
                "",
                f"- Total: `{section['summary']['total']}`",
                f"- Passed: `{section['summary']['passed']}`",
                f"- Failed: `{section['summary']['failed']}`",
                f"- Blocked: `{section['summary']['blocked']}`",
                "",
            ]
        )
        for test in section["tests"]:
            status = test["status"].upper()
            lines.append(f"- [{status}] `{test['id']}`: {test['name']}")
            lines.append(f"  - {test['details']}")
            if test.get("evidence"):
                lines.append(f"  - Evidence: `{test['evidence']}`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    args = parse_args()
    workspace = Path(args.workspace)
    bundle_root = workspace / "bundles" / args.bundle
    evidence_path = Path(args.evidence)
    validation_report_path = bundle_root / "validation-report.json"

    evidence = read_json_file(evidence_path)
    validation_report = read_json_file(validation_report_path) if validation_report_path.exists() else {}

    sections = [
        emit("chat-probe-foundation", "Chat Probe Foundation", build_probe_foundation_tests(evidence)),
        emit("console-broadcast-canaries", "Console Broadcast Canaries", build_console_broadcast_tests(evidence, validation_report)),
        emit("native-broadcast-demo", "Native Broadcast Demo", build_native_broadcast_demo_tests(evidence)),
    ]

    overall_results = []
    for section in sections:
        for test in section["tests"]:
            overall_results.append(TestResult(**test))

    report = {
        "bundle_id": args.bundle,
        "workspace_root": str(workspace),
        "bundle_root": str(bundle_root),
        "evidence_path": str(evidence_path),
        "summary": summarize(overall_results),
        "sections": sections,
    }

    if args.write_json:
        Path(args.write_json).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    markdown = render_markdown(report)
    if args.write_md:
        Path(args.write_md).write_text(markdown, encoding="utf-8")

    print(json.dumps(report, indent=2))
    if args.strict and report["summary"]["failed"] > 0:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
