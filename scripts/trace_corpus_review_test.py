#!/usr/bin/env python3
"""Unit tests for the complete-corpus human trace review."""

from __future__ import annotations

import unittest

from trace_corpus_review import acceptance_template, render_review_page


class TraceCorpusReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.records = [
            {
                "id": "glyph-upper-d",
                "category": "glyph",
                "sourceKind": "deterministic",
                "source": "/tmp/glyph-upper-d.png",
                "contourCount": 2,
                "nodeCount": 18,
                "contours": [
                    {"index": 1, "role": "outer", "jsonWinding": "counterclockwise", "svgWinding": "clockwise"},
                    {"index": 2, "role": "counter", "jsonWinding": "clockwise", "svgWinding": "counterclockwise"},
                ],
            }
        ]

    def test_acceptance_template_is_pending_and_bound_to_manifest(self) -> None:
        document = acceptance_template(self.records, "a" * 64)
        self.assertEqual(document["schemaVersion"], 1)
        self.assertEqual(document["reviewStatus"], "in-progress")
        self.assertEqual(document["corpusManifestSHA256"], "a" * 64)
        self.assertEqual(
            document["decisions"],
            [{"id": "glyph-upper-d", "status": "pending", "notes": ""}],
        )

    def test_review_page_renders_four_views_and_review_export(self) -> None:
        page = render_review_page(self.records, "a" * 64)
        self.assertIn("Baked SVG render", page)
        self.assertIn("Preserve SVG render", page)
        self.assertIn("Nodes, handles, and direction", page)
        self.assertIn("Accept", page)
        self.assertIn("Optical note", page)
        self.assertIn("Reject", page)
        self.assertIn("Export review JSON", page)
        self.assertIn('"corpusManifestSHA256":"' + "a" * 64, page)


if __name__ == "__main__":
    unittest.main()
