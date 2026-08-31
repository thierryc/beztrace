#!/usr/bin/env python3
"""Create full-canvas display SVGs from beztrace's tightly bounded baked SVGs.

Normal verification is read-only. Pass ``--write`` only when regenerating the
site example assets and their manifest hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
MANIFEST = SITE / "assets" / "examples" / "manifest.json"
CANVAS_SIZE = 1088.0
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
TOKEN_RE = re.compile(rf"[MLCZ]|{NUMBER}")
COMMAND_RE = re.compile(r"[A-Za-z]")
ARITY = {"M": 2, "L": 2, "C": 6}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def format_number(value: float) -> str:
    if not math.isfinite(value):
        raise ValueError("SVG contains a non-finite coordinate")
    if abs(value) < 0.5e-12:
        value = 0.0
    if value.is_integer():
        return str(int(value))
    return format(value, ".15g")


def path_tokens(path_data: str) -> list[str]:
    unsupported = sorted(set(COMMAND_RE.findall(path_data)) - set("MLCZ"))
    if unsupported:
        raise ValueError(f"unsupported SVG path command: {', '.join(unsupported)}")

    tokens: list[str] = []
    end = 0
    for match in TOKEN_RE.finditer(path_data):
        if path_data[end : match.start()].strip(" ,\t\r\n"):
            raise ValueError("malformed SVG path data")
        tokens.append(match.group(0))
        end = match.end()
    if path_data[end:].strip(" ,\t\r\n"):
        raise ValueError("malformed SVG path data")
    return tokens


def translate_path_y(path_data: str, delta_y: float) -> str:
    output: list[str] = []
    command: str | None = None
    coordinate_index = 0

    for token in path_tokens(path_data):
        if token in {"M", "L", "C", "Z"}:
            output.append(token)
            if token == "Z":
                command = None
                coordinate_index = 0
            else:
                command = token
                coordinate_index = 0
            continue
        if command is None:
            raise ValueError("SVG coordinate has no path command")
        value = float(token)
        if coordinate_index % 2 == 1:
            value += delta_y
        output.append(format_number(value))
        coordinate_index = (coordinate_index + 1) % ARITY[command]

    return " ".join(output)


def inspection_markup(path_data: str) -> str:
    tokens = path_tokens(path_data)
    handles: list[tuple[tuple[float, float], tuple[float, float]]] = []
    oncurves: list[tuple[float, float]] = []
    offcurves: list[tuple[float, float]] = []
    command: str | None = None
    current: tuple[float, float] | None = None
    contour_start: tuple[float, float] | None = None
    index = 0

    def coordinates(count: int) -> list[float]:
        nonlocal index
        if index + count > len(tokens) or any(token in {"M", "L", "C", "Z"} for token in tokens[index : index + count]):
            raise ValueError("malformed SVG path command")
        values = [float(token) for token in tokens[index : index + count]]
        index += count
        return values

    while index < len(tokens):
        token = tokens[index]
        if token in {"M", "L", "C", "Z"}:
            command = token
            index += 1
            if command == "Z":
                current = contour_start
                command = None
                continue
        if command == "M":
            x, y = coordinates(2)
            current = (x, y)
            contour_start = current
            oncurves.append(current)
            command = "L"
        elif command == "L":
            x, y = coordinates(2)
            current = (x, y)
            oncurves.append(current)
        elif command == "C":
            if current is None:
                raise ValueError("cubic segment has no starting point")
            c1x, c1y, c2x, c2y, x, y = coordinates(6)
            first_control = (c1x, c1y)
            second_control = (c2x, c2y)
            endpoint = (x, y)
            handles.append((current, first_control))
            handles.append((second_control, endpoint))
            offcurves.extend((first_control, second_control))
            oncurves.append(endpoint)
            current = endpoint
        else:
            raise ValueError("SVG coordinate has no path command")

    lines = [
        (
            f'<line class="trace-handle" x1="{format_number(start[0])}" y1="{format_number(start[1])}" '
            f'x2="{format_number(end[0])}" y2="{format_number(end[1])}"/>'
        )
        for start, end in handles
    ]
    nodes = [
        (
            f'<rect class="trace-oncurve" x="{format_number(x - 3)}" y="{format_number(y - 3)}" '
            'width="6" height="6"/>'
        )
        for x, y in oncurves
    ]
    controls = [
        f'<circle class="trace-offcurve" cx="{format_number(x)}" cy="{format_number(y)}" r="2.5"/>'
        for x, y in offcurves
    ]
    return "\n".join((*lines, *nodes, *controls))


def align_svg_text(source: str) -> str:
    if re.search(r"\btransform\s*=", source) or "<g" in source:
        raise ValueError("site alignment requires a baked, transform-free SVG")
    try:
        root = ET.fromstring(source)
    except ET.ParseError as error:
        raise ValueError(f"malformed SVG: {error}") from error

    view_box = root.attrib.get("viewBox", "").split()
    if len(view_box) != 4:
        raise ValueError("SVG must have a four-number viewBox")
    values = [float(value) for value in view_box]
    if not all(math.isfinite(value) for value in values) or values[2] <= 0 or values[3] <= 0:
        raise ValueError("SVG viewBox is invalid")

    paths = [element for element in root.iter() if element.tag.rsplit("}", 1)[-1] == "path"]
    if len(paths) != 1 or not paths[0].attrib.get("d"):
        raise ValueError("SVG must contain exactly one traced path")

    min_y = values[1]
    max_y = min_y + values[3]
    delta_y = CANVAS_SIZE - (min_y + max_y)
    path = paths[0]
    path_data = translate_path_y(path.attrib["d"], delta_y)
    fill = html.escape(path.attrib.get("fill", "black"), quote=True)
    fill_rule = html.escape(path.attrib.get("fill-rule", "nonzero"), quote=True)
    overlay = inspection_markup(path_data)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1088 1088" aria-hidden="true">\n'
        "<style>\n"
        ".trace-handle{fill:none;stroke:#2456f5;stroke-width:.85;stroke-opacity:.28;vector-effect:non-scaling-stroke}\n"
        ".trace-oncurve{fill:#fff;fill-opacity:.78;stroke:#2456f5;stroke-width:.85;stroke-opacity:.62;vector-effect:non-scaling-stroke}\n"
        ".trace-offcurve{fill:#fff;fill-opacity:.62;stroke:#2456f5;stroke-width:.85;stroke-opacity:.48;vector-effect:non-scaling-stroke}\n"
        "</style>\n"
        f'<path d="{html.escape(path_data, quote=True)}" fill="{fill}" fill-rule="{fill_rule}"/>\n'
        f"{overlay}\n"
        "</svg>\n"
    )


def regenerate(write: bool) -> list[str]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    failures: list[str] = []

    for example in manifest.get("examples", []):
        production_relative = example.get("productionSVG", example["svg"])
        production_path = SITE / production_relative
        display_relative = str(Path(production_relative).with_name(f"{Path(production_relative).stem}-canvas.svg"))
        display_path = SITE / display_relative
        aligned = align_svg_text(production_path.read_text(encoding="utf-8"))
        aligned_bytes = aligned.encode("utf-8")

        expected = {
            "productionSVG": production_relative,
            "productionSVGSHA256": sha256_bytes(production_path.read_bytes()),
            "svg": display_relative,
            "svgSHA256": sha256_bytes(aligned_bytes),
            "canvasAligned": True,
            "inspectionOverlay": True,
            "viewBox": [0, 0, 1088, 1088],
        }

        if write:
            display_path.write_bytes(aligned_bytes)
            example.update(expected)
            continue

        if not display_path.is_file() or display_path.read_bytes() != aligned_bytes:
            failures.append(f"{example['id']}: canvas-aligned SVG differs")
        for key, value in expected.items():
            if example.get(key) != value:
                failures.append(f"{example['id']}: manifest {key} differs")

    if write:
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="regenerate display SVGs and manifest hashes")
    args = parser.parse_args()
    failures = regenerate(write=args.write)
    if failures:
        print("site SVG alignment verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("regenerated canvas-aligned site SVGs" if args.write else "verified canvas-aligned site SVGs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
