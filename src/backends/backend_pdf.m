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

@interface AppinePdfBackend : NSObject <AppineBackend, NSTextFieldDelegate, NSGestureRecognizerDelegate>

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

// ---- highlight/comment
@property (nonatomic, strong) NSView *primaryMenu;
@property (nonatomic, strong) NSView *highlightMenu;
@property (nonatomic, strong) NSView *commentMenu;
@property (nonatomic, strong) NSTextField *commentTextField;
@property (nonatomic, strong) PDFAnnotation *currentAnnotation;
@property (nonatomic, strong) NSTimer *highlightMenuTimer;

@property (nonatomic, strong) NSView *saveBarView;
@property (nonatomic, assign) BOOL isModified;
@property (nonatomic, strong) id eventMonitor;
@property (nonatomic, strong) id clickMonitor;

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

    [self setupAnnotationUI];
    [self setupSaveBar];

    // 监听文本选中事件，弹出 Primary Card
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectionChanged:) name:PDFViewSelectionChangedNotification object:_pdfView];

    // 使用最高优先级的事件监听，强行捕获 PDFView 内的鼠标点击
    __weak __typeof__(self) weakSelf = self;
    self.clickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        if (weakSelf && weakSelf.pdfView.window == event.window) {
            // 拦截点击在我们自定义 Menu 上的事件，防止触发 PDF 的空白处点击逻辑
            NSPoint ptInContainer = [weakSelf.containerView convertPoint:event.locationInWindow fromView:nil];
            if ((!weakSelf.primaryMenu.hidden && NSPointInRect(ptInContainer, weakSelf.primaryMenu.frame)) ||
                (!weakSelf.highlightMenu.hidden && NSPointInRect(ptInContainer, weakSelf.highlightMenu.frame)) ||
                (!weakSelf.commentMenu.hidden && NSPointInRect(ptInContainer, weakSelf.commentMenu.frame))) {
                return event;
            }
            NSPoint pt = [weakSelf.pdfView convertPoint:event.locationInWindow fromView:nil];
            if (NSPointInRect(pt, weakSelf.pdfView.bounds)) {
                [weakSelf handleMouseUpAtPoint:pt];
            }
        }
        return event;
    }];

    // 监听原生右键菜单对 PDF 的修改（捕获 UndoGroup 结束事件）
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(markModified) name:NSUndoManagerDidCloseUndoGroupNotification object:nil];

    // 监听 Cmd-S 快捷键保存
    // __weak __typeof__(self) weakSelf = self;
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        if ((event.modifierFlags & NSEventModifierFlagCommand) && [[event.charactersIgnoringModifiers lowercaseString] isEqualToString:@"s"]) {
            if (weakSelf.isModified) {
                [weakSelf savePdf];
                return nil; // 拦截事件
            }
        }
        return event;
    }];
}

- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer {
    return YES; // 允许我们的点击手势与 PDFView 的原生手势同时触发
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

// ===========================================================================
// Annotation & Save 核心逻辑
// ===========================================================================

- (void)dealloc {
    if (_eventMonitor) [NSEvent removeMonitor:_eventMonitor];
    if (_clickMonitor) [NSEvent removeMonitor:_clickMonitor];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cleanup {
    if (_eventMonitor) {
        [NSEvent removeMonitor:_eventMonitor];
        _eventMonitor = nil;
    }
    if (_clickMonitor) {
        [NSEvent removeMonitor:_clickMonitor];
        _clickMonitor = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // 销毁可能正在运行的定时器，防止延迟释放
    if (_highlightMenuTimer) {
        [_highlightMenuTimer invalidate];
        _highlightMenuTimer = nil;
    }
}


- (void)setupSaveBar {
    CGFloat barHeight = 32.0;
    NSRect frame = self.containerView.frame;
    _saveBarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, barHeight)];
    _saveBarView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _saveBarView.wantsLayer = YES;
    _saveBarView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    _saveBarView.hidden = YES;

    NSTextField *label = [NSTextField labelWithString:@"已修改 (Unsaved Changes)"];
    label.frame = NSMakeRect(10, 8, 200, 16);
    [_saveBarView addSubview:label];

    NSButton *saveBtn = [NSButton buttonWithTitle:@"保存 (Cmd-S)" target:self action:@selector(savePdf)];
    saveBtn.frame = NSMakeRect(frame.size.width - 120, 4, 100, 24);
    saveBtn.autoresizingMask = NSViewMinXMargin;
    [_saveBarView addSubview:saveBtn];

    [self.containerView addSubview:_saveBarView];
}

- (void)setupAnnotationUI {
    // 1. Primary Menu (Highlight / Comment)
    _primaryMenu = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 160, 40)];
    _primaryMenu.wantsLayer = YES;
    _primaryMenu.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    _primaryMenu.layer.cornerRadius = 8;
    _primaryMenu.layer.shadowOpacity = 0.3;
    _primaryMenu.hidden = YES;

    NSButton *hlBtn = [NSButton buttonWithTitle:@"Highlight" target:self action:@selector(actionHighlight)];
    hlBtn.frame = NSMakeRect(10, 8, 70, 24);
    NSButton *cmBtn = [NSButton buttonWithTitle:@"Note" target:self action:@selector(actionComment)];
    cmBtn.frame = NSMakeRect(85, 8, 70, 24);
    [_primaryMenu addSubview:hlBtn];
    [_primaryMenu addSubview:cmBtn];
    [self.containerView addSubview:_primaryMenu];

    // 2. Secondary Menus
    _highlightMenu = [self createSecondaryMenuWithComment:NO];
    _commentMenu = [self createSecondaryMenuWithComment:YES];
    [self.containerView addSubview:_highlightMenu];
    [self.containerView addSubview:_commentMenu];
}

- (NSView *)createSecondaryMenuWithComment:(BOOL)hasComment {
    // 1. 如果是 Note，高度设为 140 以容纳三行；如果是普通 Highlight，保持单行 40
    CGFloat height = hasComment ? 140 : 40;
    NSView *menu = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, height)];
    menu.wantsLayer = YES;
    menu.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    menu.layer.cornerRadius = 8;
    menu.layer.shadowOpacity = 0.3;
    menu.hidden = YES;

    // 顶部左侧：样式按钮 [A], _A, ~A
    NSArray *styles = @[@"[A]", @"_A", @"~A"];
    for (int i=0; i<3; i++) {
        NSButton *btn = [NSButton buttonWithTitle:styles[i] target:self action:@selector(changeStyle:)];
        btn.tag = i; // 0: Highlight, 1: Underline, 2: StrikeOut
        btn.frame = NSMakeRect(10 + i*35, height - 32, 30, 24);
        [menu addSubview:btn];
    }

    // 顶部右侧：删除按钮
    NSButton *delBtn = [NSButton buttonWithTitle:@"Del" target:self action:@selector(deleteAnnotation)];
    delBtn.frame = NSMakeRect(240, height - 32, 30, 24);
    [menu addSubview:delBtn];

    // 颜色按钮
    NSArray *colors = @[[NSColor yellowColor], [NSColor greenColor], [NSColor blueColor], [NSColor redColor], [NSColor purpleColor]];
    for (int i=0; i<5; i++) {
        NSButton *btn = [NSButton buttonWithTitle:@"■" target:self action:@selector(changeColor:)];
        btn.tag = i;
        btn.contentTintColor = colors[i];

        // 动态布局：如果是 Note，颜色按钮放在底部左侧；如果是 Highlight，放在顶部中间
        CGFloat colorY = hasComment ? 8 : (height - 32);
        CGFloat colorX = hasComment ? (10 + i*25) : (120 + i*25);
        btn.frame = NSMakeRect(colorX, colorY, 20, 24);
        btn.bordered = NO;
        [menu addSubview:btn];
    }

    // 中间：多行输入框 & 底部右侧：确认按钮
    if (hasComment) {
        _commentTextField = [NSTextField textFieldWithString:@""];
        // 占据中间区域 (y=40, 高度=65)
        _commentTextField.frame = NSMakeRect(10, 40, 260, 65);
        _commentTextField.placeholderString = @"Add a note here...";
        _commentTextField.usesSingleLineMode = NO;
        ((NSTextFieldCell *)_commentTextField.cell).wraps = YES;
        ((NSTextFieldCell *)_commentTextField.cell).scrollable = NO;
        [menu addSubview:_commentTextField];

        // 确认按钮放在底部右侧
        NSButton *confirmBtn = [NSButton buttonWithTitle:@"Confirm" target:self action:@selector(confirmComment)];
        confirmBtn.frame = NSMakeRect(200, 8, 70, 24);
        [menu addSubview:confirmBtn];
    }

    return menu;
}

