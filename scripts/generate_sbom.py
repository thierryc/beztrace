#!/usr/bin/env python3
"""Generate minimal reproducible SPDX 2.3 source and binary SBOMs."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def document(
    name: str,
    release_label: str,
    namespace_suffix: str,
    packages: list[dict],
    files: list[dict],
) -> dict:
    relationships = [
        {"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": packages[0]["SPDXID"]}
    ]
    relationships.extend(
        {"spdxElementId": packages[0]["SPDXID"], "relationshipType": "CONTAINS", "relatedSpdxElement": item["SPDXID"]}
        for item in files
    )
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": name,
        "documentNamespace": f"https://beztrace.dev/spdx/{release_label}/{namespace_suffix}",
        "creationInfo": {"created": "2026-08-26T00:00:00Z", "creators": ["Tool: beztrace-generate-sbom-v1"]},
        "packages": packages,
        "files": files,
        "relationships": relationships,
    }


def package(spdx_id: str, name: str, version: str, license_id: str, supplier: str) -> dict:
    return {
        "name": name,
        "SPDXID": spdx_id,
        "versionInfo": version,
        "downloadLocation": "NOASSERTION",
        "filesAnalyzed": False,
        "licenseConcluded": license_id,
        "licenseDeclared": license_id,
        "copyrightText": "NOASSERTION",
        "supplier": supplier,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--release-kind",
        choices=("candidate", "final"),
        default="candidate",
    )
    args = parser.parse_args()
    binary = args.binary.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    revision = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout.strip()
    label = "0.1.0-rc.1" if args.release_kind == "candidate" else "0.1.0"
    source_version = f"{label}+{revision[:12]}" if args.release_kind == "candidate" else label

    source_package = package(
        "SPDXRef-Package-beztrace-source", "beztrace", source_version,
        "Apache-2.0 OR MIT", "Organization: beztrace contributors"
    )
    source_files = []
    for index, path in enumerate(sorted(
        [ROOT / "Package.swift", *ROOT.glob("Sources/**/*.swift"), *ROOT.glob("Schemas/*.json")],
        key=lambda item: item.relative_to(ROOT).as_posix(),
    )):
        source_files.append({
            "fileName": path.relative_to(ROOT).as_posix(),
            "SPDXID": f"SPDXRef-SourceFile-{index:04d}",
            "checksums": [{"algorithm": "SHA256", "checksumValue": sha256(path)}],
            "licenseConcluded": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        })
    source = document(
        "beztrace source SBOM", label, f"source-{revision}", [source_package], source_files
    )

    binary_package = package(
        "SPDXRef-Package-beztrace-binary", "beztrace", label,
        "Apache-2.0 OR MIT", "Organization: beztrace contributors"
    )
    binary_file = {
        "fileName": "bin/beztrace",
        "SPDXID": "SPDXRef-Binary-beztrace",
        "checksums": [{"algorithm": "SHA256", "checksumValue": sha256(binary)}],
        "licenseConcluded": "Apache-2.0 OR MIT",
        "copyrightText": "Copyright 2026 beztrace contributors and the img2bez Authors",
    }
    binary_document = document(
        "beztrace binary SBOM", label, f"binary-{sha256(binary)}", [binary_package], [binary_file]
    )
    binary_document["annotations"] = [{
        "annotationType": "OTHER",
        "annotator": "Tool: beztrace-generate-sbom-v1",
        "annotationDate": "2026-08-26T00:00:00Z",
        "comment": "No third-party runtime dependencies. Linked Apple system frameworks are platform prerequisites and are not distributed in the artifact.",
    }]

    (output / "sbom-source.spdx.json").write_text(
        json.dumps(source, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output / "sbom-binary.spdx.json").write_text(
        json.dumps(binary_document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"wrote SPDX 2.3 SBOMs to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
