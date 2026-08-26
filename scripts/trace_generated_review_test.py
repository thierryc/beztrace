#!/usr/bin/env python3
"""Unit tests for the generated SVG rendering report."""

from __future__ import annotations

import unittest

from trace_generated_review import contour_directions, inspection_svg, render_page


def sample_trace() -> dict:
    return {
        "bounds": [0, 0, 10, 10],
        "paths": [
            {
                "closed": True,
                "nodes": [
                    {"x": 0, "y": 0, "type": "line", "smooth": False},
                    {"x": 10, "y": 0, "type": "line", "smooth": False},
                    {"x": 10, "y": 10, "type": "line", "smooth": False},
                    {"x": 0, "y": 10, "type": "line", "smooth": False},
                ],
            },
            {
                "closed": True,
                "nodes": [
                    {"x": 3, "y": 3, "type": "line", "smooth": False},
                    {"x": 3, "y": 7, "type": "line", "smooth": False},
                    {"x": 7, "y": 7, "type": "line", "smooth": False},
                    {"x": 7, "y": 3, "type": "line", "smooth": False},
                ],
            },
        ],
    }


class TraceGeneratedReviewTests(unittest.TestCase):
    def test_contour_directions_report_y_up_and_baked_winding(self) -> None:
        self.assertEqual(
            contour_directions(sample_trace()),
            [
                {
                    "index": 1,
                    "role": "outer",
                    "jsonWinding": "counterclockwise",
                    "svgWinding": "clockwise",
                },
                {
                    "index": 2,
                    "role": "counter",
                    "jsonWinding": "clockwise",
                    "svgWinding": "counterclockwise",
                },
            ],
        )

    def test_inspection_svg_shows_direction_arrows_and_accessible_labels(self) -> None:
        document = inspection_svg(sample_trace())
        self.assertIn('id="direction-arrow"', document)
        self.assertEqual(document.count('class="direction"'), 2)
        self.assertNotIn("transform=", document)
        self.assertIn('viewBox="-64 -64 138 138"', document)
        self.assertIn('<path d="M 0 10 L 10 10 L 10 0 L 0 0 L 0 10 Z"/>', document)
        self.assertIn("Contour 1: outer; JSON Y-up counterclockwise; baked SVG clockwise", document)
        self.assertIn("Contour 2: counter; JSON Y-up clockwise; baked SVG counterclockwise", document)

    def test_render_page_compares_both_svg_modes_and_direction_overlay(self) -> None:
        record = {
            "id": "glyph-upper-d",
            "candidate": 1,
            "source": "/tmp/glyph-upper-d.png",
            "contourCount": 2,
            "nodeCount": 18,
            "contours": contour_directions(sample_trace()),
        }
        page = render_page([record])
        self.assertIn("Baked SVG render", page)
        self.assertIn("Preserve SVG render", page)
        self.assertIn("Nodes, handles, and direction", page)
        self.assertIn("svg/glyph-upper-d.svg", page)
        self.assertIn("svg-preserve/glyph-upper-d.svg", page)
        self.assertIn("Y-up CCW → baked CW", page)
        self.assertIn("Y-up CW → baked CCW", page)


if __name__ == "__main__":
    unittest.main()
