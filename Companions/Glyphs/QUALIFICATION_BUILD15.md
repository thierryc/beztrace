# Build 15 independent companion qualification

Version 0.1.0/build 15 is prepared for a separate Developer ID signed and
Apple-notarized distribution. About refers to the external manifest rather than
claiming every source-built package is unsigned. No engine code, public MCP API,
dependency or automatic installer changes are included.

The owner authorized signing, Apple uploads and official GitHub publication on
2026-10-05. Native Intel testing is explicitly owner-waived because no recent
Intel Mac is available; it remains untested. Apple Silicon native qualification
is scoped to the exact installed and running final identity.

The external release evidence records the clean source revision, final signed
archive and payload hashes, Apple submission ID, signature identity, exact OS,
Glyphs and Python runtime, each native result and remaining gates. Historical
build 13/14 tests and failure receipts are preserved. A source-level test, code
signature or Apple acceptance does not establish a missing native result.

The unsigned reproducible builder intentionally retains development-unqualified
metadata. Signed-release metadata is generated separately after signing. Do not
claim native-qualified or publish an official stable companion until the
remaining non-waived native checklist has passed against final bytes.
