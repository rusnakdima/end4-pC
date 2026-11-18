pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions
import "../modules/common/functions/KeybindLabels.js" as KeybindLabels

Singleton {
    id: root

    property var entriesByPage: ({})

    readonly property var labelledTypes: [
        "ConfigSwitch", "ConfigSpinBox", "ConfigTextArea", "ConfigSelectionArray",
        "ConfigComboBox", "ConfigSlider", "ConfigSelectionShapeArray", "ConfigRow",
        "ColorSelectionArray", "ContentSubsection"
    ]

    function parsePage(source) {
        const typeOpen = /^\s*([A-Z][\w.]*)\s*\{/;
        const labelProp = /^\s*(title|text):\s*Translation\.tr\(\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\)/;
        const entries = [];
        const stack = [];
        let section = "";
        let subsection = "";
        for (const line of source.split("\n")) {
            const prop = line.match(labelProp);
            const type = stack.length > 0 ? stack[stack.length - 1] : null;
            if (prop && type) {
                const label = (prop[2] ?? prop[3]).replace(/\\(["'])/g, "$1");
                if (type === "ContentSection" && prop[1] === "title") {
                    section = label;
                    subsection = "";
                    entries.push({ kind: "section", section: label, subsection: "", label: label });
                } else if (root.labelledTypes.includes(type)) {
                    entries.push({ kind: "option", section: section, subsection: type === "ContentSubsection" ? "" : subsection, label: label });
                    if (type === "ContentSubsection") subsection = label;
                }
            }
            const opens = (line.match(/\{/g) || []).length;
            const closes = (line.match(/\}/g) || []).length;
            for (let i = 0; i < closes; i++) stack.pop();
            const typeMatch = line.match(typeOpen);
            for (let i = 0; i < opens; i++) stack.push(i === 0 && typeMatch ? typeMatch[1] : null);
        }
        return entries;
    }

    function indexPage(pageId, source) {
        const next = Object.assign({}, root.entriesByPage);
        next[pageId] = root.parsePage(source);
        root.entriesByPage = next;
    }

    // Keybinds are not written as labelled QML controls, so parsePage() never
    // sees them. Build their entries from the same live services the Keyboard
    // page renders instead — the index and the rows then agree on what exists.
    // The labels come from KeybindLabels, which the rows also use as their
    // `title`, so a search result can be handed to ContentPage.goTo() and find
    // the exact row it points at.
    function keybindEntries() {
        const entries = [];
        for (const item of (ManagedKeybinds.editableEntries ?? [])) {
            entries.push({ label: KeybindLabels.managed(item), combo: item?.combo ?? "" });
        }
        for (const item of (HyprlandKeybinds.shellActions ?? [])) {
            entries.push({ label: KeybindLabels.shell(item), combo: (item?.combos ?? []).join(" ") });
        }
        for (const group of (HyprlandKeybinds.otherSections ?? [])) {
            for (const bind of (group?.binds ?? [])) {
                const combo = HyprlandKeybinds.comboOf(bind);
                entries.push({ label: KeybindLabels.other(bind, combo), combo: combo });
            }
        }
        return entries;
    }

    // `includeKeybinds` is opt-in: only the Settings pane search asks for it.
    // The shell-wide launcher calls search() with two arguments, so its results
    // stay exactly as they were.
    function search(query, limit, includeKeybinds) {
        const tokens = query.toLowerCase().trim().split(/\s+/).filter(t => t.length > 0);
        if (tokens.length === 0) return [];

        const results = [];
        for (const page of SettingsPages.pages) {
            const pageName = page.name.toLowerCase();
            const pageScore = root.scoreText(pageName, tokens);
            if (pageScore > 0) {
                results.push({
                    pageId: page.id, pageName: page.name, icon: page.icon,
                    kind: "page", section: "", label: page.name, score: pageScore + 50
                });
            }
            for (const entry of (root.entriesByPage[page.id] ?? [])) {
                const label = Translation.tr(entry.label);
                const section = Translation.tr(entry.section);
                const haystack = (label + " " + entry.label + " " + section + " " + pageName).toLowerCase();
                if (!tokens.every(t => haystack.includes(t))) continue;
                const labelScore = Math.max(
                    root.scoreText(label.toLowerCase(), tokens),
                    root.scoreText(entry.label.toLowerCase(), tokens)
                );
                results.push({
                    pageId: page.id, pageName: page.name, icon: page.icon,
                    kind: entry.kind, section: section, label: label, rawLabel: entry.label, rawSection: entry.section, subsection: Translation.tr(entry.subsection ?? ""), rawSubsection: entry.subsection ?? "",
                    score: labelScore + (entry.kind === "section" ? 10 : 0)
                });
            }
        }

        if (includeKeybinds === true) {
            const keyboardPage = SettingsPages.byId("keyboard");
            const pageName = keyboardPage?.name ?? "Keyboard";
            const section = Translation.tr("Keybinds");
            const haystackPageName = pageName.toLowerCase();
            for (const entry of root.keybindEntries()) {
                const label = entry.label;
                const combo = entry.combo ?? "";
                const haystack = (label + " " + combo + " " + section + " " + haystackPageName).toLowerCase();
                if (!tokens.every(t => haystack.includes(t))) continue;
                const score = Math.max(
                    root.scoreText(label.toLowerCase(), tokens),
                    root.scoreText(combo.toLowerCase(), tokens)
                );
                results.push({
                    pageId: "keyboard", pageName: pageName, icon: "keyboard",
                    kind: "keybind", section: section, label: label, rawLabel: label,
                    subsection: "", rawSubsection: "", score: score
                });
            }
        }

        results.sort((a, b) => b.score - a.score);
        return results.slice(0, limit);
    }

    function scoreText(text, tokens) {
        let score = 0;
        for (const token of tokens) {
            const at = text.indexOf(token);
            if (at < 0) continue;
            if (text === token) score += 100;
            else if (at === 0) score += 60;
            else if (text[at - 1] === " ") score += 40;
            else score += 20;
        }
        return score;
    }

    Instantiator {
        model: SettingsPages.pages
        delegate: FileView {
            required property var modelData
            path: FileUtils.trimFileProtocol(Quickshell.shellPath(modelData.path))
            onLoaded: root.indexPage(modelData.id, text())
        }
    }
}
