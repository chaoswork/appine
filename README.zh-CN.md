[English](./README.md) | 简体中文

# Appine.el 🍎

![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)
![OS: macOS](https://img.shields.io/badge/OS-macOS-lightgrey.svg)
![Emacs: 28.1+](https://img.shields.io/badge/Emacs-28.1+-purple.svg)

**Appine** 的名字源自 “App in Emacs”，它是一个 Emacs 插件，采用动态模块允许你将 macOS 原生视图（WebKit、PDFKit、Quick look PreviewView 等）直接嵌入到 Emacs 窗口中。

你可以在 Emacs 中打开浏览器、阅读 PDF、听音乐、看视频。无需离开 Emacs，即可享受 macOS 原生渲染、平滑滚动和硬件加速的全部威力！


## ✨ 特性 (Features)

- **把它当作 Emacs 缓冲区来用**: 当 Appine 启动的时候，嵌入的窗口会绑定在 \*Appine Window\* 这个 Buffer 上。可以用 `C-x 1` 最大化，用 `C-x 0` 关闭，用 `C-x o` 在不同的 buffer 中切换。也可以使用 `C-n`, `C-p`, `C-v`, `M-v`, `M-<`, and `M->` 来对 Appine Window 进行滚屏操作。
- **原生网页浏览**：在 Emacs 窗口中嵌入一个功能齐全的类似 Safari 的 WebKit 视图，而且支持 cookies。
- **原生 PDF 渲染**：使用 macOS 内置的 PDFKit 查看 PDF，享受丝滑的滚动和缩放体验，而且可以方便地拷贝其中的内容到 Emacs 的其他 buffer。
- **原生 Word/Excel 渲染**：使用 macOS 内置的 Quartz 查看 Word/Excel 文件，同样支持丝滑的滚动和缩放。不过目前还不支持编辑。
- **无缝集成**：当你分割或调整 Emacs 窗口大小时，原生视图会自动调整大小和移动。
- **标签页管理**：支持多个嵌入的标签页，可以直接在 Emacs 中进行切换和关闭。
- **Org-mode集成**：可以使用 Appine 打开 Org 文件中的链接和文件。
- **插件支持**: 现在可以给 Appine 的浏览器写一些简单的插件了。

## 📖 使用方法 (Usage)

### 打开 Appine

使用 `M-x appine` 打开 Appine Window. 如果是第一次打开，会显示一个简单的使用说明。

你可以用 `M-x appine-close` 或者 `C-x 0` 来关闭窗口。如果你想重新打开，可以使用 `M-x appine`, 其实只需要把 \*Appine Window\* 打开即可。

使用 `M-x appine-kill` 会彻底关掉嵌入的 Appine Window。

### 嵌入 App 的两种状态

嵌入的 App 有两种状态：激活和未激活。
- **激活状态**：当 \*Appine Window\* Buffer 被激活时，可以像 Mac 原生 App 那样使用。
- **非激活状态**：当 \*Appine Window\* 未被激活时，嵌入的 App 会被锁定且变灰，无法使用。此时可以正常地使用 Emacs。

一段演示两种状态的视频地址:

https://github.com/user-attachments/assets/a7eaf65a-da9b-45ee-9b24-ca835379fc34


### 打开网页 (Open a Web Page)

运行 `M-x appine-open-url`。系统会提示你输入一个 URL。一个原生的 WebKit 视图将在当前的 Emacs 窗口中打开。一段演示视频如下：

一段 Open Web Page 的视频地址

https://github.com/user-attachments/assets/f63eff4e-754e-4d4f-b11c-aa9d3f982c67

为了快速打开网页上的链接，我给 Appine 内部的浏览器写了个简单的 link-hints 插件，可以类似 Vimium 那样，按 `f` 就可以标注出网页上链接，然后按相应的键就可以快速打开当前网页中的链接，或者按 `q` 退出 link-hints, 如下图： 

<img width="3024" height="1898" alt="Image" src="https://github.com/user-attachments/assets/2e86d223-0d5f-47a3-9e90-b3d3afa36c78" />

### 打开 PDF 或者其他文档
运行 `M-x appine-open-file`。选择一个 PDF 文件，它将使用 macOS PDFKit 进行渲染。选择其他文件则会使用 quicklook 进行预览。

一段打开 PDF 的视频地址

https://github.com/user-attachments/assets/f2dd6c5a-eabb-421b-8d2c-986540f230f6

### Org-mode 集成

当 `(setq appine-use-for-org-links t)` 的时候，会使用 Appine 打开 url 和文件。运行 `M-x appine-toggle-open-in-org-mode` 来开启或者关闭该功能。

TODO：一段演示 org-mode 集成的视频

### 工具栏 (Toolbar)

Toolbar 实现了一些 App 的常用操作，比如新建标签页 (New Tab)、打开文件 (Open File) 等，同时也包含了剪切/复制/粘贴等编辑操作。
由于 Appine 引入了 macOS 的 Quick look Preview 模块，所以常用的文件基本上都可以预览。可以通过 Appine 窗口的 Open File 按钮来打开文件。

复制粘贴的视频

https://github.com/user-attachments/assets/fd33d767-37dd-4027-adae-823b32228c7e

### 窗口管理 (Window Management)

原生视图与 Emacs buffer（名为 `*Appine-Window*`）绑定。你可以分割窗口（`C-x 3`，`C-x 2`），调整它们的大小，或者切换 buffers。原生视图会自动跟踪 Emacs 窗口的几何形状。

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
  :defer t  
  :custom
  ;; 在 org-mode 中使用 Appine 打开链接
  (appine-use-for-org-links t)
  ;; 绑定你喜欢的前缀
  :bind (("C-x a a" . appine)
         ("C-x a u" . appine-open-url)
         ("C-x a o" . appine-open-file)))         
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
   (setq appine-use-for-org-links t)
   (global-set-key (kbd "C-x a a") 'appine)
   (global-set-key (kbd "C-x a u") 'appine-open-url)
   (global-set-key (kbd "C-x a o") 'appine-open-file))

   ```

## 🛠️ 持续完善

Appine 使用 Emacs 动态模块来桥接 C/Objective-C 和 Emacs Lisp。

目前项目还在持续完善中，如果使用有问题，欢迎提 issue。

对于 Windows 和 Linux 系统，会在未来考虑支持。主要是我目前没有 Windows 的电脑，而使用的 Linux 并没有可视化界面，这让我目前没法调试插件。而且 Windows 和 Linux 不像 macOS 那样系统原生自带网页、PDF 和 Office 文件的渲染框架，需要借助于第三方库来实现，这往往会带来不稳定的问题。有些跨平台的库比如 Qt 等往往都特别庞大，对于一个小小的 Emacs 插件来说实在是过于笨重。如果特别想在 Emacs 中使用浏览器、PDF 等 App，可以尝试 [EAF](https://github.com/emacs-eaf/emacs-application-framework) 项目。

## 📄 许可证 (License)

本项目采用 GNU General Public License v3.0 (GPLv3) 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件。