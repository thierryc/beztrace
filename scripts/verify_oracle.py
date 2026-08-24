#!/usr/bin/env python3
"""Fail-closed validation for a published immutable oracle directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


REVISION = "23073ca08ecdac61ad0e838bfae49a590bc2c7cc"
FORBIDDEN_PUBLIC_BYTES = (
    b"/Users/", b"/home/", b"/private/var/folders/", b"test-work/", b"thierryc"
)
STAGE_FILES = {
    "subpixel-contours.json": "subpixelContours",
    "cleaned.json": "cleaned",
    "validated.json": "validated",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finite(value: object) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, list):
        return all(finite(item) for item in value)
    if isinstance(value, dict):
        return all(finite(item) for item in value.values())
    return True


def declared_contours(topology: str) -> int:
    """Translate the reviewed v1 topology vocabulary into contour counts."""
    if "two counters" in topology:
        return 3
    if "one counter" in topology or "central counter" in topology:
        return 2
    return 1


def validate_stage(relative: str, value: object) -> list[str]:
    if not isinstance(value, dict) or not relative.startswith("basic-latin/"):
        return []
    name = Path(relative).name
    expected_stage = STAGE_FILES.get(name)
    if name == "prepared-raster.json":
        expected_stage = "preparedRaster"
        required = {"width", "height", "threshold", "invert", "rasterPNG_SHA256"}
        if not required.issubset(value):
            return [f"malformed prepared raster metadata: {relative}"]
    elif name.startswith("structural-plan-"):
        expected_stage = "structuralPlan"
    elif name.startswith("initial-fit-"):
        expected_stage = "initialFit"
    elif name.startswith("raster-refined-"):
        expected_stage = "rasterRefined"
    elif name == "final.json":
        return []
    if expected_stage is None:
        return []
    required = {"schemaVersion", "sourceRevision", "fixtureID", "stage"}
    if not required.issubset(value):
        return [f"missing stage metadata: {relative}"]
    if value.get("schemaVersion") != 1 or value.get("sourceRevision") != REVISION:
        return [f"wrong stage schema or source revision: {relative}"]
    if value.get("stage") != expected_stage:
        return [f"wrong stage name in {relative}: {value.get('stage')!r}"]
    return []


def privacy_failures(root: Path) -> list[str]:
    failures = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        data = path.read_bytes()
        if b"\0" in data:
            continue
        for marker in FORBIDDEN_PUBLIC_BYTES:
            if marker in data:
                relative = path.relative_to(root).as_posix()
                failures.append(f"machine-local data {marker.decode()!r} in {relative}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("oracle", type=Path, nargs="?", default=Path("Tests/Fixtures/oracle/v1"))
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()
    root = args.oracle
    manifest_path = root / "oracle-manifest.json"
    reference = json.loads((root / "reference.json").read_text(encoding="utf-8"))
    failures: list[str] = []
    corpus_manifest = root / "corpus" / "corpus-manifest.json"
    fixture_manifest = json.loads((root.parents[1] / "manifest.json").read_text(encoding="utf-8"))
    expected = {item["id"]: item for item in fixture_manifest["fixtures"]}
    if not corpus_manifest.is_file():
        failures.append("corpus/corpus-manifest.json is missing")
    else:
        corpus = json.loads(corpus_manifest.read_text(encoding="utf-8"))
        records = corpus.get("fixtures", [])
        if len(records) != 24 or corpus.get("determinismRuns") != 2:
            failures.append("corpus capture must contain 24 fixtures and two runs")
        for record in records:
            fixture_id = record.get("id", "")
            fixture = expected.get(fixture_id)
            if fixture is None or record.get("contours") != declared_contours(fixture["expectedTopology"]):
                failures.append(f"declared topology mismatch: {fixture_id}")
            for suffix, field in ((".json", "jsonSHA256"), (".stats.json", "statsSHA256")):
                path = root / "corpus" / f"{fixture_id}{suffix}"
                if not path.is_file() or sha256(path) != record.get(field):
                    failures.append(f"corpus hash mismatch: {path.name}")
    patch_path = root / "reference-patches" / "0001-stage-capture.patch"
    if not patch_path.is_file() or sha256(patch_path) != reference.get("instrumentationPatchSHA256"):
        failures.append("instrumentation patch is missing or does not match reference metadata")
    if not manifest_path.is_file():
        if args.allow_incomplete and reference.get("captureStatus", "").startswith("blocked-") and not failures:
            print(f"oracle incomplete: {reference['captureStatus']}")
            return 0
        print("oracle verification failed: oracle-manifest.json is missing")
        for failure in failures:
            print(f"- {failure}")
        return 1
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    paths = [item["path"] for item in manifest.get("files", [])]
    if paths != sorted(paths) or len(paths) != len(set(paths)):
        failures.append("manifest file ordering is not unique and lexical")
    excluded = {"oracle-manifest.json", "reference.json"}
    actual = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*") if path.is_file()
        if path.relative_to(root).as_posix() not in excluded
        and not path.relative_to(root).as_posix().startswith("schemas/")
    }
    if set(paths) != actual:
        failures.append("manifest coverage does not match published oracle files")
    for item in manifest.get("files", []):
        path = root / item["path"]
        if not path.is_file():
            failures.append(f"missing {item['path']}")
            continue
        if path.stat().st_size != item["bytes"] or sha256(path) != item["sha256"]:
            failures.append(f"hash or size mismatch: {item['path']}")
        if path.suffix == ".json":
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
                if not finite(value):
                    failures.append(f"non-finite JSON number: {item['path']}")
                failures.extend(validate_stage(item["path"], value))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                failures.append(f"invalid JSON {item['path']}: {error}")
    if reference.get("captureStatus") != "complete":
        failures.append(f"reference capture status is {reference.get('captureStatus')!r}")
    failures.extend(privacy_failures(root))
    if failures:
        print("oracle verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"verified {len(paths)} immutable oracle files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
