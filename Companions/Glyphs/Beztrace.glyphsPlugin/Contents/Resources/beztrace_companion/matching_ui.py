# Copyright 2026 beztrace contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Native matching panel. All preparation is detached; Apply is explicit."""
import traceback
import time
from pathlib import Path
import objc
import Quartz  # Register native CGColor bridging before configuring layer-backed controls.
from AppKit import (NSWindowController,NSPanel,NSView,NSButton,NSTextField,NSPopUpButton,NSSlider,
    NSAlert,NSOpenPanel,NSSavePanel,NSMenu,NSMenuItem,NSFont,NSColor,NSBezierPath,NSGraphicsContext,NSAffineTransform,
    NSSegmentedControl,NSImage,NSImageSymbolConfiguration,NSScrollView,NSImageLeft,NSImageView,NSImageScaleProportionallyUpOrDown,NSBox,NSBoxCustom,NSNoTitle,NSLineBorder,
    NSButtonTypePushOnPushOff,NSCompositingOperationSourceOver,
    NSWindowStyleMaskTitled,NSWindowStyleMaskClosable,NSWindowStyleMaskUtilityWindow,
    NSBackingStoreBuffered,NSModalResponseOK,NSButtonTypeSwitch)
from Foundation import NSTimer
from .matching_native import MatchingHost
from .matching import prepare_match,apply_match,export_match
from .matching_hints import HintMappingError
from .matching_contract import parse_master_set,MAX_FILE
from .matching_preview import payload
from .matching_panel_state import (initial_master_pair,point_budget,MODE_LABELS,MODE_HELP,MATCH_SOURCE_MODES,
    settings_groups,preview_actions)
from .settings import TraceSettings,PRESETS
from .api import prepare_trace,apply_trace
from . import image_io
from .matching_preview import commands
from .contract import tight_bounds
from .ui import load_preferences,save_preferences
from .engine import default_engine
from .engine_settings import save_user_engine
from .adapter import RecoveryError
from .contract import CompanionError


def mode_image(index):
    """Compose the mixed/pair icons from native SF Symbols."""
    path='point.topleft.down.to.point.bottomright.curvepath'
    names=(('photo',),('photo.on.rectangle',),('photo',path),(path,path))[index]
    symbols=[NSImage.imageWithSystemSymbolName_accessibilityDescription_(name,MODE_LABELS[index]) for name in names]
    if any(symbol is None for symbol in symbols): return None
    configuration=NSImageSymbolConfiguration.configurationWithPointSize_weight_(20,0)
    symbols=[symbol.imageWithSymbolConfiguration_(configuration) for symbol in symbols]
    if len(symbols)==1: return symbols[0]
    result=NSImage.alloc().initWithSize_((44,24)); result.lockFocus()
    try:
        for i,symbol in enumerate(symbols):
            symbol.drawInRect_fromRect_operation_fraction_(((i*24,2),(20,20)),((0,0),(0,0)),NSCompositingOperationSourceOver,1.)
    finally: result.unlockFocus()
    result.setTemplate_(True)
    return result


class ModeIconView(NSImageView):
    def hitTest_(self,point): return None


class ModeLabelView(NSTextField):
    def hitTest_(self,point): return None


class ModeChooser(NSView):
    """One visible row of native icon buttons with a single selected mode."""
    def initWithFrame_(self,frame):
        self=objc.super(ModeChooser,self).initWithFrame_(frame)
        if self is not None:
            self.selection=3; self.controller=None; self.options=[]; self.icons=[]; self.labels=[]
            self.setWantsLayer_(True); self.layer().setCornerRadius_(10)
            self.layer().setBorderWidth_(.5)
            self.layer().setBorderColor_(NSColor.separatorColor().CGColor())
            for index,label in enumerate(MODE_LABELS):
                button=NSButton.alloc().initWithFrame_(((index*195+4,4),(187,60)))
                button.setTitle_(''); button.setFont_(NSFont.systemFontOfSize_(12))
                button.setBordered_(False); button.setButtonType_(NSButtonTypePushOnPushOff)
                icon=mode_image(index)
                if icon is not None:
                    icon=icon.copy(); size=(40 if index>1 else 30,28); icon.setSize_(size)
                    icon.setAlignmentRect_(((0,0),size))
                icon_view=ModeIconView.alloc().initWithFrame_(((71.5,6),(44,28)))
                icon_view.setImage_(icon); icon_view.setImageScaling_(NSImageScaleProportionallyUpOrDown)
                icon_view.setAccessibilityElement_(False); button.addSubview_(icon_view)
                title=ModeLabelView.labelWithString_(label); title.setFrame_(((0,38),(187,18)))
                title.setAlignment_(1); title.setFont_(NSFont.systemFontOfSize_(12))
                title.setAccessibilityElement_(False); button.addSubview_(title)
                self.icons.append(icon_view); self.labels.append(title)
                button.setTag_(index); button.setTarget_(self); button.setAction_('choose:')
                button.setToolTip_(MODE_HELP[index]); button.setAccessibilityLabel_(label)
                button.setAccessibilityHelp_(MODE_HELP[index])
                button.setWantsLayer_(True); button.layer().setCornerRadius_(8)
                self.addSubview_(button); self.options.append(button)
            self.setSelectedSegment_(3)
        return self

    @objc.python_method
    def selectedSegment(self): return self.selection

    @objc.python_method
    def setSelectedSegment_(self,index):
        self.selection=index
        for i,button in enumerate(self.options):
            selected=i==index; button.setState_(selected)
            color=NSColor.controlAccentColor() if selected else NSColor.labelColor()
            self.icons[i].setContentTintColor_(color); self.labels[i].setTextColor_(color)
            button.layer().setBackgroundColor_((NSColor.controlAccentColor().colorWithAlphaComponent_(.12)
                if selected else NSColor.clearColor()).CGColor())
            button.setAccessibilityValue_(bool(selected))

    @objc.python_method
    def setEnabled_(self,enabled):
        for button in self.options: button.setEnabled_(enabled)

    def choose_(self,sender):
        previous=self.selection; self.setSelectedSegment_(sender.tag())
        if self.selection!=previous and self.controller is not None: self.controller.modeChanged_(self)

    def viewDidChangeEffectiveAppearance(self):
        if not hasattr(self,'options') or self.layer() is None: return
        self.layer().setBorderColor_(NSColor.separatorColor().CGColor())
        self.setSelectedSegment_(self.selection)


