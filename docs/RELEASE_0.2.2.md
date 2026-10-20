# Universal engine 0.2.2 and companion 0.2.1/build 26

Requested 2026-10-20. Status: source preparation; not published.
Source branch: `lit/release-v0.2.2`. Published engine 0.2.1 and companion
0.2.0/build 25 retain their tags and every distributed byte.

Both new distributions target macOS 13+ and contain arm64 and x86_64 slices.
This deployment target is distinct from tested OS coverage. The owner's
2026-10-20 instruction removes native Intel qualification as a release blocker
until an Intel Mac is available. Native Intel is untested, owner-waived;
Rosetta execution is separate evidence. All other release gates remain required.

## Changes

Engine 0.2.2 changes version identity only. Tracing, matching, fitting, smoothing,
JSON schema v1 and path-data version 2 are unchanged. Companion 0.2.1/build 26
accepts 0.2.2 and implements the documented shared `engine-settings-v1` contract.
It prefers explicit user selection over managed selection and defaults. Choose
Engine persists the user's path while preserving managed and unknown settings.
Malformed, oversized, symlinked and concurrently changed configuration is
refused. Engine selection never writes or replaces executables or plugins.

The Glyphs MCP managed installer and its catalog remain separate. Its Apple
Silicon/macOS 26.6.2 support limit does not change merely by publishing these
Beztrace distributions. Consumers must qualify their integration independently
and must preserve independent or modified installations.

## Qualification

Pending: clean-source local matrix, architecture comparisons, reproducible
packages, standalone matching and smoothing regression, performance, native
companion acceptance, Developer ID signatures, Apple notarization, signed
installation/lifecycle, Gatekeeper, and anonymous asset download verification.

Focused engine-settings and companion-package tests pass during preparation.
Final receipts will bind the exact source and distributed bytes. Earlier release
receipts remain historical and are not relabeled as qualification for this release.
