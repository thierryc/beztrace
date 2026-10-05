#!/usr/bin/env python3
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Tests for candidate and final beztrace release metadata."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ReleaseMetadataTests(unittest.TestCase):
    def test_packaged_installer_identifies_product_and_contains_welcome(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / "payload"
            payload.mkdir()
            (payload / "test.txt").write_text("installer metadata fixture")
            component = root / "component.pkg"
            distribution = root / "Distribution.xml"
            resources = root / "resources"
            product = root / "product.pkg"
            commands = [
                ["pkgbuild", "--root", str(payload), "--identifier", "dev.beztrace.cli",
                 "--version", "0.1.1", str(component)],
                ["productbuild", "--synthesize", "--package", str(component), str(distribution)],
                ["python3", str(ROOT / "scripts/configure_installer.py"),
                 "--distribution", str(distribution), "--resources", str(resources),
                 "--version", "0.1.1"],
                ["productbuild", "--distribution", str(distribution), "--resources", str(resources),
                 "--package-path", str(root), str(product)],
                ["pkgutil", "--expand", str(product), str(root / "expanded")],
            ]
            for command in commands:
                subprocess.run(command, check=True, capture_output=True)
            expanded = root / "expanded"
            xml = ET.parse(expanded / "Distribution").getroot()
            self.assertEqual(xml.findtext("title"), "Beztrace 0.1.1")
            for tag in ("welcome", "conclusion"):
                reference = xml.find(tag)
                self.assertIsNotNone(reference)
                resource = expanded / "Resources" / reference.get("file")
                self.assertIn("Beztrace 0.1.1", resource.read_text())
            package = xml.find("pkg-ref[@version='0.1.1']")
            self.assertEqual(package.get("id"), "dev.beztrace.cli")

    def test_development_sbom_requires_and_records_explicit_prerelease_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "beztrace"
            binary.write_bytes(b"development-binary")
            command = ["python3", str(ROOT / "scripts/generate_sbom.py"), "--binary", str(binary),
                       "--output-dir", str(root / "share"), "--release-kind", "development"]
            for suffix in [[], ["--version", "0.1.1"], ["--version", "bad"]]:
                result = subprocess.run(command + suffix, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
            subprocess.run(command + ["--version", "0.1.1-dev.4"], check=True, capture_output=True)
            for name in ("source", "binary"):
                data = json.loads((root / "share" / f"sbom-{name}.spdx.json").read_text())
                self.assertEqual(data["packages"][0]["versionInfo"], "0.1.1-dev.4")
                self.assertIn("/0.1.1-dev.4/", data["documentNamespace"])

    def build_manifest(self, release_kind: str, version: str = "0.1.0") -> dict:
        label = f"{version}-rc.1" if release_kind == "candidate" else version
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            (release / f"beztrace-{label}-macos-universal.zip").write_bytes(b"zip")
            (release / f"beztrace-{label}.pkg").write_bytes(b"pkg")
            subprocess.run(
                [
                    "python3",
                    str(ROOT / "scripts" / "build_release_manifest.py"),
                    "--release",
                    str(release),
                    "--release-kind",
                    release_kind,
                    "--version",
                    version,
                    "--signed-binary",
                    "--signed-package",
                    "--notarized",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            return json.loads((release / "release-manifest.json").read_text(encoding="utf-8"))

    def test_candidate_manifest_remains_backward_compatible(self) -> None:
        manifest = self.build_manifest("candidate")
        self.assertEqual(manifest["version"], "0.1.0")
        self.assertEqual(manifest["candidate"], "rc.1")
        self.assertEqual(
            [artifact["path"] for artifact in manifest["artifacts"]],
            ["beztrace-0.1.0-rc.1-macos-universal.zip", "beztrace-0.1.0-rc.1.pkg"],
        )
        self.assertIn("beztrace-0.1.0-rc.1-stage", manifest["sbom"]["source"])

    def test_final_manifest_uses_release_names_and_omits_candidate(self) -> None:
        manifest = self.build_manifest("final")
        self.assertEqual(manifest["version"], "0.1.0")
        self.assertNotIn("candidate", manifest)
        expected_revision = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.assertEqual(manifest["sourceRevision"], expected_revision)
        self.assertEqual(
            [artifact["path"] for artifact in manifest["artifacts"]],
            ["beztrace-0.1.0-macos-universal.zip", "beztrace-0.1.0.pkg"],
        )
        self.assertIn("beztrace-0.1.0-stage", manifest["sbom"]["source"])
        self.assertEqual(manifest["sbom"]["releaseSource"], "beztrace-0.1.0-source.spdx.json")
        self.assertEqual(manifest["sbom"]["releaseBinary"], "beztrace-0.1.0-binary.spdx.json")
        self.assertTrue(all(artifact["signed"] for artifact in manifest["artifacts"]))
        self.assertTrue(all(artifact["notarized"] for artifact in manifest["artifacts"]))

    def test_final_sboms_use_final_version_namespace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "beztrace"
            output = root / "share"
            binary.write_bytes(b"universal-binary-placeholder")
            subprocess.run(
                [
                    "python3",
                    str(ROOT / "scripts" / "generate_sbom.py"),
                    "--binary",
                    str(binary),
                    "--output-dir",
                    str(output),
                    "--release-kind",
                    "final",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            source = json.loads((output / "sbom-source.spdx.json").read_text(encoding="utf-8"))
            packaged = json.loads((output / "sbom-binary.spdx.json").read_text(encoding="utf-8"))
            self.assertEqual(source["packages"][0]["versionInfo"], "0.1.0")
            self.assertEqual(packaged["packages"][0]["versionInfo"], "0.1.0")
            self.assertIn("/0.1.0/", source["documentNamespace"])
            self.assertNotIn("rc.1", source["documentNamespace"])

    def test_new_stable_release_records_version_and_artifact_names(self) -> None:
        manifest = self.build_manifest("final", "0.1.1")
        self.assertEqual(manifest["version"], "0.1.1")
        self.assertEqual(manifest["artifacts"][0]["path"], "beztrace-0.1.1-macos-universal.zip")
        self.assertEqual(manifest["sbom"]["releaseBinary"], "beztrace-0.1.1-binary.spdx.json")
        self.assertNotIn("candidate", manifest)

    def test_stable_sbom_rejects_prerelease_and_uses_explicit_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "beztrace"
            binary.write_bytes(b"signed-universal-placeholder")
            command = ["python3", str(ROOT / "scripts/generate_sbom.py"), "--binary", str(binary),
                       "--output-dir", str(root / "share"), "--release-kind", "final", "--version"]
            for version in ("bad", "0.1.1-dev.4", "../0.1.1"):
                self.assertNotEqual(subprocess.run(command + [version], capture_output=True).returncode, 0)
            subprocess.run(command + ["0.1.1"], check=True, capture_output=True)
            for name in ("source", "binary"):
                sbom = json.loads((root / "share" / f"sbom-{name}.spdx.json").read_text())
                self.assertEqual(sbom["packages"][0]["versionInfo"], "0.1.1")
                self.assertIn("/0.1.1/", sbom["documentNamespace"])


if __name__ == "__main__":
    unittest.main()
