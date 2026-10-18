# Beztrace 0.2.0 standalone release qualification

Release preparation is in progress. Publication requires passing signing,
notarization, installed-package, performance, robustness and exact-source gates.
This source record does not claim those operations have already completed.
The final external release receipt records exact artifact hashes and approvals.

The release promotes standalone master matching from the immutable
0.2.0-dev.1 preview. Geometry and all fixtures are unchanged; the engine version
becomes 0.2.0 and distribution includes all neutral schemas and owned R/Y examples.
The previous public releases and tags remain immutable.

Native font application, native HOI, Glyphs UI and companion distribution are
outside the standalone release. The existing Glyphs companion supports 0.1.1;
retain that engine for it instead of assuming this release upgrades the consumer.
Use the signed ZIP to run independently without replacing a shared installation.

See [workflow](PAIR_WORKFLOW.md), [matching contract](MASTER_MATCHING.md) and
[release verification](RELEASE.md). Public assets are available only after final
qualification at https://github.com/thierryc/beztrace/releases/tag/v0.2.0.
