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
#import "appine_backend.h"

@interface AppineWebBackend : NSObject <AppineBackend, WKNavigationDelegate, NSTextFieldDelegate>
@property (nonatomic, strong) NSView *containerView; // 复合视图容器
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSTextField *urlField;
@property (nonatomic, strong) NSButton *backBtn;
@property (nonatomic, strong) NSButton *forwardBtn;
@property (nonatomic, strong) NSButton *reloadBtn;
@property (nonatomic, copy) NSString *title;
@end

@implementation AppineWebBackend

- (instancetype)initWithURL:(NSString *)urlString {
    self = [super init];
    if (self) {
        _title = @"Web";
        [self setupUI];
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
    
    // 1. 强制使用系统的默认持久化数据存储（保存 Cookie、LocalStorage、Session 等）
    // 这样 Emacs 重启后，登录状态依然存在。
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    
    // 注入 JS：保留 PC 布局，但当网页过宽时，自动等比例缩小 (Zoom) 以适应当前窗口
    // 尝试过伪装成 ipad 来自适应，但是效果一般。
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
    
    _webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600 - navHeight) configuration:config];
    
    // 2. 伪装成标准的 Mac Safari 浏览器
    // 防止 Google、GitHub 等网站以“不安全的嵌入式浏览器”为由拒绝你登录。
    _webView.customUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15";
    
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    [_containerView addSubview:_webView];
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