class MatchingPreviewView(NSView):
    def initWithFrame_(self,frame):
        self=objc.super(MatchingPreviewView,self).initWithFrame_(frame)
        if self is not None:
            self.cache=None; self.style=0; self.images=[]
        return self

    def drawRect_(self,rect):
        NSColor.textBackgroundColor().set(); NSBezierPath.fillRect_(self.bounds())
        if self.cache is None: return
        width=self.bounds().size.width; height=self.bounds().size.height
        x0,y0,x1,y1=self.cache['bounds']; dx=max(1,x1-x0); dy=max(1,y1-y0)
        halves=self.style==1
        slot=width/2 if halves else width
        scale=min((slot-40)/dx,(height-40)/dy)
        colors=(NSColor.systemBlueColor(),NSColor.systemOrangeColor())

        def draw(commands,color,fill=False,nodes=False,line_width=1.2):
            path=NSBezierPath.bezierPath()
            for kind,values in commands:
                if kind=='M': path.moveToPoint_(values)
                elif kind=='L': path.lineToPoint_(values)
                elif kind=='C': path.curveToPoint_controlPoint1_controlPoint2_(values[4:6],values[:2],values[2:4])
                else: path.closePath()
            if fill: color.colorWithAlphaComponent_(.12).set(); path.fill()
            color.set(); path.setLineWidth_(line_width/scale); path.stroke()
            if nodes:
                for kind,values in commands:
                    if kind not in ('M','L','C'): continue
                    x,y=values[-2:]; radius=2.5/scale
                    NSBezierPath.bezierPathWithOvalInRect_(((x-radius,y-radius),(2*radius,2*radius))).fill()

        for half in range(2 if halves else 1):
            NSGraphicsContext.saveGraphicsState()
            try:
                matrix=NSAffineTransform.transform()
                matrix.translateXBy_yBy_(half*slot+(slot-dx*scale)/2-x0*scale,
                                         (height-dy*scale)/2-y0*scale)
                matrix.scaleBy_(scale); matrix.concat()
                if self.style!=2:
                    for index,snapshot in (() if self.cache['processed'] else self.images):
                        if halves and index!=half: continue
                        NSGraphicsContext.saveGraphicsState()
                        try:
                            g=snapshot.geometry
                            transform=NSAffineTransform.transform(); transform.setTransformStruct_(g.transform); transform.concat()
                            x,y,w,h=g.crop
                            snapshot.image.drawInRect_fromRect_operation_fraction_respectFlipped_hints_(
                                ((x,y),(w,h)),((x,y),(w,h)),NSCompositingOperationSourceOver,.2,False,None)
                        finally: NSGraphicsContext.restoreGraphicsState()
                    masters=self.cache.get('masters',self.cache['before'])
                    for index,commands in enumerate(masters):
                        if not halves or index==half: draw(commands,colors[index],nodes=self.cache['processed'])
                    draw(self.cache.get('diagnosticHighlights',[]),NSColor.systemRedColor(),line_width=2.5)
                    NSColor.systemRedColor().set()
                    for x,y in self.cache.get('diagnosticMarkers',[]):
                        radius=4/scale
                        NSBezierPath.bezierPathWithOvalInRect_(((x-radius,y-radius),(2*radius,2*radius))).fill()
                else:
                    draw(self.cache['after'],NSColor.labelColor(),fill=True,nodes=True)
            finally: NSGraphicsContext.restoreGraphicsState()


