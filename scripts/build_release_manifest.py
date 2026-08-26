#!/usr/bin/env python3
"""Write the deterministic Milestone 5 release-candidate evidence manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--signed-binary", action="store_true")
    parser.add_argument("--signed-package", action="store_true")
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    release = args.release.resolve()
    artifacts = []
    for name, signed in (
        ("beztrace-0.1.0-rc.1-macos-universal.zip", args.signed_binary),
        ("beztrace-0.1.0-rc.1.pkg", args.signed_package),
    ):
        path = release / name
        if not path.is_file(): raise SystemExit(f"missing release artifact: {path}")
        artifacts.append({
            "path": name,
            "sha256": sha256(path),
            "size": path.stat().st_size,
            "signed": signed,
            "notarized": args.notarized,
        })
    payload = {
        "schemaVersion": 1,
        "name": "beztrace",
        "version": "0.1.0",
        "candidate": "rc.1",
        "minimumMacOS": "13.0",
        "architectures": ["arm64", "x86_64"],
        "artifacts": artifacts,
        "sbom": {
            "format": "SPDX",
            "version": "2.3",
            "source": "beztrace-0.1.0-rc.1-stage/root/Library/Application Support/beztrace/share/sbom-source.spdx.json",
            "binary": "beztrace-0.1.0-rc.1-stage/root/Library/Application Support/beztrace/share/sbom-binary.spdx.json",
        },
    }
    (release / "release-manifest.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"wrote {release / 'release-manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
