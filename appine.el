;;; appine.el --- Embed native macOS views (WebKit, PDFKit, etc.) in Emacs -*- lexical-binding: t; -*-

;; Filename: appine.el
;; Description: Appine = App in Emacs. Embed native macOS apps inside Emacs.
;; Author: Huang Chao <huangchao.cpp@gmail.com>
;; Copyright (C) 2026, Huang Chao, all rights reserved.
;; Created: 2026-03-15 19:35:21
;; Version: 0.0.5
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
(defconst appine-version "0.0.5") ;; 记得打 tag 以使用 github action


;; 加载模块

(defvar appine-download-timeout 15
  "下载预编译模块的超时时间（秒）。")

(defvar appine-download-retries 3
  "下载预编译模块的失败重试次数。")

(defun my-source-file-name ()
  "返回当前加载文件对应的 .el 源文件真实路径，方便编译"
  (let* ((file (or load-file-name (buffer-file-name)))
         (source-file
          (if (and file (string-suffix-p ".elc" file))
              (substring file 0 -1)   ; "foo.elc" -> "foo.el"
            file)))
    (and source-file
         (file-truename source-file))))

(defun appine--remove-quarantine (file)
  "尝试移除 macOS Gatekeeper 隔离属性，不然加载时可能会有弹窗拦截。"
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
  "本地执行 make 编译动态模块。"
  (message "[Appine] Starting local compilation of the module, This may take a few minutes...")
  (let* ((dir (file-name-directory (my-source-file-name)))
         (default-directory dir)
         (exit-code (call-process "make" nil "*appine-compile*" t)))
    (if (= exit-code 0)
        (message "[Appine] Starting to compile the module locally. This may take a few minutes...")
      (error "[Appine] Local compilation failed. See the *appine-compile* buffer for error details."))))

(defun appine--download-module (url dest-path)
  "带有超时和重试机制的下载函数。
如果下载成功返回 t，否则返回 nil。"
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

(defun appine-ensure-module ()
  "确保动态模块存在。如果不存在，询问是否下载预编译版本，选择是则尝试下载，否则直接本地编译。"
  ;; 使用 file-truename 解析软链接的真实路径
  (let* ((dir (file-name-directory (my-source-file-name)))
         (module-file (expand-file-name "appine-module.dylib" dir))
         (download-url (format "https://github.com/%s/releases/download/v%s/appine-module.dylib"
                               appine-github-repo appine-version)))
    
    ;; 1. 如果文件不存在，处理获取逻辑
    (unless (file-exists-p module-file)
      ;; 询问用户是否下载预编译版本
      (if (y-or-n-p "[Appine] Would you like to download a precompiled module from GitHub?\n未找到本地模块，是否尝试从 GitHub 下载预编译版本？")
          (progn
            (message "[Appine] Preparing to download the precompiled module...")
            (if (appine--download-module download-url module-file)
                ;; 下载成功后，立刻尝试移除 macOS 的隔离属性
                (appine--remove-quarantine module-file)
              ;; 如果下载失败（超时或网络错误），回退到本地编译
              (message "[Appine] Failed to download the precompiled module. Falling back to local compilation...")
              (appine--compile-module)))
        ;; 用户选择不下载（选 n），直接进入本地编译
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
           (message "[Appine] 如果是 macOS 安全限制，请在终端执行: xattr -d com.apple.quarantine %s" module-file)
           (signal (car err) (cdr err))))
      (error "[Appine] Loading failed. Please read the README.md and try building from source."))))

;; 在插件加载时自动执行保障逻辑
(appine-ensure-module)

