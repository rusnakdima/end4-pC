// Legacy Lua managed-block helpers, followed by the JSON overlay store the
// live settings path actually uses.
//
// The first half still parses/renders the old "-- >>> end4-pC managed
// keybinds" region because tst_keybindstore.qml exercises it. Nothing in the
// live path writes that region any more: generated Lua files are rewritten
// wholesale by the catalog generator, so every user change goes into the
// overlay below instead.
//
// The logic lives in a plain JavaScript module so that it can be tested
// without the Quickshell runtime, like KeyCombos.js.

var MARKER_START = "-- >>> end4-pC managed keybinds >>>";
var MARKER_END = "-- <<< end4-pC managed keybinds <<<";
var ID_PREFIX = "-- panel-id: ";

// "--##! Media" -> ["Media"]; the same regex get_keybinds.py uses for the
// scope, so a category the panel writes is a category the parser reads.
var HEADING_RE = /^--##!\s*(.*)$/;
var ID_RE = /^--\s*panel-id:\s*(\S+)\s*$/;
// One full line: hl.bind("<combo>", hl.dsp.exec_cmd("<command>"), {description = "<name>"})
// with Lua-escaped strings inside the quotes.
var BIND_RE = /^\s*hl\.bind\("([^"]*)",\s*hl\.dsp\.exec_cmd\("((?:[^"\\]|\\.)*)"\),\s*\{\s*description\s*=\s*"((?:[^"\\]|\\.)*)"\s*\}\s*\)\s*$/;

// A short stable id for a new entry: lowercase letters and digits only, so
// it survives the "-- panel-id:" round-trip and never needs escaping.
function newId() {
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}

// The value as it goes between the quotes of a Lua string.
function escapeString(text) {
    return String(text ?? "")
        .replace(/[\r\n]+/g, " ")
        .replace(/\\/g, "\\\\")
        .replace(/"/g, "\\\"");
}

// The value back out of a Lua string: any escaped character becomes the
// character itself ("\"" -> "\"", "\\" -> "\").
function unescapeString(text) {
    return String(text ?? "").replace(/\\(.)/g, "$1");
}

// Why an entry cannot be saved, or "" when it can. Codes, not sentences:
// the caller translates them. The name must not contain a double quote
// because get_keybinds.py reads it back with description = "([^"]+)".
function validate(entry) {
    const name = String(entry?.name ?? "");
    const command = String(entry?.command ?? "");
    const category = String(entry?.category ?? "");
    const combo = String(entry?.combo ?? "");
    if (name.trim() === "") return "empty-name";
    if (name.includes('"')) return "quote-name";
    if (/[\r\n]/.test(name)) return "newline-name";
    if (command.trim() === "") return "empty-command";
    if (/[\r\n]/.test(command)) return "newline-command";
    if (/[\r\n]/.test(category)) return "newline-category";
    if (combo.trim() === "") return "empty-combo";
    return "";
}

// The category groups in the order they first appear, with the empty
// category first: entries without a heading are written before any
// "--##!" line, so they never fall into the section of a heading above.
function groupOrder(entries) {
    const order = [];
    const seen = [];
    if (entries.some(entry => String(entry?.category ?? "").trim() === ""))
        order.push("");
    for (const entry of entries) {
        const category = String(entry?.category ?? "").trim();
        if (category !== "" && seen.indexOf(category) === -1) {
            seen.push(category);
            order.push(category);
        }
    }
    return order;
}

// The whole block, markers included, ending with a newline. Raw lines the
// parser did not recognise are kept verbatim inside their group, so a
// hand-written line between the markers is never silently dropped.
function renderBlock(entries) {
    const lines = [MARKER_START];
    const list = entries ?? [];
    for (const category of groupOrder(list)) {
        if (category !== "") lines.push("--##! " + category);
        for (const entry of list) {
            const entryCategory = String(entry?.category ?? "").trim();
            if (entryCategory !== category) continue;
            if (typeof entry?.raw === "string" && entry.raw !== "") {
                lines.push(entry.raw);
                continue;
            }
            lines.push(ID_PREFIX + String(entry?.id ?? ""));
            lines.push("hl.bind(\"" + escapeString(entry?.combo) + "\", hl.dsp.exec_cmd(\""
                + escapeString(entry?.command) + "\"), {description = \""
                + escapeString(entry?.name) + "\"})");
        }
    }
    lines.push(MARKER_END);
    return lines.join("\n") + "\n";
}

