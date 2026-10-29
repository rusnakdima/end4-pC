pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root
    signal reloaded()

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)
    readonly property string idleConfiguratorScriptPath: Quickshell.shellPath("scripts/hyprland/hypridleconfigurator.py")
    readonly property string hypridlePath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hypridle.conf`)

    function setIdle(lock: int, screenOff: int, suspend: int) {
        Quickshell.execDetached([
            "python3", root.idleConfiguratorScriptPath,
            "--file", root.hypridlePath,
            "--lock", String(lock),
            "--screen-off", String(screenOff),
            "--suspend", String(suspend)
        ])
        Quickshell.execDetached(["bash", "-c", "pkill -x hypridle; sleep 0.3; setsid -f hypridle >/dev/null 2>&1"])
    }

    function set(key: string, value: var) {
        // The configurator writes the override file (restart persistence) and
        // applies the value to the running compositor via `hyprctl eval`.
        Quickshell.execDetached([
            "python3", root.configuratorScriptPath,
            "--file", root.shellOverridesPath,
            "--set", key, String(value)
        ])
    }

    function setMany(entries: var) {
        // One configurator run: single file write, every value applied live.
        let args = ["python3", root.configuratorScriptPath, "--file", root.shellOverridesPath]
        for (let key in entries) {
            args.push("--set", key, String(entries[key]))
        }
        Quickshell.execDetached(args)
    }

    function reset(key: string) {
        Quickshell.execDetached([
            "python3", root.configuratorScriptPath,
            "--file", root.shellOverridesPath,
            "--reset", key
        ])
    }

    function resetMany(keys: list<string>) {
        let args = ["python3", root.configuratorScriptPath, "--file", root.shellOverridesPath]
        for (let i = 0; i < keys.length; i++) {
            args.push("--reset", keys[i])
        }
        Quickshell.execDetached(args)
    }

    readonly property string borderActiveKey: "general:col:active_border"
    readonly property string borderInactiveKey: "general:col:inactive_border"

    // Hyprland wants rgba(RRGGBBAA) without a leading '#'. Only the RGB of the
    // palette color is kept: some Appearance colors carry an alpha that encodes
    // a layer opacity inside the shell, which has nothing to do with a border.
    function toHyprColor(color, opacity) {
        const c = Qt.color(color)
        const hex = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")
        return `rgba(${hex(c.r)}${hex(c.g)}${hex(c.b)}${hex(opacity)})`
    }

    // Custom window border colors, or {} when the option is off so the colors
    // matugen writes to hyprland/colors.lua keep applying. Roles are resolved
    // here rather than stored as colors, so the borders follow the wallpaper.
    function borderColorEntries() {
        const opts = Config.options?.hyprland?.general?.borderColor
        if (WM.compositor !== "hyprland" || !Config.ready || !opts?.enable) return ({})
        let entries = ({})
        entries[root.borderActiveKey] = root.toHyprColor(
            Appearance.getColorFromName(opts.activeRole), opts.activeOpacity)
        entries[root.borderInactiveKey] = root.toHyprColor(
            Appearance.getColorFromName(opts.inactiveRole), opts.inactiveOpacity)
        return entries
    }

    // Also called by MaterialThemeLoader on every palette change.
    function applyBorderColors() {
        const entries = root.borderColorEntries()
        if (Object.keys(entries).length > 0) root.setMany(entries)
    }

    function resetBorderColors() {
        if (WM.compositor !== "hyprland") return
        root.resetMany([root.borderActiveKey, root.borderInactiveKey])
    }

    // The stored hyprland.* options, mapped onto the compositor's option keys.
    // Shared by the settings page and by the start-up apply, so both agree.
    function configEntries() {
        const h = Config.options?.hyprland
        if (!h) return ({})
        return {
            "decoration:rounding":                 h.decoration.rounding,
            "decoration:blur:enabled":             h.decoration.blur.enabled ? 1 : 0,
            "decoration:blur:size":                h.decoration.blur.size,
            "decoration:blur:passes":              h.decoration.blur.passes,
            "decoration:active_opacity":           h.decoration.activeOpacity,
            "decoration:inactive_opacity":         h.decoration.inactiveOpacity,
            "general:border_size":                 h.general.borderSize,
            "general:gaps_in":                     h.general.gapsIn,
            "general:gaps_out":                    h.general.gapsOut,
            "general:layout":                      h.general.layout,
            "animations:enabled":                  h.animations.enable ? 1 : 0,
            "input:kb_layout":                     h.input.kbLayout,
            "input:numlock_by_default":            h.input.numlock ? 1 : 0,
            "input:repeat_delay":                  h.input.repeatDelay,
            "input:repeat_rate":                   h.input.repeatRate,
            "input:follow_mouse":                  h.input.followMouse,
            "input:touchpad:natural_scroll":       h.input.touchpad.naturalScroll ? 1 : 0,
            "input:touchpad:disable_while_typing": h.input.touchpad.disableWhileTyping ? 1 : 0,
            "input:touchpad:clickfinger_behavior": h.input.touchpad.clickfingerBehavior ? 1 : 0,
            "input:touchpad:scroll_factor":        h.input.touchpad.scrollFactor,
            "misc:focus_on_activate":              h.misc.focusOnActivate ? 1 : 0
        }
    }

    // Push the stored options and the mirrored live options to the compositor.
    function applyFromConfig() {
        root.setMany(Object.assign(root.configEntries(), root.borderColorEntries()))
        HyprlandOptions.applyAllFromConfig()
    }

    // The palette can be loaded before the config, in which case the first
    // apply from MaterialThemeLoader was skipped.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                root.applyBorderColors()
                root.applyFromConfig()
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}