#!/usr/bin/env python3
"""Audit standalone/runtime-dependency and source-license boundaries."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"


def main() -> int:
    failures: list[str] = []
    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    if ".package(" in package:
        failures.append("Package.swift declares an external package dependency")
    core_forbidden = (
        "FileManager.", "CommandLine.", "Process(", "URLSession", "NSWorkspace",
        "import Network", "import WebKit", "import GlyphsApp",
    )
    swift_files = sorted(SOURCES.rglob("*.swift"))
    for path in swift_files:
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)
        if "SPDX-License-Identifier:" not in "\n".join(text.splitlines()[:8]):
            failures.append(f"{relative}: SPDX header is missing from the first eight lines")
        if "BezierTraceCore" in path.parts:
            for marker in core_forbidden:
                if marker in text:
                    failures.append(f"{relative}: core contains forbidden adapter/runtime marker {marker!r}")
    command_files = sorted((SOURCES / "BezierTraceCommand").glob("*.swift"))
    if not command_files:
        failures.append("standalone command adapter is missing")
    if "--product beztrace" not in (ROOT / "scripts" / "build_release_candidate.sh").read_text(encoding="utf-8"):
        failures.append("release script does not explicitly stage only the beztrace product")
    notices = (ROOT / "THIRD_PARTY_NOTICES").read_text(encoding="utf-8")
    for required in ("img2bez", "Virtua Grotesk", "Noto Sans", "Material Symbols"):
        if required not in notices:
            failures.append(f"THIRD_PARTY_NOTICES lacks {required}")
    if failures:
        print("product-boundary verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(
        f"verified standalone dependency boundary, core/adaptor separation, "
        f"SPDX headers for {len(swift_files)} Swift files, and notices"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
