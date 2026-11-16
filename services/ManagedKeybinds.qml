pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/KeybindStore.js" as KeybindStore

/**
 * Owns the panel-managed block of ~/.config/hypr/custom/keybinds.lua.
 *
 * The block is delimited by the markers of KeybindStore.js and is the only
 * part of the file this config writes: everything outside it belongs to the
 * user and must survive every save byte-for-byte. The file itself lives in
 * hypr/custom, which the Hyprland config requires only when it exists, so
 * creating it here is what makes the new binds take effect on the reload
 * that follows each write.
 *
 * All parsing and rendering is in KeybindStore.js; this singleton is the
 * IO half — read the file, splice the block, write it back, reload.
 * The path is a property so the test can point it at a temp file.
 */
Singleton {
    id: root

    readonly property string keybindsDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom`)
    property string keybindsPath: `${root.keybindsDir}/keybinds.lua`

    // Every parsed item of the managed block, including the lines the
    // parser did not recognise ({raw}), so renderBlock can keep them.
    property var entries: []

    // The entries the form can edit: raw residue lines are preserved but
    // never shown, because there is nothing to edit them with.
    readonly property var editableEntries: root.entries.filter(entry => typeof entry.raw !== "string")

    // A write is in flight. The file belongs to that write until it is done.
    property bool pendingWrite: false

    // The file was written at least once. A load of a file that does not
    // exist must not empty the entries after that.
    property bool wrote: false

    // The file has been loaded once (or reported missing), so its text is
    // known and a write cannot splice against an unread file.
    property bool loaded: false

    // Bumped on every parse of the file. The test switches the path or
    // resets the block and waits for the next parse instead of guessing
    // how long the read takes.
    property int loadGeneration: 0

    FileView {
        id: keybindsFile
        path: root.keybindsPath
        preload: true
        watchChanges: true

        onLoaded: root.reload()
        onFileChanged: root.reload()
        onSaved: root.reload()
        onLoadFailed: error => {
            // No file yet: the managed block starts empty, which is the
            // normal state before the first keybind is created.
            root.loaded = true;
            root.loadGeneration += 1;
            if (error === FileViewError.FileNotFound && !root.pendingWrite && !root.wrote) {
                root.entries = [];
            }
        }
    }

    // hypr/custom is user owned and normally already there, but a fresh
    // installation has no custom directory at all.
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.keybindsDir]
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

        root.loaded = true;
        root.loadGeneration += 1;
        root.entries = KeybindStore.parseBlock(keybindsFile.text() ?? "");
    }

    function write() {
        root.pendingWrite = true;
        if (!mkdirProc.running) mkdirProc.running = true;
    }

    function writeFile() {
        // From here on the file exists, or is about to. A load that reports
        // the file as missing must not empty the entries anymore.
        root.wrote = true;

        const block = KeybindStore.renderBlock(root.entries);
        let current = "";
        try {
            current = keybindsFile.text() ?? "";
        } catch (e) {
            current = "";
        }
        keybindsFile.setText(KeybindStore.splice(current, block));
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    // The validation code of KeybindStore.validate, or "" when the entry
    // can be saved. The caller translates the code.
    function validate(entry) {
        return KeybindStore.validate(entry);
    }

    // Adds an entry to the block. Returns {ok, error, id}: error is a
    // validation code, id the new entry's id when ok.
    function create(entry) {
        if (!root.loaded) return { ok: false, error: "not-loaded", id: "" };

        const id = KeybindStore.newId();
        const next = Object.assign({}, entry, { id: id });
        const error = KeybindStore.validate(next);
        if (error !== "") return { ok: false, error: error, id: "" };

        root.entries = root.entries.concat([next]);
        root.write();
        return { ok: true, error: "", id: id };
    }

    // Replaces the entry with the given id. Unknown id: nothing is written.
    function update(id, entry) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };

        const index = root.entries.findIndex(item => item.id === id && typeof item.raw !== "string");
        if (index === -1) return { ok: false, error: "not-found" };

        const next = Object.assign({}, root.entries[index], entry, { id: id });
        const error = KeybindStore.validate(next);
        if (error !== "") return { ok: false, error: error };

        const entries = root.entries.slice();
        entries[index] = next;
        root.entries = entries;
        root.write();
        return { ok: true, error: "" };
    }

    // Drops an entry from the block. Raw lines are never removed: they are
    // not managed, only preserved.
    function remove(id) {
        if (!root.loaded) return { ok: false, error: "not-loaded" };

        const next = root.entries.filter(item => item.id !== id || typeof item.raw === "string");
        if (next.length === root.entries.length) return { ok: false, error: "not-found" };

        root.entries = next;
        root.write();
        return { ok: true, error: "" };
    }
}
