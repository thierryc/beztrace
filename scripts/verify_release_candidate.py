#!/usr/bin/env python3
"""Verify the local universal release-candidate staging and artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--require-signed-binary", action="store_true")
    parser.add_argument("--require-signed-package", action="store_true")
    args = parser.parse_args()
    release = args.release.resolve()
    stage = release / "beztrace-0.1.0-rc.1-stage" / "root"
    support = stage / "Library" / "Application Support" / "beztrace"
    binary = support / "bin" / "beztrace"
    share = support / "share"
    link = stage / "usr" / "local" / "bin" / "beztrace"
    zip_path = release / "beztrace-0.1.0-rc.1-macos-universal.zip"
    package = release / "beztrace-0.1.0-rc.1.pkg"
    failures: list[str] = []
    required = [
        binary, share / "LICENSE-APACHE", share / "LICENSE-MIT", share / "THIRD_PARTY_NOTICES",
        share / "README.md", share / "trace-result-v1.schema.json",
        share / "sbom-source.spdx.json", share / "sbom-binary.spdx.json", zip_path, package,
        release / "SHA256SUMS", release / "release-manifest.json",
    ]
    for path in required:
        if not path.is_file(): failures.append(f"missing {path}")
    if not link.is_symlink() or link.readlink().as_posix() != "/Library/Application Support/beztrace/bin/beztrace":
        failures.append("staged /usr/local/bin/beztrace symlink is missing or incorrect")
    if binary.is_file():
        process = subprocess.run(["lipo", "-archs", str(binary)], capture_output=True, text=True)
        if set(process.stdout.split()) != {"arm64", "x86_64"}:
            failures.append(f"unexpected binary architectures: {process.stdout.strip()}")
        if args.require_signed_binary and subprocess.run(
            ["codesign", "--verify", "--strict", str(binary)], capture_output=True
        ).returncode:
            failures.append("binary signature verification failed")
    if args.require_signed_package and package.is_file() and subprocess.run(
        ["pkgutil", "--check-signature", str(package)], capture_output=True
    ).returncode:
        failures.append("package signature verification failed")
    for name in ("sbom-source.spdx.json", "sbom-binary.spdx.json"):
        path = share / name
        if path.is_file():
            payload = json.loads(path.read_text(encoding="utf-8"))
            if payload.get("spdxVersion") != "SPDX-2.3" or payload.get("dataLicense") != "CC0-1.0":
                failures.append(f"invalid SPDX header in {name}")
    sums = release / "SHA256SUMS"
    if sums.is_file():
        expected = {}
        for line in sums.read_text(encoding="utf-8").splitlines():
            digest, name = line.split(maxsplit=1)
            expected[name] = digest
        for path in (zip_path, package):
            if path.is_file() and expected.get(path.name) != sha256(path):
                failures.append(f"checksum mismatch for {path.name}")
    manifest_path = release / "release-manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("architectures") != ["arm64", "x86_64"]:
            failures.append("release manifest architecture order differs")
        records = {item.get("path"): item for item in manifest.get("artifacts", [])}
        for path in (zip_path, package):
            record = records.get(path.name, {})
            if path.is_file() and (record.get("sha256") != sha256(path) or record.get("size") != path.stat().st_size):
                failures.append(f"release manifest mismatch for {path.name}")
    if failures:
        print("release-candidate verification failed:")
        for failure in failures: print(f"- {failure}")
        return 1
    print("verified universal release-candidate staging, artifacts, checksums, and SPDX SBOMs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
