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

// ===========================================================================
// Log module, for debug
// ===========================================================================
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

// ===========================================================================
// 辅助 SIGUSR1 信号源判断
// ===========================================================================
static atomic_bool appine_deactivate_flag = false;
bool appine_core_check_signal(void) {
    // 检查并重置为 false
    return atomic_exchange(&appine_deactivate_flag, false);
}

#pragma mark - Backends

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
            APPINE_LOG(@"[Appine] 拦截了不支持或可能导致崩溃的文件类型: %@", ext);

            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"不支持预览该文件";
            alert.informativeText = [NSString stringWithFormat:@"Appine can’t safely preview this type of file (%@).\nPreview has been blocked.\nAppine 无法安全地预览此类型的文件。\n为防止底层渲染服务崩溃，已拦截此操作。", ext];
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

static NSView *appine_get_emacs_view(void) {
    AppineState *state = appine_state();
    if (!state.hostWindow) return nil;

    // 1. 尝试从 superview 往上找
    NSView *emacsView = state.containerView;
    while (emacsView) {
        emacsView = emacsView.superview;
        if ([emacsView.className containsString:@"Emacs"]) {
            return emacsView;
        }
    }
    // 2. 如果没找到，从 window.contentView 找
    emacsView = state.hostWindow.contentView;
    if ([emacsView.className containsString:@"Emacs"]) {
        return emacsView;
    }
    // 3. 尝试从 subviews 里面找
    for (NSView *sub in emacsView.subviews) {
        if ([sub.className containsString:@"Emacs"]) {
            return sub;
        }
    }
     // 4. 兜底返回 contentView
    return state.hostWindow.contentView;
}

// 递归查找真正的可滚动视图 (NSScrollView 或 PDFView)
static NSView *appine_find_scroll_target(NSView *view) {
    if (!view) return nil;

    // 1. 如果本身就是 NSScrollView (这会匹配到 WKWebView 内部私有的 WKScrollView)
    if ([view isKindOfClass:[NSScrollView class]]) {
        return view;
    }

    // 2. 递归查找子视图
    for (NSView *subview in view.subviews) {
        NSView *found = appine_find_scroll_target(subview);
        if (found) return found;
    }

    // 3. 如果实在找不到 NSScrollView，退回到返回 WKWebView 或 PDFView 本身
    if ([view isKindOfClass:NSClassFromString(@"WKWebView")] ||
        [view isKindOfClass:NSClassFromString(@"PDFView")]) {
        return view;
    }

    return nil;
}

static AppineTabItem *appine_find_tab(NSInteger tabId) {
    for (AppineTabItem *item in appine_state().tabs) {
        if (item.tabId == tabId) return item;
    }
    return nil;
}

// 如果当前 Appine 是激活状态，则强制将 macOS 焦点对齐到当前活跃的视图上
static void appine_restore_focus_if_active(void) {
    AppineState *state = appine_state();
    if (state.isActive && state.hostWindow) {
        AppineTabItem *active = appine_find_tab(state.activeTabId);
        if (active && active.backend && active.backend.view) {
            APPINE_LOG(@"Restoring focus to backend view: %@", [active.backend.view className]);
            [state.hostWindow makeFirstResponder:active.backend.view];
        }
    }
}

static AppineBackendKind appine_active_backend_kind(void) {
    AppineState *state = appine_state();
    AppineTabItem *active = appine_find_tab(state.activeTabId);
    if (!active || !active.backend) return AppineBackendKindUnknown;
    if ([active.backend respondsToSelector:@selector(kind)]) {
        return active.backend.kind;
    }
    return AppineBackendKindUnknown;
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
        APPINE_LOG(@"[appine] action not handled: %@", NSStringFromSelector(action));
    }
}
- (BOOL)sendScrollActionHandled:(SEL)action {
    appine_set_active(YES);
    AppineState *state = appine_state();
    AppineTabItem *active = appine_find_tab(state.activeTabId);

    if (active && active.backend && active.backend.view) {
        NSView *backendView = active.backend.view;
        NSView *targetView = appine_find_scroll_target(backendView);

        if (targetView) {
            // 仅当目标确实支持该 selector 才发送并吞键
            if ([targetView respondsToSelector:action]) {
                [NSApp sendAction:action to:targetView from:self];
                return YES;
            }
            // fallback 1: superview 链
            NSView *v = targetView.superview;
            while (v) {
                if ([v respondsToSelector:action]) {
                    [NSApp sendAction:action to:v from:self];
                    return YES;
                }
                v = v.superview;
            }
            // fallback 2: backend 根视图
            if ([active.backend.view respondsToSelector:action]) {
                [NSApp sendAction:action to:active.backend.view from:self];
                return YES;
            }
        }
    }
    APPINE_LOG(@"[appine] scroll target not found for action: %@", NSStringFromSelector(action));
    return NO;
}


