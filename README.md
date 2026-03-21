English | [简体中文](./README.zh-CN.md)

# Appine.el 🍎

![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)
![OS: macOS](https://img.shields.io/badge/OS-macOS-lightgrey.svg)
![Emacs: 28.1+](https://img.shields.io/badge/Emacs-28.1+-purple.svg)

**Appine** means "App in Emacs", which is an Emacs plugin using a Dynamic Module that allows you to embed native macOS views (WebKit, PDFKit, Quick look PreviewView, etc.) directly inside Emacs windows. 

You can open a browser, read PDFs, listen to music, and watch videos in Emacs. Enjoy the full power of native macOS rendering, smooth scrolling, and hardware acceleration without leaving Emacs!


## ✨ Features

- **Use It Like an Emacs Buffer**: When Appine starts, it opens an embedded Appine Window tied to an \*Appine Window\* buffer. You can maximize it with `C-x 1`, close it with `C-x 0`, and switch between buffers with `C-x o`. If you close it, you can reopen it with `C-x b` by switching to the *Appine Window* buffer. You can also scroll through the embedded Appine Window using `C-n`, `C-p`, `C-v`, `M-v`, `M-<`, and `M->`, just as you would in an Emacs buffer.
- **Native Web Browsing**: Embed a fully functional Safari-like WebKit view inside an Emacs window, with full support for cookies.
- **Native PDF Rendering**: View PDFs with macOS's built-in PDFKit for buttery-smooth scrolling and zooming, and easily copy content from it to other Emacs buffers.
- **Native Word/Excel Rendering**: View Word/Excel files with macOS's built-in Quartz for buttery-smooth scrolling and zooming. Unfortunately, you cannot edit them yet.
- **Seamless Integration**: The native views automatically resize and move when you split or adjust Emacs windows.
- **Tab Management**: Support for multiple embedded tabs, switching, and closing directly from Emacs.
- **Org-mode Integration**: Use Appine to open links and files within Org files.


## 📖 Usage

### Open Appine

Run `M-x appine` to open the Appine Window. If you open it for the first time, the Appine Window will show **a brief usage**.

You can close it with `M-x appine-close` or simply `C-x 0`. If you want to open the Appine window again, run `M-x appine` or just open the \*Appine Window\* buffer.

You can kill the Appine window completely with `M-x appine-kill`.

### Two States of Embedded Apps

The embedded App has two states: Active and Inactive.
- **Active State**: When the \*Appine Window\* buffer is active, it can be used just like a native Mac App. 
- **Inactive State**: When the \*Appine Window\* buffer is not active, the embedded App is locked, grayed out, and cannot be interacted with. You can use Emacs normally at this time. 

A video demonstrating the two states.

https://github.com/user-attachments/assets/a7eaf65a-da9b-45ee-9b24-ca835379fc34

### Open a Web Page

Run `M-x appine-open-url`. You will be prompted to enter a URL. A native WebKit view will open in the current Emacs window. A demonstration video is as follows:

A video demonstrating Open Web Page.

https://github.com/user-attachments/assets/f63eff4e-754e-4d4f-b11c-aa9d3f982c67

### Opening PDFs and Other Documents

Run `M-x appine-open-file`. If you select a PDF file, it will be rendered using macOS PDFKit. Other files will be previewed using Quick Look.

When you forced on the Appine window, you can typing `C-x C-f` to open file in the macOS file chooser. 

A video demonstrating Open PDF.

https://github.com/user-attachments/assets/f2dd6c5a-eabb-421b-8d2c-986540f230f6

### Org-mode Integration

Setting `(setq appine-use-for-org-links t)` enables opening URLs and files with Appine. You can toggle this feature on or off by running `M-x appine-toggle-open-in-org-mode`.

TODO: Add a video demonstrating Org-mode integration.

### Toolbar

The Toolbar implements common App operations such as New Tab, Open File, etc., and also includes editing operations like Cut/Copy/Paste. 
Since Appine introduces the macOS Quick Look Preview module, most common files can be previewed. You can open files through the Open File button in the Appine window.

Copy/Paste video

https://github.com/user-attachments/assets/fd33d767-37dd-4027-adae-823b32228c7e

### Window Management

The native view is tied to an Emacs buffer (named `*Appine-Window*`). You can split windows (`C-x 3`, `C-x 2`), resize them, or switch buffers. The native view will automatically track the Emacs window's geometry.

## 📦 Requirements

- **macOS** (Tested on macOS 12+)
- **Emacs 29.1 or higher** compiled with Dynamic Module support (`--with-modules`). You can use `M-: (functionp 'module-load)` to check if the `module-load` function is available.
  *(Note: Most popular distributions like Emacs Plus, Emacs Mac Port, and emacsformacosx have this enabled by default).*

## 🚀 Installation

### Method 1: Pre-built Binary (Recommended)

The easiest way to install Appine is using `use-package` with `straight.el` or `quelpa`. The package will **automatically download** the pre-compiled native binary (`.dylib`) for your Mac (supports both Apple Silicon and Intel) on the first run.

```elisp
(use-package appine
  :straight (appine :type git :host github :repo "chaoswork/appine")
  :defer t  
  :custom
  ;; enables opening URLs and files with Appine, default is nil
  (appine-use-for-org-links t)
  ;; bind any prefix you like
  :bind (("C-x a a" . appine)
         ("C-x a u" . appine-open-url)
         ("C-x a o" . appine-open-file)))
```

### Method 2: Build from Source

If you prefer to build the module yourself, you need the Xcode Command Line Tools (`xcode-select --install`).

1. Clone the repository:
   ```bash
   git clone https://github.com/chaoswork/appine.git ~/.emacs.d/lisp/appine
   ```
2. Compile the C/Objective-C module:
   ```bash
   cd ~/.emacs.d/lisp/appine
   make
   ```
3. Add to your `init.el`:
   ```elisp
   (add-to-list 'load-path "~/.emacs.d/lisp/appine")
   (require 'appine)
   (setq appine-use-for-org-links t)
   (global-set-key (kbd "C-x a a") 'appine)
   (global-set-key (kbd "C-x a u") 'appine-open-url)
   (global-set-key (kbd "C-x a o") 'appine-open-file))
   ```

## 🛠️ Continuous Improvement

Appine uses Emacs Dynamic Modules to bridge C/Objective-C and Emacs Lisp. 

The project is still under continuous improvement. If you encounter any problems, feel free to open an issue.

Support for Windows and Linux systems will be considered in the future. The main reason is that I currently don't have a Windows computer, and the Linux distribution I use doesn't have a GUI, which makes it impossible for me to debug the plugin at present. Moreover, unlike macOS, Windows and Linux lack native system-level rendering frameworks for web pages, PDFs, and Office files, requiring third-party libraries to implement, which often introduces instability. Cross-platform libraries like Qt are often too massive and too heavy for a small Emacs plugin. If you use Linux or Windows and really want to use browsers, PDFs, and other apps in Emacs, you can try the [EAF](https://github.com/emacs-eaf/emacs-application-framework) project.

## 📄 License

This project is licensed under the GNU General Public License v3.0 (GPLv3) - see the [LICENSE](LICENSE) file for details.