// One label per keybind, shared by the settings search index and the rows of
// the Keyboard page. A search result passes its label to ContentPage.goTo(),
// which finds the row whose `title` is that same string, so the two must be
// built by exactly the same code or the deep link stops finding its target.
//
// Pure JavaScript, no Quickshell/QML dependencies, so it can be tested with
// the plain qmltestrunner pass like KeyCombos.js.

// Managed entry: "Name (SUPER + K)". The combo is written in the file at save
// time; an override may move the live bind, but the label follows the stored
// value so search and the row always agree.
function managed(entry) {
    const name = String(entry?.name ?? "").trim();
    const combo = String(entry?.combo ?? "").trim();
    if (name === "") return combo;
    if (combo === "") return name;
    return name + " (" + combo + ")";
}

// Shell action: "Description (SUPER + A, SUPER + B)". The action name is the
// fallback when the bind has no comment, and every alias is kept so all of the
// keys the action listens on are searchable.
function shell(entry) {
    const label = String(entry?.description ?? "").trim()
        || String(entry?.action ?? "").trim();
    const combos = Array.isArray(entry?.combos)
        ? entry.combos.filter(c => String(c ?? "").trim() !== "").join(", ")
        : "";
    if (label === "") return combos;
    if (combos === "") return label;
    return label + " (" + combos + ")";
}

// Compositor bind: "Comment (SUPER + F7)", or just the combo when the bind has
// no comment. `combo` is passed in so this stays a pure function and the same
// formatting as HyprlandKeybinds.comboOf() is used on both sides.
function other(bind, combo) {
    const label = String(bind?.comment ?? "").trim();
    const keys = String(combo ?? "").trim();
    if (label === "") return keys;
    if (keys === "") return label;
    return label + " (" + keys + ")";
}
