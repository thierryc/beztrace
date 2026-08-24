#!/usr/bin/env python3
"""Validate and fingerprint an externally supplied img2bez reference UFO."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def tree_hash(root: Path) -> tuple[str, list[dict[str, object]]]:
    digest = hashlib.sha256()
    files = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix()
        data = path.read_bytes()
        item_hash = hashlib.sha256(data).hexdigest()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(item_hash))
        files.append({"path": relative, "sha256": item_hash, "bytes": len(data)})
    return digest.hexdigest(), files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ufo", type=Path)
    parser.add_argument("--license", required=True, help="SPDX identifier or reviewed license description")
    parser.add_argument("--provenance", required=True, help="Source revision or delivery provenance")
    parser.add_argument("--received", required=True, help="Receipt date in YYYY-MM-DD form")
    args = parser.parse_args()
    root = args.ufo.resolve()
    checker = Path(__file__).with_name("check_reference_ufo.py")
    subprocess.run([str(checker), str(root), "--quiet"], check=True)
    digest, files = tree_hash(root)
    result = {
        "schemaVersion": 1,
        "referenceUFOSHA256": digest,
        "license": args.license,
        "provenance": args.provenance,
        "received": args.received,
        "fileCount": len(files),
        "files": files,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
