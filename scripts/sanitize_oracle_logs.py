#!/usr/bin/env python3
"""Replace machine-local paths in captured structural logs deterministically."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("structural", type=Path)
    parser.add_argument("--img2bez-work", type=Path, required=True)
    parser.add_argument("--reference-ufo", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    replacements = (
        (str(args.reference_ufo.resolve()), "<reference-ufo>"),
        (str(args.img2bez_work.resolve()), "<img2bez-work>"),
    )
    changed: list[Path] = []
    for path in sorted(args.structural.glob("*.log")):
        original = path.read_text(encoding="utf-8")
        sanitized = original
        for source, replacement in replacements:
            sanitized = sanitized.replace(source, replacement)
        if sanitized != original:
            changed.append(path)
            if not args.check:
                path.write_text(sanitized, encoding="utf-8")

    if args.check and changed:
        names = ", ".join(path.name for path in changed)
        raise SystemExit(f"structural logs require sanitization: {names}")
    action = "would sanitize" if args.check else "sanitized"
    print(f"{action} {len(changed)} structural logs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
