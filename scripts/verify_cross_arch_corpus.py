#!/usr/bin/env python3
"""Compare arm64 and x86_64 JSON bytes for the complete frozen corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
DEFAULT_X86 = Path(
    "/private/tmp/beztrace-m5-x86-target/x86_64-apple-macosx/release/beztrace"
)
DEFAULT_OUTPUT = Path(
    "/Volumes/T9/beztrace/milestone-5/reports/cross-architecture-corpus.json"
)


def run(command: list[str], source: Path) -> bytes:
    process = subprocess.run(
        [*command, "trace", str(source), "--format", "json"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode != 0:
        raise RuntimeError(
            f"{source.name}: {' '.join(command)} failed ({process.returncode}): "
            f"{process.stderr.decode('utf-8', 'replace')}"
        )
    return process.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm-binary", type=Path, default=ROOT / ".build" / "release" / "beztrace")
    parser.add_argument("--x86-binary", type=Path, default=DEFAULT_X86)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    arm = args.arm_binary.resolve()
    x86 = args.x86_binary.resolve()
    if not arm.is_file() or not x86.is_file():
        raise FileNotFoundError(f"architecture binary missing: arm64={arm}, x86_64={x86}")

    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    fixtures = manifest["fixtures"]
    if len(fixtures) != 100:
        raise ValueError(f"expected the frozen 100-image corpus, found {len(fixtures)}")

    records: list[dict] = []
    failures: list[str] = []
    for index, fixture in enumerate(fixtures, 1):
        source = FIXTURES / fixture["path"]
        arm_bytes = run([str(arm)], source)
        x86_bytes = run(["arch", "-x86_64", str(x86)], source)
        arm_hash = hashlib.sha256(arm_bytes).hexdigest()
        x86_hash = hashlib.sha256(x86_bytes).hexdigest()
        identical = arm_bytes == x86_bytes
        if not identical:
            failures.append(fixture["id"])
        records.append(
            {
                "id": fixture["id"],
                "arm64SHA256": arm_hash,
                "x86_64SHA256": x86_hash,
                "byteIdentical": identical,
            }
        )
        print(f"[{index:03d}/100] {fixture['id']}: {'identical' if identical else 'DIFFERS'}", flush=True)

    report = {
        "schemaVersion": 1,
        "corpusCount": len(fixtures),
        "arm64Binary": str(arm),
        "x86_64Binary": str(x86),
        "allByteIdentical": not failures,
        "fixtures": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if failures:
        print("cross-architecture output differs for: " + ", ".join(failures))
        return 1
    print(f"verified byte-identical arm64/x86_64 JSON for {len(fixtures)} fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