// The entries between the markers, in file order. The category comes from
// the nearest heading above, the id from the nearest panel-id comment; a
// line that is neither comes back as {raw}, preserved but not editable.
function parseBlock(text) {
    const source = String(text ?? "");
    const start = source.indexOf(MARKER_START);
    if (start === -1) return [];
    const afterStart = start + MARKER_START.length;
    const end = source.indexOf(MARKER_END, afterStart);
    const region = source.slice(afterStart, end === -1 ? source.length : end);

    // 1-based line number of the line that holds the start marker. region
    // begins with the rest of that line, so region line i sits on markerLine+i;
    // a bind's line/endLine then matches the numbers get_keybinds.py stamps on
    // it, which is what entryForSource matches against.
    const markerLine = source.slice(0, start).split("\n").length;
    const regionLines = region.split("\n");

    const entries = [];
    let category = "";
    let pendingId = null;
    for (let i = 0; i < regionLines.length; i++) {
        const line = regionLines[i];
        const trimmed = line.trim();
        const lineNo = markerLine + i;
        if (trimmed === "") continue;
        const heading = HEADING_RE.exec(trimmed);
        if (heading !== null) {
            category = heading[1].trim();
            pendingId = null;
            continue;
        }
        const idLine = ID_RE.exec(trimmed);
        if (idLine !== null) {
            pendingId = idLine[1];
            continue;
        }
        const bind = BIND_RE.exec(line);
        if (bind !== null) {
            entries.push({
                id: pendingId !== null && pendingId !== "" ? pendingId : newId(),
                combo: bind[1],
                command: unescapeString(bind[2]),
                name: unescapeString(bind[3]),
                category: category,
                line: lineNo,
                endLine: lineNo
            });
            pendingId = null;
            continue;
        }
        entries.push({
            id: newId(),
            raw: line.replace(/\r$/, ""),
            category: category,
            name: "",
            command: "",
            combo: "",
            line: lineNo,
            endLine: lineNo
        });
    }
    return entries;
}

// =====================================================================
// JSON overlay store (the current, overlay-backed keybind path)
// =====================================================================
// The functions above are kept intact because tst_keybindstore.qml still
// exercises the legacy Lua managed block. The live settings path below uses
// ~/.config/hypr/custom/keybind-overlay.json instead: Settings writes only
// this file, and scripts/hyprland/generate_keybinds.py turns the frozen
// catalog plus this overlay into the two Lua files Hyprland actually loads.
//
// Overlay shape (see the generator):
//   { "overrides": { "<bind-id>": { combo, description, category,
//                                    dispatch, options, enabled } },
//     "adds": [ { id, category, combo, description, dispatch, options,
//                 code } ],
//     "disabled": [ "<bind-id>", ... ],
//     "seriesOverrides": { "<seriesId>": { mods, enabled } } }
//
// `seriesOverrides` is optional: raw binds emit their Lua verbatim, so a
// per-bind combo override cannot move them. One series edit rewrites the
// modifier prefix of every member in the generator instead.

var OVERLAY_DEFAULT = { overrides: {}, adds: [], disabled: [] };

function newOverlay() {
    return { overrides: {}, adds: [], disabled: [] };
}

