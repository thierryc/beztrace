#!/usr/bin/env python3
"""Build a read-only review index for the external generated candidate pool."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import struct
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / "Tests" / "Fixtures" / "corpus" / "milestone-5-plan.json"
DEFAULT_WORK = Path("/Volumes/T9/beztrace/milestone-5")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_profile(path: Path) -> tuple[int, int, str]:
    data = path.read_bytes()
    header = data[:26]
    if len(header) != 26 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a valid PNG")
    width, height = struct.unpack(">II", header[16:24])
    color_type = header[25]
    alpha_policy = "alpha" if color_type in (4, 6) or b"tRNS" in data else "opaque"
    return width, height, alpha_policy


def concepts(plan: dict) -> list[dict]:
    values: list[dict] = []
    for category, key in (("glyph", "addedGlyphs"), ("symbol", "addedSymbols")):
        for item in plan[key]:
            values.append({**item, "category": category})
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, default=DEFAULT_WORK)
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()

    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    pool = args.work / "generated-candidates"
    output = args.work / "reports" / "generated-review"
    output.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    failures: list[str] = []
    for concept in concepts(plan):
        candidates: list[dict] = []
        for index in range(1, plan["candidateCountPerGeneratedConcept"] + 1):
            path = pool / concept["id"] / f"candidate-{index:02d}.png"
            if not path.is_file():
                failures.append(f"missing {path}")
                continue
            try:
                width, height, alpha_policy = png_profile(path)
            except ValueError as error:
                failures.append(str(error))
                continue
            candidates.append(
                {
                    "candidate": index,
                    "path": str(path),
                    "sha256": sha256(path),
                    "width": width,
                    "height": height,
                    "alphaPolicy": alpha_policy,
                }
            )
        records.append({**concept, "candidates": candidates})

    manifest = {
        "schemaVersion": 1,
        "generatedOn": date.today().isoformat(),
        "generator": "OpenAI built-in image generation; model version not exposed",
        "reviewer": "project-owner",
        "reviewStatus": "pending",
        "concepts": records,
    }
    (output / "candidate-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    sections: list[str] = []
    for record in records:
        cards = []
        for candidate in record["candidates"]:
            source = Path(candidate["path"])
            relative = source.relative_to(output, walk_up=True)
            cards.append(
                "<figure><a href='{href}'><img src='{href}' alt='{alt}'></a>"
                "<figcaption><label><input type='radio' name='{name}' value='{index}'> "
                "Candidate {index}</label><br><span>{width}x{height} · {alpha}</span><br>"
                "<code>{digest}</code></figcaption></figure>".format(
                    href=html.escape(str(relative)),
                    alt=html.escape(f"{record['id']} candidate {candidate['candidate']}"),
                    name=html.escape(record["id"]),
                    index=candidate["candidate"],
                    width=candidate["width"],
                    height=candidate["height"],
                    alpha=html.escape(candidate["alphaPolicy"]),
                    digest=candidate["sha256"][:16],
                )
            )
        sections.append(
            f"<section><h2>{html.escape(record['id'])}</h2>"
            f"<p>{html.escape(record['content'])} · {record['category']}</p>"
            f"<div class='candidates'>{''.join(cards)}</div></section>"
        )
    document = """<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>beztrace Milestone 5 generated-source review</title>
<style>
body{font:16px system-ui;margin:32px;background:#eee;color:#171717}main{max-width:1200px;margin:auto}
section{background:white;border-radius:16px;padding:20px;margin:20px 0}.candidates{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}
figure{margin:0}img{width:100%;aspect-ratio:1;object-fit:contain;border:1px solid #ccc;border-radius:10px;background:white}code{font-size:12px}
label{font-weight:700;cursor:pointer}figcaption span{color:#555;font-size:13px}.toolbar{position:sticky;top:12px;background:#171717;color:white;padding:14px 18px;border-radius:12px;display:flex;align-items:center;gap:16px;z-index:2}.toolbar button{margin-left:auto;padding:9px 14px;font:inherit;font-weight:700}
</style><main><h1>beztrace generated-source review</h1>
<p>Select one source silhouette per concept before tracing. Choices are stored only in this browser and do not modify fixtures or approve traced output.</p>
<div class="toolbar"><span id="progress">0 of 38 selected</span><button id="export" type="button">Export selections.json</button></div>
""" + "\n".join(sections) + """</main>
<script>
const storageKey = "beztrace-milestone-5-generated-selections-v1";
const radios = [...document.querySelectorAll("input[type=radio]")];
const saved = JSON.parse(localStorage.getItem(storageKey) || "{}");
for (const radio of radios) {
  if (String(saved[radio.name]) === radio.value) radio.checked = true;
  radio.addEventListener("change", () => {
    saved[radio.name] = Number(radio.value);
    localStorage.setItem(storageKey, JSON.stringify(saved));
    updateProgress();
  });
}
function updateProgress() {
  const selected = new Set(radios.filter(radio => radio.checked).map(radio => radio.name));
  document.getElementById("progress").textContent = `${selected.size} of 38 selected`;
}
document.getElementById("export").addEventListener("click", () => {
  const selections = [...new Set(radios.map(radio => radio.name))]
    .filter(identifier => saved[identifier])
    .map(identifier => ({id: identifier, candidate: saved[identifier]}));
  const payload = {
    schemaVersion: 1,
    reviewer: "project-owner",
    reviewStatus: selections.length === 38 ? "source-selected" : "incomplete",
    selections,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2) + "\\n"], {type: "application/json"});
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "selections.json";
  link.click();
  URL.revokeObjectURL(link.href);
});
updateProgress();
</script></html>
"""
    (output / "index.html").write_text(document, encoding="utf-8")

    if failures and not args.allow_incomplete:
        print("generated review pool is incomplete:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"indexed {sum(len(item['candidates']) for item in records)} candidates for {len(records)} concepts at {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
