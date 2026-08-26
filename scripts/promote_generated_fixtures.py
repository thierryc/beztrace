#!/usr/bin/env python3
"""Promote owner-selected generated candidates into the immutable test corpus."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
PLAN = FIXTURES / "corpus" / "milestone-5-plan.json"
SELECTIONS = FIXTURES / "corpus" / "milestone-5-selections.json"
SELECTED_SOURCES = FIXTURES / "corpus" / "milestone-5-selected-sources.json"
DEFAULT_CANDIDATES = Path("/Volumes/T9/beztrace/milestone-5/generated-candidates")
DEFAULT_TRACE_REPORT = Path(
    "/Volumes/T9/beztrace/milestone-5/reports/selected-generated-traces/report.json"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def concepts(plan: dict) -> list[dict]:
    result: list[dict] = []
    for category, key in (("glyph", "addedGlyphs"), ("symbol", "addedSymbols")):
        result.extend({**item, "category": category} for item in plan[key])
    return result


def normalized_png(source: Path) -> tuple[bytes, dict]:
    with Image.open(source) as opened:
        opened.load()
        source_mode = opened.mode
        source_size = [opened.width, opened.height]
        rgba = opened.convert("RGBA")
        white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        opaque = Image.alpha_composite(white, rgba).convert("L")
        normalized = opaque.resize((1024, 1024), Image.Resampling.LANCZOS)
        stream = io.BytesIO()
        normalized.save(stream, format="PNG", optimize=False, compress_level=9)
    return stream.getvalue(), {"sourceMode": source_mode, "sourceSize": source_size}


def load_and_validate() -> tuple[list[dict], dict[str, dict]]:
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    selection_document = json.loads(SELECTIONS.read_text(encoding="utf-8"))
    if selection_document.get("schemaVersion") != 1:
        raise ValueError("selection schemaVersion must be 1")
    if selection_document.get("reviewer") != "project-owner":
        raise ValueError("selection reviewer must be project-owner")
    if selection_document.get("reviewStatus") != "source-selected":
        raise ValueError("selection reviewStatus must be source-selected")

    planned = concepts(plan)
    expected_ids = [item["id"] for item in planned]
    selected = selection_document.get("selections", [])
    selected_ids = [item.get("id") for item in selected]
    if len(selected_ids) != len(set(selected_ids)):
        raise ValueError("selection identifiers must be unique")
    if set(selected_ids) != set(expected_ids) or len(selected_ids) != 38:
        raise ValueError("selections must cover exactly the 38 planned generated concepts")
    by_identifier = {item["id"]: item for item in selected}
    for identifier, item in by_identifier.items():
        if item.get("candidate") not in (1, 2):
            raise ValueError(f"{identifier}: candidate must be 1 or 2")
    return planned, by_identifier


def inventory(candidates: Path) -> dict:
    planned, selected = load_and_validate()
    records: list[dict] = []
    for concept in planned:
        choice = selected[concept["id"]]["candidate"]
        source = candidates / concept["id"] / f"candidate-{choice:02d}.png"
        if not source.is_file():
            raise FileNotFoundError(source)
        normalized, profile = normalized_png(source)
        records.append(
            {
                "id": concept["id"],
                "candidate": choice,
                "sourceSHA256": sha256(source),
                "normalizedSHA256": sha256_bytes(normalized),
                **profile,
            }
        )
    return {
        "schemaVersion": 1,
        "generator": "OpenAI built-in image generation; exact model version not exposed",
        "generationDate": "2026-08-26",
        "reviewer": "project-owner",
        "reviewStatus": "source-selected",
        "normalization": "Composite RGBA over white, convert to grayscale, resize complete canvas to 1024x1024 with Pillow 12.0.0 Lanczos, save PNG compression level 9 without metadata",
        "sources": records,
    }


def promote(candidates: Path, check: bool) -> int:
    planned, selected = load_and_validate()
    pinned = json.loads(SELECTED_SOURCES.read_text(encoding="utf-8"))
    pinned_by_id = {item["id"]: item for item in pinned.get("sources", [])}
    if set(pinned_by_id) != {item["id"] for item in planned}:
        raise ValueError("selected-source manifest must pin exactly the 38 planned concepts")

    failures: list[str] = []
    for concept in planned:
        identifier = concept["id"]
        choice = selected[identifier]["candidate"]
        source = candidates / identifier / f"candidate-{choice:02d}.png"
        expected = pinned_by_id[identifier]
        if choice != expected.get("candidate"):
            failures.append(f"{identifier}: selected candidate does not match its pinned record")
            continue
        output = (
            FIXTURES
            / "corpus"
            / "generated"
            / ("glyphs" if concept["category"] == "glyph" else "symbols")
            / f"{identifier}.png"
        )
        if not source.is_file():
            if not check:
                failures.append(f"{identifier}: selected source is missing")
            elif not output.is_file() or sha256(output) != expected.get("normalizedSHA256"):
                failures.append(f"{identifier}: frozen fixture does not match its pinned normalized hash")
            continue
        source_hash = sha256(source)
        if source_hash != expected.get("sourceSHA256"):
            failures.append(f"{identifier}: selected source does not match its pinned candidate/hash")
            continue
        data, _ = normalized_png(source)
        if sha256_bytes(data) != expected.get("normalizedSHA256"):
            failures.append(f"{identifier}: normalized bytes do not match their pinned hash")
            continue
        if check:
            if not output.is_file() or output.read_bytes() != data:
                failures.append(f"{identifier}: promoted fixture differs from reproducible output")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(data)

    if failures:
        print("generated-fixture promotion failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    verb = "verified" if check else "promoted"
    print(f"{verb} {len(planned)} owner-selected generated fixtures")
    return 0


def manifest_fragment(trace_report: Path) -> list[dict]:
    planned, selected = load_and_validate()
    pinned = json.loads(SELECTED_SOURCES.read_text(encoding="utf-8"))
    pinned_by_id = {item["id"]: item for item in pinned["sources"]}
    traced = json.loads(trace_report.read_text(encoding="utf-8"))
    traced_by_id = {item["id"]: item for item in traced["fixtures"]}
    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    deterministic = {item["id"]: item for item in manifest["fixtures"]}
    result: list[dict] = []
    for concept in planned:
        identifier = concept["id"]
        reference = deterministic[identifier]
        pin = pinned_by_id[identifier]
        trace = traced_by_id[identifier]
        topology = reference["expectedTopology"]
        if identifier == "symbol-bell" and trace["contourCount"] == 3:
            topology = "one outer bell contour, one internal counter, and one clapper contour"
        result.append(
            {
                "id": f"{identifier}-generated",
                "category": concept["category"],
                "sourceKind": "generated",
                "path": f"corpus/generated/{'glyphs' if concept['category'] == 'glyph' else 'symbols'}/{identifier}.png",
                "content": concept["content"],
                "source": "OpenAI built-in image generation",
                "generator": "OpenAI built-in image generation; exact model version not exposed; 2026-08-26",
                "prompt": (
                    "Prompt summary (exact wording not retained): single isolated bold black "
                    f"{concept['content']} silhouette centered on a white or transparent square canvas, "
                    "without decoration, suitable for path tracing"
                ),
                "promptRecordKind": "summary-not-verbatim",
                "license": "Project test fixture under repository dual license",
                "attribution": "Generated for beztrace with OpenAI image generation",
                "modifications": (
                    f"Selected candidate {selected[identifier]['candidate']} by project owner; composited over white, "
                    "converted to grayscale, and resampled from 1254x1254 to 1024x1024 with Pillow 12.0.0 Lanczos"
                ),
                "selectedCandidate": selected[identifier]["candidate"],
                "sourceImageSHA256": pin["sourceSHA256"],
                "sha256": pin["normalizedSHA256"],
                "reviewStatus": "reviewed",
                "reviewedBy": "project-owner",
                "sourceReviewStatus": "source-selected",
                "acceptanceStatus": "pending-human-trace-review",
                "expectedContours": trace["contourCount"],
                "expectedTopology": topology,
                "structuralFeatures": reference["structuralFeatures"],
                "opticalAllowances": sorted(
                    set(reference.get("opticalAllowances", [])) | {"subtle generated edge softness"}
                ),
            }
        )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidates", type=Path, default=DEFAULT_CANDIDATES)
    parser.add_argument("--inventory", action="store_true")
    parser.add_argument("--manifest-fragment", action="store_true")
    parser.add_argument("--trace-report", type=Path, default=DEFAULT_TRACE_REPORT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.inventory:
        print(json.dumps(inventory(args.candidates), indent=2) + "\n", end="")
        return 0
    if args.manifest_fragment:
        print(json.dumps(manifest_fragment(args.trace_report), indent=2) + "\n", end="")
        return 0
    return promote(args.candidates, args.check)


if __name__ == "__main__":
    raise SystemExit(main())
