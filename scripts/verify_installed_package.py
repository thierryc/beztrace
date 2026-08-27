#!/usr/bin/env python3
"""Verify the installed notarized package and write Milestone 6 evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import tempfile
from pathlib import Path

from verify_packaged_workflow import validate_outputs

ROOT = Path(__file__).resolve().parents[1]
RELEASE = Path("/Volumes/T9/beztrace/milestone-5/release")
OUTPUT = Path("/Volumes/T9/beztrace/milestone-6/reports/installed-package.json")
PACKAGE_ID = "dev.beztrace.cli"
VERSION = "0.1.0"
INSTALLED_BINARY = Path("/Library/Application Support/beztrace/bin/beztrace")
INSTALLED_LINK = Path("/usr/local/bin/beztrace")
EXPECTED_LINK = "/Library/Application Support/beztrace/bin/beztrace"
FIXTURE = ROOT / "Tests/Fixtures/corpus/deterministic/glyphs/glyph-upper-a.png"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def validate_record(record: dict) -> list[str]:
    failures: list[str] = []
    if record.get("packageID") != PACKAGE_ID or record.get("version") != VERSION:
        failures.append("installed receipt identity or version differs")
    if record.get("receiptPresent") is not True:
        failures.append("installed package receipt is missing")
    if record.get("symlinkTarget") != EXPECTED_LINK:
        failures.append("installed command symlink target differs")
    if set(record.get("architectures", [])) != {"arm64", "x86_64"}:
        failures.append("installed binary is not universal")
    for key, label in (
        ("binarySignatureValid", "installed binary signature"),
        ("packageSignatureValid", "installer signature"),
        ("notarizationTrusted", "installer notarization"),
        ("stapleValid", "stapled notarization ticket"),
        ("gatekeeperAccepted", "Gatekeeper installer assessment"),
        ("jsonTraceValid", "installed JSON trace"),
        ("svgTraceValid", "installed SVG trace"),
    ):
        if record.get(key) is not True:
            failures.append(f"{label} failed")
    if record.get("installedBinarySHA256") != record.get("packagedBinarySHA256"):
        failures.append("installed and packaged binary hash differs")
    if record.get("versionOutput") != "beztrace 0.1.0":
        failures.append("installed CLI version differs")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, default=RELEASE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--fixture", type=Path, default=FIXTURE)
    args = parser.parse_args()
    release = args.release.resolve()
    package = release / "beztrace-0.1.0-rc.1.pkg"
    archive = release / "beztrace-0.1.0-rc.1-macos-universal.zip"
    fixture = args.fixture.resolve()
    record: dict = {
        "schemaVersion": 1,
        "status": "fail",
        "packageID": PACKAGE_ID,
        "version": VERSION,
        "package": str(package),
        "archive": str(archive),
        "installedBinary": str(INSTALLED_BINARY),
    }
    receipt = run(["pkgutil", "--pkg-info-plist", PACKAGE_ID])
    record["receiptPresent"] = receipt.returncode == 0
    if not receipt.returncode:
        payload = plistlib.loads(receipt.stdout)
        record["receipt"] = {
            "packageID": payload.get("pkgid"),
            "version": payload.get("pkg-version"),
            "volume": payload.get("volume"),
            "installTime": payload.get("install-time"),
        }
        record["packageID"] = payload.get("pkgid")
        record["version"] = payload.get("pkg-version")
    record["symlinkTarget"] = os.readlink(INSTALLED_LINK) if INSTALLED_LINK.is_symlink() else None
    lipo = run(["lipo", "-archs", str(INSTALLED_BINARY)])
    record["architectures"] = sorted(lipo.stdout.decode("utf-8", "replace").split()) if not lipo.returncode else []
    binary_signature = run(["codesign", "--verify", "--strict", "--verbose=2", str(INSTALLED_BINARY)])
    record["binarySignatureValid"] = binary_signature.returncode == 0
    package_signature = run(["pkgutil", "--check-signature", str(package)])
    package_signature_text = (package_signature.stdout + package_signature.stderr).decode("utf-8", "replace")
    record["packageSignatureValid"] = package_signature.returncode == 0
    record["notarizationTrusted"] = "Notarization: trusted by the Apple notary service" in package_signature_text
    staple = run(["xcrun", "stapler", "validate", str(package)])
    record["stapleValid"] = staple.returncode == 0
    gatekeeper = run(["spctl", "--assess", "--type", "install", "--verbose=4", str(package)])
    record["gatekeeperAccepted"] = gatekeeper.returncode == 0
    version = run([str(INSTALLED_LINK), "--version"])
    record["versionOutput"] = version.stdout.decode("utf-8", "replace").strip() if not version.returncode else None
    if INSTALLED_BINARY.is_file():
        record["installedBinarySHA256"] = sha256(INSTALLED_BINARY)
    with tempfile.TemporaryDirectory(prefix="beztrace-installed-package-") as temporary:
        root = Path(temporary)
        extract = run(["ditto", "-x", "-k", str(archive), str(root)])
        packaged_binary = root / "beztrace/bin/beztrace"
        record["packagedBinarySHA256"] = sha256(packaged_binary) if not extract.returncode and packaged_binary.is_file() else None
        json_path, svg_path = root / "installed.json", root / "installed.svg"
        json_run = run([
            str(INSTALLED_LINK), "trace", str(fixture), "--format", "json", "--output", str(json_path),
        ])
        svg_run = run([
            str(INSTALLED_LINK), "trace", str(fixture), "--format", "svg", "--output", str(svg_path),
        ])
        record["jsonTraceValid"] = False
        record["svgTraceValid"] = False
        if not json_run.returncode and json_path.is_file():
            result = json.loads(json_path.read_text(encoding="utf-8"))
            record["jsonTraceValid"] = (
                result.get("schemaVersion") == 1
                and result.get("pathDataVersion") == 2
                and len(result.get("paths", [])) > 0
            )
            record["installedWorkflow"] = {
                "status": "fail",
                "contourCount": len(result.get("paths", [])),
                "nodeCount": sum(len(item.get("nodes", [])) for item in result.get("paths", [])),
            }
        if not svg_run.returncode and svg_path.is_file():
            svg = svg_path.read_text(encoding="utf-8")
            record["svgTraceValid"] = not validate_outputs(
                json.loads(json_path.read_text(encoding="utf-8")), svg, sha256(fixture)
            ) if json_path.is_file() else False
        if "installedWorkflow" in record:
            record["installedWorkflow"]["status"] = (
                "pass" if record["jsonTraceValid"] and record["svgTraceValid"] else "fail"
            )
    failures = validate_record(record)
    record["failures"] = failures
    record["status"] = "pass" if not failures else "fail"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("installed package verification passed" if not failures else "installed package verification failed")
    for failure in failures:
        print(f"- {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
