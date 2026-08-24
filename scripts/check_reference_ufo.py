#!/usr/bin/env python3
"""Validate that a UFO matches img2bez's recorded focused baseline shape."""

from __future__ import annotations

import argparse
import plistlib
import xml.etree.ElementTree as ET
from pathlib import Path

EXPECTED_ONCURVES = {
    "ampersand": 35,
    "a": 27,
    "e": 18,
    "s": 22,
    "R": 26,
    "O": 8,
    "S": 20,
    "n": 19,
}
BASIC_LATIN_NAMES = (
    list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    + "zero one two three four five six seven eight nine".split()
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ufo", type=Path)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    contents_path = args.ufo / "glyphs" / "contents.plist"
    if not contents_path.is_file():
        raise SystemExit(f"missing {contents_path}")
    with contents_path.open("rb") as stream:
        contents = plistlib.load(stream)

    failures: list[str] = []
    for glyph in BASIC_LATIN_NAMES:
        if glyph not in contents:
            failures.append(f"missing Basic Latin glyph {glyph!r}")
    for glyph, expected in EXPECTED_ONCURVES.items():
        filename = contents.get(glyph)
        if not filename:
            failures.append(f"missing focused glyph {glyph!r}")
            continue
        root = ET.parse(args.ufo / "glyphs" / filename).getroot()
        actual = sum(1 for point in root.findall("./outline/contour/point") if point.get("type"))
        if actual != expected:
            failures.append(f"{glyph}: expected {expected} on-curves, found {actual}")

    if failures:
        print("reference UFO does not match the recorded img2bez baseline:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    if not args.quiet:
        print("reference UFO matches the focused baseline fingerprint and contains all 62 glyphs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
