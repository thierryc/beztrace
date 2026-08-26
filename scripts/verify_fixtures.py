#!/usr/bin/env python3
"""Validate fixture dimensions, hashes, provenance, and review state."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("not a PNG with a valid IHDR header")
    return struct.unpack(">II", header[16:24])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--allow-pending", action="store_true")
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="require the complete 100-image Milestone 5 corpus",
    )
    args = parser.parse_args()
    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    plan = json.loads(
        (FIXTURES / "corpus" / "milestone-5-plan.json").read_text(encoding="utf-8")
    )
    failures: list[str] = []
    entries = manifest.get("fixtures", [])
    target = plan["target"]
    counts = {
        "total": len(entries),
        "deterministic": sum(item.get("sourceKind") == "deterministic" for item in entries),
        "generated": sum(item.get("sourceKind") == "generated" for item in entries),
        "glyphs": sum(item.get("category") == "glyph" for item in entries),
        "symbols": sum(item.get("category") == "symbol" for item in entries),
    }
    expected = target
    for key in ("total", "deterministic", "generated", "glyphs", "symbols"):
        if counts[key] != expected[key]:
            failures.append(f"expected {expected[key]} {key}, found {counts[key]}")

    identifiers = [item.get("id") for item in entries]
    paths = [item.get("path") for item in entries]
    if len(identifiers) != len(set(identifiers)):
        failures.append("fixture identifiers must be unique")
    if len(paths) != len(set(paths)):
        failures.append("fixture paths must be unique")

    manifested_paths = set(paths)
    corpus_paths = {
        str(path.relative_to(FIXTURES))
        for directory in (
            FIXTURES / "corpus" / "deterministic" / "glyphs",
            FIXTURES / "corpus" / "deterministic" / "symbols",
            FIXTURES / "corpus" / "generated" / "glyphs",
            FIXTURES / "corpus" / "generated" / "symbols",
        )
        for path in directory.glob("*.png")
    }
    if manifested_paths != corpus_paths:
        for path in sorted(corpus_paths - manifested_paths):
            failures.append(f"unmanifested corpus input: {path}")
        for path in sorted(manifested_paths - corpus_paths):
            failures.append(f"manifested corpus input is absent: {path}")

    for item in entries:
        path = FIXTURES / item["path"]
        if not path.is_file():
            failures.append(f"{item['id']}: missing {item['path']}")
            continue
        try:
            dimensions = png_dimensions(path)
        except ValueError as error:
            failures.append(f"{item['id']}: {error}")
            continue
        if dimensions != (1024, 1024):
            failures.append(f"{item['id']}: expected 1024x1024, got {dimensions}")
        actual = sha256(path)
        expected = item.get("sha256")
        if expected in (None, "pending"):
            if not args.allow_pending:
                failures.append(f"{item['id']}: hash is pending ({actual})")
        elif actual != expected:
            failures.append(f"{item['id']}: SHA-256 mismatch ({actual})")
        if item.get("reviewStatus") != "reviewed" and not args.allow_pending:
            failures.append(f"{item['id']}: fixture has not been reviewed")
        if item.get("sourceKind") == "generated" and not item.get("prompt"):
            failures.append(f"{item['id']}: generated fixture lacks prompt provenance")
        for field in ("expectedTopology", "structuralFeatures", "license", "attribution"):
            if not item.get(field):
                failures.append(f"{item['id']}: missing {field}")

    sources = json.loads((FIXTURES / "sources" / "sources.json").read_text(encoding="utf-8"))
    for source in sources.get("sources", []):
        source_path = FIXTURES / "sources" / source["licensePath"]
        binary_name = Path(source["path"]).name
        binary_path = source_path.parent / binary_name
        if not binary_path.is_file():
            failures.append(f"{source['id']}: missing pinned source binary")
        elif sha256(binary_path) != source["sha256"]:
            failures.append(f"{source['id']}: pinned source SHA-256 mismatch")
        if not source_path.is_file():
            failures.append(f"{source['id']}: missing license file")

    if failures:
        print("fixture verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"verified {len(entries)} fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
