# encoding: utf-8
# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
# GeneralPlugin entry point adapted from GlyphsSDK (Apache-2.0).
# See GlyphsSDK-LICENSE.txt and GlyphsSDK-SOURCE.json for pinned provenance.
import objc
import sys
import platform
from AppKit import NSMenuItem, NSAlert
from GlyphsApp import Glyphs, PATH_MENU
from GlyphsApp.plugins import GeneralPlugin


class BeztracePlugin(GeneralPlugin):
    @objc.python_method
    def settings(self):
        self.name = 'Beztrace'
        self.controller = None
        self.matchingController = None

    @objc.python_method
    def start(self):
        self.menuItem = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_('Beztrace…','showTrace:', '')
        self.menuItem.setTarget_(self)
        Glyphs.menu[PATH_MENU].append(self.menuItem)
        self.matchingMenuItem = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_('Beztrace Match Masters…','showMatching:', '')
        self.matchingMenuItem.setTarget_(self)
        Glyphs.menu[PATH_MENU].append(self.matchingMenuItem)

    def showMatching_(self,sender):
        try:
            from beztrace_companion.matching_ui import MatchingWindowController
            if self.matchingController is None or self.matchingController.closed:
                self.matchingController = MatchingWindowController.alloc().init()
            self.matchingController.mode.setSelectedSegment_(3)
            self.matchingController.modeChanged_(None)
            self.matchingController.showWindow_(self)
            self.matchingController.window().makeKeyAndOrderFront_(self)
        except Exception as exc:
            alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace matching could not open')
            alert.setInformativeText_(str(exc)); alert.runModal()

    def showTrace_(self,sender):
        try:
            if sys.version_info < (3, 9):
                raise RuntimeError('Beztrace requires a Glyphs Python runtime version 3.9 or later')
            if int(platform.mac_ver()[0].split('.')[0]) < 13:
                raise RuntimeError('Beztrace requires macOS 13 or later')
            from beztrace_companion.matching_ui import MatchingWindowController
            if self.matchingController is None or self.matchingController.closed:
                self.matchingController = MatchingWindowController.alloc().init()
            self.matchingController.mode.setSelectedSegment_(0)
            self.matchingController.modeChanged_(None)
            self.matchingController.showWindow_(self)
            self.matchingController.window().makeKeyAndOrderFront_(self)
        except Exception as exc:
            alert = NSAlert.alloc().init()
            alert.setMessageText_('Beztrace could not open')
            alert.setInformativeText_(str(exc)); alert.runModal()

    @objc.python_method
    def __file__(self):
        return __file__
