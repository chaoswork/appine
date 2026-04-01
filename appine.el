;;; appine.el --- Embed native macOS views (WebKit, PDFKit, etc.) in Emacs -*- lexical-binding: t; -*-

;; Filename: appine.el
;; Description: Appine = App in Emacs. Embed native macOS apps inside Emacs.
;; Author: Huang Chao <huangchao.cpp@gmail.com>
;; Copyright (C) 2026, Huang Chao, all rights reserved.
;; Created: 2026-03-15 19:35:21
;; Version: 0.0.7
;; Package-Requires: ((emacs "29.1"))
;; URL: https://github.com/chaoswork/appine
;; Keywords: tools, multimedia, convenience, macos
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Appine ("App in Emacs") is an Emacs plugin using a Dynamic Module
;; that allows you to embed native macOS views (WebKit, PDFKit,
;; Quick Look PreviewView, etc.) directly inside Emacs windows.
;;
;; You can open a browser, read PDFs, listen to music, and watch
;; videos in Emacs. Enjoy the full power of native macOS rendering,
;; smooth scrolling, and hardware acceleration without leaving Emacs!
;;
;; Features:
;; - Native Web Browsing (WebKit)
;; - Native PDF Rendering (PDFKit)
;; - Native Word/Excel Rendering (Quartz / Quick Look)
;; - Seamless Integration with Emacs window management
;; - Tab Management
;;
;; Requirements:
;; - macOS (Tested on macOS 12+)
;; - Emacs 29.1 or higher compiled with Dynamic Module support
;;   (--with-modules).
;;
;; Please check the README at https://github.com/chaoswork/appine
;; for installation instructions and more details.

;;; Code:



