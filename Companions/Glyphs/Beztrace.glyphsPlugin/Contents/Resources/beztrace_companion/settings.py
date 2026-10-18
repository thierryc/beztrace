# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Pure trace-setting presets, validation and persistence payloads."""
import math
from dataclasses import dataclass, replace

SCHEMA_VERSION = 1
GRID_VALUES = (0, 1, 2, 4, 8)
PRESETS = {
    'Balanced': dict(accuracy=2.0, smoothing=1.0, corner_threshold=12.0,
                     grid=2, min_contour_area=100.0, refine_raster=True),
    'Sharp': dict(accuracy=1.0, smoothing=0.7, corner_threshold=10.0,
                  grid=1, min_contour_area=100.0, refine_raster=True),
    'Smooth Detail': dict(accuracy=0.75, smoothing=1.5, corner_threshold=30.0,
                          grid=0, min_contour_area=100.0, refine_raster=True),
}


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def native_preference_value(value):
    """Normalize NSNumber subclasses only at the native preferences boundary.

    Keep booleans, strings and malformed fields intact so contract validation
    still rejects coercible but invalid values rather than silently accepting them.
    """
    if value is None:
        return None
    result = dict(value)
    for key, item in result.items():
        if isinstance(item, bool):
            continue
        if isinstance(item, int):
            result[key] = int(item)
        elif isinstance(item, float):
            result[key] = float(item)
    return result


def quantize_slider(value, minimum, maximum, step):
    if not all(_number(number) for number in (value, minimum, maximum, step)) or step <= 0 or minimum > maximum:
        raise ValueError('Invalid slider range')
    stepped = round(value / step) * step
    places = len(('%0.12f' % step).rstrip('0').partition('.')[2])
    stepped = round(stepped, places)
    return min(max(stepped, minimum), maximum)


@dataclass(frozen=True)
class TraceSettings:
    threshold: object = 'auto'
    invert: bool = False
    accuracy: float = 2.0
    smoothing: float = 1.0
    corner_threshold: float = 12.0
    grid: int = 2
    min_contour_area: float = 100.0
    refine_raster: bool = True

    def validate(self):
        if self.threshold != 'auto' and not (type(self.threshold) is int and 0 <= self.threshold <= 255):
            raise ValueError('Threshold must be auto or an integer from 0 to 255')
        if type(self.invert) is not bool or type(self.refine_raster) is not bool:
            raise ValueError('Invert and raster refinement must be on or off')
        if not _number(self.accuracy) or not 0.5 <= self.accuracy <= 3.0:
            raise ValueError('Accuracy must be from 0.5 to 3.0')
        if not _number(self.smoothing) or not 0.25 <= self.smoothing <= 3.0:
            raise ValueError('Smoothing must be from 0.25 to 3.0')
        if (not _number(self.corner_threshold) or not 1 <= self.corner_threshold <= 60
                or not float(self.corner_threshold).is_integer()):
            raise ValueError('Corner sensitivity must be a whole number from 1 to 60 degrees')
        if type(self.grid) is not int or self.grid not in GRID_VALUES:
            raise ValueError('Grid must be None, 1, 2, 4, or 8')
        if not _number(self.min_contour_area) or not 0 <= self.min_contour_area <= 1000:
            raise ValueError('Remove specks must be from 0 to 1000')
        return self

    @property
    def preset(self):
        values = self.advanced_values()
        for name, preset in PRESETS.items():
            if all(values[key] == value for key, value in preset.items()):
                return name
        return 'Custom'

    def advanced_values(self):
        return {key: getattr(self, key) for key in next(iter(PRESETS.values()))}

    def applying_preset(self, name):
        if name not in PRESETS:
            raise ValueError('Unknown quality preset')
        return replace(self, **PRESETS[name]).validate()

    def engine_options(self):
        self.validate()
        return dict(threshold=self.threshold, invert=self.invert, accuracy=self.accuracy,
                    smoothing=self.smoothing, corner_threshold=self.corner_threshold,
                    grid=self.grid, min_contour_area=self.min_contour_area,
                    refine_raster=self.refine_raster)

    def persistent_value(self, advanced=False):
        value = dict(schemaVersion=SCHEMA_VERSION, advanced=bool(advanced), preset=self.preset)
        value.update(self.engine_options())
        return value

    @classmethod
    def from_persistent_value(cls, value):
        if not isinstance(value, dict) or value.get('schemaVersion') != SCHEMA_VERSION:
            return cls(), False
        try:
            settings = cls(threshold=value['threshold'], invert=value['invert'],
                           accuracy=value['accuracy'], smoothing=value['smoothing'],
                           corner_threshold=value['corner_threshold'], grid=value['grid'],
                           min_contour_area=value['min_contour_area'],
                           refine_raster=value['refine_raster']).validate()
            if value.get('preset') != settings.preset or type(value.get('advanced')) is not bool:
                raise ValueError('Inconsistent saved settings')
            return settings, value['advanced']
        except (KeyError, TypeError, ValueError):
            return cls(), False
