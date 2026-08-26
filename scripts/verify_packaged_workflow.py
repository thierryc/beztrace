#!/usr/bin/env python3
"""Exercise a release ZIP using only its packaged standalone CLI."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RELEASE = Path("/Volumes/T9/beztrace/milestone-5/release")
DEFAULT_OUTPUT = Path("/Volumes/T9/beztrace/milestone-6/reports/packaged-workflow.json")
FIXTURE = ROOT / "Tests" / "Fixtures" / "corpus" / "deterministic" / "glyphs" / "glyph-upper-o.png"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_outputs(result: dict, svg: str, source_hash: str) -> list[str]:
    failures: list[str] = []
    if result.get("schemaVersion") != 1 or result.get("pathDataVersion") != 2:
        failures.append("JSON contract version differs")
    if result.get("source", {}).get("sha256") != source_hash:
        failures.append("JSON source hash differs")
    paths = result.get("paths", [])
    if not paths:
        failures.append("JSON contains no paths")
    if any(contour.get("closed") is not True for contour in paths):
        failures.append("JSON paths are not all closed")
    if any(not contour.get("nodes") for contour in paths):
        failures.append("JSON contains an empty contour")
    if "<path " not in svg:
        failures.append("SVG contains no path")
    if "transform=" in svg or "<g" in svg:
        failures.append("default SVG unexpectedly contains a transform group")
    return failures


def run(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--archive",
        type=Path,
        default=DEFAULT_RELEASE / "beztrace-0.1.0-rc.1-macos-universal.zip",
    )
    parser.add_argument("--fixture", type=Path, default=FIXTURE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    archive, fixture = args.archive.resolve(), args.fixture.resolve()
    failures: list[str] = []
    record: dict = {
        "schemaVersion": 1,
        "status": "fail",
        "usedPackagedBinary": True,
        "archive": str(archive),
        "fixture": str(fixture),
    }
    if not archive.is_file():
        failures.append(f"release archive is missing: {archive}")
    if not fixture.is_file():
        failures.append(f"fixture is missing: {fixture}")
    if not failures:
        record["archiveSHA256"] = sha256(archive)
        record["sourceSHA256"] = sha256(fixture)
        with tempfile.TemporaryDirectory(prefix="beztrace-packaged-workflow-") as temporary:
            root = Path(temporary)
            extract = subprocess.run(
                ["ditto", "-x", "-k", str(archive), str(root)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if extract.returncode:
                failures.append(f"archive extraction failed: {extract.stderr.decode('utf-8', 'replace').strip()}")
            binary = root / "beztrace" / "bin" / "beztrace"
            if not binary.is_file():
                failures.append("packaged executable is missing")
            else:
                record["binarySHA256"] = sha256(binary)
                version = run([str(binary), "--version"])
                if version.returncode:
                    failures.append("packaged --version failed")
                else:
                    record["version"] = version.stdout.decode("utf-8", "replace").strip()
                json_path, svg_path = root / "trace.json", root / "trace.svg"
                json_run = run([
                    str(binary), "trace", str(fixture), "--format", "json", "--output", str(json_path),
                ])
                svg_run = run([
                    str(binary), "trace", str(fixture), "--format", "svg", "--output", str(svg_path),
                ])
                if json_run.returncode:
                    failures.append(f"packaged JSON trace failed: {json_run.stderr.decode('utf-8', 'replace').strip()}")
                if svg_run.returncode:
                    failures.append(f"packaged SVG trace failed: {svg_run.stderr.decode('utf-8', 'replace').strip()}")
                if not json_run.returncode and not svg_run.returncode:
                    result = json.loads(json_path.read_text(encoding="utf-8"))
                    svg = svg_path.read_text(encoding="utf-8")
                    failures.extend(validate_outputs(result, svg, record["sourceSHA256"]))
                    record["result"] = {
                        "contourCount": len(result.get("paths", [])),
                        "nodeCount": sum(len(item.get("nodes", [])) for item in result.get("paths", [])),
                        "jsonSHA256": sha256(json_path),
                        "svgSHA256": sha256(svg_path),
                        "defaultSVGTransformFree": "transform=" not in svg and "<g" not in svg,
                    }
    record["failures"] = failures
    record["status"] = "pass" if not failures else "fail"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("packaged standalone workflow passed" if not failures else "packaged standalone workflow failed")
    for failure in failures:
        print(f"- {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
