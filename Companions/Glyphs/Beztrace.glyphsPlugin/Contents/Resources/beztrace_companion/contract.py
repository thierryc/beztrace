# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Strict released-contract validation and pure geometry; no Glyphs imports."""
import copy
import hashlib
import json
import math
import re
from pathlib import Path

ENGINE_VERSION = '0.1.0'
ENGINE_VERSIONS = ('0.1.0', '0.1.1-dev.1', '0.1.1-dev.2', '0.1.1-dev.3', '0.1.1-dev.4')
MAX_INPUT = 16 * 1024 * 1024
MAX_OUTPUT = 32 * 1024 * 1024
MAX_NODES = 100000


class CompanionError(Exception):
    pass


def combined_warning(result, extra=None):
    messages = list(result.get('warnings', ()))
    if extra:
        messages.append(extra)
    return ' '.join(messages) or None


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate_schema(value, schema, root=None, path='$'):
    """Implement precisely the keywords used by the bundled, pinned v1 schema.

    Packaging tests reject unknown keywords, so schema growth cannot silently
    disable validation. No external JSON-schema package is needed in Glyphs.
    """
    root = root or schema
    if '$ref' in schema:
        target = root
        for key in schema['$ref'].split('/')[1:]:
            target = target[key]
        return validate_schema(value, target, root, path)
    if 'oneOf' in schema:
        matches = 0
        for candidate in schema['oneOf']:
            try:
                validate_schema(value, candidate, root, path)
                matches += 1
            except CompanionError:
                pass
        if matches != 1:
            raise CompanionError(path + ': invalid variant')
    kind = schema.get('type')
    valid = {'object': lambda: type(value) is dict,
             'array': lambda: type(value) is list,
             'string': lambda: type(value) is str,
             'integer': lambda: type(value) is int,
             'number': lambda: number(value),
             'boolean': lambda: type(value) is bool,
             'null': lambda: value is None}
    if kind and not valid[kind]():
        raise CompanionError(path + ': expected ' + kind)
    if 'const' in schema and (type(value) is not type(schema['const']) or value != schema['const']):
        raise CompanionError(path + ': unsupported value')
    if 'enum' in schema and value not in schema['enum']:
        raise CompanionError(path + ': unsupported value')
    if type(value) is dict:
        for key in schema.get('required', []):
            if key not in value:
                raise CompanionError(path + ': missing ' + key)
        properties = schema.get('properties', {})
        for key, item in value.items():
            rule = properties.get(key, schema.get('additionalProperties', {}))
            if rule is False:
                raise CompanionError(path + ': unexpected ' + key)
            if isinstance(rule, dict):
                validate_schema(item, rule, root, path + '.' + key)
    if type(value) is list:
        if len(value) < schema.get('minItems', 0) or len(value) > schema.get('maxItems', MAX_NODES):
            raise CompanionError(path + ': invalid array size')
        for index, item in enumerate(value):
            prefix = schema.get('prefixItems', [])
            rule = prefix[index] if index < len(prefix) else schema.get('items', {})
            validate_schema(item, rule, root, path + '[' + str(index) + ']')
    if number(value):
        for key, check in [('minimum', lambda a, b: a >= b), ('maximum', lambda a, b: a <= b),
                           ('exclusiveMinimum', lambda a, b: a > b), ('exclusiveMaximum', lambda a, b: a < b)]:
            if key in schema and not check(value, schema[key]):
                raise CompanionError(path + ': out of range')
    if isinstance(value, str) and 'pattern' in schema and not re.fullmatch(schema['pattern'], value):
        raise CompanionError(path + ': invalid format')


def segments(contour):
    """Yield (start, controls, endpoint) including the cyclic closing segment."""
    nodes = contour['nodes']
    oncurves = [i for i, n in enumerate(nodes) if n['type'] != 'offcurve']
    if len(oncurves) < 2:
        raise CompanionError('Contour needs at least two on-curve nodes')
    start_index = oncurves[0]
    previous = nodes[start_index]
    controls = []
    for offset in range(1, len(nodes) + 1):
        node = nodes[(start_index + offset) % len(nodes)]
        if node['type'] == 'offcurve':
            controls.append(node)
            if len(controls) > 2:
                raise CompanionError('A cubic requires exactly two handles')
            continue
        if len(controls) != (2 if node['type'] == 'curve' else 0):
            raise CompanionError('Invalid cyclic line/cubic node order')
        if previous['x'] == node['x'] and previous['y'] == node['y']:
            raise CompanionError('Degenerate segment')
        yield previous, controls, node
        previous, controls = node, []


def _coefficients(points):
    if len(points) == 2:
        return [points[0], points[1] - points[0]]
    a, b, c, d = points
    return [a, 3*(b-a), 3*(a-2*b+c), -a+3*b-3*c+d]


