#!/usr/bin/env python3
"""Unit tests for installed-package evidence validation."""

from __future__ import annotations

import unittest

from verify_installed_package import validate_record


class VerifyInstalledPackageTests(unittest.TestCase):
    def test_accepts_matching_notarized_installation(self) -> None:
        record = {
            "packageID": "dev.beztrace.cli",
            "version": "0.1.0",
            "receiptPresent": True,
            "symlinkTarget": "/Library/Application Support/beztrace/bin/beztrace",
            "architectures": ["arm64", "x86_64"],
            "binarySignatureValid": True,
            "packageSignatureValid": True,
            "notarizationTrusted": True,
            "stapleValid": True,
            "gatekeeperAccepted": True,
            "installedBinarySHA256": "a" * 64,
            "packagedBinarySHA256": "a" * 64,
            "versionOutput": "beztrace 0.1.0",
            "jsonTraceValid": True,
            "svgTraceValid": True,
        }
        self.assertEqual(validate_record(record), [])

    def test_rejects_hash_mismatch_and_missing_notarization(self) -> None:
        record = {
            "packageID": "dev.beztrace.cli",
            "version": "0.1.0",
            "receiptPresent": True,
            "symlinkTarget": "/Library/Application Support/beztrace/bin/beztrace",
            "architectures": ["arm64", "x86_64"],
            "binarySignatureValid": True,
            "packageSignatureValid": True,
            "notarizationTrusted": False,
            "stapleValid": True,
            "gatekeeperAccepted": True,
            "installedBinarySHA256": "a" * 64,
            "packagedBinarySHA256": "b" * 64,
            "versionOutput": "beztrace 0.1.0",
            "jsonTraceValid": True,
            "svgTraceValid": True,
        }
        failures = validate_record(record)
        self.assertTrue(any("notarization" in item for item in failures))
        self.assertTrue(any("hash" in item for item in failures))


if __name__ == "__main__":
    unittest.main()
