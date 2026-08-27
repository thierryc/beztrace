#!/usr/bin/env python3
"""Run the read-only Milestone 6 test matrix and record command evidence."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = Path("/Volumes/T9/beztrace/milestone-6/reports/test-evidence.json")


def asan_command(swift_executable: str) -> list[str]:
    return [
        swift_executable, "test", "--configuration", "release", "--disable-swift-testing",
        "--sanitize=address", "--filter", "MalformedCorpusTests",
    ]


def execute(command: list[str]) -> dict:
    started = time.monotonic()
    process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    output = process.stdout.decode("utf-8", "replace")
    return {
        "command": command,
        "returnCode": process.returncode,
        "status": "pass" if process.returncode == 0 else "fail",
        "durationSeconds": round(time.monotonic() - started, 6),
        "outputTail": output[-8_000:],
    }


def tracked_status() -> str:
    return subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--skip-x86", action="store_true")
    parser.add_argument("--skip-asan", action="store_true")
    parser.add_argument("--asan-swift", default="swift")
    args = parser.parse_args()
    python_tests = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "scripts").glob("*_test.py"))
    commands = [
        ["python3", "scripts/verify_fixtures.py"],
        ["python3", "scripts/verify_milestone5.py"],
        ["python3", "scripts/verify_oracle.py"],
        ["python3", "scripts/verify_repository.py"],
        ["python3", "scripts/verify_product_boundaries.py"],
        ["python3", "scripts/check_reference_ufo.py", "Tests/Fixtures/oracle/v1/reference-source/VirtuaGrotesk-Regular.ufo"],
        ["python3", "scripts/generate_deterministic_fixtures.py", "--check"],
        ["python3", "scripts/generate_malformed_corpus.py", "--check"],
        ["python3", "scripts/promote_generated_fixtures.py", "--check"],
        [
            "python3", "scripts/verify_release_candidate.py", "--release",
            "/Volumes/T9/beztrace/milestone-5/release",
        ],
        *(["python3", path] for path in python_tests),
        ["python3", "-m", "py_compile", *sorted(str(path.relative_to(ROOT)) for path in (ROOT / "scripts").glob("*.py"))],
        ["bash", "-n", "scripts/capture_img2bez_oracle.sh"],
        ["bash", "-n", "scripts/build_release_candidate.sh"],
        ["bash", "-n", "release/package-scripts/preinstall"],
        ["swift", "test", "--configuration", "release", "--disable-swift-testing"],
        ["swift", "build", "--configuration", "release"],
        ["git", "diff", "--check"],
    ]
    if not args.skip_asan:
        commands.append(asan_command(args.asan_swift))
    if not args.skip_x86:
        commands.append([
            "arch", "-x86_64", "swift", "test", "--disable-swift-testing",
            "--configuration", "release", "--triple", "x86_64-apple-macosx13.0",
            "--scratch-path", ".build/x86_64-target",
        ])
    clean_before = tracked_status() == ""
    records: list[dict] = []
    for index, command in enumerate(commands, 1):
        print(f"[{index:02d}/{len(commands):02d}] {' '.join(command)}", flush=True)
        record = execute(command)
        records.append(record)
        if record["status"] == "fail":
            print(record["outputTail"], flush=True)
    clean_after = tracked_status() == ""
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.strip()
    report = {
        "schemaVersion": 1,
        "revision": revision,
        "cleanBefore": clean_before,
        "cleanAfter": clean_after,
        "cleanWorktree": clean_before and clean_after,
        "allPassed": all(item["status"] == "pass" for item in records),
        "commands": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote viability test evidence to {args.output}")
    return 0 if report["allPassed"] and report["cleanWorktree"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