- (void)positionMenu:(NSView *)menu atSelection:(PDFSelection *)selection {
    if (!selection || selection.pages.count == 0) return;
    NSRect bounds = [selection boundsForPage:selection.pages.firstObject];
    NSRect viewRect = [self.pdfView convertRect:bounds fromPage:selection.pages.firstObject];

    CGFloat x = NSMidX(viewRect) - menu.frame.size.width / 2;
    CGFloat y = NSMaxY(viewRect) + 10;

    // 边界检查
    if (x < 10) x = 10;
    if (x + menu.frame.size.width > self.containerView.frame.size.width) x = self.containerView.frame.size.width - menu.frame.size.width - 10;

    menu.frame = NSMakeRect(x, y, menu.frame.size.width, menu.frame.size.height);
    menu.hidden = NO;
}

- (void)selectionChanged:(NSNotification *)notif {
    if (self.pdfView.currentSelection.string.length > 0) {
        self.highlightMenu.hidden = YES;
        self.commentMenu.hidden = YES;
        [self positionMenu:self.primaryMenu atSelection:self.pdfView.currentSelection];
    } else {
        self.primaryMenu.hidden = YES;
    }
}

- (void)actionHighlight {
    [self createAnnotationWithComment:NO];
}

- (void)actionComment {
    [self createAnnotationWithComment:YES];
}

- (void)safeAddAnnotation:(PDFAnnotation *)ann toPage:(PDFPage *)page {
    NSUndoManager *undoMgr = self.pdfView.undoManager;
    // 注册撤销动作：如果撤销“添加”，就执行“删除”
    [[undoMgr prepareWithInvocationTarget:self] safeRemoveAnnotation:ann fromPage:page];
    [page addAnnotation:ann];
    [self markModified];
}

- (void)safeRemoveAnnotation:(PDFAnnotation *)ann fromPage:(PDFPage *)page {
    NSUndoManager *undoMgr = self.pdfView.undoManager;
    // 注册撤销动作：如果撤销“删除”，就执行“添加”
    [[undoMgr prepareWithInvocationTarget:self] safeAddAnnotation:ann toPage:page];
    [page removeAnnotation:ann];
    // 智能判断修改状态：如果撤销栈已经空了（说明回到了刚打开或者刚保存时的状态），则清除“已修改”标记
    // 注意：因为当前动作还在执行中，所以要在下一个 RunLoop 检查 canUndo 状态
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!undoMgr.canUndo) {
            self.isModified = NO;
            self.saveBarView.hidden = YES;
            NSLog(@"[appine] Undo stack is empty, document is now clean.");
        } else {
            [self markModified];
        }
    });
}

