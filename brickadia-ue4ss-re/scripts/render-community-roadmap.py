import argparse
import json
import sys
from pathlib import Path


DEFAULT_REPORT = Path(
    r"C:\Users\tycox\OneDrive\Documents\GitHub\Brickadia\brickadia-ue4ss-re\notes\cl12960-baseline-tests-latest.json"
)

SECTION_PRIORITY = [
    "bundle-integrity",
    "hook-foundation",
    "resolver-coverage",
    "runtime-validation",
]

FOCUS_PRIORITY = {
    "hook-foundation": [
        "agamemodebase-initgamestate-coverage",
        "aactor-beginplay-coverage",
        "hook-runtime-confirmation-gate",
    ],
    "resolver-coverage": [
        "resolver-fuobjecthashtablesget-required",
        "resolver-gnatives-required",
        "resolver-staticfindobjectfast-required",
        "resolver-uobjectskipfunction-required",
        "resolver-fframestep-required",
    ],
    "runtime-validation": [
        "ue4ss-startup-no-fatal",
        "stage2-startup-status",
        "stage3-object-resolution-status",
        "stage4-dumper-status",
    ],
}

BLOCKED_BY = {
    "uobject-processevent-runtime": "hook-runtime-confirmation-gate",
    "uengine-loadmap-runtime": "hook-runtime-confirmation-gate",
    "agamemodebase-initgamestate-runtime": "hook-runtime-confirmation-gate",
    "aactor-beginplay-runtime": "hook-runtime-confirmation-gate",
    "stage4-dumper-status": "stage3-object-resolution-status",
}

NEXT_STEPS = {
    "agamemodebase-initgamestate-coverage": "Validate `AGameModeBase::InitGameState` against the live CL12960 binary in Ghidra/x64dbg and add an explicit Brickadia override if the stock UE5.5 default is wrong.",
    "aactor-beginplay-coverage": "Validate `AActor::BeginPlay` against the live CL12960 binary in Ghidra/x64dbg and add an explicit Brickadia override if the stock UE5.5 default is wrong.",
    "hook-runtime-confirmation-gate": "Clear the UE4SS startup fatal first so post-init hook logging can run. The immediate blocker is the missing `GUObjectHashTables.lua` / `FUObjectHashTablesGet` path.",
    "resolver-fuobjecthashtablesget-required": "Recover `FUObjectHashTables::Get()` from the hash-table family and validate it dynamically.",
    "resolver-gnatives-required": "Recover `GNatives` from the script VM dispatch path instead of the failed stock patterns.",
    "resolver-staticfindobjectfast-required": "Trace `StaticFindObjectFast` after the core startup blockers are cleared.",
    "resolver-uobjectskipfunction-required": "Recover `UObject::SkipFunction` after the higher-priority resolver failures above it are resolved.",
    "resolver-fframestep-required": "Recover `FFrame::Step` after `GNatives` and `UObject::SkipFunction` are understood.",
    "ue4ss-startup-no-fatal": "Follow the fatal line in `UE4SS.log` and clear the lower-layer resolver or signature issue causing startup to stop.",
    "stage2-startup-status": "Treat this as a roll-up status and resolve the concrete failures above it first.",
    "stage3-object-resolution-status": "Treat this as a roll-up status and resolve the concrete hook/resolver failures above it first.",
    "stage4-dumper-status": "Leave this blocked until object-resolution validation passes.",
}

SECTION_TITLES = {
    "bundle-integrity": "Working Now",
    "hook-foundation": "Priority 1: Hook Foundation",
    "resolver-coverage": "Priority 2: Resolver Coverage",
    "runtime-validation": "Priority 3: Runtime Validation",
}

FRIENDLY_TEST_NAMES = {
    "agamemodebase-initgamestate-coverage": "Map the missing game-state startup hook",
    "aactor-beginplay-coverage": "Map the missing actor startup hook",
    "hook-runtime-confirmation-gate": "Remove the startup blocker so live hook checks can run",
    "resolver-fuobjecthashtablesget-required": "Restore the engine path used to find live game objects",
    "resolver-gnatives-required": "Restore the engine path used to call built-in game functions",
    "resolver-staticfindobjectfast-required": "Recover fast object lookup for this build",
    "resolver-uobjectskipfunction-required": "Recover a missing script execution helper",
    "resolver-fframestep-required": "Recover the frame-stepping path used by scripts",
    "ue4ss-startup-no-fatal": "Make UE4SS start cleanly without a fatal error",
    "stage2-startup-status": "Get the full startup validation stage passing",
    "stage3-object-resolution-status": "Make object access stable instead of crash-prone",
    "stage4-dumper-status": "Unblock the automatic dumper and richer tooling stage",
}

