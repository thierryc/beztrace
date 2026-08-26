#!/usr/bin/env python3
"""Trace the complete 100-image corpus and build a local human-review report."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path

from trace_generated_review import (
    ROOT,
    contour_directions,
    finite,
    inspection_svg,
    trace,
    winding_abbreviation,
)

FIXTURES = ROOT / "Tests" / "Fixtures"
MANIFEST = FIXTURES / "manifest.json"
DEFAULT_OUTPUT = Path("/Volumes/T9/beztrace/milestone-6/reports/corpus-trace-review")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def acceptance_template(records: list[dict], manifest_hash: str) -> dict:
    return {
        "schemaVersion": 1,
        "reviewer": "project-owner",
        "reviewStatus": "in-progress",
        "corpusManifestSHA256": manifest_hash,
        "decisions": [
            {"id": record["id"], "status": "pending", "notes": ""}
            for record in records
        ],
    }


def render_review_page(records: list[dict], manifest_hash: str) -> str:
    rows: list[str] = []
    for record in records:
        identifier = html.escape(record["id"], quote=True)
        source_uri = html.escape(Path(record["source"]).as_uri(), quote=True)
        contours = "".join(
            f"<li><strong>C{item['index']}</strong> {item['role']} · "
            f"Y-up {winding_abbreviation(item['jsonWinding'])} → "
            f"baked {winding_abbreviation(item['svgWinding'])}</li>"
            for item in record["contours"]
        )
        expected = html.escape(record.get("expectedTopology", "not declared"))
        rows.append(
            f"<section class='fixture' data-id='{identifier}'><header><div><h2>{identifier}</h2>"
            f"<p>{html.escape(record['sourceKind'])} {html.escape(record['category'])} · "
            f"{record['contourCount']} contours · {record['nodeCount']} nodes</p>"
            f"<p class='expected'>Expected: {expected}</p></div><strong class='state pending'>Pending</strong></header>"
            "<div class='renders'>"
            f"<figure><img src='{source_uri}' alt='Raster source for {identifier}'><figcaption>Source raster</figcaption></figure>"
            f"<figure><img src='svg/{identifier}.svg' alt='Baked SVG for {identifier}'><figcaption>Baked SVG render</figcaption></figure>"
            f"<figure><img src='svg-preserve/{identifier}.svg' alt='Preserve SVG for {identifier}'><figcaption>Preserve SVG render</figcaption></figure>"
            f"<figure><img src='inspection/{identifier}.svg' alt='Nodes, handles, and direction for {identifier}'><figcaption>Nodes, handles, and direction</figcaption></figure>"
            f"</div><ul class='contours'>{contours}</ul>"
            "<div class='review'><div class='buttons'>"
            "<button type='button' data-status='accepted'>Accept</button>"
            "<button type='button' data-status='accepted-with-optical-notes'>Optical note</button>"
            "<button type='button' data-status='rejected'>Reject</button>"
            "<button type='button' data-status='pending'>Clear</button></div>"
            "<label>Review notes <textarea rows='2' placeholder='Required for optical notes or rejection'></textarea></label>"
            "</div></section>"
        )
    template = json.dumps(acceptance_template(records, manifest_hash), separators=(",", ":"))
    return """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>beztrace complete corpus review</title><style>
