import argparse
import json
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Summary:
    total: int = 0
    passed: int = 0
    failed: int = 0
    blocked: int = 0

    def add(self, other: dict) -> None:
        self.total += int(other.get("total", 0))
        self.passed += int(other.get("passed", 0))
        self.failed += int(other.get("failed", 0))
        self.blocked += int(other.get("blocked", 0))

    def as_dict(self) -> dict:
        return {
            "total": self.total,
            "passed": self.passed,
            "failed": self.failed,
            "blocked": self.blocked,
        }


def parse_args():
    parser = argparse.ArgumentParser(description="Render a combined CL12960 full test suite report.")
    parser.add_argument("--workspace", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--bundle", default="CL12960")
    parser.add_argument("--baseline-report", required=True)
    parser.add_argument("--chat-report", required=True)
    parser.add_argument("--world-export-report")
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


def suite_entry(suite_id: str, name: str, report_path: Path, report: dict) -> dict:
    return {
        "id": suite_id,
        "name": name,
        "report_path": str(report_path),
        "summary": report.get("summary", {}),
        "sections": report.get("sections", []),
    }


def render_markdown(report: dict) -> str:
    lines = [
        f"# {report['bundle_id']} Full Test Suite",
        "",
        "## Summary",
        "",
        f"- Total: `{report['summary']['total']}`",
        f"- Passed: `{report['summary']['passed']}`",
        f"- Failed: `{report['summary']['failed']}`",
        f"- Blocked: `{report['summary']['blocked']}`",
        "",
        "## Suites",
        "",
    ]

    for suite in report["suites"]:
        lines.extend(
            [
                f"- `{suite['name']}`: "
                f"{suite['summary']['passed']} passed / "
                f"{suite['summary']['failed']} failed / "
                f"{suite['summary']['blocked']} blocked",
                f"  - Report: `{suite['report_path']}`",
            ]
        )

    lines.append("")

    for suite in report["suites"]:
        lines.extend(
            [
                f"## {suite['name']}",
                "",
                f"- Total: `{suite['summary']['total']}`",
                f"- Passed: `{suite['summary']['passed']}`",
                f"- Failed: `{suite['summary']['failed']}`",
                f"- Blocked: `{suite['summary']['blocked']}`",
                f"- Report: `{suite['report_path']}`",
                "",
            ]
        )

        for section in suite["sections"]:
            lines.extend(
                [
                    f"### {section['name']}",
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
    baseline_report_path = Path(args.baseline_report)
    chat_report_path = Path(args.chat_report)
    world_export_report_path = Path(args.world_export_report) if args.world_export_report else None

    baseline_report = read_json_file(baseline_report_path)
    chat_report = read_json_file(chat_report_path)

    suites = [
        suite_entry("baseline", "Baseline Tests", baseline_report_path, baseline_report),
        suite_entry("chat-canary", "Chat Canary", chat_report_path, chat_report),
    ]
    if world_export_report_path and world_export_report_path.exists():
        world_export_report = read_json_file(world_export_report_path)
        suites.append(
            suite_entry("world-export", "World Export Canary", world_export_report_path, world_export_report)
        )

    summary = Summary()
    for suite in suites:
        summary.add(suite["summary"])

    report = {
        "bundle_id": args.bundle,
        "workspace_root": str(workspace),
        "bundle_root": str(bundle_root),
        "summary": summary.as_dict(),
        "suites": suites,
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
