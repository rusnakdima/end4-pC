pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Owns ~/.config/hypr/custom/keybind_overrides.conf, the file the Hyprland
 * config reads to find out which key an action should be bound to.
 *
 * The file holds one "action = MODS + KEY" per line. Blank lines and lines
 * starting with # are ignored. Hyprland's Lua config has no way to unbind a
 * key, so an override replaces the theme's binding for that action instead of
 * adding a second one.
 */
Singleton {
    id: root

    readonly property string overridesDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom`)
    readonly property string overridesPath: `${root.overridesDir}/keybind_overrides.conf`

    // { "<action>": "SUPER + ALT + V" }
    property var overrides: ({})

    // A write is in flight. The file belongs to that write until it is done.
    property bool pendingWrite: false

    // The file was written at least once. The map keeps its content then,
    // even when a load of a file that does not exist arrives late.
    property bool wrote: false

    FileView {
        id: overridesFile
        path: root.overridesPath
        preload: true
        watchChanges: true

        onLoaded: root.reload()
        onFileChanged: root.reload()
        onSaved: root.reload()
        onLoadFailed: error => {
            // The file does not exist. That is the normal state before the
            // first rebind, and the map is empty then anyway.
            if (error === FileViewError.FileNotFound && !root.pendingWrite && !root.wrote) {
                root.overrides = ({});
            }
        }
    }

    // The directory is user owned and normally already there, but a fresh
    // installation has no custom directory at all.
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.overridesDir]
        onExited: (exitCode, exitStatus) => {
            if (!root.pendingWrite) return;
            root.pendingWrite = false;
            root.writeFile();
        }
    }

    function reload() {
        // A write in flight owns the file. Reading it now would drop the
        // change that is about to be written.
        if (root.pendingWrite) return;

        const parsed = {};
        for (const rawLine of (overridesFile.text() ?? "").split("\n")) {
            const line = rawLine.trim();
            if (line === "" || line.startsWith("#")) continue;
            const separator = line.indexOf("=");
            if (separator === -1) continue;
            const action = line.slice(0, separator).trim();
            const combo = line.slice(separator + 1).trim();
            if (action === "" || combo === "") continue;
            parsed[action] = combo;
        }
        root.overrides = parsed;
    }

    function write() {
        root.pendingWrite = true;
        if (!mkdirProc.running) mkdirProc.running = true;
    }

    function writeFile() {
        // From here on the file exists, or is about to. A load that reports
        // the file as missing must not empty the map anymore.
        root.wrote = true;

        const lines = [
            "# end4-pC keybind overrides",
            "# One \"action = MODS + KEY\" per line.",
        ];
        for (const action of Object.keys(root.overrides).sort()) {
            lines.push(`${action} = ${root.overrides[action]}`);
        }
        overridesFile.setText(`${lines.join("\n")}\n`);
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    function setOverride(action, combo) {
        root.overrides = Object.assign({}, root.overrides, { [action]: combo });
        root.write();
    }

    function clearOverride(action) {
        const next = Object.assign({}, root.overrides);
        delete next[action];
        root.overrides = next;
        root.write();
    }

    function isOverridden(action) {
        return root.overrides[action] !== undefined;
    }

    function comboFor(action, fallback) {
        return root.overrides[action] ?? fallback;
    }
}
