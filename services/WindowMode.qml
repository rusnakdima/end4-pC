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
 * window manager, tiling keeps the dwindle/master/scrolling layout. The
 * switch has two halves, because the compositor only applies a window rule
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
        if (currentMode === "stacking") return rule?.mode === "tiling" ? false : true;
        return rule?.mode === "stacking" ? true : null;
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
    function rulesSource(currentMode, rules) {
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
            // A rule that only repeats what the mode already does is left
            // out: the file then says the same as the mode and nothing has
            // to be rewritten when only the mode changed.
            if (rule.mode === "tiling") {
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
        rules.push({ "class": String(winClass ?? ""), "mode": ruleMode === "tiling" ? "tiling" : "stacking" });
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
        const content = root.rulesSource(root.mode, root.appRules);
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
            if (root.pendingReload) {
                root.pendingReload = false;
                Quickshell.execDetached(["hyprctl", "reload"]);
            }
            root.scheduleReconcile();
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
            root.pendingWrite = false;
            root.writeRulesFile();
        }
    }

    function writeRules() {
        root.pendingWrite = true;
        root.pendingReload = true;
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
    // compositor: one action per window that has to change, and the list of
    // addresses this service owns afterwards. A window that is already in
    // the state the mode wants gets no action, so a window that floats
    // because of its own rule is never taken away from that rule, and an
    // address that no longer belongs to a live window is dropped.
    function reconcilePlan(clients, currentMode, rules, ownedAddresses) {
        const alive = new Set(clients.map(client => client.address));
        const owned = new Set((ownedAddresses ?? []).filter(address => alive.has(address)));
        const actions = [];

        for (const win of clients) {
            const want = root.desiredFloat(win.class, currentMode, rules);
            const isOwned = owned.has(win.address);

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
        }

        return { "actions": actions, "owned": Array.from(owned) };
    }

    // Brings the open windows in line with the mode. A fresh client list
    // is read for this rather than the cached one of HyprlandData, so the
    // state a window was just floated into is not mistaken for the state
    // it had a moment ago.
    function reconcile(clients) {
        if (!root.supported || !Config.ready) return;
        const plan = root.reconcilePlan(clients, root.mode, root.appRules, root.ownedFloats());

        for (const action of plan.actions) root.setFloat(action.address, action.floating);

        const current = root.ownedFloats();
        if (plan.owned.join("\n") !== current.join("\n")) root.setOwnedFloats(plan.owned);
    }

    function setFloat(address, floating) {
        if (!address) return;
        Hyprland.dispatch(`hl.dsp.window.float({ window = "address:${address}", action = "${floating ? "set" : "unset"}" })`);
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

    // A window that opens while the stacking mode is on arrives floating
    // through the rules file. This is the belt to that pair of braces: a
    // window that arrived tiled anyway is floated right away instead of
    // waiting for the next reconcile, and it is remembered as ours.
    function onWindowOpened(data) {
        if (!root.stacking || !Config.ready) return;
        const parts = String(data ?? "").split(",");
        if (parts.length < 3) return;
        const address = parts[0].trim();
        const winClass = parts[2];
        if (root.desiredFloat(winClass, root.mode, root.appRules) !== true) return;
        root.setFloat(address, true);
        root.rememberFloating(address);
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
                root.forgetFloating(String(event.data ?? "").split(",")[0].trim());
            }
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.apply();
        }
    }

    // The mode from the outside: a keybind, a script or a test flips it
    // the same way the settings page does.
    IpcHandler {
        target: "windowMode"

        function setMode(mode: string): void {
            root.setMode(mode);
        }
    }

    // The mode and the rules can also change without this service being
    // asked: the config file is shared with everything that writes it.
    onModeChanged: root.apply()
    onAppRulesChanged: root.apply()

    Component.onCompleted: {
        if (Config.ready) root.apply();
    }
}
