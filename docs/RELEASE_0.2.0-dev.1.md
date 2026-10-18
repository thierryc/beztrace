# Beztrace 0.2.0-dev.1 development preview

This standalone preview adds compatible tracing and matching for two glyph
masters. It is an unsigned development prerelease, not a qualified stable release.
Stable engine 0.1.1 and the independently released Glyphs companion are unchanged.

[Download the preview](https://github.com/thierryc/beztrace/releases/tag/v0.2.0-dev.1)
and verify its SHA256SUMS before extracting. The universal executable supports
macOS 13+ on Apple Silicon and Intel; Python and Glyphs are not runtime dependencies.
No installer is provided and no existing engine is replaced automatically.

## Use it

Provide two images of the same glyph at different weights—or an existing Regular
outline and a Bold image—run matching, and review the outlines and intermediate
weights before importing them into your font editor.

From the extracted folder, use a new output directory for each run:

```sh
./run-example.sh Y-images-smart /tmp/beztrace-Y-images
./run-example.sh R-mixed-direct /tmp/beztrace-R-mixed
./run-example.sh R-outlines-smart /tmp/beztrace-R-outlines
```

For your own sources, copy an example job and set its files, master locations,
UPM and image placement, then run:

```sh
./bin/beztrace match-pair JOB.json --output-directory RESULTS --json-errors
```

Open `RESULTS/index.html` to review numbered nodes and intermediate shapes.
`recommended.master-set.json` is the matched geometry; `comparison.json` records
measurements, source hashes, attempted routes and refusals. See [pair workflow](PAIR_WORKFLOW.md).

## What's included

- Two images: common planning returns two compatible outlines.
- Reference outline plus image: reference stays exact; target fits its structure.
- Two outlines: reference stays exact; target is aligned and refitted.
- Explicit target/both retracing and smart comparison under the same tolerance
  and budgets. Shared changes require permission in the job.
- Bounded coupled-handle fitting, local extremum constraints and shared vector/
  raster fitting. Platform-independent matching distance calculations and a
  common sequential-image seed remove the observed architecture differences.
- Versioned schemas, owned R/Y examples, paired proofs, licenses, SPDX SBOMs,
  source/build provenance and checksums. Private font artwork is excluded.

## Qualification boundary

Local evidence records 161 optimized arm64 tests with zero failures and one
intentional maintenance skip, 46 focused x86_64/Rosetta tests with zero failures,
18 controlled pair jobs with identical output files across architectures, and
clean-directory examples with collision protection. Additional private regressions
were tested locally; their inputs and output artwork are not distributed.

Tolerance remains one font unit per 1000 UPM by default. Fixed jobs derive exact
reference node ceilings; shared jobs require explicit allowances. Topology,
crossings, ambiguity and exhausted limits still refuse. No artist-quality judgment
or continuous/native interpolation guarantee is inferred from sampled checks.

Smooth-join residuals can require visual/native review. Some optional routes can
refuse even when another route succeeds. Native Intel CI qualification, Developer
ID signing, notarization, installation and native font application are separate
pending gates. The archive includes no matching Glyphs UI, native HOI implementation
or font writer. Do not replace the stable engine used by the released companion
with this preview unless that consumer explicitly supports it.
