#!/bin/bash
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.1.0"
CANDIDATE="rc.1"
PACKAGE_ID="dev.beztrace.cli"
APP_IDENTITY="${BEZTRACE_APPLICATION_IDENTITY:-}"
INSTALLER_IDENTITY="${BEZTRACE_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${BEZTRACE_NOTARY_PROFILE:-beztrace-notary}"
NOTARIZE=0
RELEASE_KIND="candidate"

usage() {
    echo "usage: BEZTRACE_EXTERNAL_WORK=/Volumes/T9/beztrace/milestone-5 $0 [--final] [--notarize]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --final) RELEASE_KIND="final" ;;
        --notarize) NOTARIZE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [ "$RELEASE_KIND" = "final" ]; then
    WORK="${BEZTRACE_EXTERNAL_WORK:-/Volumes/T9/beztrace/milestone-7}"
    LABEL="$VERSION"
    case "$WORK" in
        /Volumes/T9/beztrace/milestone-7|/private/tmp/beztrace-milestone-7-*) ;;
        *) echo "refusing final release work outside the approved Milestone 7 roots: $WORK" >&2; exit 2 ;;
    esac
else
    WORK="${BEZTRACE_EXTERNAL_WORK:-/Volumes/T9/beztrace/milestone-5}"
    LABEL="$VERSION-$CANDIDATE"
    case "$WORK" in
        /Volumes/T9/beztrace/milestone-5|/private/tmp/beztrace-milestone-5-*) ;;
        *) echo "refusing candidate work outside the approved Milestone 5 roots: $WORK" >&2; exit 2 ;;
    esac
fi
RELEASE="$WORK/release"
ARM_BUILD="$WORK/tmp/release-arm64"
INTEL_BUILD="$WORK/tmp/release-x86_64"
STAGING="$RELEASE/beztrace-$LABEL-stage"
ROOT_PAYLOAD="$STAGING/root"
SHARE="$ROOT_PAYLOAD/Library/Application Support/beztrace/share"
BIN_DIR="$ROOT_PAYLOAD/Library/Application Support/beztrace/bin"
ZIP="$RELEASE/beztrace-$LABEL-macos-universal.zip"
UNSIGNED_PKG="$RELEASE/beztrace-$LABEL-unsigned.pkg"
PKG="$RELEASE/beztrace-$LABEL.pkg"

mkdir -p "$RELEASE" "$WORK/tmp"
rm -rf "$ARM_BUILD" "$INTEL_BUILD" "$STAGING"
mkdir -p "$BIN_DIR" "$SHARE" "$ROOT_PAYLOAD/usr/local/bin"

swift build --package-path "$ROOT" --configuration release --product beztrace \
    --triple arm64-apple-macosx13.0 --scratch-path "$ARM_BUILD"
swift build --package-path "$ROOT" --configuration release --product beztrace \
    --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_BUILD"

ARM_BINARY="$(find "$ARM_BUILD" -type f -path '*/release/beztrace' -perm -111 | head -1)"
INTEL_BINARY="$(find "$INTEL_BUILD" -type f -path '*/release/beztrace' -perm -111 | head -1)"
test -n "$ARM_BINARY"
test -n "$INTEL_BINARY"
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$BIN_DIR/beztrace"
test "$(lipo -archs "$BIN_DIR/beztrace")" = "x86_64 arm64" || \
    test "$(lipo -archs "$BIN_DIR/beztrace")" = "arm64 x86_64"

if [ -n "$APP_IDENTITY" ]; then
    codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp "$BIN_DIR/beztrace"
    codesign --verify --strict --verbose=2 "$BIN_DIR/beztrace"
fi

cp "$ROOT/LICENSE-APACHE" "$ROOT/LICENSE-MIT" "$ROOT/THIRD_PARTY_NOTICES" \
    "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$SHARE/"
cp "$ROOT/Schemas/trace-result-v1.schema.json" "$SHARE/"
python3 "$ROOT/scripts/generate_sbom.py" --binary "$BIN_DIR/beztrace" \
    --output-dir "$SHARE" --release-kind "$RELEASE_KIND"
