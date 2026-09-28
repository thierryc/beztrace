# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Conservative font-metric placement. No native objects or image recognition."""
from dataclasses import dataclass
from .contract import CompanionError, number

MODES = ('Auto', 'Cap height', 'x-height', 'Ascender', 'Descender', 'Custom')
METRICS = ('baseline', 'capHeight', 'xHeight', 'ascender', 'descender')
DIGITS = ('zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine')


@dataclass(frozen=True)
class GlyphClass:
    name: str
    unicode: str = ''
    case: str = ''
    category: str = ''


@dataclass(frozen=True)
class MetricSnapshot:
    # Missing/ambiguous/invalid entries stay None; presets only require their range.
    values: tuple

    def get(self, key):
        return dict(self.values).get(key)

    def guides(self):
        return tuple((key, value) for key, value in self.values if number(value))


def metric_snapshot(layer_values, master_values):
    """Layer values are lists of (position, is_filtered) for each semantic type.

    Glyphs has already filtered these entries for this layer. Prefer a specific
    metric over a general one. Conflicting applicable entries require manual fit.
    """
    resolved = []
    for key in METRICS:
        candidates = layer_values.get(key, [])
        if candidates:
            specific = [v for v, filtered in candidates if filtered]
            values = specific or [v for v, _ in candidates]
            valid = all(number(v) for v in values) and len(set(values)) == 1
            value = float(values[0]) if valid else None
        else:
            value = master_values.get(key)
            value = float(value) if number(value) else None
        resolved.append((key, value))
    return MetricSnapshot(tuple(resolved))


def auto_mode(glyph):
    if glyph.name.endswith(('.lf', '.lnum')):
        base = glyph.name.rsplit('.', 1)[0]
        if base in DIGITS or base in tuple(str(n) for n in range(10)):
            return 'Cap height', 'Lining figures: cap-height fallback'
    try:
        char = chr(int(glyph.unicode, 16)) if glyph.unicode else ''
    except (ValueError, OverflowError):
        char = ''
    # No suffix stripping or Unicode decomposition: accents and alternates need
    # an explicit choice, even if they inherit the base glyph's Unicode/case.
    if char == glyph.name and glyph.category == 'Letter':
        if glyph.case == 'upper' and char in 'ABCDEFGHIKLMNOPRSTUVWXYZ':
            return 'Cap height', 'Auto: cap height'
        if glyph.case == 'lower' and char in 'acemnorsuvwxz':
            return 'x-height', 'Auto: x-height'
    raise CompanionError('Choose a Fit to preset or Custom for this glyph.')


@dataclass(frozen=True)
class ResolvedFit:
    height: float
    bottom: float
    explanation: str


def resolve(mode, glyph, metrics, height=700.0, bottom=0.0):
    if mode not in MODES:
        raise CompanionError('Unknown placement preset')
    explanation = mode
    if mode == 'Auto':
        mode, explanation = auto_mode(glyph)
    if mode == 'Custom':
        if not number(height) or not number(bottom) or height <= 0:
            raise CompanionError('Enter a positive height and a finite Bottom Y.')
        low, high = bottom, bottom + height
    else:
        lower, upper = {'Cap height': ('baseline', 'capHeight'), 'x-height': ('baseline', 'xHeight'),
                        'Ascender': ('baseline', 'ascender'), 'Descender': ('descender', 'xHeight')}[mode]
        low, high = metrics.get(lower), metrics.get(upper)
        if not number(low) or not number(high) or high <= low:
            raise CompanionError('This preset has missing or invalid font metrics. Choose Custom.')
    if not number(high) or max(abs(low), abs(high), high-low) > 1e6:
        raise CompanionError('Placement exceeds 1,000,000 units.')
    return ResolvedFit(high-low, low, '%s · %g–%g units' % (explanation, low, high))
