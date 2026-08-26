#!/usr/bin/env python3
"""Trace the owner-selected generated corpus twice and build a review report."""

from __future__ import annotations

import argparse
import html
import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
PLAN = FIXTURES / "corpus" / "milestone-5-plan.json"
SELECTIONS = FIXTURES / "corpus" / "milestone-5-selections.json"
SELECTED_SOURCES = FIXTURES / "corpus" / "milestone-5-selected-sources.json"
DEFAULT_OUTPUT = Path("/Volumes/T9/beztrace/milestone-5/reports/selected-generated-traces")


def fmt(value: float) -> str:
    if value == int(value):
        return str(int(value))
    return f"{value:.6f}".rstrip("0").rstrip(".")


def ordered_nodes(contour: dict) -> list[dict]:
    nodes = contour["nodes"]
    first_index = next(index for index, node in enumerate(nodes) if node["type"] != "offcurve")
    return nodes[first_index:] + nodes[:first_index]


def contour_directions(trace: dict) -> list[dict]:
    """Describe validated Y-up winding and its reflected baked-SVG winding."""
    result: list[dict] = []
    for index, contour in enumerate(trace["paths"], 1):
        on_curves = [node for node in ordered_nodes(contour) if node["type"] != "offcurve"]
        if len(on_curves) < 3:
            raise ValueError(f"contour {index} has fewer than three on-curve nodes")
        twice_area = sum(
            current["x"] * following["y"] - following["x"] * current["y"]
            for current, following in zip(on_curves, on_curves[1:] + on_curves[:1])
        )
        if abs(twice_area) <= 1e-9:
            raise ValueError(f"contour {index} has degenerate winding")
        json_winding = "counterclockwise" if twice_area > 0 else "clockwise"
        result.append(
            {
                "index": index,
                "role": "outer" if json_winding == "counterclockwise" else "counter",
                "jsonWinding": json_winding,
                "svgWinding": "clockwise" if json_winding == "counterclockwise" else "counterclockwise",
            }
        )
    return result


def path_data(contour: dict) -> tuple[str, list[tuple[float, float, str]], list[tuple[float, float, float, float]]]:
    ordered = ordered_nodes(contour)
    first = ordered[0]
    commands = [f"M {fmt(first['x'])} {fmt(first['y'])}"]
    points = [(first["x"], first["y"], first["type"])]
    handles: list[tuple[float, float, float, float]] = []
    pending: list[dict] = []
    previous = first
    for node in ordered[1:] + [first]:
        if node["type"] == "offcurve":
            pending.append(node)
            points.append((node["x"], node["y"], "offcurve"))
            continue
        if node["type"] == "curve":
            if len(pending) != 2:
                raise ValueError("curve segment does not have exactly two controls")
            commands.append(
                f"C {fmt(pending[0]['x'])} {fmt(pending[0]['y'])} "
                f"{fmt(pending[1]['x'])} {fmt(pending[1]['y'])} {fmt(node['x'])} {fmt(node['y'])}"
            )
            handles.append((previous["x"], previous["y"], pending[0]["x"], pending[0]["y"]))
            handles.append((pending[1]["x"], pending[1]["y"], node["x"], node["y"]))
        elif node["type"] == "line":
            if pending:
                raise ValueError("line segment has unexpected controls")
            commands.append(f"L {fmt(node['x'])} {fmt(node['y'])}")
        else:
            raise ValueError(f"unknown node type: {node['type']}")
        if node is not first:
            points.append((node["x"], node["y"], node["type"]))
        pending = []
        previous = node
    commands.append("Z")
    return " ".join(commands), points, handles


def direction_segment(contour: dict) -> tuple[float, float, float, float]:
    ordered = ordered_nodes(contour)
    start = ordered[0]
    target = next(
        node
        for node in ordered[1:] + [ordered[0]]
        if math.hypot(node["x"] - start["x"], node["y"] - start["y"]) > 1e-9
    )
    dx = target["x"] - start["x"]
    dy = target["y"] - start["y"]
    distance = math.hypot(dx, dy)
    length = min(56.0, max(28.0, distance * 0.35))
    return start["x"], start["y"], start["x"] + dx / distance * length, start["y"] + dy / distance * length


