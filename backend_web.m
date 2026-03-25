/*
 * Filename: backend_web.m
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
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "appine_core.h"
#import "appine_backend.h"
#import <dlfcn.h>

static void dylib_dummy_symbol() {} // locate path

extern void appine_core_add_web_tab(NSString *urlString);

// 声明 WKWebView 的私有方法，避免编译器警告
@interface WKWebView (AppinePrivate)
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event;
@end

// ===========================================================================
// AppineWebView (纯原生右键菜单劫持)
// ===========================================================================
@interface AppineWebView : WKWebView
@property (nonatomic, assign) BOOL isInterceptingDownload;
@end

@implementation AppineWebView

// 拦截真正的菜单弹出时机
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
    APPINE_LOG(@"[Appine-Menu] 1. willOpenMenu:withEvent: called");

    NSMenuItem *openLinkItem = nil;
    NSMenuItem *openImageItem = nil;

    APPINE_LOG(@"[Appine-Menu] --- Listing native menu items ---");
    for (NSMenuItem *item in menu.itemArray) {
        APPINE_LOG(@"[Appine-Menu] Item ID: '%@', Title: '%@'", item.identifier, item.title);
        if ([item.identifier isEqualToString:@"WKMenuItemIdentifierOpenLinkInNewWindow"]) {
            openLinkItem = item;
        } else if ([item.identifier isEqualToString:@"WKMenuItemIdentifierOpenImageInNewWindow"]) {
            openImageItem = item;
        }
    }
    APPINE_LOG(@"[Appine-Menu] ---------------------------------");

    for (NSMenuItem *item in menu.itemArray) {
        if ([item.identifier isEqualToString:@"WKMenuItemIdentifierDownloadLinkedFile"]) {
            if (openLinkItem) {
                APPINE_LOG(@"[Appine-Menu] 2. Successfully hijacked 'DownloadLinkedFile'");
                item.target = self;
                item.action = @selector(interceptDownloadAction:);
                item.representedObject = openLinkItem;
            }
        } else if ([item.identifier isEqualToString:@"WKMenuItemIdentifierDownloadImage"]) {
            if (openImageItem) {
                APPINE_LOG(@"[Appine-Menu] 2. Successfully hijacked 'DownloadImage'");
                item.target = self;
                item.action = @selector(interceptDownloadAction:);
                item.representedObject = openImageItem;
            }
        }
    }

    // 直接使用 super 调用，不要使用 performSelector, 不然可能死循环
    if ([WKWebView instancesRespondToSelector:@selector(willOpenMenu:withEvent:)]) {
        [super willOpenMenu:menu withEvent:event];
    }
}

- (void)interceptDownloadAction:(NSMenuItem *)sender {
    APPINE_LOG(@"[Appine-Menu] 3. interceptDownloadAction: triggered!");
    NSMenuItem *originalOpenItem = sender.representedObject;

    self.isInterceptingDownload = YES;
    APPINE_LOG(@"[Appine-Menu] isInterceptingDownload set to YES");

    if (originalOpenItem.target && originalOpenItem.action) {
        APPINE_LOG(@"[Appine-Menu] 4. Simulating click on: %@", originalOpenItem.identifier);
        void (*action)(id, SEL, id) = (void (*)(id, SEL, id))[originalOpenItem.target methodForSelector:originalOpenItem.action];
        if (action) {
            action(originalOpenItem.target, originalOpenItem.action, originalOpenItem);
        } else {
            APPINE_LOG(@"[Appine-Menu] ERROR: Failed to get action method pointer");
        }
    } else {
        APPINE_LOG(@"[Appine-Menu] ERROR: originalOpenItem missing target or action");
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isInterceptingDownload = NO;
        APPINE_LOG(@"[Appine-Menu] isInterceptingDownload reset to NO (timeout)");
    });
}
@end

// ===========================================================================
// AppineWebBackend
// ===========================================================================
@interface AppineWebBackend : NSObject <AppineBackend, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate, WKDownloadDelegate, WKScriptMessageHandler>

@property (nonatomic, strong) NSView *containerView;
@property (nonatomic, strong) AppineWebView *webView;
@property (nonatomic, strong) NSTextField *urlField;
@property (nonatomic, strong) NSButton *backBtn;
@property (nonatomic, strong) NSButton *forwardBtn;
@property (nonatomic, strong) NSButton *reloadBtn;
@property (nonatomic, copy) NSString *title;

// ---- Find Bar 相关属性 ----
@property (nonatomic, strong) NSView *findBarView;
@property (nonatomic, strong) NSTextField *findTextField;
@property (nonatomic, strong) NSTextField *findStatusLabel;
@property (nonatomic, assign) BOOL findBarVisible;
@property (nonatomic, copy) NSString *currentFindString;

- (void)toggleFindBar; // 供 appine_core 调用
@end

@implementation AppineWebBackend

- (AppineBackendKind)kind {
    return AppineBackendKindWeb;
}

- (instancetype)initWithURL:(NSString *)urlString {
    self = [super init];
    if (self) {
        _title = @"Web";
        _findBarVisible = NO;
        _currentFindString = @"";

        [self setupUI];
        [self setupFindBar]; // 初始化 Find Bar
        [self loadURL:urlString];

        // 使用 KVO 监听 WebView 状态，替代定时器
        [_webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:nil];
        [_webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
        [_webView addObserver:self forKeyPath:@"canGoBack" options:NSKeyValueObservingOptionNew context:nil];
        [_webView addObserver:self forKeyPath:@"canGoForward" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)dealloc {
    [_webView removeObserver:self forKeyPath:@"URL"];
    [_webView removeObserver:self forKeyPath:@"title"];
    [_webView removeObserver:self forKeyPath:@"canGoBack"];
    [_webView removeObserver:self forKeyPath:@"canGoForward"];
}

- (void)setupUI {
    // 1. 创建主容器 (将被 appine_native 放入 contentHostView)
    _containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _containerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat navHeight = 32.0;

    // 2. 创建专属导航栏 (固定在容器顶部)
    NSView *navBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 600 - navHeight, 800, navHeight)];
    navBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    navBar.wantsLayer = YES;
    navBar.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;

    // 底部分割线
    NSView *separator = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1)];
    separator.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [NSColor gridColor].CGColor;
    [navBar addSubview:separator];
    [_containerView addSubview:navBar];

    // 3. 添加导航按钮 (<, >, ↻)
    _backBtn = [NSButton buttonWithTitle:@"<" target:self action:@selector(goBack:)];
    _backBtn.frame = NSMakeRect(5, 4, 28, 24);
    _backBtn.bezelStyle = NSBezelStyleTexturedRounded;
    _backBtn.enabled = NO;
    [navBar addSubview:_backBtn];

    _forwardBtn = [NSButton buttonWithTitle:@">" target:self action:@selector(goForward:)];
    _forwardBtn.frame = NSMakeRect(38, 4, 28, 24);
    _forwardBtn.bezelStyle = NSBezelStyleTexturedRounded;
    _forwardBtn.enabled = NO;
    [navBar addSubview:_forwardBtn];

    _reloadBtn = [NSButton buttonWithTitle:@"↻" target:self action:@selector(reload:)];
    _reloadBtn.frame = NSMakeRect(71, 4, 28, 24);
    _reloadBtn.bezelStyle = NSBezelStyleTexturedRounded;
    [navBar addSubview:_reloadBtn];

    // 4. 添加地址栏 (在按钮右侧)
    _urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(105, 5, 800 - 110, 22)];
    _urlField.autoresizingMask = NSViewWidthSizable; // 自动拉伸宽度
    _urlField.placeholderString = @"Search or enter website name";
    _urlField.target = self;
    _urlField.action = @selector(urlEntered:);
    _urlField.focusRingType = NSFocusRingTypeNone;
    [navBar addSubview:_urlField];

    // ==========================================
    // 配置 WebView 的持久化与伪装
    // ==========================================
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // 1. 注册消息通道
    [config.userContentController addScriptMessageHandler:self name:@"appineLog"];

    // 2. 注入 JS 脚本：劫持 console.log 并监听所有 keydown 和 全局错误
    NSString *debugJS = @"\
        const origLog = console.log;\n\
        console.log = function(...args) {\n\
            origLog.apply(console, args);\n\
            const msg = args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ');\n\
            window.webkit.messageHandlers.appineLog.postMessage(msg);\n\
        };\n\
        /* 捕获语法错误等全局异常 */\n\
        window.addEventListener('error', function(e) {\n\
            console.log('❌ [Appine-JS-Error] 捕获到页面错误:', e.message, '行号:', e.lineno);\n\
        });\n\
        window.addEventListener('keydown', function(e) {\n\
            console.log('🔥 JS 捕获到按键:', e.key, 'keyCode:', e.keyCode);\n\
        }, true);\n\
    ";

    WKUserScript *debugScript = [[WKUserScript alloc] initWithSource:debugJS
                                                       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                    forMainFrameOnly:YES];
    [config.userContentController addUserScript:debugScript];

    // ==========================================
    // 插件系统初始化 (支持 ES Module 和 PluginLoader)
    // ==========================================
    Dl_info info;
    NSString *appineDir = nil;

    if (dladdr((const void *)&dylib_dummy_symbol, &info) != 0) {
        // info.dli_fname 包含了当前 dylib 的完整绝对路径 (例如: /path/to/your/libappine.dylib)
        NSString *dylibFullPath = [NSString stringWithUTF8String:info.dli_fname];
        // 剔除文件名，获取 dylib 所在的目录
        appineDir = [dylibFullPath stringByDeletingLastPathComponent];
    } else {
        // Fallback: 万一获取失败，退回到默认路径
        appineDir = [@"~/.emacs.d/straight/repos/appine" stringByExpandingTildeInPath];
        APPINE_LOG(@"[Warning] 无法动态获取 dylib 路径，使用默认路径: %@", appineDir);
    }
    NSString *pluginsDir = [appineDir stringByAppendingPathComponent:@"plugins"];
    // NSString *appineDir = [@"~/git-local/appine-dev" stringByExpandingTildeInPath];
    // 注入全局工具库 (AppineUtils)
    NSString *utilsPath = [appineDir stringByAppendingPathComponent:@"utils.js"];
    NSString *utilsJS = [NSString stringWithContentsOfFile:utilsPath encoding:NSUTF8StringEncoding error:nil];
    if (utilsJS) {
        // 注意：这里使用 WKUserScriptInjectionTimeAtDocumentStart，确保它最早可用
        WKUserScript *utilsScript = [[WKUserScript alloc] initWithSource:utilsJS
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:YES];
        [config.userContentController addUserScript:utilsScript];
    } else {
        APPINE_LOG(@"[Appine-Warning] 未找到 utils.js");
    }


    // 1. 读取 plugins-loader.js
    NSString *loaderPath = [appineDir stringByAppendingPathComponent:@"plugins-loader.js"];
    NSString *loaderJS = [NSString stringWithContentsOfFile:loaderPath encoding:NSUTF8StringEncoding error:nil];

    if (loaderJS) {
        loaderJS = [loaderJS stringByReplacingOccurrencesOfString:@"export default PluginLoader;" withString:@"window.PluginLoader = PluginLoader;"];

        // 将 loader 单独作为一个 Script 注入
        WKUserScript *loaderScript = [[WKUserScript alloc] initWithSource:loaderJS
                                                            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                         forMainFrameOnly:YES];
        [config.userContentController addUserScript:loaderScript];

        NSArray *plugins = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:pluginsDir error:nil];
        for (NSString *pluginName in plugins) {
            if ([pluginName hasPrefix:@"."]) continue;

            NSString *pluginIndexPath = [NSString stringWithFormat:@"%@/%@/index.js", pluginsDir, pluginName];
            NSString *pluginJS = [NSString stringWithContentsOfFile:pluginIndexPath encoding:NSUTF8StringEncoding error:nil];

            if (pluginJS) {
                // 原生端也打印一下，方便确认读取到了文件
                APPINE_LOG(@"[Appine-Plugin] 准备注入插件: %@", pluginName);

                NSMutableString *pluginInjectionJS = [NSMutableString string];
                NSString *modifiedJS = [pluginJS stringByReplacingOccurrencesOfString:@"export default" withString:@"return"];

                [pluginInjectionJS appendFormat:@"{\n"];
                [pluginInjectionJS appendFormat:@"  try {\n"];
                [pluginInjectionJS appendFormat:@"    console.log('[Appine-Plugin] ⏳ 开始解析并执行插件: %@');\n", pluginName];
                [pluginInjectionJS appendFormat:@"    const pluginObj = (function() {\n%@\n    })();\n", modifiedJS];
                [pluginInjectionJS appendFormat:@"    window.PluginLoader.register(pluginObj);\n"];
                [pluginInjectionJS appendFormat:@"  } catch(e) {\n"];
                [pluginInjectionJS appendFormat:@"    console.log('[Appine-Plugin] ❌ 执行插件 %@ 失败: ' + (e.message || e));\n", pluginName];
                [pluginInjectionJS appendFormat:@"  }\n"];
                [pluginInjectionJS appendFormat:@"}\n"];

                // 为每一个插件单独创建一个 WKUserScript
                WKUserScript *pluginScript = [[WKUserScript alloc] initWithSource:pluginInjectionJS
                                                                    injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                                 forMainFrameOnly:YES];
                [config.userContentController addUserScript:pluginScript];
            }
        }
    } else {
        APPINE_LOG(@"[Appine-Plugin] ⚠️ 未找到 plugins-loader.js");
    }

    // 1. 强制使用系统的默认持久化数据存储（保存 Cookie、LocalStorage、Session 等）
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    // 注入 JS：保留 PC 布局，但当网页过宽时，自动等比例缩小 (Zoom) 以适应当前窗口
    NSString *jScript = @"function autoFit() { "
                         "  if(!document.documentElement) return; "
                         "  document.documentElement.style.zoom = 1.0; "
                         "  var cw = document.documentElement.scrollWidth; "
                         "  var vw = document.documentElement.clientWidth; "
                         "  if (cw > vw && vw > 0) { "
                         "    document.documentElement.style.zoom = vw / cw; "
                         "  } "
                         "} "
                         "autoFit(); "
                         "window.addEventListener('load', autoFit); "
                         "window.addEventListener('resize', autoFit);";

    WKUserScript *wkUScript = [[WKUserScript alloc] initWithSource:jScript
                                                     injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                  forMainFrameOnly:YES];
    [config.userContentController addUserScript:wkUScript];

    _webView = [[AppineWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600 - navHeight) configuration:config];
    // 开启控制台
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130300
    if (@available(macOS 13.3, *)) {
        _webView.inspectable = YES; // macOS 13.3 及以上必须设置此属性
    } else {
        [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
    }
#else
    [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
#endif
    // 2. 伪装成标准的 Mac Safari 浏览器
    // 防止 Google、GitHub 等网站以“不安全的嵌入式浏览器”为由拒绝你登录。
    _webView.customUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15";
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;
    [_containerView addSubview:_webView];
}

// ===========================================================================
// Find Bar 界面构建与逻辑
// ===========================================================================
- (void)setupFindBar {
    CGFloat findBarHeight = 32.0;
    CGFloat navHeight = 32.0;
    NSRect containerFrame = self.containerView.frame;

    // Find Bar 位于 NavBar 正下方
    _findBarView = [[NSView alloc] initWithFrame:NSMakeRect(0, containerFrame.size.height - navHeight - findBarHeight, containerFrame.size.width, findBarHeight)];
    _findBarView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _findBarView.wantsLayer = YES;
    _findBarView.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    _findBarView.hidden = YES;

    // 顶部分割线
    NSView *separator = [[NSView alloc] initWithFrame:NSMakeRect(0, findBarHeight - 1, containerFrame.size.width, 1)];
    separator.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [NSColor gridColor].CGColor;
    [_findBarView addSubview:separator];

    // 关闭按钮
    NSButton *closeBtn = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeFindBar:)];
    closeBtn.frame = NSMakeRect(10, 5, 24, 22);
    closeBtn.bezelStyle = NSBezelStyleTexturedRounded;
    [_findBarView addSubview:closeBtn];

    // 搜索输入框
    _findTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 5, 200, 22)];
    _findTextField.placeholderString = @"Find in page...";
    _findTextField.delegate = self; // 绑定 Delegate 以支持实时搜索和快捷键
    _findTextField.target = self;
    _findTextField.action = @selector(findTextFieldAction:);
    _findTextField.focusRingType = NSFocusRingTypeNone;
    [_findBarView addSubview:_findTextField];

    // 状态标签
    _findStatusLabel = [NSTextField labelWithString:@""];
    _findStatusLabel.frame = NSMakeRect(250, 5, 80, 22);
    _findStatusLabel.textColor = [NSColor secondaryLabelColor];
    [_findBarView addSubview:_findStatusLabel];

    // 上一个按钮
    NSButton *prevBtn = [NSButton buttonWithTitle:@"▲" target:self action:@selector(findPrevious:)];
    prevBtn.frame = NSMakeRect(340, 4, 28, 24);
    prevBtn.bezelStyle = NSBezelStyleTexturedRounded;
    [_findBarView addSubview:prevBtn];

    // 下一个按钮
    NSButton *nextBtn = [NSButton buttonWithTitle:@"▼" target:self action:@selector(findNext:)];
    nextBtn.frame = NSMakeRect(370, 4, 28, 24);
    nextBtn.bezelStyle = NSBezelStyleTexturedRounded;
    [_findBarView addSubview:nextBtn];

    [self.containerView addSubview:_findBarView];
}

