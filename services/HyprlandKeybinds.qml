pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../modules/common/functions/KeybindStore.js" as KeybindStore

/**
 * A service that provides access to Hyprland keybinds.
 *
 * The data source is the frozen JSON catalog (defaults/hyprland/keybinds.json)
 * merged with the user overlay (~/.config/hypr/custom/keybind-overlay.json).
 * There is one flat bind list; the parser-shaped trees below are synthesized
 * from it so every consumer (cheatsheet, settings search, launcher, disabled
 * binds, conflict panel) keeps the exact API it already uses.
 *
 * get_keybinds.py is intentionally no longer called here.
 */
Singleton {
    id: root

    // ---- files -------------------------------------------------------------
    property string catalogPath: Quickshell.shellPath("defaults/hyprland/keybinds.json")
    readonly property string overlayDir: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom`)
    property string overlayPath: `${root.overlayDir}/keybind-overlay.json`

    // Kept for the consumers that still label a bind with the file it lives in.
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
    // Preserved but no longer used by the settings panel.
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)

    // ---- raw data ----------------------------------------------------------
    property var catalog: null
    property var overlay: ({ overrides: {}, adds: [], disabled: [] })

    // The single merged list. Every derived property below reads from this.
    property var effectiveBinds: KeybindStore.effectiveBinds(root.catalog, root.overlay)

    onEffectiveBindsChanged: root.buildTrees()

    // ---- compatibility trees -----------------------------------------------
    // The shape get_keybinds.py used to produce: a root Section with child
    // Sections, each holding keybinds. Uncategorized binds stay on the root so
    // bindsFor("") and the "Uncategorized" cheatsheet column keep working.
    property var defaultKeybinds: { "name": "", "children": [], "keybinds": [], "hiddenCombos": [] }
    property var userKeybinds: { "name": "", "children": [], "keybinds": [], "hiddenCombos": [] }

    // Turn a catalog bind into the old parser's KeyBinding shape. `mods`/`key`
    // come from splitting the effective combo; `action` is derived from a
    // quickshell global dispatcher so shell shortcuts still group together.
    function synthBind(b) {
        const combo = String(b.combo ?? "");
        const original = String(b.originalCombo ?? combo);
        const parts = combo.split(" + ").map(part => part.trim()).filter(part => part !== "");
        const key = parts.length > 0 ? parts[parts.length - 1] : "";
        const mods = parts.length > 1 ? parts.slice(0, -1) : [];

        const dispatch = b.dispatch ?? {};
        const arg = dispatch.arg ?? {};
        const argValue = String(arg.value ?? "");
        let action = "";
        let dispatcher = "hl.bind";
        let params = "";
        if (dispatch.kind === "global") {
            dispatcher = "hl.dsp.global";
            params = argValue;
            if (arg.kind === "string" && argValue.indexOf("quickshell:") === 0)
                action = argValue.slice("quickshell:".length);
        } else if (dispatch.kind === "command") {
            dispatcher = "hl.dsp.exec_cmd";
            params = String(dispatch.command ?? "");
        }

        // Adds carry no `line` (they live in JSON, not in a Lua file); their
        // sourcePath is the overlay so the conflict fixer can find them.
        const isAdd = b.line === undefined;
        const sourcePath = isAdd ? root.overlayPath
            : (String(b.source ?? "") === "custom" ? root.userKeybindConfigPath : root.defaultKeybindConfigPath);
        const hidden = /\[hidden\]/i.test(String(b.group ?? "") + " " + String(b.code ?? ""));

        return {
            mods: mods,
            key: key,
            comment: String(b.description ?? ""),
            action: action,
            dispatcher: dispatcher,
            params: params,
            line: Number(b.line ?? 0),
            endLine: Number(b.line ?? 0),
            sourcePath: sourcePath,
            id: String(b.id ?? ""),
            category: String(b.category ?? ""),
            group: String(b.group ?? ""),
            combo: combo,
            originalCombo: original,
            source: String(b.source ?? "main"),
            hidden: hidden,
            catalogBind: b
        };
    }

    function treeFor(binds) {
        const tree = { "name": "", "children": [], "keybinds": [], "hiddenCombos": [] };
        const byCategory = new Map();
        for (const b of (binds ?? [])) {
            const bind = root.synthBind(b);
            if (bind.hidden && bind.combo !== "") tree.hiddenCombos.push(bind.combo);
            if (bind.category === "") {
                tree.keybinds.push(bind);
                continue;
            }
            if (!byCategory.has(bind.category)) {
                const section = { "name": bind.category, "children": [], "keybinds": [], "hiddenCombos": [] };
                byCategory.set(bind.category, section);
                tree.children.push(section);
            }
            byCategory.get(bind.category).keybinds.push(bind);
        }
        return tree;
    }

    function buildTrees() {
        const main = [];
        const custom = [];
        for (const b of (root.effectiveBinds ?? [])) {
            if (String(b.source ?? "") === "main") main.push(b);
            else custom.push(b);
        }
        root.defaultKeybinds = root.treeFor(main);
        root.userKeybinds = root.treeFor(custom);
    }

    // ---- public API --------------------------------------------------------
    property var keybinds: ({
        name: "",
        // A [hidden] bind can sit above the first section marker, so the
        // parser records its combo on each tree's root Section. Keep the
        // merged tree complete: allUsedCombos walks this tree for hidden
        // combos, and dropping the root level would offer taken keys.
        hiddenCombos: [
            ...(defaultKeybinds.hiddenCombos ?? []),
            ...(userKeybinds.hiddenCombos ?? []),
        ],
        children: [
            ...(defaultKeybinds.children ?? []),
            ...(userKeybinds.children ?? []),
        ],
        keybinds: [
            ...(defaultKeybinds.keybinds ?? []),
            ...(userKeybinds.keybinds ?? []),
        ],
    })

    // The categories of the keybind list. The first entry is the empty one,
    // which holds the binds that sit above the first section marker. The
    // tree nests (Window, Workspace, Session, Apps sit one level down in
    // the theme's keybinds.lua), so the walk is recursive — otherwise the
    // form's chips offer less than the list itself shows.
    readonly property var categories: {
        const names = [""];
        const collect = section => {
            const name = section?.name ?? "";
            if (name !== "" && !names.includes(name)) names.push(name);
            for (const child of (section?.children ?? [])) collect(child);
        };
        for (const section of (root.keybinds.children ?? [])) collect(section);
        return names;
    }

    // The shell actions, grouped by the action name the theme binds them with.
    // These are the ones the settings panel can rebind.
    readonly property var shellActions: {
        const out = new Map();
        const collect = section => {
            for (const bind of (section?.keybinds ?? [])) {
                const action = bind?.action ?? "";
                if (action === "") continue;
                if (!out.has(action)) {
                    out.set(action, { action: action, description: bind.comment ?? "", combos: [], binds: [] });
                }
                const entry = out.get(action);
                const combo = root.comboOf(bind);
                if (!entry.combos.includes(combo)) entry.combos.push(combo);
                entry.binds.push(bind);
            }
            for (const child of (section?.children ?? [])) collect(child);
        };
        collect(root.keybinds);
        return Array.from(out.values());
    }

    // Everything that is not a shell action, grouped by category. The `file`
    // tag comes from the catalog's own `source` field ("main" / "custom") so
    // a repeat warning can say where the other holder lives.
    readonly property var otherSections: {
        const out = [];
        const collect = (section, file) => {
            const binds = (section?.keybinds ?? [])
                .filter(bind => (bind?.action ?? "") === "")
                .map(bind => Object.assign({}, bind, { "file": file }));
            if (binds.length > 0) out.push({ name: section?.name ?? "", binds: binds });
            for (const child of (section?.children ?? [])) collect(child, file);
        };
        collect(root.defaultKeybinds, "main");
        collect(root.userKeybinds, "custom");
        return out;
    }

    // "SUPER + SHIFT + S" for a bind.
    function comboOf(bind) {
        const mods = bind?.mods ?? [];
        const key = bind?.key ?? "";
        return [...mods, key].filter(part => part !== "").join(" + ");
    }

    // Every combination with the binds that hold it. Two holders means a real
    // repeat: pressing the key dispatches both binds. A shell shortcut
    // contributes its displayed combination (or each alias), a plain bind the
    // combination its overrides may have moved it to.
    readonly property var repeatIndex: {
        const index = new Map();
        const put = (combo, holder) => {
            if (combo === "") return;
            const holders = index.get(combo);
            if (holders === undefined) index.set(combo, [holder]);
            else holders.push(holder);
        };
        const collect = (tree, file) => {
            const actions = new Map();
            let plainSeq = 0;
            const walk = section => {
                for (const bind of (section?.keybinds ?? [])) {
                    const action = bind?.action ?? "";
                    const combo = root.comboOf(bind);
                    if (action !== "") {
                        if (!actions.has(action)) actions.set(action, { combos: [], comment: bind?.comment ?? "", bind: bind });
                        const entry = actions.get(action);
                        if (!entry.combos.includes(combo)) entry.combos.push(combo);
                    } else {
                        const id = "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_");
                        const sourceLine = String(bind?.line ?? ("seq" + (++plainSeq)));
                        put(HyprlandBindOverrides.comboFor(id, combo), {
                            // `id` stays the NUL-separated self-exclusion token
                            // that rows pass to repeatUsers. `overrideId` is
                            // the bare key OtherBindRow uses; `uid` keeps two
                            // binds of one combo in one file distinct rows.
                            "id": file + "\u0000" + id,
                            "uid": file + "\u0000" + sourceLine + "\u0000" + String(bind?.id ?? ""),
                            "overrideId": id,
                            "label": (bind?.comment ?? "") !== "" ? bind.comment : combo,
                            "file": file,
                            "bind": bind
                        });
                    }
                }
                for (const child of (section?.children ?? [])) walk(child);
            };
            walk(tree);
            for (const [action, entry] of actions) {
                const label = entry.comment !== "" ? entry.comment : action;
                const override = HyprlandBindOverrides.comboFor(action, "");
                if (override !== "") {
                    put(override, { "id": action, "label": label, "file": file, "bind": entry.bind });
                } else {
                    for (const combo of entry.combos) {
                        put(combo, { "id": action, "label": label, "file": file, "bind": entry.bind });
                    }
                }
            }
        };
        collect(root.defaultKeybinds, "main");
        collect(root.userKeybinds, "custom");
        return index;
    }

    // Every combination already spoken for: the indexed combos, the combos of
    // binds hidden with [hidden] and the combos of every emitted bind.
    readonly property var allUsedCombos: {
        const out = new Set();
        for (const combo of root.repeatIndex.keys()) out.add(combo);
        const walk = section => {
            for (const combo of (section?.hiddenCombos ?? [])) out.add(combo);
            for (const bind of (section?.keybinds ?? [])) {
                const combo = root.comboOf(bind);
                if (combo !== "") out.add(combo);
            }
            for (const child of (section?.children ?? [])) walk(child);
        };
        walk(root.keybinds);
        return Array.from(out);
    }

    // The other binds that hold the same combination right now, so a row can
    // show the repeat before the user has to discover it by pressing the key.
    function repeatUsers(combo, selfId) {
        const wanted = String(combo ?? "").trim();
        if (wanted === "") return [];
        return (root.repeatIndex.get(wanted) ?? []).filter(holder => holder.id !== selfId);
    }

    // Flat list of the binds of one category. "" is the uncategorized group.
    function bindsFor(categoryName) {
        const out = [];
        const collect = section => {
            for (const bind of (section?.keybinds ?? [])) out.push(bind);
            for (const child of (section?.children ?? [])) collect(child);
        };
        if (!categoryName) {
            for (const bind of (root.keybinds.keybinds ?? [])) out.push(bind);
            return out;
        }
        for (const section of (root.keybinds.children ?? [])) {
            if (section?.name === categoryName) collect(section);
        }
        return out;
    }

    // ---- loading -----------------------------------------------------------
    FileView {
        id: catalogFile
        path: root.catalogPath
        preload: true

        onLoaded: {
            try {
                root.catalog = JSON.parse(catalogFile.text() ?? "null");
            } catch (e) {
                console.error("[CheatsheetKeybinds] catalog parse failed: " + e);
            }
        }
        onLoadFailed: error => console.error("[CheatsheetKeybinds] catalog load failed: " + error)
    }

    FileView {
        id: overlayFile
        path: root.overlayPath
        preload: true
        watchChanges: true

        onLoaded: {
            root.overlay = KeybindStore.parseOverlay(overlayFile.text() ?? "");
        }
        onFileChanged: root.overlay = KeybindStore.parseOverlay(overlayFile.text() ?? "")
        onLoadFailed: error => {
            // No overlay yet is the normal state on a fresh install.
            if (error === FileViewError.FileNotFound) root.overlay = KeybindStore.newOverlay();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                // The generator rewrites the Lua files, not the catalog; the
                // overlay may still have changed from another process.
                overlayFile.reload();
            }
        }
    }
}