(defgroup appine nil
  "Appine = App in Emacs. Embed native macOS apps inside Emacs."
  :group 'external)

(defcustom appine-debug-logging nil
  "Enable debug logging for appine native module."
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
  "设置为 1.0 目前是平分两个窗口，< 1.0 则 Appine-window 会变小。"
  :type 'number)

(defvar appine--window nil)
(defvar appine--buffer-name "*Appine Window*")
(defvar appine--active nil)
(defvar appine--active-map-enabled nil)

(defvar appine-active-map
  (let ((map (make-sparse-keymap)))
    ;; mac app style shortcuts when active
    (define-key map [?\s-c] #'appine-copy)
    (define-key map [?\s-v] #'appine-paste)
    (define-key map [?\s-x] #'appine-cut)
    (define-key map [?\s-z] #'appine-undo)
    (define-key map [?\s-f] #'appine-find)
    (define-key map [?\s-w] #'appine-close-tab)
    (define-key map [?\s-t] #'appine-new-tab)
    (define-key map [?\s-o] #'appine-core-open-file)
    map)
  "High priority keymap used while appine is active.")

(defvar appine--emulation-alist
  `((appine--active-map-enabled . ,appine-active-map)))

(add-to-list 'emulation-mode-map-alists 'appine--emulation-alist)

(defun appine--buffer ()
  (get-buffer-create appine--buffer-name))

(defun appine--window-live-p ()
  (and appine--window (window-live-p appine--window)))

(defun appine--update-active-keymap ()
  (setq appine--active-map-enabled
        (and appine--active
             (appine--window-live-p)
             (eq (selected-window) appine--window))))

(defun appine--buffer ()
  (get-buffer-create appine--buffer-name))

(defun appine--ensure-window ()
  (unless (appine--window-live-p)
    (let* ((base (selected-window))
           (new (split-window base nil 'right)))
      (setq appine--window new)
      (set-window-buffer new (appine--buffer))
      
      ;;将这个窗口标记为专用，并禁止 Emacs 自动把其他 buffer 塞进来
      (set-window-dedicated-p new t)
      (set-window-parameter new 'no-other-window t)
      
      (with-current-buffer (appine--buffer)
        (setq-local mode-line-format nil)
        (setq-local header-line-format nil)
        (setq-local cursor-type nil)
        (setq buffer-read-only t)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "appine host\n")
          (insert "Toolbar is shown above tab bar.\n")
          (insert "Inactive mode: Emacs keybindings\n")
          (insert "Active mode: native mac view interaction\n\n")
          (insert "Commands:\n")
          (insert "  M-x appine-open-web-split\n")
          (insert "  M-x appine-open-pdf-split\n")
          (insert "  M-x appine-focus\n")
          (insert "  M-x appine-unfocus\n")
          (insert "  M-x appine-next-tab\n")
          (insert "  M-x appine-prev-tab\n")
          (insert "  M-x appine-close-tab\n")
          (insert "  M-x appine-close\n")))

      (let* ((total (window-total-width base))
             (target (max 20 (floor (* total appine-window-size)))))
        (ignore-errors
          (window-resize new (- target (window-total-width new)) t)))

      new))
  appine--window)

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
  (appine--window-pixel-rect (appine--ensure-window)))

(defun appine--set-active (flag)
  (unless (eq appine--active flag)
    (setq appine--active flag)
    (appine--update-active-keymap)
    (when (featurep 'appine-module)
      (ignore-errors
        (appine-native-set-active (if flag 1 0))))))

(defun appine--sync-active-state ()
  (when (appine--window-live-p)
    (appine--set-active (eq (selected-window) appine--window)))
  (unless (appine--window-live-p)
    (setq appine--active nil)
    (appine--update-active-keymap))
  (message "appine--active: %s, appine--active-map-enabled: %s" appine--active appine--active-map-enabled)
  )

(defun appine-refresh ()
  "Refresh embedded native view position."
  (interactive)
  (when (appine--window-live-p)
    (pcase-let* ((`(,x ,y ,w ,h) (appine--window-pixel-rect appine--window)))
      (appine-native-move-resize x y w h))))

(defun appine-focus ()
  "Activate appine native interaction."
  (interactive)
  (when (appine--window-live-p)
    (select-window appine--window)
    (appine--set-active t)
    (appine-native-focus)))

(defun appine-unfocus ()
  "Deactivate appine native interaction."
  (interactive)
  (when (appine--window-live-p)
    (appine--set-active nil)
    (appine-native-unfocus)))

(defun appine-native-action (name)
  "Perform native appine action NAME."
  (when (appine--window-live-p)
    (appine-native-focus)
    (appine-native-perform-action name)))

(defun appine-copy ()
  "Native copy for active appine."
  (interactive)
  (appine-native-action "copy"))

(defun appine-paste ()
  "Native paste for active appine."
  (interactive)
  (appine-native-action "paste"))

(defun appine-cut ()
  "Native cut for active appine."
  (interactive)
  (appine-native-action "cut"))

(defun appine-undo ()
  "Native undo for active appine."
  (interactive)
  (appine-native-action "undo"))

(defun appine-find ()
  "Native find for active appine."
  (interactive)
  (appine-native-action "find"))

(defun appine-new-tab ()
  "Open a new default web tab in appine."
  (interactive)
  (when (appine--window-live-p)
    (appine-action "new-tab")
    (appine--set-active t)))

(defun appine-core-open-file ()
  "Open a file chooser in appine."
  (interactive)
  (when (appine--window-live-p)
    (appine-native-action "open-file")
    (appine--set-active t)))

;;;###autoload
(defun appine-open-web-split (url)
  "Split window on the right and open URL in a new embedded native web tab."
  (interactive "sURL: ")
  ;; 检查并自动补全 https:// 前缀 (忽略大小写)
  (unless (or (string-prefix-p "http://" url t)
              (string-prefix-p "https://" url t))
    (setq url (concat "https://" url)))
  
  (pcase-let* ((`(,x ,y ,w ,h) (appine--rect)))
    (appine-native-open-web-in-rect url x y w h)
    ;; 强制将 Emacs 的光标焦点移动到 appine 窗口
    (select-window appine--window)
    (appine--set-active t)))

;; TODO: combine appine-open-file-split, appine-open-pdf-split to one func
;;;###autoload
(defun appine-open-file-split (path)
  "Split window on the right and open PATH in a new embedded native Quicklook tab."
  (interactive "fFile: ")
  (pcase-let* ((`(,x ,y ,w ,h) (appine--rect)))
    (appine-native-open-file-in-rect (expand-file-name path) x y w h)
    ;; 强制将 Emacs 的光标焦点移动到 appine 窗口
    (select-window appine--window)
    (appine--set-active t)))

(defun appine-close-tab ()
  "Close current embedded native tab."
  (interactive)
  (when (appine--window-live-p)
    (appine-native-close-active-tab)
    (appine-refresh)))

(defun appine-next-tab ()
  "Select next embedded native tab."
  (interactive)
  (when (appine--window-live-p)
    (appine-native-select-next-tab)
    (appine-refresh)))

(defun appine-prev-tab ()
  "Select previous embedded native tab."
  (interactive)
  (when (appine--window-live-p)
    (appine-native-select-prev-tab)
    (appine-refresh)))

(defun appine-close ()
  "Close all embedded native views and delete host window when possible."
  (interactive)
  (appine-native-close)
  (when (appine--window-live-p)
    (let ((win appine--window))
      (setq appine--window nil)
      (setq appine--active nil)
      (appine--update-active-keymap)
      (when (window-live-p win)
        (ignore-errors
          (delete-window win))))))

(add-hook 'window-size-change-functions
          (lambda (_frame)
            (when (and (featurep 'appine-module)
                       (appine--window-live-p))
              (ignore-errors
                (appine-refresh)))))

(defun appine--update-visibility (&rest _args)
  "Check if *appine* buffer is visible and update native view accordingly."
  (when (featurep 'appine-module)
    (let ((win (get-buffer-window appine--buffer-name)))
      (if win
          (progn
            ;; 如果可见，绑定新窗口并拽回原生视图
            (setq appine--window win)
            (ignore-errors (appine-refresh))
            (ignore-errors (appine--sync-active-state)))
        ;; Trick: 如果不可见，解绑窗口并把原生视图移到屏幕外
        ;; 注意：这里保留 100x100 的大小而不是 0x0，防止 macOS 彻底挂起 WebView 的渲染进程
        (setq appine--window nil)
        (setq appine--active nil)
        (appine--update-active-keymap)
        (ignore-errors
          (appine-native-move-resize -9999 -9999 100 100))))))

;; 监听窗口布局的变化 (例如 C-x 1, C-x 3, 拖拽边缘)
(add-hook 'window-configuration-change-hook #'appine--update-visibility)

;; 监听窗口内 Buffer 的变化 (例如 C-x b 切换到了 *appine*)
(add-hook 'window-buffer-change-functions #'appine--update-visibility)

;; 监听 Buffer 列表的变化 (处理一些边缘的焦点同步情况)
(add-hook 'buffer-list-update-hook
          (lambda ()
            (when (and (featurep 'appine-module)
                       (appine--window-live-p))
              (ignore-errors
                (appine--sync-active-state)))))



(when (featurep 'appine-module)
  (ignore-errors
    (appine-set-debug-log (if appine-debug-logging 1 0))))

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

;;; --------------------------------------------------------
;;; Org-mode 集成
;;; --------------------------------------------------------
(defcustom appine-enable-open-in-org-mode nil
  "当设置为 t 时，在 org-mode 中尝试使用 Appine 打开 URL 和非 org 文件链接。"
  :type 'boolean
  :group 'appine)

(defun appine-toggle-open-in-org-mode ()
  "切换是否在 org-mode 中使用 Appine 打开链接。"
  (interactive)
  (setq appine-enable-open-in-org-mode (not appine-enable-open-in-org-mode))
  (message "[Appine] Org-mode: Open files/URLs with Appine: %s"
           (if appine-enable-open-in-org-mode "开启 (ON)" "关闭 (OFF)")))

(defun appine--org-open-at-point ()
  "拦截 `org-open-at-point'，根据配置使用 Appine 打开链接。
作为 hook 函数添加到 `org-open-at-point-functions' 中。"
  (when appine-enable-open-in-org-mode
    (let* ((context (ignore-errors (org-element-context)))
           (type (org-element-type context)))
      (when (eq type 'link)
        (let ((link-type (org-element-property :type context))
              (path (org-element-property :path context)))
          (cond
           ;; 1. 处理 URL (http / https)
           ((member link-type '("http" "https"))
            (let ((url (concat link-type ":" path)))
              (appine-open-web-split url))
            t) ;; 返回 t 表示已拦截处理
           
           ;; 2. 处理文件链接
           ((equal link-type "file")
            ;; 如果是 org 文件，返回 nil 交给 org-mode 默认处理
            (if (string-suffix-p ".org" path t)
                nil
              ;; 否则使用 appine 打开文件
              (appine-open-file-split path)
              t)) ;; 返回 t 表示已拦截处理
           
           ;; 3. 其他类型（如内部标题链接、id 链接等），返回 nil 交给 org-mode 默认处理
           (t nil)))))))

;; 在 org-mode 加载后自动挂载 hook
(with-eval-after-load 'org
  (add-hook 'org-open-at-point-functions #'appine--org-open-at-point))


(provide 'appine)
