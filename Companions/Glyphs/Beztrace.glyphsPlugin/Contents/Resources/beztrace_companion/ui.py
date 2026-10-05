# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Small native canvas-image tracer. Placement belongs to Glyphs."""
from dataclasses import replace
import queue
import threading
import time
import traceback
from pathlib import Path
import objc
from AppKit import (NSWindowController, NSPanel, NSButton, NSTextField, NSPopUpButton, NSSlider,
    NSAlert, NSOpenPanel, NSMenu, NSMenuItem, NSFont, NSProgressIndicator, NSBox, NSColor,
    NSWindowStyleMaskTitled, NSWindowStyleMaskClosable, NSWindowStyleMaskUtilityWindow,
    NSBackingStoreBuffered, NSFloatingWindowLevel, NSModalResponseOK, NSButtonTypeSwitch,
    NSBezelStyleDisclosure, NSBoxSeparator)
from Foundation import NSTimer,NSUserDefaults
from .contract import CompanionError, combined_warning
from .engine import default_engine, trace, arguments
from .native import GlyphsHost
from .adapter import revalidate, apply_paths, RecoveryError
from .session import Session
from .canvas import transform_paths
from .settings import TraceSettings,quantize_slider,native_preference_value
from . import image_io

PREFERENCES_KEY='dev.beztrace.glyphs.trace-settings-v1'
PANEL_WIDTH=300
COLLAPSED_HEIGHT=210
EXPANDED_HEIGHT=410
MANUAL_THRESHOLD_EXTRA=24
VALIDATION_EXTRA=18


class SettingValidationError(CompanionError):
    def __init__(self,control,message):
        super().__init__(message); self.control=control


def load_preferences():
    value=NSUserDefaults.standardUserDefaults().dictionaryForKey_(PREFERENCES_KEY)
    return TraceSettings.from_persistent_value(native_preference_value(value))


def save_preferences(settings,advanced):
    NSUserDefaults.standardUserDefaults().setObject_forKey_(settings.persistent_value(advanced),PREFERENCES_KEY)


