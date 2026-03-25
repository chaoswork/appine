/*
 * Filename: appine_core.h
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
#ifndef APPINE_CORE_H
#define APPINE_CORE_H
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

int appine_core_open_web_in_rect(const char *url, int x, int y, int width, int height);
int appine_core_open_file_in_rect(const char *path, int x, int y, int width, int height);
int appine_core_move_resize(int x, int y, int width, int height);
int appine_core_close(void);

int appine_core_close_active_tab(void);
int appine_core_select_next_tab(void);
int appine_core_select_prev_tab(void);

int appine_core_focus(void);
int appine_core_unfocus(void);
int appine_core_set_active(int active);
int appine_core_perform_action(const char *action_name);

void appine_core_set_debug_log(int enable);
bool appine_core_check_signal(void);

int appine_core_web_go_forward(void);
int appine_core_web_go_back(void);
int appine_core_web_reload(void);

#ifdef __OBJC__
#import <Foundation/Foundation.h>

extern BOOL g_appine_debug_log;

#define APPINE_LOG(fmt, ...) do { \
    if (g_appine_debug_log) { \
        NSLog((@"[appine] " fmt), ##__VA_ARGS__); \
    } \
} while(0)
#endif
  

#ifdef __cplusplus
}
#endif

#endif
