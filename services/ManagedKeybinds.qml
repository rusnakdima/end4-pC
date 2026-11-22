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

    // The frozen catalog is read-only, but edits need it for id lookup and to
    // know which binds are raw Lua (their combo cannot be overridden).
    property var catalog: null
    property bool catalogLoaded: false

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

    FileView {
        id: catalogFile
        path: root.catalogPath
        preload: true

        onLoaded: {
            try {
                root.catalog = JSON.parse(catalogFile.text() ?? "null");
            } catch (e) {
                console.error("[kbd] catalog parse failed: " + e);
            }
            root.catalogLoaded = true;
        }
        onLoadFailed: error => {
            console.error("[kbd] catalog load failed: " + error);
            root.catalogLoaded = true;
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

    // The frozen catalog entry for an id, or null when the id is unknown
    // (for example a hand-written override). DisabledKeybinds uses this to
    // label the Deleted section and to pick the right generated file.
    function catalogBind(id) {
        return KeybindStore.catalogBind(root.catalog, id);
    }

    function isRawBind(id) {
        return KeybindStore.isRawBind(root.catalogBind(id));
    }

    function isDisabled(id) {
        return KeybindStore.isDisabled(root.overlay, id);
    }

    function isOverridden(id) {
        return Object.prototype.hasOwnProperty.call(root.overlay.overrides ?? {}, String(id ?? ""));
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

    // Replaces the add with the given id, or writes a narrow override for a
    // frozen catalog bind. An id that is neither is refused without a write.
    function update(id, entry) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };

        const adds = root.overlay.adds ?? [];
        const index = adds.findIndex(item => String(item.id ?? "") === id);
        if (index === -1) return updateCatalogBind(id, entry);

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

    // A frozen catalog bind can only be changed through overrides[id]: the
    // catalog itself is never edited. Raw binds are refused outright — their
    // Lua is emitted verbatim, so neither combo nor description can be
    // overridden without making the panel disagree with what Hyprland loads.
    function updateCatalogBind(id, entry) {
        const catalog = root.catalogBind(id);
        if (catalog === null) return { ok: false, error: "not-found" };

        const patch = {};
        const allowed = ["combo", "description", "category", "dispatch", "options", "enabled", "label", "name", "command"];
        for (const key of allowed) {
            if (Object.prototype.hasOwnProperty.call(entry ?? {}, key)) patch[key] = entry[key];
        }
        if (Object.keys(patch).length === 0) return { ok: false, error: "not-found" };
        if (KeybindStore.isRawBind(catalog)) return { ok: false, error: "raw-combo" };

        // The form speaks name/command; the overlay stores description/dispatch.
        if ("name" in patch) {
            patch.description = patch.name;
            delete patch.name;
        }
        if ("command" in patch) {
            patch.dispatch = { kind: "command", id: id, command: String(patch.command ?? "") };
            delete patch.command;
        }
        if ("combo" in patch && String(patch.combo ?? "").trim() === "")
            return { ok: false, error: "empty-combo" };

        const overrides = Object.assign({}, root.overlay.overrides ?? {});
        overrides[id] = Object.assign({}, overrides[id] ?? {}, patch);
        root.overlay = KeybindStore.withOverrides(root.overlay, overrides);
        root.entries = (root.overlay.adds ?? []).map(item => KeybindStore.addToEntry(item));
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

    // Narrow combo override for a catalog bind. Used by the conflict fixer and
    // by row capture for binds that do not come from an overlay add. Only
    // `combo` is written; dispatch/options stay with the frozen catalog. Raw
    // Lua binds are refused: their combo is part of the verbatim statement.
    function setOverride(id, combo) {
        if (!root.loaded || String(id ?? "") === "") return { ok: false, error: "bad-id" };
        if (root.isRawBind(id)) return { ok: false, error: "raw-combo" };
        const overrides = Object.assign({}, root.overlay.overrides ?? {});
        overrides[id] = Object.assign({}, overrides[id] ?? {}, KeybindStore.comboOverride(combo));
        const overlay = KeybindStore.withOverrides(root.overlay, overrides);
        root.overlay = overlay;
        root.entries = (overlay.adds ?? []).map(item => KeybindStore.addToEntry(item));
        root.write();
        return { ok: true, error: "" };
    }

    // One edit for every member of a catalog series. Series members are raw
    // Lua binds: their code is emitted verbatim, so a per-bind combo override
    // is refused. The generator rewrites each member's code and combo from
    // seriesOverrides[seriesId].mods instead. A null patch value clears that
    // field — that is how "enable" and "reset" undo a previous edit.
    function setSeriesOverride(seriesId, patch) {
        if (!root.loaded || String(seriesId ?? "") === "") return { ok: false, error: "bad-id" };
        const id = String(seriesId);
        const series = (root.catalog?.binds ?? []).filter(
            bind => String(bind?.seriesId ?? "") === id);
        if (series.length === 0) return { ok: false, error: "not-found" };

        const spec = {};
        if (Object.prototype.hasOwnProperty.call(patch ?? {}, "mods")) {
            const mods = patch.mods === null ? null : String(patch.mods ?? "").trim();
            if (mods === "") return { ok: false, error: "empty-combo" };
            spec.mods = mods;
        }
        if (Object.prototype.hasOwnProperty.call(patch ?? {}, "enabled")) {
            if (patch.enabled !== null && typeof patch.enabled !== "boolean")
                return { ok: false, error: "not-found" };
            spec.enabled = patch.enabled;
        }
        if (Object.keys(spec).length === 0) return { ok: false, error: "not-found" };

        root.overlay = KeybindStore.withSeriesOverride(root.overlay, id, spec);
        root.entries = (root.overlay.adds ?? []).map(item => KeybindStore.addToEntry(item));
        root.write();
        console.log("[kbd] series override id=" + id + " " + JSON.stringify(spec));
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

    // Delete/restore of a frozen catalog bind. `disabled` is the generator's
    // own contract, so a disable survives every later overlay save: the
    // generator reads the id list on each run and omits that bind again.
    function disableMany(ids) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };
        const wanted = (ids ?? []).map(id => String(id ?? "")).filter(id => id !== "");
        if (wanted.length === 0) return { ok: false, error: "bad-id" };

        const before = (root.overlay.disabled ?? []).map(id => String(id ?? ""));
        if (wanted.every(id => before.indexOf(id) !== -1)) return { ok: true, error: "" };

        let overlay = root.overlay;
        for (const id of wanted) overlay = KeybindStore.withDisabled(overlay, id, true);
        root.overlay = overlay;
        root.write();
        return { ok: true, error: "" };
    }

    function disable(id) {
        return root.disableMany([id]);
    }

    function enableMany(ids) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };
        const wanted = (ids ?? []).map(id => String(id ?? "")).filter(id => id !== "");
        if (wanted.length === 0) return { ok: false, error: "bad-id" };

        const before = (root.overlay.disabled ?? []).map(id => String(id ?? ""));
        const anyDisabled = wanted.some(id => before.indexOf(id) !== -1);
        const overrides = Object.assign({}, root.overlay.overrides ?? {});
        let clearedEnabled = false;
        for (const id of wanted) {
            const current = overrides[id];
            if (current && current.enabled === false) {
                const next = Object.assign({}, current);
                delete next.enabled;
                if (Object.keys(next).length === 0) delete overrides[id];
                else overrides[id] = next;
                clearedEnabled = true;
            }
        }
        if (!anyDisabled && !clearedEnabled) return { ok: true, error: "" };

        let overlay = root.overlay;
        for (const id of wanted) overlay = KeybindStore.withDisabled(overlay, id, false);
        root.overlay = KeybindStore.withOverrides(overlay, overrides);
        root.write();
        return { ok: true, error: "" };
    }

    function enable(id) {
        return root.enableMany([id]);
    }
}
