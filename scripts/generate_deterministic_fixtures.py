#!/usr/bin/env python3
"""Generate the deterministic half of the beztrace acceptance corpus."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"
NOTO = FIXTURES / "sources" / "noto-sans" / "NotoSans[wdth,wght].ttf"
MATERIAL = (
    FIXTURES
    / "sources"
    / "material-symbols"
    / "MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf"
)
CODEPOINTS = (
    FIXTURES
    / "sources"
    / "material-symbols"
    / "MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].codepoints"
)

GLYPHS = {
    "glyph-upper-a": "A",
    "glyph-upper-b": "B",
    "glyph-upper-o": "O",
    "glyph-upper-q": "Q",
    "glyph-lower-a": "a",
    "glyph-lower-g": "g",
    "glyph-lower-n": "n",
    "glyph-8": "8",
}

SYMBOLS = {
    "symbol-star": "star",
    "symbol-heart": "favorite",
    "symbol-right-arrow": "arrow_forward",
    "symbol-check": "check",
}


def centered_render(
    text: str,
    font: ImageFont.FreeTypeFont,
    output: Path,
    *,
    close_overlap_seams: bool = False,
) -> None:
    image = Image.new("L", (1024, 1024), 255)
    draw = ImageDraw.Draw(image)
    box = draw.textbbox((0, 0), text, font=font)
    width = box[2] - box[0]
    height = box[3] - box[1]
    x = (1024 - width) / 2 - box[0]
    y = (1024 - height) / 2 - box[1]
    draw.text((x, y), text, font=font, fill=0)
    if close_overlap_seams:
        # Some composite Material Symbols expose hairline seams where filled
        # component outlines overlap in FreeType. Expanding dark coverage by
        # two pixels removes those rasterizer artifacts without changing the
        # source silhouette at beztrace's intended scale.
        image = image.filter(ImageFilter.MinFilter(5))
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="PNG", optimize=False)


def load_codepoints() -> dict[str, int]:
    values: dict[str, int] = {}
    for line in CODEPOINTS.read_text(encoding="utf-8").splitlines():
        name, value = line.split()
        values[name] = int(value, 16)
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if output would change")
    args = parser.parse_args()

    glyph_font = ImageFont.truetype(str(NOTO), 800)
    symbol_font = ImageFont.truetype(str(MATERIAL), 760)
    try:
        symbol_font.set_variation_by_axes([1, 0, 48, 500])
    except (AttributeError, OSError):
        pass
    codepoints = load_codepoints()

    temporary: list[tuple[Path, Path]] = []
    for fixture_id, character in GLYPHS.items():
        output = FIXTURES / "corpus" / "deterministic" / "glyphs" / f"{fixture_id}.png"
        candidate = output.with_suffix(".candidate.png") if args.check else output
        centered_render(character, glyph_font, candidate)
        temporary.append((candidate, output))
    for fixture_id, symbol_name in SYMBOLS.items():
        output = FIXTURES / "corpus" / "deterministic" / "symbols" / f"{fixture_id}.png"
        candidate = output.with_suffix(".candidate.png") if args.check else output
        centered_render(
            chr(codepoints[symbol_name]),
            symbol_font,
            candidate,
            close_overlap_seams=True,
        )
        temporary.append((candidate, output))

    changed = []
    if args.check:
        for candidate, output in temporary:
            if not output.exists() or candidate.read_bytes() != output.read_bytes():
                changed.append(str(output.relative_to(ROOT)))
            candidate.unlink()
    if changed:
        print("deterministic fixtures differ:\n" + "\n".join(changed))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
