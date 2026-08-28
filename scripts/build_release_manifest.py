#!/usr/bin/env python3
"""Write deterministic candidate or final beztrace release metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument(
        "--release-kind",
        choices=("candidate", "final"),
        default="candidate",
    )
    parser.add_argument("--signed-binary", action="store_true")
    parser.add_argument("--signed-package", action="store_true")
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    release = args.release.resolve()
    label = "0.1.0-rc.1" if args.release_kind == "candidate" else "0.1.0"
    artifacts = []
    for name, signed in (
        (f"beztrace-{label}-macos-universal.zip", args.signed_binary),
        (f"beztrace-{label}.pkg", args.signed_package),
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
    sbom = {
        "format": "SPDX",
        "version": "2.3",
        "source": f"beztrace-{label}-stage/root/Library/Application Support/beztrace/share/sbom-source.spdx.json",
        "binary": f"beztrace-{label}-stage/root/Library/Application Support/beztrace/share/sbom-binary.spdx.json",
    }
    if args.release_kind == "final":
        sbom["releaseSource"] = f"beztrace-{label}-source.spdx.json"
        sbom["releaseBinary"] = f"beztrace-{label}-binary.spdx.json"
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "name": "beztrace",
        "version": "0.1.0",
        "minimumMacOS": "13.0",
        "architectures": ["arm64", "x86_64"],
        "artifacts": artifacts,
        "sbom": sbom,
    }
    if args.release_kind == "candidate":
        payload["candidate"] = "rc.1"
    else:
        payload["sourceRevision"] = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    (release / "release-manifest.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"wrote {release / 'release-manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
