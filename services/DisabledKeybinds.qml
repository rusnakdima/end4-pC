pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The recoverable "deleted keybind" list for the settings pane.
 *
 * Deletes are overlay.disabled ids, written through ManagedKeybinds. That is
 * the same contract the generator reads, so a later overlay save (create,
 * rebind, conflict fix) regenerates the Lua without resurrecting a deleted
 * bind. This service no longer splices comment markers into generated Lua —
 * those files are rewritten wholesale and the markers were always lost.
 *
 * The two config paths and their FileViews are kept as read-only snapshots so
 * the settings pane can still label a row with its source file. All writes
 * go through ManagedKeybinds; the paths are properties for the hosted test.
 */
Singleton {
    id: root

    // The two generated files are read-only snapshots here; the pane uses
    // their paths to recognise a bind it is allowed to delete.
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)

    property var _disabled: []
    readonly property var disabled: root._disabled

    // Labels come from the caller: the overlay stores only ids, so a row
    // read back from disk keeps the label of a disable in this session and
    // falls back to the catalog id otherwise. A shell action (or any other
    // delete id that groups several binds) maps to several catalog ids, so
    // both directions are remembered for restore and for list rebuilding.
    property var labelById: ({})
    property var catalogIdsByEntry: ({})
    property var entryByCatalogId: ({})

    property bool mainLoaded: false
    property bool userLoaded: false
    readonly property bool ready: root.mainLoaded && root.userLoaded

    // Bumped on every state rebuild, so a caller can wait for an overlay
    // change to land instead of guessing when the save finished.
    property int loadGeneration: 0

    // Legacy counters/state kept for the hosted tests and external callers;
    // new disables write only the overlay, through ManagedKeybinds.
    property int reloadCount: 0
    property int writeCount: 0
    property int pendingSaves: 0
    property string mainText: ""
    property string userText: ""
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

    // The overlay is the single source of truth. ManagedKeybinds writes it;
    // this service keeps the Deleted section in sync with the ids it contains,
    // including saves made from elsewhere in Settings.
    Connections {
        target: ManagedKeybinds
        function onOverlayChanged() {
            root.rebuild();
            root.loadGeneration += 1;
        }
    }

    // A single Process object is reused for a legacy reload request; new
    // disables are reloaded by ManagedKeybinds' generator hook instead.
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

    // Refresh the read-only snapshots, then rebuild from the overlay.
    function reload() {
        root.loadGeneration += 1;
        root.mainText = root.readText(mainFile);
        root.userText = root.readText(userFile);
        root.rebuild();
    }

    // Pure read of ManagedKeybinds.overlay.disabled. No generated file is
    // touched: a disable is only an id in the JSON the generator consumes.
    function rebuild() {
        const entries = [];
        for (const rawId of (ManagedKeybinds.overlay?.disabled ?? [])) {
            const catalogId = String(rawId ?? "");
            if (catalogId === "") continue;
            const entryId = root.entryByCatalogId[catalogId] ?? catalogId;
            const bind = ManagedKeybinds.catalogBind(catalogId);
            entries.push({
                id: entryId,
                label: root.labelById[entryId] ?? String(bind?.description ?? catalogId),
                file: String(bind?.source ?? "main") === "custom" ? "custom" : "main",
                lines: []
            });
        }
        root._disabled = entries;
    }

    function triggerReload() {
        root.reloadCount += 1;
        // Restart rather than only setting `running` so back-to-back saves
        // each get their own reload even if the previous one is still up.
        compositorReload.running = false;
        compositorReload.running = true;
    }

    /**
     * Disable the catalog binds behind `id` in one overlay save. `id` is the
     * row's delete id ("shell:<action>" or "bind:<file>:<line>"); the catalog
     * ids come from the bind objects, so one shell action can own every bind
     * it generates without touching a single generated file.
     *
     * Returns {ok, error}. Unknown ids write nothing.
     */
    function disableBinds(id, label, binds) {
        const wanted = String(id ?? "");
        if (wanted === "") return { ok: false, error: "bad-id" };
        if (!Array.isArray(binds) || binds.length === 0) return { ok: false, error: "no-binds" };
        if (!root.ready || !ManagedKeybinds.loaded) return { ok: false, error: "not-loaded" };

        const catalogIds = [];
        for (const bind of binds) {
            const catalogId = String(bind?.catalogBind?.id ?? bind?.id ?? "");
            if (catalogId !== "" && catalogIds.indexOf(catalogId) === -1)
                catalogIds.push(catalogId);
        }
        if (catalogIds.length === 0) return { ok: false, error: "unknown-path" };

        const result = ManagedKeybinds.disableMany(catalogIds);
        if (!result.ok) return result;

        // A stale legacy override could move a deleted combo back onto its key
        // after a restore. Clear it in the same disable; the overlay itself
        // does not need it because disabled ids are omitted by the generator.
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
            if (combo !== "")
                overrideIds.add("bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_"));
        }

        const nextIds = Object.assign({}, root.catalogIdsByEntry, { [wanted]: catalogIds });
        const nextEntries = Object.assign({}, root.entryByCatalogId);
        for (const catalogId of catalogIds) nextEntries[catalogId] = wanted;
        root.catalogIdsByEntry = nextIds;
        root.entryByCatalogId = nextEntries;
        root.labelById = Object.assign({}, root.labelById, { [wanted]: String(label ?? wanted) });
        root.loadGeneration += 1;
        root.rebuild();

        for (const overrideId of overrideIds)
            HyprlandBindOverrides.clearOverride(overrideId);
        return { ok: true, error: "" };
    }

    function isDisabled(id) {
        const wanted = String(id ?? "");
        const catalogIds = root.catalogIdsByEntry[wanted] ?? [wanted];
        return catalogIds.some(catalogId => ManagedKeybinds.isDisabled(catalogId));
    }

    // Restore the ids behind a row's delete id. A shell action can own binds
    // in both generated files, so all of its ids are re-enabled in one save.
    // An id that is not in the overlay is refused without a write.
    function restore(id) {
        const wanted = String(id ?? "");
        if (wanted === "") return { ok: false, error: "bad-id" };
        if (!root.ready || !ManagedKeybinds.loaded) return { ok: false, error: "not-loaded" };

        const catalogIds = root.catalogIdsByEntry[wanted] ?? [wanted];
        const disabled = (ManagedKeybinds.overlay?.disabled ?? []).map(item => String(item ?? ""));
        const targets = catalogIds.filter(catalogId => disabled.indexOf(catalogId) !== -1);
        if (targets.length === 0) return { ok: false, error: "not-found" };

        const result = ManagedKeybinds.enableMany(targets);
        if (!result.ok) return result;

        const nextIds = Object.assign({}, root.catalogIdsByEntry);
        delete nextIds[wanted];
        const nextLabels = Object.assign({}, root.labelById);
        delete nextLabels[wanted];
        const nextEntries = Object.assign({}, root.entryByCatalogId);
        for (const catalogId of targets) delete nextEntries[catalogId];
        root.catalogIdsByEntry = nextIds;
        root.labelById = nextLabels;
        root.entryByCatalogId = nextEntries;
        root.loadGeneration += 1;
        root.rebuild();
        return { ok: true, error: "" };
    }
}
