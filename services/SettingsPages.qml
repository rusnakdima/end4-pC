pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    readonly property string pagesDir: "modules/ii/settings/pages/"

    readonly property var pages: {
        // Ordered by what the user is looking for: how it looks (Appearance,
        // Desktop, Bar, Interface), what the shell does (Dock & Lock, Tools,
        // Keyboard, General, Services), then the compositor's own settings,
        // then About. The compositor pages are split by topic as well, so
        // one pane never carries half the config.
        const list = [
            { id: "quick",      name: Translation.tr("Quick"),      icon: "instant_mix",    file: "QuickConfig.qml" },
            { id: "appearance", name: Translation.tr("Appearance"), icon: "palette",        file: "AppearanceConfig.qml" },
            { id: "desktop",    name: Translation.tr("Desktop"),    icon: "texture",        file: "BackgroundConfig.qml" },
            { id: "bar",        name: Translation.tr("Bar"),        icon: "toast",          iconRotation: 180, file: "BarConfig.qml" },
            { id: "interface",  name: Translation.tr("Interface"),  icon: "bottom_app_bar", file: "InterfaceConfig.qml" },
            { id: "docklock",   name: Translation.tr("Dock & Lock"), icon: "dock_to_bottom", file: "DockLockConfig.qml" },
            { id: "tools",      name: Translation.tr("Tools"),      icon: "construction",   file: "ToolsConfig.qml" },
            { id: "general",    name: Translation.tr("General"),    icon: "browse",         file: "GeneralConfig.qml" },
            { id: "keyboard",   name: Translation.tr("Keyboard"),   icon: "keyboard",       file: "KeyboardConfig.qml" },
            { id: "services",   name: Translation.tr("Services"),   icon: "settings",       file: "ServicesConfig.qml" },
        ];
        if (WM.compositor === "hyprland") {
            // The Hyprland pane used to be one scrolling page; it is split
            // by topic so the rail carries the groups as separate tabs.
            list.push({ id: "hyprland-displays", name: Translation.tr("Displays"), icon: "monitor", file: "HyprlandDisplays.qml" });
            list.push({ id: "hyprland-layout", name: Translation.tr("Layout"), icon: "auto_awesome_mosaic", file: "HyprlandLayout.qml" });
            list.push({ id: "hyprland-input", name: Translation.tr("Input"), icon: "trackpad_input", file: "HyprlandInput.qml" });
            list.push({ id: "hyprland-decoration", name: Translation.tr("Decoration"), icon: "deblur", file: "HyprlandDecoration.qml" });
            list.push({ id: "hyprland-behaviour", name: Translation.tr("Behaviour"), icon: "tune", file: "HyprlandBehaviour.qml" });
            list.push({ id: "hyprland-startup", name: Translation.tr("Startup"), icon: "app_registration", file: "HyprlandStartup.qml" });
        }
        if (WM.compositor === "niri") {
            // Same split as Hyprland, minus the tabs niri does not have.
            list.push({ id: "niri-displays", name: Translation.tr("Displays"), icon: "monitor", file: "NiriDisplays.qml" });
            list.push({ id: "niri-layout", name: Translation.tr("Layout"), icon: "auto_awesome_mosaic", file: "NiriLayout.qml" });
            list.push({ id: "niri-input", name: Translation.tr("Input"), icon: "trackpad_input", file: "NiriInput.qml" });
            list.push({ id: "niri-decoration", name: Translation.tr("Decoration"), icon: "deblur", file: "NiriDecoration.qml" });
        }
        list.push({ id: "about", name: Translation.tr("About"), icon: "info", file: "About.qml" });
        return list.map(page => Object.assign({}, page, {
            component: Qt.resolvedUrl("../" + root.pagesDir + page.file),
            path: root.pagesDir + page.file
        }));
    }

    function byId(id) {
        return root.pages.find(page => page.id === id) ?? null;
    }
}
