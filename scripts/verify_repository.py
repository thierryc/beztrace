#!/usr/bin/env python3
"""Validate publication safety and local documentation links."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
MAX_GIT_FILE_BYTES = 100_000_000
FORBIDDEN = (b"/Users/", b"/home/", b"/private/var/folders/", b"test-work/", b"thierryc")
LINK = re.compile(r"\[[^]]+\]\(([^)]+)\)")


def main() -> int:
    failures: list[str] = []
    markdown = [ROOT / "README.md", ROOT / "AGENTS.md", *sorted((ROOT / "docs").glob("*.md"))]
    for document in markdown:
        text = document.read_text(encoding="utf-8")
        for target in LINK.findall(text):
            if "://" in target or target.startswith("#"):
                continue
            path_text = target.split("#", 1)[0]
            if path_text and not (document.parent / path_text).resolve().exists():
                failures.append(f"broken link in {document.relative_to(ROOT)}: {target}")

    for path in sorted(item for item in FIXTURES.rglob("*") if item.is_file()):
        relative = path.relative_to(ROOT).as_posix()
        size = path.stat().st_size
        if size >= MAX_GIT_FILE_BYTES:
            failures.append(f"file is too large for ordinary Git: {relative} ({size} bytes)")
        data = path.read_bytes()
        if b"\0" in data:
            continue
        for marker in FORBIDDEN:
            if marker in data:
                failures.append(f"machine-local data {marker.decode()!r} in {relative}")

    if failures:
        print("repository verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"verified {len(markdown)} documentation files and publication-safe fixtures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
