#!/usr/bin/env python3
"""Unit tests for the Milestone 6 viability decision."""

from __future__ import annotations

import unittest

from verify_viability import acceptance_gate, benchmark_gates, release_gate, viability_decision


class VerifyViabilityTests(unittest.TestCase):
    def test_benchmark_gates_separate_relative_absolute_and_memory(self) -> None:
        swift = {
            "fixtures": [
                {"id": "a", "medianMs": 90, "p95Ms": 120, "processP95Ms": 1_100, "peakRSSBytes": 20_000_000},
                {"id": "b", "medianMs": 180, "p95Ms": 240, "processP95Ms": 900, "peakRSSBytes": 21_000_000},
            ]
        }
        rust = {
            "fixtures": [
                {"id": "a", "medianMs": 100, "p95Ms": 100},
                {"id": "b", "medianMs": 200, "p95Ms": 200},
            ]
        }
        gates = benchmark_gates(swift, rust)
        self.assertEqual(gates[0]["status"], "pass")
        self.assertEqual(gates[1]["status"], "fail")
        self.assertEqual(gates[1]["details"]["passingFixtures"], 1)
        self.assertEqual(gates[2]["status"], "pass")

    def test_acceptance_requires_at_least_95_of_exactly_100(self) -> None:
        manifest = {"fixtures": [{"id": f"item-{index}"} for index in range(100)]}
        review = {
            "reviewer": "project-owner",
            "reviewStatus": "complete",
            "decisions": [
                {"id": f"item-{index}", "status": "accepted" if index < 95 else "rejected", "notes": ""}
                for index in range(100)
            ],
        }
        self.assertEqual(acceptance_gate(manifest, review)["status"], "pass")
        review["decisions"][94]["status"] = "rejected"
        self.assertEqual(acceptance_gate(manifest, review)["status"], "fail")

    def test_optical_acceptance_requires_a_recorded_note(self) -> None:
        manifest = {"fixtures": [{"id": f"item-{index}"} for index in range(100)]}
        review = {
            "reviewer": "project-owner",
            "reviewStatus": "complete",
            "decisions": [
                {"id": f"item-{index}", "status": "accepted", "notes": ""}
                for index in range(100)
            ],
        }
        review["decisions"][0]["status"] = "accepted-with-optical-notes"
        self.assertEqual(acceptance_gate(manifest, review)["status"], "fail")
        review["decisions"][0]["notes"] = "Minor optical adjustment may be useful."
        self.assertEqual(acceptance_gate(manifest, review)["status"], "pass")

    def test_release_requires_universal_signed_and_notarized_artifacts(self) -> None:
        manifest = {
            "architectures": ["arm64", "x86_64"],
            "artifacts": [
                {"path": "tool.zip", "signed": False, "notarized": False},
                {"path": "tool.pkg", "signed": False, "notarized": False},
            ],
        }
        self.assertEqual(release_gate(manifest)["status"], "fail")
        for artifact in manifest["artifacts"]:
            artifact["signed"] = True
            artifact["notarized"] = True
        self.assertEqual(release_gate(manifest)["status"], "pass")

    def test_any_nonpassing_required_gate_rejects_merge(self) -> None:
        self.assertEqual(
            viability_decision([{"required": True, "status": "pass"}]),
            "approve",
        )
        self.assertEqual(
            viability_decision([
                {"required": True, "status": "pass"},
                {"required": True, "status": "not-authorized"},
            ]),
            "reject",
        )


if __name__ == "__main__":
    unittest.main()
