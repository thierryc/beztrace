#!/usr/bin/env bash
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFERENCE="$ROOT/Tests/Fixtures/oracle/v1/reference.json"
WORK="$ROOT/test-work/img2bez-reference"
REVISION="23073ca08ecdac61ad0e838bfae49a590bc2c7cc"
TOOLCHAIN="${RUSTUP_TOOLCHAIN:-1.88.0}"
REFERENCE_UFO="${REFERENCE_UFO:-$ROOT/Tests/Fixtures/oracle/v1/reference-source/VirtuaGrotesk-Regular.ufo}"
REFERENCE_UFO_LICENSE="${REFERENCE_UFO_LICENSE:-OFL-1.1}"
REFERENCE_UFO_PROVENANCE="${REFERENCE_UFO_PROVENANCE:-https://github.com/eliheuer/virtua-grotesk commit 797c1065abd0c1318217b7c44aff3d61074f7280}"
REFERENCE_UFO_RECEIVED="${REFERENCE_UFO_RECEIVED:-2026-08-07}"
PATCH="$ROOT/Tests/Fixtures/oracle/v1/reference-patches/0001-stage-capture.patch"
ORACLE="$ROOT/Tests/Fixtures/oracle/v1"

rust_version="$(rustup run "$TOOLCHAIN" rustc --version 2>/dev/null || true)"
rust_minor="$(printf '%s' "$rust_version" | sed -E 's/^rustc 1\.([0-9]+).*/\1/')"
if [[ ! "$rust_minor" =~ ^[0-9]+$ ]] || (( rust_minor < 88 )); then
  echo "error: img2bez requires Rust 1.88 or later; toolchain '$TOOLCHAIN' yielded '$rust_version'" >&2
  exit 2
fi

if [[ -z "$REFERENCE_UFO" || ! -d "$REFERENCE_UFO" ]]; then
  echo "error: set REFERENCE_UFO to the audited hand-drawn UFO used by the img2bez baseline" >&2
  exit 4
fi
if [[ -z "$REFERENCE_UFO_LICENSE" || -z "$REFERENCE_UFO_PROVENANCE" || -z "$REFERENCE_UFO_RECEIVED" ]]; then
  echo "error: set REFERENCE_UFO_LICENSE, REFERENCE_UFO_PROVENANCE, and REFERENCE_UFO_RECEIVED" >&2
  exit 4
fi
python3 "$ROOT/scripts/check_reference_ufo.py" "$REFERENCE_UFO"

if [[ ! -e "$WORK/img2bez/.git" ]]; then
  mkdir -p "$WORK"
  git clone https://github.com/eliheuer/img2bez "$WORK/img2bez"
fi

git -C "$WORK/img2bez" fetch origin "$REVISION"
git -C "$WORK/img2bez" switch --detach "$REVISION"
actual="$(git -C "$WORK/img2bez" rev-parse HEAD)"
[[ "$actual" == "$REVISION" ]] || { echo "error: wrong img2bez revision" >&2; exit 3; }
if [[ -n "$(git -C "$WORK/img2bez" status --porcelain)" ]]; then
  echo "error: temporary img2bez checkout is not clean; move it aside and retry" >&2
  exit 3
fi

(
  cd "$WORK/img2bez"
  RUSTUP_TOOLCHAIN="$TOOLCHAIN" cargo test --locked --all-features
  git apply --check "$PATCH"
  git apply "$PATCH"
  # Capture is deliberately single-threaded so stage-file ordering is stable.
  RUSTUP_TOOLCHAIN="$TOOLCHAIN" cargo build --release --locked --no-default-features --features cli
)

ln -sfn "$REFERENCE_UFO" "$WORK/img2bez/eval-harness/reference.ufo"
glyph_file="$WORK/basic-latin-glyphs.txt"
python3 -c 'print("\n".join(list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") + "zero one two three four five six seven eight nine".split()))' > "$glyph_file"
(
  cd "$WORK/img2bez"
  RUSTUP_TOOLCHAIN="$TOOLCHAIN" \
  IMG2BEZ_SKIP_EVAL_HARNESS_PIP_INSTALL=1 \
  IMG2BEZ_BIN="$WORK/img2bez/target/release/img2bez" \
  GLYPH_FILE="$glyph_file" \
  RUN_LABEL=beztrace-basic-latin-v1 \
    ./eval-harness/run_structural_loop.sh
)

