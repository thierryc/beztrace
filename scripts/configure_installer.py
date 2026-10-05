#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Add product identity to a synthesized macOS Installer distribution."""

from __future__ import annotations

import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

from release_version import stable_version


def configure(distribution: Path, resources: Path, version: str) -> None:
    tree = ET.parse(distribution)
    root = tree.getroot()
    if root.tag != "installer-gui-script":
        raise ValueError("expected a synthesized Installer distribution")
    resources.mkdir(parents=True, exist_ok=True)
    for tag in ("title", "welcome", "conclusion"):
        for element in root.findall(tag):
            root.remove(element)
    title = ET.Element("title")
    title.text = f"Beztrace {version}"
    root.insert(0, title)
    for index, (tag, heading, text) in enumerate((
        ("welcome", f"Welcome to Beztrace {version}",
         "Turn clean raster glyphs and symbols into editable Bézier outlines. "
         "This installer adds the standalone Beztrace command-line engine for "
         "macOS 13 or later on Apple Silicon and Intel Macs."),
        ("conclusion", f"Beztrace {version} is installed",
         "Beztrace is ready to use from Terminal and compatible tracing tools. "
         "Run <code>beztrace --version</code> to check your installation."),
    ), 1):
        name = f"{tag.capitalize()}.html"
        root.insert(index, ET.Element(tag, {"file": name, "mime-type": "text/html"}))
        (resources / name).write_text(
            '<!doctype html><html><head><meta charset="utf-8">'
            '<style>body{font:13px -apple-system,sans-serif;color:#222;}'
            'h1{font-size:20px;font-weight:600;}p{line-height:1.5;}'
            '</style></head><body>'
            f'<h1>{heading}</h1><p>{text}</p></body></html>\n',
            encoding="utf-8",
        )
    for choice in root.findall("choice"):
        if choice.get("id") == "dev.beztrace.cli":
            choice.set("title", "Beztrace command-line engine")
    ET.indent(tree, space="    ")
    tree.write(distribution, encoding="utf-8", xml_declaration=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--distribution", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--version", type=stable_version, required=True)
    args = parser.parse_args()
    configure(args.distribution, args.resources, args.version)


if __name__ == "__main__":
    main()
