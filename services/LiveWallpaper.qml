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

    // Set when a preview had to spawn the player itself because the configured
    // wallpaper is a still (there is otherwise no player to hand a clip to).
    // An apply clears it — the player becomes the wallpaper's own — while a
    // cancelled preview has to take it down again, or the clip would keep
    // playing behind a still wallpaper.
    property bool playerStartedByPreview: false
    // The clip that spawn was for. The preview may move on to another file
    // while the player is still starting, and the one that comes up would then
    // be playing the WRONG clip; this is what tells us to switch it.
    property string playerStartPath: ""

    // The CONFIGURED wallpaper, not the preview: a player is only expected to
    // be running when that one is a clip.
    function configuredIsVideo() {
        return Images.isVideoPath(String(Config.options?.background?.wallpaperPath ?? ""));
    }

    function startPlayerForPreview(path) {
        root.playerStartPath = path;
        if (root.playerStartedByPreview) return;
        root.playerStartedByPreview = true;
        Quickshell.execDetached([Directories.videoWallpaperScriptPath, path]);
        // Do not wait for the 4s wallpaper poll to notice this player: until it
        // answers, previewPlayerActive stays false, the live layer stays
        // hidden and the desktop sits on the poster — which is exactly "I
        // clicked a video and it did not play". Poll hard for the first
        // seconds instead.
        root.refresh();
        playerStartPoll.tries = 0;
        playerStartPoll.running = true;
    }

    // Follow-up polls for a player this preview just spawned.
    Timer {
        id: playerStartPoll
        interval: 400
        repeat: true
        running: false
        property int tries: 0
        onTriggered: {
            root.refresh();
            tries += 1;
            if (root.available || !root.previewing || !root.playerStartedByPreview || tries > 50) {
                running = false;
                tries = 0;
            }
        }
    }

    // Set while a preview's loadfile is on its way. previewPlayerActive is
    // only raised once a player is confirmed to have taken the file.
    property bool pendingPreviewLoad: false
    // Set when a preview is cancelled while that loadfile is still in flight,
    // so the wallpaper can be put back the moment it lands.
    property string restoreAfterCancel: ""

    function sendCommand(json) {
        // Deliberately not gated on `available`: the 4s poll can be stale
        // (every wallpaper apply recreates the socket), and a live preview
        // must not depend on it. Without a socket the python below simply
        // fails and the glob skips it — nothing to clean up.
        //
        // The exit status says whether ANY player actually took the command.
        // This used to be swallowed (>/dev/null, always exit 0), so the shell
        // believed its loadfile had landed when there was no player at all —
        // with a still wallpaper that revealed a live layer nothing was
        // rendering behind, which is the "video does not play" after setting
        // an image first.
        commandProc.command = ["bash", "-c",
            `sent=0; for s in ${root.socketPrefix}*.sock; do [ -S "$s" ] || continue; `
            + `if python3 -c '${root.pySend}' "$s" '${json}' >/dev/null 2>&1; then sent=1; fi; done; `
            + `[ "$sent" = 1 ]`];
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
    // The file the player was handed for the current preview. apply() reads
    // it to decide whether the running player can simply be kept as the
    // wallpaper instead of being rebuilt.
    property string previewPlayfile: ""
    // Bumped on every resolver start and every cancel, so a build that was
    // superseded can never hand the player a file nobody wants any more.
    property int resolveGeneration: 0

    function sendLoadFile(path) {
        root.pendingPreviewLoad = true;
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
            root.previewPlayfile = "";
            return;
        }
        // Every preview starts with its own query: that reply IS the
        // reachability check for this click, whatever the poll believes.
        if (!root.previewing) root.previewPlayerActive = false;
        root.previewing = true;
        root.previewPlayfile = "";
        root.queryInFlight = true;
        root.pendingPreviewPath = path;
        queryPlayingProc.running = false;
        queryPlayingProc.running = true;
    }

    // `restore = false` ends a preview that is being ADOPTED as the applied
    // wallpaper: the player already holds the file the apply is about to
    // record, so handing it the old one back would only undo what the user
    // just confirmed (and switchwall keeps that player in this case).
    function stopVideoPreview(restore = true) {
        if (!root.previewing) return;
        root.previewing = false;
        root.pendingPreviewPath = "";
        // Whatever the resolver was building is no longer a preview; bumping
        // the generation makes its eventual reply a no-op.
        root.resolveGeneration += 1;
        if (restore) {
            // Cancelled: stop the work, it would only burn CPU for a clip the
            // user walked away from.
            resolvePreviewProc.running = false;
            // This preview had to spawn the player itself (the wallpaper is a
            // still): nothing else will take it down, and leaving it would
            // keep a clip running behind a still wallpaper.
            if (root.playerStartedByPreview) {
                root.playerStartedByPreview = false;
                Quickshell.execDetached([Directories.videoWallpaperScriptPath, "--stop"]);
            }
        } else {
            // Adopted by an apply: the player now belongs to the wallpaper.
            root.playerStartedByPreview = false;
        }
        // Adopted (restore = false): the build is deliberately left running —
        // it warms the proxy cache that the apply starting right now needs, so
        // the apply reuses that encode instead of encoding the same clip a
        // second time while the machine is already busy.
        const wasActive = root.previewPlayerActive && restore;
        root.previewPlayerActive = false;
        root.previewPlayfile = "";
        // Query still running: the player has not been switched yet, so
        // there is nothing to restore. An adopted preview has nothing to
        // restore either — the player is about to become the wallpaper.
        if (root.queryInFlight || !restore) {
            root.resumePath = "";
            // Adopted: nothing is owed back — the apply that adopted this
            // preview is about to become the wallpaper.
            if (!restore) root.restoreAfterCancel = "";
            return;
        }
        const back = root.resumePath.length > 0
            ? root.resumePath
            : (Config.options?.background?.wallpaperPath ?? "");
        root.resumePath = "";
        if (root.pendingPreviewLoad && back.length > 0) {
            // The preview's loadfile is still in flight: sending the restore
            // now would race it and lose, leaving the player on the cancelled
            // clip. Queue it for the moment that load lands.
            root.restoreAfterCancel = back;
        } else if (wasActive && back.length > 0) {
            root.sendLoadFile(back);
        }
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
            const p = root.pendingPreviewPath;
            root.pendingPreviewPath = "";
            if (p.length === 0) return;
            if (queryPlayingProc.queryOk) {
                resolvePreviewProc.start(p);
                return;
            }
            // No player answered. That is normal when the configured wallpaper
            // is a still — and it is exactly why a click on a clip only showed
            // a frozen poster as soon as an image was the wallpaper, while a
            // video wallpaper played it instantly. Start the player the preview
            // needs; the apply that follows adopts it instead of rebuilding it
            // (and switchwall keeps it, player_plays confirms the file).
            if (!root.configuredIsVideo()) root.startPlayerForPreview(p);
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
        // Which resolver run this is, against root.resolveGeneration: a build
        // that was superseded or cancelled must never hand its file over.
        property int generation: -1

        function start(raw) {
            resolvePreviewProc.rawPath = raw;
            resolvePreviewProc.resolvedPath = "";
            root.resolveGeneration += 1;
            resolvePreviewProc.generation = root.resolveGeneration;
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
            if (resolvePreviewProc.generation !== root.resolveGeneration) return;
            if (!root.previewing) return;
            // Only the resolver's own answer is ever handed to the player.
            // Falling back to the raw source when the build produced nothing
            // gave mpv the original 3840x2160 60 fps clip (it is in the
            // player log) and froze the compositor. With no answer the desktop
            // keeps showing the generated still instead — a frozen frame beats
            // a frozen machine.
            const out = resolvePreviewProc.resolvedPath;
            if (out.length === 0) return;
            root.previewPlayfile = out;
            // The player may already be on this exact file — previewing the
            // wallpaper that is applied, or previewing it a second time.
            // Loading it again would restart the clip from frame zero for
            // nothing, which reads as the wallpaper "reloading".
            if (root.resumePath === out) {
                root.previewPlayerActive = true;
                return;
            }
            root.sendLoadFile(out);
            // previewPlayerActive is raised by commandProc once a player
            // confirms it took the file — until then the desktop keeps the
            // generated still of the CLIP BEING PREVIEWED, which is the right
            // picture both while the proxy is still being built and when
            // there is no player to reveal at all.
        }
    }

    Process {
        id: commandProc
        // A preview's loadfile just came back. Claim the player only if one
        // really took it: with no player running (a still wallpaper) the
        // desktop must keep showing the generated still rather than reveal a
        // live layer that nothing is rendering behind — that is what made a
        // video look like it never started after setting an image first.
        onExited: (exitCode, exitStatus) => {
            if (!root.pendingPreviewLoad) return;
            root.pendingPreviewLoad = false;
            if (exitCode !== 0) return; // no player took it
            if (root.previewing) {
                root.previewPlayerActive = true;
            } else if (root.restoreAfterCancel.length > 0) {
                // The preview was cancelled while the switch was still in
                // flight, so nobody had restored the wallpaper yet.
                const back = root.restoreAfterCancel;
                root.restoreAfterCancel = "";
                Qt.callLater(() => root.sendCommand(
                    JSON.stringify({command: ["loadfile", back, "replace"]})));
            }
        }
    }

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
                    if (root.available) {
                        root.paused = reply.data === true;
                        // A player this preview started has come up. It was
                        // started on the previewed clip, so the preview owns
                        // it and the live layer may be revealed — otherwise
                        // the desktop would sit on the poster forever.
                        if (root.previewing && root.playerStartedByPreview
                            && !root.previewPlayerActive) {
                            root.previewPlayerActive = true;
                            // The preview moved on while that player was
                            // starting: hand it the clip under the preview NOW
                            // instead of leaving the old one running.
                            if (root.previewPlayfile.length > 0
                                && root.playerStartPath !== root.previewPath)
                                root.sendLoadFile(root.previewPlayfile);
                        }
                    }
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
                previewPlayfile: root.previewPlayfile,
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
