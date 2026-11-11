pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses the `get_keybinds.py` script to parse comments in config files in a certain format and convert to JSON.
 */
Singleton {
    id: root
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
    property var defaultKeybinds: {"children": []}
    property var userKeybinds: {"children": []}
    property var keybinds: ({
        name: "",
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
    // which holds the binds that sit above the first section marker.
    readonly property var categories: {
        const names = [""];
        for (const section of (root.keybinds.children ?? [])) {
            const name = section?.name ?? "";
            if (name !== "" && !names.includes(name)) names.push(name);
        }
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

    // Everything that is not a shell action, grouped by category. Each bind
    // carries the file it came from ("main" for hyprland/keybinds.lua,
    // "custom" for custom/keybinds.lua) so a repeat warning can say where
    // the other holder lives.
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

    // Every combination with the binds that hold it, counted across both
    // config files (the theme's hyprland/keybinds.lua and the user's
    // custom/keybinds.lua) and through their overrides. Two holders means a
    // real repeat: pressing the key dispatches both binds. A shell shortcut
    // contributes its displayed combination (or, without an override, each
    // of its aliases, because every line of it stays bound); a plain bind
    // contributes the combination the overrides file may have moved it to.
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
            const walk = section => {
                for (const bind of (section?.keybinds ?? [])) {
                    const action = bind?.action ?? "";
                    const combo = root.comboOf(bind);
                    if (action !== "") {
                        if (!actions.has(action)) actions.set(action, { combos: [], comment: bind?.comment ?? "" });
                        const entry = actions.get(action);
                        if (!entry.combos.includes(combo)) entry.combos.push(combo);
                    } else {
                        const id = "bind_" + combo.replace(/[^A-Za-z0-9_]/g, "_");
                        put(HyprlandBindOverrides.comboFor(id, combo), {
                            "id": file + "\u0000" + id,
                            "label": (bind?.comment ?? "") !== "" ? bind.comment : combo,
                            "file": file
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
                    // The override moves every line of the action onto one key.
                    put(override, { "id": action, "label": label, "file": file });
                } else {
                    // Without one each line keeps its own key, and an alias
                    // is a real binding that can be repeated too.
                    for (const combo of entry.combos) {
                        put(combo, { "id": action, "label": label, "file": file });
                    }
                }
            }
        };
        collect(root.defaultKeybinds, "main");
        collect(root.userKeybinds, "custom");
        return index;
    }

    // The other binds that hold the same combination right now, so a row can
    // show the repeat before the user has to discover it by pressing the
    // key. selfId keeps the row itself out: the action name for a shortcut
    // row, "file\0bind_<key>" for a plain bind row (the same combination can
    // be written in both config files, and those are two different binds).
    function repeatUsers(combo, selfId) {
        const wanted = String(combo ?? "").trim();
        if (wanted === "") return [];
        return (root.repeatIndex.get(wanted) ?? []).filter(holder => holder.id !== selfId);
    }

    // Flat list of the binds of one category. "" is the uncategorized group
    // (the binds that sit above the first section marker).
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

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getDefaultKeybinds.running = true
                getUserKeybinds.running = true
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.defaultKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.defaultKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.userKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}

