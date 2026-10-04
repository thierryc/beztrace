# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Shared version validation for distribution tooling."""

import argparse
import re
from pathlib import Path


def stable_version(value: str) -> str:
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", value):
        raise argparse.ArgumentTypeError("expected stable MAJOR.MINOR.PATCH")
    return value


def engine_version() -> str:
    source = Path(__file__).resolve().parents[1] / "Sources/BezierTraceCore/BezierTracer.swift"
    return re.search(r'public static let engine = "([^"]+)"', source.read_text()).group(1)
