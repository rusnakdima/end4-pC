// The pure logic behind the "conflicts" part of the keyboard pane.
//
// HyprlandKeybinds.repeatIndex is a Map of combo -> holders, where a holder is
// {id, label, file, bind?}. Two or more holders on one combo is a real repeat:
// pressing the key dispatches every bind that holds it. allUsedCombos is the
// union of those combos, the hidden combos and every emitted bind's combo, so
// a suggestion only has to avoid what is in that set.
//
// No Qt or Quickshell imports: like KeybindStore.js and KeyCombos.js this is a
// plain JavaScript module, imported from QML with
//   import "modules/common/functions/KeybindConflicts.js" as Conflicts
// and testable without a running shell.

// Modifiers in the order suggestions are offered, after the seed's own
// modifier set. A combo is "<modifier> + <key>", and "<modifier>" may itself
// be several modifiers joined by " + " (e.g. "SUPER + SHIFT").
var MODIFIER_ORDER = [
    "SUPER", "SUPER + SHIFT", "SUPER + CTRL", "SUPER + ALT",
    "CTRL", "CTRL + SHIFT", "ALT", "ALT + SHIFT"
];

// Candidate keys, in the order suggestions are offered within one modifier.
var KEY_ORDER = [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
];

// A holder as the caller needs it: identity, label and file only. The
// underlying bind object is deliberately dropped so a returned group is plain
// data. Two extra identity fields survive the projection:
//   uid        - distinct per source line for plain binds. Two plain binds on
//                one combo in one file share `id` (repeatUsers needs that),
//                but keeper selection must still tell them apart.
//   overrideId - the key the overrides file actually uses for a plain bind:
//                the bare "bind_<combo>", with no file prefix and no NUL.
function project(holder) {
    return {
        id: holder?.id ?? "",
        uid: holder?.uid ?? "",
        overrideId: holder?.overrideId ?? "",
        combo: holder?.combo ?? "",
        label: holder?.label ?? "",
        file: holder?.file ?? ""
    };
}

// The identity that picks one holder out of a group. Plain bind holders carry
// a uid; shell actions and legacy holders fall back to id.
function identityOf(holder) {
    const uid = String(holder?.uid ?? "");
    return uid !== "" ? uid : String(holder?.id ?? "");
}

// The combos with two or more holders, as {combo, holders} groups sorted by
// combo. A combo with a single holder is not a conflict and is left out.
// Accepts a Map (the shape of repeatIndex) and, defensively, a plain object.
function groupsFrom(repeatIndex, aliasIndex) {
    const groups = [];
    if (repeatIndex !== null && repeatIndex !== undefined) {
        const visit = (combo, holders) => {
            const list = Array.from(holders ?? []);
            if (list.length < 2) return;
            groups.push({ kind: "combo", combo: String(combo ?? ""), holders: list.map(project) });
        };

        if (typeof repeatIndex.forEach === "function") {
            repeatIndex.forEach((holders, combo) => visit(combo, holders));
        } else {
            for (const combo of Object.keys(repeatIndex)) visit(combo, repeatIndex[combo]);
        }
    }

    groups.sort((a, b) => a.combo < b.combo ? -1 : (a.combo > b.combo ? 1 : 0));

    // One action bound to several combinations is the second kind of
    // conflict: only one of its combos can be the one the user means. Each
    // alias holder is identified by action + NUL + combo, so every combo of
    // the action can be kept or removed independently.
    if (aliasIndex === null || aliasIndex === undefined) return groups;

    const aliasGroups = [];
    const addAlias = (key, entry) => {
        const action = String(entry?.action ?? key ?? "");
        const combos = Array.from(entry?.combos ?? []);
        if (action === "" || combos.length < 2) return;
        aliasGroups.push({
            kind: "alias",
            combo: String(combos[0]?.combo ?? ""),
            action: action,
            label: String(entry?.label ?? ""),
            holders: combos.map(comboEntry => {
                const combo = String(comboEntry?.combo ?? "");
                return {
                    id: action,
                    uid: action + "\u0000" + combo,
                    combo: combo,
                    label: String(comboEntry?.bind?.comment || entry?.label || action),
                    file: "shell",
                    catalogIds: comboEntry?.bind?.id ? [comboEntry.bind.id] : []
                };
            })
        });
    };

    if (typeof aliasIndex.forEach === "function") {
        aliasIndex.forEach((entry, key) => addAlias(key, entry));
    } else {
        for (const key of Object.keys(aliasIndex)) addAlias(key, aliasIndex[key]);
    }

    aliasGroups.sort((a, b) => a.action < b.action ? -1 : (a.action > b.action ? 1 : 0));
    return groups.concat(aliasGroups);
}

