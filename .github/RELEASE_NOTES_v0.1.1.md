beztrace 0.1.1 is the stable macOS tracing engine for clean raster glyphs and symbols.

This release preserves small closed contours and their meaningful curvature,
prevents unsafe handle rounding, and keeps valid no-grid geometry when Grid
snapping would collapse or self-intersect a contour. Closed output has at least
three on-curve nodes. JSON schema v1, pathDataVersion 2 and the public Swift API
remain compatible with 0.1.0.

Supports macOS 13+ on Apple Silicon and Intel. The universal executable and
installer are Developer ID signed and Apple notarized.

Download the PKG and SHA256SUMS, verify checksums, then install:

```sh
shasum -a 256 -c SHA256SUMS
pkgutil --check-signature beztrace-0.1.1.pkg
xcrun stapler validate beztrace-0.1.1.pkg
sudo installer -pkg beztrace-0.1.1.pkg -target /
beztrace --version
```

For portable use, extract the universal ZIP and run `beztrace/bin/beztrace`.
Source and binary SPDX SBOMs and the source-bound release manifest accompany
the distribution.

The optional Glyphs companion remains separately qualified development software
and is not included. Source build 12 accepts engine 0.1.1; older installed builds
require a supported earlier engine or a separate companion upgrade.

[Release verification](https://github.com/thierryc/beztrace/blob/main/docs/RELEASE.md)

Source tag commit: `9737f21fabfda0dc9e6728bd34df2f83380238e9`. Engine code and schemas match qualified source `7e43a0b48fec0634e9393f9f33d2d5cc260ced39`. Later changes add installer product identity and bind CLI tests to their own build rather than preserved development artifacts. The rebuilt stable engine also includes the minimum-node cleanup follow-up beyond the older packaged dev.4.

SHA-256 values (including the checksum file):

```text
75546a8530e0bf6f2ef4a849b298312522f21a4c6cf4c5a706c2f1448a4b8682  beztrace-0.1.1-macos-universal.zip
560d72540ab1013c444105ac45abea1780229145de4e174e7cfd0072d9a81975  beztrace-0.1.1.pkg
a89ef12ba5040affec821905a7aa1e812783271af3adb8528e241b3bb0272a5e  beztrace-0.1.1-source.spdx.json
11060d00031c34a1fbc7d2f636615698c43ae804b4413f1075198cfe46202a31  beztrace-0.1.1-binary.spdx.json
7a189d1c6a79fe8cb2bcec3473a865b215cd736e55fdb46d2cdd9ee9371d6a3e  release-manifest.json
b28b7c271c95accf3d07cb0edca38ca17ef1775737bde850745738178411fbf5  SHA256SUMS
```

Executable SHA-256: `3695e8fa41e941a21003052add1b65aea758fb8cd72addfd037288a94265e0cf`. Developer ID team `N9U29A4T8J`; arm64 and x86_64 both declare minimum macOS 13.0.

Apple notarization: ZIP `141a2161-d343-47a2-99be-faf7246555f0`, PKG `0810249c-3565-43d3-881a-16a47413f679`; both accepted. PKG stapled, Gatekeeper accepted and exact installed standalone JSON/SVG workflow verified. Installer title, welcome and completion identify **Beztrace 0.1.1**.
