import argparse
import json
from collections import Counter
from dataclasses import asdict, dataclass
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
    parser = argparse.ArgumentParser(description="Render world-export canary tests for CL12960.")
    parser.add_argument("--workspace", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--bundle", default="CL12960")
    parser.add_argument("--proof-output", required=True)
    parser.add_argument(
        "--server-exe",
        default=r"C:\Users\tycox\AppData\Roaming\omegga\steam_installs\main\Brickadia\Binaries\Win64\BrickadiaServer-Win64-Shipping.exe",
    )
    parser.add_argument(
        "--live-snapshot",
        default=r"C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\latest-snapshot.json",
    )
    parser.add_argument(
        "--live-history",
        default=r"C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\ue4ss-world-state-live-sampler\history.jsonl",
    )
    parser.add_argument(
        "--live-info",
        default=str(Path(__file__).resolve().parents[1] / "notes" / "world-state-live-sampler-live.json"),
    )
    parser.add_argument(
        "--brickadia-log",
        default=r"C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\omegga-master\omegga-master\data\Saved\Logs\Brickadia.log",
    )
    parser.add_argument("--write-json")
    parser.add_argument("--write-md")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if any test fails.")
    return parser.parse_args()


def read_json_lines(path: Path) -> tuple[list[dict], list[dict]]:
    entries: list[dict] = []
    parse_errors: list[dict] = []
    if not path.exists():
        return entries, parse_errors

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError as exc:
            parse_errors.append({"line": line_number, "error": str(exc)})
    return entries, parse_errors


def read_json_file(path: Path) -> dict | None:
    if not path.exists():
        return None

    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-16", "utf-16-le", "utf-16-be"):
        try:
            return json.loads(raw.decode(encoding))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue

    return json.loads(path.read_text(encoding="utf-8", errors="strict"))


def latest_of_kind(entries: list[dict], kind: str) -> dict | None:
    matches = [entry for entry in entries if entry.get("kind") == kind]
    return matches[-1] if matches else None


def entries_of_kind(entries: list[dict], kind: str) -> list[dict]:
    return [entry for entry in entries if entry.get("kind") == kind]


def latest_context(entries: list[dict], label: str) -> dict | None:
    matches = [entry for entry in entries_of_kind(entries, "context_object") if entry.get("label") == label]
    return matches[-1] if matches else None


def latest_candidate_scan(entries: list[dict], class_name: str) -> dict | None:
    matches = [
        entry
        for entry in entries_of_kind(entries, "candidate_class_scan")
        if str(entry.get("class_name") or "") == class_name
    ]
    return matches[-1] if matches else None


def read_candidate_count(entries: list[dict], class_name: str) -> int | None:
    latest = latest_candidate_scan(entries, class_name)
    if latest is None:
        return None
    return int(latest.get("count", 0) or 0)


def scan_binary_strings(path: Path, needles: list[str]) -> dict[str, list[str] | str]:
    if not path.exists():
        return {"error": f"Missing server binary: {path}", "matches": []}

    blob = path.read_bytes()
    matches: list[str] = []
    for needle in needles:
        ascii_hit = blob.find(needle.encode("ascii"))
        utf16_hit = blob.find(needle.encode("utf-16le"))
        if ascii_hit != -1 or utf16_hit != -1:
            matches.append(needle)
    return {"matches": matches}


def build_context_resolution_tests(proof_path: Path, entries: list[dict], parse_errors: list[dict]) -> list[TestResult]:
    startup = latest_of_kind(entries, "startup")
    scheduler = latest_of_kind(entries, "scheduler_capabilities")
    init_hook = next(
        (entry for entry in entries_of_kind(entries, "hook_event") if entry.get("hook") == "RegisterInitGameStatePostHook"),
        None,
    )
    runtime_counts = latest_of_kind(entries, "runtime_counts")

    tests = [
        TestResult(
            id="world-export-output-exists",
            name="WorldExportContextProof wrote an output report",
            status="passed" if proof_path.exists() else "failed",
            details=str(proof_path) if proof_path.exists() else f"Missing output: {proof_path}",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-output-parses",
            name="WorldExportContextProof output parses as JSONL",
            status="passed" if proof_path.exists() and not parse_errors else "failed",
            details="All world-export proof lines parsed successfully."
            if proof_path.exists() and not parse_errors
            else "Parse errors: "
            + "; ".join(f"line {item['line']}: {item['error']}" for item in parse_errors)
            if parse_errors
            else "World-export proof output file does not exist.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-startup",
            name="WorldExportContextProof startup marker was recorded",
            status="passed" if startup and startup.get("success") else "failed",
            details=startup.get("out_path")
            if startup and startup.get("success")
            else "No successful startup record was found in the world-export proof output.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-scheduler",
            name="A delayed game-thread scheduler is available for the export canary",
            status="passed"
            if scheduler and (scheduler.get("execute_in_game_thread_with_delay") or scheduler.get("execute_in_game_thread_after_frames"))
            else "failed",
            details=(
                "ExecuteInGameThreadWithDelay="
                f"{bool(scheduler.get('execute_in_game_thread_with_delay'))}; "
                "ExecuteInGameThreadAfterFrames="
                f"{bool(scheduler.get('execute_in_game_thread_after_frames'))}"
            )
            if scheduler
            else "No scheduler_capabilities record was found.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-initgamestate-hook",
            name="InitGameState fired during the world-export proof session",
            status="passed" if init_hook else "failed",
            details="Observed RegisterInitGameStatePostHook."
            if init_hook
            else "RegisterInitGameStatePostHook did not fire during the proof session.",
            evidence=str(proof_path),
        ),
    ]

    for label, name in (
        ("world", "The live UWorld can be resolved"),
        ("persistent_level", "The persistent level can be resolved"),
        ("game_mode", "The live game mode can be resolved"),
        ("game_state", "The live game state can be resolved"),
        ("game_session", "The live game session can be resolved"),
        ("game_instance", "The live game instance can be resolved"),
    ):
        entry = latest_context(entries, label)
        tests.append(
            TestResult(
                id=f"world-export-{label}-resolved",
                name=name,
                status="passed" if entry and entry.get("is_valid") else "failed",
                details=entry.get("object_name")
                if entry and entry.get("is_valid")
                else f"{label} did not resolve to a valid object.",
                evidence=str(proof_path),
            )
        )

    brick_count_number = runtime_counts.get("brick_count_number") if runtime_counts else None
    brick_count_property = runtime_counts.get("brick_count_property") if runtime_counts else None
    tests.append(
        TestResult(
            id="world-export-runtime-brick-count",
            name="A runtime brick count is readable from the live server state",
            status="passed" if brick_count_number is not None else "blocked",
            details=f"{brick_count_property}={brick_count_number}"
            if brick_count_number is not None
            else "No NumBricks/BrickCount property was readable in the current proof session.",
            evidence=str(proof_path),
        )
    )

    return tests


def build_discovery_lead_tests(proof_path: Path, entries: list[dict]) -> list[TestResult]:
    property_scans = entries_of_kind(entries, "property_keyword_scan")
    function_scans = entries_of_kind(entries, "function_keyword_scan")
    named_property_probes = entries_of_kind(entries, "named_property_probe")
    candidate_scans = entries_of_kind(entries, "candidate_class_scan")
    matching_scans = [entry for entry in property_scans if int(entry.get("match_count", 0) or 0) > 0]
    matching_function_scans = [entry for entry in function_scans if int(entry.get("match_count", 0) or 0) > 0]
    named_property_hits = [entry for entry in named_property_probes if int(entry.get("hit_count", 0) or 0) > 0]
    live_candidates = [
        entry
        for entry in candidate_scans
        if int(entry.get("count", 0) or 0) > 0 or bool(entry.get("find_first_success"))
    ]

    def candidate_priority(entry: dict) -> tuple[int, int, str]:
        class_name = str(entry.get("class_name") or "")
        normalized = class_name.lower()
        interesting_keywords = ("brick", "grid", "world", "bundle", "gizmo", "owner", "component", "subsystem")
        interesting_score = 0 if any(keyword in normalized for keyword in interesting_keywords) else 1
        count_score = -int(entry.get("count", 0) or 0)
        return (interesting_score, count_score, normalized)

    deduped_live_candidates: dict[str, dict] = {}
    for entry in live_candidates:
        class_name = str(entry.get("class_name") or "")
        existing = deduped_live_candidates.get(class_name)
        if existing is None:
            deduped_live_candidates[class_name] = entry
            continue

        existing_score = (int(existing.get("count", 0) or 0), bool(existing.get("find_first_success")))
        candidate_score = (int(entry.get("count", 0) or 0), bool(entry.get("find_first_success")))
        if candidate_score > existing_score:
            deduped_live_candidates[class_name] = entry

    prioritized_live_candidates = sorted(deduped_live_candidates.values(), key=candidate_priority)

    matched_labels = [str(entry.get("label")) for entry in matching_scans[:6]]
    matched_function_labels = [str(entry.get("label")) for entry in matching_function_scans[:6]]
    named_property_labels = [str(entry.get("label")) for entry in named_property_hits[:6]]
    candidate_labels = []
    for entry in prioritized_live_candidates[:10]:
        label = f"{entry.get('class_name')}={entry.get('count')}"
        if entry.get("find_first_success"):
            label += " (FindFirstOf)"
        candidate_labels.append(label)

    lead_fragments: list[str] = []
    if matching_scans:
        lead_fragments.append("property hits on " + ", ".join(matched_labels))
    if matching_function_scans:
        lead_fragments.append("function hits on " + ", ".join(matched_function_labels))
    if named_property_hits:
        lead_fragments.append("named property hits on " + ", ".join(named_property_labels))
    has_any_leads = bool(lead_fragments)

    tests = [
        TestResult(
            id="world-export-property-keyword-scan",
            name="Keyword property scans ran against the core world objects",
            status="passed" if property_scans else "failed",
            details=f"Observed {len(property_scans)} property keyword scan record(s)."
            if property_scans
            else "No property keyword scan records were written.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-function-keyword-scan",
            name="Keyword function scans ran against the core world objects",
            status="passed" if function_scans else "failed",
            details=f"Observed {len(function_scans)} function keyword scan record(s)."
            if function_scans
            else "No function keyword scan records were written.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-named-property-probe",
            name="Explicit build/export property probes ran against the core world objects",
            status="passed" if named_property_probes else "failed",
            details=f"Observed {len(named_property_probes)} named property probe record(s)."
            if named_property_probes
            else "No named property probe records were written.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-property-keyword-leads",
            name="The core world objects expose build/export-related leads",
            status="passed" if has_any_leads else "blocked",
            details="Leads found: " + "; ".join(lead_fragments)
            if has_any_leads
            else "No property, function, or named-property build/export leads were found on the scanned world objects yet. "
            + (
                "Closest runtime candidates: " + ", ".join(candidate_labels[:6]) + "."
                if candidate_labels
                else "No promising runtime candidates were summarized yet."
            ),
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-candidate-class-scan",
            name="Candidate runtime classes were scanned with FindAllOf",
            status="passed" if candidate_scans else "failed",
            details=f"Observed {len(candidate_scans)} candidate class scan record(s)."
            if candidate_scans
            else "No candidate class scan records were written.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-live-candidates",
            name="At least one live runtime candidate relevant to export work was found",
            status="passed" if live_candidates else "blocked",
            details="Live candidates: " + ", ".join(candidate_labels)
            if live_candidates
            else "None of the current candidate class names resolved to live instances yet.",
            evidence=str(proof_path),
        ),
    ]

    return tests


def build_prefab_native_tests(proof_path: Path, entries: list[dict], server_exe: Path) -> list[TestResult]:
    br_world_manager = read_candidate_count(entries, "BRWorldManager")
    brick_grid_actor = read_candidate_count(entries, "BrickGridActor")
    brick_grid_component = read_candidate_count(entries, "BrickGridComponent")
    brick_grid_dynamic_actor = read_candidate_count(entries, "BrickGridDynamicActor")
    dynamic_grid_entity = read_candidate_count(entries, "Entity_DynamicBrickGrid")
    tool_selector = read_candidate_count(entries, "Tool_Selector_C")
    brick_building_template = read_candidate_count(entries, "BrickBuildingTemplate")

    binary_needles = [
        "BRWorldManager",
        "BRWorldSerializer",
        "BrickPrefabs",
        "BRBundleArchive",
        "PrefabArchive",
        "PendingWorldBundle",
        "CachedWorldBundle",
        "SavedWorldBundle",
        "RequestLoadWorldAdditive",
        "ClientLoadWorldAccepted",
        "ClientLoadWorldRejected",
        "ServerUploadPrefab",
        "ClientUploadPrefab",
        "BRLoadWorldAdditiveParams",
        "ServerPlaceCurrentPrefab",
        "ServerPastePrefab",
        "PrefabCaptureBricks",
        "PrefabCaptureComponents",
        "PrefabCaptureEntities",
        "PrefabCaptureWires",
        "ApplyPrefabState",
    ]
    binary_scan = scan_binary_strings(server_exe, binary_needles)
    binary_matches = list(binary_scan.get("matches", [])) if isinstance(binary_scan.get("matches"), list) else []
    binary_error = binary_scan.get("error")

    runtime_grid_details = ", ".join(
        detail
        for detail in (
            f"BrickGridActor={brick_grid_actor}" if brick_grid_actor is not None else None,
            f"BrickGridComponent={brick_grid_component}" if brick_grid_component is not None else None,
            f"BrickGridDynamicActor={brick_grid_dynamic_actor}" if brick_grid_dynamic_actor is not None else None,
            f"Entity_DynamicBrickGrid={dynamic_grid_entity}" if dynamic_grid_entity is not None else None,
        )
        if detail
    )

    selector_details = ", ".join(
        detail
        for detail in (
            f"Tool_Selector_C={tool_selector}" if tool_selector is not None else None,
            f"BrickBuildingTemplate={brick_building_template}" if brick_building_template is not None else None,
        )
        if detail
    )

    tests = [
        TestResult(
            id="world-export-brworldmanager-live",
            name="The live BRWorldManager object resolves during the proof session",
            status="passed" if br_world_manager and br_world_manager > 0 else "blocked",
            details=f"BRWorldManager={br_world_manager}"
            if br_world_manager is not None
            else "No BRWorldManager candidate scan result was recorded.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-runtime-grid-surface",
            name="The runtime brick-grid surface is present without using commands",
            status="passed"
            if (brick_grid_actor and brick_grid_actor > 0) or (brick_grid_component and brick_grid_component > 0)
            else "blocked",
            details=runtime_grid_details
            if runtime_grid_details
            else "No live brick-grid runtime objects were recorded yet.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-selector-surface",
            name="Selector/template runtime objects are discoverable when a player selection exists",
            status="passed"
            if (tool_selector and tool_selector > 0) or (brick_building_template and brick_building_template > 0)
            else "blocked",
            details=selector_details
            if selector_details
            else "Tool_Selector_C and BrickBuildingTemplate are not live in headless startup-only sessions yet.",
            evidence=str(proof_path),
        ),
        TestResult(
            id="world-export-prefab-binary-leads",
            name="The server binary exposes prefab/world-manager native leads for future call-by-name work",
            status="passed" if len(binary_matches) >= 8 else "blocked",
            details=", ".join(binary_matches)
            if binary_matches
            else binary_error or "No targeted prefab/world-manager strings were found in the server binary.",
            evidence=str(server_exe),
        ),
        TestResult(
            id="world-export-prefab-native-call-surface",
            name="The binary exposes candidate native prefab call names",
            status="passed"
            if {"ServerPlaceCurrentPrefab", "ServerPastePrefab", "PrefabCaptureBricks", "ApplyPrefabState"}.issubset(
                set(binary_matches)
            )
            else "blocked",
            details=", ".join(
                needle
                for needle in (
                    "ServerPlaceCurrentPrefab",
                    "ServerPastePrefab",
                    "PrefabCaptureBricks",
                    "PrefabCaptureComponents",
                    "PrefabCaptureEntities",
                    "PrefabCaptureWires",
                    "ApplyPrefabState",
                )
                if needle in set(binary_matches)
            )
            or "No targeted prefab call names were found yet.",
            evidence=str(server_exe),
        ),
        TestResult(
            id="world-export-prefab-replay-binary-surface",
            name="The binary exposes candidate additive-load and prefab replay method names",
            status="passed"
            if {
                "RequestLoadWorldAdditive",
                "ClientLoadWorldAccepted",
                "ClientLoadWorldRejected",
                "ServerUploadPrefab",
                "ClientUploadPrefab",
                "PrefabArchive",
            }.issubset(set(binary_matches))
            else "blocked",
            details=", ".join(
                needle
                for needle in (
                    "RequestLoadWorldAdditive",
                    "ClientLoadWorldAccepted",
                    "ClientLoadWorldRejected",
                    "ServerUploadPrefab",
                    "ClientUploadPrefab",
                    "PrefabArchive",
                    "BRLoadWorldAdditiveParams",
                )
                if needle in set(binary_matches)
            )
            or "No targeted additive-load replay method names were found yet.",
            evidence=str(server_exe),
        ),
    ]

    return tests


def latest_transition(entries: list[dict], class_name: str) -> dict | None:
    matches = [
        entry
        for entry in entries
        if entry.get("kind") == "candidate_transition" and str(entry.get("class_name") or "") == class_name
    ]
    return matches[-1] if matches else None


def latest_property_probe(snapshot: dict | None, class_name: str) -> dict | None:
    if not snapshot:
        return None

    probes = snapshot.get("property_probes", [])
    for probe in reversed(probes):
        if str(probe.get("class_name") or "") == class_name:
            return probe
    return None


def property_names_from_probe(probe: dict | None) -> list[str]:
    if not probe:
        return []

    names: list[str] = []
    for value in probe.get("values", []):
        property_name = str(value.get("property_name") or "")
        if property_name:
            names.append(property_name)
    return names


def property_value_kind_map(probe: dict | None) -> dict[str, str]:
    if not probe:
        return {}

    kinds: dict[str, str] = {}
    for value in probe.get("values", []):
        property_name = str(value.get("property_name") or "")
        if not property_name:
            continue

        raw_value = value.get("value")
        if isinstance(raw_value, dict):
            kind = str(raw_value.get("kind") or "")
            if kind:
                kinds[property_name] = kind
                continue

        kinds[property_name] = type(raw_value).__name__

    return kinds


def property_wrapper_kind_map(probe: dict | None) -> dict[str, str]:
    if not probe:
        return {}

    wrapper_kinds: dict[str, str] = {}
    for value in probe.get("values", []):
        property_name = str(value.get("property_name") or "")
        if not property_name:
            continue

        raw_value = value.get("value")
        if isinstance(raw_value, dict):
            wrapper_kind = str(raw_value.get("wrapper_kind") or "")
            if wrapper_kind:
                wrapper_kinds[property_name] = wrapper_kind

    return wrapper_kinds


def native_call_probe_map(snapshot: dict | None) -> dict[tuple[str, str], dict]:
    if not snapshot:
        return {}

    probes: dict[tuple[str, str], dict] = {}
    for probe in snapshot.get("native_call_probes", []):
        class_name = str(probe.get("target_class_name") or "")
        function_name = str(probe.get("function_name") or "")
        if class_name and function_name:
            probes[(class_name, function_name)] = probe
    return probes


def surface_probe_map(snapshot: dict | None) -> dict[str, dict]:
    if not snapshot:
        return {}

    probes: dict[str, dict] = {}
    for probe in snapshot.get("surface_probes", []):
        class_name = str(probe.get("class_name") or "")
        if class_name:
            probes[class_name] = probe
    return probes


def read_candidate_count_from_snapshot(snapshot: dict | None, class_name: str) -> int | None:
    if not snapshot:
        return None

    for entry in snapshot.get("candidate_counts", []):
        if str(entry.get("class_name") or "") == class_name:
            return int(entry.get("count", 0) or 0)
    return None


def latest_log_line_containing(log_text: str, needle: str) -> str | None:
    matches = [line.strip() for line in log_text.splitlines() if needle in line]
    return matches[-1] if matches else None


def compact_error_detail(value: str | None, limit: int = 180) -> str | None:
    if not value:
        return None
    first_line = str(value).splitlines()[0].strip()
    if len(first_line) <= limit:
        return first_line
    return first_line[: limit - 3] + "..."


def replay_surface_captures(entries: list[dict]) -> list[dict]:
    return [entry for entry in entries if entry.get("kind") == "replay_surface_capture"]


def replay_capture_phase_name(capture: dict | None) -> str:
    if not isinstance(capture, dict):
        return ""
    return str((capture.get("capture_phase") or {}).get("name") or "")


def replay_capture_transition_delta(capture: dict | None, allowed_classes: set[str] | None = None) -> int:
    if not isinstance(capture, dict):
        return 0

    total = 0
    for transition in capture.get("trigger_transitions") or []:
        class_name = str(transition.get("class_name") or "")
        if allowed_classes and class_name not in allowed_classes:
            continue
        previous_count = transition.get("previous_count")
        current_count = transition.get("current_count")
        if not isinstance(previous_count, int) or not isinstance(current_count, int):
            continue
        total += max(0, current_count - previous_count)
    return total


def select_replay_surface_capture(captures: list[dict], latest_capture: dict | None) -> dict | None:
    candidates = [capture for capture in captures if isinstance(capture, dict)]
    if isinstance(latest_capture, dict):
        candidates.append(latest_capture)
    if not candidates:
        return latest_capture if isinstance(latest_capture, dict) else None

    phase_rank = {
        "grid_component_window": 5,
        "dynamic_grid_window": 4,
        "grid_expansion_window": 3,
        "transfer_window": 2,
        "bundle_archive_window": 1,
    }
    grid_classes = {"BrickGridActor", "BrickGridComponent", "BrickGridDynamicActor"}

    best_capture: dict | None = None
    best_score: tuple[int, int, int, int, int, int] | None = None
    for index, capture in enumerate(candidates):
        capture_classes = {
            str(class_entry.get("class_name") or "")
            for class_entry in capture.get("classes") or []
            if isinstance(class_entry, dict)
        }
        score = (
            phase_rank.get(replay_capture_phase_name(capture), 0),
            replay_capture_transition_delta(capture, grid_classes),
            replay_capture_transition_delta(capture),
            len(grid_classes.intersection(capture_classes)),
            len(capture.get("alias_edges") or []),
            index,
        )
        if best_score is None or score > best_score:
            best_capture = capture
            best_score = score

    return best_capture


def replay_property_alias_pairs(capture: dict | None, allowed_classes: set[str]) -> list[tuple[str, str]]:
    if not isinstance(capture, dict):
        return []

    pairs: set[tuple[str, str]] = set()
    for alias_edge in capture.get("alias_edges") or []:
        left_key = str(alias_edge.get("left") or "")
        right_key = str(alias_edge.get("right") or "")
        if not left_key or not right_key or left_key == right_key:
            continue
        left_class = str(alias_edge.get("left_class") or left_key.split(".", 1)[0])
        right_class = str(alias_edge.get("right_class") or right_key.split(".", 1)[0])
        if left_class not in allowed_classes or right_class not in allowed_classes:
            continue
        pairs.add(tuple(sorted((left_key, right_key))))

    if pairs:
        return sorted(pairs)

    for class_entry in capture.get("classes") or []:
        left_class = str(class_entry.get("class_name") or "")
        if left_class not in allowed_classes:
            continue
        for property_entry in class_entry.get("properties") or []:
            left_property = str(property_entry.get("property_name") or "")
            if not left_property:
                continue
            left_key = f"{left_class}.{left_property}"
            for match in property_entry.get("matches") or []:
                if str(match.get("source_kind") or "") != "property_value":
                    continue
                right_class = str(match.get("class_name") or "")
                right_property = str(match.get("property_name") or "")
                if right_class not in allowed_classes or not right_property:
                    continue
                right_key = f"{right_class}.{right_property}"
                if left_key == right_key:
                    continue
                pairs.add(tuple(sorted((left_key, right_key))))

    return sorted(pairs)


def replay_property_address_sets(captures: list[dict], allowed_classes: set[str]) -> dict[str, set[str]]:
    address_sets: dict[str, set[str]] = {}
    for capture in captures:
        for class_entry in capture.get("classes") or []:
            class_name = str(class_entry.get("class_name") or "")
            if class_name not in allowed_classes:
                continue
            for property_entry in class_entry.get("properties") or []:
                property_name = str(property_entry.get("property_name") or "")
                value_address = str(property_entry.get("value_address") or "")
                if not property_name or not value_address:
                    continue
                key = f"{class_name}.{property_name}"
                address_sets.setdefault(key, set()).add(value_address.lower())
    return address_sets


def classify_grid_handle_followup(probe: dict | None) -> str | None:
    if not probe:
        return None

    followup = probe.get("grid_handle_followup")
    if not isinstance(followup, dict):
        return None

    explicit_status = str(followup.get("handle_status") or probe.get("result_interpretation") or "")
    if explicit_status:
        return explicit_status

    handle = followup.get("handle") or {}
    handle_kind = str(handle.get("kind") or "")
    handle_wrapper_kind = str(handle.get("wrapper_kind") or handle.get("ue4ss_type") or followup.get("ue4ss_type") or "")

    is_valid_call = followup.get("is_valid_call") or {}
    invalid_handle = bool(is_valid_call.get("ok")) and str(is_valid_call.get("value") or "").lower() == "false"

    full_name_call = followup.get("full_name_call") or {}
    empty_full_name = bool(full_name_call.get("ok")) and str(full_name_call.get("value") or "") == ""

    properties = followup.get("properties") or []
    placeholder_property_count = 0
    for entry in properties:
        if not entry.get("ok"):
            continue
        rendered_value = entry.get("value")
        if not isinstance(rendered_value, dict):
            continue
        if str(rendered_value.get("kind") or "") != "userdata":
            continue
        rendered_wrapper_kind = str(rendered_value.get("wrapper_kind") or rendered_value.get("ue4ss_type") or "")
        if rendered_wrapper_kind == "UObject":
            placeholder_property_count += 1

    if (
        handle_kind == "userdata"
        and handle_wrapper_kind == "UObject"
        and invalid_handle
        and empty_full_name
        and properties
        and placeholder_property_count == len(properties)
    ):
        return "placeholder_null_wrapper"

    if handle_kind == "object" and bool(is_valid_call.get("ok")) and str(is_valid_call.get("value") or "").lower() == "true":
        return "decoded_object"

    if invalid_handle and empty_full_name:
        return "invalid_wrapper"

    if handle_kind:
        return "opaque_handle"

    return None


def build_live_prefab_runtime_tests(
    live_snapshot_path: Path,
    live_history_path: Path,
    live_info_path: Path,
    brickadia_log_path: Path,
) -> list[TestResult]:
    snapshot = read_json_file(live_snapshot_path)
    live_info = read_json_file(live_info_path)
    history_entries, history_parse_errors = read_json_lines(live_history_path)
    log_text = brickadia_log_path.read_text(encoding="utf-8", errors="replace") if brickadia_log_path.exists() else ""

    bundle_archive_count = read_candidate_count_from_snapshot(snapshot, "BRBundleArchive")
    dynamic_actor_count = read_candidate_count_from_snapshot(snapshot, "BrickGridDynamicActor")
    world_manager_count = read_candidate_count_from_snapshot(snapshot, "BRWorldManager")
    transfer_count = read_candidate_count_from_snapshot(snapshot, "BRBundleTransferComponent")

    bundle_archive_probe = latest_property_probe(snapshot, "BRBundleArchive")
    dynamic_actor_probe = latest_property_probe(snapshot, "BrickGridDynamicActor")
    bundle_archive_properties = property_names_from_probe(bundle_archive_probe)
    dynamic_actor_properties = property_names_from_probe(dynamic_actor_probe)
    bundle_archive_value_kinds = property_value_kind_map(bundle_archive_probe)
    dynamic_actor_value_kinds = property_value_kind_map(dynamic_actor_probe)
    bundle_archive_wrapper_kinds = property_wrapper_kind_map(bundle_archive_probe)
    dynamic_actor_wrapper_kinds = property_wrapper_kind_map(dynamic_actor_probe)
    native_probes = native_call_probe_map(snapshot)
    live_surface_probes = surface_probe_map(snapshot)
    replay_surface_capture = snapshot.get("latest_replay_surface_capture") if isinstance(snapshot, dict) else None
    replay_alias_history = snapshot.get("replay_alias_history") if isinstance(snapshot, dict) else None
    replay_capture_history = replay_surface_captures(history_entries)
    selected_replay_capture = select_replay_surface_capture(replay_capture_history, replay_surface_capture)
    replay_history_classes = {"BRWorldManager", "BRBundleTransferComponent", "BRBundleArchive"}

    bundle_transition = latest_transition(history_entries, "BRBundleArchive")
    dynamic_transition = latest_transition(history_entries, "BrickGridDynamicActor")

    cache_line = latest_log_line_containing(log_text, "Caching prefab from serialized data")
    additive_line = latest_log_line_containing(log_text, "Loading world additively from bundle")
    metadata_line = latest_log_line_containing(log_text, "Loading prefab metadata")
    spawn_line = latest_log_line_containing(log_text, "Spawning entities and grid serializers")
    success_line = latest_log_line_containing(log_text, "World successfully loaded additively")
    additive_sequence_complete = all((cache_line, additive_line, metadata_line, spawn_line, success_line))

    expected_bundle_properties = {"BricksInChunk", "ChunkOffsets", "ChunkSizes", "OwnerIndices", "PrefabMetadata", "RelativePositions"}
    expected_dynamic_properties = {
        "BricksInChunk",
        "ChunkOffsets",
        "ChunkSizes",
        "OwnerIndices",
        "RelativePositions",
        "Orientations",
        "MaterialIndices",
        "PrefabMetadata",
        "EntityType",
    }
    bundle_property_hits = sorted(expected_bundle_properties.intersection(bundle_archive_properties))
    dynamic_property_hits = sorted(expected_dynamic_properties.intersection(dynamic_actor_properties))
    bundle_userdata_hits = [name for name in bundle_property_hits if bundle_archive_value_kinds.get(name) == "userdata"]
    dynamic_userdata_hits = [name for name in dynamic_property_hits if dynamic_actor_value_kinds.get(name) == "userdata"]
    bundle_placeholder_hits = [
        name
        for name in bundle_property_hits
        if bundle_archive_value_kinds.get(name) == "userdata" and bundle_archive_wrapper_kinds.get(name) == "UObject"
    ]
    dynamic_placeholder_hits = [
        name
        for name in dynamic_property_hits
        if dynamic_actor_value_kinds.get(name) == "userdata" and dynamic_actor_wrapper_kinds.get(name) == "UObject"
    ]
    bundle_wrapper_hits = sorted({bundle_archive_wrapper_kinds.get(name) for name in bundle_property_hits if bundle_archive_wrapper_kinds.get(name)})
    dynamic_wrapper_hits = sorted({dynamic_actor_wrapper_kinds.get(name) for name in dynamic_property_hits if dynamic_actor_wrapper_kinds.get(name)})

    grid_getter_probes = [
        probe
        for probe in native_probes.values()
        if str(probe.get("function_name") or "") == "GetBrickGrid"
    ]
    grid_getter_details: list[str] = []
    decoded_grid_getter_available = False
    for probe in sorted(grid_getter_probes, key=lambda item: str(item.get("target_class_name") or "")):
        interpretation = classify_grid_handle_followup(probe) or "unknown"
        if interpretation == "decoded_object":
            decoded_grid_getter_available = True
        fragment = (
            f"{probe.get('target_class_name')}->{probe.get('function_name')} success={probe.get('success')} "
            f"interpretation={interpretation}"
        )
        reason = str(probe.get("reason") or "")
        if reason:
            fragment += f" reason={reason}"
        grid_getter_details.append(fragment)

    replay_probe_names = {
        "RequestLoadWorldAdditive",
        "ClientLoadWorldAccepted",
        "ClientLoadWorldRejected",
        "ServerUploadPrefab",
        "ClientUploadPrefab",
    }
    replay_probes = [
        probe
        for probe in native_probes.values()
        if str(probe.get("function_name") or "") in replay_probe_names
    ]
    replay_probe_details = []
    for probe in sorted(
        replay_probes,
        key=lambda item: (str(item.get("target_class_name") or ""), str(item.get("function_name") or "")),
    ):
        fragment = f"{probe.get('target_class_name')}->{probe.get('function_name')} success={probe.get('success')}"
        reason = str(probe.get("reason") or "")
        if reason:
            fragment += f" reason={reason}"
        replay_probe_details.append(fragment)

    def render_native_probe_details(probe: dict | None) -> str | None:
        if not probe:
            return None
        detail = f"{probe.get('target_class_name')}->{probe.get('function_name')} success={probe.get('success')}"
        interpretation = classify_grid_handle_followup(probe)
        if interpretation:
            detail += f" interpretation={interpretation}"
        if probe.get("reason"):
            detail += f" reason={probe.get('reason')}"
        elif probe.get("output"):
            detail += f" output={probe.get('output')}"
        return detail

    ordered_native_probe_items = sorted(
        native_probes.values(),
        key=lambda probe: (
            0 if probe.get("success") else 1,
            str(probe.get("target_class_name") or ""),
            str(probe.get("function_name") or ""),
        ),
    )
    native_probe_details = "; ".join(
        detail
        for detail in (render_native_probe_details(probe) for probe in ordered_native_probe_items)
        if detail
    )

    surface_probe_details = []
    for class_name in ("BRWorldManager", "BRBundleArchive", "BrickGridDynamicActor"):
        probe = live_surface_probes.get(class_name)
        if not probe:
            continue
        property_scan = probe.get("property_scan") or {}
        function_scan = probe.get("function_scan") or {}
        fragment = (
            f"{class_name} property_matches={property_scan.get('match_count', 0)}"
            f" function_matches={function_scan.get('match_count', 0)}"
        )
        compact_property_error = compact_error_detail(property_scan.get("error"))
        compact_function_error = compact_error_detail(function_scan.get("error"))
        if compact_property_error:
            fragment += f" property_error={compact_property_error}"
        if compact_function_error:
            fragment += f" function_error={compact_function_error}"
        surface_probe_details.append(fragment)

    runtime_surface_details = ", ".join(
        detail
        for detail in (
            f"BRWorldManager={world_manager_count}" if world_manager_count is not None else None,
            f"BRBundleArchive={bundle_archive_count}" if bundle_archive_count is not None else None,
            f"BrickGridDynamicActor={dynamic_actor_count}" if dynamic_actor_count is not None else None,
            f"BRBundleTransferComponent={transfer_count}" if transfer_count is not None else None,
        )
        if detail
    )

    transition_details = ", ".join(
        detail
        for detail in (
            f"BRBundleArchive at {bundle_transition.get('timestamp')}" if bundle_transition else None,
            f"BrickGridDynamicActor at {dynamic_transition.get('timestamp')}" if dynamic_transition else None,
        )
        if detail
    )

    replay_capture_trigger_details: list[str] = []
    replay_capture_class_details: list[str] = []
    replay_capture_native_details: list[str] = []
    selected_replay_property_aliases = replay_property_alias_pairs(selected_replay_capture, replay_history_classes)
    selected_replay_alias_edges = (
        selected_replay_capture.get("alias_edges") if isinstance(selected_replay_capture, dict) else []
    ) or []
    selected_replay_phase = replay_capture_phase_name(selected_replay_capture)
    latest_replay_phase = replay_capture_phase_name(replay_surface_capture)
    replay_alias_counter: Counter[tuple[str, str]] = Counter()
    for capture in replay_capture_history:
        for pair in replay_property_alias_pairs(capture, replay_history_classes):
            replay_alias_counter[pair] += 1
    repeated_replay_aliases = []
    if isinstance(replay_alias_history, dict):
        for edge in replay_alias_history.get("repeated_edges") or []:
            edge_key = str(edge.get("key") or "")
            if not edge_key:
                continue
            seen_count = edge.get("seen_count")
            repeated_replay_aliases.append(f"{edge_key} x{seen_count}" if seen_count else edge_key)
    if not repeated_replay_aliases:
        repeated_replay_aliases = [
            " <-> ".join(pair)
            for pair, count in sorted(replay_alias_counter.items())
            if count > 1
        ]
    replay_address_sets = replay_property_address_sets(replay_capture_history, replay_history_classes)
    stable_replay_properties = sorted(name for name, addresses in replay_address_sets.items() if len(addresses) == 1)
    churning_replay_properties = sorted(name for name, addresses in replay_address_sets.items() if len(addresses) > 1)
    if isinstance(selected_replay_capture, dict):
        for transition in selected_replay_capture.get("trigger_transitions") or []:
            replay_capture_trigger_details.append(
                f"{transition.get('class_name')} {transition.get('previous_count')}->{transition.get('current_count')}"
            )
        for class_entry in selected_replay_capture.get("classes") or []:
            properties = class_entry.get("properties") or []
            aliased_properties = sum(1 for item in properties if item.get("match_count"))
            replay_capture_class_details.append(
                f"{class_entry.get('class_name')} props={len(properties)} aliased={aliased_properties}"
            )
        for probe in selected_replay_capture.get("native_probes") or []:
            detail = (
                f"{probe.get('target_class_name')}->{probe.get('function_name')} success={probe.get('success')}"
            )
            interpretation = str(probe.get("result_interpretation") or "")
            if interpretation:
                detail += f" interpretation={interpretation}"
            replay_capture_native_details.append(detail)

    property_details = []
    if bundle_property_hits:
        property_details.append("BRBundleArchive: " + ", ".join(bundle_property_hits))
    if dynamic_property_hits:
        property_details.append("BrickGridDynamicActor: " + ", ".join(dynamic_property_hits))

    sampler_verified = bool(live_info and live_info.get("verified"))
    sampler_started_at = str(live_info.get("started_at")) if live_info else None

    tests = [
        TestResult(
            id="world-export-live-prefab-sampler-output",
            name="The live prefab sampler produced a parseable snapshot",
            status="passed" if snapshot and not history_parse_errors else "blocked",
            details=(
                f"Snapshot updated_at={snapshot.get('updated_at')}; sampler_started_at={sampler_started_at}"
                if snapshot and not history_parse_errors
                else "Missing or unparseable live prefab sampler output."
            ),
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-prefab-additive-load-trace",
            name="The server log shows the additive prefab load path end-to-end",
            status="passed" if additive_sequence_complete else "blocked",
            details=" | ".join(
                fragment
                for fragment in (cache_line, additive_line, metadata_line, spawn_line, success_line)
                if fragment
            )
            if additive_sequence_complete
            else "The expected additive prefab load sequence was not fully observed in the live server log.",
            evidence=str(brickadia_log_path),
        ),
        TestResult(
            id="world-export-live-prefab-runtime-surface",
            name="Live runtime prefab/archive objects appear after a player-driven load",
            status="passed"
            if (bundle_archive_count and bundle_archive_count > 0) and (dynamic_actor_count and dynamic_actor_count > 0)
            else "blocked",
            details=(runtime_surface_details + (f"; {transition_details}" if transition_details else ""))
            if runtime_surface_details
            else "No live runtime prefab/archive objects were summarized from the sampler snapshot.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-replay-surface-capture",
            name="A safe replay-surface capture is recorded when prefab runtime counts change",
            status="passed" if selected_replay_capture else "blocked",
            details="; ".join(
                detail
                for detail in (
                    f"selected_phase={selected_replay_phase}" if selected_replay_phase else None,
                    (
                        f"latest_phase={latest_replay_phase}"
                        if latest_replay_phase and latest_replay_phase != selected_replay_phase
                        else None
                    ),
                    "triggers=" + ", ".join(replay_capture_trigger_details) if replay_capture_trigger_details else None,
                    "classes=" + ", ".join(replay_capture_class_details) if replay_capture_class_details else None,
                    "native=" + ", ".join(replay_capture_native_details[:6]) if replay_capture_native_details else None,
                )
                if detail
            )
            if selected_replay_capture
            else "No replay-surface capture has been recorded in the live snapshot yet.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-replay-capture-diff",
            name="Replay-surface history can be diffed across multiple prefab loads",
            status="passed" if len(replay_capture_history) >= 2 else "blocked",
            details="; ".join(
                detail
                for detail in (
                    f"captures={len(replay_capture_history)}" if replay_capture_history else None,
                    f"selected_phase={selected_replay_phase}" if selected_replay_phase else None,
                    (
                        f"latest_phase={latest_replay_phase}"
                        if latest_replay_phase and latest_replay_phase != selected_replay_phase
                        else None
                    ),
                    "selected_property_aliases=" + ", ".join(" <-> ".join(pair) for pair in selected_replay_property_aliases)
                    if selected_replay_property_aliases
                    else "selected_property_aliases=none",
                    f"selected_alias_edges={len(selected_replay_alias_edges)}" if selected_replay_alias_edges else None,
                    "repeated_property_aliases=" + ", ".join(repeated_replay_aliases[:4])
                    if repeated_replay_aliases
                    else "repeated_property_aliases=none_yet",
                    (
                        f"repeated_alias_edges={replay_alias_history.get('repeated_edge_count')}"
                        if isinstance(replay_alias_history, dict)
                        else None
                    ),
                    f"stable_replay_properties={len(stable_replay_properties)}",
                    f"churning_replay_properties={len(churning_replay_properties)}",
                )
                if detail
            )
            if len(replay_capture_history) >= 2
            else "At least two replay-surface captures are needed before diffing bundle/property churn.",
            evidence=str(live_history_path),
        ),
        TestResult(
            id="world-export-live-native-call-probes",
            name="Live native call probes ran against the bundle/world-manager replay surface",
            status="passed" if native_probes else "blocked",
            details=native_probe_details
            if native_probe_details
            else "No native call probe results were recorded in the live sampler snapshot yet.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-grid-getter-decoder-status",
            name="Live GetBrickGrid returns a decoded grid object instead of a placeholder wrapper",
            status="passed" if decoded_grid_getter_available else "blocked",
            details="; ".join(grid_getter_details)
            if grid_getter_details
            else "No GetBrickGrid probe results were available in the live sampler snapshot.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-replay-native-surface",
            name="Live additive-load replay candidates are being probed on the runtime bundle surface",
            status="passed" if replay_probes else "blocked",
            details="; ".join(replay_probe_details)
            if replay_probe_details
            else "Unsafe live replay calls are intentionally disabled in the sampler right now because zero-arg probing of upload/accept methods can trip PendingWorldUpload assertions. The replay path is still tracked as a binary/runtime lead, just not invoked blindly.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-surface-scan-status",
            name="Live prefab classes were surface-scanned for reflected property/function leads",
            status="passed" if surface_probe_details else "blocked",
            details="; ".join(surface_probe_details)
            if surface_probe_details
            else "No live surface probe summaries were recorded for BRWorldManager/BRBundleArchive/BrickGridDynamicActor yet.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-prefab-property-surface",
            name="The live prefab/archive objects expose the expected chunk and prefab property names",
            status="passed" if bundle_property_hits and dynamic_property_hits else "blocked",
            details="; ".join(property_details)
            if property_details
            else "The live prefab/archive property probes did not expose the expected chunk/prefab field names yet.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-live-prefab-property-decoder-status",
            name="Expected live prefab property values decode beyond observe-only userdata handles",
            status="passed"
            if (
                bundle_property_hits
                and dynamic_property_hits
                and (
                    len(bundle_placeholder_hits) < len(bundle_property_hits)
                    or len(dynamic_placeholder_hits) < len(dynamic_property_hits)
                )
            )
            else "blocked",
            details=(
                "BRBundleArchive userdata="
                f"{len(bundle_userdata_hits)}/{len(bundle_property_hits)}"
                + " placeholder_uobject="
                + f"{len(bundle_placeholder_hits)}/{len(bundle_property_hits)}"
                + "; BrickGridDynamicActor userdata="
                + f"{len(dynamic_userdata_hits)}/{len(dynamic_property_hits)}"
                + " placeholder_uobject="
                + f"{len(dynamic_placeholder_hits)}/{len(dynamic_property_hits)}"
                + (
                    "; BRBundleArchive wrappers="
                    + ", ".join(bundle_wrapper_hits)
                    if bundle_wrapper_hits
                    else ""
                )
                + (
                    "; BrickGridDynamicActor wrappers="
                    + ", ".join(dynamic_wrapper_hits)
                    if dynamic_wrapper_hits
                    else ""
                )
                + ". Current blocker: expected prefab fields exist, but they are still resolving as placeholder-style UObject userdata wrappers instead of decoded brick/prefab values."
            )
            if bundle_property_hits or dynamic_property_hits
            else "No expected prefab property hits were available to classify yet.",
            evidence=str(live_snapshot_path),
        ),
        TestResult(
            id="world-export-headless-prefab-replay-surface",
            name="The server-side runtime surface for future headless prefab replay is present",
            status="passed"
            if sampler_verified
            and additive_sequence_complete
            and (bundle_archive_count and bundle_archive_count > 0)
            and (world_manager_count and world_manager_count > 0)
            and native_probes
            else "blocked",
            details=(
                "Sampler verified; additive prefab load recorded; BRWorldManager and BRBundleArchive are both live; native call probes are running. "
                "This is a replay target surface, not proof of automatic headless replay yet."
            )
            if sampler_verified
            and additive_sequence_complete
            and (bundle_archive_count and bundle_archive_count > 0)
            and (world_manager_count and world_manager_count > 0)
            and native_probes
            else "The runtime surfaces needed for a future headless replay target are not all present in this live capture yet.",
            evidence=str(live_snapshot_path),
        ),
    ]

    return tests


def render_markdown(report: dict) -> str:
    lines = [
        f"# {report['bundle_id']} World Export Canary Report",
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
            lines.append(f"- [{test['status'].upper()}] `{test['id']}`: {test['name']}")
            lines.append(f"  - {test['details']}")
            if test.get("evidence"):
                lines.append(f"  - Evidence: `{test['evidence']}`")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main():
    args = parse_args()
    proof_path = Path(args.proof_output)
    server_exe = Path(args.server_exe)
    live_snapshot_path = Path(args.live_snapshot)
    live_history_path = Path(args.live_history)
    live_info_path = Path(args.live_info)
    brickadia_log_path = Path(args.brickadia_log)
    entries, parse_errors = read_json_lines(proof_path)
    workspace = Path(args.workspace)
    bundle_root = workspace / "bundles" / args.bundle

    sections = [
        emit("context-resolution", "Context Resolution", build_context_resolution_tests(proof_path, entries, parse_errors)),
        emit("discovery-leads", "Discovery Leads", build_discovery_lead_tests(proof_path, entries)),
        emit("prefab-native-leads", "Prefab Native Leads", build_prefab_native_tests(proof_path, entries, server_exe)),
        emit(
            "live-prefab-runtime",
            "Live Prefab Runtime",
            build_live_prefab_runtime_tests(
                live_snapshot_path,
                live_history_path,
                live_info_path,
                brickadia_log_path,
            ),
        ),
    ]

    summary = {"total": 0, "passed": 0, "failed": 0, "blocked": 0}
    for section in sections:
        for key in summary:
            summary[key] += int(section["summary"].get(key, 0))

    report = {
        "bundle_id": args.bundle,
        "workspace_root": str(workspace),
        "bundle_root": str(bundle_root),
        "proof_output": str(proof_path),
        "server_exe": str(server_exe),
        "summary": summary,
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
