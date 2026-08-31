#!/usr/bin/env python3
"""Tests for canvas-aligning baked site example SVGs."""

from __future__ import annotations

import unittest

from align_site_example_svgs import align_svg_text


class AlignSVGTextTests(unittest.TestCase):
    def test_expands_viewbox_and_translates_every_y_coordinate(self) -> None:
        source = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="10 20 30 40">'
            '<path d="M10 20 L20 30 C21 31 22 32 23 33 Z" '
            'fill="black" fill-rule="nonzero"/></svg>\n'
        )

        aligned = align_svg_text(source)

        self.assertIn('viewBox="0 0 1088 1088"', aligned)
        self.assertIn('d="M 10 1028 L 20 1038 C 21 1039 22 1040 23 1041 Z"', aligned)
        self.assertEqual(aligned.count('class="trace-handle"'), 2)
        self.assertEqual(aligned.count('class="trace-oncurve"'), 3)
        self.assertEqual(aligned.count('class="trace-offcurve"'), 2)
        self.assertIn('<line class="trace-handle" x1="20" y1="1038" x2="21" y2="1039"/>', aligned)
        self.assertIn('<line class="trace-handle" x1="22" y1="1040" x2="23" y2="1041"/>', aligned)
        self.assertIn('vector-effect:non-scaling-stroke', aligned)
        self.assertNotIn("<g", aligned)
        self.assertNotIn("transform=", aligned)

    def test_is_deterministic_for_an_already_centered_outline(self) -> None:
        source = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="274 240 540 608">'
            '<path d="M274 848 L350 848 L510 240 Z" '
            'fill="black" fill-rule="nonzero"/></svg>\n'
        )

        first = align_svg_text(source)
        second = align_svg_text(source)

        self.assertEqual(first, second)
        self.assertIn('d="M 274 848 L 350 848 L 510 240 Z"', first)

    def test_rejects_non_baked_or_unsupported_svg(self) -> None:
        transformed = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
            '<g transform="scale(1 -1)"><path d="M0 0 L1 1 Z"/></g></svg>'
        )
        quadratic = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
            '<path d="M0 0 Q1 1 2 2 Z"/></svg>'
        )

        with self.assertRaisesRegex(ValueError, "transform-free"):
            align_svg_text(transformed)
        with self.assertRaisesRegex(ValueError, "unsupported"):
            align_svg_text(quadratic)


if __name__ == "__main__":
    unittest.main()
