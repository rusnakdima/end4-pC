pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The system's xkb rule lists: /usr/share/X11/xkb/rules/base.lst names
 * every keyboard layout, variant and option the system can load. The
 * settings pick from these lists instead of asking for a code to be typed,
 * which is where invalid values used to come from.
 *
 * The parsers are plain functions over the file text so the tests can feed
 * them a fixture. A variant list is per layout ("intl" exists for us and
 * for others), and an option without a colon ("grp") is a category header
 * rather than a real option.
 */
Singleton {
    id: root

    // [{ value, displayName }] entries for the dropdowns.
    property var layouts: []
    // [{ variant, layout, displayName }] — layout decides who shows up.
    property var variants: []
    property var options: []
    property bool loaded: false

    // Lines under one "! <section>" marker of a rules list.
    function sectionLines(text, marker) {
        const out = [];
        let inside = false;
        for (const line of String(text ?? "").split("\n")) {
            if (line.startsWith("!")) {
                inside = line.trim() === marker;
                continue;
            }
            if (inside && line.trim() !== "") out.push(line);
        }
        return out;
    }

    // "  us              English (US)" -> { value: "us", displayName: "English (US)" }
    function layoutsFrom(text) {
        const out = [];
        for (const line of root.sectionLines(text, "! layout")) {
            const match = line.match(/^\s*(\S+)\s+(.+)$/);
            if (match) out.push({ "value": match[1], "displayName": match[2].trim() });
        }
        return out;
    }

    // "  intl           us: English (US, intl.)" -> { variant: "intl", layout: "us", ... }
    function variantsFrom(text) {
        const out = [];
        for (const line of root.sectionLines(text, "! variant")) {
            const match = line.match(/^\s*(\S+)\s+(\S+?):?\s+(.+)$/);
            if (match) out.push({ "variant": match[1], "layout": match[2], "displayName": match[3].trim() });
        }
        return out;
    }

    // "  caps:escape    Make Caps Lock an additional Escape" -> { value, displayName }.
    // Colon-less entries ("grp", "custom") are category headers, not options.
    function optionsFrom(text) {
        const out = [];
        for (const line of root.sectionLines(text, "! option")) {
            const match = line.match(/^\s*(\S+)\s+(.+)$/);
            if (match && match[1].includes(":")) out.push({ "value": match[1], "displayName": match[2].trim() });
        }
        return out;
    }

    // The variants of the first layout a value names: "us, ru" shows us
    // variants. Nothing is shown before a layout is chosen, because a bare
    // variant name like "phonetic" belongs to several layouts.
    function variantOptions(layoutValue) {
        const first = String(layoutValue ?? "").split(",")[0].trim();
        if (first === "") return [];
        return root.variantsFor(first)
            .map(entry => ({ "value": entry.variant, "displayName": entry.displayName }));
    }

    // The variants of exactly one layout.
    function variantsFor(layoutCode) {
        return root.variants.filter(entry => entry.layout === layoutCode);
    }

    // One entry per layout position for the variant field. xkb matches the
    // nth variant against the nth layout, so every layout gets its own slot
    // with its own "Default" that clears it, and the chip can say which
    // layout it belongs to ("ru: phonetic").
    function variantEntries(layoutValue) {
        if (!root.loaded) return [];
        const layouts = String(layoutValue ?? "").split(",").map(part => part.trim()).filter(part => part.length > 0);
        const out = [];
        layouts.forEach((layout, slot) => {
            out.push({ "value": "", "displayName": Translation.tr("Default (no variant)"), "slot": slot, "slotLabel": layout });
            for (const entry of root.variantsFor(layout)) {
                out.push({ "value": entry.variant, "displayName": entry.displayName, "slot": slot, "slotLabel": layout });
            }
        });
        return out;
    }

    // The variant string that is actually valid for a layout list: a slot
    // whose variant does not belong to the layout at that position is
    // dropped — xkb rejects the whole keymap for it — and empty trailing
    // slots are trimmed. Before the rule lists load nothing can be judged,
    // so the value passes through untouched.
    function sanitizeVariant(variantValue, layoutValue) {
        const raw = String(variantValue ?? "");
        if (!root.loaded) return raw;
        const layouts = String(layoutValue ?? "").split(",").map(part => part.trim()).filter(part => part.length > 0);
        const parts = raw.split(",").map(part => part.trim());
        const out = [];
        layouts.forEach((layout, slot) => {
            const variant = parts[slot] ?? "";
            if (variant === "") {
                out.push("");
                return;
            }
            out.push(root.variantsFor(layout).some(entry => entry.variant === variant) ? variant : "");
        });
        while (out.length > 0 && out[out.length - 1] === "") out.pop();
        return out.join(",");
    }

    function applyRules(text) {
        root.layouts = root.layoutsFrom(text);
        root.variants = root.variantsFrom(text);
        root.options = root.optionsFrom(text);
        root.loaded = true;
    }

    FileView {
        id: rulesFile
        path: "/usr/share/X11/xkb/rules/base.lst"
        preload: true
        onLoaded: root.applyRules(text())
        onLoadFailed: {
            // Not every install ships base.lst; evdev is the same list
            // under the name the system rules actually use.
            if (rulesFile.path.endsWith("base.lst")) {
                rulesFile.path = "/usr/share/X11/xkb/rules/evdev.lst";
            } else {
                root.applyRules("");
            }
        }
    }
}
