pragma Singleton

import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/*
 * Control surface for the mpvpaper live wallpaper.
 *
 * switchwall.sh gives every output an mpv IPC socket, so the wallpaper can be
 * paused and resumed instead of only being killed and relaunched. Commands go
 * to every socket at once: one wallpaper, however many screens.
 *
 * mpvpaper also pauses on its own when the wallpaper is hidden (its -p flag).
 * That one is invisible from here and does not change `paused`, which tracks
 * what was asked for, not what mpv is doing behind a maximised window.
 */
Singleton {
    id: root

    readonly property string socketPrefix:
        `${Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"}/mpvpaper-`

    // A live wallpaper is running and reachable
    property bool available: false
    // What we last asked for
    property bool paused: false

    readonly property bool pauseOnBattery: Config.options?.background.liveWallpaper.pauseOnBattery ?? false
    readonly property real pauseBelowPercent: Config.options?.background.liveWallpaper.pauseBelowPercent ?? 0

    // ── Socket IO ──────────────────────────────────────────────────────────
    // python3 instead of socat: socat is not installed here, and the old
    // socat commands failed silently (>/dev/null), which left the player
    // unreachable — `available` never became true. One script, two modes:
    // send (fire and forget) and query (print the reply).
    readonly property string pySend: `import socket, sys
sk = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sk.settimeout(2)
sk.connect(sys.argv[1])
sk.sendall((sys.argv[2] + chr(10)).encode())
sk.close()`
    readonly property string pyQuery: `import socket, sys
sk = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sk.settimeout(2)
sk.connect(sys.argv[1])
sk.sendall((sys.argv[2] + chr(10)).encode())
try:
    sys.stdout.write(sk.recv(65536).decode())
except Exception:
    pass
sk.close()`

    function sendCommand(json) {
        // Deliberately not gated on `available`: the 4s poll can be stale
        // (every wallpaper apply recreates the socket), and a live preview
        // must not depend on it. Without a socket the python below simply
        // fails and the glob skips it — nothing to clean up.
        commandProc.command = ["bash", "-c",
            `for s in ${root.socketPrefix}*.sock; do [ -S "$s" ] || continue; `
            + `python3 -c '${root.pySend}' "$s" '${json}' >/dev/null 2>&1; done`];
        commandProc.running = true;
    }

    function setPaused(value) {
        root.paused = value;
        root.sendCommand(`{"command":["set_property","pause",${value}]}`);
    }

    function toggle() { root.setPaused(!root.paused) }
    function pause()  { root.setPaused(true) }
    function resume() { root.setPaused(false) }

    // Re-read the player immediately. The apply path uses this so a fresh
    // mpvpaper is noticed before the regular 4 s poll runs.
    function refresh() {
        if (pollProc.running) {
            pollProc.running = false;
            Qt.callLater(() => pollProc.running = true);
        } else {
            pollProc.running = true;
        }
    }

    // ── Live preview of a video from the picker ────────────────────────────
    // The desktop shows the running wallpaper player, so previewing a video
    // means handing that player the previewed file. What was playing is
    // queried first — it may be a switchwall proxy file — so that stopping
    // the preview restores exactly that. When no player is running the
    // caller shows a generated still frame instead (Wallpapers.ensureVideoStill).

    property bool previewing: false
    property bool queryInFlight: false
    // Result of the current preview's own reachability query: true once the
    // player answered and was handed the previewed file. Background binds
    // to this instead of the 4s poll, so a stale `available` can never make
    // a preview dead or reveal an empty desktop.
    property bool previewPlayerActive: false
    property string resumePath: ""
    property string pendingPreviewPath: ""

    function sendLoadFile(path) {
        // The JSON travels inside a single-quoted shell string: escape any
        // quote a file name contains so it cannot break out of it.
        const json = JSON.stringify({command: ["loadfile", path, "replace"]}).replace(/'/g, "'\\''");
        root.sendCommand(json);
    }

    function startVideoPreview(path) {
        if (!path) return;
        if (root.queryInFlight) {
            // The player will be switched as soon as the query answers;
            // only the latest request matters.
            root.pendingPreviewPath = path;
            return;
        }
        // Every preview starts with its own query: that reply IS the
        // reachability check for this click, whatever the poll believes.
        if (!root.previewing) root.previewPlayerActive = false;
        root.previewing = true;
        root.queryInFlight = true;
        root.pendingPreviewPath = path;
        queryPlayingProc.running = false;
        queryPlayingProc.running = true;
    }

    function stopVideoPreview() {
        if (!root.previewing) return;
        root.previewing = false;
        root.pendingPreviewPath = "";
        // A proxy build for the cancelled preview must not hand its file to
        // the player afterwards; killing the process lands in onExited,
        // which the previewing guard below rejects.
        resolvePreviewProc.running = false;
        const wasActive = root.previewPlayerActive;
        root.previewPlayerActive = false;
        // Query still running: the player has not been switched yet, so
        // there is nothing to restore.
        if (root.queryInFlight) {
            root.resumePath = "";
            return;
        }
        const back = root.resumePath.length > 0
            ? root.resumePath
            : (Config.options?.background?.wallpaperPath ?? "");
        root.resumePath = "";
        if (wasActive && back.length > 0) root.sendLoadFile(back);
    }

    Process {
        id: queryPlayingProc
        // Set by the reply handler, consumed by onExited: the player is
        // only marked reachable when a valid path actually came back.
        property bool queryOk: false
        command: ["bash", "-c",
            `for s in ${root.socketPrefix}*.sock; do [ -S "$s" ] || continue; `
            + `python3 -c '${root.pyQuery}' "$s" '{"command":["get_property","path"]}' 2>/dev/null | head -1; break; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                queryPlayingProc.queryOk = false;
                if (!root.previewing) return;
                let played = "";
                try {
                    const reply = JSON.parse(text.trim());
                    if (reply.error === "success" && typeof reply.data === "string") played = reply.data;
                } catch (e) {}
                queryPlayingProc.queryOk = played.length > 0;
                root.resumePath = played.length > 0
                    ? played
                    : (Config.options?.background?.wallpaperPath ?? "");
            }
        }
        onExited: {
            root.queryInFlight = false;
            if (!root.previewing) return;
            const ok = queryPlayingProc.queryOk && root.pendingPreviewPath.length > 0;
            root.previewPlayerActive = ok;
            if (!ok) {
                root.pendingPreviewPath = "";
                return;
            }
            const p = root.pendingPreviewPath;
            root.pendingPreviewPath = "";
            resolvePreviewProc.start(p);
        }
    }

    // The picker hands the RAW file to the player: a 4K60 source saturates
    // the iGPU (98-99% gpu_busy) and freezes the compositor, so the
    // supervisor normally plays a scaled proxy. Previewing does the same —
    // build (or reuse) the proxy FIRST, with the old wallpaper still
    // playing, and only then hand the resolved file over. On failure the
    // resolver falls back to the original file itself.
    Process {
        id: resolvePreviewProc
        property string rawPath: ""
        property string resolvedPath: ""

        function start(raw) {
            resolvePreviewProc.rawPath = raw;
            resolvePreviewProc.resolvedPath = "";
            resolvePreviewProc.command = ["bash", Directories.videoWallpaperScriptPath, "--prefetch", raw];
            resolvePreviewProc.running = false;
            resolvePreviewProc.running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                resolvePreviewProc.resolvedPath = text.trim();
            }
        }
        onExited: {
            if (!root.previewing) return;
            const out = resolvePreviewProc.resolvedPath.length > 0
                ? resolvePreviewProc.resolvedPath
                : resolvePreviewProc.rawPath;
            if (out.length > 0) root.sendLoadFile(out);
        }
    }

    Process { id: commandProc }

    // Reads back the real state, so a wallpaper change or a restart does not
    // leave the button lying about what is playing.
    Process {
        id: pollProc
        running: true
        command: ["bash", "-c",
            `for s in ${root.socketPrefix}*.sock; do [ -S "$s" ] || continue; `
            + `python3 -c '${root.pyQuery}' "$s" '{"command":["get_property","pause"]}' 2>/dev/null | head -1; exit 0; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                if (line === "") {
                    root.available = false;
                    return;
                }
                try {
                    const reply = JSON.parse(line);
                    root.available = reply.error === "success";
                    if (root.available) root.paused = reply.data === true;
                } catch (e) {
                    root.available = false;
                }
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 4000
        onTriggered: pollProc.running = true
    }

    // Policies: a laptop on battery has better things to do than loop a video
    readonly property bool shouldPauseForPower: root.available
        && Battery.available && !Battery.isPluggedIn
        && (root.pauseOnBattery
            || (root.pauseBelowPercent > 0 && Battery.percentage * 100 <= root.pauseBelowPercent))

    onShouldPauseForPowerChanged: {
        if (root.shouldPauseForPower) root.pause();
        else if (root.paused) root.resume();
    }

    // Diagnostics and CLI control:
    //   qs -c end4-pC ipc call livewallpaper status
    //   qs -c end4-pC ipc call livewallpaper preview /path/to/video.mp4
    //   qs -c end4-pC ipc call livewallpaper stopPreview
    IpcHandler {
        target: "livewallpaper"

        function status(): string {
            return JSON.stringify({
                available: root.available,
                paused: root.paused,
                previewing: root.previewing,
                queryInFlight: root.queryInFlight,
                previewPlayerActive: root.previewPlayerActive,
                resumePath: root.resumePath,
                pendingPreviewPath: root.pendingPreviewPath
            });
        }

        function preview(path: string): void {
            Wallpapers.startPreview(path);
        }

        function stopPreview(): void {
            Wallpapers.stopPreview();
        }
    }
}
