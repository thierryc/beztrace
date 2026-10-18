#!/usr/bin/env python3
"""Unit tests for installed-package evidence validation."""

from __future__ import annotations

import unittest

from verify_installed_package import validate_record, notarization_trusted


class VerifyInstalledPackageTests(unittest.TestCase):
    def test_trust_requires_notarized_assessment_when_pkgutil_omits_it(self) -> None:
        signature = "Status: signed by a developer certificate issued by Apple for distribution"
        self.assertTrue(notarization_trusted(True, signature, True, "accepted\nsource=Notarized Developer ID"))
        self.assertFalse(notarization_trusted(True, signature, True, "accepted\nsource=Developer ID"))
        self.assertFalse(notarization_trusted(True, signature, False, "source=Notarized Developer ID"))
        self.assertFalse(notarization_trusted(False, signature, True, "source=Notarized Developer ID"))

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
        record["version"] = "0.1.1"
        record["versionOutput"] = "beztrace 0.1.1"
        self.assertEqual(validate_record(record, "0.1.1"), [])
        self.assertTrue(validate_record(record, "0.1.0"))
        record["versionOutput"] = "beztrace 0.1.0"
        self.assertTrue(validate_record(record, "0.1.1"))

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