if [ "$RELEASE_KIND" = "final" ]; then
    cp "$SHARE/sbom-source.spdx.json" "$RELEASE/beztrace-$LABEL-source.spdx.json"
    cp "$SHARE/sbom-binary.spdx.json" "$RELEASE/beztrace-$LABEL-binary.spdx.json"
    cp "$ROOT/Schemas/release-manifest-v1.schema.json" "$SHARE/"
fi
ln -s "/Library/Application Support/beztrace/bin/beztrace" "$ROOT_PAYLOAD/usr/local/bin/beztrace"

find "$ROOT_PAYLOAD" -type f -exec touch -t 202608260000 {} +
find "$ROOT_PAYLOAD" -type d -exec touch -t 202608260000 {} +
find "$ROOT_PAYLOAD" -type f -exec shasum -a 256 {} + | LC_ALL=C sort -k2 > "$STAGING/payload-SHA256SUMS"

rm -f "$ZIP" "$UNSIGNED_PKG" "$PKG"
(cd "$ROOT_PAYLOAD/Library/Application Support" && ditto -c -k --keepParent beztrace "$ZIP")
pkgbuild --root "$ROOT_PAYLOAD" --identifier "$PACKAGE_ID" --version "$VERSION" \
    --install-location / --scripts "$ROOT/release/package-scripts" "$UNSIGNED_PKG"
if [ -n "$INSTALLER_IDENTITY" ]; then
    productbuild --package "$UNSIGNED_PKG" --sign "$INSTALLER_IDENTITY" "$PKG"
else
    cp "$UNSIGNED_PKG" "$PKG"
fi

CHECKSUM_FILES=("$(basename "$ZIP")" "$(basename "$PKG")")
if [ "$RELEASE_KIND" = "final" ]; then
    CHECKSUM_FILES+=("beztrace-$LABEL-source.spdx.json" "beztrace-$LABEL-binary.spdx.json")
fi
(
    cd "$RELEASE"
    shasum -a 256 "${CHECKSUM_FILES[@]}" > SHA256SUMS
)
MANIFEST_ARGS=(--release "$RELEASE" --release-kind "$RELEASE_KIND")
if [ -n "$APP_IDENTITY" ]; then MANIFEST_ARGS+=(--signed-binary); fi
if [ -n "$INSTALLER_IDENTITY" ]; then MANIFEST_ARGS+=(--signed-package); fi
python3 "$ROOT/scripts/build_release_manifest.py" "${MANIFEST_ARGS[@]}"
VERIFY_ARGS=(--release "$RELEASE" --release-kind "$RELEASE_KIND")
if [ -n "$APP_IDENTITY" ]; then VERIFY_ARGS+=(--require-signed-binary); fi
if [ -n "$INSTALLER_IDENTITY" ]; then VERIFY_ARGS+=(--require-signed-package); fi
python3 "$ROOT/scripts/verify_release_candidate.py" "${VERIFY_ARGS[@]}"

if [ "$NOTARIZE" -eq 1 ]; then
    test -n "$APP_IDENTITY" || { echo "BEZTRACE_APPLICATION_IDENTITY is required" >&2; exit 1; }
    test -n "$INSTALLER_IDENTITY" || { echo "BEZTRACE_INSTALLER_IDENTITY is required" >&2; exit 1; }
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PKG"
    xcrun stapler validate "$PKG"
    (
        cd "$RELEASE"
        shasum -a 256 "${CHECKSUM_FILES[@]}" > SHA256SUMS
    )
    python3 "$ROOT/scripts/build_release_manifest.py" \
        --release "$RELEASE" --release-kind "$RELEASE_KIND" \
        --signed-binary --signed-package --notarized
    python3 "$ROOT/scripts/verify_release_candidate.py" --release "$RELEASE" \
        --release-kind "$RELEASE_KIND" \
        --require-signed-binary --require-signed-package
fi

echo "$RELEASE_KIND release staged at $RELEASE"
