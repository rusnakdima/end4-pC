pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Image Preview — shell-level viewer for images from a file or the clipboard.
 *
 * Opens a frameless Material 3 panel with the image and fit/zoom controls.
 * Trigger with the compositor global shortcut "imagePreview" (Super+Shift+I
 * in the theme's keybind snippet), or from a script:
 *   qs ipc call imagePreview toggle
 *   qs ipc call imagePreview openPath /path/to/image.png
 *
 * Companion fish/nvim snippets live in features/image-preview/.
 */
Singleton {
    id: root

    property bool open: false
    property string imagePath: ""
    property string sourceLabel: ""
    property bool fitMode: true
    property real zoom: 1.0

    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/image-preview`)
    readonly property string clipboardImagePath: `${cacheDir}/clipboard.png`
    readonly property string filePickerCommand: Config.options?.imagePreview?.filePickerCommand
        ?? "zenity --file-selection --title='Select an image' --file-filter='Images | *.png *.jpg *.jpeg *.gif *.bmp *.webp *.tiff'"

    signal opened()
    signal closed()

    // Generic shell-job runner, mirrors the AdvancedPaste singleton.
    property var jobQueue: []
    property bool jobRunning: false

    function _run(commandLine, callback) {
        root.jobQueue.push({ command: commandLine, callback: callback });
        root._pump();
    }

    function _pump() {
        if (root.jobRunning || root.jobQueue.length === 0) return;
        const job = root.jobQueue.shift();
        root.jobRunning = true;
        runner.resultText = "";
        runner.callback = job.callback;
        runner.command = ["bash", "-c", job.command];
        runner.running = true;
    }

    Process {
        id: runner
        property string resultText: ""
        property var callback: null
        stdout: SplitParser {
            onRead: (line) => { runner.resultText += line + "\n"; }
        }
        onExited: (exitCode) => {
            const cb = runner.callback;
            const result = runner.resultText.replace(/\n$/, "");
            runner.callback = null;
            root.jobRunning = false;
            if (cb) cb(result, exitCode);
            root._pump();
        }
    }

    function _shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    // ----- lifecycle -----------------------------------------------------------

    function toggle(): void {
        if (root.open || GlobalStates.imagePreviewOpen) root.close();
        else root.openFromClipboard();
    }

    function close(): void {
        if (!root.open && !GlobalStates.imagePreviewOpen) return;
        root.open = false;
        GlobalStates.imagePreviewOpen = false;
        zoom = 1.0;
        root.closed();
    }

    function _show(path, label): void {
        root.imagePath = path;
        root.sourceLabel = label;
        root.fitMode = true;
        zoom = 1.0;
        root.open = true;
        GlobalStates.imagePreviewOpen = true;
        root.opened();
    }

    function openPath(path: string): void {
        const clean = FileUtils.trimFileProtocol(String(path));
        root._run(`test -f ${root._shellQuote(clean)} && echo yes`, (result, code) => {
            if (code !== 0 || result.trim() !== "yes") {
                root.sourceLabel = "File not found: " + clean;
                return;
            }
            root._show(clean, clean.split("/").pop());
        });
    }

    function openFromClipboard(): void {
        root._run(`mkdir -p ${root._shellQuote(root.cacheDir)} && wl-paste -t image/png 2>/dev/null > ${root._shellQuote(root.clipboardImagePath)} && echo image`, (result, code) => {
            if (code === 0 && result.trim() === "image") {
                root._show(root.clipboardImagePath, "Clipboard image");
                return;
            }
            // The clipboard may hold a path to an image instead.
            root._run("wl-paste -n 2>/dev/null | head -n 1", (text, tcode) => {
                const candidate = FileUtils.trimFileProtocol(String(text).trim());
                if (tcode === 0 && candidate.indexOf("/") === 0) root.openPath(candidate);
                else root.pickFile();
            });
        });
    }

    function pickFile(): void {
        root._run(`${root.filePickerCommand} 2>/dev/null`, (result, code) => {
            if (code === 0 && String(result).trim().length > 0) root.openPath(String(result).trim());
            else root.close();
        });
    }

    function zoomIn(): void { fitMode = false; zoom = Math.min(zoom + 0.25, 8); }
    function zoomOut(): void { fitMode = false; zoom = Math.max(zoom - 0.25, 0.25); }
    function resetZoom(): void { fitMode = true; zoom = 1.0; }

    IpcHandler {
        target: "imagePreview"

        function toggle(): void { root.toggle() }
        function open(): void { if (!root.open) root.openFromClipboard() }
        function close(): void { root.close() }
        function openPath(path: string): void { root.openPath(path) }
    }

    CompositorGlobalShortcut {
        name: "imagePreview"
        description: "Image Preview — view an image from a file or the clipboard"
        onPressed: root.toggle()
    }
}