- (void)toggleFindBar {
    if (self.findBarVisible) {
        [self closeFindBar:nil];
    } else {
        [self showFindBar];
    }
}

- (void)showFindBar {
    if (self.findBarVisible) {
        [self.findTextField.window makeFirstResponder:self.findTextField];
        return;
    }

    self.findBarVisible = YES;
    self.findBarView.hidden = NO;

    // 动态压缩 WebView 的高度，腾出 Find Bar 的空间
    CGFloat findBarHeight = 32.0;
    NSRect webFrame = self.webView.frame;
    webFrame.size.height -= findBarHeight;
    self.webView.frame = webFrame;

    [self.findTextField.window makeFirstResponder:self.findTextField];
    if (self.findTextField.stringValue.length > 0) {
        [self.findTextField selectText:nil];
    }
}

- (void)closeFindBar:(id)sender {
    if (!self.findBarVisible) return;

    self.findBarVisible = NO;
    self.findBarView.hidden = YES;

    CGFloat findBarHeight = 32.0;
    NSRect webFrame = self.webView.frame;
    webFrame.size.height += findBarHeight;
    self.webView.frame = webFrame;

    // 清除页面高亮和 JS 状态
    NSString *clearJS = @"\
        if (window.appineFindState && window.appineFindState.elements) {\
            window.appineFindState.elements.forEach(el => {\
                const parent = el.parentNode;\
                if (parent) {\
                    parent.replaceChild(document.createTextNode(el.textContent), el);\
                    parent.normalize();\
                }\
            });\
        }\
        window.appineFindState = { index: -1, elements: [] };\
    ";
    [self.webView evaluateJavaScript:clearJS completionHandler:nil];

    // 清除原生查找状态（以防万一）
    if (@available(macOS 12.0, *)) {
        WKFindConfiguration *config = [[WKFindConfiguration alloc] init];
        [self.webView findString:@"" withConfiguration:config completionHandler:^(WKFindResult *result) {}];
    }

    self.findStatusLabel.stringValue = @"";
    self.currentFindString = @"";

    [self.webView.window makeFirstResponder:self.webView];
}

