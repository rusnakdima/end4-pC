pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/KeybindStore.js" as KeybindStore

/**
 * Owns ~/.config/hypr/custom/keybind-overlay.json — the only file the settings
 * panel writes for keybinds.
 *
 * The frozen catalog lives in the shell (defaults/hyprland/keybinds.json) and
 * is never edited here. This singleton reads the user overlay, exposes its
 * adds as editable entries, and after every write runs the catalog generator
 * (scripts/hyprland/generate_keybinds.py) so the two Lua files Hyprland loads
 * always match what the panel shows. A compositor reload follows the write.
 *
 * All JSON parsing/rendering is in KeybindStore.js; this singleton is the IO
 * half. keybindsPath is a property so a test can point it at a temp file.
 */
Singleton {
    id: root

    readonly property string keybindsDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom`)
    property string keybindsPath: `${root.keybindsDir}/keybind-overlay.json`

    // Frozen inputs / generated outputs, all absolute for the bash -lc call.
    readonly property string catalogPath: Quickshell.shellPath("defaults/hyprland/keybinds.json")
    readonly property string generatorPath: Quickshell.shellPath("scripts/hyprland/generate_keybinds.py")
    readonly property string mainOutPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    readonly property string customOutPath: `${root.keybindsDir}/keybinds.lua`
    readonly property string commandsOutPath: FileUtils.trimFileProtocol(
        Quickshell.shellPath("state/generated-commands.json"))

    // The parsed overlay. The generator and HyprlandKeybinds read the same
    // object, so the list, the cheatsheet and the live config cannot drift.
    property var overlay: KeybindStore.newOverlay()

    // Every add in the overlay, as the form/filter view objects. There is no
    // raw residue in a JSON file, so every entry is editable.
    property var entries: []

    readonly property var editableEntries: root.entries

    // A write is in flight. The file belongs to that write until it is done.
    property bool pendingWrite: false
    // The overlay was written at least once: a late "missing file" load must
    // not empty the entries after that.
    property bool wrote: false
    // The overlay has been read once (or reported missing).
    property bool loaded: false
    // Bumped on every parse so a test can wait for the next read.
    property int loadGeneration: 0
    // The custom directory exists (startup mkdir finished).
    property bool dirReady: false
    // A setText is awaiting its onSaved confirmation before the generator runs.
    property bool awaitGeneration: false

    FileView {
        id: overlayFile
        path: root.keybindsPath
        preload: true
        watchChanges: true

        onLoaded: root.reload()
        onFileChanged: root.reload()
        onSaved: {
            if (root.awaitGeneration) {
                root.awaitGeneration = false;
                root.runGenerator();
            } else {
                root.reload();
            }
        }
        onSaveFailed: error => {
            console.error("[kbd] overlay save failed: " + error);
            root.awaitGeneration = false;
        }
        onLoadFailed: error => {
            root.loaded = true;
            root.loadGeneration += 1;
            if (error === FileViewError.FileNotFound && !root.pendingWrite && !root.wrote) {
                root.overlay = KeybindStore.newOverlay();
                root.entries = [];
            }
        }
    }

    // hypr/custom is user owned and normally already there, but a fresh
    // installation can have no custom directory at all. Create it once at
    // startup so a save does not depend on a process hop.
    Process {
        id: mkdirProc
        running: true
        command: ["mkdir", "-p", root.keybindsDir]
        onExited: (exitCode, exitStatus) => {
            root.dirReady = true;
            if (root.pendingWrite) {
                root.pendingWrite = false;
                root.writeFile();
            }
        }
    }

    function shq(value) {
        return "'" + String(value ?? "").replace(/'/g, "'\\''") + "'";
    }

    // Exactly the generator contract sync.sh uses, with absolute paths.
    function generatorCommand() {
        return "mkdir -p " + shq(FileUtils.trimFileProtocol(Quickshell.shellPath("state")))
            + "; python3 " + shq(root.generatorPath)
            + " --catalog " + shq(root.catalogPath)
            + " --overlay " + shq(root.keybindsPath)
            + " --main-out " + shq(root.mainOutPath)
            + " --custom-out " + shq(root.customOutPath)
            + " --commands-out " + shq(root.commandsOutPath);
    }

    Process {
        id: generateProc
        command: ["bash", "-lc", root.generatorCommand()]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("[kbd] keybind generator exited " + exitCode);
                return;
            }
            // Same reload mechanism the old managed-block writer used.
            Quickshell.execDetached(["hyprctl", "reload"]);
        }
    }

    function reload() {
        // A write in flight owns the file. Reading it now would drop the
        // change that is about to be written.
        if (root.pendingWrite) return;

        root.loaded = true;
        root.loadGeneration += 1;
        const parsed = KeybindStore.parseOverlay(overlayFile.text() ?? "");
        root.overlay = parsed;
        root.entries = (parsed.adds ?? []).map(add => KeybindStore.addToEntry(add));
        console.log("[kbd] overlay reload gen=" + root.loadGeneration
            + " adds=" + root.entries.length);
    }

    function runGenerator() {
        generateProc.running = false;
        generateProc.running = true;
    }

    function write() {
        if (root.dirReady) {
            root.writeFile();
            return;
        }
        root.pendingWrite = true;
        if (!mkdirProc.running) mkdirProc.running = true;
    }

    function writeFile() {
        root.wrote = true;
        const text = KeybindStore.renderOverlay(root.overlay);
        console.log("[kbd] overlay write path=" + root.keybindsPath + " bytes=" + text.length);
        root.awaitGeneration = true;
        overlayFile.setText(text);
    }

    // The overlay add a synthesized bind came from, or null when the bind is
    // one of the frozen catalog entries. Adds carry their overlay id directly
    // (there is no line number in a JSON file), and sourcePath is the overlay
    // file so a catalog bind written to a Lua path can never match.
    function entryForSource(bind) {
        if (bind === undefined || bind === null) return null;
        const source = FileUtils.trimFileProtocol(String(bind.sourcePath ?? ""));
        const overlayPath = FileUtils.trimFileProtocol(String(root.keybindsPath ?? ""));
        if (source === "" || overlayPath === "" || source !== overlayPath) return null;
        const id = String(bind.id ?? "");
        if (id === "") return null;
        return root.entries.find(entry => entry.id === id) ?? null;
    }

    // The validation code of KeybindStore.validate, or "" when the entry can
    // be saved. The caller translates the code.
    function validate(entry) {
        return KeybindStore.validate(entry);
    }

    // Adds an entry to the overlay. Returns {ok, error, id}.
    function create(entry) {
        if (!root.loaded) { console.error("[kbd] create rejected: not-loaded"); return { ok: false, error: "not-loaded", id: "" }; }

        const id = KeybindStore.newId();
        const next = Object.assign({}, entry, { id: id });
        const error = KeybindStore.validate(next);
        if (error !== "") { console.error("[kbd] create invalid: " + error); return { ok: false, error: error, id: "" }; }

        const add = KeybindStore.makeAdd(next, id);
        const overlay = KeybindStore.withAdds(root.overlay, (root.overlay.adds ?? []).concat([add]));
        root.overlay = overlay;
        root.entries = overlay.adds.map(item => KeybindStore.addToEntry(item));
        root.write();
        console.log("[kbd] create ok id=" + id + " combo=" + next.combo);
        return { ok: true, error: "", id: id };
    }

    // Replaces the add with the given id. Unknown id: nothing is written.
    function update(id, entry) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };

        const adds = root.overlay.adds ?? [];
        const index = adds.findIndex(item => String(item.id ?? "") === id);
        if (index === -1) return { ok: false, error: "not-found" };

        const current = KeybindStore.addToEntry(adds[index]);
        const next = Object.assign({}, current, entry, { id: id });
        const error = KeybindStore.validate(next);
        if (error !== "") return { ok: false, error: error };

        const updated = adds.slice();
        updated[index] = KeybindStore.makeAdd(next, id);
        const overlay = KeybindStore.withAdds(root.overlay, updated);
        root.overlay = overlay;
        root.entries = overlay.adds.map(item => KeybindStore.addToEntry(item));
        root.write();
        return { ok: true, error: "" };
    }

    // Drops an add from the overlay.
    function remove(id) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };

        const adds = root.overlay.adds ?? [];
        const next = adds.filter(item => String(item.id ?? "") !== id);
        if (next.length === adds.length) return { ok: false, error: "not-found" };

        const overlay = KeybindStore.withAdds(root.overlay, next);
        root.overlay = overlay;
        root.entries = overlay.adds.map(item => KeybindStore.addToEntry(item));
        root.write();
        return { ok: true, error: "" };
    }

    // Narrow combo override for a catalog bind. Used by the conflict fixer for
    // holders that do not come from an overlay add. Only `combo` is written; a
    // command bind's dispatch/options stay with the frozen catalog.
    function setOverride(id, combo) {
        if (!root.loaded || String(id ?? "") === "") return { ok: false, error: "bad-id" };
        const overrides = Object.assign({}, root.overlay.overrides ?? {});
        overrides[id] = Object.assign({}, overrides[id] ?? {}, KeybindStore.comboOverride(combo));
        const overlay = KeybindStore.withOverrides(root.overlay, overrides);
        root.overlay = overlay;
        root.entries = (overlay.adds ?? []).map(item => KeybindStore.addToEntry(item));
        root.write();
        return { ok: true, error: "" };
    }

    function clearOverride(id) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };
        const overrides = Object.assign({}, root.overlay.overrides ?? {});
        if (!(id in overrides)) return { ok: false, error: "not-found" };
        delete overrides[id];
        const overlay = KeybindStore.withOverrides(root.overlay, overrides);
        root.overlay = overlay;
        root.entries = (overlay.adds ?? []).map(item => KeybindStore.addToEntry(item));
        root.write();
        return { ok: true, error: "" };
    }
}
