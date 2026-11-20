# ADR 004: Image Preview widget

**Status**: Accepted
**Date**: 2026-11-20

## Context

Pixels need to leave the terminal sometimes: a screenshot from the clipboard,
an image linked in a Markdown document, or a file the user wants to inspect
with zoom controls. The shell had no native image viewer; the existing
terminal-only helpers (kitty `icat`, `chafa`) work well inline but cannot show
an image as a proper desktop overlay, and there was no single entry point that
works for both shell users on every machine.

## Decision

Add a first-class Image Preview pane to the QuickShell theme, following the
existing Advanced Paste architecture:

- `services/ImagePreview.qml` — a singleton owning all state and a small
  serial `Process` job queue. It reads the clipboard via `wl-paste -t
  image/png`, accepts paths via `qs ipc call imagePreview openPath <path>`, and
  falls back to a `zenity` file picker. It exposes a `CompositorGlobalShortcut`
  named `imagePreview` (bound to Super+Shift+I in the theme keybind snippet)
  and an `IpcHandler` with `toggle`, `open`, `close`, and `openPath`.
- `modules/ii/imagePreview/` — a `Scope` that loads a frameless Material 3
  window while `GlobalStates.imagePreviewOpen` is true. The window mirrors the
  Advanced Paste card styling and offers fit/zoom/close controls plus
  Escape/+/-/0 keys.
- `Config.options.imagePreview` holds `maxWidth`, `maxHeight`, and
  `filePickerCommand`. `shell.qml` calls `ImagePreview.close()` on startup so
  the singleton and its IPC/shortcut are always registered. Both panel families
  load the new scope so it works under either shell layout.
- `features/image-preview/` holds thin fish/nvim companion snippets. The
  `ishow` fish function uses kitty graphics when available and `chafa`
  otherwise; `ishow --widget <path>` forwards to the shell widget. The nvim
  snippets add `:ImagePreview`, `<leader>i`, and `<leader>I`.

The theme repository is the single source of truth: the same snippets are
installed into both users' dotfiles on each machine. No image preview logic
lives in machine-local configuration.

## Consequences

- Clipboard and file images open in a consistent themed overlay on all hosts,
  with a keyboard-only path from nvim/fish to the widget.
- The QML side depends on `wl-paste` and `zenity`; the inline side on `chafa`
  or a kitty terminal. All are already part of the desktop package set.
- Because the singleton resets `imagePreviewOpen` on load, a shell reload can
  never resurrect a stale preview window.