// 专门用于在已有的匹配项中丝滑跳转
- (void)jumpToNextMatchBackwards:(BOOL)backwards {
    NSString *jumpJS = [NSString stringWithFormat:@"\
        (function(backwards) {\
            let state = window.appineFindState;\
            if (!state || !state.elements || state.elements.length === 0) return '0/0';\
            \
            /* 移除上一个当前项的橙色高亮 */\
            if (state.index >= 0 && state.index < state.elements.length) {\
                state.elements[state.index].classList.remove('appine-current');\
            }\
            \
            /* 计算下一个索引，支持首尾循环 (Wrap) */\
            if (backwards) {\
                state.index = state.index <= 0 ? state.elements.length - 1 : state.index - 1;\
            } else {\
                state.index = state.index >= state.elements.length - 1 ? 0 : state.index + 1;\
            }\
            \
            /* 给新的当前项加上橙色高亮，并滚动到屏幕中央 */\
            let target = state.elements[state.index];\
            target.classList.add('appine-current');\
            target.scrollIntoView({ behavior: 'auto', block: 'center' });\
            \
            return (state.index + 1) + '/' + state.elements.length;\
        })(%@);\
    ", backwards ? @"true" : @"false"];

    [self.webView evaluateJavaScript:jumpJS completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:[NSString class]]) {
            self.findStatusLabel.stringValue = result; // 更新 1/12 标签
        }
    }];
}