- (void)deactivate:(id)sender {
    // Appine Window 失去焦点，更新 UI 状态
    appine_set_active(NO);
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
            // 这一行可以去掉了。
            // appine_restore_focus_if_active();
        }
    }
}
- (void)undo:(id)sender { (void)sender; [self focusAndSendAction:@selector(undo:)]; }
- (void)cut:(id)sender { (void)sender; [self focusAndSendAction:@selector(cut:)]; }
- (void)copy:(id)sender { (void)sender; [self focusAndSendAction:@selector(copy:)]; }
- (void)paste:(id)sender { (void)sender; [self focusAndSendAction:@selector(paste:)]; }
- (void)find:(id)sender { (void)sender; [self focusAndSendAction:@selector(performFindPanelAction:)]; }

// PDF 的方向和正常是相反的, interesting...
- (BOOL)scrollPageDown:(id)sender {
    (void)sender;
    SEL sel = (appine_active_backend_kind() == AppineBackendKindPDF)
        ? @selector(scrollPageUp:)
        : @selector(scrollPageDown:);
    return [self sendScrollActionHandled:sel];
}
- (BOOL)scrollPageUp:(id)sender {
    (void)sender;
    SEL sel = (appine_active_backend_kind() == AppineBackendKindPDF)
        ? @selector(scrollPageDown:)
        : @selector(scrollPageUp:);
    return [self sendScrollActionHandled:sel];
}
- (BOOL)scrollLineDown:(id)sender {
    (void)sender;
    SEL sel = (appine_active_backend_kind() == AppineBackendKindPDF)
        ? @selector(scrollLineUp:)
        : @selector(scrollLineDown:);
    return [self sendScrollActionHandled:sel];
}
- (BOOL)scrollLineUp:(id)sender {
    (void)sender;
    SEL sel = (appine_active_backend_kind() == AppineBackendKindPDF)
        ? @selector(scrollLineDown:)
        : @selector(scrollLineUp:);
    return [self sendScrollActionHandled:sel];
}
- (BOOL)scrollToTop:(id)sender    { (void)sender; return [self sendScrollActionHandled:@selector(scrollToBeginningOfDocument:)]; }
- (BOOL)scrollToBottom:(id)sender { (void)sender; return [self sendScrollActionHandled:@selector(scrollToEndOfDocument:)]; }

- (void)tabChanged:(NSSegmentedControl *)sender {
    AppineState *state = appine_state();
    APPINE_LOG(@"tabChanged triggered. Selected segment: %ld", (long)sender.selectedSegment);
    if (sender.selectedSegment >= 0 && sender.selectedSegment < (NSInteger)state.tabs.count) {
        state.activeTabId = state.tabs[sender.selectedSegment].tabId;
        APPINE_LOG(@"Switching to tabId: %ld", (long)state.activeTabId);
        appine_attach_active_view();
    }
}
- (void)nextTab:(NSSegmentedControl *)sender {
    AppineState *state = appine_state();
    if (state.tabs.count < 2) return;
    AppineTabItem *active = appine_find_tab(state.activeTabId);
    NSInteger idx = [state.tabs indexOfObject:active];
    state.activeTabId = state.tabs[(idx + 1) % state.tabs.count].tabId;
    appine_attach_active_view();
}
- (void)prevTab:(NSSegmentedControl *)sender {
    AppineState *state = appine_state();
    if (state.tabs.count < 2) return;
    AppineTabItem *active = appine_find_tab(state.activeTabId);
    NSInteger idx = [state.tabs indexOfObject:active];
    state.activeTabId = state.tabs[(idx - 1 + state.tabs.count) % state.tabs.count].tabId;
    appine_attach_active_view();
}

@end

