# Copyright 2026 Thierry Charbonnel (thierryc)
# SPDX-License-Identifier: Apache-2.0
# Adapted from dekink-glyphs4 f6c33d969732716698e8a10e0714e1ec4b74a118.
# Companion evaluates every candidate and ranks native shape deviation first.
"""Pure candidate planning; never evaluates Glyphs interpolation."""
import math


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def scale(a, k):
    return (a[0] * k, a[1] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def lerp(a, b, t):
    return add(scale(a, 1 - t), scale(b, t))


def metric(points):
    if len(points) != 3 or any(len(p) != 2 or not all(math.isfinite(v) for v in p) for p in points):
        raise ValueError('Expected three finite coordinate pairs')
    a, j, b = points
    u, v, d = sub(a, j), sub(b, j), sub(b, a)
    degenerate = min(math.hypot(*u), math.hypot(*v), math.hypot(*d)) < 1e-10
    return {'error_u': None if degenerate else abs(cross(sub(j, a), d)) / math.hypot(*d),
            'degenerate': degenerate, 'folded': dot(u, v) >= 0}


def candidates(a, b, tolerance=.001):
    """Try single-node quadratic candidates before a coordinated pair.

    Values are desired native midpoint positions, not calibrated stored ip.
    Local indices refer to previous tangent point, join, next tangent point.
    Existing nonlinear local HOI invalidates these assumptions.
    """
    if not math.isfinite(tolerance) or tolerance < 0:
        raise ValueError('Invalid tolerance')
    for points in (a, b):
        m = metric(points)
        if m['degenerate'] or m['folded']:
            raise ValueError('Folded or degenerate source tangency')
    mid = [lerp(p, q, .5) for p, q in zip(a, b)]
    plans = []

    def offer(label, entries):
        entries = {i: p for i, p in entries.items() if math.dist(p, mid[i]) > 1e-9}
        if entries:
            plans.append({'strategy': label, 'targets': entries, 'entries': len(entries),
                          'movement_u': sum(math.dist(p, mid[i]) for i, p in entries.items())})

    direction = sub(mid[2], mid[0])
    change = sub(sub(b[2], b[0]), sub(a[2], a[0]))
    denom = cross(direction, change)
    if abs(denom) > 1e-12 * max(1, math.hypot(*direction) * math.hypot(*change)):
        offer('one join', {1: sub(mid[1], scale(change, cross(direction, sub(mid[1], mid[0])) / denom))})
    for moving, reference in ((0, 2), (2, 0)):
        ratios = []
        for points in (a, b):
            v = sub(points[reference], points[1])
            ratios.append(dot(sub(points[moving], points[1]), v) / dot(v, v))
        offer('one neighbor', {moving: add(mid[1], scale(sub(mid[reference], mid[1]), sum(ratios) / 2))})
    unit = [scale(sub(p[2], p[1]), 1 / math.dist(p[2], p[1])) for p in (a, b)]
    if math.hypot(*lerp(*unit, .5)) < 1e-6:
        raise ValueError('Opposing source directions')
    d = lerp(*unit, .5)
    offer('coordinated neighbors', {i: add(mid[1], scale(d, (dot(sub(a[i], a[1]), unit[0]) + dot(sub(b[i], b[1]), unit[1])) / 2)) for i in (0, 2)})
    return sorted(plans, key=lambda p: (p['entries'], p['movement_u']))


def verification_limit(source_metrics, tolerance):
    """Preserved endpoints impose a measured residual floor, not an exclusion.

    Exact sources retain the absolute tolerance. Rounded sources allow only
    their largest endpoint residual plus tolerance; native trials still decide
    whether a candidate is effective over the sampled span.
    """
    if not math.isfinite(tolerance) or tolerance < 0 or not source_metrics:
        raise ValueError('Invalid source metrics or tolerance')
    if any(m['degenerate'] or m['folded'] or m['error_u'] is None
           or not math.isfinite(m['error_u']) for m in source_metrics):
        raise ValueError('Folded or degenerate source tangency')
    floor = max(m['error_u'] for m in source_metrics)
    return tolerance if floor <= tolerance else floor + tolerance


def summarize(samples):
    if not samples:
        raise ValueError('Empty sample set')
    finite = [s for s in samples if s['error_u'] is not None]
    return {'peak': max(finite, key=lambda s: s['error_u']) if finite else None,
            'midpoint': next((s for s in samples if s['factor'] == .5), None),
            'sample_count': len(samples), 'invalid': any(s['degenerate'] or s['folded'] for s in samples)}


def calibrate_midpoint(target, write, read, tolerance, attempts=8):
    """Bounded native-response calibration via callbacks; retain final write.

    Coordinate agreement is separate from span tangency. Caller must still
    verify actual native output over the entire declared sample set.
    """
    if not math.isfinite(tolerance) or tolerance < 0 or type(attempts) is not int or attempts < 1:
        raise ValueError('Invalid calibration controls')
    requested = tuple(target)
    for attempt in range(attempts):
        write(requested)
        actual = tuple(read())
        if not all(math.isfinite(v) for v in actual):
            raise ValueError('Nonfinite native midpoint')
        delta = sub(target, actual)
        error = math.hypot(*delta)
        if error <= tolerance:
            return {'ip': requested, 'actual': actual, 'error_u': error, 'attempts': attempt + 1, 'converged': True}
        if attempt + 1 < attempts:
            requested = add(requested, delta)
    return {'ip': requested, 'actual': actual, 'error_u': error, 'attempts': attempts, 'converged': False}
