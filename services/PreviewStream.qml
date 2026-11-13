pragma Singleton

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * One shared local video stream for the wallpaper picker's hovered cell.
 *
 * The picker used to create a LiveWallpaperPreview per cell. Every time the
 * grid re-created a cell (or the pointer re-entered the same one) the Python
 * frame stream was started again from frame zero, which made a hovered clip
 * look like it restarted constantly. The stream belongs to the picker, not to
 * a cell: cells only ask for their path, and the one process keeps running as
 * long as the path does not change.
 *
 * The desktop preview stays on mpvpaper (`LiveWallpaper`); this service only
 * produces the small JPEG frames shown inside the grid.
 */
Singleton {
    id: root

    readonly property string scriptPath: `${Directories.scriptPath}/wallpapers/frame_stream.py`

    property string path: ""
    readonly property bool isVideo: root.path !== "" && Images.isVideoPath(root.path)

    property string frameUrl: ""
    property bool ready: false
    property bool failed: false
    property int restarts: 0
    property bool closing: false

    // A path can change while the old process is still alive; QML's Process
    // cannot restart until it has exited. Remember the request and start it
    // from onExited instead of dropping it.
    property bool startPending: false

    // Bumped on every stop/start so an exit from the previous process cannot
    // schedule a retry that restarts the stream for the new path.
    property int generation: 0

    function request(path) {
        const next = String(path ?? "");
        // The same hovered clip must not restart. This is the fix for the
        // "starts over every second" loop: cell recreation is now harmless.
        if (next === root.path && !root.failed) return;

        root.stopStream();
        root.path = next;
        root.failed = false;
        root.restarts = 0;
        if (root.isVideo) {
            if (proc.running) root.startPending = true;
            else root.startStream();
        }
    }

    function clear() {
        root.stopStream();
        root.path = "";
        root.failed = false;
        root.restarts = 0;
    }

    function startStream() {
        if (root.closing || !root.isVideo || root.failed) return;
        if (proc.running) {
            root.startPending = true;
            return;
        }
        root.startPending = false;
        root.generation += 1;
        proc.generation = root.generation;
        proc.command = ["python3", root.scriptPath, root.path];
        proc.startedAt = Date.now();
        proc.running = true;
    }

    function stopStream() {
        retry.stop();
        root.startPending = false;
        root.generation += 1;
        if (proc.running) proc.running = false;
        root.ready = false;
        root.frameUrl = "";
    }

    Process {
        id: proc
        property real startedAt: 0
        property int generation: -1

        stdout: SplitParser {
            onRead: data => {
                // Frames from a process that is already being replaced must
                // not repopulate frameUrl for the new path.
                if (proc.generation !== root.generation) return;
                const frame = data.trim();
                if (frame.length === 0) return;
                root.restarts = 0;
                root.failed = false;
                root.frameUrl = `data:image/jpeg;base64,${frame}`;
                root.ready = true;
            }
        }

        onExited: (exitCode, exitStatus) => {
            // A new path was requested while this process was still alive:
            // start it now that the old one has actually exited.
            if (root.startPending) {
                root.startPending = false;
                if (root.isVideo && !root.closing && !root.failed) root.startStream();
                return;
            }
            if (proc.generation !== root.generation) return;
            if (root.closing) return;
            const quick = Date.now() - proc.startedAt < 2000;
            root.restarts = quick ? root.restarts + 1 : 0;
            if (root.restarts >= 3 || exitCode === 2) {
                root.failed = true;
                root.ready = false;
                return;
            }
            retry.interval = Math.min(3000, 300 * Math.pow(2, root.restarts));
            retry.restart();
        }
    }

    Timer {
        id: retry
        repeat: false
        onTriggered: root.startStream()
    }

    Component.onDestruction: {
        root.closing = true;
        root.stopStream();
    }

    // Diagnostics:
    //   qs -c end4-pC ipc call previewStream status
    IpcHandler {
        target: "previewStream"

        function status(): string {
            return JSON.stringify({
                path: root.path,
                ready: root.ready,
                failed: root.failed,
                restarts: root.restarts,
                generation: root.generation,
                frameLength: root.frameUrl.length,
                isVideo: root.isVideo,
                closing: root.closing,
                running: proc.running,
                scriptPath: root.scriptPath
            });
        }
    }
}
