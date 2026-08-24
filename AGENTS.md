# Agent instructions

These instructions apply to the entire beztrace repository.

## Current phase

The reference checkpoint is complete and the repository is pre-implementation.
It contains documentation, test infrastructure, and immutable fixtures. Do not
add `Package.swift`, `Sources/`, an Xcode project, Swift production code, or
release automation until the user separately authorizes Swift implementation.

Before any future implementation work, read every document linked from the
root `README.md`, confirm the current branch, and inspect the worktree. Never
discard unrelated changes.

## Branch contract

- Keep `main` usable for reviewed documentation, requirement, and project
  policy fixes.
- Perform implementation only on `lit/initial-swift-port` or a later branch
  explicitly authorized by the user.
- Merge `main` into the long-running implementation branch periodically. Do
  not rebase or force-push the long-running branch.
- Do not merge implementation into `main` until the viability gate in
  `docs/QUALITY_GATES.md` passes in full.
- Do not create a remote repository, push, publish, sign, notarize, or upload
  artifacts without separate explicit authorization.

## Product boundaries

- beztrace must remain a standalone product with no Glyphs.app or Glyphs MCP
  runtime dependency.
- The intended future role is a companion engine that returns neutral,
  versioned paths for a separately versioned Glyphs MCP adapter to consume.
- Do not edit the Glyphs MCP repository from a beztrace implementation task.
- Do not add an MCP adapter here. Future consumers use the versioned neutral
  JSON contract.
- V1 targets clean generated glyph silhouettes, not general image
  vectorization.
- Apple Vision may be used only for experiments or diagnostics. It must not
  replace the specified subpixel contour, structural fitting, raster
  refinement, and typographic cleanup pipeline.
- Polygon-only, generic SVG autotrace, or excessive-point output does not
  satisfy the product requirements.

## Porting and provenance

- The sole img2bez baseline is commit
  `23073ca08ecdac61ad0e838bfae49a590bc2c7cc`.
- Treat the Swift implementation as a permitted derivative port, not as a
  clean-room implementation.
- Preserve upstream copyright and `SPDX-License-Identifier: Apache-2.0 OR MIT`
  in translated files, and identify the Swift port and material changes.
- Port img2bez-owned behavior only. Do not translate code from Rust
  dependencies unless its separate license and provenance are audited and
  recorded first.
- Do not silently import behavior from newer img2bez revisions. Proposed
  changes must be developed as beztrace work with their own tests and notes.

## Engineering requirements

- Implement in the phase order defined in `docs/IMPLEMENTATION_DIRECTIVE.md`.
- Use Swift `Double` for geometry and deterministic ordering and rounding.
- Add tests with each implementation stage; do not postpone the differential
  harness or geometry validation until the end.
- Keep the core library free of filesystem, CLI, logging, and presentation
  policy. Adapters own those concerns.
- Use Apple system frameworks and avoid external runtime dependencies unless a
  reviewed requirement change explicitly permits one.
- Treat quality and performance gates as release blockers, not aspirational
  metrics.

## Release boundary

A working local executable is not a viable product. No v1 release is eligible
until the library, CLI, schema, fixtures, benchmarks, licensing, SBOM,
universal build, Developer ID signing, notarization, package installation, and
non-Glyphs workflow validation all pass the documented gates.