- (void)createAnnotationWithComment:(BOOL)hasComment {
    PDFSelection *selection = self.pdfView.currentSelection;
    if (!selection || selection.pages.count == 0) return;

    PDFPage *page = selection.pages.firstObject;
    NSRect bounds = [selection boundsForPage:page];

    // 1. 统一创建 Highlight 背景
    PDFAnnotation *ann = [[PDFAnnotation alloc] initWithBounds:bounds forType:PDFAnnotationSubtypeHighlight withProperties:nil];
    ann.color = [NSColor yellowColor];

    NSMutableArray *quadPoints = [NSMutableArray array];
    NSMutableArray<NSValue *> *rects = [NSMutableArray array]; // 记录每一行的局部矩形

    for (PDFSelection *line in [selection selectionsByLine]) {
        NSRect lineBounds = [line boundsForPage:page];

        CGFloat minX = NSMinX(lineBounds) - NSMinX(bounds);
        CGFloat maxX = NSMaxX(lineBounds) - NSMinX(bounds);
        CGFloat minY = NSMinY(lineBounds) - NSMinY(bounds);
        CGFloat maxY = NSMaxY(lineBounds) - NSMinY(bounds);

        [quadPoints addObject:[NSValue valueWithPoint:NSMakePoint(minX, maxY)]];
        [quadPoints addObject:[NSValue valueWithPoint:NSMakePoint(maxX, maxY)]];
        [quadPoints addObject:[NSValue valueWithPoint:NSMakePoint(minX, minY)]];
        [quadPoints addObject:[NSValue valueWithPoint:NSMakePoint(maxX, minY)]];

        if (hasComment) {
            [rects addObject:[NSValue valueWithRect:NSMakeRect(minX, minY, maxX - minX, maxY - minY)]];
        }
    }
    ann.quadrilateralPoints = quadPoints;
    [ann setShouldDisplay:YES];
    [ann setShouldPrint:YES];
    ann.userName = NSUserName() ?: @"User";
    ann.modificationDate = [NSDate date];

    // 开启撤销分组，确保高亮、边缘线、小方块能一次性撤销
    NSUndoManager *undoMgr = self.pdfView.undoManager;
    [undoMgr beginUndoGrouping];

    [self safeAddAnnotation:ann toPage:page];

    // [page addAnnotation:ann];

    // 2. 如果是 Comment，绘制包裹的边缘线
    if (hasComment && rects.count > 0) {
        PDFAnnotation *edgeAnn = [[PDFAnnotation alloc] initWithBounds:bounds forType:PDFAnnotationSubtypeInk withProperties:nil];
        edgeAnn.color = [NSColor blackColor]; // 黑色边缘
        edgeAnn.userName = @"AppineCommentEdge";

        NSBezierPath *path = [NSBezierPath bezierPath];
        NSUInteger n = rects.count;

        if (n == 1) {
            // 只有一行，直接画矩形
            [path appendBezierPathWithRect:[rects[0] rectValue]];
        } else {
            // 多行情况
            NSRect r1 = [rects[0] rectValue];
            NSRect rn_1 = [rects[n - 2] rectValue];
            NSRect rn = [rects[n - 1] rectValue];
            NSRect r2 = [rects[1] rectValue];

            // 按顺序连线
            // y ^
            //   |
            //   +---->
            //        x
            [path moveToPoint:NSMakePoint(NSMinX(r1) - 1, NSMaxY(r1))];    // R1 左上
            [path lineToPoint:NSMakePoint(NSMaxX(r1) + 1, NSMaxY(r1))];    // R1 右上
            [path lineToPoint:NSMakePoint(NSMaxX(rn_1) + 1, NSMinY(rn_1))];// R_{n-1} 右下
            [path lineToPoint:NSMakePoint(NSMaxX(rn) + 1, MIN(NSMaxY(rn),NSMinY(rn_1)))];    // R_n 右上
            [path lineToPoint:NSMakePoint(NSMaxX(rn) + 1, NSMinY(rn))];    // R_n 右下
            [path lineToPoint:NSMakePoint(NSMinX(rn) - 1, NSMinY(rn))];    // R_n 左下
            [path lineToPoint:NSMakePoint(NSMinX(r2) - 1, NSMaxY(r2))];    // R_2 左上
            [path lineToPoint:NSMakePoint(NSMinX(r1) - 1, MAX(NSMinY(r1), NSMaxY(r2)))];    // R_1 左下
            [path closePath]; // 自动闭合回到 R1 左上
        }

        path.lineWidth = 1.5;
        [edgeAnn addBezierPath:path];
        // [page addAnnotation:edgeAnn];
        [self safeAddAnnotation:edgeAnn toPage:page];
    }

    if (hasComment) {
        // 创建一个 Popup 注解，作为便签的可见图标
        NSRect popupBounds = NSMakeRect(NSMinX(bounds), NSMaxY(bounds), 20, 20);
        PDFAnnotation *popup = [[PDFAnnotation alloc] initWithBounds:popupBounds forType:PDFAnnotationSubtypePopup withProperties:nil];
        [self safeAddAnnotation:popup toPage:page];
        ann.popup = popup; // 将 Popup 与当前的高亮关联起来

        ann.contents = @"";
        self.commentTextField.stringValue = @"";
        [self positionMenu:self.commentMenu atSelection:selection];
    } else {
        [self positionMenu:self.highlightMenu atSelection:selection];
        [self startHighlightTimer];
    }

    // 结束撤销分组
    [undoMgr endUndoGrouping];
    [undoMgr setActionName:hasComment ? @"Add Note" : @"Add Highlight"];

    self.currentAnnotation = ann;
    self.primaryMenu.hidden = YES;
    [self.pdfView clearSelection];
    [self markModified];
}

