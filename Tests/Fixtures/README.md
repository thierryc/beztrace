# Test fixtures

This directory contains immutable inputs and reviewed expectations for the
beztrace test harness. Ordinary tests are read-only. Baselines may only be
changed by the explicit regeneration commands documented in
`docs/TESTING.md`.

- `corpus/deterministic`: reproducible renders from checksum-pinned fonts.
- `corpus/generated`: generated acceptance inputs with recorded prompts.
- `sources`: the exact redistributable source assets and their licenses.
- `oracle/v1`: metadata and captured stage output from the pinned img2bez
  reference.
- `manifest.json`: provenance, hashes, and structural review expectations.

Generated images are acceptance fixtures, not coordinate oracles. The
deterministic corpus and the 62-glyph img2bez reference provide vector-backed
comparisons.
