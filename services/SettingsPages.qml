pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property string pagesDir: "modules/ii/settings/pages/"

    readonly property var categories: [
        "Network & internet",
        "Connected devices",
        "Personalization",
        "System",
        "About"
    ]

    readonly property var pages: {
        // Ordered by what the user is looking for: how it looks (Appearance,
        // Desktop, Bar, Interface), what the shell does (Dock & Lock, Tools,
        // Keyboard, General, Services), then the compositor's own settings,
        // then About. The compositor pages are split by topic as well, so
        // one pane never carries half the config.
        const list = [
            { id: "quick", category: "Personalization",      name: Translation.tr("Quick"),      icon: "instant_mix",    file: "QuickConfig.qml" },
            { id: "appearance", category: "Personalization", name: Translation.tr("Appearance"), icon: "palette",        file: "AppearanceConfig.qml" },
            { id: "desktop", category: "Personalization",    name: Translation.tr("Desktop"),    icon: "texture",        file: "BackgroundConfig.qml" },
            { id: "bar", category: "Personalization",        name: Translation.tr("Bar"),        icon: "toast",          iconRotation: 180, file: "BarConfig.qml" },
            { id: "interface", category: "Personalization",  name: Translation.tr("Interface"),  icon: "bottom_app_bar", file: "InterfaceConfig.qml" },
            { id: "docklock", category: "Personalization",   name: Translation.tr("Dock & Lock"), icon: "dock_to_bottom", file: "DockLockConfig.qml" },
            { id: "tools", category: "System",      name: Translation.tr("Tools"),      icon: "construction",   file: "ToolsConfig.qml" },
            { id: "advanced-paste", category: "System", name: Translation.tr("Advanced Paste"), icon: "content_paste_go", file: "AdvancedPasteConfig.qml" },
            { id: "general", category: "System",    name: Translation.tr("General"),    icon: "browse",         file: "GeneralConfig.qml" },
            { id: "default-apps", category: "System", name: Translation.tr("Default apps"), icon: "apps",        file: "DefaultAppsConfig.qml" },
            { id: "keyboard", category: "System",   name: Translation.tr("Keyboard"),   icon: "keyboard",       file: "KeyboardConfig.qml" },
            { id: "wifi", category: "Network & internet",       name: Translation.tr("Wi-Fi"),      icon: "wifi",           file: "WifiConfig.qml" },
            { id: "bluetooth", category: "Connected devices",  name: Translation.tr("Bluetooth"),  icon: "bluetooth",      file: "BluetoothConfig.qml" },
            { id: "services", category: "System",   name: Translation.tr("Services"),   icon: "settings",       file: "ServicesConfig.qml" },
            { id: "vnc", category: "Connected devices",        name: Translation.tr("VNC"),        icon: "screen_share",   file: "VncConfig.qml" },
            { id: "cast", category: "Connected devices",       name: Translation.tr("Cast"),       icon: "cast",           file: "CastConfig.qml" },
        ];
        if (WM.compositor === "hyprland") {
            // The Hyprland pane used to be one scrolling page; it is split
            // by topic so the rail carries the groups as separate tabs.
            list.push({ id: "hyprland-displays", category: "System", name: Translation.tr("Displays"), icon: "monitor", file: "HyprlandDisplays.qml" });
            list.push({ id: "projection", category: "Connected devices", name: Translation.tr("Projection"), icon: "desktop_windows", file: "ProjectionConfig.qml" });
            list.push({ id: "hyprland-layout", category: "System", name: Translation.tr("Layout"), icon: "auto_awesome_mosaic", file: "HyprlandLayout.qml" });
            list.push({ id: "hyprland-input", category: "System", name: Translation.tr("Input"), icon: "trackpad_input", file: "HyprlandInput.qml" });
            list.push({ id: "hyprland-decoration", category: "System", name: Translation.tr("Decoration"), icon: "deblur", file: "HyprlandDecoration.qml" });
            list.push({ id: "hyprland-behaviour", category: "System", name: Translation.tr("Behaviour"), icon: "tune", file: "HyprlandBehaviour.qml" });
            list.push({ id: "hyprland-startup", category: "System", name: Translation.tr("Startup"), icon: "app_registration", file: "HyprlandStartup.qml" });
        }
        if (WM.compositor === "niri") {
            // Same split as Hyprland, minus the tabs niri does not have.
            list.push({ id: "niri-displays", category: "System", name: Translation.tr("Displays"), icon: "monitor", file: "NiriDisplays.qml" });
            list.push({ id: "niri-layout", category: "System", name: Translation.tr("Layout"), icon: "auto_awesome_mosaic", file: "NiriLayout.qml" });
            list.push({ id: "niri-input", category: "System", name: Translation.tr("Input"), icon: "trackpad_input", file: "NiriInput.qml" });
            list.push({ id: "niri-decoration", category: "System", name: Translation.tr("Decoration"), icon: "deblur", file: "NiriDecoration.qml" });
        }
        list.push({ id: "about", category: "About", name: Translation.tr("About"), icon: "info", file: "About.qml" });
        return list.map(page => Object.assign({}, page, {
            component: Qt.resolvedUrl("../" + root.pagesDir + page.file),
            path: root.pagesDir + page.file
        }));
    }

    function byId(id) {
        return root.pages.find(page => page.id === id) ?? null;
    }

    // A page without a category is not an error: it belongs in System until
    // its own entry is updated. New-style rails must never crash on it.
    function pagesInCategory(name) {
        return root.pages.filter(page => (page.category ?? "System") === name);
    }
}