static AppineActionTarget *g_action_target = nil;


#pragma mark - Event Monitor
// ===========================================================================
// Globla Event Monitor
// ===========================================================================
static void appine_setup_global_event_monitor(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 同时监听 鼠标左键 和 键盘按下
        NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskKeyDown;
        [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {

            // 调试：无条件打印所有键盘事件
            if (event.type == NSEventTypeKeyDown) {
                NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
                APPINE_LOG(@"[appine-debug-event] KeyDown RECEIVED - keyCode: %hu, chars: '%@', charsIgnoring: '%@', ctrl:%d opt:%d shift:%d cmd:%d",
                      event.keyCode,
                      event.characters,
                      event.charactersIgnoringModifiers,
                      (flags & NSEventModifierFlagControl) != 0,
                      (flags & NSEventModifierFlagOption) != 0,
                      (flags & NSEventModifierFlagShift) != 0,
                      (flags & NSEventModifierFlagCommand) != 0);
            }
            // ------------------------------------------------
            // 拦截键盘事件 (处理 Emacs 风格的 C-y, M-w 等)
            // 经过测试不同的 emacs 版本，Ctrl key的捕获基本没有问题
            // 但是 Meta 键有时候会被不同层捕获到，可能走不到这个 monitor 中。
            // ------------------------------------------------
            APPINE_LOG(@"envet.type: %lu, NSEventTypeKeyDown: %lu", event.type, NSEventTypeKeyDown);
            if (event.type == NSEventTypeKeyDown) {
                AppineState *state = appine_state();
                if (!state.containerView || !state.isActive || !state.hostWindow) {
                    return event;
                }                
                if (state.isActive && state.hostWindow && state.hostWindow.firstResponder) {
                    NSResponder *responder = state.hostWindow.firstResponder;
                    BOOL isAppineFocused = NO;
                    if ([responder isKindOfClass:[NSView class]]) {
                        NSView *v = (NSView *)responder;
                        while (v) {
                            if (v == state.containerView) {
                                isAppineFocused = YES;
                                break;
                            }
                            v = v.superview;
                        }
                    }
                    APPINE_LOG(@"check isAppineFocused: %d", isAppineFocused);
                    if (isAppineFocused) {
                        NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
                        NSString *chars = event.charactersIgnoringModifiers.lowercaseString;

                        BOOL isCtrl = (flags & NSEventModifierFlagControl) != 0;
                        BOOL isOpt  = (flags & NSEventModifierFlagOption) != 0;
                        BOOL isShift = (flags & NSEventModifierFlagShift) != 0;

                        APPINE_LOG(@"check isCtrl: %d, isOpt: %d, isShift: %d, chars: %@", isCtrl, isOpt, isShift, chars);
                        // ----------------------------------------------------------
                        // 拦截 Emacs 前缀键 (C-x, C-c, C-h) 和全局键 (C-g, M-x)
                        // ----------------------------------------------------------
                        if ((isCtrl && ([chars isEqualToString:@"x"] ||
                                        [chars isEqualToString:@"c"] ||
                                        [chars isEqualToString:@"g"] ||
                                        [chars isEqualToString:@"h"])) ||
                            (isOpt  && [chars isEqualToString:@"x"])) {

                            // 寻找 EmacsMainView 尝试 superview
                            NSView *emacsView = appine_get_emacs_view();
                            if (emacsView) {
                                // 将 macOS 的键盘焦点强行还给 Emacs 主视图
                                [state.hostWindow makeFirstResponder:emacsView];
                            }
                            // 直接 return event，让系统自然地把按键分发给 Emacs
                            return event;
                        }

                        // ----------------------------------------------------------
                        // 拦截并映射到原生 Action (C-y, C-w, M-w, C-/, C-s)
                        // ----------------------------------------------------------
                        if (isCtrl && [chars isEqualToString:@"y"]) { [g_action_target paste:nil]; return nil; }
                        if (isCtrl && [chars isEqualToString:@"w"]) { [g_action_target cut:nil]; return nil; }
                        if (isOpt  && [chars isEqualToString:@"w"]) { [g_action_target copy:nil]; return nil; }
                        if (isCtrl && [chars isEqualToString:@"/"]) { [g_action_target undo:nil]; return nil; }
                        if (isCtrl && [chars isEqualToString:@"s"]) { [g_action_target find:nil]; return nil; }
                        if (isCtrl && [chars isEqualToString:@"f"]) { [g_action_target nextTab:nil]; return nil; }
                        if (isCtrl && [chars isEqualToString:@"b"]) { [g_action_target prevTab:nil]; return nil; }
                        // ==========================================================
                        // 3. 拦截滚动快捷键 (C-v, M-v, C-n, C-p, M-<, M->)
                        // ==========================================================

                        if (isCtrl && [chars isEqualToString:@"v"]) { return [g_action_target scrollPageDown:nil] ? nil:event; }
                        if (isOpt  && [chars isEqualToString:@"v"]) { return [g_action_target scrollPageUp:nil] ? nil:event; }
                        if (isCtrl && [chars isEqualToString:@"n"]) { return [g_action_target scrollLineDown:nil] ? nil:event; }
                        if (isCtrl && [chars isEqualToString:@"p"]) { return [g_action_target scrollLineUp:nil] ? nil:event; }

                        // M-< 和 M-> 在美式键盘上通常是 Option + Shift + , 和 Option + Shift + .
                        // charactersIgnoringModifiers 有时会受 Shift 影响，所以同时兼容逗号句号和尖括号
                        if (isOpt && isShift && ([chars isEqualToString:@","] || [chars isEqualToString:@"<"])) {
                            return [g_action_target scrollToTop:nil] ? nil: event;
                        }
                        if (isOpt && isShift && ([chars isEqualToString:@"."] || [chars isEqualToString:@">"])) {
                            return [g_action_target scrollToBottom:nil] ? nil:event;
                        }
                    }
                }
                return event;
            }
            // ----------------------------------------------------------
            // 原有的鼠标点击逻辑 (绕过 Emacs 事件黑洞)
            // ----------------------------------------------------------
            NSView *hitView = nil;
            if (event.window && event.window.contentView) {
                hitView = [event.window.contentView hitTest:event.locationInWindow];
            }

            if (g_appine_debug_log) {
                NSLog(@"[appine] GLOBAL CLICK at %@, hitTest view: %@, window: %@",
                      NSStringFromPoint(event.locationInWindow), [hitView className], [event.window className]);
            }

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
            else if ([hitView isKindOfClass:[NSTextField class]] || [hitView isKindOfClass:[NSTextView class]]) {
                [event.window makeFirstResponder:hitView];
                return event;
            }

            return event;
        }];
    });
}


