# Release and verification

Version `0.2.0` is the current downloadable stable standalone beztrace release. It supports macOS 13
or later on Apple Silicon and Intel Macs and has no non-system runtime
dependency.

## Release assets

- `beztrace-0.2.0.pkg`: Developer ID-signed and Apple-notarized installer.
- `beztrace-0.2.0-macos-universal.zip`: signed universal executable with
  licenses, notices, schemas, and SPDX SBOMs.
- `SHA256SUMS`: SHA-256 hashes for the distributed binary assets and SBOMs.
- `qualification-receipt.json`: public distribution check results and scope.
- `release-manifest.json`: machine-readable version, architecture, signature,
  notarization, artifact, and SBOM inventory.
- `beztrace-0.2.0-source.spdx.json` and
  `beztrace-0.2.0-binary.spdx.json`: SPDX 2.3 SBOMs.

The canonical download location is the
[GitHub v0.2.0 release](https://github.com/thierryc/beztrace/releases/tag/v0.2.0).

## Verify and install

Download all release assets into one directory, then verify them before
installation:

```sh
shasum -a 256 -c SHA256SUMS
pkgutil --check-signature beztrace-0.2.0.pkg
xcrun stapler validate beztrace-0.2.0.pkg
sudo installer -pkg beztrace-0.2.0.pkg -target /
beztrace --version
```

The final command must print `beztrace 0.2.0`. The package installs the binary
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

Inputs are local PNG or JPEG files. Version `0.2.0` performs no network access,
telemetry, automatic updating, Glyphs document mutation, or Glyphs MCP
integration.

## Match two masters

Use the ZIP without installing to keep another engine version available:

```sh
./beztrace/run-example.sh Y-images-smart /tmp/beztrace-example
./beztrace/bin/beztrace match-pair JOB.json --output-directory RESULTS --json-errors
```

The matching command accepts two images, an outline plus an image, or two outlines.
Review `index.html` and consume `recommended.master-set.json`. The default keeps a
vector reference exact. Additional nodes and shared subdivision require explicit
limits; smart routes share the same tolerance and budgets.

[Configuration](https://github.com/thierryc/beztrace/blob/v0.2.0/docs/PAIR_WORKFLOW.md)
and [0.2.0 qualification](RELEASE_0.2.0.md) describe the contracts and evidence.
All new builds, tests and qualification run locally. GitHub Actions test and
release workflows have been removed.

## Contract

JSON schema v1 and `pathDataVersion 2` are the neutral machine contract.
Consumers must check those fields and the engine version before using returned
paths. JSON remains Y-up; SVG defaults to baked, transform-free SVG coordinates.
Use `--svg-transform preserve` when SVG path coordinates must stay Y-up.

## Optional companion distribution

The separately versioned [Glyphs 4 plugin](../Companions/Glyphs/README.md) has its
own [release procedure](../Companions/Glyphs/RELEASE.md) and artifact manifest.
It is not included in engine 0.2.0 assets and does not change their checksums,
signatures, or installation behavior. The independently released companion 0.1.0/build 15 requires its supported
0.1.1 engine. Keep that installation and run the standalone 0.2.0 ZIP separately
until native matching integration is independently qualified.

## 0.1.1-dev.1 development prerelease

The small-contour correction and Glyphs companion build 6 are distributed as a
GitHub prerelease, with 0.1.0 retained as latest stable at that historical publication.
The new engine and companion are development artifacts without Developer ID
signing or notarization. Full companion UI qualification remains pending.

Assets include a universal engine ZIP, the independently versioned companion
ZIP, engine/companion manifests, SPDX SBOMs and SHA256SUMS. Verify checksums before
extracting. The engine archive's `bin/beztrace` can be selected using the
companion's Choose Engine menu. It does not replace the shared 0.1.0 installation
automatically. There is no development installer package.

See [small-contour verification](SMALL_CONTOUR_FIX.md) and the
[companion prerelease procedure](../Companions/Glyphs/RELEASE.md).

## 0.1.1 stable qualification and reproduction

Source version 0.1.1 promotes the small-contour, handle-rounding, topology-safe Grid and
small convex-curve corrections described in [development verification](SMALL_CONTOUR_FIX.md).
The neutral contract remains JSON schema v1 and pathDataVersion 2.
The prior [0.1.0 release](https://github.com/thierryc/beztrace/releases/tag/v0.1.0)
and development prerelease remain available with their original assets.

Stable v0.1.1 is published after all distribution gates passed. The API and release page return 200, and all assets download anonymously with matching checksums. The exact tag/source is `9737f21fabfda0dc9e6728bd34df2f83380238e9`. See the [integration handoff](GLYPHS_MCP_V2_HANDOFF.md) for hashes and evidence.

The published asset names are `beztrace-0.1.1.pkg`,
`beztrace-0.1.1-macos-universal.zip`, versioned source/binary SPDX SBOMs,
`release-manifest.json`, and `SHA256SUMS`.

Reproduction uses a clean source revision and a fresh staging directory:

```sh
BEZTRACE_EXTERNAL_WORK=/private/tmp/beztrace-milestone-7-v0.1.1 \
BEZTRACE_APPLICATION_IDENTITY='Developer ID Application: <name> (<team>)' \
BEZTRACE_INSTALLER_IDENTITY='Developer ID Installer: <name> (<team>)' \
  scripts/build_release_candidate.sh --final --version 0.1.1 --notarize
```

The script refuses existing output and checks the compiled engine version.
The notary keychain profile defaults to `beztrace-notary`. Never publish unsigned
or unnotarized output as a stable release. The distribution excludes the Glyphs
companion. Source build 12 accepts 0.1.1; earlier installed builds reject it and
require a separate companion upgrade or an explicit supported engine path.

See [0.1.1 qualification](RELEASE_0.1.1.md) for the release evidence.
