pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Owns the tiling/stacking window mode of the session.
 *
 * Stacking floats every window so they overlap like a classic stacking
 * window manager, tiling keeps the dwindle/master/scrolling layout. An app
 * rule can put one app on the other side of that choice, and a rule with
 * mode "span" floats the app over the bounding box of every enabled monitor
 * (a remote desktop that shows all its monitors at once, for example).
 *
 * A span rule is a float rule plus the window geometry: the rule sizes the
 * window so it opens covering the whole layout, and the resize/move
 * dispatchers put it at the bounding box origin once it is open. Hyprland
 * does not apply rule changes to open windows, so the geometry is also
 * re-applied whenever the monitors change, the rules change, a window opens
 * or the safety timer fires. Fullscreen requests of a span window are
 * suppressed: fullscreen cannot cover more than one monitor, and covering
 * the whole layout is already the point of the rule.
 *
 * The switch has two halves, because the compositor only applies a window rule
 * when a window is created:
 *
 *   * ~/.config/hypr/hyprland/shellOverrides/windowMode.lua holds the rules
 *     for the windows that open from now on. It is required from
 *     hyprland.lua after every other rules file, so a rule written here
 *     wins over the static ones, and it is rewritten and reloaded whenever
 *     the mode or the app rules change.
 *
 *   * the windows that are already open are pushed onto the other side one
 *     by one with the float dispatcher, because a reload leaves them alone.
 *
 * A window this service floated is remembered in Persistent, so the mode
 * can tile it back later. A window that floats because of its own rule (a
 * file dialog, pavucontrol) is never in that list and is never touched:
 * those apps belong in the app rules if they should follow the mode.
 */
