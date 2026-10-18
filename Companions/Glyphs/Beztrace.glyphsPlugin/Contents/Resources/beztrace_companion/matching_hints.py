# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Apply-only hint correspondence. Never infer node identity from proximity."""
from .contract import CompanionError
from .native import _native_items, _properties


REFERENCES = (('originNode', 'origin'), ('targetNode', 'target'),
              ('otherNode1', 'other1'), ('otherNode2', 'other2'))
METADATA = ('type', 'horizontal', 'options', 'name', 'scale', 'stem', 'alignment', 'userData')


class HintMappingError(CompanionError):
    """The preview remains usable, but its paths cannot safely replace hints."""


def metadata(hint):
    return _properties(hint, METADATA)


def node_map(current, result, master):
    """Map native source indices only when the packet describes those sources."""
    output = result[('reference', 'target')[master]]['outline']
    if current == output:
        return {(ci, ni): (ci, ni) for ci, p in enumerate(current['contours'])
                for ni in range(len(p['nodes']))}
    if current != result['sourceMasters'][master]['outline']:
        return {}  # Raster-boundary indices are not destination path indices.
    mapping = {}
    for ci, report in enumerate(result['contours']):
        source_ci = report['referenceContour' if master == 0 else 'targetContour']
        indices = report['referenceSourceNodes' if master == 0 else 'targetSourceNodes']
        for ni, source_ni in enumerate(indices):
            if source_ni is None:
                continue
            key = (source_ci, source_ni)
            if key in mapping:
                raise HintMappingError('Apply blocked: hint node correspondence is ambiguous.')
            if current['contours'][source_ci]['nodes'][source_ni]['type'] == output['contours'][ci]['nodes'][ni]['type']:
                mapping[key] = (ci, ni)
    return mapping


def references(hint, paths, same):
    refs = []
    for attribute, index_attribute in REFERENCES:
        node = getattr(hint, attribute)
        if node is None:
            # A nonempty unresolved index can describe an intersection/handle or
            # an unsupported attachment. Do not mistake it for an absolute hint.
            if getattr(hint, index_attribute):
                raise HintMappingError('Apply blocked: a hint has an unsupported node reference. Review that hint before applying.')
            refs.append(None)
            continue
        locations = [(ci, ni) for ci, path in enumerate(paths) for ni, candidate in enumerate(path.nodes)
                     if same(node, candidate)]
        if len(locations) != 1:
            raise HintMappingError('Apply blocked: a hint attachment cannot be mapped safely. Review that hint before applying.')
        refs.append(locations[0])
    return refs


def prepare(host, ctx, stage, result):
    try:
        return _prepare(host, ctx, stage, result)
    except HintMappingError:
        raise
    except Exception as exc:
        raise HintMappingError('Apply blocked: hint preservation could not be verified. Review the affected hints before applying.') from exc


def _prepare(host, ctx, stage, result):
    """Preflight both masters without writes, copies retaining all hint settings."""
    transfers = []
    for mi, (target, prepared) in enumerate(zip(ctx['targets'], stage['layers'])):
        layer = target.layer
        hints = _native_items(layer.hints)
        keep = ([host.shape_state(p) for p in layer.shapes] ==
                [host.shape_state(p) for p in prepared.shapes])
        transfer = dict(keep=keep, hints=[], originals=hints)
        transfers.append(transfer)
        if keep:
            continue  # Retain the actual source paths, nodes and hints unchanged.
        mapping = node_map(ctx['outlines'][mi], result, mi) if hints else {}
        for hi, hint in enumerate(hints):
            old_refs = references(hint, layer.paths, host.same)
            if any(ref is not None and ref not in mapping for ref in old_refs):
                raise HintMappingError('Apply blocked: hint %d in %s refers to a node replaced by matching. Review that hint before applying.' %
                                       (hi + 1, str(layer.name)))
            mapped = [mapping[ref] if ref is not None else None for ref in old_refs]
            # Corner/cap hints also depend on the neighboring segment structure.
            if getattr(hint, 'isCorner', False):
                for ref in (r for r in old_refs if r is not None):
                    ci, ni = ref; dest_ci, dest_ni = mapping[ref]
                    old_count = len(layer.paths[ci].nodes); new_count = len(prepared.paths[dest_ci].nodes)
                    if any(mapping.get((ci, (ni + delta) % old_count)) !=
                           (dest_ci, (dest_ni + delta) % new_count) for delta in (-1, 1)):
                        raise HintMappingError('Apply blocked: matching changes the segments used by a corner or cap hint. Review that hint before applying.')
            absolute=[key for ref,key in zip(old_refs,('position','width')) if ref is None]
            transfer['hints'].append(dict(hint=hint.copy(), refs=mapped, metadata=metadata(hint),
                                          absolute=_properties(hint, absolute)))
    return dict(stage, hint_transfers=transfers)


def install(host, layer, prepared, transfer):
    if transfer['keep']:
        return
    # Remove old hints before replacing paths, then bind copies to the actual
    # installed nodes. Never leave a copied hint pointing into the preview font.
    layer.hints = []
    layer.shapes = [s.copy() for s in prepared.shapes]
    layer.hints = [entry['hint'].copy() for entry in transfer['hints']]
    for hint, entry in zip(_native_items(layer.hints), transfer['hints']):
        for (attribute, _), ref in zip(REFERENCES, entry['refs']):
            if ref is not None:
                ci, ni = ref
                setattr(hint, attribute, layer.paths[ci].nodes[ni])


def verify(host, layer, transfer):
    hints = _native_items(layer.hints)
    if transfer['keep']:
        if len(hints) != len(transfer['originals']) or any(not host.same(a, b) for a, b in zip(hints, transfer['originals'])):
            raise CompanionError('Matching changed hints on an unchanged layer')
        return
    if len(hints) != len(transfer['hints']):
        raise CompanionError('Matching changed the hint count')
    for hint, entry in zip(hints, transfer['hints']):
        if metadata(hint) != entry['metadata']:
            raise CompanionError('Matching changed hint settings')
        if _properties(hint, [key for key,_ in entry['absolute']]) != entry['absolute']:
            raise CompanionError('Matching changed an absolute hint')
        if references(hint, layer.paths, host.same) != entry['refs']:
            raise CompanionError('Matching hint references differ from the prepared correspondence')