:root{color-scheme:light}*{box-sizing:border-box}body{font:16px system-ui;margin:28px;background:#ececec;color:#171717}main{max-width:1720px;margin:auto}
.toolbar,.fixture{background:white;border-radius:16px;padding:20px;margin:20px 0}.toolbar{position:sticky;top:8px;z-index:5;box-shadow:0 5px 24px #0002}.toolbar p{margin:.35rem 0;color:#555}
.summary{display:flex;gap:12px;flex-wrap:wrap;margin:12px 0}.summary span{background:#eee;border-radius:999px;padding:6px 11px}.toolbar button{font:inherit;font-weight:700;padding:9px 14px}
header{display:flex;justify-content:space-between;gap:20px}h2{margin:0}.fixture p{color:#555}.expected{font-size:.92rem}.state{height:max-content;padding:6px 10px;border-radius:999px;background:#eee}.state.accepted{background:#d9f8df;color:#126426}.state.accepted-with-optical-notes{background:#fff1bf;color:#704d00}.state.rejected{background:#ffd9d5;color:#8a1d12}
.renders{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}figure{margin:0}img{display:block;width:100%;aspect-ratio:1;object-fit:contain;border:1px solid #ccc;background:white;border-radius:10px}figcaption{text-align:center;margin-top:8px;font-weight:650}
.contours{display:flex;flex-wrap:wrap;gap:8px 22px;list-style:none;padding:0;color:#555}.review{display:grid;grid-template-columns:auto 1fr;gap:18px;align-items:end}.buttons{display:flex;gap:8px;flex-wrap:wrap}.buttons button{font:inherit;padding:8px 12px}.buttons button.selected{outline:3px solid #1683ff}label{display:grid;gap:5px;font-weight:650}textarea{font:inherit;width:100%;padding:8px}
@media(max-width:1100px){.renders{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:720px){body{margin:12px}.renders{grid-template-columns:1fr}.review{grid-template-columns:1fr}}
</style></head><body><main><h1>beztrace complete corpus review</h1>
<div class="toolbar"><p>Compare the source with both production serializers and the transform-free inspection overlay. The overlay is baked point-for-point and adds padded nodes, handles, and traversal arrows.</p>
<p>Accept traces only when topology, counters, direction, node economy, corners, curves, and optical shape are usable. Optical-note and rejection decisions require notes.</p>
<div class="summary"><span id="accepted">Accepted: 0</span><span id="optical">Optical notes: 0</span><span id="rejected">Rejected: 0</span><span id="pending">Pending: 0</span></div>
<button id="export" type="button">Export review JSON</button></div>
""" + "\n".join(rows) + f"""
<script>const template={template};const storageKey="beztrace-review-"+template.corpusManifestSHA256;
let saved;try{{saved=JSON.parse(localStorage.getItem(storageKey))}}catch(_error){{saved=null}}
const decisions=new Map((saved&&saved.decisions||template.decisions).map(item=>[item.id,item]));
function label(status){{return {{accepted:"Accepted","accepted-with-optical-notes":"Optical note",rejected:"Rejected",pending:"Pending"}}[status]}}
function refresh(){{const counts={{accepted:0,"accepted-with-optical-notes":0,rejected:0,pending:0}};document.querySelectorAll(".fixture").forEach(section=>{{const item=decisions.get(section.dataset.id)||{{id:section.dataset.id,status:"pending",notes:""}};decisions.set(item.id,item);counts[item.status]++;section.querySelector(".state").className="state "+item.status;section.querySelector(".state").textContent=label(item.status);section.querySelector("textarea").value=item.notes||"";section.querySelectorAll("button[data-status]").forEach(button=>button.classList.toggle("selected",button.dataset.status===item.status));}});document.querySelector("#accepted").textContent="Accepted: "+counts.accepted;document.querySelector("#optical").textContent="Optical notes: "+counts["accepted-with-optical-notes"];document.querySelector("#rejected").textContent="Rejected: "+counts.rejected;document.querySelector("#pending").textContent="Pending: "+counts.pending;localStorage.setItem(storageKey,JSON.stringify({{decisions:[...decisions.values()]}}));}}
document.querySelectorAll(".fixture").forEach(section=>{{section.querySelectorAll("button[data-status]").forEach(button=>button.addEventListener("click",()=>{{const item=decisions.get(section.dataset.id);item.status=button.dataset.status;refresh();}}));section.querySelector("textarea").addEventListener("input",event=>{{decisions.get(section.dataset.id).notes=event.target.value;refresh();}});}});
document.querySelector("#export").addEventListener("click",()=>{{const values=template.decisions.map(item=>decisions.get(item.id));const invalid=values.filter(item=>(item.status==="rejected"||item.status==="accepted-with-optical-notes")&&!item.notes.trim());if(invalid.length){{alert("Add notes for: "+invalid.map(item=>item.id).join(", "));return}}const output={{...template,reviewStatus:values.some(item=>item.status==="pending")?"in-progress":"complete",reviewedOn:new Date().toISOString(),decisions:values}};const blob=new Blob([JSON.stringify(output,null,2)+"\\n"],{{type:"application/json"}});const anchor=document.createElement("a");anchor.href=URL.createObjectURL(blob);anchor.download="trace-acceptance.json";anchor.click();URL.revokeObjectURL(anchor.href);}});refresh();</script></main></body></html>\n"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=ROOT / ".build" / "release" / "beztrace")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file():
        raise SystemExit(f"binary does not exist: {binary}")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    fixtures = manifest.get("fixtures", [])
    if len(fixtures) != 100 or len({item.get("id") for item in fixtures}) != 100:
        raise RuntimeError("corpus manifest must contain exactly 100 unique fixtures")
    manifest_hash = sha256(MANIFEST)
    output = args.output.resolve()
    directories = {name: output / name for name in ("json", "svg", "svg-preserve", "inspection")}
    for directory in directories.values():
        directory.mkdir(parents=True, exist_ok=True)

    records: list[dict] = []
    for index, fixture in enumerate(fixtures, 1):
        identifier = fixture["id"]
        source = FIXTURES / fixture["path"]
        if sha256(source) != fixture["sha256"]:
            raise RuntimeError(f"{identifier}: source hash differs from manifest")
        json_first, json_second = trace(binary, source, "json"), trace(binary, source, "json")
        baked_first, baked_second = trace(binary, source, "svg", "bake"), trace(binary, source, "svg", "bake")
        preserve_first, preserve_second = trace(binary, source, "svg", "preserve"), trace(binary, source, "svg", "preserve")
        if json_first != json_second or baked_first != baked_second or preserve_first != preserve_second:
            raise RuntimeError(f"{identifier}: trace output is nondeterministic")
        document = json.loads(json_first)
        if not finite(document):
            raise RuntimeError(f"{identifier}: trace contains a non-finite number")
        if not document.get("paths") or any(not contour.get("closed") for contour in document["paths"]):
            raise RuntimeError(f"{identifier}: trace is empty or open")
        if document["source"]["sha256"] != fixture["sha256"]:
            raise RuntimeError(f"{identifier}: tracer source hash differs from manifest")
        expected_contours = fixture.get("expectedContours")
        if expected_contours is not None and document["statistics"]["contourCount"] != expected_contours:
            raise RuntimeError(
                f"{identifier}: expected {expected_contours} contours, "
                f"found {document['statistics']['contourCount']}"
            )
        (directories["json"] / f"{identifier}.json").write_bytes(json_first)
        (directories["svg"] / f"{identifier}.svg").write_bytes(baked_first)
        (directories["svg-preserve"] / f"{identifier}.svg").write_bytes(preserve_first)
        (directories["inspection"] / f"{identifier}.svg").write_text(
            inspection_svg(document), encoding="utf-8"
        )
        records.append(
            {
                "id": identifier,
                "category": fixture["category"],
                "sourceKind": fixture["sourceKind"],
                "source": str(source.resolve()),
                "sourceSHA256": fixture["sha256"],
                "expectedTopology": fixture.get("expectedTopology", ""),
                "expectedContours": expected_contours,
                "contourCount": document["statistics"]["contourCount"],
                "nodeCount": document["statistics"]["nodeCount"],
                "lineCount": document["statistics"]["lineCount"],
                "curveCount": document["statistics"]["curveCount"],
                "contours": contour_directions(document),
                "automaticChecks": "passed",
            }
        )
        print(f"[{index:03d}/100] {identifier}")

    report = {
        "schemaVersion": 1,
        "corpusManifestSHA256": manifest_hash,
        "fixtureCount": len(records),
        "deterministicRuns": 2,
        "automaticChecks": "passed",
        "fixtures": records,
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (output / "trace-acceptance-template.json").write_text(
        json.dumps(acceptance_template(records, manifest_hash), indent=2) + "\n", encoding="utf-8"
    )
    (output / "index.html").write_text(render_review_page(records, manifest_hash), encoding="utf-8")
    print(f"wrote complete-corpus trace review to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
