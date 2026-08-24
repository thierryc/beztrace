# Historical request for img2bez reference UFO

This request was never posted. It is retained only to explain the historical
`0.964` provenance gap; the project now uses the pinned public replacement
baseline documented in `TESTING.md`.

This message is prepared for the img2bez author. Sending it is an external
action and requires separate authorization.

> Subject: Request for the reference UFO used by img2bez commit 23073ca
>
> I am preparing a licensed Swift derivative port of img2bez, pinned to commit
> `23073ca08ecdac61ad0e838bfae49a590bc2c7cc`. The repository's evaluation
> harness refers to an untracked `eval-harness/reference.ufo`, and I would like
> to reproduce the published 62-glyph mean structural score of `0.964` without
> substituting a different source.
>
> Could you provide the exact reference UFO used for that result, together
> with its license, provenance/source revision, and approximate capture date?
> A SHA-256 checksum is sufficient if the UFO cannot be redistributed.
>
> For verification, the recorded focused baseline expects these reference
> on-curve counts: ampersand 35, a 27, e 18, s 22, R 26, O 8, S 20, n 19.
> The UFO must also contain a-z, A-Z, and 0-9.
>
> No newer img2bez behavior will be imported; the reference will be used only
> to freeze differential test fixtures for the pinned revision.

On receipt, record the original delivery channel and date without committing
private correspondence. Run `scripts/intake_reference_ufo.py` before any
oracle capture. Do not rename, edit, normalize, or resave the supplied UFO.
