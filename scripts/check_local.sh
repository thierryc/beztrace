#!/bin/bash
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Run the former hosted checks locally. Never installs or publishes anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTPUT="${1:-.build/local-checks}"
if [ -e "$OUTPUT" ]; then echo "Choose a new results directory: $OUTPUT" >&2; exit 2; fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
run_check() {
    local name="$1"; shift
    echo "Checking $name..."
    if "$@" > "$OUTPUT/$name.log" 2>&1; then
        echo "Passed $name"
    else
        tail -n 40 "$OUTPUT/$name.log" >&2
        echo "Failed $name; see $OUTPUT/$name.log" >&2
        return 1
    fi
}
run_check dependencies python3 -c 'import PIL, jsonschema'
ASAN_ARGS=()
if [ -n "${BEZTRACE_ASAN_DEVELOPER_DIRECTORY:-}" ]; then
    ASAN_ARGS+=(--asan-developer-directory "$BEZTRACE_ASAN_DEVELOPER_DIRECTORY")
fi
run_check source-tests python3 scripts/run_viability_tests.py --source-only \
    --output "$OUTPUT/test-evidence.json" "${ASAN_ARGS[@]}"
run_check website-examples python3 scripts/align_site_example_svgs_test.py
run_check website-assets python3 scripts/align_site_example_svgs.py
run_check universal-engine python3 scripts/build_development_engine.py --output "$OUTPUT/universal-engine"
if [ -f scripts/qualify_pair_matching.py ]; then
    run_check pair-native python3 scripts/qualify_pair_matching.py \
        --engine "$OUTPUT/universal-engine/bin/beztrace" --output "$OUTPUT/pair-native"
    if [ "$(uname -m)" = arm64 ]; then
        run_check pair-x86_64 python3 scripts/qualify_pair_matching.py \
            --engine "$OUTPUT/universal-engine/bin/beztrace" --architecture x86_64 --output "$OUTPUT/pair-x86_64"
        run_check pair-comparison python3 scripts/compare_pair_architectures.py \
            --arm64 "$OUTPUT/pair-native" --x86-64 "$OUTPUT/pair-x86_64" --output "$OUTPUT/pair-comparison.json"
    fi
fi
mkdir -p "$OUTPUT/companion-stable-source"
git archive v0.1.1 | tar -x -C "$OUTPUT/companion-stable-source"
run_check companion-engine swift build --package-path "$OUTPUT/companion-stable-source" \
    --configuration release --product beztrace
run_check companion-tests env BEZTRACE_TEST_ENGINE="$OUTPUT/companion-stable-source/.build/release/beztrace" \
    python3 -m unittest discover -s Companions/Glyphs/tests -v
run_check companion-package python3 Companions/Glyphs/scripts/package.py --output "$OUTPUT/glyphs-companion"
run_check companion-verification python3 Companions/Glyphs/scripts/verify_package.py "$OUTPUT/glyphs-companion"
run_check source-preservation git diff --exit-code
printf 'All local checks passed. Results: %s\n' "$OUTPUT"
