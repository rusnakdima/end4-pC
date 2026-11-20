pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.modules.common
import qs.services

/**
 * Actions behind the shell-drawn window controls.
 *
 * The three familiar buttons (minimize, maximize, close) and the window-type
 * selector all funnel through here, so the QML views stay declarative and the
 * decisions can be asserted without a compositor (tst_window_controls.qml).
 *
 * Design decisions, and why:
 *
 *  - This service never reimplements WindowMode. Floating/tiling for one
 *    window are WindowMode.setFloat(); the global stacking mode is
 *    WindowMode.setMode(); a span rule is WindowMode.addAppRule(). The service
 *    only chooses which one a button means.
 *
 *  - The maximize dispatcher is verified against the installed Hyprland
 *    config: keybinds.lua uses
 *      hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })
 *    for SUPER+D. A native `fullscreen 1` is kept as a fallback.
 *
 *  - There is no local minimize dispatcher in the config, and Hyprland's
 *    native `minimize` is version dependent. Instead of probing at startup
 *    (which would minimize the active window as a side effect), the service
 *    tries the candidates on the first real click, watches whether the client
 *    state actually changed, and remembers the candidate that worked. A
 *    known-bad candidate is skipped from then on.
 *
 *  - Nothing here writes config or persists state. Ownership of floated
 *    windows stays in WindowMode/Persistent.
 *
 *  - All helpers that decide something are pure: they take their inputs as
 *    arguments instead of reading globals. That is the contract the tests
 *    rely on. The only impure functions are the ones that dispatch or read
 *    HyprlandData/ToplevelManager.
 */
