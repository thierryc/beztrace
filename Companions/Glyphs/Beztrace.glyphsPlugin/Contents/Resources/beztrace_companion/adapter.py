# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Target binding and reversible main-thread application through a small host API."""
from dataclasses import dataclass
from .contract import CompanionError


class RecoveryError(CompanionError):
    """Partial native state may remain. The window must disable further writes."""


@dataclass
class Target:
    document: object
    font: object
    glyph: object
    owner: object
    layer: object
    destination: str
    identity: tuple
    fingerprint: object
    label: str
    metrics: object = None
    classification: object = None


def capture(host, destination):
    host.assert_main()
    if destination not in ('foreground', 'background'):
        raise CompanionError('Invalid destination')
    document, font, glyph, owner = host.current()
    layer = host.destination(owner, destination)
    host.check_editable(glyph, layer)
    return Target(document, font, glyph, owner, layer, destination,
                  host.identity(glyph, owner), host.fingerprint(layer),
                  host.label(document, font, glyph, owner),
                  host.metrics(owner) if hasattr(host, 'metrics') else None,
                  host.classification(glyph) if hasattr(host, 'classification') else None)


def revalidate(host, target):
    host.assert_main()
    if target is None or not host.contains(target):
        raise CompanionError('The captured document, glyph, or layer is no longer available. Select the layer and trace again.')
    host.check_editable(target.glyph, target.layer)
    if target.metrics is not None and host.metrics(target.owner) != target.metrics:
        raise CompanionError('Font metrics changed. Prepare image placement again.')
    if target.classification is not None and host.classification(target.glyph) != target.classification:
        raise CompanionError('Glyph classification changed. Prepare image placement again.')
    if host.fingerprint(target.layer) != target.fingerprint:
        raise CompanionError('The destination changed. Trace again after reviewing the destination.')


def apply_paths(host, target, paths, replace=False, *, base_snapshot=None):
    revalidate(host, target)
    if replace:
        host.check_replace(target.layer)
    native = host.make_paths(paths)
    snapshot = host.snapshot(target.layer)
    prior = host.fingerprint(target.layer)
    state = host.rounding_state(target.layer)  # Capability check before mutation.
    begun = False
    try:
        host.begin_undo(target.glyph)
        begun = True
        try:
            host.set_rounding(target.layer, True)
            if base_snapshot is not None:
                host.restore(target.layer, base_snapshot)
            host.insert(target.layer, native, replace)
            host.set_rounding(target.layer, state)
            host.verify(target.layer, native, paths, base_snapshot if base_snapshot is not None else snapshot, replace)
        except Exception as original:
            try:
                host.set_rounding(target.layer, True)
                host.restore(target.layer, snapshot)
                host.set_rounding(target.layer, state)
                if host.fingerprint(target.layer) != prior:
                    raise RuntimeError('Recovered layer does not match its snapshot')
            except Exception as recovery:
                raise RecoveryError('Apply failed and recovery could not be verified. Stop editing this target; partial changes may remain. ' + str(recovery)) from original
            raise CompanionError('Apply failed; the previous layer content was restored. ' + str(original)) from original
    finally:
        # Attempt both cleanup actions, even when one native call fails.
        failures = []
        try:
            host.set_rounding(target.layer, state)
            if host.rounding_state(target.layer) != state:
                raise RuntimeError('Precision flag restoration failed')
        except Exception as exc:
            failures.append(str(exc))
        if begun:
            try:
                host.end_undo(target.glyph)
            except Exception as exc:
                failures.append(str(exc))
        if failures:
            raise RecoveryError('Native transaction cleanup failed: ' + '; '.join(failures))
    try:
        host.redraw()
    except Exception:
        # Redraw failure must not turn a verified mutation into a retryable Apply.
        return "Paths applied; refresh the Glyphs view to display them."
    return None


def apply_image(host, target, image, replace=False):
    """Undoable image-only assignment, with verified in-memory recovery."""
    revalidate(host,target)
    old=target.layer.backgroundImage
    if old is not None and not replace:
        raise CompanionError('This layer already has an image; replacement was not requested')
    prior=host.fingerprint(target.layer)
    preserved=host.content_without_image(target.layer)
    expected=host.image_state(image)
    begun=False
    try:
        host.begin_undo(target.glyph); begun=True
        try:
            host.set_image(target.layer,image)
            if host.image_state(target.layer.backgroundImage)!=expected or host.content_without_image(target.layer)!=preserved:
                raise CompanionError('Native image placement failed verification')
        except Exception as original:
            try:
                host.set_image(target.layer,old)
                if host.fingerprint(target.layer)!=prior:
                    raise RuntimeError('Image recovery did not restore the layer')
            except Exception as recovery:
                raise RecoveryError('Image placement failed and recovery could not be verified: '+str(recovery)) from original
            raise CompanionError('Image placement failed; previous state restored: '+str(original)) from original
    finally:
        if begun:
            try: host.end_undo(target.glyph)
            except Exception as exc: raise RecoveryError('Image undo cleanup failed: '+str(exc)) from exc
    try: host.redraw()
    except Exception: pass  # Verified placement is complete; do not encourage retry.