- (void)performFindWithString:(NSString *)string backwards:(BOOL)backwards {
    if (!string || string.length == 0) {
        self.currentFindString = @"";
        self.findStatusLabel.stringValue = @"";
        NSString *clearJS = @"\
            if (window.appineFindState && window.appineFindState.elements) {\
                window.appineFindState.elements.forEach(el => {\
                    const parent = el.parentNode;\
                    if (parent) {\
                        parent.replaceChild(document.createTextNode(el.textContent), el);\
                        parent.normalize();\
                    }\
                });\
            }\
            window.appineFindState = { index: -1, elements: [] };\
        ";
        [self.webView evaluateJavaScript:clearJS completionHandler:nil];
        return;
    }

    BOOL stringChanged = ![string isEqualToString:self.currentFindString];

    if (stringChanged) {
        self.currentFindString = string;

        NSString *safeString = [string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        safeString = [safeString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        safeString = [safeString stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        safeString = [safeString stringByReplacingOccurrencesOfString:@"\r" withString:@""];

        // 注入 CSS：全局黄色，当前选中橙色
        NSString *injectCSSJS = @"\
            (function() {\
                if (!document.getElementById('appine-highlight-style')) {\
                    let style = document.createElement('style');\
                    style.id = 'appine-highlight-style';\
                    style.innerHTML = \
                        'mark.appine-highlight { background-color: #FFFF00 !important; color: black !important; } ' + \
                        'mark.appine-current { background-color: #FF9632 !important; color: black !important; }';\
                    document.head.appendChild(style);\
                }\
            })();\
        ";
        [self.webView evaluateJavaScript:injectCSSJS completionHandler:nil];

        // 使用 JS 提取并保存所有匹配的 DOM 节点
        NSString *highlightJS = [NSString stringWithFormat:@"\
            (function(keyword) {\
                if (window.appineFindState && window.appineFindState.elements) {\
                    window.appineFindState.elements.forEach(el => {\
                        const parent = el.parentNode;\
                        if (parent) {\
                            parent.replaceChild(document.createTextNode(el.textContent), el);\
                            parent.normalize();\
                        }\
                    });\
                }\
                /* 初始化全局状态对象 */\
                window.appineFindState = { index: -1, elements: [] };\
                if (!keyword) return '0/0';\
                \
                const escapeRegExp = (s) => s.replace(/[-/\\\\^$*+?.()|[\\]{}]/g, '\\\\$&');\
                const regex = new RegExp('(' + escapeRegExp(keyword) + ')', 'gi');\
                \
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);\
                const textNodes = [];\
                let node;\
                while (node = walker.nextNode()) {\
                    const pNode = node.parentNode;\
                    const p = pNode.nodeName;\
                    if (p !== 'SCRIPT' && p !== 'STYLE' && p !== 'NOSCRIPT') {\
                        /* 复用全局工具库，但关闭视口检查(全页搜索)、尺寸检查和点击检查 */\
                        if (window.AppineUtils && !window.AppineUtils.isElementVisible(pNode, {\
                            checkViewport: false, \
                            checkSize: false, \
                            checkPointerEvents: false \
                        })) {\
                            continue;\
                        }\
                        if (regex.test(node.nodeValue)) textNodes.push(node);\
                    }\
                }\
                \
                let count = 0;\
                for (let i = 0; i < textNodes.length; i++) {\
                    if (count > 1000) break;\
                    const textNode = textNodes[i];\
                    const frag = document.createDocumentFragment();\
                    const parts = textNode.nodeValue.split(regex);\
                    parts.forEach(part => {\
                        if (part.toLowerCase() === keyword.toLowerCase()) {\
                            const mark = document.createElement('mark');\
                            mark.className = 'appine-highlight';\
                            mark.textContent = part;\
                            frag.appendChild(mark);\
                            /* 将匹配的节点存入数组，供跳转使用 */\
                            window.appineFindState.elements.push(mark);\
                            count++;\
                        } else if (part) {\
                            frag.appendChild(document.createTextNode(part));\
                        }\
                    });\
                    textNode.parentNode.replaceChild(frag, textNode);\
                }\
                return window.appineFindState.elements.length > 0 ? '0/' + window.appineFindState.elements.length : '0/0';\
            })('%@');\
        ", safeString];

        [self.webView evaluateJavaScript:highlightJS completionHandler:^(id result, NSError *error) {
            if ([result isKindOfClass:[NSString class]]) {
                self.findStatusLabel.stringValue = result;
                // 如果找到了结果，立刻让第一个结果变成橙色并滚动到视野中
                if (![result isEqualToString:@"0/0"]) {
                    [self jumpToNextMatchBackwards:backwards];
                }
            }
        }];
    } else {
        // 之前使用过原生 findString! 和 js 配合不太好。
        // 如果搜索词没变（点击了 Next/Prev），直接调用 JS 跳转
        [self jumpToNextMatchBackwards:backwards];
    }
}

- (void)findTextFieldAction:(id)sender {
    [self performFindWithString:self.findTextField.stringValue backwards:NO];
}

- (void)findPrevious:(id)sender {
    [self performFindWithString:self.findTextField.stringValue backwards:YES];
}

- (void)findNext:(id)sender {
    [self performFindWithString:self.findTextField.stringValue backwards:NO];
}

#pragma mark - NSTextFieldDelegate (Find Bar 实时搜索与快捷键)

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *field = notification.object;
    if (field == self.findTextField) {
        // 防抖：取消之前的延迟请求，避免用户快速打字时疯狂触发 JS
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(triggerSearchFromTyping) object:nil];
        // 延迟 0.25 秒执行搜索
        [self performSelector:@selector(triggerSearchFromTyping) withObject:nil afterDelay:0.25];
    }
}

// 供防抖调用的独立方法
- (void)triggerSearchFromTyping {
    [self performFindWithString:self.findTextField.stringValue backwards:NO];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == self.findTextField) {
        // ESC -> 关闭 Find Bar
        if (commandSelector == @selector(cancelOperation:)) {
            [self closeFindBar:nil];
            return YES;
        }
        // Enter -> 查找下一个 (Shift+Enter -> 查找上一个)
        if (commandSelector == @selector(insertNewline:)) {
            NSUInteger flags = [NSEvent modifierFlags];
            if (flags & NSEventModifierFlagShift) {
                [self findPrevious:nil];
            } else {
                [self findNext:nil];
            }
            return YES;
        }
    }
    return NO;
}

