# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import unittest
from dataclasses import replace
from test_contract import ROOT
from beztrace_companion.settings import GRID_VALUES,PRESETS,TraceSettings,quantize_slider


class SettingsTests(unittest.TestCase):
    def test_presets_and_custom_detection(self):
        settings=TraceSettings(threshold=149,invert=True)
        for name,values in PRESETS.items():
            result=settings.applying_preset(name)
            self.assertEqual(result.preset,name)
            self.assertEqual(result.threshold,149)
            self.assertTrue(result.invert)
            for key,value in values.items(): self.assertEqual(getattr(result,key),value)
        self.assertEqual(replace(settings,accuracy=1.25).preset,'Custom')
        with self.assertRaises(ValueError): settings.applying_preset('Missing')

    def test_boundaries_and_engine_options(self):
        for settings in [
            TraceSettings(threshold=0,accuracy=.5,smoothing=.25,corner_threshold=1,
                          grid=0,min_contour_area=0),
            TraceSettings(threshold=255,accuracy=3,smoothing=3,corner_threshold=60,
                          grid=8,min_contour_area=1000),
        ]:
            self.assertEqual(settings.validate(),settings)
            self.assertEqual(settings.engine_options()['threshold'],settings.threshold)
        invalid=[dict(threshold=256),dict(invert=1),dict(accuracy=.49),dict(accuracy=3.01),
                 dict(smoothing=.24),dict(corner_threshold=12.5),dict(corner_threshold=61),dict(grid=3),
                 dict(min_contour_area=-1),dict(min_contour_area=1001),dict(refine_raster=1)]
        for values in invalid:
            with self.subTest(values=values),self.assertRaises(ValueError):
                replace(TraceSettings(),**values).validate()
        self.assertEqual(GRID_VALUES,(0,1,2,4,8))

    def test_slider_quantization_clamps_to_valid_ranges(self):
        self.assertEqual(quantize_slider(.25,.25,3,.1),.25)
        self.assertEqual(quantize_slider(.26,.25,3,.1),.3)
        self.assertEqual(quantize_slider(3.1,.25,3,.1),3)
        self.assertEqual(quantize_slider(.49,.5,3,.25),.5)
        self.assertEqual(quantize_slider(1.2,.5,3,.25),1.25)
        with self.assertRaises(ValueError): quantize_slider(1,0,1,0)

    def test_persistence_round_trip_and_fallback(self):
        settings=TraceSettings(threshold=128,invert=True).applying_preset('Smooth Detail')
        value=settings.persistent_value(advanced=True)
        self.assertEqual(TraceSettings.from_persistent_value(value),(settings,True))
        for broken in [None,{},dict(value,schemaVersion=2),dict(value,accuracy=99),
                       dict(value,preset='Balanced'),dict(value,advanced=1)]:
            self.assertEqual(TraceSettings.from_persistent_value(broken),(TraceSettings(),False))


if __name__=='__main__': unittest.main()