// An overlay with no series edits keeps the original three-section shape the
// generator and the older round-trip tests expect.
function hasSeriesOverrides(overlay) {
    const value = overlay?.seriesOverrides;
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

// Parse the overlay defensively: a partial or hand-broken file must not take
// the settings page down. Anything unrecognised falls back to empty sections.
function parseOverlay(text) {
    const result = newOverlay();
    if (typeof text !== "string" || text.trim() === "") return result;
    try {
        const parsed = JSON.parse(text);
        if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return result;
        if (parsed.overrides !== null && typeof parsed.overrides === "object"
                && !Array.isArray(parsed.overrides))
            result.overrides = parsed.overrides;
        if (Array.isArray(parsed.adds)) result.adds = parsed.adds;
        if (Array.isArray(parsed.disabled)) result.disabled = parsed.disabled;
        if (hasSeriesOverrides(parsed)) result.seriesOverrides = parsed.seriesOverrides;
    } catch (e) {
        console.error("[KeybindStore] overlay parse failed: " + e);
    }
    return result;
}

// A stable, readable JSON document. JSON.parse can read it back verbatim, so
// there is no marker splicing to get wrong.
function renderOverlay(data) {
    const overlay = data ?? newOverlay();
    const out = {
        overrides: overlay.overrides ?? {},
        adds: overlay.adds ?? [],
        disabled: overlay.disabled ?? []
    };
    if (hasSeriesOverrides(overlay)) out.seriesOverrides = overlay.seriesOverrides;
    return JSON.stringify(out, null, 2) + "\n";
}

// Lua string literal, used for the `code` fallback emitted for new binds.
function luaLiteral(text) {
    return '"' + String(text ?? "")
        .replace(/\\/g, "\\\\")
        .replace(/"/g, '\\"')
        .replace(/\r/g, "\\r")
        .replace(/\n/g, "\\n")
        .replace(/\t/g, "\\t") + '"';
}

// The overlay's flat, effective bind list: the frozen catalog with disabled
// binds removed and overrides applied, then the user's adds appended. This is
// the single list Settings and HyprlandKeybinds both read from.
function effectiveBinds(catalog, overlay) {
    const ov = overlay ?? newOverlay();
    const overrides = ov.overrides ?? {};
    const adds = ov.adds ?? [];
    const disabled = new Set(ov.disabled ?? []);
    const out = [];
    for (const b of (catalog?.binds ?? [])) {
        if (disabled.has(b.id)) continue;
        const override = overrides[b.id];
        if (override && override.enabled === false) continue;
        const next = Object.assign({}, b);
        if (override) {
            // Remember the frozen combo: the UI uses it as the identity of a
            // row (and as the reset target) while `combo` below is what the
            // generator actually emits from the overlay.
            next.originalCombo = b.combo;
            // Only these fields are user-editable. `code`, `source`, `line`
            // and the dispatch of a command bind stay with the frozen catalog.
            // A raw bind is exempt: the generator emits its code verbatim and
            // rejects such an override, so honouring it here would drift.
            if (!isRawBind(b)) {
                for (const key of ["combo", "description", "category", "dispatch", "options"]) {
                    if (Object.prototype.hasOwnProperty.call(override, key)) next[key] = override[key];
                }
            }
        }
        // A series edit moves every member's combo in lockstep with the raw
        // Lua the generator emits. The frozen combo is kept as originalCombo
        // so rows still have a stable identity and a reset target.
        const sid = String(b.seriesId ?? "");
        if (sid !== "") {
            const spec = seriesOverrideOf(ov, sid);
            next.seriesEnabled = spec.enabled !== false;
            const mods = String(spec.mods ?? "");
            if (mods !== "") {
                if (next.originalCombo === undefined) next.originalCombo = b.combo;
                next.combo = applySeriesMods(next.combo, mods);
            }
        }
        out.push(next);
    }
    for (const a of adds) {
        const next = Object.assign({}, a);
        if (next.source === undefined) next.source = "custom";
        if (next.options === undefined) next.options = {};
        if (next.description === undefined) next.description = next.name ?? "";
        if (next.category === undefined) next.category = "";
        if (next.dispatch === undefined)
            next.dispatch = { kind: "command", id: next.id ?? "", command: next.command ?? "" };
        out.push(next);
    }
    return out;
}

// The overlay `adds` entry for a form entry. `code` is the legacy-mode
// fallback: the generator emits it verbatim for command binds when it runs
// with --exec-mode legacy, while `dispatch.id` serves the bridge mode.
function makeAdd(entry, id) {
    const newId = String(id ?? entry?.id ?? "");
    const combo = String(entry?.combo ?? "");
    const command = String(entry?.command ?? entry?.dispatch?.command ?? "");
    const name = String(entry?.name ?? entry?.description ?? "");
    return {
        id: newId,
        category: String(entry?.category ?? ""),
        combo: combo,
        description: name,
        dispatch: { kind: "command", id: newId, command: command },
        options: {},
        source: "custom",
        code: "hl.bind(" + luaLiteral(combo) + ", hl.dsp.exec_cmd(" + luaLiteral(command)
            + "), { description = " + luaLiteral(name) + " })"
    };
}

// The editable view of an add: the form and the filter still speak
// name/command, while the overlay file stores description/dispatch.
function addToEntry(add) {
    return {
        id: String(add?.id ?? ""),
        name: String(add?.description ?? add?.name ?? ""),
        category: String(add?.category ?? ""),
        combo: String(add?.combo ?? ""),
        command: String(add?.dispatch?.command ?? add?.command ?? ""),
        code: String(add?.code ?? ""),
        raw: false
    };
}

// Immutable updates, so a rejected write never leaves a half-mutated overlay.
function withAdds(overlay, adds) {
    const next = newOverlay();
    next.overrides = overlay?.overrides ?? {};
    next.disabled = overlay?.disabled ?? [];
    if (hasSeriesOverrides(overlay)) next.seriesOverrides = overlay.seriesOverrides;
    next.adds = adds;
    return next;
}

function withOverrides(overlay, overrides) {
    const next = newOverlay();
    next.adds = overlay?.adds ?? [];
    next.disabled = overlay?.disabled ?? [];
    if (hasSeriesOverrides(overlay)) next.seriesOverrides = overlay.seriesOverrides;
    next.overrides = overrides;
    return next;
}

// --- multi-bind series overrides --------------------------------------------
// A series is a set of raw catalog binds sharing a `seriesId`. The generator
// rewrites each member's stored Lua `code` and combo from one
// seriesOverrides[sid].mods value, so the helpers below keep that extra
// overlay section optional and immutable just like overrides/adds/disabled.

function seriesOverrideOf(overlay, seriesId) {
    const id = String(seriesId ?? "");
    if (id === "") return {};
    const spec = (overlay?.seriesOverrides ?? {})[id];
    if (spec === null || typeof spec !== "object" || Array.isArray(spec)) return {};
    return Object.assign({}, spec);
}

// A null/undefined patch value clears that field; an empty spec removes the
// series id entirely. Other series and the three original sections survive.
function withSeriesOverride(overlay, seriesId, patch) {
    const id = String(seriesId ?? "");
    const next = newOverlay();
    next.overrides = overlay?.overrides ?? {};
    next.adds = overlay?.adds ?? [];
    next.disabled = overlay?.disabled ?? [];
    const series = Object.assign({}, overlay?.seriesOverrides ?? {});
    const spec = Object.assign({}, series[id] ?? {});
    for (const key of Object.keys(patch ?? {})) {
        const value = patch[key];
        if (value === null || value === undefined) delete spec[key];
        else spec[key] = value;
    }
    if (Object.keys(spec).length === 0) delete series[id];
    else series[id] = spec;
    if (Object.keys(series).length > 0) next.seriesOverrides = series;
    return next;
}

// Mirror the generator's series-combo rewrite. For `code:N` binds everything
// before the first `code:` is replaced by the series modifier prefix. Plain
// numbered binds (e.g. `SUPER + 1`) keep their last token and only swap the
// modifier prefix (`CTRL + 1`).
function applySeriesMods(combo, mods) {
    const prefix = String(mods ?? "");
    const value = String(combo ?? "");
    if (prefix === "") return value;
    if (value.indexOf("code:") !== -1) {
        return value.replace(/^(.*?)(code:)/,
            (match, before, code) => prefix + " + " + code);
    }
    const parts = value.split(" + ")
        .map(part => part.trim()).filter(part => part !== "");
    if (parts.length < 2) return prefix + " + " + value;
    return prefix + " + " + parts[parts.length - 1];
}

function comboMods(combo) {
    const parts = String(combo ?? "").split(" + ")
        .map(part => part.trim()).filter(part => part !== "");
    if (parts.length < 2) return "";
    return parts.slice(0, -1).join(" + ");
}

// Display-only label for a `code:N` token. Capture still produces Qt key
// names for NEW binds; this only makes a catalog bind's own keyLabel ("1",
// "Num 7") readable in the settings rows and key caps.
function displayCombo(bind, combo) {
    const label = String(bind?.keyLabel ?? "");
    const parts = String(combo ?? bind?.combo ?? "").split(" + ")
        .map(part => part.trim()).filter(part => part !== "");
    if (label === "") return parts.join(" + ");
    return parts.map(part => /^code:/.test(part) ? label : part).join(" + ");
}

// One logical row per series, in catalog order. `binds` are the effective
// binds, so a member's combo already reflects any series mods rewrite.
function groupBySeries(binds, overlay) {
    const groups = [];
    const byId = new Map();
    for (const b of (binds ?? [])) {
        const id = String(b?.seriesId ?? "");
        if (id === "") continue;
        let group = byId.get(id);
        if (group === undefined) {
            const spec = seriesOverrideOf(overlay, id);
            const combo = String(b.combo ?? "");
            group = {
                seriesId: id,
                seriesLabel: String(b.seriesLabel ?? id),
                count: 0,
                mods: comboMods(combo),
                defaultMods: comboMods(String(b.originalCombo ?? combo)),
                enabled: spec.enabled !== false,
                overridden: Object.keys(spec).length > 0,
                memberLabels: "",
                members: []
            };
            byId.set(id, group);
            groups.push(group);
        }
        const parts = String(b.combo ?? "").split(" + ");
        const keyLabel = String(b.keyLabel ?? parts[parts.length - 1] ?? "");
        group.count += 1;
        group.memberLabels += (group.memberLabels === "" ? "" : ", ") + keyLabel;
        group.members.push({
            id: String(b.id ?? ""),
            keyLabel: keyLabel,
            combo: String(b.combo ?? ""),
            displayCombo: displayCombo(b, b.combo)
        });
    }
    return groups;
}

// Immutable update of the overlay's `disabled` array — the contract the
// generator already honours. Adding a catalog id there omits the bind from the
// generated Lua entirely; removing it restores it. Nothing is ever written to
// a generated file, so a later overlay save cannot undo a delete.
function withDisabled(overlay, id, disabled) {
    const wanted = String(id ?? "");
    const next = newOverlay();
    next.overrides = overlay?.overrides ?? {};
    next.adds = overlay?.adds ?? [];
    if (hasSeriesOverrides(overlay)) next.seriesOverrides = overlay.seriesOverrides;
    const ids = (overlay?.disabled ?? []).filter(item => String(item ?? "") !== wanted);
    if (disabled === true) ids.push(wanted);
    next.disabled = ids;
    return next;
}

function isDisabled(overlay, id) {
    const wanted = String(id ?? "");
    return (overlay?.disabled ?? []).some(item => String(item ?? "") === wanted);
}

// A raw bind's `code` is emitted verbatim, so a combo override cannot be
// applied to it: the generator rejects the overlay and the cheatsheet would
// drift from what Hyprland loaded. The UI uses this to refuse combo editing
// before writing anything.
function isRawBind(bind) {
    const kind = String(bind?.dispatch?.kind ?? "");
    return kind === "raw";
}

// Look up a catalog bind by its stable id, or null when the id is unknown.
function catalogBind(catalog, id) {
    const wanted = String(id ?? "");
    for (const bind of (catalog?.binds ?? [])) {
        if (String(bind?.id ?? "") === wanted) return bind;
    }
    return null;
}

// A narrow override patch: only combo/description/category/enabled are ever
// written. A command bind's dispatch and options stay untouched.
function comboOverride(combo) {
    return { combo: String(combo ?? "") };
}

// The file with only the marker region replaced. The block is appended
// (after a blank line) when the markers are missing, and a dangling start
// marker is healed by treating everything to the end of file as the block.
function splice(text, block) {
    const source = String(text ?? "");
    const start = source.indexOf(MARKER_START);
    if (start === -1) {
        if (source === "") return String(block);
        const base = source.endsWith("\n") ? source : source + "\n";
        return base + "\n" + String(block);
    }
    const afterStart = start + MARKER_START.length;
    let end = source.indexOf(MARKER_END, afterStart);
    let cutEnd;
    if (end === -1) {
        cutEnd = source.length;
    } else {
        cutEnd = end + MARKER_END.length;
        if (source.charAt(cutEnd) === "\n") cutEnd += 1;
    }
    return source.slice(0, start) + String(block) + source.slice(cutEnd);
}
