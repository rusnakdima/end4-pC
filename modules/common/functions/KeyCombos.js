// The key names Hyprland uses, and the conversion of a key event into a
// Hyprland key combination.
//
// The logic lives in a plain JavaScript module so that it can be tested
// without the Quickshell runtime.

var cachedKeyNames = null;

// The name Hyprland knows a key by. The digits and the letters are the
// characters themselves, everything else has a name of its own.
function keyNames() {
    if (cachedKeyNames !== null) return cachedKeyNames;

    const names = {};
    for (let code = Qt.Key_A; code <= Qt.Key_Z; code++) names[code] = String.fromCharCode(code);
    for (let code = Qt.Key_0; code <= Qt.Key_9; code++) names[code] = String.fromCharCode(code);
    for (let i = 1; i <= 12; i++) names[Qt.Key_F1 + i - 1] = "F" + i;

    names[Qt.Key_Space] = "space";
    names[Qt.Key_Tab] = "Tab";
    names[Qt.Key_Backtab] = "Tab";
    names[Qt.Key_Return] = "Return";
    names[Qt.Key_Enter] = "Return";
    names[Qt.Key_Escape] = "Escape";
    names[Qt.Key_Backspace] = "BackSpace";
    names[Qt.Key_Delete] = "Delete";
    names[Qt.Key_Insert] = "Insert";
    names[Qt.Key_Home] = "Home";
    names[Qt.Key_End] = "End";
    names[Qt.Key_Left] = "Left";
    names[Qt.Key_Up] = "Up";
    names[Qt.Key_Right] = "Right";
    names[Qt.Key_Down] = "Down";
    names[Qt.Key_PageUp] = "Page_Up";
    names[Qt.Key_PageDown] = "Page_Down";
    names[Qt.Key_Slash] = "Slash";
    names[Qt.Key_Backslash] = "Backslash";
    names[Qt.Key_Semicolon] = "Semicolon";
    names[Qt.Key_Apostrophe] = "Apostrophe";
    names[Qt.Key_Comma] = "Comma";
    names[Qt.Key_Period] = "Period";
    names[Qt.Key_Minus] = "Minus";
    names[Qt.Key_Equal] = "Equal";
    names[Qt.Key_BracketLeft] = "BracketLeft";
    names[Qt.Key_BracketRight] = "BracketRight";
    names[Qt.Key_Print] = "Print";
    names[Qt.Key_Pause] = "Pause";
    names[Qt.Key_CapsLock] = "Caps_Lock";
    names[Qt.Key_NumLock] = "Num_Lock";
    names[Qt.Key_ScrollLock] = "Scroll_Lock";
    names[Qt.Key_Menu] = "Menu";

    cachedKeyNames = names;
    return names;
}

// Human-readable words for the parts of a key combination. The Hyprland
// tokens are what the config files speak; these are what the settings form
// and the shortcut rows show, so "CTRL + SUPER + Return" reads as
// "Ctrl + Super + Enter".
var displayLabels = {
    "SUPER": "Super",
    "CTRL": "Ctrl",
    "SHIFT": "Shift",
    "ALT": "Alt",
    "META": "Meta",
    "Return": "Enter",
    "Enter": "Enter",
    "Escape": "Esc",
    "BackSpace": "Backspace",
    "Backspace": "Backspace",
    "space": "Space",
    "Tab": "Tab",
    "Delete": "Del",
    "Insert": "Ins",
    "Home": "Home",
    "End": "End",
    "Page_Up": "Page Up",
    "Page_Down": "Page Down",
    "Left": "Left",
    "Up": "Up",
    "Right": "Right",
    "Down": "Down",
    "Print": "PrtSc",
    "Pause": "Pause",
    "Caps_Lock": "Caps Lock",
    "Num_Lock": "Num Lock",
    "Scroll_Lock": "Scroll Lock",
    "Menu": "Menu",
    // Punctuation keys are shown as the character they type.
    "Slash": "/",
    "Backslash": "\\",
    "Semicolon": ";",
    "Apostrophe": "'",
    "Comma": ",",
    "Period": ".",
    "Minus": "-",
    "Equal": "=",
    "BracketLeft": "[",
    "BracketRight": "]"
};

// The readable word for one part of a combination. Unknown tokens (media
// keys, mouse buttons, function keys) come back unchanged, so nothing is
// ever shown as an empty string.
function displayLabel(part) {
    const key = String(part ?? "");
    if (key === "") return "";
    return displayLabels[key] ?? key;
}

// The readable parts of "CTRL + SUPER + K" -> ["Ctrl", "Super", "K"].
// Split on the same separator the combos are written with.
function displayParts(combo) {
    const text = String(combo ?? "");
    if (text === "") return [];
    return text.split(" + ").map(displayLabel);
}