#pragma mark - UI Management

static void appine_ensure_container(void) {
    appine_setup_global_event_monitor(); // 启动全局事件追踪，后续可以加开关关闭？

    AppineState *state = appine_state();
    if (state.containerView) return;

    NSWindow *win = appine_target_window();
    if (!win) return;

    state.isActive = NO;
    state.hostWindow = win;
    g_action_target = [[AppineActionTarget alloc] init];

    state.containerView = [[NSView alloc] initWithFrame:state.targetRect];
    [win.contentView addSubview:state.containerView];

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
    state.toolbarView.layer.backgroundColor = active ? [NSColor controlBackgroundColor].CGColor : [NSColor colorWithCalibratedWhite:0.92 alpha:1.0].CGColor;

    state.tabBarView.wantsLayer = YES;
    state.tabBarView.layer.backgroundColor = active ? [NSColor windowBackgroundColor].CGColor : [NSColor colorWithCalibratedWhite:0.94 alpha:1.0].CGColor;

    state.contentHostView.wantsLayer = YES;
    state.contentHostView.layer.backgroundColor = [NSColor textBackgroundColor].CGColor;
    state.contentHostView.layer.borderWidth = 2.0;
    state.contentHostView.layer.borderColor = active ? [NSColor keyboardFocusIndicatorColor].CGColor : [NSColor colorWithCalibratedWhite:0.72 alpha:1.0].CGColor;

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
    // 保险：对齐焦点
    appine_restore_focus_if_active();
}

