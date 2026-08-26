#!/usr/bin/env python3
"""Validate Milestone 5 corpus, evidence, and release-plan invariants."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
PLAN = FIXTURES / "corpus" / "milestone-5-plan.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="also require the frozen 100-image manifest and all human reviews",
    )
    args = parser.parse_args()
    failures: list[str] = []
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    target = plan.get("target", {})
    expected_target = {
        "total": 100,
        "deterministic": 50,
        "generated": 50,
        "glyphs": 64,
        "symbols": 36,
        "minimumHumanAccepted": 95,
    }
    if target != expected_target:
        failures.append(f"unexpected target composition: {target}")
    if plan.get("reviewer") != "project-owner":
        failures.append("human review identifier must be project-owner")
    if plan.get("candidateCountPerGeneratedConcept") != 2:
        failures.append("each generated concept must have exactly two initial candidates")
    glyphs = plan.get("addedGlyphs", [])
    symbols = plan.get("addedSymbols", [])
    if len(glyphs) != 24 or len(symbols) != 14:
        failures.append(f"expected 24 added glyphs and 14 added symbols, found {len(glyphs)} and {len(symbols)}")
    identifiers = [item.get("id") for item in glyphs + symbols]
    if len(set(identifiers)) != 38 or identifiers != sorted(identifiers, key=identifiers.index):
        if len(set(identifiers)) != 38:
            failures.append("added concept identifiers must be unique")
    if any(not str(item.get("content", "")).strip() for item in glyphs + symbols):
        failures.append("every added concept needs content")
    if any(not str(item.get("materialName", "")).strip() for item in symbols):
        failures.append("every deterministic symbol needs a Material Symbols name")
    external = plan.get("externalWorkRoot", "")
    if external != "/Volumes/T9/beztrace/milestone-5":
        failures.append("bulk external work must be rooted at /Volumes/T9/beztrace/milestone-5")

    manifest = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
    entries = manifest.get("fixtures", [])
    counts = {
        "total": len(entries),
        "deterministic": sum(item.get("sourceKind") == "deterministic" for item in entries),
        "generated": sum(item.get("sourceKind") == "generated" for item in entries),
        "glyphs": sum(item.get("category") == "glyph" for item in entries),
        "symbols": sum(item.get("category") == "symbol" for item in entries),
    }
    expected_counts = target
    for key in ("total", "deterministic", "generated", "glyphs", "symbols"):
        if counts[key] != expected_counts[key]:
            state = "complete corpus"
            failures.append(
                f"{state} {key}: expected {expected_counts[key]}, found {counts[key]}"
            )

    by_identifier = {item.get("id"): item for item in entries}
    for identifier in identifiers:
        item = by_identifier.get(identifier)
        if not item:
            failures.append(f"missing deterministic fixture record: {identifier}")
        elif item.get("sourceKind") != "deterministic":
            failures.append(f"{identifier}: planned deterministic record has wrong source kind")
        elif not isinstance(item.get("expectedContours"), int) or item["expectedContours"] < 1:
            failures.append(f"{identifier}: deterministic record lacks expected contour count")

    selections_path = FIXTURES / "corpus" / "milestone-5-selections.json"
    selected_sources_path = FIXTURES / "corpus" / "milestone-5-selected-sources.json"
    if not selections_path.is_file() or not selected_sources_path.is_file():
        failures.append("generated source selection evidence is missing")
    else:
        selection_document = json.loads(selections_path.read_text(encoding="utf-8"))
        source_document = json.loads(selected_sources_path.read_text(encoding="utf-8"))
        if selection_document.get("schemaVersion") != 1:
            failures.append("generated selection schemaVersion must be 1")
        if selection_document.get("reviewer") != "project-owner":
            failures.append("generated selection reviewer must be project-owner")
        if selection_document.get("reviewStatus") != "source-selected":
            failures.append("generated selection status must be source-selected")
        selections = selection_document.get("selections", [])
        selected_by_id = {item.get("id"): item for item in selections}
        pinned_sources = source_document.get("sources", [])
        pinned_by_id = {item.get("id"): item for item in pinned_sources}
        if len(selections) != 38 or set(selected_by_id) != set(identifiers):
            failures.append("generated selections must cover exactly the 38 planned concepts")
        if len(pinned_sources) != 38 or set(pinned_by_id) != set(identifiers):
            failures.append("selected-source hashes must cover exactly the 38 planned concepts")
        for identifier in identifiers:
            selection = selected_by_id.get(identifier, {})
            pin = pinned_by_id.get(identifier, {})
            item = by_identifier.get(f"{identifier}-generated")
            if not item:
                failures.append(f"missing generated fixture record: {identifier}-generated")
                continue
            if item.get("sourceKind") != "generated":
                failures.append(f"{identifier}-generated: wrong source kind")
            if item.get("selectedCandidate") != selection.get("candidate"):
                failures.append(f"{identifier}-generated: selected candidate mismatch")
            if item.get("sourceImageSHA256") != pin.get("sourceSHA256"):
                failures.append(f"{identifier}-generated: source candidate hash mismatch")
            if item.get("sha256") != pin.get("normalizedSHA256"):
                failures.append(f"{identifier}-generated: normalized hash mismatch")
            if item.get("reviewedBy") != "project-owner":
                failures.append(f"{identifier}-generated: source lacks project-owner review")
            if item.get("sourceReviewStatus") != "source-selected":
                failures.append(f"{identifier}-generated: source selection status is invalid")
            if not isinstance(item.get("expectedContours"), int) or item["expectedContours"] < 1:
                failures.append(f"{identifier}-generated: expected contour count is missing")

    if args.require_complete:
        accepted = sum(item.get("acceptanceStatus") == "accepted" for item in entries)
        if accepted < target["minimumHumanAccepted"]:
            failures.append(f"expected at least {target['minimumHumanAccepted']} human-accepted traces, found {accepted}")
        for item in entries:
            if item.get("sourceKind") == "generated" and item.get("reviewedBy") != "project-owner":
                failures.append(f"{item.get('id')}: generated source lacks project-owner review")

    if failures:
        print("Milestone 5 verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    state = "complete" if args.require_complete else "plan"
    print(f"verified Milestone 5 {state} invariants")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
