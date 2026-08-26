#!/usr/bin/env python3
"""Record comparable Milestone 5 Rust or Swift tracing evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import re
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
PORT_REVISION = "23073ca08ecdac61ad0e838bfae49a590bc2c7cc"
BENCHMARKS = [
    ("glyph-upper-r-generated", "corpus/generated/glyphs/glyph-upper-r.png", "R", "0052"),
    ("glyph-upper-o", "corpus/deterministic/glyphs/glyph-upper-o.png", "O", "004F"),
    ("glyph-8", "corpus/deterministic/glyphs/glyph-8.png", "eight", "0038"),
    ("glyph-upper-s-generated", "corpus/generated/glyphs/glyph-upper-s.png", "S", "0053"),
    ("symbol-heart", "corpus/deterministic/symbols/symbol-heart.png", "heart", "E000"),
]
RUST_TIMING = re.compile(r"Result\s+.*\((\d+)ms\)")
RSS = re.compile(r"^\s*(\d+)\s+maximum resident set size\s*$", re.MULTILINE)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def production_source_sha256() -> str:
    digest = hashlib.sha256()
    paths = [ROOT / "Package.swift", *sorted((ROOT / "Sources").rglob("*.swift"))]
    for path in paths:
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1)]


def swift_sample(binary: Path, fixture: Path, output: Path) -> tuple[float, float]:
    command = [
        str(binary), "trace", str(fixture), "--format", "json",
        "--diagnostics", "summary", "--output", str(output),
    ]
    started = time.perf_counter_ns()
    subprocess.run(command, check=True, capture_output=True)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000
    payload = json.loads(output.read_text(encoding="utf-8"))
    return float(payload["timingsMs"]["total"]), elapsed


def rust_sample(
    binary: Path, fixture: Path, output: Path, glyph_name: str, unicode_value: str
) -> tuple[float, float]:
    command = [
        str(binary), "--input", str(fixture), "--output", str(output),
        "--name", glyph_name, "--unicode", unicode_value, "--format", "json",
        "--profile", "clean", "--target-height", "1088", "--y-offset", "0",
    ]
    started = time.perf_counter_ns()
    process = subprocess.run(command, check=True, capture_output=True, text=True)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000
    match = RUST_TIMING.search(process.stderr)
    if not match:
        raise RuntimeError("img2bez output did not contain its internal Result timing")
    return float(match.group(1)), elapsed


def peak_rss(command: list[str]) -> int:
    process = subprocess.run(["/usr/bin/time", "-l", *command], capture_output=True, text=True)
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, command, process.stdout, process.stderr)
    match = RSS.search(process.stderr)
    if not match:
        raise RuntimeError("/usr/bin/time -l did not report maximum resident set size")
    return int(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", choices=("swift", "rust"), required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--rust-toolchain", default="1.88.0-aarch64-apple-darwin")
    args = parser.parse_args()
    if args.warmups != 3 or args.samples != 30:
        raise SystemExit("release evidence requires exactly 3 warmups and 30 samples")
    binary = args.binary.resolve()
    if not binary.is_file():
        raise SystemExit(f"binary does not exist: {binary}")

    records: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="beztrace-benchmark-") as temporary:
        temporary_root = Path(temporary)
        for fixture_id, relative, glyph_name, unicode_value in BENCHMARKS:
            fixture = FIXTURES / relative
            output = temporary_root / f"{fixture_id}.json"
            if args.engine == "swift":
                sample = lambda: swift_sample(binary, fixture, output)
                memory_command = [
                    str(binary), "trace", str(fixture), "--format", "json",
                    "--output", str(output),
                ]
            else:
                sample = lambda: rust_sample(binary, fixture, output, glyph_name, unicode_value)
                memory_command = [
                    str(binary), "--input", str(fixture), "--output", str(output),
                    "--name", glyph_name, "--unicode", unicode_value, "--format", "json",
                    "--profile", "clean", "--target-height", "1088", "--y-offset", "0",
                ]
            cold_core, cold_process = sample()
            for _ in range(args.warmups):
                sample()
            core_values: list[float] = []
            process_values: list[float] = []
            for _ in range(args.samples):
                core, process = sample()
                core_values.append(core)
                process_values.append(process)
            record = {
                "id": fixture_id,
                "path": relative,
                "sha256": sha256(fixture),
                "coldMs": round(cold_core, 6),
                "coldProcessMs": round(cold_process, 6),
                "samplesMs": [round(value, 6) for value in core_values],
                "processSamplesMs": [round(value, 6) for value in process_values],
                "medianMs": round(statistics.median(core_values), 6),
                "p95Ms": round(percentile(core_values, 0.95), 6),
                "processMedianMs": round(statistics.median(process_values), 6),
                "processP95Ms": round(percentile(process_values, 0.95), 6),
                "peakRSSBytes": peak_rss(memory_command),
            }
            records.append(record)
            print(
                f"{fixture_id}: core median={record['medianMs']:.3f} ms "
                f"p95={record['p95Ms']:.3f} ms process p95={record['processP95Ms']:.3f} ms"
            )

    revision = (
        PORT_REVISION
        if args.engine == "rust"
        else subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True
        ).stdout.strip()
    )
    result = {
        "schemaVersion": 1,
        "engine": "img2bez-rust" if args.engine == "rust" else "beztrace-swift",
        "revision": revision,
        "binarySHA256": sha256(binary),
        "productionSourceSHA256": production_source_sha256() if args.engine == "swift" else None,
        "environment": {
            "hardware": platform.processor() or platform.machine(),
            "os": platform.platform(),
            "architecture": platform.machine(),
            "toolchain": subprocess.run(
                ["rustup", "run", args.rust_toolchain, "rustc", "--version"]
                if args.engine == "rust" else ["swift", "--version"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip(),
            "buildMode": "release",
        },
        "protocol": {
            "warmups": args.warmups,
            "samples": args.samples,
            "percentileMethod": "nearest-rank",
            "timingScope": "engine internal trace timer including decode; subprocess wall time recorded separately",
        },
        "fixtures": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
