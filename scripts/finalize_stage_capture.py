#!/usr/bin/env python3
"""Finalize wrapper-owned hashes and validate common stage invariants."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


def finite(value: object) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, list):
        return all(finite(item) for item in value)
    if isinstance(value, dict):
        return all(finite(item) for item in value.values())
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    args = parser.parse_args()
    raster = args.capture / "prepared-raster.png"
    metadata = args.capture / "prepared-raster.json"
    required = {"subpixel-contours.json", "cleaned.json", "validated.json"}
    missing = sorted(name for name in required if not (args.capture / name).is_file())
    if missing or not raster.is_file() or not metadata.is_file():
        raise SystemExit("incomplete stage capture: " + ", ".join(missing))
    value = json.loads(metadata.read_text(encoding="utf-8"))
    value["rasterPNG_SHA256"] = hashlib.sha256(raster.read_bytes()).hexdigest()
    metadata.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for path in sorted(args.capture.glob("*.json")):
        if path.name == "final.json":
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("schemaVersion") != 1 or not finite(payload):
            raise SystemExit(f"invalid stage JSON: {path}")
    print(f"finalized {args.capture}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