#pragma mark - Actions

- (void)goBack:(id)sender { [self.webView goBack]; }
- (void)goForward:(id)sender { [self.webView goForward]; }
- (void)reload:(id)sender { [self.webView reload]; }

- (void)urlEntered:(NSTextField *)sender {
    // 去除首尾的空白字符
    NSString *input = [sender.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (input.length == 0) return;

    BOOL isSearch = NO;

    // 1. 如果包含空格，直接认为是搜索
    if ([input rangeOfString:@" "].location != NSNotFound) {
        isSearch = YES;
    }
    // 2. 如果不包含 "."，且不是 localhost，也不是本地文件协议，通常也是搜索词 (例如直接输入 "emacs")
    else if ([input rangeOfString:@"."].location == NSNotFound &&
               ![input isEqualToString:@"localhost"] &&
               ![input hasPrefix:@"http://localhost"] &&
               ![input hasPrefix:@"https://localhost"] &&
               ![input hasPrefix:@"file://"]) {
        isSearch = YES;
    }

    NSURL *url = nil;
    if (isSearch) {
        // 构建 Google 搜索 URL，并对搜索词进行 URLEncode
        NSString *encodedQuery = [input stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *searchUrlStr = [NSString stringWithFormat:@"https://www.google.com/search?q=%@", encodedQuery];
        url = [NSURL URLWithString:searchUrlStr];
    } else {
        NSString *urlStr = input;
        // 自动补全协议头
        if (![urlStr hasPrefix:@"http://"] && ![urlStr hasPrefix:@"https://"] && ![urlStr hasPrefix:@"file://"]) {
            urlStr = [@"https://" stringByAppendingString:urlStr];
        }
        url = [NSURL URLWithString:urlStr];

        // 3. 如果 NSURL 解析失败（例如包含未转义的特殊字符），降级为搜索
        if (!url) {
            NSString *encodedQuery = [input stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            NSString *searchUrlStr = [NSString stringWithFormat:@"https://www.google.com/search?q=%@", encodedQuery];
            url = [NSURL URLWithString:searchUrlStr];
        }
    }

    if (url) {
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    }

    // 提交后将焦点还给 WebView
    [self.containerView.window makeFirstResponder:self.webView];
}

#pragma mark - KVO (监听 WebView 状态)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"URL"]) {
        // 只有当用户没有在地址栏输入时，才自动更新地址栏文本
        if (self.urlField.window.firstResponder != self.urlField.currentEditor) {
            self.urlField.stringValue = self.webView.URL.absoluteString ?: @"";
        }
    } else if ([keyPath isEqualToString:@"title"]) {
        self.title = self.webView.title ?: @"Web";
    } else if ([keyPath isEqualToString:@"canGoBack"]) {
        self.backBtn.enabled = self.webView.canGoBack;
    } else if ([keyPath isEqualToString:@"canGoForward"]) {
        self.forwardBtn.enabled = self.webView.canGoForward;
    }
}

#pragma mark - WKNavigationDelegate (Downloads)

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (@available(macOS 11.3, *)) {
        if (navigationAction.shouldPerformDownload) {
            decisionHandler(WKNavigationActionPolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (@available(macOS 11.3, *)) {
        if (!navigationResponse.canShowMIMEType) {
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download API_AVAILABLE(macos(11.3)) {
    download.delegate = self;
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download API_AVAILABLE(macos(11.3)) {
    download.delegate = self;
}

#pragma mark - WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {

    APPINE_LOG(@"[Appine-Menu] 5. createWebViewWithConfiguration: called, URL: %@", navigationAction.request.URL);

    if ([webView isKindOfClass:[AppineWebView class]]) {
        AppineWebView *appineWebView = (AppineWebView *)webView;
        APPINE_LOG(@"[Appine-Menu] isInterceptingDownload: %d", appineWebView.isInterceptingDownload);

        if (appineWebView.isInterceptingDownload) {
            APPINE_LOG(@"[Appine-Menu] 6. INTERCEPTED! Converting new window request to download task.");
            appineWebView.isInterceptingDownload = NO;
            if (@available(macOS 11.3, *)) {
                [webView startDownloadUsingRequest:navigationAction.request completionHandler:^(WKDownload * _Nonnull download) {
                    download.delegate = self;
                }];
            }
            return nil;
        }
    }

    if (!navigationAction.targetFrame.isMainFrame) {
        if (@available(macOS 11.3, *)) {
            if (navigationAction.shouldPerformDownload) {
                [webView startDownloadUsingRequest:navigationAction.request completionHandler:^(WKDownload * _Nonnull download) {
                    download.delegate = self;
                }];
                return nil;
            }
        }
        NSURL *url = navigationAction.request.URL;
        if (url) {
            // 调用 appine_core.m 提供的接口，在 Appine 中创建一个新的 Tab
            appine_core_add_web_tab(url.absoluteString);
        }
    }

    // 返回 nil 表示我们不提供一个新的 WKWebView 实例给系统去渲染，
    // 而是由我们自己的 Tab 系统接管了这个 URL。
    return nil;
}

// upload file (<input type="file">)
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> * _Nullable URLs))completionHandler {

    APPINE_LOG(@"[Appine-Upload] 1. 网页请求打开文件选择面板 (runOpenPanelWithParameters)");
    APPINE_LOG(@"[Appine-Upload] 2. 参数 - 是否允许多选: %@, 是否允许选目录: %@",
          parameters.allowsMultipleSelection ? @"YES" : @"NO",
          parameters.allowsDirectories ? @"YES" : @"NO");

    // 必须在主线程弹出 UI
    dispatch_async(dispatch_get_main_queue(), ^{
        NSOpenPanel *openPanel = [NSOpenPanel openPanel];
        openPanel.canChooseFiles = YES;
        openPanel.canChooseDirectories = parameters.allowsDirectories;
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection;
        openPanel.message = @"请选择要上传的文件";

        // 确保应用被激活，防止文件选择面板被挡在其他窗口后面
        [NSApp activateIgnoringOtherApps:YES];

        APPINE_LOG(@"[Appine-Upload] 3. 正在展示 NSOpenPanel...");
        [openPanel beginWithCompletionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK) {
                NSArray<NSURL *> *selectedURLs = openPanel.URLs;
                APPINE_LOG(@"[Appine-Upload] 4. 用户成功选择了 %lu 个文件", (unsigned long)selectedURLs.count);
                for (NSURL *url in selectedURLs) {
                    APPINE_LOG(@"[Appine-Upload] ---> 选中文件路径: %@", url.path);
                }
                // 将选中的文件 URL 数组回调给 WKWebView
                completionHandler(selectedURLs);
            } else {
                APPINE_LOG(@"[Appine-Upload] 4. 用户取消了文件选择");
                // 必须调用 completionHandler 并传入 nil，否则 WKWebView 会卡死或崩溃
                completionHandler(nil);
            }
        }];
    });
}

#pragma mark - WKDownloadDelegate

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL * _Nullable))completionHandler API_AVAILABLE(macos(11.3)) {

    dispatch_async(dispatch_get_main_queue(), ^{
        NSSavePanel *savePanel = [NSSavePanel savePanel];
        savePanel.canCreateDirectories = YES;
        savePanel.nameFieldStringValue = suggestedFilename ?: @"download";

        [NSApp activateIgnoringOtherApps:YES];

        [savePanel beginWithCompletionHandler:^(NSModalResponse result) {
            if (result == NSModalResponseOK) {
                APPINE_LOG(@"[Appine] Download started: %@", savePanel.URL.path);
                completionHandler(savePanel.URL);
            } else {
                completionHandler(nil);
            }
        }];
    });
}

- (void)downloadDidFinish:(WKDownload *)download API_AVAILABLE(macos(11.3)) {
    APPINE_LOG(@"[Appine] Download finished successfully.");
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error expectedResumeData:(NSData *)resumeData API_AVAILABLE(macos(11.3)) {
    APPINE_LOG(@"[Appine] Download failed: %@", error.localizedDescription);
}

// ==========================================
// 接收来自 JS 的 console.log
// ==========================================
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"appineLog"]) {
        APPINE_LOG(@"[Appine-JS] %@", message.body);
    }
}

#pragma mark - AppineBackend Protocol

- (NSView *)view {
    // 返回包含了导航栏和 WebView 的复合容器
    return self.containerView;
}

- (void)loadURL:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url];
    if (u) {
        [self.webView loadRequest:[NSURLRequest requestWithURL:u]];
    }
}

@end

// C API export
id<AppineBackend> appine_create_web_backend(NSString *urlString) {
    return [[AppineWebBackend alloc] initWithURL:urlString];
}
