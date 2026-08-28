# Release and verification

Version `0.1.0` is the first standalone beztrace release. It supports macOS 13
or later on Apple Silicon and Intel Macs and has no non-system runtime
dependency.

## Release assets

- `beztrace-0.1.0.pkg`: Developer ID-signed and Apple-notarized installer.
- `beztrace-0.1.0-macos-universal.zip`: signed universal executable with
  licenses, notices, schemas, and SPDX SBOMs.
- `SHA256SUMS`: SHA-256 hashes for the distributed binary assets and SBOMs.
- `release-manifest.json`: machine-readable version, architecture, signature,
  notarization, artifact, and SBOM inventory.
- `beztrace-0.1.0-source.spdx.json` and
  `beztrace-0.1.0-binary.spdx.json`: SPDX 2.3 SBOMs.

The canonical download location is the
[GitHub v0.1.0 release](https://github.com/thierryc/beztrace/releases/tag/v0.1.0).

## Verify and install

Download all release assets into one directory, then verify them before
installation:

```sh
shasum -a 256 -c SHA256SUMS
pkgutil --check-signature beztrace-0.1.0.pkg
xcrun stapler validate beztrace-0.1.0.pkg
sudo installer -pkg beztrace-0.1.0.pkg -target /
beztrace --version
```

The final command must print `beztrace 0.1.0`. The package installs the binary
at `/Library/Application Support/beztrace/bin/beztrace` and creates
`/usr/local/bin/beztrace` as its command-line entry point.

## Smoke test

Trace a supported PNG into canonical Y-up JSON:

```sh
beztrace trace input.png --format json --output outline.json
```

Or create a transform-free SVG for design tools:

```sh
beztrace trace input.png --format svg --output outline.svg
```

Inputs are local PNG or JPEG files. Version `0.1.0` performs no network access,
telemetry, automatic updating, Glyphs document mutation, or Glyphs MCP
integration.

## Contract

JSON schema v1 and `pathDataVersion 2` are the neutral machine contract.
Consumers must check those fields and the engine version before using returned
paths. JSON remains Y-up; SVG defaults to baked, transform-free SVG coordinates.
Use `--svg-transform preserve` when SVG path coordinates must stay Y-up.
