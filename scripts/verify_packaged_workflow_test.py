#!/usr/bin/env python3
"""Unit tests for packaged standalone workflow validation."""

from __future__ import annotations

import unittest

from verify_packaged_workflow import validate_outputs


class VerifyPackagedWorkflowTests(unittest.TestCase):
    def test_accepts_closed_json_and_transform_free_svg(self) -> None:
        result = {
            "schemaVersion": 1,
            "pathDataVersion": 2,
            "source": {"sha256": "a" * 64},
            "paths": [{"closed": True, "nodes": [{"x": 0, "y": 0, "type": "line", "smooth": False}]}],
        }
        self.assertEqual(validate_outputs(result, '<svg><path d="M0 0Z"/></svg>', "a" * 64), [])

    def test_rejects_open_geometry_and_svg_transform(self) -> None:
        result = {
            "schemaVersion": 1,
            "pathDataVersion": 2,
            "source": {"sha256": "b" * 64},
            "paths": [{"closed": False, "nodes": []}],
        }
        failures = validate_outputs(result, '<svg><g transform="scale(1 -1)"></g></svg>', "a" * 64)
        self.assertTrue(any("hash" in item for item in failures))
        self.assertTrue(any("closed" in item for item in failures))
        self.assertTrue(any("transform" in item for item in failures))


if __name__ == "__main__":
    unittest.main()