- (void)startHighlightTimer {
    [self.highlightMenuTimer invalidate];
    self.highlightMenuTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
        self.highlightMenu.hidden = YES;
    }];
}

- (void)changeStyle:(NSButton *)sender {
    if (!self.currentAnnotation) return;
    NSString *type = PDFAnnotationSubtypeHighlight;
    if (sender.tag == 1) type = PDFAnnotationSubtypeUnderline;
    // if (sender.tag == 2) type = PDFAnnotationSubtypeSquiggly;
    if (sender.tag == 2) type = PDFAnnotationSubtypeStrikeOut;
    self.currentAnnotation.type = type;
    [self markModified];
    if (!self.highlightMenu.hidden) [self startHighlightTimer];
}

- (void)changeColor:(NSButton *)sender {
    if (!self.currentAnnotation) return;
    self.currentAnnotation.color = sender.contentTintColor;
    [self markModified];
    if (!self.highlightMenu.hidden) [self startHighlightTimer];
}

- (void)deleteAnnotation {
    if (self.currentAnnotation && self.currentAnnotation.page) {
        PDFPage *page = self.currentAnnotation.page;

        // 开启撤销分组
        NSUndoManager *undoMgr = self.pdfView.undoManager;
        [undoMgr beginUndoGrouping];

        // 1. 移除关联的 Popup
        if (self.currentAnnotation.popup) {
            [page removeAnnotation:self.currentAnnotation.popup];
        }

        // 2. 移除关联的边缘线 (Ink)
        PDFAnnotation *edgeToRemove = nil;
        for (PDFAnnotation *a in page.annotations) {
            // 通过我们刚才设定的 userName 标记和相同的 bounds 来精确定位边缘线
            if ([a.userName isEqualToString:@"AppineCommentEdge"] && NSEqualRects(a.bounds, self.currentAnnotation.bounds)) {
                edgeToRemove = a;
                break;
            }
        }
        if (edgeToRemove) {
            [page removeAnnotation:edgeToRemove];
        }

        // 3. 移除本体
        [page removeAnnotation:self.currentAnnotation];

        [undoMgr endUndoGrouping];
        [undoMgr setActionName:@"Delete Annotation"];
        self.currentAnnotation = nil;
        self.highlightMenu.hidden = YES;
        self.commentMenu.hidden = YES;
        [self markModified];
    }
}

- (void)confirmComment {
    if (self.currentAnnotation) {
        self.currentAnnotation.contents = self.commentTextField.stringValue;
        self.currentAnnotation.modificationDate = [NSDate date]; // 更新时间戳
        self.commentMenu.hidden = YES;
        [self markModified];
    }
}