FRIENDLY_WHY_NOW = {
    "agamemodebase-initgamestate-coverage": "This is one of the remaining core startup hooks we need before we can trust deeper runtime checks.",
    "aactor-beginplay-coverage": "This is the other major startup hook still missing clear build-specific coverage.",
    "hook-runtime-confirmation-gate": "The tool is stopping too early, so the live hook checks never get a chance to run.",
    "resolver-fuobjecthashtablesget-required": "Until object lookup works, anything that depends on finding live game objects stays unreliable.",
    "resolver-gnatives-required": "Until this is restored, built-in script/native execution support stays incomplete.",
    "resolver-staticfindobjectfast-required": "This is part of the object lookup family that later modding work depends on.",
    "resolver-uobjectskipfunction-required": "This is a lower-level scripting helper still missing from the current build coverage.",
    "resolver-fframestep-required": "This is another low-level scripting helper that has to come back before deeper script support is trustworthy.",
    "ue4ss-startup-no-fatal": "A clean startup is the minimum bar before we can trust any later validation stage.",
    "stage2-startup-status": "This is the roll-up check for whether the startup layer is really healthy.",
    "stage3-object-resolution-status": "This is the roll-up check for whether object access is safe enough to build on.",
    "stage4-dumper-status": "This stays blocked until the lower-level object work is truly stable.",
}

