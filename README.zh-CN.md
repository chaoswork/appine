[English](./README.md) | 简体中文

# Appine.el 🍎

![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)
![OS: macOS](https://img.shields.io/badge/OS-macOS-lightgrey.svg)
![Emacs: 28.1+](https://img.shields.io/badge/Emacs-28.1+-purple.svg)

**Appine** 的名字源自 “App in Emacs”，它是一个 Emacs 插件，采用动态模块允许你将 macOS 原生视图（WebKit、PDFKit、Quick look PreviewView 等）直接嵌入到 Emacs 窗口中。

你可以在 Emacs 中打开浏览器、阅读 PDF、听音乐、看视频。无需离开 Emacs，即可享受 macOS 原生渲染、平滑滚动和硬件加速的全部威力！

对于 Windows 和 Linux 系统，会在未来考虑支持。主要是我目前没有 Windows 的电脑，而使用的 Linux 并没有可视化界面，这让我目前没法调试插件。而且 Windows 和 Linux 不像 macOS 那样系统原生自带网页、PDF 和 Office 文件的渲染框架，需要借助于第三方库来实现，这往往会带来不稳定的问题。有些跨平台的库比如 Qt 等往往都特别庞大，对于一个小小的 Emacs 插件来说实在是过于笨重。如果特别想在 Emacs 中使用浏览器、PDF 等 App，可以尝试 [EAF](https://github.com/emacs-eaf/emacs-application-framework) 项目。

## ✨ 特性 (Features)

- **原生网页浏览**：在 Emacs 窗口中嵌入一个功能齐全的类似 Safari 的 WebKit 视图，而且支持 cookies。
- **原生 PDF 渲染**：使用 macOS 内置的 PDFKit 查看 PDF，享受丝滑的滚动和缩放体验，而且可以方便地拷贝其中的内容到 Emacs 的其他 buffer。
- **原生 Word/Excel 渲染**：使用 macOS 内置的 Quartz 查看 Word/Excel 文件，同样支持丝滑的滚动和缩放。不过目前还不支持编辑。
- **无缝集成**：当你分割或调整 Emacs 窗口大小时，原生视图会自动调整大小和移动。
- **标签页管理**：支持多个嵌入的标签页，可以直接在 Emacs 中进行切换和关闭。

## 📖 使用方法 (Usage)

### 嵌入 App 的两种状态

嵌入的 App 有两种状态：激活和未激活。
- **激活状态**：点击嵌入的 App 可以进入到嵌入 App 的激活状态。当激活的时候可以像 Mac 原生 App 那样使用。此时 Emacs 被锁定。
- **非激活状态**：当鼠标点击其他 Emacs 的 buffer 的时候，嵌入的 App 会被锁定且变灰，无法使用。此时可以正常地使用 Emacs。如果原生视图当前拥有焦点，你可以点击 **Deactivate** 按钮（或使用配置的快捷键）安全地将焦点交还给 Emacs，并将视图拆分为并排布局。

一段演示两种状态的视频地址:

https://github.com/user-attachments/assets/a7eaf65a-da9b-45ee-9b24-ca835379fc34

deactivate:

https://github.com/user-attachments/assets/986af882-56e5-4ce4-b66d-1acde987c9ed


### 打开网页 (Open a Web Page)
运行 `M-x appine-open-web-split`。系统会提示你输入一个 URL。一个原生的 WebKit 视图将在当前的 Emacs 窗口中打开。一段演示视频如下：

一段 Open Web Page 的视频地址

https://github.com/user-attachments/assets/f63eff4e-754e-4d4f-b11c-aa9d3f982c67

### 打开 PDF 文档 (Open a PDF Document)
运行 `M-x appine-open-pdf-split`。选择一个 PDF 文件，它将使用 macOS PDFKit 进行渲染。

一段打开 PDF 的视频地址

https://github.com/user-attachments/assets/fd33d767-37dd-4027-adae-823b32228c7e

### 工具栏 (Toolbar)

Toolbar 实现了一些 App 的常用操作，比如新建标签页 (New Tab)、打开文件 (Open File) 等，同时也包含了剪切/复制/粘贴等编辑操作。
由于 Appine 引入了 macOS 的 Quick look Preview 模块，所以常用的文件基本上都可以预览。可以通过 Appine 窗口的 Open File 按钮来打开文件。

### 窗口管理 (Window Management)
原生视图与 Emacs buffer（例如 `*Appine*`）绑定。你可以分割窗口（`C-x 3`，`C-x 2`），调整它们的大小，或者切换 buffers。原生视图会自动跟踪 Emacs 窗口的几何形状。

## 📦 环境要求 (Requirements)

- **macOS** (在 macOS 12+ 上测试通过)
- **Emacs 29.1 或更高版本**，编译时需开启动态模块支持 (`--with-modules`)。可以使用 `M-: (functionp 'module-load)` 来判断是否有 `module-load` 函数。
  *(注意：大多数流行的发行版，如 Emacs Plus、Emacs Mac Port 和 emacsformacosx 默认已启用此功能)。*

## 🚀 安装 (Installation)

### 方法 1：预编译二进制文件（推荐）

安装 Appine 最简单的方法是使用 `use-package` 配合 `straight.el` 或 `quelpa`。该包会在首次运行时**自动下载**适用于你 Mac 的预编译原生二进制文件（`.dylib`，支持 Apple Silicon 和 Intel）。

```elisp
(use-package appine
  :straight (appine :type git :host github :repo "chaoswork/appine")
  :config
  ;; 可选：设置默认快捷键
  (global-set-key (kbd "C-x a w") 'appine-open-web-split)
  (global-set-key (kbd "C-x a p") 'appine-open-pdf-split))
```

### 方法 2：源码编译

如果你更喜欢自己编译模块，你需要安装 Xcode 命令行工具 (`xcode-select --install`)。

1. 克隆仓库：
   ```bash
   git clone https://github.com/chaoswork/appine.git ~/.emacs.d/lisp/appine
   ```
2. 编译 C/Objective-C 模块：
   ```bash
   cd ~/.emacs.d/lisp/appine
   make
   ```
3. 添加到你的 `init.el`：
   ```elisp
   (add-to-list 'load-path "~/.emacs.d/lisp/appine")
   (require 'appine)
   ```

## 🛠️ 持续完善

Appine 使用 Emacs 动态模块来桥接 C/Objective-C 和 Emacs Lisp。
为了安全地处理由 macOS UI 线程触发的事件（如点击按钮）而不导致 Emacs 崩溃，它使用了 POSIX 信号 (`SIGUSR1`) 和 C11 `atomic_bool` 标志的组合，以安全地中断 Emacs 的事件循环并执行 Lisp 回调。
目前项目还在持续完善中，如果使用有问题，欢迎提 issue。

## 📄 许可证 (License)

本项目采用 GNU General Public License v3.0 (GPLv3) 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件。