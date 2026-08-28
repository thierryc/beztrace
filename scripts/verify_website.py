#!/usr/bin/env python3
"""Validate the static GitHub Pages site and its traced example assets."""

from __future__ import annotations

import re
import hashlib
import json
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
WORKFLOW = ROOT / ".github" / "workflows" / "pages.yml"
REQUIRED_EXAMPLES = 8


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SiteParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.references: list[str] = []
        self.examples = 0
        self.ids: list[str] = []
        self.title = ""
        self.description = ""
        self._in_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "title":
            self._in_title = True
        if "id" in values and values["id"]:
            self.ids.append(values["id"])
        if "data-example" in values:
            self.examples += 1
        if tag in {"a", "link"} and values.get("href"):
            self.references.append(values["href"] or "")
        if tag in {"img", "script"} and values.get("src"):
            self.references.append(values["src"] or "")
        if tag == "meta" and values.get("name") == "description":
            self.description = values.get("content", "") or ""

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title += data


def local_path(reference: str) -> Path | None:
    parsed = urlsplit(reference)
    if parsed.scheme or parsed.netloc or reference.startswith("#"):
        return None
    return SITE / parsed.path.lstrip("/")


def main() -> int:
    failures: list[str] = []
    index = SITE / "index.html"
    if not index.is_file():
        failures.append("missing site/index.html")
    if not WORKFLOW.is_file():
        failures.append("missing GitHub Pages workflow")
    if failures:
        print("website verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    source = index.read_text(encoding="utf-8")
    parser = SiteParser()
    parser.feed(source)

    if "beztrace" not in parser.title.lower():
        failures.append("document title does not identify beztrace")
    if len(parser.description) < 60:
        failures.append("meta description is missing or too short")
    if parser.examples < REQUIRED_EXAMPLES:
        failures.append(f"expected at least {REQUIRED_EXAMPLES} trace examples, found {parser.examples}")
    if len(parser.ids) != len(set(parser.ids)):
        failures.append("HTML ids must be unique")
    for phrase in ("Y-up JSON", "transform-free SVG", "v0.1.0", "Glyphs MCP"):
        if phrase not in source:
            failures.append(f"missing product contract copy: {phrase}")

    for reference in parser.references:
        if reference.startswith(("file:", "/Users/", "/Volumes/")):
            failures.append(f"private or absolute reference: {reference}")
            continue
        path = local_path(reference)
        if path is not None and not path.is_file():
            failures.append(f"missing local site asset: {reference}")

    svg_files = sorted((SITE / "assets" / "examples").glob("*.svg"))
    png_files = sorted((SITE / "assets" / "examples").glob("*.png"))
    if len(svg_files) < REQUIRED_EXAMPLES or len(png_files) < REQUIRED_EXAMPLES:
        failures.append(
            f"expected {REQUIRED_EXAMPLES} source/trace pairs, found {len(png_files)} PNG and {len(svg_files)} SVG"
        )
    for path in svg_files:
        text = path.read_text(encoding="utf-8")
        try:
            root = ET.fromstring(text)
        except ET.ParseError as error:
            failures.append(f"malformed SVG {path.name}: {error}")
            continue
        if "viewBox" not in root.attrib:
            failures.append(f"SVG lacks a viewBox: {path.name}")
        if re.search(r"\btransform\s*=", text) or "<g" in text:
            failures.append(f"example is not a baked transform-free SVG: {path.name}")
        if "<path" not in text:
            failures.append(f"SVG has no traced path: {path.name}")

    manifest_path = SITE / "assets" / "examples" / "manifest.json"
    if not manifest_path.is_file():
        failures.append("missing trace-example manifest")
    else:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        examples = manifest.get("examples", [])
        if manifest.get("schemaVersion") != 1 or manifest.get("engineVersion") != "0.1.0":
            failures.append("trace-example manifest version differs")
        if manifest.get("svgTransformMode") != "bake" or len(examples) != REQUIRED_EXAMPLES:
            failures.append("trace-example manifest mode or count differs")
        for example in examples:
            source_path = ROOT / example.get("source", "")
            raster_path = SITE / example.get("raster", "")
            svg_path = SITE / example.get("svg", "")
            for label, path, expected in (
                ("source", source_path, example.get("sourceSHA256")),
                ("raster", raster_path, example.get("rasterSHA256")),
                ("svg", svg_path, example.get("svgSHA256")),
            ):
                if not path.is_file() or sha256(path) != expected:
                    failures.append(f"{example.get('id', '<unknown>')} {label} hash differs")
            if source_path.is_file() and raster_path.is_file() and source_path.read_bytes() != raster_path.read_bytes():
                failures.append(f"{example.get('id', '<unknown>')} published raster differs from fixture")

    workflow = WORKFLOW.read_text(encoding="utf-8")
    for requirement in (
        "pages: write",
        "id-token: write",
        "actions/configure-pages@v5",
        "actions/upload-pages-artifact@v4",
        "actions/deploy-pages@v4",
        "python3 scripts/verify_website.py",
    ):
        if requirement not in workflow:
            failures.append(f"Pages workflow lacks {requirement}")

    if failures:
        print("website verification failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"verified GitHub Pages site with {parser.examples} trace examples")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
