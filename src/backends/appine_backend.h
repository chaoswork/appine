/*
 * Filename: appine_backend.h
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
#ifndef APPINE_BACKEND_H
#define APPINE_BACKEND_H

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, AppineBackendKind) {
    AppineBackendKindUnknown = 0,
    AppineBackendKindWeb,
    AppineBackendKindPDF,
    AppineBackendKindQuickLook,
};

@protocol AppineBackend <NSObject>

// 必须实现：返回要嵌入的 Native View
@property (nonatomic, readonly, strong) NSView *view;

// 必须实现：返回 Tab 显示的标题
@property (nonatomic, readonly, copy) NSString *title;

// 必须实现：返回 Backend 类型
@property (nonatomic, assign, readonly) AppineBackendKind kind;

@optional
// 可选实现：处理特定的动作（如 copy, paste, undo 等）
- (void)performAction:(NSString *)actionName;
// 显示/隐藏页面内查找栏
- (void)toggleFindBar;
// - (BOOL)isFindBarVisible;
- (void)findNext;
- (void)findPrev;

@end

#endif /* APPINE_BACKEND_H */
