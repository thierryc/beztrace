#!/usr/bin/env python3
"""Unit tests for construction of the Milestone 6 test matrix."""

from __future__ import annotations

import unittest

from run_viability_tests import asan_command


class RunViabilityTestsTests(unittest.TestCase):
    def test_asan_command_uses_the_explicit_swift_toolchain(self) -> None:
        swift = "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/test-swift"
        command = asan_command(swift)
        self.assertEqual(command[0], swift)
        self.assertIn("--sanitize=address", command)
        self.assertEqual(command[-2:], ["--filter", "MalformedCorpusTests"])


if __name__ == "__main__":
    unittest.main()
