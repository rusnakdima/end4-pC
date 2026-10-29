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
