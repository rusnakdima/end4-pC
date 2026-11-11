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

    // Everything that is not a shell action, grouped by category.
    readonly property var otherSections: {
        const out = [];
        const collect = section => {
            const binds = (section?.keybinds ?? []).filter(bind => (bind?.action ?? "") === "");
            if (binds.length > 0) out.push({ name: section?.name ?? "", binds: binds });
            for (const child of (section?.children ?? [])) collect(child);
        };
        collect(root.keybinds);
        return out;
    }

    // "SUPER + SHIFT + S" for a bind.
    function comboOf(bind) {
        const mods = bind?.mods ?? [];
        const key = bind?.key ?? "";
        return [...mods, key].filter(part => part !== "").join(" + ");
    }

    // The other shell actions that bind a combination right now, so a row
    // can say which shortcut shares its key. Only shell shortcuts count:
    // the theme deliberately repeats a shortcut's key as a fallback bind
    // (it runs only when the shell is dead), and warning about those would
    // point at the feature the row already describes. Actions are counted
    // through their override, so a rebind shows up here immediately, and
    // the action of the row itself is left out.
    function comboUsers(combo, excludeAction) {
        const wanted = String(combo ?? "").trim();
        if (wanted === "") return [];
        const out = [];
        const seen = new Set();
        for (const entry of root.shellActions) {
            if (entry.action === excludeAction) continue;
            const effective = HyprlandBindOverrides.comboFor(entry.action, entry.combos[0] ?? "");
            if (effective !== wanted) continue;
            const label = (entry.description ?? "") !== "" ? entry.description : entry.action;
            const id = label + "\u0000" + entry.action;
            if (seen.has(id)) continue;
            seen.add(id);
            out.push({ "label": label, "action": entry.action });
        }
        return out;
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

