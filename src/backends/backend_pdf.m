/*
 * Filename: backend_pdf.m
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
#import "appine_backend.h"
#import <PDFKit/PDFKit.h>

@interface AppinePdfBackend : NSObject <AppineBackend, NSTextFieldDelegate>

@property (nonatomic, strong) NSView *containerView;
@property (nonatomic, strong) PDFView *pdfView;
@property (nonatomic, copy) NSString *path;

// ---- Find Bar 相关属性 ----
@property (nonatomic, strong) NSView *findBarView;
@property (nonatomic, strong) NSTextField *findTextField;
@property (nonatomic, strong) NSTextField *findStatusLabel;
@property (nonatomic, assign) BOOL findBarVisible;
@property (nonatomic, copy) NSString *currentFindString;

// ---- 查找状态 ----
@property (nonatomic, strong) NSArray<PDFSelection *> *allSelections;
@property (nonatomic, assign) NSInteger currentMatchIndex;

- (void)toggleFindBar; // 供 appine_core 调用

@end

@implementation AppinePdfBackend

- (AppineBackendKind)kind {
    return AppineBackendKindPDF;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
        _findBarVisible = NO;
        _currentFindString = @"";
        _allSelections = @[];
        _currentMatchIndex = -1;
        
        [self setupUI];
        [self setupFindBar];
        
        if (_path && _path.length > 0) {
            NSURL *url = [NSURL fileURLWithPath:_path];
            if (url) {
                PDFDocument *doc = [[PDFDocument alloc] initWithURL:url];
                if (doc) {
                    [_pdfView setDocument:doc];
                }
            }
        }
    }
    return self;
}

- (void)setupUI {
    // 1. 创建主容器
    _containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _containerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    // 2. 创建 PDFView
    _pdfView = [[PDFView alloc] initWithFrame:_containerView.bounds];
    [_pdfView setAutoScales:YES];
    [_pdfView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_containerView addSubview:_pdfView];
}

// ===========================================================================
// Find Bar 界面构建与逻辑
// ===========================================================================
- (void)setupFindBar {
    CGFloat findBarHeight = 32.0;
    NSRect containerFrame = self.containerView.frame;
    
    // Find Bar 位于顶部
    _findBarView = [[NSView alloc] initWithFrame:NSMakeRect(0, containerFrame.size.height - findBarHeight, containerFrame.size.width, findBarHeight)];
    _findBarView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _findBarView.wantsLayer = YES;
    _findBarView.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    _findBarView.hidden = YES;
    
    // 底部分割线
    NSView *separator = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, containerFrame.size.width, 1)];
    separator.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
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
    _findTextField.placeholderString = @"Find in document...";
    _findTextField.delegate = self;
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
    
    // 动态压缩 PDFView 的高度，腾出 Find Bar 的空间
    CGFloat findBarHeight = 32.0;
    NSRect pdfFrame = self.pdfView.frame;
    pdfFrame.size.height -= findBarHeight;
    self.pdfView.frame = pdfFrame;
    
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
    NSRect pdfFrame = self.pdfView.frame;
    pdfFrame.size.height += findBarHeight;
    self.pdfView.frame = pdfFrame;
    
    // 清除状态与高亮
    self.pdfView.highlightedSelections = nil;
    self.allSelections = @[];
    self.currentMatchIndex = -1;
    self.findStatusLabel.stringValue = @"";
    self.currentFindString = @"";
    
    [self.pdfView.window makeFirstResponder:self.pdfView];
}

// ===========================================================================
// 查找核心逻辑
// ===========================================================================
- (void)performFindWithString:(NSString *)string backwards:(BOOL)backwards {
    if (!string || string.length == 0) {
        self.currentFindString = @"";
        self.findStatusLabel.stringValue = @"";
        self.pdfView.highlightedSelections = nil;
        self.allSelections = @[];
        self.currentMatchIndex = -1;
        return;
    }

    BOOL stringChanged = ![string isEqualToString:self.currentFindString];
    
    if (stringChanged) {
        self.currentFindString = string;
        
        if (self.pdfView.document) {
            // 同步查找整个文档中的所有匹配项
            NSArray<PDFSelection *> *selections = [self.pdfView.document findString:string withOptions:NSCaseInsensitiveSearch];
            self.allSelections = selections ?: @[];
            
            if (self.allSelections.count > 0) {
                self.currentMatchIndex = backwards ? (self.allSelections.count - 1) : 0;
            } else {
                self.currentMatchIndex = -1;
            }
        }
    } else {
        // 搜索词未变，仅在匹配项中循环跳转
        if (self.allSelections.count > 0) {
            if (backwards) {
                self.currentMatchIndex = (self.currentMatchIndex <= 0) ? (self.allSelections.count - 1) : (self.currentMatchIndex - 1);
            } else {
                self.currentMatchIndex = (self.currentMatchIndex >= (long)self.allSelections.count - 1) ? 0 : (self.currentMatchIndex + 1);
            }
        }
    }
    
    [self updateHighlights];
}

- (void)updateHighlights {
    if (self.allSelections.count == 0) {
        self.findStatusLabel.stringValue = @"0/0";
        self.pdfView.highlightedSelections = nil;
        return;
    }
    
    self.findStatusLabel.stringValue = [NSString stringWithFormat:@"%ld/%ld", (long)(self.currentMatchIndex + 1), (long)self.allSelections.count];
    
    // 必须使用深拷贝，否则会污染 PDFKit 底层的 Selection 缓存，导致之前输入一半的单词（如 soft）一直高亮
    NSMutableArray<PDFSelection *> *coloredSelections = [NSMutableArray arrayWithCapacity:self.allSelections.count];
    
    for (NSInteger i = 0; i < (long)self.allSelections.count; i++) {
        // 1. 拷贝 Selection
        PDFSelection *sel = [self.allSelections[i] copy];
        
        // 2. 设置颜色
        if (i == self.currentMatchIndex) {
            sel.color = [NSColor colorWithRed:1.0 green:0.588 blue:0.196 alpha:1.0]; // #FF9632 (橙色)
        } else {
            sel.color = [NSColor yellowColor];
        }
        
        [coloredSelections addObject:sel];
    }
    
    // 3. 触发 PDFView 重绘高亮
    self.pdfView.highlightedSelections = coloredSelections;
    
    // 4. 跳转到当前匹配项（使用 goToSelection: 而不是 scrollSelectionToVisible: 以支持跨页跳转）
    if (self.currentMatchIndex >= 0 && self.currentMatchIndex < (long)coloredSelections.count) {
        PDFSelection *currentSel = coloredSelections[self.currentMatchIndex];
        [self.pdfView goToSelection:currentSel];
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
        // 防抖处理
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(triggerSearchFromTyping) object:nil];
        [self performSelector:@selector(triggerSearchFromTyping) withObject:nil afterDelay:0.25];
    }
}

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

#pragma mark - AppineBackend Protocol

- (NSView *)view {
    // 返回包含了 Find Bar 和 PDFView 的复合容器
    return self.containerView;
}

- (NSString *)title {
    return [self.path lastPathComponent] ?: @"PDF";
}

@end

// C API export
id<AppineBackend> appine_create_pdf_backend(NSString *path) {
    return [[AppinePdfBackend alloc] initWithPath:path];
}
