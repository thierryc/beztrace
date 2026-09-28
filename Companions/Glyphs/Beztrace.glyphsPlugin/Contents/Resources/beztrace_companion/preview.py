# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Shared preview geometry and callback lifecycle, independent of AppKit."""
from dataclasses import dataclass
from .contract import place, segments, tight_bounds


@dataclass(frozen=True)
class PreviewGeometry:
    paths: list
    commands: tuple
    ink_bounds: tuple
    image_bounds: tuple
    guides: tuple


def geometry(result, fit, horizontal, metrics):
    paths = place(result, fit.height, fit.bottom, horizontal)
    commands = []
    for path in paths:
        parts = list(segments(path))
        commands.append(('M', (parts[0][0]['x'], parts[0][0]['y'])))
        for _, controls, end in parts:
            points = controls + [end]
            commands.append(('C' if controls else 'L', tuple(v for p in points for v in (p['x'], p['y']))))
        commands.append(('Z', ()))
    x0, y0, _, y1 = result['bounds']
    scale = fit.height / (y1-y0)
    source = result['source']
    image_bounds = (-scale*x0+horizontal, -scale*y0+fit.bottom,
                    scale*(1088*source['width']/source['height']-x0)+horizontal,
                    scale*(1088-y0)+fit.bottom)
    return PreviewGeometry(paths, tuple(commands), tuple(tight_bounds(paths)), image_bounds, metrics.guides())


class OverlayBinding:
    """Only callback registration and cached target identity; no font mutation.

    The controller revalidates targets outside drawing. Membership is checked on
    its timer and before Apply; drawing uses only cached native object identity.
    """
    def __init__(self, add, remove, redraw, callback, hook, same):
        self.add, self.remove, self.redraw = add, remove, redraw
        self.callback, self.hook, self.same = callback, hook, same
        self.registered = False
        self.closed = False
        self.owner = None
        self.destination = None
        self.payload = None

    def publish(self, owner, destination, payload, enabled=True):
        if self.closed:
            return
        self.owner, self.destination = owner, destination
        self.payload = payload if enabled else None
        if self.payload is not None and not self.registered:
            self.add(self.callback, self.hook)
            self.registered = True
        elif self.payload is None and self.registered:
            self.remove(self.callback)
            self.registered = False
        self.redraw()

    def matches(self, layer):
        return (not self.closed and self.payload is not None and
                (self.same(layer, self.owner) or self.same(layer, self.destination)))

    def clear(self):
        self.publish(None, None, None, False)

    def close(self):
        self.clear()
        self.closed = True