// The words a person may type for a modifier, mapped to the Hyprland token.
var modifierTokens = {
    "super": "SUPER",
    "meta": "SUPER",
    "ctrl": "CTRL",
    "control": "CTRL",
    "shift": "SHIFT",
    "alt": "ALT"
};

var modifierOrder = ["CTRL", "SUPER", "SHIFT", "ALT"];

// The names of keys that are not a single character, lowercased so a typed
// combination may spell them like words ("enter", "pgdown").
var keyNameTokens = null;

function keyNameByToken() {
    if (keyNameTokens !== null) return keyNameTokens;

    const names = {};
    const known = keyNames();
    for (const code in known) names[String(known[code]).toLowerCase()] = known[code];
    names["enter"] = "Return";
    names["return"] = "Return";
    names["esc"] = "Escape";
    names["escape"] = "Escape";
    names["backspace"] = "BackSpace";
    names["del"] = "Delete";
    names["delete"] = "Delete";
    names["ins"] = "Insert";
    names["insert"] = "Insert";
    names["pageup"] = "Page_Up";
    names["pgup"] = "Page_Up";
    names["pagedown"] = "Page_Down";
    names["pgdown"] = "Page_Down";
    names["prtsc"] = "Print";
    names["print"] = "Print";
    names["capslock"] = "Caps_Lock";
    names["numlock"] = "Num_Lock";
    names["scrolllock"] = "Scroll_Lock";
    // The punctuation keys, as the characters they type.
    const punctuation = {
        "/": "Slash", "\\": "Backslash", ";": "Semicolon", "'": "Apostrophe",
        ",": "Comma", ".": "Period", "-": "Minus", "=": "Equal",
        "[": "BracketLeft", "]": "BracketRight"
    };
    for (const character in punctuation) names[character] = punctuation[character];

    keyNameTokens = names;
    return names;
}

// Splits a combination into its tokens, accepting "+" or whitespace as the
// separator and any mixture of case.
function comboTokens(text) {
    return String(text ?? "").trim().split(/[+\s]+/).filter(token => token !== "");
}

// A comparable form of a combination: lowercase, modifiers in the canonical
// order, joined by "+". "i + super" and "SUPER + I" both become "super+i".
function canonicalCombo(text) {
    const mods = [];
    const keys = [];
    for (const token of comboTokens(text)) {
        const lower = token.toLowerCase();
        const modifier = modifierTokens[lower];
        if (modifier) {
            if (!mods.includes(modifier)) mods.push(modifier);
        } else {
            keys.push(lower);
        }
    }
    mods.sort((a, b) => modifierOrder.indexOf(a) - modifierOrder.indexOf(b));
    return mods.concat(keys).join("+").toLowerCase();
}

// True when two spellings name the same combination.
function comboMatches(query, combo) {
    const left = canonicalCombo(query);
    return left !== "" && left === canonicalCombo(combo);
}

// Turns typed text ("super+i", "i super", "ctrl shift k") into the spelling
// the config files use ("SUPER + I"). Returns "" unless exactly one
// non-modifier key is present, so a partial modifier press is ignored.
function comboFromText(text) {
    const mods = [];
    const keys = [];
    for (const token of comboTokens(text)) {
        const lower = token.toLowerCase();
        const modifier = modifierTokens[lower];
        if (modifier) {
            if (!mods.includes(modifier)) mods.push(modifier);
            continue;
        }
        const known = keyNameByToken()[lower];
        if (known) {
            keys.push(known);
        } else if (token.length === 1) {
            keys.push(token.toUpperCase());
        } else {
            // Not a key name we know: the text is a search phrase, not a
            // combination someone typed.
            return "";
        }
    }
    if (keys.length !== 1) return "";
    mods.sort((a, b) => modifierOrder.indexOf(a) - modifierOrder.indexOf(b));
    return mods.concat(keys).join(" + ");
}

// Converts a key event into a Hyprland key combination ("SUPER + ALT + V").
// Returns "" when the key has no name Hyprland would understand, so the
// caller can ignore the press.
function keyEventToCombo(event) {
    if (!event) return "";

    const mods = [];
    // The order the theme writes its own binds in, so that a captured
    // combination reads like the ones in the config file.
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL");
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER");
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
    if (event.modifiers & Qt.AltModifier) mods.push("ALT");

    let name = keyNames()[event.key];
    if (!name) {
        const text = event.text ?? "";
        if (text.length === 1 && text >= " " && text <= "~") name = text;
    }
    if (!name) return "";

    if (name.length === 1) name = name.toUpperCase();
    return mods.concat([name]).join(" + ");
}
