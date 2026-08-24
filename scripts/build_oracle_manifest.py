#!/usr/bin/env python3
"""Build the lexically ordered manifest for a completed oracle capture."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path

REVISION = "23073ca08ecdac61ad0e838bfae49a590bc2c7cc"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("oracle", type=Path)
    parser.add_argument("--reference-ufo-sha256", required=True)
    parser.add_argument("--instrumentation-patch", type=Path, required=True)
    args = parser.parse_args()
    excluded = {"oracle-manifest.json", "reference.json"}
    files = []
    paths = (item for item in args.oracle.rglob("*") if item.is_file())
    for path in sorted(paths, key=lambda item: item.relative_to(args.oracle).as_posix()):
        relative = path.relative_to(args.oracle).as_posix()
        if relative in excluded or relative.startswith("schemas/"):
            continue
        files.append({"path": relative, "sha256": sha256(path), "bytes": path.stat().st_size})
    manifest = {
        "schemaVersion": 1,
        "sourceRevision": REVISION,
        "referenceUFOSHA256": args.reference_ufo_sha256,
        "instrumentationPatchSHA256": sha256(args.instrumentation_patch),
        "environment": {
            "platform": platform.platform(), "machine": platform.machine(),
            "rustc": subprocess.run(["rustup", "run", "1.88.0", "rustc", "--version"], check=True, text=True, capture_output=True).stdout.strip(),
            "cargo": subprocess.run(["rustup", "run", "1.88.0", "cargo", "--version"], check=True, text=True, capture_output=True).stdout.strip(),
        },
        "commands": [
            "scripts/capture_img2bez_oracle.sh",
            "python3 scripts/verify_oracle.py Tests/Fixtures/oracle/v1"
        ],
        "timingConvention": {"clock": "monotonic wall clock", "buildMode": "release", "warmColdState": "recorded per benchmark", "units": "milliseconds"},
        "files": files,
    }
    (args.oracle / "oracle-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"manifested {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
