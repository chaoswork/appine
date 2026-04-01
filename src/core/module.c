/*
 * Filename: module.c
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
#include <emacs-module.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include "appine_core.h"

int plugin_is_GPL_compatible; // dynamic-module 必须遵循 GPL 协议

#define DEFINE_EMACS_0PARAM_WRAPPER(func_name, core_func)                    \
    static emacs_value func_name(emacs_env *env, ptrdiff_t nargs,            \
                                 emacs_value *args, void *data) {            \
        core_func();                                                         \
        return env->intern(env, "t");                                        \
    }

static emacs_value Fappine_set_debug_log(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    // 使用 env->extract_integer 来获取 Elisp 传过来的整数
    intmax_t enable = env->extract_integer(env, args[0]);
    appine_core_set_debug_log((int)enable);
    return env->intern(env, "t");
}

static emacs_value Fappine_check_signal(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    // 调用 appine_core.m 中的函数
    bool is_mine = appine_core_check_signal();

    // 如果是 true 返回 Elisp 的 t，否则返回 nil
    return is_mine ? env->intern(env, "t") : env->intern(env, "nil");
}

static char *copy_emacs_string(emacs_env *env, emacs_value str) {
    ptrdiff_t size = 0;
    env->copy_string_contents(env, str, NULL, &size);
    char *buf = malloc(size);
    if (!buf) return NULL;
    env->copy_string_contents(env, str, buf, &size);
    return buf;
}

static int get_emacs_int(emacs_env *env, emacs_value v) {
    return (int)env->extract_integer(env, v);
}

static emacs_value Fappine_open_web_in_rect(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    char *url = copy_emacs_string(env, args[0]);
    if (!url) return env->intern(env, "nil");

    int x = get_emacs_int(env, args[1]);
    int y = get_emacs_int(env, args[2]);
    int w = get_emacs_int(env, args[3]);
    int h = get_emacs_int(env, args[4]);

    appine_core_open_web_in_rect(url, x, y, w, h);
    free(url);
    return env->intern(env, "t");
}

static emacs_value Fappine_open_file_in_rect(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    char *path = copy_emacs_string(env, args[0]);
    if (!path) return env->intern(env, "nil");

    int x = get_emacs_int(env, args[1]);
    int y = get_emacs_int(env, args[2]);
    int w = get_emacs_int(env, args[3]);
    int h = get_emacs_int(env, args[4]);

    appine_core_open_file_in_rect(path, x, y, w, h);
    free(path);
    return env->intern(env, "t");
}

static emacs_value Fappine_move_resize(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    int x = get_emacs_int(env, args[0]);
    int y = get_emacs_int(env, args[1]);
    int w = get_emacs_int(env, args[2]);
    int h = get_emacs_int(env, args[3]);

    appine_core_move_resize(x, y, w, h);
    return env->intern(env, "t");
}

static emacs_value Fappine_set_active(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    int active = get_emacs_int(env, args[0]);
    appine_core_set_active(active);
    return env->intern(env, "t");
}

static emacs_value Fappine_perform_action(emacs_env *env, ptrdiff_t nargs, emacs_value *args, void *data) {
    char *name = copy_emacs_string(env, args[0]);
    if (!name) return env->intern(env, "nil");
    appine_core_perform_action(name);
    free(name);
    return env->intern(env, "t");
}

DEFINE_EMACS_0PARAM_WRAPPER(Fappine_close_active_tab, appine_core_close_active_tab)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_select_next_tab, appine_core_select_next_tab)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_select_prev_tab, appine_core_select_prev_tab)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_web_go_forward, appine_core_web_go_forward)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_web_go_back, appine_core_web_go_back)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_web_reload, appine_core_web_reload)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_focus, appine_core_focus)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_unfocus, appine_core_unfocus)
DEFINE_EMACS_0PARAM_WRAPPER(Fappine_close, appine_core_close)

static void bind_function(emacs_env *env,
                          const char *name,
                          ptrdiff_t min_arity,
                          ptrdiff_t max_arity,
                          emacs_value (*fn)(emacs_env*, ptrdiff_t, emacs_value*, void*),
                          const char *doc) {
    emacs_value fset = env->intern(env, "fset");
    emacs_value symbol = env->intern(env, name);
    emacs_value function = env->make_function(env, min_arity, max_arity, fn, doc, NULL);
    emacs_value args[] = { symbol, function };
    env->funcall(env, fset, 2, args);
}

int emacs_module_init(struct emacs_runtime *runtime) {
    emacs_env *env = runtime->get_environment(runtime);

    bind_function(env, "appine-native-open-web-in-rect", 5, 5, Fappine_open_web_in_rect,
                  "Open URL in embedded rect as a new tab.");
    bind_function(env, "appine-native-open-file-in-rect", 5, 5, Fappine_open_file_in_rect,
                  "Open File in embedded rect as a new tab.");
    bind_function(env, "appine-native-move-resize", 4, 4, Fappine_move_resize,
                  "Move/resize embedded native view.");
    bind_function(env, "appine-native-close-active-tab", 0, 0, Fappine_close_active_tab,
                  "Close active embedded tab.");
    bind_function(env, "appine-native-select-next-tab", 0, 0, Fappine_select_next_tab,
                  "Select next embedded tab.");
    bind_function(env, "appine-native-select-prev-tab", 0, 0, Fappine_select_prev_tab,
                  "Select previous embedded tab.");

    bind_function(env, "appine-native-web-go-forward", 0, 0, Fappine_web_go_forward,
                  "show next web.");
    bind_function(env, "appine-native-web-go-back", 0, 0, Fappine_web_go_back,
                  "show last web.");
    bind_function(env, "appine-native-web-reload", 0, 0, Fappine_web_reload,
                  "reload webpage.");

    bind_function(env, "appine-native-focus", 0, 0, Fappine_focus,
                  "Focus active embedded native view.");
    bind_function(env, "appine-native-unfocus", 0, 0, Fappine_unfocus,
                  "Unfocus embedded native view.");
    bind_function(env, "appine-native-set-active", 1, 1, Fappine_set_active,
                  "Set embedded native view active/inactive.");
    bind_function(env, "appine-native-perform-action", 1, 1, Fappine_perform_action,
                  "Perform a named native action.");
    bind_function(env, "appine-native-close", 0, 0, Fappine_close,
                  "Close embedded native view.");
    bind_function(env, "appine-set-debug-log", 1, 1, Fappine_set_debug_log,
              "Enable or disable native debug logging.");
    bind_function(env, "appine-check-signal", 0, 0, Fappine_check_signal,
                  "Check if SIGUSR1 was triggered by appine deactivate button.");

    emacs_value provide = env->intern(env, "provide");
    emacs_value feature = env->intern(env, "appine-module");
    emacs_value pargs[] = { feature };
    env->funcall(env, provide, 1, pargs);

    return 0;
}