def inspection_svg(trace: dict) -> str:
    min_x, min_y, max_x, max_y = trace["bounds"]
    pad = max(64.0, 0.08 * max(max_x - min_x, max_y - min_y))
    view_box = f"{fmt(min_x-pad)} {fmt(min_y-pad)} {fmt(max_x-min_x+2*pad)} {fmt(max_y-min_y+2*pad)}"
    flip = min_y + max_y
    paths: list[str] = []
    control_lines: list[str] = []
    markers: list[str] = []
    directions: list[str] = []
    metadata = contour_directions(trace)
    for contour, direction in zip(trace["paths"], metadata):
        data, points, handles = path_data(contour)
        paths.append(f'<path d="{data}"/>')
        for x1, y1, x2, y2 in handles:
            control_lines.append(
                f'<line x1="{fmt(x1)}" y1="{fmt(y1)}" x2="{fmt(x2)}" y2="{fmt(y2)}"/>'
            )
        for x, y, kind in points:
            if kind == "offcurve":
                markers.append(f'<circle class="off" cx="{fmt(x)}" cy="{fmt(y)}" r="5"/>')
            else:
                markers.append(f'<rect class="on" x="{fmt(x-6)}" y="{fmt(y-6)}" width="12" height="12"/>')
        x1, y1, x2, y2 = direction_segment(contour)
        label = (
            f"Contour {direction['index']}: {direction['role']}; "
            f"JSON Y-up {direction['jsonWinding']}; baked SVG {direction['svgWinding']}"
        )
        directions.append(
            f'<line class="direction" x1="{fmt(x1)}" y1="{fmt(y1)}" '
            f'x2="{fmt(x2)}" y2="{fmt(y2)}" marker-end="url(#direction-arrow)"><title>{label}</title></line>'
        )
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}">\n'
        '<defs><marker id="direction-arrow" viewBox="0 0 10 10" refX="8" refY="5" '
        'markerWidth="10" markerHeight="10" orient="auto-start-reverse" markerUnits="userSpaceOnUse">'
        '<path d="M 0 0 L 10 5 L 0 10 Z" fill="#ff5a36"/></marker></defs>\n'
        '<rect width="100%" height="100%" fill="white"/>\n'
        f'<g transform="translate(0 {fmt(flip)}) scale(1 -1)">\n'
        f'<g fill="black" fill-rule="nonzero">{"".join(paths)}</g>\n'
        f'<g fill="none" stroke="#1683ff" stroke-width="2">{"".join(control_lines)}</g>\n'
        f'<g class="nodes" stroke="#1683ff" stroke-width="2"><g fill="white">{"".join(markers)}</g></g>\n'
        f'<g fill="none" stroke="#ff5a36" stroke-width="5">{"".join(directions)}</g>\n'
        '</g>\n</svg>\n'
    )


