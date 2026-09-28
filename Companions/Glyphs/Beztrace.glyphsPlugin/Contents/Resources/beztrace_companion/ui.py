# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Small native canvas-image tracer. Placement belongs to Glyphs."""
import queue
import threading
import time
import traceback
from pathlib import Path
import objc
from AppKit import (NSWindowController, NSPanel, NSButton, NSTextField, NSPopUpButton,
    NSAlert, NSOpenPanel, NSMenu, NSMenuItem, NSFont, NSProgressIndicator,
    NSWindowStyleMaskTitled, NSWindowStyleMaskClosable, NSWindowStyleMaskUtilityWindow,
    NSBackingStoreBuffered, NSFloatingWindowLevel, NSModalResponseOK, NSButtonTypeSwitch)
from Foundation import NSTimer
from .contract import CompanionError
from .engine import DEFAULT_ENGINE, trace, arguments
from .native import GlyphsHost
from .adapter import revalidate, apply_paths, apply_image, RecoveryError
from .session import Session
from .canvas import transform_paths
from . import image_io


class BeztraceWindowController(NSWindowController):
    def init(self):
        panel=NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            ((180,160),(280,190)),NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow,
            NSBackingStoreBuffered,False)
        self=objc.super(BeztraceWindowController,self).initWithWindow_(panel)
        if self is None: return None
        self.host=GlyphsHost(); self.session=Session(); self.messages=queue.Queue()
        self.engine=DEFAULT_ENGINE; self.pending=None; self.idle_target=None
        self.details=''; self.last_completed=None; self.next_refresh=0
        panel.setTitle_('Beztrace'); panel.setFloatingPanel_(True)
        panel.setLevel_(NSFloatingWindowLevel); panel.setHidesOnDeactivate_(True)
        panel.setReleasedWhenClosed_(False); panel.setDelegate_(self)
        self.content=panel.contentView()
        self.target_label=self.label('Select a glyph layer',(12,157,220,20))
        self.menu_button=self.button('⋯','showMenu:',(242,155,26,24))
        self.image_button=self.button('Choose Image…','chooseImage:',(12,127,116,25))
        self.image_label=self.label('No canvas image',(134,130,134,18),11)
        self.label('Threshold',(12,98,74,20))
        self.threshold=NSPopUpButton.alloc().initWithFrame_pullsDown_(((88,94),(98,26)),False)
        self.threshold.addItemsWithTitles_(['Auto','Manual']); self.threshold.setTarget_(self)
        self.threshold.setAction_('settingsChanged:'); self.threshold.setAccessibilityLabel_('Threshold mode')
        self.content.addSubview_(self.threshold)
        self.value=NSTextField.alloc().initWithFrame_(((193,96),(73,23)))
        self.value.setStringValue_('128'); self.value.setDelegate_(self)
        self.value.setAccessibilityLabel_('Threshold from 0 to 255'); self.value.setEnabled_(False)
        self.content.addSubview_(self.value)
        self.invert=self.button('Invert','settingsChanged:',(12,68,100,24))
        self.invert.setButtonType_(NSButtonTypeSwitch)
        self.status_label=self.label('Place and resize an image in Glyphs.',(12,31,256,34),11)
        self.status_label.cell().setWraps_(True)
        self.status_label.cell().setScrollable_(False)
        self.spinner=NSProgressIndicator.alloc().initWithFrame_(((14,8),(16,16)))
        self.spinner.setStyle_(1); self.spinner.setDisplayedWhenStopped_(False)
        self.content.addSubview_(self.spinner)
        self.trace_button=self.button('Trace','traceImage:',(184,4,84,27))
        self.trace_button.setKeyEquivalent_('\r')
        self.timer=NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(.1,self,'poll:',None,True)
        self.update_buttons()
        return self

    @objc.python_method
    def label(self,title,rect,size=12):
        view=NSTextField.labelWithString_(title); view.setFrame_(((rect[0],rect[1]),(rect[2],rect[3])))
        view.setFont_(NSFont.systemFontOfSize_(size)); self.content.addSubview_(view)
        return view

    @objc.python_method
    def button(self,title,action,rect):
        view=NSButton.alloc().initWithFrame_(((rect[0],rect[1]),(rect[2],rect[3])))
        view.setTitle_(title); view.setBezelStyle_(1); view.setTarget_(self); view.setAction_(action)
        view.setAccessibilityLabel_(title); self.content.addSubview_(view)
        return view

    @objc.python_method
    def status(self,message):
        self.status_label.setStringValue_(message); self.status_label.setToolTip_(message)
        self.update_buttons()

    @objc.python_method
    def error(self,exc):
        self.details=''.join(traceback.format_exception(type(exc),exc,exc.__traceback__))
        self.status(str(exc))
        if isinstance(exc,RecoveryError):
            self.session.poisoned=True
            alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace recovery needs attention')
            alert.setInformativeText_(str(exc)); alert.runModal()
        self.update_buttons()

    @objc.python_method
    def update_buttons(self):
        running=self.session.busy or self.pending is not None
        valid=self.idle_target is not None and not self.session.poisoned
        has_image=valid and self.idle_target.layer.backgroundImage is not None
        self.trace_button.setTitle_('Cancel' if running else 'Trace')
        self.trace_button.setEnabled_(bool(running or has_image))
        self.image_button.setEnabled_(bool(valid and not running))
        self.threshold.setEnabled_(not running); self.invert.setEnabled_(not running)
        self.value.setEnabled_(not running and self.threshold.indexOfSelectedItem()==1)
        self.value.setHidden_(self.threshold.indexOfSelectedItem()==0)
        if running: self.spinner.startAnimation_(None)
        else: self.spinner.stopAnimation_(None)

    @objc.python_method
    def options(self):
        try: threshold='auto' if self.threshold.indexOfSelectedItem()==0 else int(self.value.stringValue())
        except ValueError: raise CompanionError('Threshold must be an integer from 0 to 255')
        result=dict(threshold=threshold,invert=bool(self.invert.state()))
        arguments(result)
        return result

    def settingsChanged_(self,sender):
        self.update_buttons()

    def controlTextDidChange_(self,notification):
        self.settingsChanged_(None)

    @objc.python_method
    def request(self,action):
        try:
            if self.session.poisoned: raise CompanionError('Close this panel; recovery needs attention')
            context=self.host.selection_context()
            self.pending=(action,context)
            self.status('Reading current layer…')
        except Exception as exc: self.error(exc)

    def chooseImage_(self,sender):
        if not self.session.busy and self.pending is None: self.request('choose')

    def traceImage_(self,sender):
        if self.session.busy or self.pending is not None:
            self.pending=None; self.session.invalidate(); self.status('Trace cancelled.')
        else: self.request('trace')

    @objc.python_method
    def choose_for_target(self,target):
        panel=NSOpenPanel.openPanel(); panel.setAllowedFileTypes_(['png','jpg','jpeg'])
        panel.setCanChooseDirectories_(False); panel.setAllowsMultipleSelection_(False)
        if panel.runModal()!=NSModalResponseOK: return
        replacing=target.layer.backgroundImage is not None
        if replacing:
            alert=NSAlert.alloc().init(); alert.setMessageText_('Replace the canvas image?')
            alert.setInformativeText_(target.label); alert.addButtonWithTitle_('Replace Image'); alert.addButtonWithTitle_('Cancel')
            if alert.runModal()!=1000: return
        image=self.host.new_image(str(panel.URL().path()))
        apply_image(self.host,target,image,replacing)
        self.last_completed=None
        self.status('Resize the image in Glyphs, then Trace.')

    @objc.python_method
    def begin_trace(self,target):
        if not Path(self.engine).is_file(): raise CompanionError('Engine missing. Use ⋯ → Choose Engine…')
        options=self.options(); image=image_io.snapshot(target.layer.backgroundImage)
        key=(target.identity,target.destination,image.path,image.geometry,image.file_state,tuple(sorted(options.items())))
        if self.last_completed is not None:
            old_target,old_key,post=self.last_completed
            if (self.host.same(target.document,old_target.document) and key==old_key
                    and self.host.fingerprint(target.layer)==post):
                raise CompanionError('Already traced. Undo the insertion before tracing this image again.')
        token,cancel=self.session.begin(target)
        messages=self.messages; engine=self.engine
        def worker():
            try:
                messages.put((token,'progress','Preparing canvas image…'))
                data,source_hash=image_io.prepare(image,cancel)
                result=trace(engine,data,options,cancel,lambda stage:messages.put((token,'progress',stage)))
                paths=transform_paths(result,image.geometry)
                messages.put((token,'result',(result,paths,image,source_hash,key)))
            except Exception as exc: messages.put((token,'error',exc))
        threading.Thread(target=worker,name='Beztrace canvas trace',daemon=True).start()
        self.status('Preparing canvas image…')

    def poll_(self,timer):
        if self.session.closed: return
        if self.pending is not None:
            action,context=self.pending; self.pending=None
            try:
                self.host.check_selection_context(context)
                target=self.host.active_target(); self.idle_target=target
                if action=='choose': self.choose_for_target(target)
                else: self.begin_trace(target)
            except Exception as exc: self.error(exc)
        while True:
            try: token,kind,value=self.messages.get_nowait()
            except queue.Empty: break
            if token!=self.session.generation or self.session.cancel.is_set(): continue
            if kind=='progress': self.status(value)
            elif kind=='error':
                self.session.busy=False; self.error(value)
            else:
                result,paths,image,source_hash,key=value
                if not self.session.complete(token,result): continue
                try:
                    target=self.session.target
                    revalidate(self.host,target); image_io.revalidate(self.host,target,image,source_hash)
                    warning=apply_paths(self.host,target,paths)
                    self.session.mark_applied()
                    self.last_completed=(target,key,self.host.fingerprint(target.layer))
                    self.details=''
                    self.status(warning or 'Traced %d contours. Undo is available.' % len(paths))
                except Exception as exc: self.error(exc)
        if not self.session.busy and time.monotonic()>=self.next_refresh:
            self.next_refresh=time.monotonic()+.4
            try:
                self.idle_target=self.host.active_target()
                t=self.idle_target
                self.target_label.setStringValue_('%s · %s%s' % (t.glyph.name,t.owner.name,' · Background' if t.destination=='background' else ''))
                self.target_label.setToolTip_(t.label)
                img=t.layer.backgroundImage
                self.image_label.setStringValue_(Path(str(img.path)).name if img else 'No canvas image')
            except Exception:
                self.idle_target=None; self.target_label.setStringValue_('Select one glyph layer')
                self.image_label.setStringValue_('')
        self.update_buttons()

    def showMenu_(self,sender):
        menu=NSMenu.alloc().init()
        for title,action in [('Choose Engine…','chooseEngine:'),('Error Details…','showDetails:'),('About Beztrace','showAbout:')]:
            item=NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title,action,'')
            item.setTarget_(self); menu.addItem_(item)
        menu.popUpMenuPositioningItem_atLocation_inView_(None,(0,0),sender)

    def chooseEngine_(self,sender):
        if self.session.busy: return
        panel=NSOpenPanel.openPanel(); panel.setCanChooseDirectories_(False); panel.setAllowsMultipleSelection_(False)
        if panel.runModal()==NSModalResponseOK:
            self.engine=str(panel.URL().path()); self.status('Engine selected. Ready to trace.')

    def showDetails_(self,sender):
        alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace details')
        alert.setInformativeText_(self.details or 'No errors.'); alert.runModal()

    def showAbout_(self,sender):
        alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace 0.1.0 · build 6')
        alert.setInformativeText_('Supports beztrace 0.1.0 and 0.1.1-dev.1.\nEngine: '+self.engine+'\n\nUnsigned local development build. Native qualification status is recorded with the package.')
        alert.runModal()

    def windowWillClose_(self,notification):
        self.pending=None; self.session.close(); self.timer.invalidate()