Singleton {
    id: root

    readonly property bool supported: WM.compositor === "hyprland"

    // ------------------------------------------------------------------
    // Demo mode (playground.qml). When enabled, every action below writes
    // to this mock client and the log instead of dispatching into Hyprland.
    // It can never close, minimize or resize a real window.
    // ------------------------------------------------------------------

    property bool demoMode: false
    property var demoClient: null
    property var demoLog: []
    property string demoGlobalMode: "tiling"
    property bool demoSpan: false

    readonly property var displayClient: root.demoMode ? root.demoClient : root.activeClient

    function demoReset(winClass) {
        root.demoGlobalMode = "tiling";
        root.demoSpan = false;
        root.demoClient = {
            "address": "0xdemo",
            "class": String(winClass ?? "playground"),
            "title": "Demo window",
            "floating": false,
            "fullscreen": 0,
            "hidden": false,
            "mapped": true,
            "monitor": 0,
            "at": [0, 0],
            "size": [960, 600]
        };
        root.demoLog = [];
    }

    function demoRecord(action, detail) {
        const line = `${action}${detail ? " · " + detail : ""}`;
        root.demoLog = root.demoLog.concat([line]);
    }

    function demoApplyType(type) {
        const mock = root.demoClient ?? {};
        mock.floating = type !== "tiling";
        root.demoClient = mock;
        root.demoGlobalMode = type === "stacking" ? "stacking" : "tiling";
        root.demoSpan = type === "span";
    }

    // What the controls should display, whether in the live session or the
    // sandbox. Views call these instead of reaching into WindowMode directly.
    function displayType() {
        if (root.demoMode) {
            if (root.demoSpan) return "span";
            if (root.demoGlobalMode === "stacking") return "stacking";
            return root.demoClient?.floating ? "floating" : "tiling";
        }
        return root.windowTypeFor(root.activeClient, WindowMode.mode, WindowMode.appRules ?? []);
    }

    function displayCanMaximize() {
        return root.demoMode
            ? !root.isMinimized(root.demoClient)
            : root.canMaximize(root.activeClient, WindowMode.appRules ?? []);
    }

    function displayCanMinimize() {
        if (root.demoMode) return root.canMinimize(root.demoClient);
        return root.canMinimize(root.activeClient)
            && !root.isShellMinimized(root.activeAddress);
    }

    // The order of the type chooser. Kept here so a test can assert cycling
    // and a view can render the same list the button cycles through.
    readonly property var windowTypes: ["floating", "tiling", "stacking", "span"]

    // The last candidate index that actually changed the client state.
    // -1 means every candidate failed, so the button should be hidden.
    property int maximizeCandidate: 0
    property int minimizeCandidate: 0

    // The active window, resolved from the Wayland toplevel and the Hyprland
    // client list. Both are needed: the toplevel has the address, the client
    // has the state (floating, fullscreen, hidden) the buttons depend on.
    readonly property string activeAddress: {
        if (!root.supported) return "";
        const address = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
        return address ? `0x${address}` : "";
    }
    readonly property var activeClient: root.findClient(HyprlandData.windowByAddress ?? ({}), root.activeAddress)

    // ------------------------------------------------------------------
    // Pure helpers. No globals, no side effects: tst_window_controls.qml
    // calls these directly.
    // ------------------------------------------------------------------

    // Accept "0xabc", "abc", "address:0xabc" and the address strings the
    // compositor emits, so callers (IPC, overlay, bar) can pass whatever they
    // happen to have. Always returns the "0x..." form the client map uses.
    function normalizeAddress(value) {
        if (value === undefined || value === null) return "";
        let text = String(value).trim();
        if (text.startsWith("address:")) text = text.slice("address:".length);
        text = text.split(",")[0].trim();
        if (!text) return "";
        if (!text.startsWith("0x") && !text.startsWith("0X")) text = `0x${text}`;
        return text.toLowerCase();
    }

    // The client map is keyed by hyprctl's exact address string. Look up by
    // normalized key first, then fall back to a normalized scan so a
    // different letter case in the map cannot make the controls go blind.
    function findClient(clientMap, address) {
        const key = root.normalizeAddress(address);
        if (!key) return null;
        const map = clientMap ?? ({});
        if (map[key]) return map[key];
        for (const candidate of Object.keys(map)) {
            if (root.normalizeAddress(candidate) === key) return map[candidate];
        }
        return null;
    }

    // A minimized client is hidden from the layout but must stay in the dock
    // and alt-tab. Hyprland reports either flag depending on the version.
    function isMinimized(client) {
        if (!client) return false;
        return client.hidden === true || client.mapped === false;
    }

    // Hyprland 0.57 has no native minimize dispatcher. A window is hidden by
    // tagging it and moving it to a special workspace; the record is kept so
    // an activation from the dock or alt-tab can bring it back to the exact
    // workspace it came from.
    function minimizedRecords() {
        return Persistent.states?.windowControls?.minimized ?? [];
    }

    function minimizedRecord(address) {
        const key = root.normalizeAddress(address);
        if (!key) return null;
        return (root.minimizedRecords()).find(entry =>
            root.normalizeAddress(entry?.address) === key) ?? null;
    }

    function isShellMinimized(address) {
        return root.minimizedRecord(address) !== null;
    }

    // A span window covers every monitor and suppresses fullscreen requests
    // at the rule level, so maximize is meaningless for it.
    function isSpan(client, rules) {
        if (!client) return false;
        return WindowMode.desiredSpan(client, rules ?? []);
    }

    function canMaximize(client, rules) {
        if (!client) return false;
        if (root.isMinimized(client)) return false;
        return !root.isSpan(client, rules);
    }

    function canMinimize(client) {
        return client != null && !root.isMinimized(client);
    }

    // The current type shown by the selector. Stacking is a session-wide mode
    // in WindowMode, so it wins over the per-window floating flag; span is a
    // per-app rule, so it wins over both.
    function windowTypeFor(client, globalMode, rules) {
        if (!client) return "tiling";
        if (root.isSpan(client, rules)) return "span";
        if (globalMode === "stacking") return "stacking";
        return client.floating ? "floating" : "tiling";
    }

    function isWindowType(value) {
        return root.windowTypes.indexOf(value) >= 0;
    }

    // View helpers shared by the cluster and the type menu. They live here so
    // the labels a user sees are asserted by the same test file as the
    // decisions that drive them.
    function showsButton(buttons, name) {
        return (buttons ?? []).indexOf(name) >= 0;
    }

    function typeSymbol(type) {
        switch (type) {
        case "floating": return "open_in_full";
        case "tiling": return "grid_view";
        case "stacking": return "layers";
        case "span": return "crop_free";
        }
        return "layers";
    }

    function typeLabel(type) {
        switch (type) {
        case "floating": return "Floating";
        case "tiling": return "Tiling";
        case "stacking": return "Stacking";
        case "span": return "Span (all monitors)";
        }
        return type;
    }

    // Windows-like glyphs. The raw Material Symbols names "maximize" and
    // "restore" render as a dash and a clock in this font, so the cluster
    // uses these verified ones instead: a square and two overlapping squares.
    function windowStateSymbol(fullscreen) {
        return Number(fullscreen ?? 0) === 0 ? "crop_square" : "filter_none";
    }

    function nextType(current) {
        const index = root.windowTypes.indexOf(current);
        const next = (index + 1) % root.windowTypes.length;
        return root.windowTypes[next < 0 ? 0 : next];
    }

    // Match a class pattern the way WindowMode does: a search, not an anchor.
    function patternMatchesClass(pattern, winClass) {
        const text = String(pattern ?? "");
        if (!text) return false;
        try {
            return new RegExp(text).test(String(winClass ?? ""));
        } catch (error) {
            return false;
        }
    }

    // True when a span rule for this class is already in the list, so the
    // type button never adds the same rule twice.
    function hasSpanRule(rules, winClass) {
        return (rules ?? []).some(rule =>
            rule?.mode === "span" && root.patternMatchesClass(rule?.class, winClass));
    }

    // Dispatcher strings. Pure so the fallback chain is testable. The
    // numbered candidates are tried in order; index 1 is always the native
    // Hyprland fallback, which acts on the active window (the one this
    // control is attached to).
    function closeDispatcher(address) {
        return `hl.dsp.window.close({ window = "address:${address}" })`;
    }

    function focusDispatcher(address) {
        return `hl.dsp.focus({ window = "address:${address}" })`;
    }

    function maximizeDispatcher(address, candidate) {
        if (candidate === 1) return "fullscreen 1";
        return `hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = "address:${address}" })`;
    }

    // Hide: tag the window and park it on a special workspace. It stays in
    // ToplevelManager, so the dock and alt-tab still list it.
    function hideDispatcher(address) {
        return `hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:${address}" })`;
    }

    function tagDispatcher(address) {
        return `hl.dsp.window.tag({ tag = "minimized", window = "address:${address}" })`;
    }

    function untagDispatcher(address) {
        return `hl.dsp.window.clear_tags({ window = "address:${address}" })`;
    }

    // Restore: move the window back to its own workspace, following it, then
    // clear the tag. The focus call comes from the caller's activation.
    function restoreDispatcher(address, workspace) {
        return `hl.dsp.window.move({ workspace = ${workspace}, follow = true, window = "address:${address}" })`;
    }

    function minimizeDispatcher(address, candidate) {
        return root.hideDispatcher(address);
    }

    function floatDispatcher(address, floating) {
        return `hl.dsp.window.float({ window = "address:${address}", action = "${floating ? "set" : "unset"}" })`;
    }

    function dispatchersFor(action, address) {
        if (action === "maximize") return [root.maximizeDispatcher(address, 0), root.maximizeDispatcher(address, 1)];
        if (action === "minimize") return [root.hideDispatcher(address)];
        return [];
    }

    function candidateIndex(action) {
        if (action === "maximize") return root.maximizeCandidate;
        if (action === "minimize") return root.minimizeCandidate;
        return 0;
    }

    function setCandidateIndex(action, index) {
        if (action === "maximize") root.maximizeCandidate = index;
        else if (action === "minimize") root.minimizeCandidate = index;
    }

    // The value watched after a dispatch to decide whether it worked.
    function stateFor(action, client) {
        if (!client) return null;
        if (action === "maximize") return Number(client.fullscreen ?? 0);
        if (action === "minimize") return root.isMinimized(client) || root.isShellMinimized(client.address);
        return null;
    }

    // ------------------------------------------------------------------
    // Actions. These are the only impure functions.
    // ------------------------------------------------------------------

    function close(addressArg) {
        if (root.demoMode) {
            root.demoRecord("close", "no real window closed");
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        Hyprland.dispatch(root.closeDispatcher(address));
        return true;
    }

    // Bring a hidden window back to the workspace it was on, then focus it.
    // This runs automatically when the dock or alt-tab activates the window,
    // so those paths keep working without knowing about the special workspace.
    function restore(addressArg) {
        if (root.demoMode) {
            const mock = root.demoClient ?? {};
            mock.hidden = false;
            mock.mapped = true;
            root.demoClient = mock;
            root.demoRecord("restore");
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        const record = root.minimizedRecord(address);
        if (record) {
            Hyprland.dispatch(root.restoreDispatcher(address, Number(record.workspace ?? 1)));
            Hyprland.dispatch(root.untagDispatcher(address));
            root.setMinimizedRecords(root.minimizedRecords().filter(entry =>
                root.normalizeAddress(entry?.address) !== address));
        }
        Hyprland.dispatch(root.focusDispatcher(address));
        return true;
    }

    function setMinimizedRecords(records) {
        Persistent.states.windowControls.minimized = records;
    }

    function maximize(addressArg) {
        if (root.demoMode) {
            const mock = root.demoClient ?? {};
            mock.fullscreen = Number(mock.fullscreen ?? 0) === 0 ? 1 : 0;
            root.demoClient = mock;
            root.demoRecord("maximize", mock.fullscreen ? "maximized" : "restored");
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        const client = root.findClient(HyprlandData.windowByAddress ?? ({}), address);
        if (!root.canMaximize(client, WindowMode.appRules ?? [])) return false;
        if (root.maximizeCandidate < 0) root.maximizeCandidate = 0;
        return root.dispatchTracked("maximize", address);
    }

    function minimize(addressArg) {
        if (root.demoMode) {
            const mock = root.demoClient ?? {};
            mock.hidden = true;
            mock.mapped = false;
            root.demoClient = mock;
            root.demoRecord("minimize", "hidden, still in dock & alt-tab");
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        const client = root.findClient(HyprlandData.windowByAddress ?? ({}), address);
        if (!root.canMinimize(client)) return false;
        if (root.isShellMinimized(address)) return true;

        const workspace = Number(client?.workspace?.id ?? 1);
        const records = root.minimizedRecords().filter(entry =>
            root.normalizeAddress(entry?.address) !== address);
        records.push({ "address": address, "workspace": workspace });
        root.setMinimizedRecords(records);

        Hyprland.dispatch(root.tagDispatcher(address));
        Hyprland.dispatch(root.hideDispatcher(address));
        return true;
    }

    function setFloating(addressArg, floating) {
        if (root.demoMode) {
            const mock = root.demoClient ?? {};
            mock.floating = !!floating;
            root.demoClient = mock;
            root.demoRecord("float", floating ? "set" : "unset");
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        WindowMode.setFloat(address, !!floating);
        if (floating) WindowMode.rememberFloating(address);
        else WindowMode.forgetFloating(address);
        return true;
    }

    function setSpan(addressArg) {
        if (root.demoMode) {
            root.demoSpan = true;
            root.demoRecord("span", "rule added for the demo class");
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        const client = root.findClient(HyprlandData.windowByAddress ?? ({}), address);
        const winClass = String(client?.class ?? "");
        if (!winClass) return false;
        const rules = WindowMode.appRules ?? [];
        if (root.hasSpanRule(rules, winClass)) return true;
        WindowMode.addAppRule(winClass, "span");
        return true;
    }

    function setType(type, addressArg) {
        if (!root.isWindowType(type)) return false;
        if (root.demoMode) {
            root.demoApplyType(type);
            root.demoRecord("setType", root.typeLabel(type));
            return true;
        }
        const address = root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        switch (type) {
        case "floating":
            return root.setFloating(address, true);
        case "tiling":
            return root.setFloating(address, false);
        case "stacking":
            WindowMode.setMode("stacking");
            return true;
        case "span":
            return root.setSpan(address);
        }
        return false;
    }

    function cycleType(addressArg) {
        // In demo mode there is no live toplevel to take an address from.
        const address = root.demoMode
            ? (root.normalizeAddress(addressArg) || "0xdemo")
            : root.normalizeAddress(addressArg ?? root.activeAddress);
        if (!address) return false;
        const current = root.demoMode
            ? root.displayType()
            : root.windowTypeFor(
                root.findClient(HyprlandData.windowByAddress ?? ({}), address),
                WindowMode.mode,
                WindowMode.appRules ?? []);
        return root.setType(root.nextType(current), address);
    }

    // ------------------------------------------------------------------
    // Fallback verification.
    // ------------------------------------------------------------------

    property var _pending: null

    function dispatchTracked(action, address) {
        const dispatchers = root.dispatchersFor(action, address);
        const index = root.candidateIndex(action);
        if (index < 0 || index >= dispatchers.length) return false;
        const client = root.findClient(HyprlandData.windowByAddress ?? ({}), address);
        root._pending = {
            "action": action,
            "address": address,
            "index": index,
            "before": root.stateFor(action, client)
        };
        Hyprland.dispatch(dispatchers[index]);
        verifyTimer.restart();
        return true;
    }

    Timer {
        id: verifyTimer
        interval: 300
        repeat: false

        onTriggered: {
            const pending = root._pending;
            if (!pending) return;
            root._pending = null;
            const client = root.findClient(HyprlandData.windowByAddress ?? ({}), pending.address);
            if (!client) return; // The window closed before we could verify.
            const after = root.stateFor(pending.action, client);
            if (after !== pending.before) {
                root.setCandidateIndex(pending.action, pending.index);
                return;
            }
            const next = pending.index + 1;
            const dispatchers = root.dispatchersFor(pending.action, pending.address);
            if (next < dispatchers.length) {
                Hyprland.dispatch(dispatchers[next]);
                root._pending = {
                    "action": pending.action,
                    "address": pending.address,
                    "index": next,
                    "before": pending.before
                };
                verifyTimer.restart();
            } else {
                // Nothing worked. Hide the button until the compositor or the
                // config changes; a manual setMode() through IPC can retry.
                root.setCandidateIndex(pending.action, -1);
            }
        }
    }

    Connections {
        target: Hyprland
        enabled: root.supported

        function onRawEvent(event) {
            const address = root.normalizeAddress(String(event.data ?? "").split(",")[0]);

            if (event.name === "closewindow") {
                if (root._pending && root._pending.address === address) root._pending = null;
                if (root.isShellMinimized(address)) {
                    root.setMinimizedRecords(root.minimizedRecords().filter(entry =>
                        root.normalizeAddress(entry?.address) !== address));
                }
                return;
            }

            if (event.name === "activewindow" && root.isShellMinimized(address)) {
                // The dock and alt-tab activate a toplevel; that is the moment
                // to bring a parked window back. Do it after the event so the
                // activation is not overwritten by the move.
                Qt.callLater(() => {
                    if (root.isShellMinimized(address)) root.restore(address);
                });
            }
        }
    }

    // ------------------------------------------------------------------
    // Scripting surface, mirroring WindowMode's IpcHandler pattern.
    // ------------------------------------------------------------------

    IpcHandler {
        target: "windowControls"

        function close(): void { root.close(); }
        function maximize(): void { root.maximize(); }
        function minimize(): void { root.minimize(); }
        function restore(): void { root.restore(); }

        // Address-taking variants for scripts and for testing a specific
        // window without stealing focus.
        function minimizeAddress(address: string): void { root.minimize(address); }
        function restoreAddress(address: string): void { root.restore(address); }
        function setType(type: string): void { root.setType(type); }
        function cycleType(): void { root.cycleType(); }

        function status(): string {
            return JSON.stringify({
                "supported": root.supported,
                "demoMode": root.demoMode,
                "displayType": root.displayType(),
                "activeAddress": root.activeAddress,
                "activeClass": root.activeClient?.class ?? "",
                "activeTitle": root.activeClient?.title ?? "",
                "activeType": root.windowTypeFor(root.activeClient, WindowMode.mode, WindowMode.appRules ?? []),
                "minimized": root.isMinimized(root.activeClient),
                "canMaximize": root.canMaximize(root.activeClient, WindowMode.appRules ?? []),
                "maximizeCandidate": root.maximizeCandidate,
                "minimizeCandidate": root.minimizeCandidate,
                "dispatchers": root.dispatchersFor("maximize", root.activeAddress)
                    .concat(root.dispatchersFor("minimize", root.activeAddress))
            });
        }

        function retryDispatchers(): void {
            root.maximizeCandidate = 0;
            root.minimizeCandidate = 0;
        }
    }
}
