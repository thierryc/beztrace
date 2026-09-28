# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Compact AppKit inspector; font changes occur only through explicit Apply."""
import dataclasses
import queue
import threading
import time
from pathlib import Path
import objc
from AppKit import (NSWindowController, NSPanel, NSView, NSButton, NSTextField,
    NSPopUpButton, NSSegmentedControl, NSScrollView, NSTextView, NSOpenPanel, NSAlert, NSImage,
    NSColor, NSFont, NSBezierPath, NSGraphicsContext, NSProgressIndicator,
    NSWindowStyleMaskTitled, NSWindowStyleMaskClosable, NSWindowStyleMaskResizable,
    NSWindowStyleMaskUtilityWindow, NSBackingStoreBuffered, NSModalResponseOK,
    NSButtonTypeSwitch, NSCompositingOperationSourceOver, NSViewWidthSizable,
    NSViewHeightSizable, NSFloatingWindowLevel, NSMenu, NSMenuItem,
    NSPasteboardTypeFileURL, NSPasteboardURLReadingFileURLsOnlyKey, NSDragOperationCopy,
    NSFontAttributeName, NSForegroundColorAttributeName)
from Foundation import NSData, NSTimer, NSURL, NSAffineTransform, NSString
from Quartz import (CGImageSourceCreateWithData, CGImageSourceCopyPropertiesAtIndex,
    CGImageSourceCreateThumbnailAtIndex, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
    kCGImageSourceCreateThumbnailFromImageAlways, kCGImageSourceCreateThumbnailWithTransform,
    kCGImageSourceThumbnailMaxPixelSize)
from .contract import CompanionError, MAX_INPUT
from .engine import DEFAULT_ENGINE, DEFAULT_OPTIONS, trace, arguments
from .session import Session
from .adapter import capture, revalidate, apply_paths, RecoveryError
from .native import GlyphsHost
from .placement import MODES, MetricSnapshot, resolve
from .preview import geometry, OverlayBinding
from .inspector import actions, mode_after_edit, accepts_image
from .drawing import CachedDrawing


class BeztraceInspectorDocument(NSView):
    def isFlipped(self):
        return True


class BeztraceImageView(NSView):
    def initWithFrame_(self, frame):
        self = objc.super(BeztraceImageView, self).initWithFrame_(frame)
        if self is not None:
            self.owner = None
            self.image = None
            self.drawing = None
            self.mode = 'Overlay'
            self.registerForDraggedTypes_([NSPasteboardTypeFileURL])
            self.setAccessibilityElement_(True)
            self.setAccessibilityRole_('AXButton')
            self.setAccessibilityLabel_('Source image. Click to choose or drop a PNG or JPEG.')
        return self

    def mouseDown_(self, event):
        self.owner.chooseImage_(self)

    def accessibilityPerformPress(self):
        self.owner.chooseImage_(self)
        return True

    @objc.python_method
    def dropped_path(self, sender):
        urls = sender.draggingPasteboard().readObjectsForClasses_options_(
            [NSURL], {NSPasteboardURLReadingFileURLsOnlyKey: True}) or []
        if len(urls) == 1 and urls[0].isFileURL():
            path = Path(str(urls[0].path()))
            if accepts_image(path):
                return path
        return None

    def draggingEntered_(self, sender):
        return NSDragOperationCopy if self.dropped_path(sender) else 0

    def prepareForDragOperation_(self, sender):
        return self.dropped_path(sender) is not None

    def performDragOperation_(self, sender):
        path = self.dropped_path(sender)
        return bool(path and self.owner.load_image(path))

    def drawRect_(self, rect):
        NSColor.controlBackgroundColor().set()
        NSBezierPath.fillRect_(self.bounds())
        size = self.bounds().size
        if self.image is None:
            text = 'Choose or drop an image'
            attrs = {NSFontAttributeName: NSFont.systemFontOfSize_(12),
                     NSForegroundColorAttributeName: NSColor.secondaryLabelColor()}
            label = NSString.stringWithString_(text)
            width = label.sizeWithAttributes_(attrs).width
            label.drawAtPoint_withAttributes_(((size.width-width)/2,size.height/2-6),attrs)
            return
        NSGraphicsContext.saveGraphicsState()
        try:
            if self.drawing and self.mode != 'Image':
                box = self.drawing.geometry.image_bounds if self.mode == 'Overlay' else self.drawing.geometry.ink_bounds
                x0,y0,x1,y1 = box
                scale = min((size.width-24)/max(x1-x0,1),(size.height-24)/max(y1-y0,1))
                transform = NSAffineTransform.transform()
                transform.translateXBy_yBy_((size.width-(x1-x0)*scale)/2-x0*scale,
                                           (size.height-(y1-y0)*scale)/2-y0*scale)
                transform.scaleBy_(scale); transform.concat()
                self.drawing.draw(scale,source=self.mode=='Overlay',guides=False)
            else:
                image_size = self.image.size()
                scale = min((size.width-24)/max(image_size.width,1),(size.height-24)/max(image_size.height,1))
                w,h = image_size.width*scale,image_size.height*scale
                self.image.drawInRect_fromRect_operation_fraction_(
                    (((size.width-w)/2,(size.height-h)/2),(w,h)),((0,0),(0,0)),NSCompositingOperationSourceOver,1)
        finally:
            NSGraphicsContext.restoreGraphicsState()


