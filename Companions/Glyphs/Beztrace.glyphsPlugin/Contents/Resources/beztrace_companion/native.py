# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Glyphs 4 boundary. All methods are called on the AppKit main thread."""
import copy
from .contract import CompanionError, signed_area
from .placement import GlyphClass, metric_snapshot


def _value(v):
    if v is None or isinstance(v, (str, bool, int, float)):
        return v
    if hasattr(v, 'keys'):
        return tuple(sorted((str(k), _value(v[k])) for k in v.keys()))
    try:
        return tuple(_value(x) for x in v)
    except TypeError:
        # Native value descriptions (colors, dates, points); never used as identity.
        return str(v)


def _properties(obj, names):
    return tuple((key, _value(getattr(obj, key, None))) for key in names)


class GlyphsHost:
    def __init__(self):
        from GlyphsApp import Glyphs, GSPath, GSNode, GSBackgroundLayer, LINE, CURVE, OFFCURVE
        from Foundation import NSThread
        import objc
        self.same = lambda a, b: a is not None and b is not None and objc.pyobjc_id(a) == objc.pyobjc_id(b)
        self.app, self.Path, self.Node, self.Background = Glyphs, GSPath, GSNode, GSBackgroundLayer
        self.types = {'line': LINE, 'curve': CURVE, 'offcurve': OFFCURVE}
        self.thread = NSThread
        if int(Glyphs.buildNumber) < 4107 or int(Glyphs.versionNumber) != 4:
            raise CompanionError('Beztrace requires Glyphs 4.1 build 4107 or later in Glyphs 4')

    def assert_main(self):
        if not self.thread.isMainThread():
            raise CompanionError('Native font access must run on the main thread')

    def current(self):
        self.assert_main()
        font = self.app.font
        if font is None or font.parent is None:
            raise CompanionError('Open a font and select one glyph layer')
        selected = list(font.selectedLayers or [])
        if len(selected) != 1:
            raise CompanionError('Select exactly one glyph layer')
        layer = selected[0]
        glyph = layer.parent
        if isinstance(layer, self.Background):
            candidates = [l for l in glyph.layers if self.same(l.background, layer)]
            if len(candidates) != 1:
                raise CompanionError('Cannot resolve the owning layer of this background')
            layer = candidates[0]
        if not any(self.same(l, layer) for l in glyph.layers):
            raise CompanionError('Select a stored glyph layer, not a generated preview')
        return font.parent, font, glyph, layer

    def destination(self, owner, destination):
        return owner if destination == 'foreground' else owner.background

    def check_editable(self, glyph, layer):
        if glyph.locked:
            raise CompanionError('Unlock the target glyph before tracing')
        if layer is None:
            raise CompanionError('Destination layer is unavailable')
        self.rounding_state(layer)

    def check_replace(self, layer):
        if any(p.locked for p in layer.paths):
            raise CompanionError('Unlock existing paths before replacing them')
        if len(layer.hints):
            raise CompanionError('This layer has hints that may reference existing paths. Use Append or remove the hints explicitly before replacement.')

    def identity(self, glyph, owner):
        return str(glyph.id), str(owner.layerId)

    def contains(self, target):
        if not any(self.same(d, target.document) for d in self.app.documents):
            return False
        if not self.same(target.font.parent, target.document) or not self.same(target.glyph.parent, target.font):
            return False
        if not any(self.same(g, target.glyph) for g in target.font.glyphs):
            return False
        if not any(self.same(l, target.owner) for l in target.glyph.layers):
            return False
        return (self.identity(target.glyph, target.owner) == target.identity
                and self.same(self.destination(target.owner, target.destination), target.layer))

    def label(self, document, font, glyph, owner):
        return '%s / %s / %s' % (document.displayName(), glyph.name, owner.name)

    def classification(self, glyph):
        from GlyphsApp import GSUppercase, GSLowercase
        case = 'upper' if glyph.case == GSUppercase else 'lower' if glyph.case == GSLowercase else ''
        return GlyphClass(str(glyph.name), str(glyph.unicode or ''), case, str(glyph.category or ''))

    def metrics(self, owner):
        from GlyphsApp import (GSMetricsTypeBaseline, GSMetricsTypeCapHeight,
            GSMetricsTypexHeight, GSMetricsTypeAscender, GSMetricsTypeDescender)
        types = {GSMetricsTypeBaseline: 'baseline', GSMetricsTypeCapHeight: 'capHeight',
                 GSMetricsTypexHeight: 'xHeight', GSMetricsTypeAscender: 'ascender',
                 GSMetricsTypeDescender: 'descender'}
        return self.read_metrics(owner, types)

    def read_metrics(self, owner, types):
        self.assert_main()
        layer_values = {}
        for store in owner.metrics or []:
            metric = store.metric
            key = types.get(metric.type) if metric is not None else None
            if key:
                layer_values.setdefault(key, []).append((store.position, store.filter is not None))
        master = owner.master
        defaults = {key: getattr(master, key, None) for key in ('capHeight', 'xHeight', 'ascender', 'descender')}
        # Baseline is the font coordinate origin unless an explicit metric exists.
        defaults['baseline'] = 0.0
        if master is not None:
            general = {}
            for metric in owner.parent.parent.metrics:
                key = types.get(metric.type)
                if key and metric.filter is None:
                    store = master.metrics[metric.id]
                    general.setdefault(key, []).append((store.position if store else None, False))
            resolved_master = metric_snapshot(general, defaults)
            defaults = dict(resolved_master.values)
        return metric_snapshot(layer_values, defaults)

    def path_data(self, path):
        inverse = {v: k for k, v in self.types.items()}
        return {'closed': bool(path.closed), 'nodes': [dict(x=float(n.position.x), y=float(n.position.y),
                type=inverse[n.type], smooth=bool(n.smooth)) for n in path.nodes]}

    def shape_state(self, shape):
        if isinstance(shape, self.Path):
            return ('path', self.path_data(shape), _properties(shape, ['locked','attributes']),
                    tuple(_properties(n, ['name','userData']) for n in shape.nodes))
        return ('component', _properties(shape, ['componentName','transform','alignment','locked',
                                               'smartComponentValues','attributes']))

    def preserved_state(self, layer):
        return (_properties(layer, ['width','vertWidth','leftMetricsKey','rightMetricsKey','widthMetricsKey',
                                    'topMetricsKey','bottomMetricsKey','attributes','userData','color',
                                    'associatedMasterId','layerId','name']),
                tuple(_properties(a, ['name','position','userData']) for a in layer.anchors),
                tuple(_properties(g, ['position','angle','name','locked']) for g in layer.guides),
                tuple(_properties(a, ['position','text','type','width','angle']) for a in layer.annotations),
                tuple(_properties(h, ['type','origin','target','other1','other2','horizontal','options','name','scale']) for h in layer.hints),
                _properties(layer.backgroundImage, ['path','transform','alpha','crop','locked']) if layer.backgroundImage else None)

    def fingerprint(self, layer):
        return copy.deepcopy((tuple(self.shape_state(s) for s in layer.shapes), self.preserved_state(layer)))

    def snapshot(self, layer):
        return {'layer': layer.copy(), 'shapes': list(layer.shapes),
                'shapeStates': copy.deepcopy([self.shape_state(s) for s in layer.shapes]),
                'preserved': copy.deepcopy(self.preserved_state(layer)), 'width': layer.width}

    def make_paths(self, paths):
        result = []
        for contour in paths:
            path = self.Path()
            for n in contour['nodes']:
                node = self.Node((n['x'], n['y']), self.types[n['type']])
                node.smooth = n['smooth']
                path.nodes.append(node)
            path.closed = contour['closed']
            result.append(path)
        return result

    def rounding_state(self, layer):
        getter = getattr(layer, 'temporarilyDisableRounding', None)
        setter = getattr(layer, 'setTemporarilyDisableRounding_', None)
        if getter is None or not callable(setter):
            raise CompanionError('Required native precision API is unavailable on this Glyphs build')
        return bool(getter() if callable(getter) else getter)

    def set_rounding(self, layer, value):
        layer.setTemporarilyDisableRounding_(value)

    def begin_undo(self, glyph):
        glyph.beginUndo()

    def end_undo(self, glyph):
        glyph.endUndo()

    def insert(self, layer, paths, replace):
        width = layer.width
        if replace:
            for i in reversed(range(len(layer.shapes))):
                if isinstance(layer.shapes[i], self.Path):
                    del layer.shapes[i]
        for path in paths:
            layer.shapes.append(path)
        # Component alignment can affect metrics; preserve the captured width.
        if layer.width != width:
            layer.width = width

    def restore(self, layer, snapshot):
        # Keep original native objects (including hint references) when intact.
        originals = snapshot['shapes']
        if [self.shape_state(s) for s in originals] != snapshot['shapeStates']:
            originals = [s.copy() for s in snapshot['layer'].shapes]
        layer.shapes = originals
        layer.width = snapshot['width']

    def verify(self, layer, native, expected, snapshot, replace):
        shapes = list(layer.shapes)
        survivors = [s for s in snapshot['shapes'] if not (replace and isinstance(s, self.Path))]
        if len(shapes) != len(survivors) + len(native) or not all(self.same(a, b) for a, b in zip(shapes, survivors)):
            raise CompanionError('Native insertion changed existing shape order or identity')
        survivor_states = [state for s, state in zip(snapshot['shapes'], snapshot['shapeStates'])
                           if not (replace and isinstance(s, self.Path))]
        if [self.shape_state(s) for s in survivors] != survivor_states:
            raise CompanionError('Native insertion changed existing shapes')
        if self.preserved_state(layer) != snapshot['preserved']:
            raise CompanionError('Native insertion changed non-path layer data')
        for path, wanted in zip(shapes[len(survivors):], expected):
            actual = self.path_data(path)
            if actual['closed'] != wanted['closed'] or len(actual['nodes']) != len(wanted['nodes']):
                raise CompanionError('Native path structure differs from the preview')
            for a, b in zip(actual['nodes'], wanted['nodes']):
                if a['type'] != b['type'] or a['smooth'] != b['smooth'] or abs(a['x']-b['x']) > 1e-7 or abs(a['y']-b['y']) > 1e-7:
                    raise CompanionError('Native node differs from the preview (tolerance 1e-7 units)')
            area = signed_area(wanted)
            if signed_area(actual)*area <= 0 or int(path.direction) != (1 if area < 0 else -1):
                raise CompanionError('Native contour direction differs from the preview')

    def redraw(self):
        self.app.redraw()