(require 'url)

(defconst appine-github-repo "chaoswork/appine")
(defconst appine-version "0.0.7") ;; 记得打 tag 以使用 github action

;;; ==========================================================================
;;; 加载模块
;;; ==========================================================================
(defvar appine-download-timeout 15
  "下载预编译模块的超时时间（秒）.")

(defvar appine-download-retries 3
  "下载预编译模块的失败重试次数.")

(defvar appine-root-dir
  (file-name-directory
    ;; 返回当前加载文件对应的 .el 源文件真实路径，方便编译
    (let* ((file (or load-file-name (buffer-file-name)))
         (source-file
          (if (and file (string-suffix-p ".elc" file))
              (substring file 0 -1)   ; "foo.elc" -> "foo.el"
            file)))
    (and source-file
         (file-truename source-file))))
  "Appine 插件所在的真实根目录路径.")

(defun appine--remove-quarantine (file)
  "尝试移除 macOS Gatekeeper 隔离属性，不然加载时可能会有弹窗拦截."
  (when (and (eq system-type 'darwin)
             (executable-find "xattr")
             (file-exists-p file))
    (condition-case err
        (progn
          (call-process "xattr" nil nil nil "-d" "com.apple.quarantine" file)
          (message "[Appine] 已自动移除 Gatekeeper 隔离属性"))
      (error
       (message "[Appine] 移除隔离属性失败: %s" (error-message-string err))))))

(defun appine--compile-module ()
  "本地执行 make 编译动态模块."
  (message "[Appine] Starting local compilation of the module, This may take a few minutes...")
  (let* ((default-directory appine-root-dir)
         (exit-code (call-process "make" nil "*appine-compile*" t)))
    (if (= exit-code 0)
        (message "[Appine] Starting to compile the module locally. This may take a few minutes...")
      (error "[Appine] Local compilation failed.  See the *appine-compile* buffer for error details!"))))

(defun appine--download-module (url dest-path)
  "带有超时和重试机制的下载函数.
如果下载成功返回 t，否则返回 nil."
  (let ((retries appine-download-retries)
        (success nil))
    (while (and (> retries 0) (not success))
      (message "[Appine] Downloading the precompiled module (try %d/%d)..."
               (1+ (- appine-download-retries retries))
               appine-download-retries)
      (condition-case err
          ;; url-retrieve-synchronously 的第 4 个参数是超时时间（秒）
          (let ((buffer (url-retrieve-synchronously url t nil appine-download-timeout)))
            (if (not buffer)
                (error "连接超时")
              (with-current-buffer buffer
                (goto-char (point-min))
                ;; 检查 HTTP 状态码是否为 200
                (if (re-search-forward "^HTTP/[0-9.]+ 200 OK" nil t)
                    (progn
                      ;; 跳过 HTTP Header，找到正文的起始位置
                      (re-search-forward "^\r?\n\r?" nil t)
                      (let ((coding-system-for-write 'no-conversion))
                        (write-region (point) (point-max) dest-path nil 'silent))
                      (setq success t)
                      (message "[Appine] download successful！"))
                  (error "文件不存在或网络错误 (HTTP 状态异常)"))
                (kill-buffer buffer))))
        (error
         (message "[Appine] download failed: %s" (error-message-string err))
         (setq retries (1- retries))
         (when (> retries 0)
           (sleep-for 2))))) ;; 失败后等待 2 秒再重试
    success))

(defun appine-fetch-github-version ()
  "从 GitHub 获取 appine.el 的最新版本号."
  (let* ((url "https://raw.githubusercontent.com/chaoswork/appine/master/appine.el")
         (content
          (condition-case nil
              ;; 添加 5 秒超时，防止网络问题导致 Emacs 启动卡死
              (with-current-buffer (url-retrieve-synchronously url t t 5)
                (unwind-protect
                    (progn
                      (goto-char (point-min))
                      (when (re-search-forward "\r?\n\r?\n" nil t)
                        (buffer-substring-no-properties (point) (point-max))))
                  (kill-buffer (current-buffer))))
            (error nil))))
    (when (and content (string-match "^;;[[:space:]]*Version:[[:space:]]*\\([0-9][0-9.]*\\)" content))
      (match-string 1 content))))

(defun appine--check-update ()
  "检查 GitHub 上的新版本，并根据用户的忽略配置决定是否提示更新。
如果执行了更新并重新加载，则返回 t；否则返回 nil。"
  (let ((github-version (appine-fetch-github-version))
        (updated nil))
    ;; 1. 如果获取到了版本，且和当前版本不一致
    (when (and github-version (not (string= github-version appine-version)))
      (let* ((config-dir (expand-file-name "~/.config/appine/"))
             (config-path (expand-file-name "ignore_version.json" config-dir))
             (trigger-update t)
             (current-time (float-time)))
        
        ;; 2 & 3. 尝试读取配置文件
        (when (file-exists-p config-path)
          (let* ((json-object-type 'alist)
                 (json-array-type 'list)
                 (config (ignore-errors (json-read-file config-path)))
                 (ignore-version (alist-get 'ignore_version config))
                 (last-ask-date (alist-get 'last_ask_date config)))
            ;; 如果配置里的版本和 GitHub 最新版本一致
            (when (and (stringp ignore-version)
                       (string= ignore-version github-version)
                       (numberp last-ask-date))
              ;; 判断最后询问日期是否不到一个月 (30天 = 2592000秒)
              (when (< (- current-time last-ask-date) 2592000)
                (setq trigger-update nil))))) ;; 放弃更新逻辑
        
        ;; 4. 触发更新逻辑
        (when trigger-update
          (if (y-or-n-p (concat (format "[Appine] New version (%s) found on GitHub. Update right now? " github-version)
                                (format "[Appine] github上发现新版本 (%s)，是否更新插件?" github-version)))
              ;; 6. 用户选是：执行 git pull 并重新加载
              (progn
                (message "[Appine] prepare update...")
                (let ((default-directory appine-root-dir))
                  ;; 先执行 git stash 暂存本地可能存在的修改
                  (message "[Appine] stash local modify (git stash)...")
                  (call-process "git" nil nil nil "stash")
                  
                  ;; 然后执行 git pull
                  (message "[Appine] pull the newest code (git pull)...")
                  (if (= 0 (call-process "git" nil nil nil "pull" "origin" "master"))
                      (progn
                        (message "[Appine] Update successfully. Cleaning up old appine-module.dylib...")
                        
                        ;; 1. 检查并删除 appine-module.dylib
                        (let ((dylib-file (expand-file-name "appine-module.dylib" appine-root-dir)))
                          (when (file-exists-p dylib-file)
                            (delete-file dylib-file)
                            (message "[Appine] old appine-module.dylib has been removed")))
                        
                        ;; 2. 重新加载新版本的 appine.el
                        (message "[Appine] reload appine.el ...")
                        (load-file (expand-file-name "appine.el" appine-root-dir))
                        ;; 设置为 github 的版本
                        (setq appine-version github-version)

                        ;; 3. 标记更新成功，不再抛出 error
                        (setq updated t)
                        (message "[Appine] Appine has been successfully updated and reloaded."))
                    
                    ;; ELSE 分支
                    (message "[Appine] Auto update failed! Please update manually."))))

            ;; 5. 用户选否：写入忽略版本
            (unless (file-exists-p config-dir)
              (make-directory config-dir t))
            (let ((json-config (list (cons 'ignore_version github-version)
                                     (cons 'last_ask_date current-time))))
              (with-temp-file config-path
                (insert (json-encode json-config))))))))
    updated)) ;; 返回是否更新成功的状态

(defun appine-ensure-module ()
  "确保动态模块存在。如果不存在，询问是否下载预编译版本，选择是则尝试下载，否则直接本地编译。"
  ;; 如果 appine--check-update 返回 t，说明加载了新文件，新文件会负责加载模块，旧文件直接跳过
  (unless (appine--check-update)
    (let* ((module-file (expand-file-name "appine-module.dylib" appine-root-dir))
           (download-url (format "https://github.com/%s/releases/download/v%s/appine-module.dylib"
                                 appine-github-repo appine-version)))
      
      ;; 1. 如果文件不存在，处理获取逻辑
      (unless (file-exists-p module-file)
        (if (y-or-n-p "[Appine] Would you like to download a precompiled module from GitHub?\n未找到本地模块，是否尝试从 GitHub 下载预编译版本?")
            (progn
              (message "[Appine] Preparing to download the precompiled module...")
              (if (appine--download-module download-url module-file)
                  (appine--remove-quarantine module-file)
                (message "[Appine] Failed to download the precompiled module. Falling back to local compilation...")
                (appine--compile-module)))
          (message "[Appine] Skipping download and starting local compilation...")
          (appine--compile-module)))
      
      ;; 2. 加载模块
      (if (file-exists-p module-file)
          (condition-case err
              (progn
                (appine--remove-quarantine module-file)
                (module-load module-file)
                (message "[Appine] module loaded！"))
            (error
             (message "[Appine] module load failed: %s" (error-message-string err))
             (message "[Appine] If this is caused by macOS security restrictions, please run the following command in Terminal: xattr -d com.apple.quarantine %s" module-file)
             (signal (car err) (cdr err))))
        (error "[Appine] Loading failed. Please read the README.md and try building from source!")))))


;;; ==========================================================================
;;; 核心实现
;;; ==========================================================================
(defgroup appine nil
  "Appine = App in Emacs.  Embed native macOS apps inside Emacs."
  :group 'external)

(defcustom appine-debug-logging nil
  "Enable debug logging for appine native module."
  :type 'boolean
  :group 'appine)

(defcustom appine-dedicated-window nil
  "Whether Appine window should be dedicated while Appine is active.
default is nil, If non-nil, window becomes dedicated only when Appine is active."
  :type 'boolean
  :group 'appine)


(defun appine-toggle-debug-logging ()
  "Toggle native debug logging for appine."
  (interactive)
  (setq appine-debug-logging (not appine-debug-logging))
  (when (featurep 'appine-module)
    (ignore-errors
      (appine-set-debug-log (if appine-debug-logging 1 0))))
  (message "appine debug logging is now %s" (if appine-debug-logging "ON" "OFF")))

(defcustom appine-window-size 1.0
  "Set it to 1.0 to make the two windows split evenly.
If it is less than 1.0, the Appine window will become smaller."
  :type 'number)

(defvar appine--buffer-name "*Appine Window*")
(defvar appine--active nil)
(defvar appine--active-map-enabled nil)

(defvar appine-active-map
  (let ((map (make-sparse-keymap)))
    ;; mac app style shortcuts when active
    ;; 如果已经把 Cmd-c 等绑定到 kill-ring-save, 那按 Cmd-c 的时候，可能会先被 Emacs
    ;; 捕获，导致无法在 Appine-window 执行 copy。
    ;; 所以这里在激活 Appine Window 的时候，绑定到 dynamic module 的函数进行兜底。
    ;; 但是这些函数只在 Appine Window 激活的时候生效，当 M-x appine-copy 的时候，
    ;; Appine Window 自动进入了不激活状态，所以实际上也无法被手动调用，所以用
    ;; lambda () (interactive) 来隐藏 M-x 编辑函数 的调用。
    ;; 后续可能改成在 appine_core.m 中来处理 Cmd key 的捕获。
    (define-key map [?\s-c] (lambda () (interactive) (appine--copy)))
    (define-key map [?\s-v] (lambda () (interactive) (appine--paste)))
    (define-key map [?\s-x] (lambda () (interactive) (appine--cut)))
    (define-key map [?\s-z] (lambda () (interactive) (appine--undo)))
    (define-key map [?\s-f] (lambda () (interactive) (appine--find)))
    ;; (define-key map [?\s-u] #'appine-unfocus) ;; debug
    (define-key map [?\s-w] #'appine-close-tab)
    (define-key map [?\s-t] #'appine-new-tab)
    (define-key map [?\s-r] #'appine-web-reload)
    (define-key map [?\s-o] #'appine-open-file-by-file-chooser)
    (define-key map (kbd "C-x C-f") #'appine-open-file-by-file-chooser)
    (define-key map (kbd "C-c f") #'appine-next-tab)
    (define-key map (kbd "C-c b") #'appine-prev-tab)
    (define-key map (kbd "C-c C-f") #'appine-web-go-forward)
    (define-key map (kbd "C-c C-b") #'appine-web-go-back)
    (define-key map [?\s-g] #'appine-find-next)
    (define-key map [?\s-G] #'appine-find-prev)
    ;; 绑定 C-c C-n 似乎会中断 find 的过程，导致无法按照预期工作
    ;; (define-key map (kbd "C-c C-n") #'appine-find-next)
    ;; (define-key map (kbd "C-c C-p") #'appine-find-prev)
    
    ;; Appine-Window 也支持 Emacs 的常用编辑快捷键
    ;; Meta 键会被被中间某些环节捕获，传递不到 appine_core.m 的 monitor
    ;; 所以通过 perform action 的方式实现。
    (define-key map (kbd "M-w") (lambda () (interactive) (appine--copy)))
    (define-key map (kbd "M-v") (lambda () (interactive) (appine--scroll-page-up)))
    (define-key map (kbd "M-<") (lambda () (interactive) (appine--scroll-to-top)))
    (define-key map (kbd "M->") (lambda () (interactive) (appine--scroll-to-bottom)))
    ;; The shortcuts below are already bound in =appine_core.m=.
    ;; (define-key map (kbd "C-y") #'appine-paste)
    ;; (define-key map (kbd "C-w") #'appine-cut)
    ;; (define-key map (kbd "C-/") #'appine-undo)
    map)
  "High priority keymap used while appine is active.")

(defvar appine--emulation-alist
  `((appine--active-map-enabled . ,appine-active-map)))

(add-to-list 'emulation-mode-map-alists 'appine--emulation-alist)

(defun appine--buffer ()
  (get-buffer-create appine--buffer-name))

(defun appine--should-be-active-p ()
  "判断当前 Appine 是否应该处于激活（接管焦点）状态。
条件：当前选中的窗口正在显示 Appine 的 Buffer。"
  (and (get-buffer appine--buffer-name)
       (eq (current-buffer) (get-buffer appine--buffer-name))))

(defun appine--update-active-keymap ()
  (setq appine--active-map-enabled
        (and appine--active
             (appine--should-be-active-p))))

(defun appine--ensure-window ()
  "确保 Appine Buffer 有一个可见的窗口，如果没有则向右分屏创建。"
  (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
    (unless win
      (let* ((base (selected-window))
             (new (split-window base nil 'right)))
        (setq win new)
        (set-window-buffer new (appine--buffer))
        (set-window-dedicated-p new nil)      
        
        (with-current-buffer (appine--buffer)
          (setq-local mode-line-format nil)
          (setq-local header-line-format nil)
          (setq-local cursor-type nil)
          (setq buffer-read-only t)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert "\nThis is the *Appine Window* buffer.\n")
            (insert "\nIf you can see this message, Emacs is currently displaying at least two *Appine Window* buffers.\n")
            (insert "\nThe embedded macOS view of Appine can only be attached to the active *Appine Window* buffer.\n")
            (insert "\nYou can press `C-x 1` to close this buffer.\n")))

        (let* ((total (window-total-width base))
               (target (max 20 (floor (* total appine-window-size)))))
          (ignore-errors
            (window-resize new (- target (window-total-width new)) t)))))
    win))

(defun appine--window-pixel-rect (win)
  (let* ((edges (window-inside-pixel-edges win))
         (left (nth 0 edges))
         (top (nth 1 edges))
         (right (nth 2 edges))
         (bottom (nth 3 edges))
         (frame-px-height (frame-pixel-height))
         (x left)
         (y (- frame-px-height bottom))
         (w (- right left))
         (h (- bottom top)))
    (list x y w h)))

(defun appine--rect ()
  (let ((win (or (appine--get-active-window-for-buffer appine--buffer-name)
                 (appine--ensure-window))))
    (appine--window-pixel-rect win)))

(defun appine--set-active (flag)
  (unless (eq appine--active flag)
    (setq appine--active flag)
    (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
      ;; 失活时一定解除 dedicated，避免影响 C-x ? 等改变窗口的操作
      (when (window-live-p win)
        (set-window-dedicated-p win (and flag appine-dedicated-window))))
    (appine--update-active-keymap)
    (when (featurep 'appine-module)
      (ignore-errors
        (appine-native-set-active (if flag 1 0))))))

(defun appine--sync-active-state (&rest _args)
  "同步 Appine 的激活状态。"
  (appine--set-active (appine--should-be-active-p)))

(defun appine-refresh ()
  "Refresh embedded native view position."
  (interactive)
  (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
    (when win
      (pcase-let* ((`(,x ,y ,w ,h) (appine--window-pixel-rect win)))
        (appine-native-move-resize x y w h)))))

(defun appine-focus ()
  "Activate appine native interaction."
  (interactive)
  (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
    (when win
      (select-window win)
      (appine--set-active t)
      (appine-native-focus))))

(defun appine-unfocus ()
  "Deactivate appine native interaction."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine--set-active nil)
    (appine-native-unfocus)))

(defun appine-native-action (name)
  "Perform native appine action NAME."
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-focus)
    (appine-native-perform-action name)))

;; scroll page down, scroll to top or bottom implement in appine_core.m
(defun appine--scroll-page-up ()
  "Native scroll page up for active appine."
  (appine-native-action "scrollPageUp"))

(defun appine--scroll-to-top ()
  "Native scroll to top for active appine."
  (appine-native-action "scrollToTop"))

(defun appine--scroll-to-bottom ()
  "Native scroll to bottom for active appine."
  (appine-native-action "scrollToBottom"))

(defun appine--copy ()
  "Native copy for active appine."
  (appine-native-action "copy"))

(defun appine--paste ()
  "Native paste for active appine."
  (appine-native-action "paste"))

(defun appine--cut ()
  "Native cut for active appine."
  (appine-native-action "cut"))

(defun appine--undo ()
  "Native undo for active appine."
  (appine-native-action "undo"))

(defun appine--find ()
  "Native find for active appine."
  (appine-native-action "find"))

(defun appine-new-tab ()
  "Open a new default web tab in appine."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-action "newTab")
    (appine--set-active t)))

(defun appine-open-file-by-file-chooser ()
  "This function can only be used when the Appine window is active!
Open a file chooser in appine."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-action "openFile")
    (appine--set-active t)))

(defun appine-close-tab ()
  "Close current embedded native tab."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-close-active-tab)
    (appine-refresh)))

(defun appine-next-tab ()
  "Select next embedded native tab."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-select-next-tab)
    (appine-refresh)))

(defun appine-prev-tab ()
  "Select previous embedded native tab."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-select-prev-tab)
    (appine-refresh)))

(defun appine-web-go-forward ()
  "Go forward in Appine Web Backend."
  (interactive)
  (appine-native-web-go-forward))

(defun appine-web-go-back ()
  "Go back in Appine Web Backend."
  (interactive)
  (appine-native-web-go-back))

(defun appine-web-reload ()
  "Go back in Appine Web Backend."
  (interactive)
  (appine-native-web-reload))

(defun appine-find-next ()
  "Open a new default web tab in appine."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-action "findNext")
    (appine--set-active t)))

(defun appine-find-prev ()
  "Open a new default web tab in appine."
  (interactive)
  (when (appine--get-active-window-for-buffer appine--buffer-name)
    (appine-native-action "findPrevious")
    (appine--set-active t)))



;;;###autoload
(defun appine ()
  "Open the Appine window.
If the `*Appine Window*` buffer already exists,display it in
a right-hand split window; otherwise, split the window
on the right and open the default usage.html help page."
  (interactive)
  (let* ((buf-exists (get-buffer appine--buffer-name))
         (usage-file (expand-file-name "docs/usage.html" appine-root-dir)))
    (if buf-exists
        (let ((win (appine--ensure-window)))
          (select-window win)
          (appine--set-active t))
      (appine-open-file usage-file))))

;;;###autoload
(defun appine-open-url (url)
  "Split window on the right and open URL in a new embedded native tab."
  (interactive "sURL: ")
  ;; 前缀判断均交给 appine_core
  (pcase-let* ((`(,x ,y ,w ,h) (appine--rect)))
    (appine-native-open-web-in-rect url x y w h)
    (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
      (when win (select-window win)))
    (appine--set-active t)))

;;;###autoload
(defun appine-open-file (path)
  "Split window on the right and open PATH in a new embedded native tab."
  (interactive "fFile: ")
  ;; Elisp 只负责把相对路径或 ~ 展开为绝对路径，然后转成 file:// 协议传给统一入口
  (let ((file-url (concat "file://" (expand-file-name path))))
    (appine-open-url file-url))) ; 直接复用 appine-open-url

(defun appine-close ()
  "Close all embedded native views and delete host window when possible."
  (interactive)
  (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
    (when win (delete-window win))))

(defun appine-kill ()
  "Close all embedded native views and delete host window when possible."
  (interactive)
  (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
    (when win (set-window-dedicated-p win nil))
    
    (appine--set-active nil)
    (when (featurep 'appine-module)
      (ignore-errors (appine-native-unfocus))
      (ignore-errors (appine-native-close)))
    
    (setq appine--active nil)
    (setq appine--active-map-enabled nil)
    
    (when (get-buffer appine--buffer-name)
      (kill-buffer appine--buffer-name))
    
    (when (and win (window-live-p win))
      (ignore-errors (delete-window win)))
    
    (appine--update-active-keymap)))

(add-hook 'window-size-change-functions
          (lambda (_frame)
            (when (and (featurep 'appine-module)
                       (appine--get-active-window-for-buffer appine--buffer-name))
              (ignore-errors
                (appine-refresh)))))

(defun appine--get-active-window-for-buffer (buf-name)
  "获取用于渲染 Appine 原生视图的 Emacs 窗口。
优先返回当前选中的窗口（如果它显示的是该 buf），否则返回任意一个显示该 buf 的可见窗口。"
  (let ((sel-win (selected-window)))
    (if (equal (buffer-name (window-buffer sel-win)) buf-name)
        sel-win
      (get-buffer-window buf-name 'visible))))

(defun appine--update-visibility (&rest _args)
  "Check if *appine* buffer is visible and update native view accordingly."
  (when (featurep 'appine-module)
    (let ((win (appine--get-active-window-for-buffer appine--buffer-name)))
      (if win
          (progn
            (ignore-errors (appine-refresh))
            (ignore-errors (appine--sync-active-state)))
        ;; 如果不可见，把原生视图移到屏幕外，并彻底释放焦点
        (appine--set-active nil)
        (ignore-errors
          (appine-native-move-resize -9999 -9999 100 100))))))

(defun appine--post-command-focus-restore ()
  "在 Emacs 执行完命令后，如果用户依然停留在 Appine Buffer，则强制抢回焦点。"
  (when (and appine--active
             (appine--should-be-active-p)
             (featurep 'appine-module))
    (ignore-errors (appine-native-focus))))

;; 将焦点恢复逻辑挂载到 post-command-hook
(add-hook 'post-command-hook #'appine--post-command-focus-restore)

;; 监听窗口布局的变化 (例如 C-x 1, C-x 3, 拖拽边缘)
(add-hook 'window-configuration-change-hook #'appine--update-visibility)

;; 监听窗口内 Buffer 的变化 (例如 C-x b 切换到了 *appine*)
(add-hook 'window-buffer-change-functions #'appine--update-visibility)

;; 监听窗口焦点的变化 (例如 C-x o 切换窗口，让视图能瞬间“瞬移”过去)
(add-hook 'window-selection-change-functions #'appine--update-visibility)

;; 监听 Buffer 列表的变化 (处理一些边缘的焦点同步情况)
(add-hook 'buffer-list-update-hook
          (lambda ()
            (when (and (featurep 'appine-module)
                       (appine--get-active-window-for-buffer appine--buffer-name))
              (ignore-errors
                (appine--sync-active-state)))))


;; 尝试过使用绑定虚拟按键 <f20> 来绑定函数，但是没有成功。改为使用 sigusr1
;; 为了防止其他插件也使用 sigusr1， 加了一个标志位来判断是否是 Appine 发送的信号。
(defvar appine--old-sigusr1-handler (lookup-key special-event-map [sigusr1]))

(defun appine-deactivate-action ()
  "接收 SIGUSR1，检查标志位，决定是否处理。"
  (interactive)
  (if (appine-check-signal)
      ;; 是我们发的信号，执行分屏逻辑
      (let ((mac-buf (get-buffer appine--buffer-name))
            (scratch-buf (get-buffer-create "*scratch*")))
        (when mac-buf
          (set-window-dedicated-p nil nil)
          (delete-other-windows)
          (set-window-buffer nil scratch-buf)
          (let ((new-win (split-window-right)))
            (set-window-buffer new-win mac-buf)
            (select-window (frame-first-window)))))
    (message "[Appine] 拦截到其他 SIGUSR1 信号，交给原来的sigusr1 handler处理！")
    ;; 不是我们发的信号，传递给原来的处理函数
    (when (commandp appine--old-sigusr1-handler)
      (call-interactively appine--old-sigusr1-handler))))

;; 绑定到 SIGUSR1
(define-key special-event-map [sigusr1] #'appine-deactivate-action)

;;; ==========================================================================
;;; Org-mode 集成
;;; ==========================================================================
(defcustom appine-use-for-org-links nil
  "当设置为 t 时，在 org-mode 中尝试使用 Appine 打开 URL 和非 org 文件链接。"
  :type 'boolean
  :group 'appine)

(defun appine-toggle-use-for-org-links ()
  "切换是否在 org-mode 中使用 Appine 打开链接。"
  (interactive)
  (setq appine-use-for-org-links (not appine-use-for-org-links))
  (message "[Appine] Org-mode: Open files/URLs with Appine: %s"
           (if appine-use-for-org-links "开启 (ON)" "关闭 (OFF)")))

(defun appine--org-open-at-point ()
  "拦截 `org-open-at-point'，根据配置使用 Appine 打开链接。
作为 hook 函数添加到 `org-open-at-point-functions' 中。"
  (when appine-use-for-org-links
    (let* ((context (ignore-errors (org-element-context)))
           (type (org-element-type context)))
      (when (eq type 'link)
        (let ((link-type (org-element-property :type context))
              (path (org-element-property :path context)))
          (cond
           ;; 1. 处理 URL (http / https)
           ((member link-type '("http" "https"))
            (let ((url (concat link-type ":" path)))
              (appine-open-url url))
            t) ;; 返回 t 表示已拦截处理
           
           ;; 2. 处理文件链接
           ((equal link-type "file")
            ;; 如果是 org 文件，返回 nil 交给 org-mode 默认处理
            (if (string-suffix-p ".org" path t)
                nil
              ;; 否则使用 appine 打开文件
              (appine-open-file path)
              t)) ;; 返回 t 表示已拦截处理
           
           ;; 3. 其他类型（如内部标题链接、id 链接等），返回 nil 交给 org-mode 默认处理
           (t nil)))))))

;; 在 org-mode 加载后自动挂载 hook
(with-eval-after-load 'org
  (add-hook 'org-open-at-point-functions #'appine--org-open-at-point))

(appine-ensure-module)
(when (featurep 'appine-module)
  (ignore-errors
    (appine-set-debug-log (if appine-debug-logging 1 0))))


(provide 'appine)
