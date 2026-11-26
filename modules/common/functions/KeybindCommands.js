// Helpers for the command keybinds shown in the Settings "Commands" section.
// A command bind is a catalog or overlay bind whose dispatch runs a saved
// command. Built-in commands must stay in the picker after their bind is
// deleted, so the delete plan distinguishes an overlay add from a catalog bind.

// Only binds with a real command and a "Category: Label" description belong in
// the Commands list. Other dispatches (global theme actions, raw Lua) are
// managed by their own sections.
function commandEntries(binds) {
    const out = [];
    for (const bind of (binds ?? [])) {
        const dispatch = bind?.dispatch ?? {};
        const command = String(dispatch.command ?? "");
        const description = String(bind?.description ?? "");
        if (dispatch.kind !== "command" || command === "") continue;
        const separator = description.indexOf(": ");
        if (separator <= 0) continue;
        out.push({
            bind: bind,
            id: String(bind?.id ?? ""),
            label: description.slice(separator + 2),
            command: command,
            combo: String(bind?.combo ?? ""),
            description: description,
            category: description.slice(0, separator)
        });
    }
    return out;
}

// An effective bind from KeybindStore has no sourcePath for an overlay add,
// so the service's source lookup cannot find it. Match the overlay entry by
// id first; only catalog binds need the source-path lookup.
function sourceEntryFor(bind, entries, entryForSource) {
    const id = String(bind?.id ?? "");
    if (id !== "") {
        const entry = (entries ?? []).find(item => String(item?.id ?? "") === id) ?? null;
        if (entry !== null) return entry;
    }
    return entryForSource(bind) ?? null;
}

// An overlay add owns its generated command entry: removing the add drops the
// command too. A catalog bind is frozen, so only its bind can be disabled;
// the generated command stays and can be reused by a new bind.
function deletePlan(bind, entryForSource) {
    const entry = entryForSource(bind) ?? null;
    const description = String(bind?.description ?? "");
    if (entry !== null) {
        return {
            kind: "add",
            id: String(entry.id ?? ""),
            label: description,
            binds: [bind]
        };
    }
    return {
        kind: "builtin",
        id: String(bind?.id ?? ""),
        label: description,
        binds: [bind]
    };
}
