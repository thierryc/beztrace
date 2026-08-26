#!/usr/bin/env python3
"""Evaluate the Milestone 6 viability gates without weakening missing evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
MILESTONE5 = Path("/Volumes/T9/beztrace/milestone-5")
MILESTONE6 = Path("/Volumes/T9/beztrace/milestone-6")
MIB = 1024 * 1024


def gate(identifier: str, title: str, status: str, details: dict, *, required: bool = True) -> dict:
    return {
        "id": identifier,
        "title": title,
        "required": required,
        "status": status,
        "details": details,
    }


def benchmark_gates(swift: dict, rust: dict) -> list[dict]:
    swift_by_id = {item.get("id"): item for item in swift.get("fixtures", [])}
    rust_by_id = {item.get("id"): item for item in rust.get("fixtures", [])}
    identifiers = sorted(set(swift_by_id) | set(rust_by_id))
    relative_records: list[dict] = []
    absolute_records: list[dict] = []
    memory_records: list[dict] = []
    for identifier in identifiers:
        swift_item, rust_item = swift_by_id.get(identifier), rust_by_id.get(identifier)
        if not swift_item or not rust_item:
            relative_records.append({"id": identifier, "pass": False, "reason": "missing engine result"})
            continue
        median_ratio = swift_item["medianMs"] / rust_item["medianMs"] if rust_item["medianMs"] else float("inf")
        p95_ratio = swift_item["p95Ms"] / rust_item["p95Ms"] if rust_item["p95Ms"] else float("inf")
        relative_records.append(
            {
                "id": identifier,
                "medianRatio": round(median_ratio, 6),
                "p95Ratio": round(p95_ratio, 6),
                "pass": median_ratio <= 1.5 and p95_ratio <= 1.5,
            }
        )
        process_p95 = swift_item.get("processP95Ms")
        absolute_records.append(
            {
                "id": identifier,
                "processP95Ms": process_p95,
                "pass": isinstance(process_p95, (int, float)) and process_p95 < 1_000,
            }
        )
        peak = swift_item.get("peakRSSBytes")
        memory_records.append(
            {
                "id": identifier,
                "peakRSSBytes": peak,
                "pass": isinstance(peak, int) and peak < 256 * MIB,
            }
        )
    relative_passes = sum(item["pass"] for item in relative_records)
    absolute_passes = sum(item["pass"] for item in absolute_records)
    memory_passes = sum(item["pass"] for item in memory_records)
    return [
        gate(
            "performance-relative",
            "Swift median and p95 are within 1.5× Rust",
            "pass" if identifiers and relative_passes == len(identifiers) else "fail",
            {"passingFixtures": relative_passes, "fixtureCount": len(identifiers), "fixtures": relative_records},
        ),
        gate(
            "performance-absolute",
            "Single-shot 1024×1024 CLI p95 is below one second",
            "pass" if identifiers and absolute_passes == len(identifiers) else "fail",
            {"passingFixtures": absolute_passes, "fixtureCount": len(identifiers), "fixtures": absolute_records},
        ),
        gate(
            "memory",
            "Peak RSS is below 256 MiB",
            "pass" if identifiers and memory_passes == len(identifiers) else "fail",
            {"passingFixtures": memory_passes, "fixtureCount": len(identifiers), "fixtures": memory_records},
        ),
    ]


def acceptance_gate(manifest: dict, review: dict | None) -> dict:
    expected_ids = [item.get("id") for item in manifest.get("fixtures", [])]
    decisions = [] if review is None else review.get("decisions", [])
    decision_ids = [item.get("id") for item in decisions]
    accepted_statuses = {"accepted", "accepted-with-optical-notes"}
    accepted = sum(item.get("status") in accepted_statuses for item in decisions)
    notes_valid = all(
        item.get("status") != "accepted-with-optical-notes"
        or bool(str(item.get("notes", "")).strip())
        for item in decisions
    )
    manifest_hash_matches = (
        "_sha256" not in manifest
        or (review is not None and review.get("corpusManifestSHA256") == manifest["_sha256"])
    )
    valid = (
        len(expected_ids) == 100
        and len(decisions) == 100
        and len(set(decision_ids)) == 100
        and set(decision_ids) == set(expected_ids)
        and review is not None
        and review.get("reviewer") == "project-owner"
        and review.get("reviewStatus") == "complete"
        and accepted >= 95
        and notes_valid
        and manifest_hash_matches
    )
    return gate(
        "human-trace-acceptance",
        "Project owner accepts at least 95 of 100 reviewed traces",
        "pass" if valid else ("pending" if review is None or accepted == 0 else "fail"),
        {
            "decisionCount": len(decisions),
            "acceptedCount": accepted,
            "minimumAccepted": 95,
            "reviewStatus": None if review is None else review.get("reviewStatus"),
            "reviewer": None if review is None else review.get("reviewer"),
            "manifestHashMatches": manifest_hash_matches,
            "notesValid": notes_valid,
        },
    )


def release_gate(manifest: dict | None) -> dict:
    architectures = [] if manifest is None else manifest.get("architectures", [])
    artifacts = [] if manifest is None else manifest.get("artifacts", [])
    universal = set(architectures) == {"arm64", "x86_64"} and len(architectures) == 2
    secure = len(artifacts) >= 2 and all(
        item.get("signed") is True and item.get("notarized") is True for item in artifacts
    )
    return gate(
        "release-artifacts",
        "Universal release artifacts are signed and notarized",
        "pass" if universal and secure else "fail",
        {
            "architectures": architectures,
            "artifactCount": len(artifacts),
            "universal": universal,
            "allSigned": bool(artifacts) and all(item.get("signed") is True for item in artifacts),
            "allNotarized": bool(artifacts) and all(item.get("notarized") is True for item in artifacts),
        },
    )


def viability_decision(gates: list[dict]) -> str:
    return "approve" if all(item.get("status") == "pass" for item in gates if item.get("required")) else "reject"


def load(path: Path | None) -> dict | None:
    if path is None or not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def production_source_sha256() -> str:
    digest = hashlib.sha256()
    paths = [ROOT / "Package.swift", *sorted((ROOT / "Sources").rglob("*.swift"))]
    for path in paths:
        digest.update(path.relative_to(ROOT).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def evidence_gate(identifier: str, title: str, document: dict | None, predicate) -> dict:
    valid = document is not None and predicate(document)
    return gate(identifier, title, "pass" if valid else ("missing" if document is None else "fail"), document or {})


def command_evidence_gate(identifier: str, title: str, document: dict | None, script_name: str) -> dict:
    matches = [] if document is None else [
        item for item in document.get("commands", [])
        if any(script_name in part for part in item.get("command", []))
    ]
    valid = len(matches) == 1 and matches[0].get("status") == "pass"
    return gate(
        identifier,
        title,
        "pass" if valid else ("missing" if not matches else "fail"),
        {"script": script_name, "matches": matches},
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--swift-benchmark", type=Path, default=MILESTONE6 / "benchmarks" / "swift.json")
    parser.add_argument("--rust-benchmark", type=Path, default=MILESTONE5 / "benchmarks" / "rust.json")
    parser.add_argument("--acceptance", type=Path, default=MILESTONE6 / "reports" / "corpus-trace-review" / "trace-acceptance.json")
    parser.add_argument("--corpus-report", type=Path, default=MILESTONE6 / "reports" / "corpus-trace-review" / "report.json")
    parser.add_argument("--test-evidence", type=Path, default=MILESTONE6 / "reports" / "test-evidence.json")
    parser.add_argument("--cross-architecture", type=Path, default=MILESTONE5 / "reports" / "cross-architecture-corpus.json")
    parser.add_argument("--fuzz-evidence", type=Path, default=MILESTONE5 / "fuzz" / "decoder-campaign-50000.json")
    parser.add_argument("--release-manifest", type=Path, default=MILESTONE5 / "release" / "release-manifest.json")
    parser.add_argument("--packaged-workflow", type=Path, default=MILESTONE6 / "reports" / "packaged-workflow.json")
    parser.add_argument("--output", type=Path, default=MILESTONE6 / "reports" / "viability-report.json")
    parser.add_argument("--signing-authorized", action="store_true")
    parser.add_argument("--merge-approved", action="store_true")
    parser.add_argument("--publication-authorized", action="store_true")
    parser.add_argument("--require-approve", action="store_true")
    args = parser.parse_args()

    manifest_path = FIXTURES / "manifest.json"
    corpus_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    corpus_manifest["_sha256"] = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    swift, rust = load(args.swift_benchmark), load(args.rust_benchmark)
    gates: list[dict] = []
    test_evidence = load(args.test_evidence)
    gates.append(evidence_gate(
        "automated-tests", "Complete optimized and clean-worktree test matrix passes", test_evidence,
        lambda value: value.get("allPassed") is True and value.get("cleanWorktree") is True,
    ))
    gates.append(command_evidence_gate(
        "reference-checkpoint", "Immutable oracle and 62-glyph reference verify", test_evidence,
        "verify_oracle.py",
    ))
    gates.append(command_evidence_gate(
        "product-boundaries", "Standalone dependency, source-license, and notice boundaries verify", test_evidence,
        "verify_product_boundaries.py",
    ))
    gates.append(command_evidence_gate(
        "release-metadata", "Unsigned staging, checksums, licenses, schemas, and SPDX SBOM verify", test_evidence,
        "verify_release_candidate.py",
    ))
    corpus = load(args.corpus_report)
    gates.append(evidence_gate(
        "automatic-corpus", "All 100 corpus traces pass automatic deterministic checks", corpus,
        lambda value: value.get("fixtureCount") == 100 and value.get("automaticChecks") == "passed"
            and value.get("deterministicRuns", 0) >= 2,
    ))
    gates.append(acceptance_gate(corpus_manifest, load(args.acceptance)))
    if swift is None or rust is None:
        gates.extend([
            gate("performance-relative", "Swift median and p95 are within 1.5× Rust", "missing", {}),
            gate("performance-absolute", "Single-shot 1024×1024 CLI p95 is below one second", "missing", {}),
            gate("memory", "Peak RSS is below 256 MiB", "missing", {}),
        ])
    else:
        source_hash = production_source_sha256()
        gates.append(gate(
            "performance-evidence-binding",
            "Swift benchmark is bound to the current production source tree",
            "pass" if swift.get("productionSourceSHA256") == source_hash else "fail",
            {
                "expectedProductionSourceSHA256": source_hash,
                "recordedProductionSourceSHA256": swift.get("productionSourceSHA256"),
                "revision": swift.get("revision"),
            },
        ))
        gates.extend(benchmark_gates(swift, rust))
    gates.append(evidence_gate(
        "cross-architecture", "All 100 outputs are byte-identical on arm64 and x86_64", load(args.cross_architecture),
        lambda value: value.get("corpusCount") == 100 and value.get("allByteIdentical") is True,
    ))
    gates.append(evidence_gate(
        "fuzz", "The 50,000-case malformed-input campaign completes without acceptance or crashes", load(args.fuzz_evidence),
        lambda value: value.get("cases", 0) >= 50_000 and value.get("rejected") == value.get("cases")
            and value.get("accepted") == 0,
    ))
    release = release_gate(load(args.release_manifest))
    if release["status"] != "pass" and not args.signing_authorized:
        release["status"] = "not-authorized"
        release["details"]["reason"] = "Developer ID signing and notarization were not authorized"
    gates.append(release)
    gates.append(evidence_gate(
        "packaged-workflow", "Packaged CLI completes a non-Glyphs JSON and SVG workflow", load(args.packaged_workflow),
        lambda value: value.get("status") == "pass" and value.get("usedPackagedBinary") is True,
    ))
    gates.append(gate(
        "merge-approval", "Project owner explicitly approves merge to main", "pass" if args.merge_approved else "pending",
        {"approved": args.merge_approved},
    ))
    gates.append(gate(
        "publication-authorization", "Project owner explicitly authorizes publication", "pass" if args.publication_authorized else "not-authorized",
        {"authorized": args.publication_authorized}, required=False,
    ))
    decision = viability_decision(gates)
    report = {
        "schemaVersion": 1,
        "milestone": 6,
        "decision": decision,
        "mergeEligible": decision == "approve",
        "publicationAuthorized": args.publication_authorized,
        "gates": gates,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Milestone 6 decision: {decision}")
    for item in gates:
        print(f"- {item['status']}: {item['title']}")
    return 1 if args.require_approve and decision != "approve" else 0


if __name__ == "__main__":
    raise SystemExit(main())