def trace(binary: Path, source: Path, output_format: str, svg_transform: str | None = None) -> bytes:
    command = [str(binary), "trace", str(source), "--format", output_format]
    if svg_transform is not None:
        if output_format != "svg":
            raise ValueError("svg_transform is valid only for SVG output")
        command.extend(["--svg-transform", svg_transform])
    result = subprocess.run(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{source.name}: trace failed ({result.returncode}): {result.stderr.decode('utf-8', 'replace')}")
    return result.stdout


def winding_abbreviation(value: str) -> str:
    return "CCW" if value == "counterclockwise" else "CW"


def render_page(records: list[dict]) -> str:
    rows: list[str] = []
    for record in records:
        source_uri = Path(record["source"]).as_uri()
        clean = f"svg/{record['id']}.svg"
        preserve = f"svg-preserve/{record['id']}.svg"
        inspection = f"inspection/{record['id']}.svg"
        contours = "".join(
            f"<li><strong>C{item['index']}</strong> {item['role']} · "
            f"Y-up {winding_abbreviation(item['jsonWinding'])} → "
            f"baked {winding_abbreviation(item['svgWinding'])}</li>"
            for item in record["contours"]
        )
        rows.append(
            f"<section><h2>{html.escape(record['id'])}</h2><p>Candidate {record['candidate']} · "
            f"{record['contourCount']} contours · {record['nodeCount']} nodes · trace review pending</p>"
            f"<div class='renders'><figure><img src='{source_uri}' alt='Selected raster source for {html.escape(record['id'])}'>"
            f"<figcaption>Selected source</figcaption></figure>"
            f"<figure><img src='{clean}' alt='Transform-free baked SVG rendering of {html.escape(record['id'])}'>"
            f"<figcaption>Baked SVG render</figcaption></figure>"
            f"<figure><img src='{preserve}' alt='Y-up preserve-mode SVG rendering of {html.escape(record['id'])}'>"
            f"<figcaption>Preserve SVG render</figcaption></figure>"
            f"<figure><img src='{inspection}' alt='Nodes, handles, and contour direction for {html.escape(record['id'])}'>"
            f"<figcaption>Nodes, handles, and direction</figcaption></figure></div>"
            f"<ul class='contours'>{contours}</ul></section>"
        )
    return """<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>beztrace SVG rendering review</title><style>
body{font:16px system-ui;margin:32px;background:#eee;color:#171717}main{max-width:1720px;margin:auto}section{background:white;border-radius:16px;padding:20px;margin:20px 0}
.renders{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:18px}figure{margin:0}img{width:100%;aspect-ratio:1;object-fit:contain;border:1px solid #ccc;background:white;border-radius:10px}figcaption{text-align:center;margin-top:8px;font-weight:650}p{color:#555}
.legend{background:#fff;border-radius:12px;padding:14px 18px;line-height:1.5}.contours{display:flex;flex-wrap:wrap;gap:8px 22px;list-style:none;padding:0;margin:14px 0 0;color:#555}.contours strong{color:#171717}
@media(max-width:1100px){.renders{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:620px){body{margin:14px}.renders{grid-template-columns:1fr}}
</style><main><h1>beztrace SVG rendering review</h1><div class="legend">Baked and preserve SVGs must render identically. JSON uses Y-up font coordinates; baking reflects Y for transform-free SVG output, so every contour winding reverses. Orange arrows show rendered traversal; blue marks show nodes and handles.</div>""" + "\n".join(rows) + "</main></html>\n"


def finite(value: object) -> bool:
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return True
    if isinstance(value, (int, float)):
        return math.isfinite(value)
    if isinstance(value, list):
        return all(finite(item) for item in value)
    if isinstance(value, dict):
        return all(finite(item) for item in value.values())
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=ROOT / ".build" / "release" / "beztrace")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file():
        raise FileNotFoundError(binary)

    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    selections = json.loads(SELECTIONS.read_text(encoding="utf-8"))
    pinned = json.loads(SELECTED_SOURCES.read_text(encoding="utf-8"))
    choices = {item["id"]: item["candidate"] for item in selections["selections"]}
    hashes = {item["id"]: item["normalizedSHA256"] for item in pinned["sources"]}
    concepts = [
        *({**item, "category": "glyph"} for item in plan["addedGlyphs"]),
        *({**item, "category": "symbol"} for item in plan["addedSymbols"]),
    ]

    output = args.output
    json_dir = output / "json"
    svg_dir = output / "svg"
    preserve_svg_dir = output / "svg-preserve"
    inspection_dir = output / "inspection"
    for directory in (json_dir, svg_dir, preserve_svg_dir, inspection_dir):
        directory.mkdir(parents=True, exist_ok=True)

    records: list[dict] = []
    for index, concept in enumerate(concepts, 1):
        identifier = concept["id"]
        source = FIXTURES / "corpus" / "generated" / ("glyphs" if concept["category"] == "glyph" else "symbols") / f"{identifier}.png"
        json_first = trace(binary, source, "json")
        json_second = trace(binary, source, "json")
        svg_first = trace(binary, source, "svg", "bake")
        svg_second = trace(binary, source, "svg", "bake")
        preserve_first = trace(binary, source, "svg", "preserve")
        preserve_second = trace(binary, source, "svg", "preserve")
        if json_first != json_second or svg_first != svg_second or preserve_first != preserve_second:
            raise RuntimeError(f"{identifier}: trace output is nondeterministic")
        document = json.loads(json_first)
        if not finite(document):
            raise RuntimeError(f"{identifier}: trace contains a non-finite number")
        if not document.get("paths") or any(not contour.get("closed") for contour in document["paths"]):
            raise RuntimeError(f"{identifier}: trace is empty or open")
        if document["source"]["sha256"] != hashes[identifier]:
            raise RuntimeError(f"{identifier}: tracer source hash differs from pinned normalized hash")
        (json_dir / f"{identifier}.json").write_bytes(json_first)
        (svg_dir / f"{identifier}.svg").write_bytes(svg_first)
        (preserve_svg_dir / f"{identifier}.svg").write_bytes(preserve_first)
        (inspection_dir / f"{identifier}.svg").write_text(inspection_svg(document), encoding="utf-8")
        records.append(
            {
                "id": identifier,
                "category": concept["category"],
                "content": concept["content"],
                "candidate": choices[identifier],
                "source": str(source),
                "contourCount": document["statistics"]["contourCount"],
                "nodeCount": document["statistics"]["nodeCount"],
                "lineCount": document["statistics"]["lineCount"],
                "curveCount": document["statistics"]["curveCount"],
                "warnings": document.get("warnings", []),
                "contours": contour_directions(document),
                "automaticChecks": "passed",
                "traceAcceptanceStatus": "pending-human-review",
            }
        )
        print(f"[{index:02d}/38] {identifier}: {document['statistics']['contourCount']} contours, {document['statistics']['nodeCount']} nodes")

    report = {
        "schemaVersion": 1,
        "sourceReviewStatus": "source-selected",
        "traceAcceptanceStatus": "pending-human-review",
        "deterministicRuns": 2,
        "fixtures": records,
    }
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    (output / "index.html").write_text(render_page(records), encoding="utf-8")
    print(f"wrote trace review for {len(records)} fixtures to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
