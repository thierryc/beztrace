# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
import copy
import unittest
from test_contract import sample,contour
from beztrace_companion.canvas import ImageGeometry,transform_paths,fitted_transform
from beztrace_companion.contract import CompanionError,signed_area
from beztrace_companion.placement import ResolvedFit


class CanvasTests(unittest.TestCase):
    def test_padding_is_preserved_and_ink_is_not_refitted(self):
        result=sample()
        geometry=ImageGeometry((100,100),(0,0,100,100),(2,0,0,2,40,-70))
        node=transform_paths(result,geometry)[0]['nodes'][0]
        self.assertAlmostEqual(node['x'],40+20/10.88)
        self.assertAlmostEqual(node['y'],-70+40/10.88)
        self.assertEqual(result,sample())

    def test_cropped_fractional_image_affine_on_every_node(self):
        result=sample(); result['source'].update(width=200,height=100)
        result['paths']=[contour([(0,0),(2176,0),(2176,1088),(0,1088)],['curve','line','offcurve','offcurve'])]
        result['paths'][0]['nodes'][0]['smooth']=True
        geometry=ImageGeometry((300,200),(20.5,40.25,100,80),(1,.25,-.5,2,9,-30))
        points=[(20.5,40.25),(120.5,40.25),(120.5,120.25),(20.5,120.25)]
        output=transform_paths(result,geometry)[0]
        self.assertTrue(output['closed']); self.assertTrue(output['nodes'][0]['smooth'])
        for node,(x,y) in zip(output['nodes'],points):
            self.assertAlmostEqual(node['x'],x-.5*y+9)
            self.assertAlmostEqual(node['y'],.25*x+2*y-30)

    def test_rotation_reflection_holes_and_nonuniform_scale(self):
        data=sample(); data['paths'].append(contour([(30,40),(90,40),(90,100),(30,100)]))
        for matrix in [(0,1,-1,0,30,50),(-2,0,0,3,0,0),(1,.3,.2,2,-40,-50)]:
            mapped=transform_paths(data,ImageGeometry((100,100),(0,0,100,100),matrix))
            det=matrix[0]*matrix[3]-matrix[1]*matrix[2]
            for before,after in zip(data['paths'],mapped):
                self.assertGreater(signed_area(before)*signed_area(after)*det,0)
            self.assertLess(signed_area(mapped[0])*signed_area(mapped[1]),0)

    def test_invalid_crop_transform_and_placed_output(self):
        for g in [ImageGeometry((100,100),(0,0,0,100),(1,0,0,1,0,0)),
                  ImageGeometry((100,100),(-1,0,100,100),(1,0,0,1,0,0)),
                  ImageGeometry((100,100),(0,0,100,100),(1,2,2,4,0,0)),
                  ImageGeometry((100,100),(0,0,100,100),(1,0,0,float('nan'),0,0))]:
            with self.assertRaises(CompanionError): transform_paths(sample(),g)
        data=sample(); data['placement']={}
        with self.assertRaises(CompanionError): transform_paths(data,ImageGeometry((100,100),(0,0,100,100),(1,0,0,1,0,0)))

    def test_agent_ink_fit_and_dpi_logical_size(self):
        fit=ResolvedFit(700,-120,'Custom')
        for size in [(100,100),(50,50),(120,80)]:
            matrix=fitted_transform(sample(),size,fit,40)
            mapped=transform_paths(sample(),ImageGeometry(size,(0,0,*size),matrix))
            xs=[n['x'] for n in mapped[0]['nodes']]; ys=[n['y'] for n in mapped[0]['nodes']]
            self.assertAlmostEqual(min(xs),40); self.assertAlmostEqual(min(ys),-120)
            self.assertAlmostEqual(max(ys),580)

    def test_agent_fit_preserves_native_image_aspect_ratio(self):
        matrix=fitted_transform(sample(),(120,80),ResolvedFit(700,0,'Custom'),0)
        self.assertEqual(matrix[0],matrix[3])
