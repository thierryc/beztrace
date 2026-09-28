# Agent image-placement API v1

Available inside Glyphs after the companion loads:

```python
from beztrace_companion.api import API_VERSION, ImportRequest, prepare_imports, apply_imports
assert API_VERSION == 1
```

This API places native background images. It does **not** create glyphs, insert
paths, save fonts, change advance widths, or expose an MCP server. The interactive
panel traces the placed image later. A future MCP adapter remains separate work
and must use its authorized mutation/recovery workflow.

## Prepare, review, apply

Call `prepare_imports(font, entries, *, engine=...)` on the
main thread with an explicitly resolved open font. Entries are `ImportRequest`
objects. The return value is a cancellable `Preparation`; `done` is nonblocking,
`error` contains a preparation failure, and `plan` becomes available on success.
Poll `job.done` without blocking the Glyphs UI, then inspect `job.plan` in a
later authorized main-thread operation. Completion never schedules a font write.

```python
# Resolve this font and its layer IDs explicitly under the caller's authorization.
entries = [
    ImportRequest('/absolute/images/A.png', 'A', regular_layer_id),
    ImportRequest('/absolute/images/a.png', 'a', regular_layer_id),
    ImportRequest('/absolute/images/g.png', 'g', regular_layer_id,
                  preset='Descender'),
]
job = prepare_imports(font, entries)
# Later, on the main thread, after job.done and review:
plan = job.plan
report = apply_imports(plan)
```

Request fields:

| Field | Meaning / default |
| --- | --- |
| `path` | Existing PNG/JPEG source; normalized to an absolute path |
| `glyph`, `layer_id` | Exact existing glyph name and owning layer ID |
| `destination` | `foreground` (default) or `background` |
| `preset` | `Auto` (default), `Cap height`, `x-height`, `Ascender`, `Descender`, `Custom` |
| `height`, `bottom` | Custom ink height / bottom Y; defaults 700 / 0 |
| `horizontal` | Ink's leftmost X; default 0 |
| `replace` | Replace an existing image only when explicitly true; default false |

Auto supports unambiguous basic Latin uppercase and x-height lowercase glyphs,
and explicit `.lf`/`.lnum` lining figures. Ambiguous cases fail preparation;
choose a preset or Custom. Applicable layer metrics take precedence over master
metrics. Invalid/missing metrics never silently guess a placement.

Preparation snapshots targets and metrics on the main thread, then renders and
traces image snapshots off the UI thread to measure ink. It fits ink with a
uniform scale, retaining full-image padding. It returns proposed image transforms
without changing font content. `job.cancel()` cancels the engine and also prevents
application of an already prepared plan.

## Apply and recovery

`apply_imports(plan)` must run on the main thread. It checks the complete batch
before the first write: document/layer identity, content, metrics, classification,
source hashes and prepared-image integrity. Duplicate destination entries are
rejected. Preflight failures raise an exception and change no font content.

Each item has its own glyph undo group. Application stops on the first failure,
restores the failing item's image, and reports earlier completed items rather
than claiming the whole batch rolled back. A plan is consumed once application
starts, even when it partially fails; prepare a fresh plan before retrying.

The returned dictionary has `api_version`, `completed`, and ordered `items`.
Each item contains `glyph`, `layer_id`, `destination`, and `status`:
`applied`, `failed`, `recovery-failed`, `cancelled`, or `not-applied`.
Applied items include `transform`; failures include `error`. A recovery failure
means partial state may remain; stop editing that target and inspect it.

The source files remain external references and must remain available. No file
copying, source deletion, glyph creation, or font saving is performed. The `_host`
parameter is a test seam and is not part of API v1.

For engine 0.1.1-dev.1, pass the absolute path of the local development executable
as `engine`. Build 6 accepts this exact version and released 0.1.0, requiring the
version probe and result version to agree. The default remains the installed
0.1.0 executable; the API does not select development builds automatically.