static void appine_set_active(BOOL active) {
    AppineState *state = appine_state();

    BOOL changed = (state.isActive != active);
    state.isActive = active;

    if (changed) {
        APPINE_LOG(@"State changing to active: %d", active);
        appine_apply_visual_state();
    }

    if (active) {
        // 只要要求激活，就检查当前焦点是否在 Appine 的容器视图内
        NSResponder *responder = state.hostWindow.firstResponder;
        BOOL isAppineFocused = NO;
        if ([responder isKindOfClass:[NSView class]]) {
            NSView *v = (NSView *)responder;
            while (v) {
                if (v == state.containerView) {
                    isAppineFocused = YES;
                    break;
                }
                v = v.superview;
            }
        }
        
        // 如果焦点不在 Appine 内部（比如被 C-x 临时借给了 Emacs），则强制抢回焦点
        if (!isAppineFocused) {
            AppineTabItem *tab = appine_find_tab(state.activeTabId);
            if (tab && tab.backend.view) {
                APPINE_LOG(@"Forcing FirstResponder to backend view: %@", [tab.backend.view className]);
                [state.hostWindow makeFirstResponder:tab.backend.view];
            }
        }
    } else {
        if (changed) {
            APPINE_LOG(@"Yielding focus. Current FirstResponder is: %@", [state.hostWindow.firstResponder className]);
            // 把 macOS 的键盘焦点还给 Emacs
            NSView *emacsView = appine_get_emacs_view();
            if (emacsView) {
                [state.hostWindow makeFirstResponder:emacsView];
            }
        }
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

        BOOL handled = NO;

        // 1. 优先检查自定义 g_action_target 是否实现了该方法 (如 newTab:, openFile:, find:)
        if (g_action_target && [g_action_target respondsToSelector:sel]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [g_action_target performSelector:sel withObject:nil];
            #pragma clang diagnostic pop
            handled = YES;
        }
        // 2. 否则发送给 macOS 响应链（处理标准的 copy:, paste: 等原生未被拦截的 action）
        else if ([NSApp sendAction:sel to:nil from:nil]) {
            handled = YES;
        }

        if (!handled) {
            APPINE_LOG(@"[appine] action not handled: %@", action);
        } else {
            APPINE_LOG(@"[appine] action handled succ: %@", action);
        }
    });
    return 0;
}

int appine_core_close(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();

        // 1. 先把焦点还给 Emacs
        if (state.hostWindow) {
            NSView *emacsView = appine_get_emacs_view();
            if (emacsView) {
                [state.hostWindow makeFirstResponder:emacsView];
            }
        }

        // 2. 重置所有状态
        state.isActive = NO;

        // 3. 移除视图
        [state.containerView removeFromSuperview];
        state.containerView = nil;
        state.toolbarView = nil;
        state.toolbarStack = nil;
        state.tabBarView = nil;
        state.tabControl = nil;
        state.contentHostView = nil;
        state.inactiveOverlayView = nil;

        // 4. 清空 tabs
        [state.tabs removeAllObjects];
        state.activeTabId = -1;

        // 5. 解除 hostWindow 引用
        state.hostWindow = nil;

        APPINE_LOG(@"appine_core_close: all state reset, container removed.");
    });
    return 0;
}

// ===========================================================================
// Web 专属控制 API
// ===========================================================================
int appine_core_web_go_forward(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        AppineTabItem *active = appine_find_tab(state.activeTabId);

        // 动态检查当前的 backend 是否实现了 goForward: 方法
        if (active && [active.backend respondsToSelector:@selector(goForward:)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [active.backend performSelector:@selector(goForward:) withObject:nil];
            #pragma clang diagnostic pop
            appine_restore_focus_if_active();
        }
    });
    
    return 0;
}

int appine_core_web_go_back(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        AppineTabItem *active = appine_find_tab(state.activeTabId);

        // 动态检查当前的 backend 是否实现了 goBack: 方法
        if (active && [active.backend respondsToSelector:@selector(goBack:)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [active.backend performSelector:@selector(goBack:) withObject:nil];
            #pragma clang diagnostic pop
            appine_restore_focus_if_active();
        }
    });
    return 0;
}

int appine_core_web_reload(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppineState *state = appine_state();
        AppineTabItem *active = appine_find_tab(state.activeTabId);

        // 动态检查当前的 backend 是否实现了 reload: 方法
        if (active && [active.backend respondsToSelector:@selector(reload:)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [active.backend performSelector:@selector(reload:) withObject:nil];
            #pragma clang diagnostic pop
            appine_restore_focus_if_active();
        }
    });
    return 0;
}