FRIENDLY_NEXT_STEPS = {
    "agamemodebase-initgamestate-coverage": "Verify the current build in Ghidra/x64dbg and add a Brickadia-specific override if the default layout is wrong.",
    "aactor-beginplay-coverage": "Verify the current build in Ghidra/x64dbg and add a Brickadia-specific override if the default layout is wrong.",
    "hook-runtime-confirmation-gate": "Clear the current startup error first so the live hook-address checks can finally run.",
    "resolver-fuobjecthashtablesget-required": "Trace the hash-table family and recover the getter used by this build.",
    "resolver-gnatives-required": "Trace the script/native dispatch path and recover the current table address from the live binary.",
    "resolver-staticfindobjectfast-required": "Revisit fast object lookup after the startup blockers above it are cleared.",
    "resolver-uobjectskipfunction-required": "Recover this helper after the bigger object and script blockers are solved.",
    "resolver-fframestep-required": "Recover this helper after the script dispatch path is understood again.",
    "ue4ss-startup-no-fatal": "Follow the fatal line in the log and fix the lower-level resolver issue causing startup to stop.",
    "stage2-startup-status": "Resolve the concrete startup failures above this roll-up check.",
    "stage3-object-resolution-status": "Resolve the hook and resolver failures above this roll-up check.",
    "stage4-dumper-status": "Leave this parked until object access is stable.",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Render a community-friendly roadmap from Brickadia baseline test results.")
    parser.add_argument("--report", default=str(DEFAULT_REPORT))
    parser.add_argument("--write")
    return parser.parse_args()


def load_report(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def section_map(report: dict):
    return {section["id"]: section for section in report["sections"]}


def tests_by_status(section: dict, status: str):
    return [test for test in section["tests"] if test["status"] == status]


def choose_focus(report: dict):
    sections = section_map(report)
    for section_id in SECTION_PRIORITY:
        section = sections.get(section_id)
        if not section:
            continue
        failed = {test["id"]: test for test in tests_by_status(section, "failed")}
        if not failed:
            continue
        for preferred in FOCUS_PRIORITY.get(section_id, []):
            if preferred in failed:
                return failed[preferred]
        return next(iter(failed.values()))
    return None


def choose_follow_ups(report: dict, focus_id: str | None):
    follow_ups = []
    sections = section_map(report)
    for section_id in SECTION_PRIORITY:
        section = sections.get(section_id)
        if not section:
            continue
        failed = {test["id"]: test for test in tests_by_status(section, "failed")}
        for preferred in FOCUS_PRIORITY.get(section_id, []):
            if preferred in failed and preferred != focus_id:
                follow_ups.append(failed[preferred])
                if len(follow_ups) == 2:
                    return follow_ups
    return follow_ups


def blocked_dependency(test_id: str):
    dependency = BLOCKED_BY.get(test_id)
    if not dependency:
        return "an earlier prerequisite"
    return dependency


def friendly_name(test: dict):
    return FRIENDLY_TEST_NAMES.get(test["id"], test["name"])


def friendly_reason(test: dict):
    return FRIENDLY_WHY_NOW.get(test["id"], test["details"])


def friendly_next_step(test: dict):
    return FRIENDLY_NEXT_STEPS.get(test["id"], NEXT_STEPS.get(test["id"], test["details"]))


def render_section(title: str, tests: list[dict], emoji: str):
    lines = [f"## {title}", ""]
    if not tests:
        lines.append(f"- {emoji} None in this section right now.")
        lines.append("")
        return lines

    for test in tests:
        lines.append(f"- {emoji} {test['name']}")
    lines.append("")
    return lines


def render_section_with_details(title: str, tests: list[dict], emoji: str, show_details: bool = True):
    lines = [f"## {title}", ""]
    if not tests:
        lines.append(f"- {emoji} None in this section right now.")
        lines.append("")
        return lines

    for test in tests:
        lines.append(f"- {emoji} {test['name']}")
        if show_details:
            lines.append(f"  Current: {test['details']}")
    lines.append("")
    return lines


def render_markdown(report: dict) -> str:
    focus = choose_focus(report)
    follow_ups = choose_follow_ups(report, focus["id"] if focus else None)
    sections = section_map(report)
    hook_section = sections.get("hook-foundation", {"tests": []})
    resolver_section = sections.get("resolver-coverage", {"tests": []})
    runtime_section = sections.get("runtime-validation", {"tests": []})
    bundle_section = sections.get("bundle-integrity", {"tests": []})
    hook_summary = hook_section.get("summary", {})
    resolver_summary = resolver_section.get("summary", {})
    runtime_summary = runtime_section.get("summary", {})
    bundle_summary = bundle_section.get("summary", {})

    hook_failed = tests_by_status(hook_section, "failed")
    resolver_failed = tests_by_status(resolver_section, "failed")
    runtime_failed = tests_by_status(runtime_section, "failed")
    blocked_tests = []
    for section_id in SECTION_PRIORITY:
        section = sections.get(section_id)
        if not section:
            continue
        blocked_tests.extend(tests_by_status(section, "blocked"))

    lines = [
        "# Brickadia Windows Modding Progress",
        "",
        f"_Tracked build: `{report['bundle_id']}`_",
        "",
        "## At A Glance",
        "",
        f"- Working checks: `{report['summary']['passed']}`",
        f"- In progress: `{report['summary']['failed']}`",
        f"- Waiting on earlier fixes: `{report['summary']['blocked']}`",
        f"- Total checks tracked: `{report['summary']['total']}`",
        "",
    ]

    lines.extend(
        [
            "## What's Working",
            "",
            f"- The compatibility bundle is assembled correctly and its file checks are all passing ({bundle_summary.get('passed', 0)} of {bundle_summary.get('total', 0)} bundle checks).",
            f"- The core startup hooks are now mapped for this build ({hook_summary.get('passed', 0)} passing hook-foundation checks so far).",
            f"- Several lower-level engine building blocks are already identified ({resolver_summary.get('passed', 0)} passing resolver checks so far).",
            f"- Startup logs and baseline reports are being captured reliably ({runtime_summary.get('passed', 0)} passing runtime checks so far).",
            "",
        ]
    )

    if focus:
        lines.extend(
            [
                "## Current Focus",
                "",
                f"- {friendly_name(focus)}",
                f"  Why this matters: {friendly_reason(focus)}",
                f"  Next step: {friendly_next_step(focus)}",
                "",
            ]
        )

    lines.append("## Priority 1: Core Startup Hooks")
    lines.append("")
    if hook_failed:
        for test in hook_failed:
            lines.append(f"- {friendly_name(test)}")
            lines.append(f"  Why it matters: {friendly_reason(test)}")
    else:
        lines.append("- No open startup-hook work right now.")
    lines.append("")

    lines.append("## Priority 2: Object Lookup And Scripting Support")
    lines.append("")
    if resolver_failed:
        for test in resolver_failed:
            lines.append(f"- {friendly_name(test)}")
            lines.append(f"  Why it matters: {friendly_reason(test)}")
    else:
        lines.append("- No open resolver work right now.")
    lines.append("")

    lines.append("## Priority 3: Stability And Validation")
    lines.append("")
    if runtime_failed:
        for test in runtime_failed:
            lines.append(f"- {friendly_name(test)}")
            lines.append(f"  Why it matters: {friendly_reason(test)}")
    else:
        lines.append("- No open validation work right now.")
    lines.append("")

    lines.append("## Waiting On Earlier Fixes")
    lines.append("")
    if blocked_tests:
        for test in blocked_tests:
            lines.append(f"- {friendly_name(test)}")
            lines.append(f"  Waiting on: {friendly_name({'id': blocked_dependency(test['id']), 'name': blocked_dependency(test['id'])}) if blocked_dependency(test['id']) in FRIENDLY_TEST_NAMES else blocked_dependency(test['id'])}")
    else:
        lines.append("- Nothing is blocked right now.")
    lines.append("")

    if follow_ups:
        lines.append("## Up Next")
        lines.append("")
        for test in follow_ups:
            lines.append(f"- {friendly_name(test)}")
            lines.append(f"  Next step: {friendly_next_step(test)}")
        lines.append("")

    lines.extend(
        [
            "## What This Means",
            "",
            "- The Windows wrapper and reporting side are already in place.",
            "- The remaining work is inside the game/engine compatibility layer, not the launcher or UI layer.",
            "- The near-term job is to finish the remaining resolver work, then stabilize startup and object lookup.",
            "",
            "## For Technical Readers",
            "",
            f"- Detailed engineering report: `{DEFAULT_REPORT.with_name('cl12960-baseline-tests-latest.md')}`",
            f"- Detailed bundle status: `{Path(DEFAULT_REPORT).parents[1] / 'bundles' / report['bundle_id'] / 'validation-report.md'}`",
            "",
        ]
    )

    return "\n".join(lines)


def main():
    args = parse_args()
    report = load_report(Path(args.report))
    markdown = render_markdown(report)
    if args.write:
        Path(args.write).write_text(markdown + "\n", encoding="utf-8")
        return

    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    print(markdown)


if __name__ == "__main__":
    main()
