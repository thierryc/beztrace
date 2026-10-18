# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Presentation decisions without AppKit or font mutation."""

# UI order is independent of the existing, versioned matching API source modes.
MODE_LABELS = ('Single image', 'Images → masters', 'Image → path', 'Paths → masters')
MATCH_SOURCE_MODES = (None, 2, 1, 0)
MODE_HELP = ('Trace the canvas image into editable outlines.',
             'Trace two images into compatible master outlines.',
             'Trace an image to match an existing outline.',
             'Match existing outlines across masters.')


def settings_groups(mode, hoi=False, repair=False, shared=False, manual=False, review=False):
    """Ordered contextual groups; dependent fields appear beside their option."""
    if mode == 0:
        return [('Image', ('preset', 'raster', 'invert')),
                ('Curves', ('accuracy', 'smoothing', 'corner', 'grid', 'specks', 'refine')),
                ('', ('actions',))]
    groups = []
    if mode in (2, 3):
        groups.append(('Reference', ('policy',) + (('extra',) if shared and not review else ())))
    groups.append(('Fitting', ('fit', 'nodes', 'smooth')))
    if mode in (1, 2): groups.append(('Image', ('raster', 'invert')))
    if mode in (2, 3):
        rows = ('review',) if mode == 3 else ()
        if not review: rows += ('manual',) + (('pairs',) if manual else ())
        groups.append(('Correspondence', rows))
    if hoi:
        groups.append(('Interpolation', ('repair',) + (('kink', 'movement') if repair else ())))
    groups.append(('', ('actions',)))
    return groups


def visible_settings(mode, **options):
    return {name for _, rows in settings_groups(mode, **options) for name in rows}


def preview_actions(usable, busy, current, valid):
    """Update is always secondary; Apply requires the exact reviewed inputs."""
    return dict(update=bool(usable and not busy and not current),
                apply=bool(usable and not busy and current and valid))


def initial_master_pair(master_ids,current_id,previous_id=None):
    """Current selection is the target; prefer the prior selection as reference."""
    target=master_ids.index(current_id)
    reference=(master_ids.index(previous_id) if previous_id in master_ids and previous_id!=current_id
               else (target-1)%len(master_ids))
    return reference,target


def next_action(usable,busy,verified):
    if busy: return 'processing'
    if usable and verified: return 'apply'
    return 'process' if usable else 'unavailable'


def point_budget(reference,extra,total,source_mode):
    """Keep the on-curve ceiling distinct from a total that includes handles."""
    on_curves=sum(node['type']!='offcurve' for contour in reference.get('contours',[])
                  for node in contour['nodes']) if reference else 0
    ceiling=on_curves+extra if source_mode!=2 and on_curves else total
    return dict(maxAdditionalOnCurveNodes=extra,maxOnCurveNodes=min(1024,total,ceiling),maxNodes=total)
