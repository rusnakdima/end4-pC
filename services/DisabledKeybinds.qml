pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/common/functions/KeybindDisableStore.js" as KeybindDisableStore

/**
 * Owns the recoverable "deleted keybind" blocks in the two keybind config
 * files. The theme's file and the user's file are watched separately, but a
 * save writes each touched file once and reloads Hyprland once in total.
 *
 * All text editing lives in KeybindDisableStore.js: this singleton only
 * reads a file, hands its text to the store, writes the returned text back
 * and keeps the list of blocks in `disabled` for the settings pane. Nothing
 * outside a marker block is ever rewritten. The paths are properties so the
 * hosted test can point them at temporary files.
 */
Singleton {
    id: root

    // Two files, not two directories: a bind's sourcePath is the file it was
    // parsed from, and that is also the only place this service may write.
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)

    property var _disabled: []
    readonly property var disabled: root._disabled

    // Labels come from the caller: the marker block stores only the id and
    // the original bytes. Blocks read back from disk keep the label of a
    // disable in this session and fall back to the id otherwise.
    property var labelById: ({})

    property bool mainLoaded: false
    property bool userLoaded: false
    readonly property bool ready: root.mainLoaded && root.userLoaded

    // Bumped on every parse, so a caller can wait for a read/write to land
    // instead of guessing how long a FileView save takes.
    property int loadGeneration: 0

    // Test-visible counter: one increment per hyprctl reload request.
    property int reloadCount: 0

    // One increment per FileView.setText, so a grouped save can be checked
    // for one write per file rather than one write per bind.
    property int writeCount: 0

    // FileView saves are asynchronous. Track them so a caller can wait for
    // the bytes to reach disk instead of guessing from a read counter.
    property int pendingSaves: 0

    // The last text read from (or written to) each file. Writes compute from
    // these copies, so a late watch event can never splice against bytes
    // that are not what the service last saw.
    property string mainText: ""
    property string userText: ""

    // A write in flight owns both files until the new text is in memory and
    // `disabled` has been rebuilt from it. Watch callbacks arriving in that
    // window must not replace the new state with the bytes they saw change.
    property bool writing: false

    FileView {
        id: mainFile
        path: root.defaultKeybindConfigPath
        preload: true
        watchChanges: true

        onLoaded: {
            root.mainLoaded = true;
            root.reload();
        }
        onFileChanged: root.onWatch()
        onSaved: {
            if (root.pendingSaves > 0) root.pendingSaves -= 1;
            root.onWatch();
        }
        onLoadFailed: error => {
            root.mainLoaded = true;
            root.reload();
        }
    }

    FileView {
        id: userFile
        path: root.userKeybindConfigPath
        preload: true
        watchChanges: true

        onLoaded: {
            root.userLoaded = true;
            root.reload();
        }
        onFileChanged: root.onWatch()
        onSaved: {
            if (root.pendingSaves > 0) root.pendingSaves -= 1;
            root.onWatch();
        }
        onLoadFailed: error => {
            root.userLoaded = true;
            root.reload();
        }
    }

    // A single Process object is reused for every save; the counter above
    // records that a save asked for exactly one reload, not one per file.
    Process {
        id: compositorReload
        command: ["hyprctl", "reload"]
    }

    function readText(view) {
        try {
            return view.text() ?? "";
        } catch (e) {
            // A missing file is the normal state before the first disable.
            return "";
        }
    }

    // Watch events are reads. They never write and they never touch a file
    // while our own write is between setText() and the state rebuild.
    function onWatch() {
        if (root.writing) return;
        root.reload();
    }

    // Rebuild the pane's list from both files' marker blocks. Pure read: no
    // file is written here, and a block loaded from disk is presented with
    // the label remembered from this session (or its id as a fallback).
    function reload() {
        root.loadGeneration += 1;
        root.mainText = root.readText(mainFile);
        root.userText = root.readText(userFile);
        root.rebuild(root.mainText, root.userText);
    }

    function rebuild(mainText, userText) {
        const entries = [];
        const collect = (text, file) => {
            for (const block of KeybindDisableStore.parseDisabled(text)) {
                entries.push({
                    id: block.id,
                    label: root.labelById[block.id] ?? block.id,
                    file: file,
                    lines: block.lines
                });
            }
        };
        collect(mainText, "main");
        collect(userText, "custom");
        root._disabled = entries;
    }

    // A bind may only be written to one of the two known files. Anything
    // else is refused, so a stale or crafted sourcePath cannot make this
    // service rewrite an unrelated file.
    function viewFor(sourcePath) {
        const path = FileUtils.trimFileProtocol(String(sourcePath ?? ""));
        if (path === FileUtils.trimFileProtocol(root.defaultKeybindConfigPath)) return mainFile;
        if (path === FileUtils.trimFileProtocol(root.userKeybindConfigPath)) return userFile;
        return null;
    }

    function triggerReload() {
        root.reloadCount += 1;
        // Restart rather than only setting `running` so back-to-back saves
        // each get their own reload even if the previous one is still up.
        compositorReload.running = false;
        compositorReload.running = true;
    }

    /**
     * Disable the given bind lines, grouping them by source file. `id` is
     * the caller's stable id and is passed to the store verbatim for every
     * bind — this service does not generate or reinterpret ids.
     *
     * Returns {ok, error}. All texts are computed before any write, so a
     * bad range or an unowned path leaves both config files untouched.
     */
    function disableBinds(id, label, binds) {
        const wanted = String(id ?? "");
        if (wanted === "") return { ok: false, error: "bad-id" };
        if (!Array.isArray(binds) || binds.length === 0) return { ok: false, error: "no-binds" };
        if (!root.ready) return { ok: false, error: "not-loaded" };

        const groups = [];
        const byPath = new Map();
        for (const bind of binds) {
            const path = String(bind?.sourcePath ?? "");
            const view = root.viewFor(path);
            if (view === null) return { ok: false, error: "unknown-path" };

            let group = byPath.get(path);
            if (group === undefined) {
                group = { view: view, binds: [] };
                byPath.set(path, group);
                groups.push(group);
            }
            group.binds.push(bind);
        }

        // One store call per file, whatever number of binds it holds. The
        // store's batch form unwraps every range against the same original
        // text and applies them bottom-up, so a single id can own several
        // blocks in one file without tripping its already-disabled guard.
        const writes = [];
        for (const group of groups) {
            const text = (group.view === mainFile) ? root.mainText : root.userText;
            const ranges = group.binds.map(bind => ({
                line: bind?.line, endLine: bind?.endLine
            }));
            const result = KeybindDisableStore.disableAll(text, {
                id: wanted, ranges: ranges
            });
            if (!result.ok) return { ok: false, error: result.error };
            writes.push({ view: group.view, text: result.text });
        }

        // A stale override would move the deleted combo back onto its key,
        // so clear every deleted bind's override as part of the same disable.
        // Shell actions key the overrides file by action name; a plain bind
        // has no action and is keyed by "bind_<combo>" (the id OtherBindRow
        // uses). Callers may carry that id explicitly, otherwise derive it
        // from the bind's mods/key — existing callers need no change.
        const overrideIds = new Set();
        for (const bind of binds) {
            const action = String(bind?.action ?? "");
            if (action !== "") {
                overrideIds.add(action);
                continue;
            }
            const explicitId = String(bind?.overrideId ?? "");
            if (explicitId !== "") {
                overrideIds.add(explicitId);
                continue;
            }
            const combo = HyprlandKeybinds.comboOf(bind);
            if (combo !== "") {
                overrideIds.add("bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_"));
            }
        }

        root.writing = true;
        for (const write of writes) {
            root.pendingSaves += 1;
            root.writeCount += 1;
            write.view.setText(write.text);
            if (write.view === mainFile) root.mainText = write.text;
            else root.userText = write.text;
        }
        root.labelById = Object.assign({}, root.labelById, { [wanted]: String(label ?? wanted) });
        root.loadGeneration += 1;
        root.rebuild(root.mainText, root.userText);
        root.writing = false;

        for (const id of overrideIds)
            HyprlandBindOverrides.clearOverride(id);
        root.triggerReload();
        return { ok: true, error: "" };
    }

    function isDisabled(id) {
        const wanted = String(id ?? "");
        return root.disabled.some(entry => entry.id === wanted);
    }

    // Restore every block with this id from both files. Shell actions are
    // grouped across the merged tree, so one disable id can own a block in
    // each config file; stopping at the first one would leave the bind
    // disabled, the row non-deletable and the Deleted section populated.
    // Unknown ids and malformed blocks are refused without a write.
    function restore(id) {
        const wanted = String(id ?? "");
        if (wanted === "") return { ok: false, error: "bad-id" };
        if (!root.ready) return { ok: false, error: "not-loaded" };

        const targets = [];
        if (KeybindDisableStore.isDisabled(root.mainText, wanted))
            targets.push({ view: mainFile, text: root.mainText });
        if (KeybindDisableStore.isDisabled(root.userText, wanted))
            targets.push({ view: userFile, text: root.userText });
        if (targets.length === 0) return { ok: false, error: "not-found" };

        // Compute both texts before touching either file: a malformed block
        // in the second file must not leave a half-restored first file.
        const writes = [];
        for (const target of targets) {
            const result = KeybindDisableStore.restore(target.text, wanted);
            if (!result.ok) return { ok: false, error: result.error };
            writes.push({ view: target.view, text: result.text });
        }

        root.writing = true;
        for (const write of writes) {
            root.pendingSaves += 1;
            root.writeCount += 1;
            write.view.setText(write.text);
            if (write.view === mainFile) root.mainText = write.text;
            else root.userText = write.text;
        }
        root.loadGeneration += 1;
        root.rebuild(root.mainText, root.userText);
        root.writing = false;

        root.triggerReload();
        return { ok: true, error: "" };
    }
}
