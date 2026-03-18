/*
 * Filename: appine_core.m
 * Project: Appine (App in Emacs)
 * Description: Emacs dynamic module to embed native macOS views 
 *              (WebKit, PDFKit, Quick Look, etc.) directly inside Emacs windows.
 * Author: Huang Chao <huangchao.cpp@gmail.com>
 * Copyright (C) 2026, Huang Chao, all rights reserved.
 * URL: https://github.com/chaoswork/appine
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#import <stdatomic.h>
#import <signal.h>
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "appine_core.h"
#import "appine_backend.h"

// ==========================================
// 日志系统
// ==========================================
static BOOL g_appine_debug_log = NO;

#define APPINE_LOG(fmt, ...) do { \
    if (g_appine_debug_log) { \
        NSLog((@"[appine] " fmt), ##__VA_ARGS__); \
    } \
} while(0)

void appine_core_set_debug_log(int enable) {
    g_appine_debug_log = (enable != 0);
    NSLog(@"[appine] Debug logging %@", g_appine_debug_log ? @"enabled" : @"disabled");
}

// ==========================================
// 辅助 SIGUSR1 信号源判断
// ==========================================
static atomic_bool appine_deactivate_flag = false;
bool appine_core_check_signal(void) {
    // 检查并重置为 false
    return atomic_exchange(&appine_deactivate_flag, false);
}

// ==========================================
// 全局事件拦截器，主要用来 DEBUG 
// ==========================================
static void appine_setup_global_event_monitor(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
            NSView *hitView = nil;
            if (event.window && event.window.contentView) {
                hitView = [event.window.contentView hitTest:event.locationInWindow];
            }
            
            if (g_appine_debug_log) {
                NSLog(@"[appine] GLOBAL CLICK at %@, hitTest view: %@, window: %@", 
                      NSStringFromPoint(event.locationInWindow), [hitView className], [event.window className]);
            }
            
            // 绕过 Emacs 事件黑洞
            if ([hitView isKindOfClass:[NSSegmentedControl class]]) {
                NSSegmentedControl *tabControl = (NSSegmentedControl *)hitView;
                NSPoint loc = [tabControl convertPoint:event.locationInWindow fromView:nil];
                NSInteger count = tabControl.segmentCount;
                if (count > 0) {
                    CGFloat width = tabControl.bounds.size.width / count;
                    NSInteger clickedIdx = (NSInteger)(loc.x / width);
                    if (clickedIdx >= 0 && clickedIdx < count && [tabControl isEnabledForSegment:clickedIdx]) {
                        tabControl.selectedSegment = clickedIdx;
                        if (tabControl.target && tabControl.action) {
                            #pragma clang diagnostic push
                            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            [tabControl.target performSelector:tabControl.action withObject:tabControl];
                            #pragma clang diagnostic pop
                        }
                    }
                }
                return nil;
            } 
            else if ([hitView isKindOfClass:[NSButton class]]) {
                NSButton *btn = (NSButton *)hitView;
                if (btn.isEnabled) {
                    if (btn.target && btn.action) {
                        #pragma clang diagnostic push
                        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [btn.target performSelector:btn.action withObject:btn];
                        #pragma clang diagnostic pop
                    }
                }
                return nil;
            }
            // 允许点击任何输入框 (如地址栏) 时强制获取焦点
            else if ([hitView isKindOfClass:[NSTextField class]] || [hitView isKindOfClass:[NSTextView class]]) {
                [event.window makeFirstResponder:hitView];
                return event;
            }
            
            return event;
        }];
    });
}

extern id<AppineBackend> appine_create_web_backend(NSString *urlString);
extern id<AppineBackend> appine_create_pdf_backend(NSString *path);
extern id<AppineBackend> appine_create_quicklook_backend(NSString *path);
static id<AppineBackend> appine_create_backend_for_file(NSString *path) {
    // 智能判断使用appine_create_quicklook_backend, appine_create_pdf_backend
    // 或者 appine_create_web_backend
    if (!path || path.length == 0) return nil;
    
    UTType *fileType = [UTType typeWithFilenameExtension:path.pathExtension];
    
    if ([fileType conformsToType:UTTypePDF]) {
        return appine_create_pdf_backend(path);
    } 
    else if ([fileType conformsToType:UTTypeHTML] || 
             [fileType conformsToType:UTTypeWebArchive]) {
        NSURL *url = [NSURL fileURLWithPath:path];
        return appine_create_web_backend(url.absoluteString);
    } 
    else {
        BOOL isSafeForQuickLook = NO;
        
        if (fileType != nil) {
            // 【白名单】
            NSArray<UTType *> *safeTypes = @[
                UTTypeContent, UTTypeText, UTTypeSourceCode,
                UTTypeScript, UTTypeLog, UTTypeJSON, UTTypeXML
            ];
            for (UTType *safeType in safeTypes) {
                if ([fileType conformsToType:safeType]) {
                    isSafeForQuickLook = YES;
                    break;
                }
            }
            
            // 【黑名单】
            if ([fileType conformsToType:UTTypeExecutable] ||
                [fileType conformsToType:UTTypeArchive] ||
                [fileType conformsToType:UTTypeDiskImage] ||
                [fileType conformsToType:UTTypeApplication] ||
                [fileType conformsToType:UTTypePluginBundle] ||
                [fileType conformsToType:UTTypeFramework] ||
                [fileType conformsToType:UTTypeFolder]) {
                isSafeForQuickLook = NO;
            }
        }
        
        if (isSafeForQuickLook) {
            return appine_create_quicklook_backend(path);
        } else {
            NSString *ext = path.pathExtension.length > 0 ? path.pathExtension : @"无后缀/未知";
            NSLog(@"[Appine] 拦截了不支持或可能导致崩溃的文件类型: %@", ext);
            
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"不支持预览该文件";
            alert.informativeText = [NSString stringWithFormat:@"Appine 无法安全地预览此类型的文件 (%@)。\n为防止底层渲染服务崩溃，已拦截此操作。", ext];
            [alert runModal];
            return nil;
        }
    }
}


static const CGFloat kAppineToolbarHeight = 34.0;
static const CGFloat kAppineTabBarHeight = 28.0;

#pragma mark - Models & State

@interface AppineTabItem : NSObject
@property(nonatomic, assign) NSInteger tabId;
@property(nonatomic, strong) id<AppineBackend> backend;
@end
@implementation AppineTabItem
@end

@interface AppineState : NSObject
@property(nonatomic, weak) NSWindow *hostWindow;
@property(nonatomic, strong) NSView *containerView;
@property(nonatomic, strong) NSView *toolbarView;
@property(nonatomic, strong) NSStackView *toolbarStack;
@property(nonatomic, strong) NSView *tabBarView;
@property(nonatomic, strong) NSSegmentedControl *tabControl;
@property(nonatomic, strong) NSView *contentHostView;
@property(nonatomic, strong) NSView *inactiveOverlayView;
@property(nonatomic, strong) NSMutableArray<AppineTabItem *> *tabs;
@property(nonatomic, assign) NSInteger activeTabId;
@property(nonatomic, assign) NSInteger nextTabId;
@property(nonatomic, assign) NSRect targetRect;
@property(nonatomic, assign) BOOL isActive;
@end
@implementation AppineState
@end

static AppineState *appine_state(void) {
    static AppineState *g_state = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_state = [[AppineState alloc] init];
        g_state.tabs = [NSMutableArray array];
        g_state.activeTabId = -1;
        g_state.nextTabId = 1;
    });
    return g_state;
}

#pragma mark - Helpers

static AppineTabItem *appine_find_tab(NSInteger tabId) {
    for (AppineTabItem *item in appine_state().tabs) {
        if (item.tabId == tabId) return item;
    }
    return nil;
}

static NSWindow *appine_target_window(void) {
    AppineState *state = appine_state();
    if (state.hostWindow) return state.hostWindow;
    if ([NSApp keyWindow]) return [NSApp keyWindow];
    return [[NSApp windows] firstObject];
}

static void appine_apply_visual_state(void);
static void appine_apply_rect(void);
static void appine_rebuild_tabs(void);
static void appine_attach_active_view(void);
static void appine_set_active(BOOL active);
static void appine_add_tab(id<AppineBackend> backend);

#pragma mark - Core Magic Overlay

@interface AppineInactiveOverlayView : NSView
@end
@implementation AppineInactiveOverlayView
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.65 alpha:0.35] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
    [[NSColor colorWithCalibratedWhite:0.45 alpha:0.75] setStroke];
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    [path setLineWidth:1.0];
    [path stroke];
}
- (NSView *)emacsTargetViewForEvent:(NSEvent *)event {
    AppineState *state = appine_state();
    if (!state.containerView) return self.window.contentView;
    BOOL wasHidden = state.containerView.isHidden;
    state.containerView.hidden = YES;
    NSView *target = [self.window.contentView hitTest:event.locationInWindow];
    state.containerView.hidden = wasHidden;
    return target ?: self.window.contentView;
}

- (void)mouseDown:(NSEvent *)e {
    AppineState *state = appine_state();
    NSView *nativeTarget = nil;
    if (state.containerView) {
        BOOL overlayWasHidden = self.isHidden;
        self.hidden = YES;
        nativeTarget = [self.window.contentView hitTest:e.locationInWindow];
        self.hidden = overlayWasHidden;
    }
    
    BOOL isNativeControl = (nativeTarget && (nativeTarget == state.tabControl || [nativeTarget isKindOfClass:[NSControl class]]));
    NSView *target = [self emacsTargetViewForEvent:e];
    
    APPINE_LOG(@"Overlay mouseDown forwarded to: %@, nativeTarget: %@", [target className], [nativeTarget className]);
    
    if (target && target != self) {
        [self.window makeFirstResponder:target];
        [target mouseDown:e];
    } else {
        [super mouseDown:e];
    }
    
    if (isNativeControl) {
        APPINE_LOG(@"Also forwarding mouseDown to native control: %@", [nativeTarget className]);
        [nativeTarget mouseDown:e];
    }
}
- (void)mouseDragged:(NSEvent *)e {
    NSView *target = [self emacsTargetViewForEvent:e];
    if (target && target != self) [target mouseDragged:e];
    else [super mouseDragged:e];
}
- (void)mouseUp:(NSEvent *)e {
    NSView *target = [self emacsTargetViewForEvent:e];
    if (target && target != self) [target mouseUp:e];
    else [super mouseUp:e];
}
@end

#pragma mark - UI Targets

@interface AppineActionTarget : NSObject
@end
@implementation AppineActionTarget
- (void)focusAndSendAction:(SEL)action {
    appine_set_active(YES);
    if (![NSApp sendAction:action to:nil from:nil]) {
        NSLog(@"[appine] action not handled: %@", NSStringFromSelector(action));
    }
}
- (void)deactivate:(id)sender {
    // Appine Window 失去焦点，更新 UI 状态
    appine_set_active(NO);
    NSWindow *win = appine_state().hostWindow;
    if (win && win.contentView) {
        [win makeFirstResponder:win.contentView];
    }
    // 标记这个信号是我们发出的
    atomic_store(&appine_deactivate_flag, true);
    // 发送给整个进程，让 Emacs 的主线程去捕获它
    kill(getpid(), SIGUSR1);
}
- (void)newTab:(id)sender { (void)sender; appine_add_tab(appine_create_web_backend(@"https://google.com")); }
- (void)closeTab:(id)sender { (void)sender; appine_core_close_active_tab(); }
- (void)openFile:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        NSString *path = panel.URL.path;
        id<AppineBackend> backend = appine_create_backend_for_file(path);
        if (backend) {
            appine_add_tab(backend);
        }
    }
}
- (void)undo:(id)sender { (void)sender; [self focusAndSendAction:@selector(undo:)]; }
- (void)cut:(id)sender { (void)sender; [self focusAndSendAction:@selector(cut:)]; }
- (void)copy:(id)sender { (void)sender; [self focusAndSendAction:@selector(copy:)]; }
- (void)paste:(id)sender { (void)sender; [self focusAndSendAction:@selector(paste:)]; }
- (void)find:(id)sender { (void)sender; [self focusAndSendAction:@selector(performFindPanelAction:)]; }

- (void)tabChanged:(NSSegmentedControl *)sender {
    AppineState *state = appine_state();
    APPINE_LOG(@"tabChanged triggered. Selected segment: %ld", (long)sender.selectedSegment);
    if (sender.selectedSegment >= 0 && sender.selectedSegment < (NSInteger)state.tabs.count) {
        state.activeTabId = state.tabs[sender.selectedSegment].tabId;
        APPINE_LOG(@"Switching to tabId: %ld", (long)state.activeTabId);
        appine_attach_active_view();
        if (state.isActive) [state.hostWindow makeFirstResponder:appine_find_tab(state.activeTabId).backend.view];
    }
}
@end

static AppineActionTarget *g_action_target = nil;

#pragma mark - UI Management

static void appine_ensure_container(void) {
    appine_setup_global_event_monitor(); // 启动全局事件追踪，后续可以加开关关闭？
    
    AppineState *state = appine_state();
    if (state.containerView) return;
    
    NSWindow *win = appine_target_window();
    if (!win) return;
    
    state.hostWindow = win;
    g_action_target = [[AppineActionTarget alloc] init];
    
    state.containerView = [[NSView alloc] initWithFrame:state.targetRect];
    [win.contentView addSubview:state.containerView];

    if (@available(macOS 10.14, *)) {
        state.containerView.appearance = win.appearance;
    }

    state.toolbarView = [[NSView alloc] init];
    state.toolbarStack = [NSStackView stackViewWithViews:@[]];
    state.toolbarStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    // TODO：这里可能还有点问题，排版还是都靠左边了，有空了再修复。
    state.toolbarStack.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; 
    [state.toolbarView addSubview:state.toolbarStack];
    [state.containerView addSubview:state.toolbarView];
    
    // 左侧按钮组
    NSArray *leftBtns = @[@"Deactivate", @"Open File", @"New Tab", @"Close Tab"];
    NSArray *leftSels = @[@"deactivate:", @"openFile:", @"newTab:", @"closeTab:"];
    for (NSUInteger i = 0; i < leftBtns.count; i++) {
        NSButton *btn = [NSButton buttonWithTitle:leftBtns[i] target:g_action_target action:NSSelectorFromString(leftSels[i])];
        [btn setBezelStyle:NSBezelStyleTexturedRounded];
        [state.toolbarStack addArrangedSubview:btn];
    }
    
    // 中间空白区
    NSView *spacer = [[NSView alloc] init];
    // 设置极低的抗拉伸优先级，使其自动填满所有剩余空间
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [state.toolbarStack addArrangedSubview:spacer];
    
    // 右侧编辑按钮组
    NSArray *rightBtns = @[@"Cut", @"Copy", @"Paste", @"Undo", @"Find"];
    NSArray *rightSels = @[@"cut:", @"copy:", @"paste:", @"undo:", @"find:"];
    for (NSUInteger i = 0; i < rightBtns.count; i++) {
        NSButton *btn = [NSButton buttonWithTitle:rightBtns[i] target:g_action_target action:NSSelectorFromString(rightSels[i])];
        [btn setBezelStyle:NSBezelStyleTexturedRounded];
        [state.toolbarStack addArrangedSubview:btn];
    }
    
    state.tabBarView = [[NSView alloc] init];
    state.tabControl = [NSSegmentedControl segmentedControlWithLabels:@[] trackingMode:NSSegmentSwitchTrackingSelectOne target:g_action_target action:@selector(tabChanged:)];
    // 等宽分布
    if (@available(macOS 10.13, *)) {
        state.tabControl.segmentDistribution = NSSegmentDistributionFillEqually;
    }
    [state.tabBarView addSubview:state.tabControl];
    [state.containerView addSubview:state.tabBarView];
    
    state.contentHostView = [[NSView alloc] init];
    [state.containerView addSubview:state.contentHostView];
    
    state.inactiveOverlayView = [[AppineInactiveOverlayView alloc] init];
    [state.containerView addSubview:state.inactiveOverlayView];
    
    appine_apply_rect();
    appine_apply_visual_state();
}

static void appine_apply_rect(void) {
    AppineState *state = appine_state();
    if (!state.containerView) return;
    
    [state.containerView setFrame:state.targetRect];
    NSRect bounds = state.containerView.bounds;
    
    CGFloat th = bounds.size.height >= kAppineToolbarHeight ? kAppineToolbarHeight : 0;
    CGFloat tbh = bounds.size.height >= (th + kAppineTabBarHeight) ? kAppineTabBarHeight : 0;
    CGFloat ch = MAX(0, bounds.size.height - th - tbh);
    
    [state.toolbarView setFrame:NSMakeRect(0, bounds.size.height - th, bounds.size.width, th)];
    [state.toolbarStack setFrame:NSInsetRect(state.toolbarView.bounds, 6, 4)];
    [state.tabBarView setFrame:NSMakeRect(0, ch, bounds.size.width, tbh)];
    [state.tabControl setFrame:NSInsetRect(state.tabBarView.bounds, 6, 2)];
    [state.contentHostView setFrame:NSMakeRect(0, 0, bounds.size.width, ch)];
    [state.inactiveOverlayView setFrame:bounds];
}

static void appine_apply_visual_state(void) {
    AppineState *state = appine_state();
    BOOL active = state.isActive;
    
    state.toolbarView.wantsLayer = YES;
    state.toolbarView.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;

    state.tabBarView.wantsLayer = YES;
    state.tabBarView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

    state.contentHostView.wantsLayer = YES;
    state.contentHostView.layer.backgroundColor = [NSColor textBackgroundColor].CGColor;
    state.contentHostView.layer.borderWidth = 2.0;
    state.contentHostView.layer.borderColor = active ? [NSColor keyboardFocusIndicatorColor].CGColor : [NSColor separatorColor].CGColor;

    state.inactiveOverlayView.hidden = active;
    
    for (NSView *v in state.toolbarStack.arrangedSubviews) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton *btn = (NSButton *)v;
            btn.enabled = active && (btn.action != @selector(closeTab:) || state.tabs.count > 0);
        }
    }
}
static void appine_rebuild_tabs(void) {
    AppineState *state = appine_state();
    if (!state.tabControl) return;
    
    [state.tabControl setSegmentCount:state.tabs.count];
    NSInteger selectedIdx = -1;
    
    for (NSInteger i = 0; i < (NSInteger)state.tabs.count; i++) {
        AppineTabItem *item = state.tabs[i];
        
        // 获取标题并进行硬性长度截断（防止单个 Tab 时标题过长）
        NSString *title = item.backend.title ?: @"Tab";
        const NSUInteger kMaxTitleLength = 30;
        if (title.length > kMaxTitleLength) {
            title = [[title substringToIndex:kMaxTitleLength - 1] stringByAppendingString:@"…"];
        }
        
        [state.tabControl setLabel:title forSegment:i];
        if (item.tabId == state.activeTabId) selectedIdx = i;
    }
    
    if (selectedIdx >= 0) [state.tabControl setSelectedSegment:selectedIdx];
}

static void appine_attach_active_view(void) {
    AppineState *state = appine_state();
    if (!state.contentHostView) return;
    
    for (NSView *v in state.contentHostView.subviews) [v removeFromSuperview];
    
    AppineTabItem *active = appine_find_tab(state.activeTabId);
    if (active && active.backend.view) {
        NSView *v = active.backend.view;
        [v setFrame:state.contentHostView.bounds];
        [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [state.contentHostView addSubview:v];
    }
    appine_rebuild_tabs();
}

static void appine_set_active(BOOL active) {
    AppineState *state = appine_state();
    
    if (state.isActive == active) return;
    
    APPINE_LOG(@"State changing to active: %d", active);
    state.isActive = active;
    appine_apply_visual_state();
    
    if (active) {
        AppineTabItem *tab = appine_find_tab(state.activeTabId);
        if (tab && tab.backend.view) {
            APPINE_LOG(@"Forcing FirstResponder to backend view: %@", [tab.backend.view className]);
            [state.hostWindow makeFirstResponder:tab.backend.view];
        }
    } else {
        APPINE_LOG(@"Yielding focus. Current FirstResponder is: %@", [state.hostWindow.firstResponder className]);
    }
}

static void appine_add_tab(id<AppineBackend> backend) {
    AppineState *state = appine_state();
    AppineTabItem *item = [[AppineTabItem alloc] init];
    item.tabId = state.nextTabId++;
    item.backend = backend;
    [state.tabs addObject:item];
    state.activeTabId = item.tabId;
    appine_attach_active_view();
    appine_set_active(YES);
}
void appine_core_add_web_tab(NSString *urlString) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (urlString) {
            appine_add_tab(appine_create_web_backend(urlString));
        }
    });
}

#pragma mark - C API Exports

int appine_core_open_web_in_rect(const char *url, int x, int y, int w, int h) {
    NSString *urlString = url ? [NSString stringWithUTF8String:url] : @"https://google.com";
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_state().targetRect = NSMakeRect(x, y, w, h);
        appine_ensure_container();
        appine_add_tab(appine_create_web_backend(urlString));
    });
    return 0;
}

int appine_core_open_file_in_rect(const char *path, int x, int y, int w, int h) {
    NSString *filePath = path ? [NSString stringWithUTF8String:path] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_state().targetRect = NSMakeRect(x, y, w, h);
        appine_ensure_container();
        
        id<AppineBackend> backend = appine_create_backend_for_file(filePath);
        if (backend) {
            appine_add_tab(backend);
        }
    });
    return 0;
}

int appine_core_move_resize(int x, int y, int w, int h) {
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_state().targetRect = NSMakeRect(x, y, w, h);
        appine_apply_rect();
    });
    return 0;
}

int appine_core_close_active_tab(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        AppineTabItem *active = appine_find_tab(state.activeTabId);
        if (active) {
            NSInteger idx = [state.tabs indexOfObject:active];
            [state.tabs removeObject:active];
            if (state.tabs.count > 0) {
                state.activeTabId = state.tabs[MIN(idx, (NSInteger)state.tabs.count - 1)].tabId;
            } else {
                state.activeTabId = -1;
            }
            appine_attach_active_view();
            appine_apply_visual_state();
        }
    });
    return 0;
}

int appine_core_select_next_tab(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        if (state.tabs.count < 2) return;
        AppineTabItem *active = appine_find_tab(state.activeTabId);
        NSInteger idx = [state.tabs indexOfObject:active];
        state.activeTabId = state.tabs[(idx + 1) % state.tabs.count].tabId;
        appine_attach_active_view();
    });
    return 0;
}

int appine_core_select_prev_tab(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        if (state.tabs.count < 2) return;
        AppineTabItem *active = appine_find_tab(state.activeTabId);
        NSInteger idx = [state.tabs indexOfObject:active];
        state.activeTabId = state.tabs[(idx - 1 + state.tabs.count) % state.tabs.count].tabId;
        appine_attach_active_view();
    });
    return 0;
}

int appine_core_set_active(int active) {
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_set_active(active != 0);
    });
    return 0;
}

int appine_core_focus(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_set_active(YES);
    });
    return 0;
}

int appine_core_unfocus(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_set_active(NO);
    });
    return 0;
}

int appine_core_perform_action(const char *action_name) {
    NSString *action = action_name ? [NSString stringWithUTF8String:action_name] : nil;
    if (!action) return 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        appine_set_active(YES);
        SEL sel = NSSelectorFromString([action stringByAppendingString:@":"]);
        if (![NSApp sendAction:sel to:nil from:nil]) {
            NSLog(@"[appine] action not handled: %@", action);
        }
    });
    return 0;
}

int appine_core_close(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        [state.containerView removeFromSuperview];
        state.containerView = nil;
        [state.tabs removeAllObjects];
        state.activeTabId = -1;
    });
    return 0;
}
