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

[Release verification](https://github.com/thierryc/beztrace/blob/v0.1.1/docs/RELEASE.md)
