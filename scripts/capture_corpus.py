#!/usr/bin/env python3
"""Capture deterministic img2bez JSON/stats evidence for the 24-image corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unicode_for(item: dict[str, object]) -> str | None:
    content = str(item["content"])
    return f"{ord(content):04X}" if len(content) == 1 else None


def run_trace(binary: Path, item: dict[str, object], output: Path) -> bytes:
    command = [
        str(binary), "--input", str(FIXTURES / str(item["path"])),
        "--output", str(output), "--name", str(item["id"]),
        "--format", "json", "--profile", "clean", "--target-height", "1088",
        "--y-offset", "0",
    ]
    if codepoint := unicode_for(item):
        command.extend(["--unicode", codepoint])
    subprocess.run(command, check=True, capture_output=True)
    return output.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=FIXTURES / "oracle" / "v1" / "corpus")
    args = parser.parse_args()
    binary = args.binary.resolve()
    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix="beztrace-corpus-") as temporary:
        temp = Path(temporary)
        for item in manifest["fixtures"]:
            fixture_id = item["id"]
            first = run_trace(binary, item, temp / f"{fixture_id}-a.json")
            second = run_trace(binary, item, temp / f"{fixture_id}-b.json")
            if first != second:
                raise SystemExit(f"nondeterministic JSON output for {fixture_id}")
            parsed = json.loads(first)
            if not parsed.get("outline", {}).get("contours"):
                raise SystemExit(f"empty outline for {fixture_id}")
            destination = args.output / f"{fixture_id}.json"
            destination.write_bytes(first)
            stats_bytes = subprocess.run(
                [str(binary), "stats", str(FIXTURES / item["path"])],
                check=True, capture_output=True,
            ).stdout
            json.loads(stats_bytes)
            stats_path = args.output / f"{fixture_id}.stats.json"
            stats_path.write_bytes(stats_bytes)
            records.append({
                "id": fixture_id,
                "inputSHA256": item["sha256"],
                "jsonSHA256": digest(first),
                "statsSHA256": digest(stats_bytes),
                "contours": len(parsed["outline"]["contours"]),
                "points": sum(len(contour["points"]) for contour in parsed["outline"]["contours"]),
            })
    result = {
        "schemaVersion": 1,
        "sourceRevision": "23073ca08ecdac61ad0e838bfae49a590bc2c7cc",
        "binarySHA256": digest(binary.read_bytes()),
        "options": {"profile": "clean", "targetHeight": 1088, "yOffset": 0},
        "determinismRuns": 2,
        "fixtures": records,
    }
    (args.output / "corpus-manifest.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"captured {len(records)} deterministic corpus results in {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