// Split a group around the holder the user chose to keep: keeper is that
// holder, others are every holder that must be removed or reassigned. The
// selector is identityOf(holder) — uid when present — so two plain binds with
// the same id are still two independent rows. An unknown selector picks
// nothing and leaves all holders in others.
function chooseKeeper(group, keeperId) {
    const holders = Array.from(group?.holders ?? []);
    const wanted = String(keeperId ?? "");
    const keeper = holders.find(holder => identityOf(holder) === wanted) ?? null;
    const others = holders.filter(holder => identityOf(holder) !== wanted);
    return { keeper: keeper, others: others };
}

// The modifier part of a combo ("SUPER + SHIFT" for "SUPER + SHIFT + A"):
// everything before the final " + ". A bare key ("F7") has no modifier set.
function modifierSetOf(combo) {
    const parts = String(combo ?? "").split(" + ").map(part => part.trim()).filter(part => part !== "");
    if (parts.length <= 1) return "";
    return parts.slice(0, parts.length - 1).join(" + ");
}

// Deterministic free-combo suggestions: up to `count` combos that are not in
// usedCombos. The seed's modifier set is tried first (so a replacement stays
// close to the key the user is used to), then the fixed MODIFIER_ORDER, and
// within each modifier the fixed KEY_ORDER. When fewer than `count` combos
// are free, only the free ones are returned; when none are, [].
function freeCombos(usedCombos, count, seedCombo) {
    const wanted = Math.max(0, Math.floor(Number(count) || 0));
    if (wanted === 0) return [];

    const used = new Set();
    if (usedCombos !== null && usedCombos !== undefined) {
        for (const combo of usedCombos) used.add(String(combo ?? ""));
    }

    // Prefer the seed's modifiers, then the standard order without repeats.
    const modifiers = [];
    const seedModifiers = modifierSetOf(seedCombo);
    if (seedModifiers !== "") modifiers.push(seedModifiers);
    for (const modifier of MODIFIER_ORDER) {
        if (modifiers.indexOf(modifier) === -1) modifiers.push(modifier);
    }

    const out = [];
    for (const modifier of modifiers) {
        for (const key of KEY_ORDER) {
            const combo = modifier + " + " + key;
            if (used.has(combo)) continue;
            out.push(combo);
            if (out.length >= wanted) return out;
        }
    }
    return out;
}

// A duplicate combo may belong to a shell action that also has other combos.
// repeatIndex records such an action with its first bind; the conflict is on
// group.combo, so resolve the bind that actually owns that combo before the
// caller deletes or moves it. Non-combo (alias) groups keep the original.
function targetHolder(group, holder, actionData, comboOf) {
    if (String(group?.kind ?? "") !== "combo") return holder;
    const combo = String(group?.combo ?? "");
    if (combo === "") return holder;
    const binds = Array.from(actionData?.binds ?? []);
    const bind = binds.find(candidate => String(comboOf(candidate) ?? "") === combo) ?? null;
    if (bind === null) return holder;
    return Object.assign({}, holder, { bind: bind, overrideId: String(bind?.id ?? "") });
}

// A write can be accepted by the service before FileView reports the disk
// result. Treat a recorded save error as failure even when result.ok is true.
function writeSucceeded(result, lastSaveError) {
    const resultOk = !(result && result.ok === false);
    return resultOk && String(lastSaveError ?? "") === "";
}

// Move one holder onto `combo`. Both services and the managed-entry lookup are
// injected so this stays pure and the fix decision is testable without Qt: the
// caller passes ManagedKeybinds.entryForSource, ManagedKeybinds and
// HyprlandBindOverrides, while the hosted test passes stubs. One call moves
// exactly one holder, through exactly one service — a group with several
// other holders makes one of these calls per holder, one write per click.
//
// Returns "managed" or "override" so the caller can confirm a write happened.
// Returns {kind, ok, error}: a failed write must never be reported as a
// resolved conflict. Services that return nothing (older stubs) count as ok.
function fixHolder(holder, combo, entryForSource, managed, overrides) {
    const entry = entryForSource(holder?.bind) ?? null;
    if (entry !== null) {
        const result = managed.update(entry.id, { combo: combo });
        return {
            kind: "managed",
            ok: !(result && result.ok === false),
            error: String(result?.error ?? "")
        };
    }
    // A plain bind's `id` is "file\0bind_<combo>" — a self-exclusion token,
    // not an overrides key. Writing it would put a NUL in the config and the
    // row would never see the new combo. The bare overrideId is the key
    // OtherBindRow/clearOverride use; legacy callers without one keep id.
    const result = overrides.setOverride(String(holder?.overrideId || holder?.id || ""), combo);
    return {
        kind: "override",
        ok: !(result && result.ok === false),
        error: String(result?.error ?? "")
    };
}

// Split a group into the holder to keep and the holders to remove, in the
// shape the Settings panel consumes. Works for both conflict kinds.
function removalPlan(group, keeperId) {
    const chosen = chooseKeeper(group, keeperId);
    return { kind: String(group?.kind ?? "combo"), keeper: chosen.keeper, remove: chosen.others };
}
