# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Regress Glyphs' lazy default-crop initialization and retain stale guards."""
from types import SimpleNamespace
import unittest
from test_adapter import FakeHost, Path
from beztrace_companion.adapter import capture, revalidate
from beztrace_companion.contract import CompanionError
from beztrace_companion.native import GlyphsHost


class LazyImage:
    def __init__(self, crop=((0, 0), (0, 0)), readable=True):
        self.path='/tmp/input.png'
        self.transform=(2, 0, 0, 2, 40, 100)
        self.alpha=1.0
        self.crop=crop
        self.locked=False
        self.readable=readable
        self.loaded=False
        self.bitmap=object()

    @property
    def image(self):
        if not self.readable:
            return None
        if not self.loaded:
            self.loaded=True
            if self.crop == ((0, 0), (0, 0)):
                self.crop=((0, 0), (160, 180))
        return self.bitmap


class LazyImageTests(unittest.TestCase):
    def host(self, image):
        native=GlyphsHost.__new__(GlyphsHost)
        native.Path=Path
        host=FakeHost()
        host.owner=SimpleNamespace(shapes=[], width=700, anchors=[], guides=[],
                                  annotations=[], hints=[], backgroundImage=image)
        host.fingerprint=native.fingerprint
        return native, host

    def test_first_capture_survives_native_bitmap_snapshot(self):
        image=LazyImage()
        native, host=self.host(image)
        target=capture(host, 'foreground')
        # image_io.snapshot reads this native property before starting the worker.
        bitmap=image.image
        self.assertIs(bitmap, image.bitmap)
        self.assertEqual(image.crop, ((0, 0), (160, 180)))
        revalidate(host, target)
        self.assertEqual(target.fingerprint, native.fingerprint(host.owner))

    def test_explicit_crop_is_preserved_on_first_load(self):
        crop=((10, 20), (80, 90))
        image=LazyImage(crop)
        native, host=self.host(image)
        target=capture(host, 'foreground')
        self.assertTrue(image.loaded)
        self.assertEqual(image.crop, crop)
        image.image
        revalidate(host, target)
        self.assertEqual(native.image_state(image)[3], ('crop', crop))

    def test_real_image_edits_still_invalidate_pending_result(self):
        for field, value in (('crop', ((10, 20), (80, 90))),
                             ('transform', (1, 0, 0, 1, 0, 0)),
                             ('path', '/tmp/other.png'), ('alpha', 0.5),
                             ('locked', True)):
            with self.subTest(field=field):
                image=LazyImage()
                _, host=self.host(image)
                target=capture(host, 'foreground')
                setattr(image, field, value)
                with self.assertRaisesRegex(CompanionError, 'destination changed'):
                    revalidate(host, target)

    def test_unreadable_image_fails_before_target_capture(self):
        _, host=self.host(LazyImage(readable=False))
        with self.assertRaisesRegex(CompanionError, 'cannot be loaded'):
            capture(host, 'foreground')
        self.assertEqual(host.events, [])

    def test_layer_without_image_can_still_be_captured(self):
        native, host=self.host(None)
        revalidate(host, capture(host, 'foreground'))
        self.assertIsNone(native.image_state(None))


if __name__ == '__main__':
    unittest.main()