summary="$WORK/img2bez/eval-harness/runs/beztrace-basic-latin-v1/structural_summary.txt"
mean="$(awk '/mean_structural_score:/ {print $2}' "$summary")"
minimum="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["minimumMeanStructuralScore"])' "$REFERENCE")"
python3 - "$mean" "$minimum" <<'PY'
import sys
score, minimum = map(float, sys.argv[1:])
if score < minimum:
    raise SystemExit(f"error: structural mean {score:.3f} is below required {minimum:.3f}")
PY

capture_pass() {
  local destination="$1"
  local glyph code key image stage_dir
  mkdir -p "$destination/basic-latin"
  while IFS= read -r glyph; do
    code="$(python3 - "$glyph" <<'PY'
import sys
digits = {name: str(index) for index, name in enumerate("zero one two three four five six seven eight nine".split())}
character = digits.get(sys.argv[1], sys.argv[1])
print(f"{ord(character):04X}")
PY
)"
    key="uni$code"
    image="$WORK/img2bez/eval-harness/work/$key.png"
    if [[ ${#glyph} -gt 1 ]]; then
      image="$WORK/img2bez/eval-harness/work/$glyph.png"
    fi
    stage_dir="$destination/basic-latin/$key"
    mkdir -p "$stage_dir"
    BEZTRACE_CAPTURE_DIR="$stage_dir" BEZTRACE_CAPTURE_FIXTURE="$key" \
      "$WORK/img2bez/target/release/img2bez" --input "$image" \
      --output "$stage_dir/final.json" --name "$glyph" --unicode "$code" \
      --format json --profile clean --target-height 1088 --y-offset 0
    BEZTRACE_CAPTURE_DIR="$stage_dir" BEZTRACE_CAPTURE_FIXTURE="$key" \
      "$WORK/img2bez/target/release/img2bez" --input "$image" \
      --output "$stage_dir/final.svg" --name "$glyph" --unicode "$code" \
      --format svg --profile clean --target-height 1088 --y-offset 0
    python3 "$ROOT/scripts/finalize_stage_capture.py" "$stage_dir"
  done < "$glyph_file"
  cp "$summary" "$destination/structural-summary.txt"
}

first="$WORK/capture-a"
second="$WORK/capture-b"
[[ ! -e "$first" && ! -e "$second" ]] || {
  echo "error: capture work directories already exist; move them aside and retry" >&2
  exit 3
}
capture_pass "$first"
capture_pass "$second"
diff -qr "$first" "$second"
mkdir -p "$ORACLE/basic-latin"
cp -R "$first/basic-latin/." "$ORACLE/basic-latin/"
cp "$first/structural-summary.txt" "$ORACLE/structural-summary.txt"
mkdir -p "$ORACLE/structural"
cp -R "$WORK/img2bez/eval-harness/runs/beztrace-basic-latin-v1/." "$ORACLE/structural/"
python3 "$ROOT/scripts/sanitize_oracle_logs.py" "$ORACLE/structural" \
  --img2bez-work "$WORK/img2bez/eval-harness/work" \
  --reference-ufo "$REFERENCE_UFO"

intake="$WORK/reference-ufo-intake.json"
python3 "$ROOT/scripts/intake_reference_ufo.py" "$REFERENCE_UFO" \
  --license "$REFERENCE_UFO_LICENSE" --provenance "$REFERENCE_UFO_PROVENANCE" \
  --received "$REFERENCE_UFO_RECEIVED" > "$intake"
ufo_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["referenceUFOSHA256"])' "$intake")"
cp "$intake" "$ORACLE/reference-ufo-intake.json"
python3 - "$REFERENCE" "$ufo_sha" <<'PY'
import json, sys
path, ufo_hash = sys.argv[1:]
value = json.load(open(path, encoding="utf-8"))
value["captureStatus"] = "complete"
value.pop("captureBlocker", None)
value["referenceUFOSHA256"] = ufo_hash
open(path, "w", encoding="utf-8").write(json.dumps(value, indent=2) + "\n")
PY
python3 "$ROOT/scripts/build_oracle_manifest.py" "$ORACLE" \
  --reference-ufo-sha256 "$ufo_sha" --instrumentation-patch "$PATCH"
python3 "$ROOT/scripts/verify_oracle.py" "$ORACLE"

echo "reference metadata: $REFERENCE"
echo "validated Basic Latin report: $summary"