- (void)handleMouseUpAtPoint:(NSPoint)pt {
    PDFPage *page = [self.pdfView pageForPoint:pt nearest:NO];
    if (!page) return;

    NSPoint pagePoint = [self.pdfView convertPoint:pt toPage:page];
    PDFAnnotation *ann = [page annotationAtPoint:pagePoint];
    NSLog(@"[Appine Debug] 点击页面坐标: %@, 捕获到注解类型: %@", NSStringFromPoint(pagePoint), ann ? ann.type : @"无");

    if (ann) {
        // 如果点到了原生的 Popup 黄色方块，我们要通过遍历找到它的父节点（即高亮本身）
        if ([ann.type isEqualToString:@"Popup"]) {
            for (PDFAnnotation *parentAnn in page.annotations) {
                if (parentAnn.popup == ann) {
                    ann = parentAnn;
                    NSLog(@"[Appine Debug] 成功回溯找到父节点高亮");
                    break;
                }
            }
        }
        //如果点到了我们画的边缘线，回溯找到对应的高亮 ---
        if ([ann.type isEqualToString:@"Ink"] && [ann.userName isEqualToString:@"AppineCommentEdge"]) {
            for (PDFAnnotation *parentAnn in page.annotations) {
                if ([parentAnn.type isEqualToString:@"Highlight"] && NSEqualRects(parentAnn.bounds, ann.bounds)) {
                    ann = parentAnn;
                    NSLog(@"[Appine Debug] 成功回溯找到边缘线对应的高亮");
                    break;
                }
            }
        }

        // 使用硬编码字符串比对，防止底层常量指针不一致导致判断失败
        if ([ann.type isEqualToString:@"Highlight"] ||
            [ann.type isEqualToString:@"Underline"] ||
            [ann.type isEqualToString:@"StrikeOut"]) {

            NSLog(@"[Appine Debug] 确认点击了文本标记，准备弹出菜单");
            self.currentAnnotation = ann;
            NSRect viewRect = [self.pdfView convertRect:ann.bounds fromPage:page];

            // 检查是否有评论内容，或者是否有关联的边缘线（判断为 Note）
            BOOL isComment = (ann.popup != nil || (ann.contents && ann.contents.length > 0));
            if (!isComment) {
                for (PDFAnnotation *edge in page.annotations) {
                    if ([edge.type isEqualToString:@"Ink"] && [edge.userName isEqualToString:@"AppineCommentEdge"] && NSEqualRects(edge.bounds, ann.bounds)) {
                        isComment = YES;
                        break;
                    }
                }
            }

            if (isComment) {
                NSLog(@"[Appine Debug] 这是一个 Comment，弹出 Comment Menu");
                self.commentTextField.stringValue = ann.contents ?: @"";
                self.highlightMenu.hidden = YES;

                CGFloat x = NSMidX(viewRect) - self.commentMenu.frame.size.width / 2;
                self.commentMenu.frame = NSMakeRect(x, NSMaxY(viewRect) + 10, self.commentMenu.frame.size.width, self.commentMenu.frame.size.height);
                self.commentMenu.hidden = NO;
            } else {
                NSLog(@"[Appine Debug] 这是一个纯 Highlight，弹出 Highlight Menu");
                self.commentMenu.hidden = YES;

                CGFloat x = NSMidX(viewRect) - self.highlightMenu.frame.size.width / 2;
                self.highlightMenu.frame = NSMakeRect(x, NSMaxY(viewRect) + 10, self.highlightMenu.frame.size.width, self.highlightMenu.frame.size.height);
                self.highlightMenu.hidden = NO;
                [self startHighlightTimer];
            }
            return;
        }
    }

    // 点击空白处隐藏菜单
    self.highlightMenu.hidden = YES;
    if (self.commentMenu.hidden == NO && [self.commentTextField.stringValue isEqualToString:@""]) {
        self.commentMenu.hidden = YES;
    }
}

- (void)markModified {
    self.isModified = YES;
    self.saveBarView.hidden = NO;
}

- (void)savePdf {
    if (self.path) {
        NSURL *url = [NSURL fileURLWithPath:self.path];
        BOOL success = [self.pdfView.document writeToURL:url];
        if (success) {
            self.isModified = NO;
            self.saveBarView.hidden = YES;
            NSLog(@"[Appine] PDF 批注保存成功！");
        } else {
            NSLog(@"[Appine] PDF 保存失败！");
        }
    }
}


@end

// C API export
id<AppineBackend> appine_create_pdf_backend(NSString *path) {
    return [[AppinePdfBackend alloc] initWithPath:path];
}