class MatchingWindowController(NSWindowController):
    def init(self):
        panel=NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(((180,120),(820,620)),
            NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow,NSBackingStoreBuffered,False)
        self=objc.super(MatchingWindowController,self).initWithWindow_(panel)
        if self is None: return None
        self.host=MatchingHost(); self.engine=default_engine(); self.job=None; self.plan=None; self.ctx=None
        self.closed=False; self.poisoned=False; self.imported=None; self.axis_confirmed=False
        self.pairs=[]; self.starts=[]; self.details=''; self.diagnostic=None; self.has_error=False
        self.selector_outlines=None; self.selector_indices=None; self.selector_context=None
        self.last_selection=None; self.hoi_available=False
        self.preview_key=None; self.pending_key=None; self.display_result=None; self.display_hoi=None
        self.input_key=None; self.next_source_check=0.; self.mode_index=3
        panel.setTitle_('Beztrace'); panel.setFloatingPanel_(True); panel.setReleasedWhenClosed_(False)
        panel.setDelegate_(self); self.content=panel.contentView()
        self.mode=ModeChooser.alloc().initWithFrame_(((20,532),(780,68)))
        self.mode.controller=self; self.mode.setAccessibilityLabel_('Vectorization mode')
        self.content.addSubview_(self.mode)
        self.reference_label=self.label('Reference',(126,0,88,18),13)
        self.reference=self.popup('referenceChanged:',(226,488,190,28))
        self.target_label=self.label('Target',(440,0,52,18),13)
        self.target=self.popup('targetChanged:',(504,488,190,28))
        self.reference.setAccessibilityLabel_('Reference master'); self.target.setAccessibilityLabel_('Target master')
        self.preview_surface=self.surface((20,64,544,412))
        self.inspector_surface=self.surface((576,64,224,412))
        self.preview_tabs=NSSegmentedControl.alloc().initWithFrame_(((32,436),(520,28)))
        self.preview_tabs.setSegmentCount_(3)
        for i,label in enumerate(('Overlay','Side by side','Interpolation')):
            self.preview_tabs.setLabel_forSegment_(label,i); self.preview_tabs.setWidth_forSegment_(170,i)
        self.preview_tabs.setSelectedSegment_(0); self.preview_tabs.setTarget_(self); self.preview_tabs.setAction_('previewStyleChanged:')
        self.preview_tabs.setAccessibilityLabel_('Preview display'); self.content.addSubview_(self.preview_tabs)
        self.preview=MatchingPreviewView.alloc().initWithFrame_(((32,134),(520,296)))
        self.preview.setAccessibilityLabel_('Glyph outline preview'); self.content.addSubview_(self.preview)
        self.low_label=self.label('',(32,0,58,18),11)
        self.slider=NSSlider.alloc().initWithFrame_(((102,104),(354,24))); self.slider.setMinValue_(0); self.slider.setMaxValue_(100)
        self.slider.setDoubleValue_(50); self.slider.setContinuous_(True); self.slider.setTarget_(self); self.slider.setAction_('sliderChanged:')
        self.slider.setAccessibilityLabel_('Interpolation axis'); self.content.addSubview_(self.slider)
        self.axis_label=self.label('',(468,0,84,18),11)
        self.position_label=self.label('',(192,84,174,18),10)
        self.position_label.setAlignment_(1)
        self.center_label(self.low_label,self.slider)
        self.center_label(self.axis_label,self.slider,right=False)
        self.layout_sources()
        self.status=self.label('',(32,68,510,24),11)
        self.status.cell().setWraps_(True); self.status.cell().setScrollable_(False)
        self.prepare_button=self.button('Update Preview','prepare:',(20,20,160,32))
        icon=NSImage.imageWithSystemSymbolName_accessibilityDescription_('arrow.triangle.2.circlepath','Update Preview')
        if icon is not None: self.prepare_button.setImage_(icon); self.prepare_button.setImagePosition_(NSImageLeft)
        self.cancel_button=self.button('Cancel','cancel:',(550,20,90,32)); self.cancel_button.setKeyEquivalent_('\x1b')
        self.apply_button=self.button('Apply to Masters','apply:',(652,20,148,32))
        self.menu=NSMenu.alloc().init(); self.menu.setAutoenablesItems_(False)
        self.details_item=NSMenuItem.alloc().initWithTitle_action_keyEquivalent_('Error Details…','showDetails:','')
        self.details_item.setTarget_(self); self.menu.addItem_(self.details_item)
        for title,action in [('Use current glyph','useSelection:'),('Import masters…','importFile:'),
                             ('Export masters…','exportFile:'),('Choose engine…','chooseEngine:')]:
            item=NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title,action,'')
            item.setTarget_(self); self.menu.addItem_(item)
            if action=='importFile:': self.import_button=item
            if action=='exportFile:': self.export_button=item
        self.build_options()
        stored,self.stored_advanced=load_preferences()
        for attr,key in (('accuracy','accuracy'),('smoothing','smoothing'),('corner','corner_threshold'),('grid','grid'),('specks','min_contour_area')):
            getattr(self,attr).setStringValue_(str(getattr(stored,key)))
        self.threshold.setStringValue_(str(stored.threshold)); self.invert.setState_(stored.invert)
        self.refine.setState_(stored.refine_raster); self.preset.selectItemWithTitle_(stored.preset)
        self.timer=NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(.04,self,'poll:',None,True)
        self.useSelection_(None); self.buttons()
        return self

    @objc.python_method
    def build_options(self):
        self.option_rows=[]
        def row(name,height,build):
            before=len(self.content.subviews()); build()
            self.option_rows.append((name,height,[(v,v.frame()) for v in list(self.content.subviews())[before:]]))
        def numeric(name,title,value,attribute):
            def build():
                label=self.label(title,(0,0,116,18),12)
                control=self.field(value,(128,0,72,24),title)
                self.center_label(label,control)
                setattr(self,attribute,control)
            row(name,32,build)
        def preset():
            label=self.label('Quality',(0,0,60,18),12)
            self.preset=self.popup('presetChanged:',(72,0,128,28)); self.preset.addItemsWithTitles_(list(PRESETS)+['Custom']); self.center_label(label,self.preset)
        row('preset',32,preset)
        numeric('fit','Fit tolerance','1','fit')
        self.fit.setToolTip_('Maximum fitting deviation in units per 1000 em')
        numeric('nodes','Node limit','64','max_points')
        self.max_points.setToolTip_('Maximum total nodes, including cubic handles, per master')
        def policy():
            self.policy=self.popup('settingsChanged:',(0,0,200,28))
            self.policy.addItemsWithTitles_(['Keep reference unchanged','Allow shared subdivision'])
        row('policy',34,policy)
        def check(name,title,attribute,state=0):
            def build():
                v=self.button(title,'settingsChanged:',(0,0,200,24)); v.setButtonType_(NSButtonTypeSwitch); v.setState_(state); v.setFont_(NSFont.systemFontOfSize_(11))
                setattr(self,attribute,v)
            row(name,30,build)
        check('smooth','Smooth compatible joins','smooth',1)
        self.smooth.setToolTip_('Adjust target handles within the fit tolerance; keep the reference, on-curves and node structure unchanged')
        check('repair','Native HOI correction','repair',0)
        check('invert','Invert image','invert')
        numeric('raster','Image threshold','auto','threshold')
        numeric('accuracy','Accuracy','2','accuracy')
        numeric('smoothing','Smoothing','1','smoothing')
        numeric('corner','Corner sensitivity','12','corner')
        numeric('grid','Grid','2','grid')
        numeric('specks','Remove specks','100','specks')
        check('refine','Refine raster','refine',1)
        numeric('extra','Additional on-curves','0','extra_points')
        numeric('kink','Kink threshold','1','kink')
        numeric('movement','Movement limit','5','movement')
        check('review','Review existing structure','review')
        check('manual','Manual correspondence','manual')
        def pairs():
            self.label('Contour correspondence',(0,64,200,20),11)
            self.contour=self.popup('contourChanged:',(0,32,68,28))
            self.pair=self.popup('pairChanged:',(76,32,124,28))
            self.start=self.popup('startChanged:',(0,0,200,28))
        row('pairs',88,pairs)
        def actions():
            self.more_button=self.button('Additional actions…','showMenu:',(0,0,200,28))
            self.more_button.setBordered_(False); self.more_button.setAlignment_(0)
        row('actions',32,actions)
        # Expanded dependent controls scroll within the fixed inspector.
        self.inspector=NSScrollView.alloc().initWithFrame_(((588,76),(200,388)))
        self.inspector.setHasVerticalScroller_(True); self.inspector.setAutohidesScrollers_(True)
        self.inspector.setDrawsBackground_(False); self.content.addSubview_(self.inspector)
        self.inspector_content=NSView.alloc().initWithFrame_(((0,0),(200,388)))
        self.inspector.setDocumentView_(self.inspector_content)
        for _,_,views in self.option_rows:
            for view,_ in views: view.removeFromSuperview(); self.inspector_content.addSubview_(view)
        self.group_labels={}
        for title in ('Image','Curves','Reference','Fitting','Correspondence','Interpolation'):
            label=self.label(title,(0,0,200,18),11)
            label.setFont_(NSFont.boldSystemFontOfSize_(11))
            label.setTextColor_(NSColor.secondaryLabelColor())
            label.removeFromSuperview(); self.inspector_content.addSubview_(label)
            self.group_labels[title]=label
        self.layout_options()

    @objc.python_method
    def layout_options(self):
        mode=self.mode.selectedSegment()
        groups=settings_groups(mode,hoi=self.hoi_available,repair=bool(self.repair.state()),
            shared=self.policy.indexOfSelectedItem()==1,manual=bool(self.manual.state()),
            review=mode==3 and bool(self.review.state()))
        rows={name:(h,views) for name,h,views in self.option_rows}
        self.visible_rows=[name for _,names in groups for name in names]
        height=max(388,16+sum((24 if title else 8)+sum(rows[name][0] for name in names)
                             for title,names in groups))
        self.inspector_content.setFrameSize_((200,height)); y=height-8
        for label in self.group_labels.values(): label.setHidden_(True)
        for title,names in groups:
            if title:
                label=self.group_labels[title]; label.setHidden_(False)
                label.setFrame_(((0,y-18),(200,18))); y-=24
            else: y-=8
            for name in names:
                h,views=rows[name]
                content_height=max(frame.origin.y+frame.size.height for _,frame in views)
                offset=y-content_height
                for view,frame in views: view.setFrame_(((frame.origin.x,offset+frame.origin.y),frame.size))
                y-=h
        for name,_,views in self.option_rows:
            for view,_ in views: view.setHidden_(name not in self.visible_rows)
        self.inspector.contentView().scrollToPoint_((0,max(0,height-388)))
        self.inspector.reflectScrolledClipView_(self.inspector.contentView())
        self.configure_key_order()

    def showMenu_(self,sender):
        self.menu.popUpMenuPositioningItem_atLocation_inView_(None,(0,0),sender)

    @objc.python_method
    def configure_key_order(self):
        views=self.mode.options+[self.reference,self.target,self.preview_tabs]
        rows={name:row for name,_,row in self.option_rows}
        for name in self.visible_rows:
            row=rows[name]
            views.extend(v for v,_ in row if not v.isHidden() and (
                isinstance(v,(NSButton,NSPopUpButton)) or isinstance(v,NSTextField) and v.isEditable()))
        views += [self.slider,self.prepare_button,self.cancel_button,self.apply_button]
        for first,second in zip(views,views[1:]+views[:1]): first.setNextKeyView_(second)

    @objc.python_method
    def center_label(self,label,control,right=True):
        """Center intrinsic label text on AppKit's actual control title rectangle."""
        frame=label.frame(); title=control.cell().titleRectForBounds_(control.bounds())
        if title.size.height<=0: title=control.bounds()
        height=label.cell().cellSize().height
        middle=control.frame().origin.y+title.origin.y+title.size.height/2
        label.setFrame_(((frame.origin.x,middle-height/2),(frame.size.width,height)))
        label.setAlignment_(2 if right else 0)

    @objc.python_method
    def layout_sources(self):
        single=self.mode_index==0
        self.target.setFrame_(((347 if single else 504,488),(190,28)))
        self.target_label.setFrame_(((283 if single else 440,0),(52,18)))
        self.center_label(self.reference_label,self.reference)
        self.center_label(self.target_label,self.target)

    @objc.python_method
    def surface(self,rect):
        box=NSBox.alloc().initWithFrame_(((rect[0],rect[1]),(rect[2],rect[3])))
        box.setBoxType_(NSBoxCustom); box.setTitlePosition_(NSNoTitle); box.setBorderType_(NSLineBorder)
        box.setBorderWidth_(.5); box.setCornerRadius_(8)
        box.setFillColor_(NSColor.textBackgroundColor()); box.setBorderColor_(NSColor.separatorColor())
        self.content.addSubview_(box)
        return box

    @objc.python_method
    def label(self,text,rect,size=12):
        v=NSTextField.labelWithString_(text); v.setFrame_(((rect[0],rect[1]),(rect[2],rect[3])))
        v.setFont_(NSFont.systemFontOfSize_(size)); self.content.addSubview_(v); return v
    @objc.python_method
    def button(self,title,action,rect):
        v=NSButton.alloc().initWithFrame_(((rect[0],rect[1]),(rect[2],rect[3])))
        v.setTitle_(title); v.setFont_(NSFont.systemFontOfSize_(13)); v.setBezelStyle_(1); v.setTarget_(self); v.setAction_(action)
        v.setAccessibilityLabel_(title); self.content.addSubview_(v); return v
    @objc.python_method
    def popup(self,action,rect):
        v=NSPopUpButton.alloc().initWithFrame_pullsDown_(((rect[0],rect[1]),(rect[2],rect[3])),False)
        v.setFont_(NSFont.systemFontOfSize_(13)); v.setTarget_(self); v.setAction_(action); v.setAccessibilityLabel_(action.rstrip(':'))
        self.content.addSubview_(v); return v
    @objc.python_method
    def field(self,text,rect,label):
        v=NSTextField.alloc().initWithFrame_(((rect[0],rect[1]),(rect[2],rect[3])))
        v.setStringValue_(text); v.setFont_(NSFont.systemFontOfSize_(13)); v.setDelegate_(self); v.setAccessibilityLabel_(label); self.content.addSubview_(v); return v
    @objc.python_method
    def set_status(self,message,error=False):
        self.has_error=error
        self.status.setStringValue_(message)
        self.status.setHidden_(not bool(message))
        self.position_label.setHidden_(self.mode_index==0 or bool(message))
        self.status.setTextColor_(NSColor.systemRedColor() if error else NSColor.labelColor())
    @objc.python_method
    def failure(self,exc):
        if self.job is not None: self.job.cancel()
        self.job=None; self.preview_key=None
        self.plan=None
        self.display_result=None; self.display_hoi=None
        self.diagnostic=getattr(exc,'diagnostic',None)
        self.set_status(str(exc),error=True); self.details=traceback.format_exc()
        if self.diagnostic is not None:
            import json
            self.details+='\n'+json.dumps(self.diagnostic,sort_keys=True,indent=2)
        if self.ctx is None:
            self.preview.cache=None; self.preview.setNeedsDisplay_(True)
        try: self.refresh_preview()
        except Exception:
            self.preview.cache=None; self.preview.setNeedsDisplay_(True)
        self.buttons()
    @objc.python_method
    def invalidate(self):
        if self.job is not None: self.job.cancel()
        if self.plan is not None:
            (self.plan.cancel if self.mode_index==0 else self.plan.cancel_event).set()
        self.job=None; self.plan=None; self.preview_key=None; self.diagnostic=None; self.details=''
        if self.preview.cache is not None:
            self.preview.cache['diagnosticMarkers']=[]; self.preview.cache['diagnosticHighlights']=[]
            self.preview.setNeedsDisplay_(True)
        self.buttons()

    @objc.python_method
    def input_signature(self):
        mode=self.mode.selectedSegment()
        values=self.trace_options() if mode==0 else self.settings()
        if mode in (1,2): values=dict(values,raster=self.raster_options())
        if mode==3: values=dict(values,review=bool(self.review.state()))
        return (mode,self.engine,self.reference.indexOfSelectedItem(),self.target.indexOfSelectedItem(),
                repr(sorted(values.items())),self.imported,self.axis_confirmed)

    @objc.python_method
    def source_usable(self):
        if self.ctx is None or self.closed or self.poisoned: return False
        mode=self.mode.selectedSegment()
        targets=self.ctx['targets']
        images=[getattr(t.layer,'backgroundImage',None) is not None for t in targets]
        if mode==0: return bool(images[0])
        if self.imported is not None: return True
        if mode==1: return all(images)
        if mode==2: return bool(self.ctx['outlines'][0]['contours'] and images[1])
        return all(o['contours'] for o in self.ctx['outlines'])

    @objc.python_method
    def source_help(self):
        return ('Place a PNG or JPEG on the selected layer.',
                'Place a canvas image in each selected master.',
                'The reference needs outlines and the target needs a canvas image.',
                'Both selected masters need outlines.')[self.mode_index]

    @objc.python_method
    def buttons(self):
        busy=self.job is not None
        usable=self.source_usable()
        try: key=self.input_signature()
        except (ValueError,CompanionError): key=None; usable=False
        current=self.preview_key is not None and key==self.preview_key and self.plan is not None
        valid=current and not self.plan.consumed and not getattr(self.plan,'apply_error',None)
        if self.mode_index!=0 and valid:
            valid=not self.plan.poisoned and (self.plan.hoi is None or
                  self.plan.hoi['nativeVerified'] and not self.plan.hoi['unresolved'])
        actions=preview_actions(usable,busy,current,valid)
        self.primary_action='apply' if actions['apply'] else 'processing' if busy else 'process' if actions['update'] else 'unavailable'
        self.prepare_button.setTitle_('Updating…' if busy else 'Update Preview')
        self.prepare_button.setEnabled_(actions['update']); self.prepare_button.setHidden_(False)
        self.prepare_button.setBezelColor_(None); self.prepare_button.setKeyEquivalent_('')
        self.apply_button.setHidden_(False); self.apply_button.setEnabled_(actions['apply'])
        self.apply_button.setTitle_('Apply to Layer' if self.mode_index==0 else 'Apply to Masters')
        self.apply_button.setBezelColor_(NSColor.controlAccentColor() if actions['apply'] else None)
        self.apply_button.setKeyEquivalent_('\r' if actions['apply'] else '')
        self.window().setDefaultButtonCell_(self.apply_button.cell() if actions['apply'] else None)
        self.cancel_button.setEnabled_(True); self.cancel_button.setHidden_(False)
        self.export_button.setEnabled_(actions['apply'] and self.mode_index!=0)
        self.import_button.setEnabled_(self.ctx is not None and self.mode_index!=0 and not busy and not self.poisoned)
        self.more_button.setEnabled_(not busy)
        self.mode.setEnabled_(not busy); self.reference.setEnabled_(not busy); self.target.setEnabled_(not busy and self.mode_index!=0)
        self.details_item.setHidden_(not self.has_error)
        self.slider.setEnabled_(bool(self.display_result is not None and self.mode_index!=0 and not busy))
        for v in (self.slider,self.low_label,self.axis_label): v.setHidden_(self.mode_index==0)
        self.position_label.setHidden_(self.mode_index==0 or bool(self.status.stringValue()))
        for i in (1,2): self.preview_tabs.setEnabled_forSegment_(self.mode_index!=0,i)
        for _,_,views in self.option_rows:
            for view,_ in views:
                if hasattr(view,'setEnabled_'): view.setEnabled_(not busy and not self.poisoned)
        # Shared planning for images is explicit in the selected mode, never a fallback.
        self.policy.setEnabled_(not busy and self.mode_index in (2,3) and not (self.mode_index==3 and self.review.state()))
        self.extra_points.setEnabled_(not busy and self.policy.indexOfSelectedItem()==1)
        self.smooth.setEnabled_(not busy and not self.poisoned and self.imported is None)
        self.configure_key_order()

    def useSelection_(self,sender):
        self.invalidate(); self.imported=None; self.axis_confirmed=False
        self.selector_outlines=None; self.selector_indices=None; self.selector_context=None
        self.display_result=None; self.display_hoi=None; self.preview.cache=None; self.preview.images=[]
        self.reference.removeAllItems(); self.target.removeAllItems()
        try:
            _,font,glyph,owner,destination=self.host.current_selection()
            self.font=font; self.glyph_name=str(glyph.name); self.master_ids=[str(m.id) for m in font.masters]
            if self.mode_index==0:
                self.single_layer_id=str(owner.layerId); self.single_destination=destination
                self.ctx=self.single_context()
                self.target.addItemWithTitle_(str(owner.name)+(' · Background' if destination=='background' else '')); self.target.setEnabled_(False)
                self.pairs=[]; self.starts=[]; self.hoi_available=False
            else:
                if destination!='foreground': raise CompanionError('Select an ordinary foreground master layer')
                previous=self.last_selection[1] if self.last_selection is not None and self.last_selection[0] is font else None
                reference,target=initial_master_pair(self.master_ids,str(owner.layerId),previous)
                self.last_selection=(font,str(owner.layerId))
                self.ctx=self.host.context(font,self.glyph_name,self.master_ids[reference])
                count=sum(len(p['nodes']) for p in self.ctx['outlines'][0]['contours'])
                self.extra_points.setStringValue_('0')
                self.max_points.setStringValue_(str(min(4096,max(64 if self.mode_index==1 else 3,(count*5+3)//4))))
                names=[str(m.name) for m in font.masters]
                for popup in (self.reference,self.target): popup.addItemsWithTitles_(names)
                self.reference.selectItemAtIndex_(reference)
                self.target.selectItemAtIndex_(target)
                self.slider.setDoubleValue_(50)
                self.reset_pairs(); self.hoi_available=self.host.hoi_available()
                if not self.hoi_available: self.repair.setState_(0)
            self.capture_images(); self.set_status('' if self.source_usable() else self.source_help())
            self.input_key=self.input_signature(); self.layout_options(); self.refresh_preview()
        except Exception as exc: self.ctx=None; self.failure(exc)
        self.reference.setHidden_(self.mode_index==0); self.reference_label.setHidden_(self.mode_index==0)
        self.target_label.setStringValue_('Layer' if self.mode_index==0 else 'Target')
        self.layout_sources(); self.buttons()
        if self.mode_index==0: self.target.setEnabled_(False)

    @objc.python_method
    def single_context(self):
        target=self.host.target(self.font,self.glyph_name,self.single_layer_id,self.single_destination)
        paths=[self.host.path_data(p) for p in target.layer.paths]
        return dict(targets=[target],outlines=[dict(contours=[]),dict(contours=paths)],
                    axis=dict(tag='',locations=[0,1]))

    @objc.python_method
    def capture_images(self):
        self.preview.images=[]
        if self.ctx is None: return
        mode=self.mode_index
        for i,t in enumerate(self.ctx['targets']):
            image=getattr(t.layer,'backgroundImage',None)
            if image is not None and (mode==0 or mode==1 or mode==2 and i==1):
                self.preview.images.append((1 if mode==0 else i,image_io.snapshot(image)))

    def modeChanged_(self,sender):
        self.mode_index=self.mode.selectedSegment()
        # Cancel the previous plan using its own mode, before replacing context.
        if self.plan is not None:
            getattr(self.plan,'cancel',getattr(self.plan,'cancel_event',None)).set()
            self.plan=None
        self.policy.selectItemAtIndex_(1 if self.mode_index==1 else 0)
        self.review.setState_(0); self.manual.setState_(0)
        self.preview_tabs.setSelectedSegment_(0); self.preview.style=0
        self.useSelection_(None)

    def previewStyleChanged_(self,sender):
        self.preview.style=self.preview_tabs.selectedSegment(); self.preview.setNeedsDisplay_(True)

    @objc.python_method
    def trace_options(self):
        threshold=self.threshold.stringValue().strip()
        settings=TraceSettings(threshold='auto' if threshold=='auto' else int(threshold),invert=bool(self.invert.state()),
            accuracy=float(self.accuracy.stringValue()),smoothing=float(self.smoothing.stringValue()),
            corner_threshold=float(self.corner.stringValue()),grid=int(self.grid.stringValue()),
            min_contour_area=float(self.specks.stringValue()),refine_raster=bool(self.refine.state()))
        return settings.engine_options()

    @objc.python_method
    def raster_options(self):
        threshold=self.threshold.stringValue().strip()
        if threshold!='auto' and not 0<=int(threshold)<=255: raise CompanionError('Image threshold must be auto or 0–255')
        return dict(threshold=None if threshold=='auto' else int(threshold),invert=bool(self.invert.state()))

    def presetChanged_(self,sender):
        name=str(self.preset.titleOfSelectedItem())
        if name not in PRESETS: return
        values=TraceSettings().applying_preset(name)
        for attr,key in (('accuracy','accuracy'),('smoothing','smoothing'),('corner','corner_threshold'),('grid','grid'),('specks','min_contour_area')):
            getattr(self,attr).setStringValue_(str(getattr(values,key)))
        self.refine.setState_(values.refine_raster); self.settingsChanged_(sender)

    @objc.python_method
    def reset_pairs(self):
        outlines=self.selector_outlines or self.ctx['outlines']
        count=len(outlines[0]['contours']); self.pairs=[-1]*count; self.starts=[-1]*count
        self.contour.removeAllItems(); self.contour.addItemsWithTitles_([str(i) for i in range(count)])
        self.contourChanged_(None)
    def referenceChanged_(self,sender):
        self.target.selectItemAtIndex_(1-self.reference.indexOfSelectedItem()); self.rebind()
    def targetChanged_(self,sender):
        self.reference.selectItemAtIndex_(1-self.target.indexOfSelectedItem()); self.rebind()
    @objc.python_method
    def rebind(self):
        self.invalidate(); self.imported=None
        self.display_result=None; self.display_hoi=None
        self.selector_outlines=None; self.selector_indices=None; self.selector_context=None
        try:
            ref=self.master_ids[self.reference.indexOfSelectedItem()]
            self.ctx=self.host.context(self.font,self.glyph_name,ref)
            self.slider.setDoubleValue_(50)
            self.reset_pairs(); self.capture_images(); self.refresh_preview()
            self.set_status('' if self.source_usable() else self.source_help())
            self.input_key=self.input_signature()
        except Exception as exc: self.ctx=None; self.failure(exc)
        self.buttons()

    def settingsChanged_(self,sender):
        try:
            key=self.input_signature()
            if key!=self.input_key:
                self.invalidate(); self.input_key=key; self.set_status('')
            if self.mode_index==0:
                options=self.trace_options()
                trace_settings=TraceSettings(**options)
                self.preset.selectItemWithTitle_(trace_settings.preset)
                save_preferences(trace_settings,self.stored_advanced)
        except (ValueError,CompanionError) as exc:
            self.invalidate(); self.input_key=None; self.set_status(str(exc),error=True)
        self.layout_options(); self.buttons()

    def controlTextDidChange_(self,notification): self.settingsChanged_(None)
    def contourChanged_(self,sender):
        i=self.contour.indexOfSelectedItem()
        self.pair.removeAllItems(); self.start.removeAllItems(); self.pair.addItemWithTitle_('Automatic'); self.start.addItemWithTitle_('Automatic')
        if i<0 or self.ctx is None: return
        paths=(self.selector_outlines or self.ctx['outlines'])[1]['contours']
        self.pair.addItemsWithTitles_([str(j) for j in range(len(paths))]); self.pair.selectItemAtIndex_(self.pairs[i]+1)
        target=self.pairs[i] if self.pairs[i]>=0 else min(i,len(paths)-1)
        self.start_indices=[]
        if target>=0:
            self.start_indices=[self.selector_indices[1][target][j] if self.selector_indices else j
                                for j,n in enumerate(paths[target]['nodes']) if n['type']!='offcurve']
            self.start.addItemsWithTitles_(['Node %d'%j for j in self.start_indices])
            if self.starts[i] in self.start_indices: self.start.selectItemAtIndex_(self.start_indices.index(self.starts[i])+1)
    def pairChanged_(self,sender):
        i=self.contour.indexOfSelectedItem()
        if i>=0: self.pairs[i]=self.pair.indexOfSelectedItem()-1; self.starts[i]=-1
        self.contourChanged_(None); self.settingsChanged_(None)
    def startChanged_(self,sender):
        i=self.contour.indexOfSelectedItem(); choice=self.start.indexOfSelectedItem()
        if i>=0: self.starts[i]=-1 if choice==0 else self.start_indices[choice-1]
        self.settingsChanged_(None)
    @objc.python_method
    def settings(self):
        manual=self.mode_index in (2,3) and bool(self.manual.state()) and not (self.mode_index==3 and self.review.state())
        if manual and any(v>=0 for v in self.pairs) and any(v<0 for v in self.pairs):
            raise CompanionError('Choose every contour pair, or leave every pair Automatic')
        source_mode=MATCH_SOURCE_MODES[self.mode_index]
        shared=self.mode_index==1 or self.policy.indexOfSelectedItem()==1
        budget=point_budget(self.ctx['outlines'][0] if self.ctx else None,
                            int(self.extra_points.stringValue()) if shared and self.mode_index!=1 else 0,
                            int(self.max_points.stringValue()),source_mode)
        result=dict(referencePolicy='shared-subdivision' if shared else 'fixed',
                    fitTolerance=float(self.fit.stringValue()),kinkThreshold=float(self.kink.stringValue()) if self.repair.state() else 1.,
                    maxShapeMovement=float(self.movement.stringValue()) if self.repair.state() else 5.,
                    smoothJoins=bool(self.smooth.state()),repairHOI=bool(self.hoi_available and self.repair.state()),**budget,
                    contourPairs=self.pairs if manual and self.pairs and min(self.pairs)>=0 else [],
                    startNodes=self.starts if manual and any(v>=0 for v in self.starts) else [])
        from .matching import options
        return options(result)

    def prepare_(self,sender):
        if not self.prepare_button.isEnabled(): return
        self.invalidate()
        try:
            self.pending_key=self.input_signature()
            if self.mode_index==0:
                self.ctx=self.single_context(); self.capture_images()
                self.job=prepare_trace(self.font,self.glyph_name,self.single_layer_id,destination=self.single_destination,
                                       options=self.trace_options(),engine=self.engine,_host=self.host)
            else:
                if self.selector_context is not None:
                    try: self.host.revalidate_match(self.selector_context)
                    except Exception:
                        self.selector_outlines=None; self.selector_indices=None; self.selector_context=None; self.reset_pairs()
                        raise CompanionError('The image changed. Update with automatic correspondence.')
                settings=self.settings(); ref=self.master_ids[self.reference.indexOfSelectedItem()]
                source_mode=3 if self.mode_index==3 and self.review.state() else MATCH_SOURCE_MODES[self.mode_index]
                self.job=prepare_match(self.font,self.glyph_name,ref,settings=settings,engine=self.engine,
                                       imported=self.imported,confirm_axis=self.axis_confirmed,source_mode=source_mode,
                                       _host=self.host,raster_options=self.raster_options() if self.mode_index in (1,2) else None)
                self.ctx=self.job.context; self.capture_images()
            self.set_status('Updating…')
        except Exception as exc: self.failure(exc)
        self.buttons()

    def poll_(self,timer):
        if self.closed: return
        if self.job is not None:
            if self.mode_index!=0: self.job.advance(); self.set_status(self.job.progress)
            if self.job.done:
                job=self.job; self.job=None
                try:
                    self.plan=job.plan
                    if self.mode_index==0:
                        from .adapter import revalidate
                        revalidate(self.host,self.plan.target)
                        image_io.revalidate(self.host,self.plan.target,self.plan.image,self.plan.source_hash)
                        self.display_result=self.plan.paths; self.display_hoi=None
                    else:
                        self.ctx=self.plan.context; self.display_result=self.plan.result; self.display_hoi=self.plan.hoi
                    self.preview_key=self.pending_key; self.input_key=self.pending_key
                    self.diagnostic=None
                    self.details=str(self.plan.result)
                    self.set_status('Some kinks remain. Adjust the Interpolation settings.' if self.mode_index!=0 and
                                    self.plan.hoi is not None and self.plan.hoi['unresolved'] else '')
                    self.refresh_preview()
                except Exception as exc:
                    if getattr(job,'planning',None) is not None:
                        self.selector_outlines=job.planning['outlines']; self.selector_indices=job.planning['sourceNodeIndices']; self.selector_context=job.context
                        self.reset_pairs()
                    self.failure(exc)
            self.buttons()
        elif self.plan is not None and time.monotonic()>=self.next_source_check:
            self.next_source_check=time.monotonic()+.5
            try:
                if self.mode_index==0:
                    from .adapter import revalidate
                    revalidate(self.host,self.plan.target)
                    image_io.revalidate(self.host,self.plan.target,self.plan.image,self.plan.source_hash)
                else: self.host.revalidate_match(self.plan.context)
            except Exception:
                self.invalidate()  # The enabled update button is the only stale indicator.

    def cancel_(self,sender):
        if self.job is not None: self.invalidate(); self.set_status(''); return
        self.window().performClose_(None)

    def apply_(self,sender):
        if not self.apply_button.isEnabled(): return
        try:
            if self.input_signature()!=self.preview_key: self.invalidate(); return
            if self.mode_index==0:
                result=apply_trace(self.plan,_host=self.host); self.useSelection_(None)
            else:
                result=apply_match(self.plan); self.rebind()
            self.set_status(result['warning'] or '')
        except HintMappingError as exc:
            # Application-only refusal: retain the reviewed outlines and slider.
            self.set_status(str(exc),error=True); self.details=str(exc)
        except RecoveryError as exc: self.poisoned=True; self.failure(exc)
        except Exception as exc: self.failure(exc)
        self.buttons()

    def sliderChanged_(self,sender): self.refresh_preview()

    @objc.python_method
    def refresh_preview(self):
        if self.ctx is None:
            self.preview.cache=None; self.preview.setNeedsDisplay_(True); return
        factor=round(self.slider.doubleValue())/100
        if self.mode_index==0:
            paths=self.display_result or self.ctx['outlines'][1]['contours']
            self.preview.cache=dict(bounds=tight_bounds(paths) if paths else (0,0,1000,1000),
                before=[[],commands(paths)],masters=[[],commands(paths)],after=commands(paths),links=[],
                processed=self.display_result is not None,diagnosticMarkers=[],diagnosticHighlights=[])
        else:
            context=dict(self.ctx,outlines=self.selector_outlines) if self.selector_outlines and self.display_result is None else self.ctx
            self.preview.cache=payload(context,self.display_result,self.display_hoi,factor,diagnostic=self.diagnostic)
            locations=self.ctx['axis']['locations']; lo,hi=min(locations),max(locations)
            names={str(m.id):str(m.name) for m in self.font.masters}
            low=0 if locations[0]<locations[1] else 1
            self.low_label.setStringValue_(names[str(self.ctx['targets'][low].owner.layerId)])
            self.axis_label.setStringValue_(names[str(self.ctx['targets'][1-low].owner.layerId)])
            self.position_label.setStringValue_('%d%%'%round(factor*100))
            self.position_label.setToolTip_('%s %.4g'%(self.ctx['axis']['tag'],lo+(hi-lo)*factor))
        if self.display_result is None and self.preview.images:
            points=[]
            for _,snap in self.preview.images:
                x,y,w,h=snap.geometry.crop; a,b,c,d,tx,ty=snap.geometry.transform
                points.extend((a*px+c*py+tx,b*px+d*py+ty) for px,py in ((x,y),(x+w,y),(x,y+h),(x+w,y+h)))
            x0,y0,x1,y1=self.preview.cache['bounds']
            self.preview.cache['bounds']=(min([x0]+[p[0] for p in points]),min([y0]+[p[1] for p in points]),
                max([x1]+[p[0] for p in points]),max([y1]+[p[1] for p in points]))
        self.preview.setNeedsDisplay_(True)

    def importFile_(self,sender):
        dialog=NSOpenPanel.openPanel(); dialog.setAllowedFileTypes_(['json']); dialog.setAllowsMultipleSelection_(False)
        if dialog.runModal()!=NSModalResponseOK: return
        try:
            path=Path(str(dialog.URL().path()))
            if path.stat().st_size>MAX_FILE: raise CompanionError('File exceeds 16 MiB')
            data=path.read_bytes(); result=parse_master_set(data)
            native=result.get('extensions',{}).get('glyphs4',{})
            imported_hoi=bool(native.get('entries') or native.get('preserved'))
            if imported_hoi and not self.hoi_available:
                raise CompanionError('This file includes native HOI; choose a Glyphs build that can verify it before importing')
            alert=NSAlert.alloc().init(); alert.setMessageText_('Map imported masters')
            alert.setInformativeText_('Map %s to %s and %s to %s on %s? UPM must match. Native HOI will be checked again.'%(
                result['reference']['id'],self.reference.titleOfSelectedItem(),result['target']['id'],self.target.titleOfSelectedItem(),self.ctx['axis']['tag']))
            alert.addButtonWithTitle_('Map and Preview'); alert.addButtonWithTitle_('Cancel')
            if alert.runModal()!=1000: return
            self.imported=data; self.axis_confirmed=True; self.mode.setSelectedSegment_(3); self.mode_index=3; self.policy.setEnabled_(True)
            self.policy.selectItemAtIndex_(0 if result['options']['referencePolicy']=='fixed' else 1)
            self.fit.setStringValue_(str(result['options']['fitTolerance']*1000/result['unitsPerEm']))
            self.smooth.setState_(bool(result['options'].get('smoothJoins',False)))
            self.repair.setState_(imported_hoi)
            self.extra_points.setStringValue_(str(result['options'].get('maxAdditionalOnCurveNodes',0)))
            self.max_points.setStringValue_(str(result['options'].get('maxNodes',64)))
            self.layout_options(); self.buttons(); self.prepare_(None)
        except Exception as exc: self.failure(exc)
    def exportFile_(self,sender):
        try:
            data=export_match(self.plan); dialog=NSSavePanel.savePanel(); dialog.setAllowedFileTypes_(['json'])
            dialog.setNameFieldStringValue_(self.glyph_name+'-masters.json')
            if dialog.runModal()==NSModalResponseOK: Path(str(dialog.URL().path())).write_bytes(data)
        except Exception as exc: self.failure(exc)
    def chooseEngine_(self,sender):
        dialog=NSOpenPanel.openPanel(); dialog.setAllowsMultipleSelection_(False)
        if dialog.runModal()==NSModalResponseOK:
            try:
                executable=str(dialog.URL().path()); save_user_engine(executable)
                self.engine=executable; self.settingsChanged_(None)
            except Exception as exc: self.failure(exc)
    def showDetails_(self,sender):
        alert=NSAlert.alloc().init(); alert.setMessageText_('Beztrace matching details')
        alert.setInformativeText_(self.details[:8000] or 'Update the preview to see its details.'); alert.runModal()
    def windowWillClose_(self,notification):
        self.invalidate(); self.closed=True; self.mode.controller=None
        if self.timer is not None: self.timer.invalidate(); self.timer=None
