#!/usr/bin/env python3
"""Record reproducible single-shot timings for the pinned img2bez binary."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--peak-rss-bytes", type=int, help="Value from one matching /usr/bin/time -l run")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 3:
        raise SystemExit("--samples must be at least 3")
    binary = args.binary.resolve()
    fixture = FIXTURES / "corpus" / "generated" / "glyphs" / "glyph-upper-r.png"
    values = []
    with tempfile.TemporaryDirectory(prefix="beztrace-bench-") as temporary:
        output = Path(temporary) / "trace.json"
        command = [str(binary), "--input", str(fixture), "--output", str(output),
                   "--name", "R", "--unicode", "0052", "--format", "json",
                   "--profile", "clean", "--target-height", "1088", "--y-offset", "0"]
        subprocess.run(command, check=True, capture_output=True)  # warm-up
        for _ in range(args.samples):
            start = time.perf_counter_ns()
            subprocess.run(command, check=True, capture_output=True)
            values.append((time.perf_counter_ns() - start) / 1_000_000)
    result = {
        "schemaVersion": 1,
        "sourceRevision": "23073ca08ecdac61ad0e838bfae49a590bc2c7cc",
        "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "fixture": "glyph-upper-r-generated",
        "fixtureSHA256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
        "buildMode": "release",
        "state": "one unrecorded warm-up followed by warm single-shot subprocess samples",
        "clock": "time.perf_counter_ns wall clock",
        "sampleCount": args.samples,
        "medianMs": round(statistics.median(values), 3),
        "p95Ms": round(percentile(values, 0.95), 3),
        "samplesMs": [round(value, 3) for value in values],
        "environment": {"platform": platform.platform(), "machine": platform.machine()},
        "peakRSSBytes": args.peak_rss_bytes,
        "peakRSSMethod": "/usr/bin/time -l maximum resident set size" if args.peak_rss_bytes else "not recorded",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"median={result['medianMs']:.3f}ms p95={result['p95Ms']:.3f}ms n={args.samples}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