class BeztraceWindowController(NSWindowController):
    def init(self):
        stored,advanced=load_preferences()
        height=(EXPANDED_HEIGHT+(MANUAL_THRESHOLD_EXTRA if stored.threshold!='auto' else 0)
                if advanced else COLLAPSED_HEIGHT)
        panel=NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            ((180,160),(PANEL_WIDTH,height)),NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow,
            NSBackingStoreBuffered,False)
        self=objc.super(BeztraceWindowController,self).initWithWindow_(panel)
        if self is None: return None
        self.host=GlyphsHost(); self.session=Session(); self.messages=queue.Queue()
        self.engine=default_engine(); self.pending=None; self.idle_target=None
        self.details=''; self.last_completed=None; self.next_refresh=0
        self.base_snapshot=None; self.retrace_at=None
        self.trace_settings=stored; self.last_valid_settings=stored; self.advanced=advanced
        self.validation_control=None
        panel.setTitle_('Beztrace'); panel.setFloatingPanel_(True)
        panel.setLevel_(NSFloatingWindowLevel); panel.setHidesOnDeactivate_(True)
        panel.setReleasedWhenClosed_(False); panel.setDelegate_(self)
        self.content=panel.contentView()
        self.target_label=self.label('Select a glyph layer',(0,0,0,0))
        self.menu_button=self.button('⋯','showMenu:',(0,0,0,0))
        self.image_label=self.label('No canvas image',(0,0,0,0),11)
        self.threshold_label=self.label('Threshold',(0,0,0,0))
        self.threshold=NSPopUpButton.alloc().initWithFrame_pullsDown_(((0,0),(0,0)),False)
        self.threshold.addItemsWithTitles_(['Auto','Manual']); self.threshold.setTarget_(self)
        self.threshold.setAction_('settingsChanged:'); self.threshold.setAccessibilityLabel_('Threshold mode')
        self.content.addSubview_(self.threshold)
        self.value=self.numeric_field('Threshold from 0 to 255')
        self.value.setStringValue_('128'); self.value.setDelegate_(self)
        self.slider=self.make_slider(0,255,'Manual threshold','Adjust the foreground cutoff from 0 to 255.','sliderChanged:')
        self.invert=self.button('Invert image','settingsChanged:',(0,0,0,0))
        self.invert.setButtonType_(NSButtonTypeSwitch)
        self.advanced_separator=self.separator()
        self.advanced_label=self.label('Advanced Options',(0,0,0,0))
        self.advanced_button=self.button('','toggleAdvanced:',(0,0,0,0))
        self.advanced_button.setBezelStyle_(NSBezelStyleDisclosure)
        self.advanced_button.setAccessibilityLabel_('Advanced Options')

        self.preset_label=self.label('Preset',(0,0,0,0),11)
        self.preset=NSPopUpButton.alloc().initWithFrame_pullsDown_(((0,0),(0,0)),False)
        self.preset.addItemsWithTitles_(['Balanced','Sharp','Smooth Detail','Custom'])
        self.preset.setTarget_(self); self.preset.setAction_('presetChanged:')
        self.preset.setAccessibilityLabel_('Trace quality preset'); self.content.addSubview_(self.preset)
        self.accuracy_label=self.label('Accuracy',(0,0,0,0),11)
        self.accuracy_slider=self.make_slider(.5,3,'Accuracy','Lower values follow source pixels more closely.','advancedSliderChanged:')
        self.accuracy_value=self.numeric_field('Accuracy from 0.5 to 3.0')
        self.smoothing_label=self.label('Smoothing',(0,0,0,0),11)
        self.smoothing_slider=self.make_slider(.25,3,'Smoothing','Higher values suppress raster corners and soften transitions.','advancedSliderChanged:')
        self.smoothing_value=self.numeric_field('Smoothing from 0.25 to 3.0')
        self.corner_label=self.label('Corner sensitivity',(0,0,0,0),11)
        self.corner_slider=self.make_slider(1,60,'Corner sensitivity','Higher values classify fewer raster irregularities as corners.','advancedSliderChanged:')
        self.corner_value=self.numeric_field('Corner sensitivity from 1 to 60 degrees')
        self.grid_label=self.label('Grid',(0,0,0,0),11)
        self.grid=NSPopUpButton.alloc().initWithFrame_pullsDown_(((0,0),(0,0)),False)
        self.grid.addItemsWithTitles_(['None','1','2','4','8']); self.grid.setTarget_(self)
        self.grid.setAction_('settingsChanged:'); self.grid.setAccessibilityLabel_('Output grid')
        self.grid.setToolTip_('Snaps output before Glyphs placement; use None for enlarged images.')
        self.grid.setAccessibilityHelp_('Snaps output before Glyphs placement.')
        self.content.addSubview_(self.grid)
        self.speck_label=self.label('Remove specks',(0,0,0,0),11)
        self.speck_slider=self.make_slider(0,1000,'Remove specks','Contours below this minimum area are omitted.','advancedSliderChanged:')
        self.speck_value=self.numeric_field('Minimum contour area from 0 to 1000')
        self.refine=self.button('Raster refinement','settingsChanged:',(0,0,0,0))
        self.refine.setButtonType_(NSButtonTypeSwitch)
        self.refine.setToolTip_('Refine fitted curves against the source raster.')
        self.validation_label=self.label('',(0,0,0,0),10)
        self.validation_label.setTextColor_(NSColor.systemRedColor())
        self.validation_label.setAccessibilityLabel_('Trace setting error')
        self.validation_label.setHidden_(True)
        self.advanced_views=[self.threshold_label,self.threshold,self.value,self.slider,
            self.accuracy_label,self.accuracy_slider,
            self.accuracy_value,self.smoothing_label,self.smoothing_slider,self.smoothing_value,
            self.corner_label,self.corner_slider,self.corner_value,self.grid_label,self.grid,
            self.speck_label,self.speck_slider,self.speck_value,self.refine]

        self.footer_separator=self.separator()
        self.status_label=self.label('Place and resize an image in Glyphs.',(0,0,0,0),11)
        self.status_label.cell().setWraps_(True)
        self.status_label.cell().setScrollable_(False)
        self.spinner=NSProgressIndicator.alloc().initWithFrame_(((0,0),(16,16)))
        self.spinner.setStyle_(1); self.spinner.setDisplayedWhenStopped_(False)
        self.content.addSubview_(self.spinner)
        self.trace_button=self.button('Trace','traceImage:',(0,0,0,0))
        self.trace_button.setKeyEquivalent_('\r')
        self.apply_settings(stored)
        self.layout()
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
    def separator(self):
        view=NSBox.alloc().initWithFrame_(((0,0),(0,0)))
        view.setBoxType_(NSBoxSeparator); self.content.addSubview_(view)
        return view

    @objc.python_method
    def numeric_field(self,label):
        view=NSTextField.alloc().initWithFrame_(((0,0),(0,0)))
        view.setAccessibilityLabel_(label); view.setDelegate_(self); self.content.addSubview_(view)
        return view

    @objc.python_method
    def make_slider(self,minimum,maximum,label,tooltip,action):
        view=NSSlider.alloc().initWithFrame_(((0,0),(0,0)))
        view.setMinValue_(minimum); view.setMaxValue_(maximum); view.setContinuous_(True)
        view.setTarget_(self); view.setAction_(action); view.setAccessibilityLabel_(label)
        view.setToolTip_(tooltip); view.setAccessibilityHelp_(tooltip); self.content.addSubview_(view)
        return view

    @objc.python_method
    def desired_height(self):
        if not self.advanced: return COLLAPSED_HEIGHT
        manual=self.threshold.indexOfSelectedItem()==1
        return (EXPANDED_HEIGHT+(MANUAL_THRESHOLD_EXTRA if manual else 0)
                +(VALIDATION_EXTRA if self.validation_control is not None else 0))

    @objc.python_method
    def resize_preserving_top(self):
        desired=self.desired_height(); old=self.window().frame()
        top=old.origin.y+old.size.height
        if self.content.bounds().size.width!=PANEL_WIDTH or self.content.bounds().size.height!=desired:
            self.window().setContentSize_((PANEL_WIDTH,desired))
            new=self.window().frame(); self.window().setFrameOrigin_((new.origin.x,top-new.size.height))
        self.layout()

    @objc.python_method
    def layout(self):
        h=self.desired_height(); label_x=12; control_x=112; value_x=224
        self.target_label.setFrame_(((12,h-33),(230,20)))
        self.menu_button.setFrame_(((262,h-35),(26,24)))
        self.image_label.setFrame_(((12,h-57),(276,18)))
        self.preset_label.setFrame_(((label_x,h-92),(96,20)))
        self.preset.setFrame_(((control_x,h-96),(176,26)))
        self.invert.setFrame_(((12,h-126),(130,24)))
        self.advanced_separator.setFrame_(((12,h-138),(276,1)))
        self.advanced_label.setFrame_(((12,h-164),(190,20)))
        self.advanced_button.setFrame_(((264,h-166),(24,24)))
        self.advanced_button.setState_(1 if self.advanced else 0)
        self.advanced_button.setAccessibilityValue_('Expanded' if self.advanced else 'Collapsed')
        self.advanced_button.setAccessibilityHelp_(
            'Hide advanced trace controls.' if self.advanced else 'Show advanced trace controls.')

        y=h-195
        self.threshold_label.setFrame_(((label_x,y),(96,20)))
        self.threshold.setFrame_(((control_x,y-4),(176,26)))
        y-=28
        manual=self.threshold.indexOfSelectedItem()==1
        if manual:
            self.slider.setFrame_(((control_x,y),(104,20)))
            self.value.setFrame_(((value_x,y-2),(64,23)))
            if self.validation_control is self.value:
                self.validation_label.setFrame_(((control_x,y-18),(176,16))); y-=VALIDATION_EXTRA
            y-=MANUAL_THRESHOLD_EXTRA

        rows=[(self.accuracy_label,self.accuracy_slider,self.accuracy_value),
              (self.smoothing_label,self.smoothing_slider,self.smoothing_value),
              (self.corner_label,self.corner_slider,self.corner_value)]
        for label,slider,field in rows:
            label.setFrame_(((label_x,y),(100,20)))
            slider.setFrame_(((control_x,y),(104,20)))
            field.setFrame_(((value_x,y-2),(64,23)))
            if self.validation_control is field:
                self.validation_label.setFrame_(((control_x,y-18),(176,16))); y-=VALIDATION_EXTRA
            y-=28
        self.grid_label.setFrame_(((label_x,y),(100,20)))
        self.grid.setFrame_(((control_x,y-4),(176,26))); y-=28
        self.speck_label.setFrame_(((label_x,y),(100,20)))
        self.speck_slider.setFrame_(((control_x,y),(104,20)))
        self.speck_value.setFrame_(((value_x,y-2),(64,23)))
        if self.validation_control is self.speck_value:
            self.validation_label.setFrame_(((control_x,y-18),(176,16))); y-=VALIDATION_EXTRA
        y-=28
        self.refine.setFrame_(((label_x,y-2),(180,24)))

        for view in self.advanced_views: view.setHidden_(not self.advanced)
        self.value.setHidden_(not self.advanced or not manual)
        self.slider.setHidden_(not self.advanced or not manual)
        self.validation_label.setHidden_(not self.advanced or self.validation_control is None)
        self.footer_separator.setFrame_(((0,43),(PANEL_WIDTH,1)))
        self.status_label.setFrame_(((12,9),(160,28)))
        self.spinner.setFrame_(((180,13),(16,16)))
        self.trace_button.setFrame_(((204,8),(84,27)))
        self.configure_key_order()

    @objc.python_method
    def configure_key_order(self):
        views=[self.preset,self.invert,self.advanced_button]
        if self.advanced:
            views += [self.threshold]
            if self.threshold.indexOfSelectedItem()==1: views += [self.slider,self.value]
            views += [self.accuracy_slider,self.accuracy_value,self.smoothing_slider,
                      self.smoothing_value,self.corner_slider,self.corner_value,self.grid,
                      self.speck_slider,self.speck_value,self.refine]
        views.append(self.trace_button)
        for first,second in zip(views,views[1:]): first.setNextKeyView_(second)
        views[-1].setNextKeyView_(views[0])

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
        completed=self.last_completed is not None
        self.trace_button.setTitle_('Done' if completed else ('Cancel' if running else 'Trace'))
        self.trace_button.setEnabled_(bool((completed and not running and self.retrace_at is None) or
                                          (not completed and (running or has_image))))
        editable=not self.session.poisoned and (completed or not running)
        self.threshold.setEnabled_(editable); self.invert.setEnabled_(editable)
        self.preset.setEnabled_(editable)
        self.advanced_button.setEnabled_(editable)
        manual=self.threshold.indexOfSelectedItem()==1
        self.value.setEnabled_(editable and manual); self.value.setHidden_(not self.advanced or not manual)
        self.slider.setEnabled_(editable and manual); self.slider.setHidden_(not self.advanced or not manual)
        for view in [self.accuracy_slider,self.accuracy_value,self.smoothing_slider,
                     self.smoothing_value,self.corner_slider,self.corner_value,self.grid,
                     self.speck_slider,self.speck_value,self.refine]:
            view.setEnabled_(editable)
        if running: self.spinner.startAnimation_(None)
        else: self.spinner.stopAnimation_(None)

    @objc.python_method
    def format_number(self,value,places=2):
        text='%.*f' % (places,value)
        return text if places==0 else text.rstrip('0').rstrip('.')

    @objc.python_method
    def apply_settings(self,settings):
        self.trace_settings=settings; self.last_valid_settings=settings
        self.threshold.selectItemAtIndex_(0 if settings.threshold=='auto' else 1)
        threshold=128 if settings.threshold=='auto' else settings.threshold
        self.value.setStringValue_(str(threshold)); self.slider.setIntegerValue_(threshold)
        self.invert.setState_(settings.invert)
        self.accuracy_slider.setDoubleValue_(settings.accuracy)
        self.accuracy_value.setStringValue_(self.format_number(settings.accuracy))
        self.smoothing_slider.setDoubleValue_(settings.smoothing)
        self.smoothing_value.setStringValue_(self.format_number(settings.smoothing))
        self.corner_slider.setDoubleValue_(settings.corner_threshold)
        self.corner_value.setStringValue_(self.format_number(settings.corner_threshold,0))
        self.grid.selectItemWithTitle_('None' if settings.grid==0 else str(settings.grid))
        self.speck_slider.setDoubleValue_(settings.min_contour_area)
        self.speck_value.setStringValue_(self.format_number(settings.min_contour_area,0))
        self.refine.setState_(settings.refine_raster)
        self.preset.selectItemWithTitle_(settings.preset)

    @objc.python_method
    def number_from_field(self,field,minimum,maximum,whole=False):
        try: value=float(field.stringValue())
        except (TypeError,ValueError):
            value=None
        valid=(value is not None and minimum<=value<=maximum
               and (not whole or value.is_integer()))
        if not valid:
            if field is self.value: message='Enter a whole number from 0 to 255.'
            elif field is self.accuracy_value: message='Enter a value from 0.5 to 3.0.'
            elif field is self.smoothing_value: message='Enter a value from 0.25 to 3.0.'
            elif field is self.corner_value: message='Enter a whole number from 1° to 60°.'
            else: message='Enter a value from 0 to 1000.'
            raise SettingValidationError(field,message)
        return int(value) if whole else value

    @objc.python_method
    def settings_from_controls(self):
        try:
            threshold=('auto' if self.threshold.indexOfSelectedItem()==0 else
                       self.number_from_field(self.value,0,255,True))
            grid_title=str(self.grid.titleOfSelectedItem())
            settings=TraceSettings(threshold=threshold,invert=bool(self.invert.state()),
                accuracy=self.number_from_field(self.accuracy_value,.5,3),
                smoothing=self.number_from_field(self.smoothing_value,.25,3),
                corner_threshold=self.number_from_field(self.corner_value,1,60,True),
                grid=0 if grid_title=='None' else int(grid_title),
                min_contour_area=self.number_from_field(self.speck_value,0,1000),
                refine_raster=bool(self.refine.state())).validate()
        except SettingValidationError:
            raise
        except (TypeError,ValueError) as exc:
            raise CompanionError(str(exc) or 'Trace settings contain an invalid number') from exc
        return settings

    @objc.python_method
    def show_validation(self,control,message):
        if self.validation_control is not None and self.validation_control is not control:
            self.validation_control.setAccessibilityHelp_('')
        self.validation_control=control
        self.validation_label.setStringValue_(message)
        self.validation_label.setToolTip_(message)
        control.setAccessibilityHelp_(message)
        self.resize_preserving_top()

    @objc.python_method
    def clear_validation(self,resize=True):
        if self.validation_control is not None:
            self.validation_control.setAccessibilityHelp_('')
        self.validation_control=None
        self.validation_label.setStringValue_('')
        self.validation_label.setHidden_(True)
        if resize: self.resize_preserving_top()

    @objc.python_method
    def options(self):
        result=self.settings_from_controls().engine_options()
        arguments(result)
        return result

    @objc.python_method
    def commit_settings(self,settings,schedule=True):
        self.trace_settings=settings; self.last_valid_settings=settings
        self.preset.selectItemWithTitle_(settings.preset)
        save_preferences(settings,self.advanced)
        if schedule and self.last_completed is not None:
            self.pending=None; self.session.invalidate()
            self.retrace_at=time.monotonic()+.15
            self.status('Updating trace…')

    def sliderChanged_(self,sender):
        self.value.setStringValue_(str(self.slider.integerValue()))
        self.settingsChanged_(sender)

    def advancedSliderChanged_(self,sender):
        if sender is self.accuracy_slider:
            value=quantize_slider(sender.doubleValue(),.5,3,.25)
            self.accuracy_value.setStringValue_(self.format_number(value))
        elif sender is self.smoothing_slider:
            value=quantize_slider(sender.doubleValue(),.25,3,.1)
            self.smoothing_value.setStringValue_(self.format_number(value))
        elif sender is self.corner_slider:
            value=round(sender.doubleValue())
            self.corner_value.setStringValue_(self.format_number(value,0))
        elif sender is self.speck_slider:
            value=round(sender.doubleValue())
            self.speck_value.setStringValue_(self.format_number(value,0))
        self.settingsChanged_(sender)

    def settingsChanged_(self,sender):
        try:
            settings=self.settings_from_controls()
            self.clear_validation(False)
            if settings.threshold!='auto': self.slider.setIntegerValue_(settings.threshold)
            self.accuracy_slider.setDoubleValue_(settings.accuracy)
            self.smoothing_slider.setDoubleValue_(settings.smoothing)
            self.corner_slider.setDoubleValue_(settings.corner_threshold)
            self.speck_slider.setDoubleValue_(settings.min_contour_area)
            self.commit_settings(settings)
            self.resize_preserving_top()
        except SettingValidationError as exc:
            self.retrace_at=None; self.show_validation(exc.control,str(exc))
        except CompanionError as exc:
            self.retrace_at=None; self.status(str(exc))
        self.update_buttons()

    def controlTextDidChange_(self,notification):
        self.settingsChanged_(notification.object() if notification is not None else None)

    def controlTextDidEndEditing_(self,notification):
        try: self.settings_from_controls()
        except CompanionError:
            self.clear_validation(False)
            self.apply_settings(self.last_valid_settings); self.status('Restored the last valid trace settings.')
            self.resize_preserving_top()
        else:
            self.clear_validation()
        self.update_buttons()

    def presetChanged_(self,sender):
        name=str(self.preset.titleOfSelectedItem())
        if name=='Custom':
            self.preset.selectItemWithTitle_(self.trace_settings.preset); return
        settings=self.trace_settings.applying_preset(name)
        self.clear_validation(False); self.apply_settings(settings); self.commit_settings(settings)
        self.resize_preserving_top()
        self.update_buttons()

    def toggleAdvanced_(self,sender):
        self.advanced=not self.advanced
        self.resize_preserving_top(); save_preferences(self.trace_settings,self.advanced); self.update_buttons()

    def resetSettings_(self,sender):
        self.clear_validation(False)
        self.apply_settings(TraceSettings())
        if self.advanced: self.toggleAdvanced_(None)
        else: save_preferences(self.trace_settings,False)
        self.commit_settings(self.trace_settings); self.update_buttons()

    @objc.python_method
    def request(self,action):
        try:
            if self.session.poisoned: raise CompanionError('Close this panel; recovery needs attention')
            context=self.host.selection_context()
            self.pending=(action,context)
            self.status('Reading current layer…')
        except Exception as exc: self.error(exc)

    def traceImage_(self,sender):
        if self.last_completed is not None:
            if not self.session.busy and self.pending is None and self.retrace_at is None:
                self.window().performClose_(None)
        elif self.session.busy or self.pending is not None:
            self.pending=None; self.session.invalidate(); self.status('Trace cancelled.')
        else: self.request('trace')

    @objc.python_method
    def begin_trace(self,target):
        if not Path(self.engine).is_file(): raise CompanionError('Engine missing. Use ⋯ → Choose Engine…')
        options=self.options(); image=image_io.snapshot(target.layer.backgroundImage)
        key=(target.identity,target.destination,image.path,image.geometry,image.file_state,tuple(sorted(options.items())))
        if self.last_completed is not None:
            old_target,old_key,post=self.last_completed
            if (not self.host.same(target.document,old_target.document)
                    or not self.host.same(target.layer,old_target.layer)):
                raise CompanionError('Return to the traced layer, or click Done and open a new panel.')
            revalidate(self.host,replace(old_target,fingerprint=post))
            if key[:-1]!=old_key[:-1]:
                raise CompanionError('The canvas image changed. Click Done and review the layer before tracing again.')
        else:
            self.base_snapshot=self.host.snapshot(target.layer)
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
        if self.retrace_at is not None and time.monotonic()>=self.retrace_at:
            self.retrace_at=None; self.request('trace')
        if self.pending is not None:
            action,context=self.pending; self.pending=None
            try:
                self.host.check_selection_context(context)
                target=self.host.active_target(); self.idle_target=target
                self.begin_trace(target)
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
                    warning=apply_paths(self.host,target,paths,base_snapshot=self.base_snapshot if self.last_completed else None)
                    self.session.mark_applied()
                    self.last_completed=(target,key,self.host.fingerprint(target.layer))
                    self.details=''
                    self.status(combined_warning(result,warning)
                                or 'Traced %d contours. Adjust settings or click Done.' % len(paths))
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
        for title,action in [('Choose Engine…','chooseEngine:'),('Reset Trace Settings','resetSettings:'),
                             ('Error Details…','showDetails:'),('About Beztrace','showAbout:')]:
            item=NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title,action,'')
            if action=='resetSettings:': item.setEnabled_(not self.session.busy and not self.session.poisoned)
            item.setTarget_(self); menu.addItem_(item)
        menu.popUpMenuPositioningItem_atLocation_inView_(None,(0,0),sender)

    def chooseEngine_(self,sender):
        if self.session.busy: return
        panel=NSOpenPanel.openPanel(); panel.setCanChooseDirectories_(False); panel.setAllowsMultipleSelection_(False)
        if panel.runModal()==NSModalResponseOK:
            self.engine=str(panel.URL().path()); self.status('Engine selected. Ready to trace.')
            self.settingsChanged_(None)

    def showDetails_(self,sender):
        alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace details')
        alert.setInformativeText_(self.details or 'No errors.'); alert.runModal()

    def showAbout_(self,sender):
        alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace 0.1.0 · build 15')
        alert.setInformativeText_('Supports beztrace 0.1.0, 0.1.1 and 0.1.1-dev.1 through 0.1.1-dev.4.\nEngine: '+self.engine+'\n\nSigning and native qualification status are recorded in the release manifest.')
        alert.runModal()

    def windowWillClose_(self,notification):
        self.pending=None; self.retrace_at=None; self.session.close(); self.timer.invalidate()
