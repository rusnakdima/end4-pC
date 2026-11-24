.pragma library

/*
 * The pure layer behind the Default apps settings page.
 *
 * A "default app" here is a shortcut target, not an XDG mime association:
 * each role owns one or more ids from the frozen catalog's Apps section, and
 * picking an app writes an override for those ids. The fallback chain in the
 * catalog is the value shown until an override exists, so clearing an
 * override restores the theme default without any second state file.
 *
 * Desktop entries expose their launch line as `execString`. Keybind commands
 * are run through bash, so the raw Exec field codes (%U, %f, ...) have to be
 * stripped before the line can be used as an override command.
 */

var ROLES = [
    {
        id: "terminal",
        label: "Terminal",
        icon: "terminal",
        bindIds: ["apps", "apps-2", "apps-3"],
        categories: ["TerminalEmulator", "System"],
        hints: ["kitty", "konsole", "xfce4-terminal", "alacritty", "wezterm"]
    },
    {
        id: "filemanager",
        label: "File manager",
        icon: "folder",
        bindIds: ["apps-4"],
        categories: ["FileManager", "System"],
        hints: ["dolphin", "nautilus", "nemo", "thunar", "yazi"]
    },
    {
        id: "browser",
        label: "Browser",
        icon: "public",
        bindIds: ["apps-5"],
        categories: ["WebBrowser", "Network"],
        hints: ["google-chrome-stable", "zen-browser", "firefox", "brave", "chromium", "microsoft-edge-stable", "opera", "librewolf"]
    },
    {
        id: "codeeditor",
        label: "Code editor",
        icon: "code",
        bindIds: ["apps-6"],
        categories: ["IDE", "Development", "TextEditor"],
        hints: ["windsurf", "antigravity", "code", "codium", "cursor", "zed", "kate", "emacs"]
    },
    {
        id: "office",
        label: "Office",
        icon: "description",
        bindIds: ["apps-7"],
        categories: ["Office", "Viewer"],
        hints: ["wps", "onlyoffice-desktopeditors", "libreoffice"]
    },
    {
        id: "texteditor",
        label: "Text editor",
        icon: "edit_note",
        bindIds: ["apps-8"],
        categories: ["TextEditor", "Utility"],
        hints: ["kate", "gnome-text-editor", "emacs"]
    },
    {
        id: "volumemixer",
        label: "Volume mixer",
        icon: "volume_up",
        bindIds: ["apps-9"],
        categories: ["Mixer", "AudioVideo"],
        hints: ["pavucontrol-qt", "pavucontrol"]
    },
    {
        id: "taskmanager",
        label: "Task manager",
        icon: "monitoring",
        bindIds: ["apps-11"],
        categories: ["Monitor", "System"],
        hints: ["gnome-system-monitor", "plasma-systemmonitor", "btop"]
    }
];

function roleById(id) {
    return ROLES.find(role => role.id === id) ?? null;
}

function roleForBindId(bindId) {
    const id = String(bindId ?? "");
    return ROLES.find(role => role.bindIds.includes(id)) ?? null;
}

function bindIds() {
    return ROLES.reduce((all, role) => all.concat(role.bindIds), []);
}

// Desktop Entry field codes are meaningful to a launcher, not to a shell.
// %% is an escaped percent and must survive; the rest are dropped.
function commandFromExec(raw) {
    if (raw === null || raw === undefined) return "";
    const escapedPercent = "\u0000";
    const line = String(raw)
        .replace(/%%/g, escapedPercent)
        .replace(/%[fFuUdDnNickvm]/g, "")
        .replace(new RegExp(escapedPercent, "g"), "%")
        .replace(/\s+/g, " ")
        .trim();
    return line;
}

function matchesCommand(entry, command) {
    if (!entry) return false;
    const wanted = commandFromExec(command);
    return wanted !== "" && commandFromExec(entry.execString) === wanted;
}

function isOverriddenIn(overlay, bindId) {
    const id = String(bindId ?? "");
    return Object.prototype.hasOwnProperty.call(overlay?.overrides ?? {}, id);
}

// Only a command dispatch represents a chosen app. A user may have overridden
// just the combo or the enabled flag of the same bind; that is not a default.
function commandForOverlay(overlay, bindId) {
    const entry = overlay?.overrides?.[String(bindId ?? "")];
    if (entry?.dispatch?.kind !== "command") return "";
    return String(entry.dispatch.command ?? "");
}
