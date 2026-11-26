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
 * Peek — universal preview for the current PRIMARY/clipboard selection.
 *
 * Trigger with the compositor global shortcut "peek" (Alt+Space in the
 * theme's keybind snippet), or from a script:
 *   qs ipc call peek toggle
 *   qs ipc call peek openPath /path/to/file
 *   qs ipc call peek openText "some selected text"
 *   qs ipc call peek edit
 *
 * Images are shown as frameless previews; `e` opens them in swappy via
 * peek-image.sh. Selected file paths open in nvim via peek-edit.sh. Plain
 * selected text has no preview and is skipped.
 */
Singleton {
    id: root

    property bool open: false
    property string kind: "empty" // image | text | binary | notfound | empty
    property string sourcePath: ""
    property string displayLabel: ""
    property string content: ""
    property bool fitMode: true
    property real zoom: 1.0
    property string actionMessage: ""

    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/peek`)
    readonly property string detectScript: Quickshell.shellPath("features/peek/peek-detect.sh")
    readonly property string editScript: Quickshell.shellPath("features/peek/peek-edit.sh")
    readonly property string imageScript: Quickshell.shellPath("features/peek/peek-image.sh")
    readonly property string copyScript: Quickshell.shellPath("features/peek/peek-copy.sh")

    Timer {
        id: actionMessageTimer
        interval: 2000
        onTriggered: root.actionMessage = ""
    }
    readonly property int maxPreviewBytes: Config.options?.peek?.maxPreviewBytes ?? 262144

    signal opened()
    signal closed()

    // Serialized shell jobs, mirroring ImagePreview.qml.
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
        if (root.open || GlobalStates.peekOpen) root.close();
        else root.detect();
    }

    function close(): void {
        if (!root.open && !GlobalStates.peekOpen) return;
        root.open = false;
        GlobalStates.peekOpen = false;
        root.fitMode = true;
        root.zoom = 1.0;
        root.actionMessage = "";
        root.closed();
    }

    function _show(nextKind: string, path: string, label: string, text: string): void {
        root.kind = nextKind;
        root.sourcePath = path;
        root.displayLabel = label;
        root.content = text ?? "";
        root.fitMode = true;
        root.zoom = 1.0;
        root.open = true;
        GlobalStates.peekOpen = true;
        root.opened();
    }

    function _showEmpty(): void {
        root._show("empty", "", "Nothing selected", "");
    }

    // ----- target resolution ---------------------------------------------------

    function detect(): void {
        const command = `mkdir -p ${root._shellQuote(root.cacheDir)} && PEEK_CACHE_DIR=${root._shellQuote(root.cacheDir)} bash ${root._shellQuote(root.detectScript)}`;
        root._run(command, (result, code) => {
            const fields = String(result).split("\n")[0].split("\t");
            if (code !== 0 || fields.length < 3 || fields[0] !== "path") {
                root._showEmpty();
                return;
            }
            if (fields[2] === "Selected text" || fields[2] === "Clipboard text") {
                // Plain text is not a preview target: file paths go to nvim,
                // images to swappy, and raw text has nothing to show.
                root.close();
                return;
            }
            const autoEdit = true;
            root.openPath(fields[1], fields[2], autoEdit);
        });
    }

    function openPath(path: string, label: string, autoEdit: bool): void {
        const clean = FileUtils.trimFileProtocol(String(path));
        const name = label || clean.split("/").pop();
        const command = `test -f ${root._shellQuote(clean)} && test -r ${root._shellQuote(clean)} && file --mime-type -b -- ${root._shellQuote(clean)}`;
        root._run(command, (result, code) => {
            if (code !== 0) {
                root._show("notfound", clean, "File not found: " + name, "");
                return;
            }
            const mime = String(result).split("\n")[0].trim();
            if (mime.indexOf("image/") === 0) {
                if (autoEdit) { root._openInViewer(clean, name); return; }
                // Explicit IPC requests keep the frameless 75% preview.
                root._show("image", clean, name, "");
                return;
            }
            // A path selected in a file manager, terminal or IDE opens in nvim
            // when editable; detected images go straight to swappy.
            if (autoEdit) {
                root._openInEditor(clean, name);
                return;
            }
            const textish = mime.indexOf("text/") === 0
                || mime === "application/json"
                || mime === "application/xml"
                || mime === "application/x-shellscript";
            if (mime === "application/octet-stream" || !textish) {
                root._show("binary", clean, name, "");
                return;
            }
            const read = `head -c ${root.maxPreviewBytes} -- ${root._shellQuote(clean)}`;
            root._run(read, (text, readCode) => {
                root._show("text", clean, name, readCode === 0 ? text : "");
            });
        });
    }

    function openText(text: string, label: string): void {
        const scratch = `${root.cacheDir}/selection-${Math.floor(Date.now() / 1000)}.txt`;
        const command = `mkdir -p ${root._shellQuote(root.cacheDir)} && printf '%s' ${root._shellQuote(String(text))} > ${root._shellQuote(scratch)} && echo ok`;
        root._run(command, (result, code) => {
            if (code !== 0 || String(result).trim() !== "ok") {
                root._showEmpty();
                return;
            }
            root.openPath(scratch, label || "Selected text", false);
        });
    }

    function _openInEditor(path: string, label: string): void {
        root.sourcePath = path;
        root.displayLabel = label;
        root._run(`${root._shellQuote(root.editScript)} ${root._shellQuote(path)}`, (result, code) => {
            if (code !== 0) {
                const lines = String(result).split("\n").map(line => line.trim()).filter(Boolean);
                const message = lines.length > 0 ? lines[lines.length - 1] : "unknown error";
                root._show("notfound", path, "Could not open editor: " + message, "");
                return;
            }
            root.close();
        });
    }

    function _openInViewer(path: string, label: string): void {
        root.sourcePath = path;
        root.displayLabel = label;
        root._run(`${root._shellQuote(root.imageScript)} ${root._shellQuote(path)}`, (result, code) => {
            if (code !== 0) {
                const lines = String(result).split("\n").map(line => line.trim()).filter(Boolean);
                const message = lines.length > 0 ? lines[lines.length - 1] : "unknown error";
                root._show("notfound", path, "Could not open image viewer: " + message, "");
                return;
            }
            root.close();
        });
    }

    function edit(): void {
        if (root.kind === "empty" || root.sourcePath === "") return;
        if (root.kind === "image") {
            root._openInViewer(root.sourcePath, root.displayLabel);
            return;
        }
        root._openInEditor(root.sourcePath, root.displayLabel);
    }

    function _flash(message: string): void {
        root.actionMessage = message;
        actionMessageTimer.restart();
    }

    function _copyError(result: string, fallback: string): string {
        const lines = String(result).split("\n").map(line => line.trim()).filter(Boolean);
        return lines.length > 0 ? lines[lines.length - 1] : fallback;
    }

    function copyImage(): void {
        if (root.kind !== "image" || root.sourcePath === "") return;
        root._run(`${root._shellQuote(root.copyScript)} image ${root._shellQuote(root.sourcePath)}`, (result, code) => {
            if (code !== 0) {
                root._flash("Copy failed: " + root._copyError(result, "unknown error"));
                return;
            }
            root._flash("Image copied");
        });
    }

    function copyPath(): void {
        if (root.sourcePath === "") return;
        root._run(`${root._shellQuote(root.copyScript)} path ${root._shellQuote(root.sourcePath)}`, (result, code) => {
            if (code !== 0) {
                root._flash("Copy failed: " + root._copyError(result, "unknown error"));
                return;
            }
            root._flash("Path copied");
        });
    }

    function zoomIn(): void { fitMode = false; zoom = Math.min(zoom + 0.25, 8); }
    function zoomOut(): void { fitMode = false; zoom = Math.max(zoom - 0.25, 0.25); }
    function resetZoom(): void { fitMode = true; zoom = 1.0; }

    IpcHandler {
        target: "peek"

        function toggle(): void { root.toggle() }
        function open(): void { if (!root.open) root.detect() }
        function close(): void { root.close() }
        function openPath(path: string): void { root.openPath(path, "", false) }
        function openText(text: string): void { root.openText(text, "") }
        function edit(): void { root.edit() }
        function copyImage(): void { root.copyImage() }
        function copyPath(): void { root.copyPath() }
    }

    CompositorGlobalShortcut {
        name: "peek"
        description: "Peek — preview the selected file, image or text"
        onPressed: root.toggle()
    }
}