def signed_area(contour):
    # Exact polynomial integral of (x dy - y dx)/2, including cubic handles.
    total = 0.0
    for a, controls, b in segments(contour):
        points = [a] + controls + [b]
        x = _coefficients([p['x'] for p in points])
        y = _coefficients([p['y'] for p in points])
        for i in range(len(x)):
            for j in range(1, len(y)):
                total += (x[i]*j*y[j] - y[i]*j*x[j]) / (i+j)
    return total / 2


def tight_bounds(paths):
    xs, ys = [], []
    for path in paths:
        for a, controls, b in segments(path):
            for axis, output in [('x', xs), ('y', ys)]:
                coeff = _coefficients([p[axis] for p in [a] + controls + [b]])
                output.extend([a[axis], b[axis]])
                if not controls:
                    continue
                _, c, bb, aa = coeff
                qa, qb, qc = 3*aa, 2*bb, c
                roots = []
                if abs(qa) < 1e-12:
                    if abs(qb) > 1e-12:
                        roots = [-qc/qb]
                else:
                    disc = qb*qb-4*qa*qc
                    if disc >= 0:
                        roots = [(-qb-math.sqrt(disc))/(2*qa), (-qb+math.sqrt(disc))/(2*qa)]
                for t in roots:
                    if 0 < t < 1:
                        output.append(sum(v*t**i for i, v in enumerate(coeff)))
    return [min(xs), min(ys), max(xs), max(ys)]


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CompanionError('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse_result(data, image_bytes, expected_engine_version=None):
    if len(data) > MAX_OUTPUT:
        raise CompanionError('Engine output exceeds 32 MiB')
    try:
        result = json.loads(data, object_pairs_hook=_unique,
                            parse_constant=lambda x: (_ for _ in ()).throw(CompanionError('Non-finite JSON')))
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise CompanionError('Malformed engine JSON: ' + str(exc)) from exc
    schema = json.loads((Path(__file__).resolve().parent.parent / 'trace-result-v1.schema.json').read_text())
    try:
        validate_schema(result, schema)
    except RecursionError as exc:
        raise CompanionError('Engine JSON nesting is too deep') from exc
    if result['engine']['version'] not in ENGINE_VERSIONS:
        raise CompanionError('Unsupported beztrace engine version')
    if expected_engine_version is not None and result['engine']['version'] != expected_engine_version:
        raise CompanionError('Engine JSON version does not match executable version')
    if result['source']['sha256'] != hashlib.sha256(image_bytes).hexdigest():
        raise CompanionError('Engine result does not match the selected image')
    if result['placement'] is not None or result['resolvedOptions']['targetHeight'] != 1088:
        raise CompanionError('Expected neutral, unplaced engine coordinates')
    counts = {'contourCount': len(result['paths']), 'nodeCount': 0,
              'lineCount': 0, 'curveCount': 0, 'offCurveCount': 0}
    names = {'line': 'lineCount', 'curve': 'curveCount', 'offcurve': 'offCurveCount'}
    for path in result['paths']:
        counts['nodeCount'] += len(path['nodes'])
        if counts['nodeCount'] > MAX_NODES:
            raise CompanionError('Trace exceeds the companion limit of 100,000 nodes')
        for node in path['nodes']:
            if max(abs(node['x']), abs(node['y'])) > 1e7:
                raise CompanionError('Unreasonable coordinate magnitude')
            if node['type'] == 'offcurve' and node['smooth']:
                raise CompanionError('Off-curve nodes cannot be smooth')
            counts[names[node['type']]] += 1
        if abs(signed_area(path)) < 1e-9:
            raise CompanionError('Degenerate contour area')
    if counts != result['statistics']:
        raise CompanionError('Engine statistics do not match paths')
    actual = tight_bounds(result['paths'])
    if result['bounds'] is None or any(abs(a-b) > 1e-5 for a,b in zip(actual, result['bounds'])):
        raise CompanionError('Engine bounds do not match paths')
    if actual[3] <= actual[1] or actual[2] <= actual[0]:
        raise CompanionError('Empty ink bounds')
    return result


def place(result, height=700.0, baseline=0.0, horizontal=0.0):
    if not all(number(v) for v in (height, baseline, horizontal)) or height <= 0:
        raise CompanionError('Height must be positive; placement values must be finite')
    if max(height, abs(baseline), abs(horizontal)) > 1e6:
        raise CompanionError('Placement exceeds 1,000,000 units')
    if result.get('placement') is not None:
        raise CompanionError('Cannot place an already placed result')
    x0, y0, _, y1 = result['bounds']
    if y1 <= y0:
        raise CompanionError('Empty ink bounds')
    scale = height / (y1-y0)
    paths = copy.deepcopy(result['paths'])
    for path in paths:
        for n in path['nodes']:
            n['x'] = scale * (n['x']-x0) + horizontal
            n['y'] = scale * (n['y']-y0) + baseline
            if not number(n['x']) or not number(n['y']) or max(abs(n['x']),abs(n['y'])) > 1e7:
                raise CompanionError('Placement produced an invalid coordinate')
    return paths
