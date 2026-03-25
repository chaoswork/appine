# Welcome to Appine

**Appine** (App in Emacs) allows you to embed native macOS views directly inside Emacs windows.

When Appine starts, it opens an embedded Appine Window tied to an \*Appine Window\* buffer. You can maximize it with `C-x 1`, close it with `C-x 0`, switch between buffers with `C-x o`. If you close it, you can reopen it with `C-x b` by switching to the \*Appine Window\* buffer. You can also scroll through the embedded Appine Window using `C-n`, `C-p`, `C-v`, `M-v`, `M-<`, and `M->`, just as you would in an Emacs buffer.

## Commands (M-x)

- `appine`: Open Appine Window and show the usage.
- `appine-open-url`: Open a URL in a new web tab.
- `appine-open-file`: Open a local file (PDF, Word, etc.) in a new tab.
- `appine-next-tab` / `appine-prev-tab`: Switch between tabs.
- `appine-close-tab`: Close the current tab.
- `appine-close`: Close Appine. This only closes the embedded view; the \*Appine Buffer\* remains in the background. You can reopen the \*Appine Buffer\* at any time to restore the view.
- `appine-kill`: kill the Appine window completely.

## Shortcuts (When Focused)

Although there is a toolbar at the top, most common operations support both macOS and Emacs keybindings as much as possible. Currently supported shortcuts include:

- Open File: `C-x C-f` or `Cmd + o`
- New Tab: `Cmd + t`
- Close Tab: `Cmd + w`
- Next Tab: `C-c f`
- Previous Tab: `C-c b`
- Forward Web Page: `C-c C-f`
- Backward Web Page: `C-c C-b`
- Reload Web Page: `Cmd + r`
- Copy: `M-w` or `Cmd + c`
- Cut: `C-w` or `Cmd + x`
- Paste: `C-y` or `Cmd + v`
- Undo: `C-/` or `Cmd + z`

## Web Browser Plugins

### Link Hints

To quickly open links on web pages, I wrote a simple link-hints plugin for Appine\'s built-in browser. It works similarly to Vimium - pressing `f` will highlight the links on the page, and then pressing the corresponding key will quickly open the link on the current page, or pressing `q` to quit the link hints, as shown below:

<img width="512" alt="Image" src="https://github.com/user-attachments/assets/2e86d223-0d5f-47a3-9e90-b3d3afa36c78" />

## Something More

When the focus is on \*Appine Window\*, the \*Appine Window\* is active, and you can use it just like a native macOS app.

When the focus is not on \*Appine Window\*, the \*Appine Window\* becomes inactive. In this state, it will be dimmed and locked.

Enjoy the full power of native macOS rendering without leaving Emacs!