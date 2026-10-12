# Beztrace skills and Glyphs MCP catalog handoff

Prepared 2026-10-10 on the authorized `lit/master-matching` branch.
This task creates generic Beztrace skills and plans their inclusion in the
Glyphs MCP app. It does not modify the Glyphs MCP repository or ship its app.

## Deliverables

| Skill ID | Catalog title | Scope |
| --- | --- | --- |
| `beztrace-vectorize-image` | Beztrace Image Vectorization | Explain or trace clean PNG/JPEG glyph/symbol silhouettes; neutral JSON/SVG, native placement, quality and review. |
| `beztrace-match-masters` | Beztrace Master Matching | Explain or perform reference-guided tracing and outline correspondence; strict unchanged structure, unchanged on-curves with handles, or explicitly bounded growth. |

Canonical sources are [vectorization](../skills/beztrace-vectorize-image/SKILL.md)
and [master matching](../skills/beztrace-match-masters/SKILL.md) in this repository.
Each has portable relative references and `agents/openai.yaml` catalog metadata.
Names remain generic, independent of a particular font, user path, weight,
test corpus or computer. Explanations and standalone tracing do not require MCP.
Both remain discoverable through normal implicit skill selection.

Ordinary tracing uses stable trace schema 1 / path-data 2. Matching requires the
optional budget-capable engine and compatible companion; the currently tested
matching implementation is developmental. Listing a skill must not imply the
corresponding engine/plugin is installed, loaded or release-qualified.

## Inspected integration points

Read-only inspection of the Glyphs MCP checkout found:

- `skills/` is the canonical skill bundle there.
- `scripts/sync_codex_plugin_skills.sh` has an explicit `SKILLS` list and mirrors
  it into `plugins/glyphs-mcp/skills/`; `--check` verifies exact parity and rejects
  unexpected packaged directories.
- `plugins/glyphs-mcp/.codex-plugin/plugin.json` advertises `./skills/`.
- `macos-installer/GlyphsMCPInstaller/Core/FileIO.swift`,
  `InstallerPayload.managedSkillDirectories()`, currently accepts only `glyphs`
  and names beginning `glyphs-mcp-`. It would omit the two generic Beztrace IDs.
- The app's `Sources/ContentView.swift` Skills tab handles Codex/Claude targets;
  `InstallerViewModel.swift` derives uninstall ownership from managed payload
  names. Packaging, update and uninstall must agree on these IDs.

These are observed source paths, not completed changes. Reinspect the current
app branch and its applicable instructions before implementing the handoff.

## Implementation sequence in the Glyphs MCP task

1. **Import the reviewed source bundle.** Record its Beztrace revision and file
   hashes; include both entire skill directories, their references and UI YAML.
   Preserve Beztrace's Apache-2.0 OR MIT licensing and notices. Use a recorded
   import/update procedure rather than maintaining divergent copies. No private
   font fixtures, local paths or development binaries belong in the bundle.
2. **Register both generic IDs.** Add them to the shared-plugin sync allowlist
   and installer payload ownership. Prefer explicit owned names/manifest entries
   over accepting arbitrary directory prefixes. Keep install/update/uninstall
   consistent, including both client destinations. Do not rename them solely to
   satisfy the current prefix filter.
3. **Expose the catalog entries.** Use the supplied display names, descriptions
   and example prompts. Explain/image-only routes stay available when Glyphs or
   the optional companion is absent. For execution, detect engine modes/schema/
   budgets and loaded companion support; display truthful development or missing-
   dependency status. Reuse an existing dependency/setup workflow when needed,
   without auto-installing, restarting or claiming new bridge endpoints.
4. **Route to existing consumers.** Standalone CLI/file exchange and the native
   companion menus require no new MCP protocol. Automation uses only advertised
   native script/edit capabilities and documented loaded companion APIs. If a
   separate adapter is later needed, scope it as separate implementation; skills
   alone do not provide that runtime capability.
5. **Qualify the bundle and app.** Run skill validation and sync `--check`; verify
   installer payload completeness, client discovery, prompts, sibling/reference
   links, explicit ownership and collisions with existing local skills. Preserve
   unrelated skills and reconcile existing Beztrace copies before replacement.
   Verify skill-only installation does not require a font, save unsaved work,
   change outlines, or install/relaunch Glyphs as a side effect.
6. **Qualify routing and release separately.** Exercise the scenarios below
   with bounded fixtures and disposable native documents where necessary. Record
   exact source, packaged files, loaded host/companion and engine. App signing,
   notarization, installation and publication follow that repository's own gates
   and authorizations; adding catalog text does not qualify matching for release.

## Acceptance scenarios

| User request or condition | Required observable behavior |
| --- | --- |
| Explain compatible tracing | Matching skill loads; explains shared ordering, fitting and the three point policies without writes or requiring an app connection. |
| Trace one glyph image to SVG | Vectorization skill routes to the available CLI, preserves source, reviews quality/placement and produces a vector file. |
| No extra points of any kind | Fixed reference with zero added on-curves and total-node ceiling equal to the reference count; no hidden handle allowance. An infeasible fit is reported. |
| No extra on-curves, handles permitted | Explicit shared policy and total-node budget; actual handle growth is reported distinctly. |
| Trace intended for a variable-font master | Vectorization routes to matching before independent tracing; equal counts alone are not accepted as correspondence. |
| Matching unsupported by selected engine | Precise availability report; no invented MCP call, source injection or silent upgrade. Ordinary tracing remains available. |
| Native trace preview requested | Standalone review or `prepare_trace`; ordinary panel Trace is correctly described as immediate insertion. |
| Ambiguous correspondence, topology or budget failure | No Apply, tolerance relaxation, point inflation or unrequested source cleanup. Report the reason and explicit alternatives. |
| Existing or imported HOI | Preserve existing settings; revalidate imported corrections natively; keep geometry and native HOI claims separate. |
| Catalog install/update/remove | Both IDs and all referenced files remain coherent; only explicitly managed paths are changed; no font edits or lost unsaved work. |

## Current completion boundary

The two portable skill sources, UI metadata and this plan are created in
Beztrace. Both also have verified exact copies in the local Codex skills folder.
Frontmatter/UI metadata, relative links, Python example syntax, advertised
engine capabilities and referenced API symbols were checked. These checks do
not constitute new native font or installed-app qualification. Local records
are `.build/beztrace-skills/validation.json` and `local-registration.json`.
Local registration is separate from the planned app catalog inclusion.
No Glyphs MCP source,
plugin cache, app payload, released tag or distributed bytes are changed here.