class BeztraceWindowController(NSWindowController):
    def init(self):
        panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            ((180,160),(360,680)), NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
            NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow, NSBackingStoreBuffered,False)
        self = objc.super(BeztraceWindowController,self).initWithWindow_(panel)
        if self is None:
            return None
        self.host = GlyphsHost()
        self.session = Session()
        self.messages = queue.Queue()
        self.image_bytes = None
        self.engine = DEFAULT_ENGINE
        self.fields, self.labels, self.views = {}, {}, {}
        self.placed = self.cached = None
        self.fit = None
        self.advanced = self.details_open = False
        self.text_scale = 1.0
        self.details = ''
        self.next_target_check = 0
        self.overlay_fault = None
        self.metrics = MetricSnapshot(())
        panel.setTitle_('Beztrace')
        panel.setFloatingPanel_(True); panel.setLevel_(NSFloatingWindowLevel)
        panel.setHidesOnDeactivate_(True); panel.setBecomesKeyOnlyIfNeeded_(False)
        panel.setReleasedWhenClosed_(False); panel.setDelegate_(self)
        panel.setContentMinSize_((360,480)); panel.setContentMaxSize_((520,1100))
        self.content = panel.contentView()
        self.scroll = NSScrollView.alloc().initWithFrame_(((0,126),(360,554)))
        self.scroll.setHasVerticalScroller_(True); self.scroll.setAutohidesScrollers_(True)
        self.scroll.setDrawsBackground_(False)
        self.document = BeztraceInspectorDocument.alloc().initWithFrame_(((0,0),(360,850)))
        self.scroll.setDocumentView_(self.document); self.content.addSubview_(self.scroll)
        self.create_controls()
        from GlyphsApp import DRAWFOREGROUND
        self.overlay = OverlayBinding(self.host.app.addCallback,self.host.app.removeCallback,
            self.host.redraw,self.beztraceInspectorDrawForeground,DRAWFOREGROUND,self.host.same)
        self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(.1,self,'poll:',None,True)
        self.layout()
        self.useCurrent_(None)
        return self

    @objc.python_method
    def create_controls(self):
        for key,title in [('target','TARGET'),('image','IMAGE'),('placement','PLACEMENT'),
                          ('tracing','TRACING'),('destination','DESTINATION')]:
            self.label(key+'_heading',title,heading=True)
        self.label('target','Select one glyph layer',strong=True)
        self.label('document','No document')
        self.button('current','Use Current','useCurrent:')
        self.button('more','⋯','showMore:')
        self.views['more'].setAccessibilityLabel_('Engine settings and inspector options')
        self.preview = BeztraceImageView.alloc().initWithFrame_(((0,0),(300,128)))
        self.preview.owner = self
        self.document.addSubview_(self.preview); self.views['preview'] = self.preview
        self.label('filename','PNG or JPEG · up to 16 MiB')
        self.button('image','Change…','chooseImage:')
        self.segment('preview_mode',['Image','Overlay','Outline'],'previewMode:',1)
        self.popup('fit',MODES,'fitChanged:')
        self.label('fit_label','Fit to')
        self.label('fit_note','Choose a target to resolve font metrics.')
        for key,title,value in [('height','Height',700),('bottom','Bottom Y',0),('horizontal','Horizontal position',0)]:
            self.field(key,title,value)
        self.check('live','Preview in Glyphs','displayChanged:',True)
        self.check('source','Source image','displayChanged:',False)
        self.popup('threshold_mode',['Auto','Fixed'],'thresholdChanged:')
        self.field('threshold','Threshold',127)
        self.field('accuracy','Accuracy',2.0)
        self.check('invert','Invert image','traceOptionChanged:',False)
        self.button('advanced','▸ Advanced settings','toggleAdvanced:')
        for key,title,value in [('smoothing','Smoothing',1),('corner_threshold','Corner threshold (°)',12),
                                ('min_contour_area','Minimum contour area',100),('grid','Grid',2),('structure_grid','Structure grid',0)]:
            self.field(key,title,value)
        self.check('refine','Refine raster','traceOptionChanged:',True)
        self.check('rtl','RTL contour start','traceOptionChanged:',False)
        self.segment('destination',['Foreground','Background'],'destinationChanged:')
        self.popup('operation',['Add to existing paths','Replace existing paths'],'operationChanged:')
        self.label('operation_note','Existing outlines are preserved.')
        self.label('placement_error','',error=True)
        self.label('tracing_error','',error=True)
        # Fixed action footer; document content scrolls independently.
        self.label('status','Ready',parent=self.content)
        self.detail_scroll = NSScrollView.alloc().initWithFrame_(((18,48),(324,82)))
        self.detail_scroll.setHasVerticalScroller_(True)
        self.detail_text = NSTextView.alloc().initWithFrame_(((0,0),(304,82)))
        self.detail_text.setEditable_(False); self.detail_text.setSelectable_(True)
        self.detail_text.setVerticallyResizable_(True)
        self.detail_text.setHorizontallyResizable_(False)
        self.detail_text.textContainer().setWidthTracksTextView_(True)
        self.detail_text.setAutoresizingMask_(NSViewWidthSizable)
        self.detail_text.setAccessibilityLabel_('Process details')
        self.detail_scroll.setDocumentView_(self.detail_text)
        self.content.addSubview_(self.detail_scroll)
        self.button('details','Details…','toggleDetails:',parent=self.content)
        self.button('trace','Trace','traceImage:',parent=self.content)
        self.button('cancel','Cancel','cancelTrace:',parent=self.content)
        self.button('apply','Apply','applyTrace:',parent=self.content)
        self.spinner = NSProgressIndicator.alloc().initWithFrame_(((0,0),(16,16)))
        self.spinner.setStyle_(1); self.spinner.setIndeterminate_(True)
        self.spinner.setDisplayedWhenStopped_(False); self.content.addSubview_(self.spinner)

    @objc.python_method
    def label(self,key,title,heading=False,strong=False,error=False,parent=None):
        view = NSTextField.labelWithString_(title)
        view.cell().setWraps_(True); view.cell().setUsesSingleLineMode_(False)
        view.setTextColor_(NSColor.systemRedColor() if error else NSColor.secondaryLabelColor() if heading or not strong else NSColor.labelColor())
        view.setSelectable_(not heading)
        view.setAccessibilityLabel_(title)
        (parent or self.document).addSubview_(view)
        self.labels[key] = (view,heading,strong)
        return view

    @objc.python_method
    def button(self,key,title,action,parent=None):
        view = NSButton.alloc().initWithFrame_(((0,0),(100,28)))
        view.setTitle_(title); view.setBezelStyle_(1)
        view.setTarget_(self); view.setAction_(action); view.setAccessibilityLabel_(title)
        (parent or self.document).addSubview_(view); self.views[key] = view
        return view

    @objc.python_method
    def check(self,key,title,action,value):
        view = self.button(key,title,action)
        view.setButtonType_(NSButtonTypeSwitch); view.setState_(int(value))

    @objc.python_method
    def field(self,key,title,value):
        self.label(key+'_label',title)
        view = NSTextField.alloc().initWithFrame_(((0,0),(100,26)))
        view.setStringValue_(str(value)); view.setDelegate_(self)
        view.setAccessibilityLabel_(title); view.setToolTip_(title)
        self.document.addSubview_(view); self.fields[key] = view

    @objc.python_method
    def popup(self,key,titles,action):
        view = NSPopUpButton.alloc().initWithFrame_pullsDown_(((0,0),(180,28)),False)
        view.addItemsWithTitles_(list(titles)); view.setTarget_(self); view.setAction_(action)
        view.setAccessibilityLabel_({'fit':'Fit to','operation':'Path operation','threshold_mode':'Threshold mode'}.get(key,key))
        self.document.addSubview_(view); self.views[key] = view

    @objc.python_method
    def segment(self,key,titles,action,selected=0):
        view = NSSegmentedControl.alloc().initWithFrame_(((0,0),(300,26)))
        view.setSegmentCount_(len(titles)); view.setTrackingMode_(0)
        for i,title in enumerate(titles): view.setLabel_forSegment_(title,i)
        view.setSelectedSegment_(selected); view.setTarget_(self); view.setAction_(action)
        view.setAccessibilityLabel_('Preview mode' if key=='preview_mode' else 'Destination')
        self.document.addSubview_(view); self.views[key] = view

    @objc.python_method
    def text(self,key,value):
        view = self.labels[key][0]
        view.setStringValue_(value); view.setToolTip_(value)

    @objc.python_method
    def layout(self):
        if not hasattr(self,'views') or 'apply' not in self.views:
            return
        size = self.content.bounds().size
        s = self.text_scale
        footer = (210 if self.details_open else 122)*s
        self.scroll.setFrame_(((0,footer),(size.width,max(50,size.height-footer))))
        width = self.scroll.contentSize().width
        pad, gap = 18, 8
        w = width-2*pad
        h = 28*s
        y = 12
        for view,heading,strong in self.labels.values():
            view.setFont_(NSFont.boldSystemFontOfSize_((10 if heading else 13)*s) if heading or strong else NSFont.systemFontOfSize_(12*s))
        for view in list(self.fields.values())+list(self.views.values()):
            if hasattr(view,'setFont_'): view.setFont_(NSFont.systemFontOfSize_(12*s))
        def frame(view,x,top,length,height=h): view.setFrame_(((x,top),(length,height)))
        def label(key,x=pad,top=None,length=w,height=None):
            frame(self.labels[key][0],x,y if top is None else top,length,height or h)
        def control(key,x=pad,top=None,length=w,height=None):
            frame(self.views[key],x,y if top is None else top,length,height or h)
        def heading(key):
            nonlocal y
            label(key+'_heading',height=18*s); y+=22*s
        def field(key):
            nonlocal y
            label(key+'_label',length=w*.59)
            frame(self.fields[key],pad+w*.62,y,w*.38,h)
            y+=h+6
        heading('target')
        label('target',length=w-36); control('more',x=width-pad-30,length=30); y+=h
        label('document',length=w-116,height=34*s); control('current',x=width-pad-110,length=110); y+=40*s
        heading('image'); control('preview',height=128*s); y+=136*s
        label('filename',length=w-84); control('image',x=width-pad-80,length=80); y+=h+4
        control('preview_mode'); y+=h+18
        heading('placement'); label('fit_label',length=68); control('fit',x=pad+75,length=w-75); y+=h+2
        label('fit_note',height=40*s); y+=44*s
        half=(w-gap)/2
        for i,key in enumerate(('height','bottom')):
            x=pad+i*(half+gap)
            label(key+'_label',x=x,length=half,height=20*s)
            frame(self.fields[key],x,y+22*s,half,h)
        y+=24*s+h+6; field('horizontal')
        if str(self.labels['placement_error'][0].stringValue()):
            label('placement_error',height=40*s); y+=44*s
            self.labels['placement_error'][0].setHidden_(False)
        else: self.labels['placement_error'][0].setHidden_(True)
        control('live',length=w*.57); control('source',x=pad+w*.57,length=w*.43); y+=h+16
        heading('tracing')
        label('threshold_label',length=w*.4)
        control('threshold_mode',x=pad+w*.4,length=w*.3)
        fixed=self.views['threshold_mode'].indexOfSelectedItem()==1
        frame(self.fields['threshold'],pad+w*.72,y,w*.28,h)
        self.fields['threshold'].setHidden_(not fixed); y+=h+6
        field('accuracy'); control('invert'); y+=h+2
        control('advanced'); y+=h+4
        for key in ('smoothing','corner_threshold','min_contour_area','grid','structure_grid'):
            self.labels[key+'_label'][0].setHidden_(not self.advanced); self.fields[key].setHidden_(not self.advanced)
            if self.advanced: field(key)
        for key in ('refine','rtl'):
            self.views[key].setHidden_(not self.advanced)
            if self.advanced: control(key); y+=h+2
        if str(self.labels['tracing_error'][0].stringValue()):
            label('tracing_error',height=40*s); y+=44*s
            self.labels['tracing_error'][0].setHidden_(False)
        else: self.labels['tracing_error'][0].setHidden_(True)
        y+=12; heading('destination'); control('destination'); y+=h+6
        control('operation'); y+=h+3
        label('operation_note',height=36*s); y+=44*s
        self.document.setFrameSize_((width,max(y,self.scroll.contentSize().height)))
        # Footer uses the ordinary AppKit Y-up coordinate system.
        frame(self.views['trace'],size.width-206,12,92,h)
        frame(self.views['apply'],size.width-108,12,92,h)
        frame(self.views['cancel'],18,12,86,h)
        frame(self.views['details'],18,12,86,h)
        self.detail_scroll.setHidden_(not self.details_open)
        self.detail_text.setFont_(NSFont.systemFontOfSize_(12*s))
        if self.details_open:
            frame(self.detail_scroll,18,48*s,size.width-36,82*s)
        frame(self.labels['status'][0],42,footer-64*s,size.width-60,56*s)
        self.spinner.setFrame_(((18,footer-37*s),(16,16)))
        # Explicit key order follows visual groups, then the footer.
        keys=[self.views[k] for k in ('current','image','preview_mode','fit')]
        keys += [self.fields[k] for k in ('height','bottom','horizontal')]
        keys += [self.views[k] for k in ('live','source','threshold_mode')]
        keys += ([self.fields['threshold']] if fixed else [])+[self.fields['accuracy'],self.views['invert'],self.views['advanced']]
        if self.advanced:
            keys += [self.fields[k] for k in ('smoothing','corner_threshold','min_contour_area','grid','structure_grid')]
            keys += [self.views['refine'],self.views['rtl']]
        keys += [self.views[k] for k in ('destination','operation','trace','apply','more')]
        for a,b in zip(keys,keys[1:]+keys[:1]): a.setNextKeyView_(b)

    def windowDidResize_(self,notification):
        self.layout()

    def toggleAdvanced_(self,sender):
        self.advanced = not self.advanced
        self.views['advanced'].setTitle_('▾ Advanced settings' if self.advanced else '▸ Advanced settings')
        self.layout()

    def toggleDetails_(self,sender):
        self.details_open = not self.details_open
        self.views['details'].setTitle_('Hide details' if self.details_open else 'Details…')
        self.layout()

    def showMore_(self,sender):
        menu = NSMenu.alloc().initWithTitle_('Beztrace')
        for title,action in [('Choose Engine…','chooseEngine:'),('About Beztrace 0.1.0 (2)…','showAbout:'),
                             ('Use regular text' if self.text_scale>1 else 'Use larger text','toggleText:')]:
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title,action,'')
            item.setTarget_(self); menu.addItem_(item)
        menu.popUpMenuPositioningItem_atLocation_inView_(None,(0,sender.bounds().size.height),sender)

    def toggleText_(self,sender):
        self.text_scale = 1.0 if self.text_scale>1 else 1.2
        if self.text_scale>1 and self.window().contentView().bounds().size.width<400:
            self.window().setContentSize_((400,self.content.bounds().size.height))
        self.layout()

    def showAbout_(self,sender):
        alert = NSAlert.alloc().init()
        alert.setMessageText_('Beztrace 0.1.0 · build 2')
        alert.setInformativeText_('Requires beztrace 0.1.0.\nEngine: '+self.engine+'\n\nUnsigned development build. Native qualification pending.')
        alert.runModal()

    @objc.python_method
    def status(self,message,details=None):
        self.text('status',message)
        if details is not None:
            self.details=details; self.detail_text.setString_(details)
        self.update_buttons()

    @objc.python_method
    def error(self,exc,field=None):
        text=str(exc)
        if field: self.text(field+'_error',text); self.layout()
        self.status(text,text)

    @objc.python_method
    def update_buttons(self):
        state=actions(self.session,bool(self.image_bytes),bool(self.placed))
        self.views['trace'].setEnabled_(state.trace_enabled)
        self.views['trace'].setTitle_(state.trace_title)
        self.views['apply'].setEnabled_(state.apply_enabled)
        self.views['cancel'].setHidden_(not state.cancel_visible)
        self.views['details'].setHidden_(state.cancel_visible)
        self.views['details'].setEnabled_(bool(self.details))
        self.views['trace'].setKeyEquivalent_('\r' if state.primary=='trace' and state.trace_enabled else '')
        self.views['apply'].setKeyEquivalent_('\r' if state.primary=='apply' else '')
        if state.cancel_visible: self.spinner.startAnimation_(None)
        else: self.spinner.stopAnimation_(None)

    @objc.python_method
    def clear_preview(self):
        self.placed=self.cached=None
        self.preview.drawing=None; self.preview.setNeedsDisplay_(True)
        self.overlay.clear()

    @objc.python_method
    def clear_result(self):
        self.session.invalidate(); self.clear_preview(); self.update_buttons()

    def useCurrent_(self,sender):
        self.clear_result()
        try:
            self.session.target=capture(self.host,'background' if self.views['destination'].selectedSegment() else 'foreground')
            target=self.session.target
            self.metrics=target.metrics
            self.text('target','%s · %s' % (target.glyph.name,target.owner.name))
            self.text('document',str(target.document.displayName()))
            self.operationChanged_(None)
            self.resolve_fit()
            self.status('Target captured. Choose an image, then Trace.','')
        except Exception as exc:
            self.session.target=None; self.fit=None
            self.text('target','Select one glyph layer'); self.text('document','No valid target')
            self.error(exc)
        self.update_buttons()

    def destinationChanged_(self,sender):
        self.clear_result()
        try:
            target=self.session.target; revalidate(self.host,target)
            destination='background' if self.views['destination'].selectedSegment() else 'foreground'
            layer=self.host.destination(target.owner,destination)
            self.host.check_editable(target.glyph,layer)
            self.session.target=dataclasses.replace(target,layer=layer,destination=destination,fingerprint=self.host.fingerprint(layer))
            self.operationChanged_(None)
        except Exception as exc:
            self.session.target=None; self.error(exc)
        self.update_buttons()

    def operationChanged_(self,sender):
        count=len(self.session.target.layer.paths) if self.session.target else 0
        replacing=self.views['operation'].indexOfSelectedItem()==1
        self.text('operation_note','%d existing paths will be replaced.' % count if replacing else 'Existing outlines are preserved.')

    @objc.python_method
    def resolve_fit(self):
        self.fit=None; self.text('placement_error','')
        if self.session.target is None: return
        try:
            mode=str(self.views['fit'].titleOfSelectedItem())
            height=float(self.fields['height'].stringValue()) if mode=='Custom' else 700.0
            bottom=float(self.fields['bottom'].stringValue()) if mode=='Custom' else 0.0
            self.fit=resolve(mode,self.session.target.classification,self.metrics,height,bottom)
            self.fields['height'].setStringValue_('%g' % self.fit.height)
            self.fields['bottom'].setStringValue_('%g' % self.fit.bottom)
            self.text('fit_note',self.fit.explanation)
        except (ValueError,CompanionError) as exc:
            self.text('fit_note','Choose a preset or enter Custom placement.')
            self.text('placement_error',str(exc))
        self.layout()

    def fitChanged_(self,sender):
        self.resolve_fit(); self.update_preview()

    def thresholdChanged_(self,sender):
        self.layout(); self.traceOptionChanged_(sender)

    def displayChanged_(self,sender):
        self.publish_overlay()

    def previewMode_(self,sender):
        self.preview.mode=('Image','Overlay','Outline')[self.views['preview_mode'].selectedSegment()]
        self.preview.setNeedsDisplay_(True)

    @objc.python_method
    def publish_overlay(self):
        target=self.session.target
        visible=bool(target and self.cached and self.views['live'].state() and not self.session.applied)
        self.overlay.publish(target.owner if target else None,target.layer if target else None,
                             self.cached,visible)

    @objc.python_method
    def beztraceInspectorDrawForeground(self,layer,info):
        # No font scans, metric resolution, tracing, or file reads in this callback.
        if self.overlay.matches(layer):
            try:
                self.overlay.payload.draw(info.get('Scale',1.0),source=bool(self.views['source'].state()))
            except Exception as exc:
                self.overlay_fault=str(exc)  # Report and disable outside drawing.

    def chooseEngine_(self,sender):
        panel=NSOpenPanel.openPanel()
        panel.setCanChooseDirectories_(False); panel.setAllowsMultipleSelection_(False)
        if panel.runModal()==NSModalResponseOK:
            self.engine=str(panel.URL().path()); self.clear_result()
            self.status('Engine selected. Click Trace to check compatibility.',self.engine)

    def chooseImage_(self,sender):
        panel=NSOpenPanel.openPanel()
        panel.setAllowedFileTypes_(['png','jpg','jpeg'])
        panel.setCanChooseDirectories_(False); panel.setAllowsMultipleSelection_(False)
        if panel.runModal()==NSModalResponseOK: self.load_image(Path(str(panel.URL().path())))

    @objc.python_method
    def load_image(self,path):
        self.clear_result(); self.image_bytes=None; self.preview.image=None
        try:
            if not accepts_image(path): raise CompanionError('Choose a PNG or JPEG image.')
            with path.open('rb') as source: data=source.read(MAX_INPUT+1)
            if not data or len(data)>MAX_INPUT: raise CompanionError('Image must contain 1 byte to 16 MiB.')
            source=CGImageSourceCreateWithData(NSData.dataWithBytes_length_(data,len(data)),None)
            properties=CGImageSourceCopyPropertiesAtIndex(source,0,None) if source else None
            if not properties: raise CompanionError('Cannot decode the selected image.')
            if max(int(properties.get(kCGImagePropertyPixelWidth,0)),int(properties.get(kCGImagePropertyPixelHeight,0)))>4096:
                raise CompanionError('Image dimensions must not exceed 4096 × 4096.')
            cg=CGImageSourceCreateThumbnailAtIndex(source,0,{kCGImageSourceCreateThumbnailFromImageAlways:True,
                kCGImageSourceCreateThumbnailWithTransform:True,kCGImageSourceThumbnailMaxPixelSize:4096})
            if cg is None: raise CompanionError('Cannot decode image preview.')
            self.preview.image=NSImage.alloc().initWithCGImage_size_(cg,(0,0)); self.image_bytes=data
            self.text('filename',path.name); self.preview.setNeedsDisplay_(True)
            self.status('Image loaded. Click Trace.','')
            return True
        except Exception as exc:
            self.error(exc); self.preview.setNeedsDisplay_(True)
            return False

    @objc.python_method
    def options(self):
        result=dict(DEFAULT_OPTIONS)
        for key in result:
            if key in self.fields:
                text=str(self.fields[key].stringValue()).strip()
                if key=='threshold' and self.views['threshold_mode'].indexOfSelectedItem()==0:
                    result[key]='auto'; continue
                try: result[key]=int(text) if key in ('grid','structure_grid','threshold') else float(text)
                except ValueError as exc: raise CompanionError('Invalid '+key.replace('_',' ')+': '+text) from exc
        result.update(invert=bool(self.views['invert'].state()),refine_raster=bool(self.views['refine'].state()),
                      rtl_start=bool(self.views['rtl'].state()))
        arguments(result)  # Validate synchronously so input errors appear by controls.
        return result

    def traceImage_(self,sender):
        try:
            revalidate(self.host,self.session.target)
            options=self.options(); self.text('tracing_error',''); self.layout()
            if not Path(self.engine).is_file():
                self.status('Engine missing. Choose Engine… in the ⋯ menu.',self.engine)
                return
            token,cancel=self.session.begin(self.session.target)
            self.clear_preview()
            image,engine,messages=self.image_bytes,self.engine,self.messages
            def worker():
                try:
                    result=trace(engine,image,options,cancel,lambda stage:messages.put((token,'progress',stage)))
                    messages.put((token,'result',result))
                except Exception as exc: messages.put((token,'error',str(exc)))
            threading.Thread(target=worker,name='Beztrace engine',daemon=True).start()
            self.status('Preparing image…','')
        except Exception as exc: self.error(exc,'tracing')

    def poll_(self,timer):
        if self.session.closed: return
        if self.overlay_fault:
            detail=self.overlay_fault; self.overlay_fault=None
            self.views['live'].setState_(0); self.overlay.clear()
            self.error('Live preview was disabled: '+detail)
        # Membership/metric checks stay outside drawing and are throttled.
        if self.session.target and not self.session.applied and time.monotonic()>=self.next_target_check:
            self.next_target_check=time.monotonic()+.5
            try:
                revalidate(self.host,self.session.target)
            except Exception as exc:
                self.clear_result(); self.session.target=None; self.error(exc)
        while True:
            try: token,kind,payload=self.messages.get_nowait()
            except queue.Empty: break
            if token!=self.session.generation or self.session.closed: continue
            if kind=='progress': self.status(payload)
            elif kind=='result':
                if self.session.complete(token,payload):
                    self.update_preview()
                    summary='%d contours · %d nodes' % (len(payload['paths']),payload['statistics']['nodeCount'])
                    self.status(summary if self.placed else summary+' · choose placement', '\n'.join(payload['warnings']))
            else:
                self.session.busy=False; self.error(payload)
            self.update_buttons()

    @objc.python_method
    def update_preview(self):
        self.clear_preview()
        self.text('placement_error','')
        try:
            if self.session.result and self.fit and not self.session.applied:
                data=geometry(self.session.result,self.fit,float(self.fields['horizontal'].stringValue()),self.metrics)
                self.cached=CachedDrawing(data,self.preview.image)
                self.placed=data.paths
                self.preview.drawing=self.cached
                self.publish_overlay()
            elif self.session.result and not self.fit:
                self.text('placement_error','Choose a valid preset or Custom placement.')
        except Exception as exc: self.error(exc,'placement')
        self.preview.setNeedsDisplay_(True); self.layout(); self.update_buttons()

    def controlTextDidChange_(self,notification):
        control=notification.object()
        placement=next((key for key in ('height','bottom','horizontal') if control==self.fields[key]),None)
        if placement:
            mode=mode_after_edit(str(self.views['fit'].titleOfSelectedItem()),placement)
            self.views['fit'].selectItemWithTitle_(mode)
            self.resolve_fit(); self.update_preview()
        else: self.traceOptionChanged_(None)

    def traceOptionChanged_(self,sender):
        self.clear_result(); self.status('Settings changed. Click Trace again.','')

    def cancelTrace_(self,sender):
        self.clear_result(); self.status('Trace cancelled.','')

    def applyTrace_(self,sender):
        try:
            if not self.session.can_apply() or not self.placed: raise CompanionError('Trace and review outlines before applying.')
            revalidate(self.host,self.session.target)
            replacing=self.views['operation'].indexOfSelectedItem()==1
            if replacing:
                alert=NSAlert.alloc().init()
                alert.setMessageText_('Replace %d existing paths?' % len(self.session.target.layer.paths))
                alert.setInformativeText_(self.session.target.label+' — '+self.session.target.destination)
                alert.addButtonWithTitle_('Replace Paths'); alert.addButtonWithTitle_('Cancel')
                if alert.runModal()!=1000: return
            warning=apply_paths(self.host,self.session.target,self.placed,replacing)
            self.session.mark_applied(); self.clear_preview()
            self.status(warning or 'Applied. Undo is available. Use Current to start another trace.','')
        except RecoveryError as exc:
            self.session.poisoned=True; self.clear_preview(); self.error(exc)
            alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace recovery needs attention')
            alert.setInformativeText_(str(exc)); alert.runModal()
        except Exception as exc: self.error(exc)
        self.update_buttons()

    def windowWillClose_(self,notification):
        self.session.close(); self.timer.invalidate(); self.overlay.close()
        self.preview.drawing=None; self.placed=self.cached=None