Singleton {
    id: root

    // Niri and sway have no floating windows to switch to, so the whole
    // service stands down outside Hyprland.
    readonly property bool supported: WM.compositor === "hyprland"

    readonly property string mode: {
        if (!Config.ready) return "tiling";
        return Config.options?.hyprland?.windowMode?.mode === "stacking" ? "stacking" : "tiling";
    }
    readonly property bool stacking: root.mode === "stacking"
    readonly property var appRules: Config.ready ? (Config.options?.hyprland?.windowMode?.appRules ?? []) : []

    // Every enabled screen, in layout coordinates. The span rules of the
    // window mode stretch a window over this rectangle.
    readonly property var spanRect: root.spanRectFor(Quickshell.screens)
    // A scalar change key: a JS object is a new object on every evaluation,
    // so binding on spanRect itself would rewrite the rules file each time
    // Quickshell re-evaluates it.
    readonly property string spanKey: root.spanRect
        ? `${root.spanRect.x},${root.spanRect.y},${root.spanRect.width},${root.spanRect.height}`
        : ""
    readonly property bool hasSpanRules: (root.appRules ?? []).some(rule => rule?.mode === "span")

    readonly property string rulesDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides`)
    readonly property string rulesPath: `${root.rulesDir}/windowMode.lua`

    // The content of the rules file as the service last saw it. The file is
    // unknown until the first read, and an unknown file is always written.
    property bool rulesKnown: false
    property string rulesContent: ""

    // A write is in flight: it owns the file until it is done, and the
    // reload of the compositor is owed to it.
    property bool pendingWrite: false
    property bool pendingReload: false
    property string generatedContent: ""
    // A content that arrived while the file was being saved. Writes are
    // serialized: a second setText() while the first is in flight can land
    // out of order and leave the compositor reading the older one.
    property string queuedContent: ""

    // ------------------------------------------------------------------
    // Decision logic. Pure, so tst_window_mode.qml can assert it.
    // ------------------------------------------------------------------

    // The first rule whose class pattern matches the window, or null.
    // The pattern is a regular expression, searched like the compositor
    // searches its own rules: "firefox" matches "org.mozilla.firefox".
    function matchRule(winClass, rules) {
        for (const rule of rules ?? []) {
            const pattern = String(rule?.class ?? "");
            if (pattern.length === 0) continue;
            try {
                if (new RegExp(pattern).test(String(winClass ?? ""))) return rule;
            } catch (error) {
                console.warn("[WindowMode] invalid window class pattern:", pattern, error);
            }
        }
        return null;
    }

    // true: the window has to float. false: it has to tile. null: the mode
    // has no opinion and the window keeps what it has - a dialog that
    // floats because of its own rule, or a window the user floated by hand.
    function desiredFloat(winClass, currentMode, rules) {
        const rule = root.matchRule(winClass, rules);
        // A span window must float in both global modes: tiling a window
        // would confine it to one monitor.
        if (rule?.mode === "span") return true;
        if (currentMode === "stacking") return rule?.mode === "tiling" ? false : true;
        return rule?.mode === "stacking" ? true : null;
    }

    // The rule that stretches this window over every monitor, or null.
    function desiredSpan(winClass, rules) {
        return root.matchRule(winClass, rules)?.mode === "span";
    }

    // The bounding box of every enabled screen, in the layout coordinates
    // the compositor uses for windows. Null when no screen is known yet.
    // Mirrored outputs have the same geometry as their source, so they do
    // not widen the box; a disabled output is not in the list at all.
    function spanRectFor(screens) {
        const list = (screens ?? []).filter(screen => screen
            && Number(screen.width) > 0 && Number(screen.height) > 0);
        if (list.length === 0) return null;

        let minX = Infinity;
        let minY = Infinity;
        let maxX = -Infinity;
        let maxY = -Infinity;
        for (const screen of list) {
            minX = Math.min(minX, Number(screen.x));
            minY = Math.min(minY, Number(screen.y));
            maxX = Math.max(maxX, Number(screen.x) + Number(screen.width));
            maxY = Math.max(maxY, Number(screen.y) + Number(screen.height));
        }
        return {
            "x": Math.round(minX),
            "y": Math.round(minY),
            "width": Math.round(maxX - minX),
            "height": Math.round(maxY - minY)
        };
    }

    // The size part of a span rule. The compositor applies a rule only when
    // the window is created, so the current layout is baked into the file
    // and rewritten when the layout changes. No size until the screens are
    // known; the dispatcher path still places the window.
    function spanSizeRule(rect) {
        if (!rect || !(Number(rect.width) > 0) || !(Number(rect.height) > 0)) return "";
        return `, size = { ${Math.round(rect.width)}, ${Math.round(rect.height)} }`;
    }

    // Whether an open window already covers the rectangle. The compositor
    // can round or clamp by a pixel, and a rule that fights an app for a
    // single pixel would dispatch on every reconcile.
    function rectMatches(win, rect) {
        if (!win || !rect) return false;
        const at = win.at ?? [0, 0];
        const size = win.size ?? [0, 0];
        const tolerance = 2;
        return Math.abs(at[0] - rect.x) <= tolerance
            && Math.abs(at[1] - rect.y) <= tolerance
            && Math.abs(size[0] - rect.width) <= tolerance
            && Math.abs(size[1] - rect.height) <= tolerance;
    }

    // A window that stops being a span window must not keep the whole
    // layout as its floating size. 60% x 65% of the screen the window
    // belongs to is the size the stacking mode feels like. The client list
    // carries the compositor's monitor id; the screen list is in the same
    // order, and a wrong guess only costs a size on the other screen.
    function defaultFloatRect(win, screens) {
        const list = (screens ?? []).filter(screen => screen
            && Number(screen.width) > 0 && Number(screen.height) > 0);
        if (list.length === 0) return null;

        const at = win?.at ?? [0, 0];
        const size = win?.size ?? [0, 0];
        const centreX = at[0] + size[0] / 2;
        const centreY = at[1] + size[1] / 2;
        let screen = Number.isInteger(win?.monitor) ? list[win.monitor] : undefined;
        if (!screen) {
            screen = list.find(s => centreX >= s.x && centreX < s.x + s.width
                && centreY >= s.y && centreY < s.y + s.height);
        }
        if (!screen) screen = list[0];

        const width = Math.round(screen.width * 0.6);
        const height = Math.round(screen.height * 0.65);
        return {
            "x": Math.round(screen.x + (screen.width - width) / 2),
            "y": Math.round(screen.y + (screen.height - height) / 2),
            "width": width,
            "height": height
        };
    }

    // A class pattern is typed by the user and ends up inside a Lua string.
    function luaQuote(value) {
        return String(value)
            .replace(/\\/g, "\\\\")
            .replace(/"/g, '\\"')
            .replace(/[\r\n]/g, "");
    }

    // The whole rules file for a mode. The rules of the shell load after
    // hyprland/rules.lua, so the global float rule of the stacking mode
    // comes first and the per-app rules that contradict it come after it.
    // spanRect is the current layout bounding box: a span rule bakes the
    // size into the file so a new window opens covering everything, while
    // the position is left to the resize/move dispatchers (Hyprland's
    // "move" rule is unreliable for a window larger than one monitor).
    function rulesSource(currentMode, rules, spanRect) {
        const lines = [
            "-- Written by the shell (services/WindowMode.qml). DO NOT EDIT.",
            `-- Window mode: ${currentMode}.`,
            ""
        ];
        if (currentMode === "stacking") {
            lines.push('hl.window_rule({ match = { class = ".*" }, float = true })');
        }
        for (const rule of rules ?? []) {
            const pattern = root.luaQuote(rule?.class ?? "");
            if (pattern.length === 0) continue;
            if (rule.mode === "span") {
                lines.push(`hl.window_rule({ match = { class = "${pattern}" }, float = true${root.spanSizeRule(spanRect)}, border_size = 0, rounding = 0, opacity = "1 1", suppress_event = "fullscreen" })`);
            // A rule that only repeats what the mode already does is left
            // out: the file then says the same as the mode and nothing has
            // to be rewritten when only the mode changed.
            } else if (rule.mode === "tiling") {
                if (currentMode === "stacking") lines.push(`hl.window_rule({ match = { class = "${pattern}" }, tile = true })`);
            } else if (currentMode !== "stacking") {
                lines.push(`hl.window_rule({ match = { class = "${pattern}" }, float = true })`);
            }
        }
        return lines.join("\n") + "\n";
    }

    // ------------------------------------------------------------------
    // The public surface of the service: what the settings page calls.
    // ------------------------------------------------------------------

    function setMode(newMode) {
        if (!root.supported || !Config.ready) return;
        const value = newMode === "stacking" ? "stacking" : "tiling";
        if (Config.options.hyprland.windowMode.mode === value) return;
        Config.options.hyprland.windowMode.mode = value;
        root.apply();
    }

    function setAppRules(rules) {
        if (!root.supported || !Config.ready) return;
        Config.options.hyprland.windowMode.appRules = rules;
        root.apply();
    }

    function addAppRule(winClass, ruleMode) {
        const rules = root.appRules.slice();
        const mode = ["tiling", "stacking", "span"].includes(ruleMode) ? ruleMode : "stacking";
        rules.push({ "class": String(winClass ?? ""), "mode": mode });
        root.setAppRules(rules);
    }

    function updateAppRule(index, patch) {
        const rules = root.appRules.slice();
        if (index < 0 || index >= rules.length) return;
        rules[index] = Object.assign({}, rules[index], patch);
        root.setAppRules(rules);
    }

    function removeAppRule(index) {
        const rules = root.appRules.slice();
        if (index < 0 || index >= rules.length) return;
        rules.splice(index, 1);
        root.setAppRules(rules);
    }

    // ------------------------------------------------------------------
    // Writing the rules file and reloading the compositor.
    // ------------------------------------------------------------------

    // Coalesces the writes: a rule typed into the settings page commits on
    // every debounce tick, and every commit would otherwise rewrite the
    // file and reload the compositor.
    Timer {
        id: applyTimer
        interval: 300
        onTriggered: root.doApply()
    }

    function apply() {
        if (!root.supported || !Config.ready) return;
        applyTimer.restart();
    }

    function doApply() {
        if (!root.supported || !Config.ready) return;
        const content = root.rulesSource(root.mode, root.appRules, root.spanRect);
        if (root.rulesKnown && root.rulesContent === content) {
            // The file already says what the mode needs, so there is
            // nothing to reload. The windows still have to be brought in
            // line - the mode may have changed while the shell was down.
            root.scheduleReconcile();
            return;
        }
        root.generatedContent = content;
        root.writeRules();
    }

    FileView {
        id: rulesFile
        path: root.rulesPath
        preload: true
        watchChanges: true

        onLoaded: {
            root.rulesContent = rulesFile.text() ?? "";
            root.rulesKnown = true;
        }
        onLoadFailed: error => {
            // No file yet. That is the normal state before the first mode
            // switch, and the first write creates it.
            if (error === FileViewError.FileNotFound) {
                root.rulesContent = "";
                root.rulesKnown = true;
            }
        }
        onSaved: {
            // The file is on disk; only now does the write stop owning it.
            root.pendingWrite = false;
            if (root.pendingReload) {
                root.pendingReload = false;
                Quickshell.execDetached(["hyprctl", "reload"]);
            }
            root.scheduleReconcile();

            if (root.queuedContent !== "" && root.queuedContent !== root.rulesContent) {
                root.generatedContent = root.queuedContent;
                root.queuedContent = "";
                root.writeRules();
                return;
            }
            root.queuedContent = "";

            // A change that slipped in behind the save (or an outside edit)
            // would leave the compositor with a stale file. Compare what it
            // will read with the model and write again when they differ.
            const expected = root.rulesSource(root.mode, root.appRules, root.spanRect);
            if ((rulesFile.text() ?? "") !== expected) {
                root.generatedContent = expected;
                root.writeRules();
            }
        }
        onFileChanged: {
            // This service owns the file, so a change that is not a write
            // in flight is somebody else's edit. It is read back so the
            // next apply() sees that the file no longer matches the mode.
            if (!root.pendingWrite) {
                root.rulesContent = rulesFile.text() ?? "";
                root.rulesKnown = true;
            }
        }
    }

    // The directory is user owned and normally already there, but a fresh
    // installation has no shellOverrides directory of its own.
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.rulesDir]
        onExited: (exitCode, exitStatus) => {
            if (!root.pendingWrite) return;
            // pendingWrite stays set until onSaved: the setText() below is
            // asynchronous, and a second apply() must queue its content
            // instead of starting a competing write.
            root.writeRulesFile();
        }
    }

    function writeRules() {
        root.pendingReload = true;
        if (root.pendingWrite) {
            root.queuedContent = root.generatedContent;
            return;
        }
        root.pendingWrite = true;
        if (!mkdirProc.running) mkdirProc.running = true;
    }

    function writeRulesFile() {
        root.rulesContent = root.generatedContent;
        root.rulesKnown = true;
        rulesFile.setText(root.generatedContent);
    }

    // ------------------------------------------------------------------
    // The windows that are already open.
    // ------------------------------------------------------------------

    Timer {
        id: reconcileTimer
        interval: 350
        onTriggered: root.fetchClients()
    }

    function scheduleReconcile() {
        if (!root.supported || !Config.ready) return;
        reconcileTimer.restart();
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.reconcile(JSON.parse(text));
                } catch (error) {
                    console.error("[WindowMode] could not read the client list:", error);
                }
            }
        }
    }

    function fetchClients() {
        if (!root.supported) return;
        clientsProc.running = false;
        clientsProc.running = true;
    }

    // What has to happen to each open window, decided without touching the
    // compositor: one action per property that has to change, and the lists
    // of addresses this service owns afterwards. A window that is already in
    // the state the mode wants gets no action, so a window that floats
    // because of its own rule is never taken away from that rule, and an
    // address that no longer belongs to a live window is dropped.
    //
    // A span window gets a rect action instead of a size rule: the rule in
    // the file applies only when the window is created, and both monitors
    // and the rule list can change while it is open.
    function reconcilePlan(clients, currentMode, rules, ownedAddresses, screens, spanAddresses) {
        const alive = new Set(clients.map(client => client.address));
        const owned = new Set((ownedAddresses ?? []).filter(address => alive.has(address)));
        const spans = new Set((spanAddresses ?? []).filter(address => alive.has(address)));
        const spanRect = root.spanRectFor(screens);
        const actions = [];

        for (const win of clients) {
            const want = root.desiredFloat(win.class, currentMode, rules);
            const isOwned = owned.has(win.address);
            const isSpan = root.desiredSpan(win.class, rules);
            // A fullscreen window is on one monitor by definition. The app
            // cannot request it (the span rule suppresses that), but a
            // keybind can; resizing it back every tick would fight the user.
            const isFullscreen = Number(win.fullscreen ?? 0) !== 0;

            // Where the window ends up after the float action below: a span
            // window must float, a tiled window must not, and otherwise the
            // current state is kept unless this service tiles it back.
            let floatingAfter = win.floating;
            if (want === true) floatingAfter = true;
            else if (want === false) floatingAfter = false;
            else if (isOwned) floatingAfter = false;

            if (want === true) {
                if (!win.floating) {
                    actions.push({ "address": win.address, "floating": true });
                    owned.add(win.address);
                }
            } else if (want === false) {
                if (win.floating) actions.push({ "address": win.address, "floating": false });
                owned.delete(win.address);
            } else if (isOwned) {
                // The rules have no opinion anymore: only a window this
                // service floated goes back onto the grid.
                if (win.floating) actions.push({ "address": win.address, "floating": false });
                owned.delete(win.address);
            }

            if (isSpan) {
                if (spanRect && !isFullscreen && !root.rectMatches(win, spanRect)) {
                    actions.push({ "address": win.address, "rect": spanRect });
                }
                if (floatingAfter) spans.add(win.address);
            } else if (spans.has(win.address)) {
                // The span rule is gone. A window that still floats gets a
                // sane size back instead of keeping the whole layout; one
                // that is tiled back needs no geometry.
                if (floatingAfter) {
                    const rect = root.defaultFloatRect(win, screens);
                    if (rect) actions.push({ "address": win.address, "rect": rect });
                }
                spans.delete(win.address);
            }
        }

        return { "actions": actions, "owned": Array.from(owned), "spans": Array.from(spans) };
    }

    // Brings the open windows in line with the mode. A fresh client list
    // is read for this rather than the cached one of HyprlandData, so the
    // state a window was just floated into is not mistaken for the state
    // it had a moment ago.
    function reconcile(clients) {
        if (!root.supported || !Config.ready) return;
        const plan = root.reconcilePlan(clients, root.mode, root.appRules, root.ownedFloats(),
            Quickshell.screens, root.ownedSpans());

        for (const action of plan.actions) {
            // The float action has to happen before the geometry: a tiled
            // window does not take a floating rect.
            if (action.floating !== undefined) root.setFloat(action.address, action.floating);
            if (action.rect) root.setRect(action.address, action.rect);
        }

        const current = root.ownedFloats();
        if (plan.owned.join("\n") !== current.join("\n")) root.setOwnedFloats(plan.owned);
        const currentSpans = root.ownedSpans();
        if (plan.spans.join("\n") !== currentSpans.join("\n")) root.setOwnedSpans(plan.spans);
    }

    function setFloat(address, floating) {
        if (!address) return;
        Hyprland.dispatch(`hl.dsp.window.float({ window = "address:${address}", action = "${floating ? "set" : "unset"}" })`);
    }

    // A resize keeps the window centre, so the move has to come second. The
    // rule that creates a span window already sets the size; this puts the
    // window at the bounding box origin and brings it back when the layout
    // or the rule list changed while it was open.
    function setRect(address, rect) {
        if (!address || !rect) return;
        Hyprland.dispatch(`hl.dsp.window.resize({ window = "address:${address}", x = ${Math.round(rect.width)}, y = ${Math.round(rect.height)}, exact = true })`);
        Hyprland.dispatch(`hl.dsp.window.move({ window = "address:${address}", x = ${Math.round(rect.x)}, y = ${Math.round(rect.y)}, exact = true })`);
    }

    // The windows this service floated. They live in the persisted session
    // state so that a shell that restarts while the stacking mode is on
    // still knows which windows it may tile back later.
    function ownedFloats() {
        return Array.from(Persistent.states.windowMode.ownedFloats ?? []);
    }

    function setOwnedFloats(list) {
        Persistent.states.windowMode.ownedFloats = list;
    }

    function rememberFloating(address) {
        if (!address) return;
        const owned = root.ownedFloats();
        if (owned.includes(address)) return;
        owned.push(address);
        root.setOwnedFloats(owned);
    }

    function forgetFloating(address) {
        if (!address) return;
        const owned = root.ownedFloats();
        if (!owned.includes(address)) return;
        root.setOwnedFloats(owned.filter(entry => entry !== address));
    }

    // The windows this service stretched over every monitor. Kept apart
    // from the float list so the service can give a window its normal size
    // back when the span rule goes away, even when the window floats
    // because of its own rule.
    function ownedSpans() {
        return Array.from(Persistent.states.windowMode.ownedSpans ?? []);
    }

    function setOwnedSpans(list) {
        Persistent.states.windowMode.ownedSpans = list;
    }

    function rememberSpan(address) {
        if (!address) return;
        const owned = root.ownedSpans();
        if (owned.includes(address)) return;
        owned.push(address);
        root.setOwnedSpans(owned);
    }

    function forgetSpan(address) {
        if (!address) return;
        const owned = root.ownedSpans();
        if (!owned.includes(address)) return;
        root.setOwnedSpans(owned.filter(entry => entry !== address));
    }

    // A window that opens while the stacking mode is on arrives floating
    // through the rules file. This is the belt to that pair of braces: a
    // window that arrived tiled anyway is floated right away instead of
    // waiting for the next reconcile, and it is remembered as ours.
    //
    // A span window gets its geometry here as well. The rule sized it, but
    // the "move" rule is not reliable for a window larger than a monitor,
    // so the dispatcher puts it at the bounding box origin. This runs in
    // tiling mode too: a span app is the one exception that must float
    // there.
    function onWindowOpened(data) {
        if (!Config.ready) return;
        const parts = String(data ?? "").split(",");
        if (parts.length < 3) return;
        const address = parts[0].trim();
        const winClass = parts[2];
        const span = root.desiredSpan(winClass, root.appRules);
        const want = root.desiredFloat(winClass, root.mode, root.appRules);
        // The stacking mode already floats every window through the rule;
        // a non-span window in tiling mode keeps the old path (the rule
        // floats an always-stacking app, and reconcile catches a miss).
        if (!root.stacking && !span) return;
        if (want !== true) return;
        root.setFloat(address, true);
        root.rememberFloating(address);
        if (span) {
            const rect = root.spanRectFor(Quickshell.screens);
            if (rect) root.setRect(address, rect);
            root.rememberSpan(address);
        }
        root.scheduleReconcile();
    }

    Connections {
        target: Hyprland
        enabled: root.supported

        function onRawEvent(event) {
            if (event.name === "openwindow") {
                root.onWindowOpened(event.data);
            } else if (event.name === "closewindow") {
                // "closewindow" carries the address of the window alone.
                const address = String(event.data ?? "").split(",")[0].trim();
                root.forgetFloating(address);
                root.forgetSpan(address);
            }
        }
    }

    // The layout changed (a monitor plugged, unplugged, resized or moved).
    // The span size baked into the rules file is stale now, and the open
    // span windows have to follow the new bounding box.
    Connections {
        target: HyprlandData
        enabled: root.supported

        function onMonitorsChanged() {
            root.apply();
            root.scheduleReconcile();
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.apply();
        }
    }

    // A span window is a standing promise: the app may resize itself (a
    // remote desktop negotiates its resolution when it connects), and
    // Hyprland has no raw event for a plain resize. This only runs while a
    // span rule exists, and rectMatches keeps it from dispatching twice.
    Timer {
        id: spanReconcileTimer
        interval: 2000
        repeat: true
        running: root.supported && Config.ready && root.hasSpanRules
        onTriggered: root.scheduleReconcile()
    }

    // The mode from the outside: a keybind, a script or a test flips it
    // the same way the settings page does.
    IpcHandler {
        target: "windowMode"

        function setMode(mode: string): void {
            root.setMode(mode);
        }

        // Read-only state for scripts and for diagnosing a layout. The
        // settings page does not need it; a shell restart is the usual
        // moment to ask what the service believes.
        function status(): string {
            return JSON.stringify({
                "supported": root.supported,
                "mode": root.mode,
                "spanRect": root.spanRect,
                "hasSpanRules": root.hasSpanRules,
                "appRules": root.appRules,
                "ownedFloats": root.ownedFloats(),
                "ownedSpans": root.ownedSpans(),
                "rulesKnown": root.rulesKnown,
                "pendingWrite": root.pendingWrite
            });
        }

        // Force the rules file and the open windows to be brought in line
        // with the current config. Useful for scripts and after an outside
        // change that the file/monitor watchers did not see.
        function reapply(): void {
            root.apply();
            root.scheduleReconcile();
        }
    }

    // The mode and the rules can also change without this service being
    // asked: the config file is shared with everything that writes it.
    onModeChanged: root.apply()
    onAppRulesChanged: root.apply()
    // The layout changed: the size baked into the span rules is stale and
    // the open windows have to follow the new bounding box. The keys are
    // compared as scalars, so an unchanged layout does not rewrite the file.
    onSpanKeyChanged: {
        root.apply();
        root.scheduleReconcile();
    }

    Component.onCompleted: {
        if (Config.ready) root.apply();
    }
}
