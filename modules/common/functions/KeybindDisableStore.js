// The recoverable "disabled keybind" block written into a Hyprland config
// when a bind is deleted from the keyboard pane.
//
//   -- >>> end4-pC disabled keybind: <stable-id>
//   -- <original line 1>
//   -- <original line 2>
//   -- <<< end4-pC disabled keybind <<<
//
// A line starting with "-- " is ignored by get_keybinds.py (only "--#/#" is
// special), so the bind disappears from Hyprland and from the pane. The
// original lines are kept verbatim inside the block so restore() can put the
// exact bytes back. Everything outside the block is never rewritten.
//
// Like KeybindStore.js, the logic lives in a plain JavaScript module so it
// can be tested without the Quickshell runtime. No Qt types are used here.

// One-line markers, spelled exactly as they appear on disk. START ends with
// the space before the id, END is a complete line on its own.
var START = "-- >>> end4-pC disabled keybind: ";
var END = "-- <<< end4-pC disabled keybind <<<";
var PREFIX = "-- ";

// Only these characters may appear inside an id: it lives in a "-- " comment
// and must survive a byte-for-byte round-trip through the marker line.
function sanitize(value) {
    return String(value ?? "").replace(/[^A-Za-z0-9_.:-]/g, "_");
}

// The id is derived from the bind itself, never from its line numbers —
// commenting a bind shifts the lines below it, so line numbers cannot be a
// stable identity across reloads. Prefer an action, then a comment, then the
// combination built from the modifiers and the key.
function idForBind(bind, fileLabel) {
    const b = bind ?? {};
    const mods = Array.isArray(b.mods) ? b.mods : [];
    const combo = mods.concat([b.key ?? ""]).join(" + ");
    const action = String(b.action ?? "");
    const comment = String(b.comment ?? "");
    const value = action !== "" ? action : (comment !== "" ? comment : combo);
    return sanitize(fileLabel) + ":" + sanitize(value);
}

function isStartLine(line) {
    return String(line ?? "").indexOf(START) === 0;
}

function idOfStartLine(line) {
    return String(line ?? "").substring(START.length);
}

// Remove the one "-- " we added, leaving the original line exactly as it was
// (including any leading "--" of a "--#/#" placeholder).
function stripPrefix(line) {
    const s = String(line ?? "");
    return s.indexOf(PREFIX) === 0 ? s.substring(PREFIX.length) : s;
}

// Every block in the text, in file order, as {id, lines:[original...]}.
function parseDisabled(text) {
    const lines = String(text ?? "").split("\n");
    const blocks = [];
    for (let i = 0; i < lines.length; ++i) {
        if (!isStartLine(lines[i])) continue;
        const body = [];
        let j = i + 1;
        for (; j < lines.length && lines[j] !== END; ++j) {
            body.push(stripPrefix(lines[j]));
        }
        // A dangling start marker with no END is not a complete block.
        if (j >= lines.length) continue;
        blocks.push({ id: idOfStartLine(lines[i]), lines: body });
        i = j; // skip END so a line inside a body is never re-parsed
    }
    return blocks;
}

function isDisabled(text, id) {
    const wanted = String(id ?? "");
    return parseDisabled(text).some(function(block) {
        return block.id === wanted;
    });
}

// Comment out several ranges in one pass, producing one marker block per
// range, all carrying the same id. This is the batch form used when one
// logical bind owns several source ranges in the same file: the id may only
// be inserted once, so calling disable() for each range would trip its
// already-disabled guard. Ranges are 1-based inclusive and must not overlap.
// All other lines, including the trailing empty element of a final "\n", are
// kept byte-for-byte. Errors are codes the caller translates, as in
// KeybindStore.validate.
function disableAll(text, spec) {
    const source = String(text ?? "");
    const s = spec ?? {};
    const id = String(s.id ?? "");
    const ranges = Array.isArray(s.ranges) ? s.ranges : [];

    if (id === "") return { ok: false, error: "bad-id", text: source };
    if (ranges.length === 0) return { ok: false, error: "no-ranges", text: source };

    const lines = source.split("\n");
    // A trailing "\n" leaves one empty element that is not a bind line.
    let count = lines.length;
    if (count > 0 && lines[count - 1] === "") count -= 1;

    // Validate every range against the original line count before writing,
    // so a bad range leaves the text untouched.
    const normalized = [];
    for (const range of ranges) {
        const line = range?.line;
        const endLine = range?.endLine;
        if (!Number.isInteger(line) || !Number.isInteger(endLine)
            || line < 1 || endLine < line || endLine > count) {
            return { ok: false, error: "bad-range", text: source };
        }
        normalized.push({ line: line, endLine: endLine });
    }
    normalized.sort(function(a, b) { return a.line - b.line; });
    for (let i = 1; i < normalized.length; ++i) {
        if (normalized[i].line <= normalized[i - 1].endLine) {
            return { ok: false, error: "overlapping-range", text: source };
        }
    }
    if (isDisabled(source, id)) {
        return { ok: false, error: "already-disabled", text: source };
    }

    // Work from the bottom up: inserting a block adds two marker lines above
    // it, so applying lower ranges first would invalidate the line numbers of
    // the ranges that follow.
    let out = lines.slice();
    for (let i = normalized.length - 1; i >= 0; --i) {
        const range = normalized[i];
        const original = out.slice(range.line - 1, range.endLine);
        const block = [START + id];
        for (const originalLine of original) block.push(PREFIX + originalLine);
        block.push(END);
        out = out.slice(0, range.line - 1).concat(block, out.slice(range.endLine));
    }
    return { ok: true, error: "", text: out.join("\n") };
}

// The single-range form, kept as the public API of the original store and
// now expressed as the degenerate case of disableAll.
function disable(text, spec) {
    const s = spec ?? {};
    return disableAll(text, {
        id: s.id ?? "",
        ranges: [{ line: s.line, endLine: s.endLine }]
    });
}

// Remove every block with the matching id and restore its original lines in
// place. A grouped id can own several blocks in one file (see disableAll), so
// all of them are unwrapped; other blocks and all untouched bytes stay as they
// were.
function restore(text, id) {
    const source = String(text ?? "");
    const lines = source.split("\n");
    const wanted = String(id ?? "");
    const out = [];
    let found = false;

    for (let i = 0; i < lines.length; ++i) {
        if (isStartLine(lines[i]) && idOfStartLine(lines[i]) === wanted) {
            const body = [];
            let j = i + 1;
            for (; j < lines.length && lines[j] !== END; ++j) {
                body.push(stripPrefix(lines[j]));
            }
            if (j >= lines.length) {
                return { ok: false, error: "malformed-block", text: source };
            }
            for (const originalLine of body) out.push(originalLine);
            i = j; // skip END
            found = true;
            continue;
        }
        out.push(lines[i]);
    }

    if (!found) return { ok: false, error: "not-found", text: source };
    return { ok: true, error: "", text: out.join("\n") };
}
