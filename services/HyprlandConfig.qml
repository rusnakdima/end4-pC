pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
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

    // The full apply pipeline as one string: write the file first, restart
    // hypridle only after the write succeeded. Kept separate from setIdle so
    // the tests can assert the sequence without killing the live daemon.
    function idleApplyCommand(lock: int, screenOff: int, suspend: int, file: string): string {
        return `python3 "${root.idleConfiguratorScriptPath}" --file "${file}"` +
            ` --lock ${lock} --screen-off ${screenOff} --suspend ${suspend} &&` +
            ` { pkill -x hypridle; sleep 0.5; setsid -f hypridle >/dev/null 2>&1; }`
    }

    function setIdle(lock: int, screenOff: int, suspend: int) {
        // One shell for both halves: the two detached calls used to run in
        // parallel, so the daemon came up on the old config and the new
        // timeouts never took effect.
        Quickshell.execDetached(["bash", "-c",
            root.idleApplyCommand(lock, screenOff, suspend, root.hypridlePath)])
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

    // Switch the active XKB layout.
    //
    // Hyprland keeps the active layout group by NAME: reordering kb_layout
    // moves the codes around but never changes which one is active. The old
    // active name is therefore dropped first - the group falls back to the
    // only layout left - and the full list is restored right after with the
    // target in front.
    function setKeyboardLayout(target: string, codes: list<string>) {
        const wanted = target.trim();
        if (wanted.length === 0) return "";

        const others = codes
            .map(c => c.trim())
            .filter(c => c.length > 0 && c.toLowerCase() !== wanted.toLowerCase());
        const applied = [wanted, ...others].join(",");

        // Both steps in one eval so the compositor runs them back to back, in
        // order: the single layout selects the target, the full list keeps
        // the other layouts available.
        Quickshell.execDetached([
            "hyprctl", "eval",
            `hl.config({ input = { kb_layout = "${wanted}" } }); hl.config({ input = { kb_layout = "${applied}" } })`
        ]);

        // Persist the final list; the configurator re-applies it live as well.
        root.set("input:kb_layout", applied);
        return applied;
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

    // hypridle.conf is written by setIdle; config.json is what the settings
    // show. When the two disagree - a write lost to a reload, a manual edit,
    // a value from before the write path was sequenced - the file is the
    // stale side, and the start-up check below brings it back in line.
    property string idleText: ""

    // Set once the file has been read (or is known to be missing). Without
    // it a config that becomes ready before the read would compare against
    // an empty text, read that as "no listeners" and restart hypridle for
    // nothing on every shell start.
    property bool idleFileLoaded: false

    // The three listeners are told apart by what they run, the same way
    // hypridleconfigurator.py matches them. A listener that is not in the
    // file has a timeout of 0: that is how the configurator writes "off".
    function idleTimeoutsFrom(text) {
        const found = { "lock": 0, "screenOff": 0, "suspend": 0 };
        const blocks = [];
        let current = null;
        let depth = 0;
        for (const line of String(text ?? "").split("\n")) {
            if (current === null) {
                if (/^\s*listener\s*\{/.test(line)) {
                    current = [line];
                    depth = (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
                }
                continue;
            }
            current.push(line);
            depth += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
            if (depth <= 0) {
                blocks.push(current.join("\n"));
                current = null;
            }
        }
        for (const block of blocks) {
            const match = block.match(/timeout\s*=\s*(\d+)/);
            if (!match) continue;
            const seconds = parseInt(match[1], 10);
            if (block.includes("loginctl lock-session")) found.lock = seconds;
            else if (block.includes("dpms")) found.screenOff = seconds;
            else if (block.includes("$suspend_cmd")) found.suspend = seconds;
        }
        return found;
    }

    function idleDiffers(fileTimeouts, config) {
        return fileTimeouts.lock !== config.lock
            || fileTimeouts.screenOff !== config.screenOff
            || fileTimeouts.suspend !== config.suspend;
    }

    function reconcileIdle() {
        if (WM.compositor !== "hyprland" || !Config.ready || !root.idleFileLoaded) return;
        if (!root.idleDiffers(root.idleTimeoutsFrom(root.idleText), Config.options.hyprland.idle)) return;
        const idle = Config.options.hyprland.idle;
        root.setIdle(idle.lock, idle.screenOff, idle.suspend);
    }

    FileView {
        id: idleFile
        path: root.hypridlePath
        preload: true
        // setIdle writes this file, and so can a manual edit outside the
        // shell. Watching means a change that never reached config.json (or
        // never reached hypridle) is reconciled within a moment instead of
        // only at the next shell start. setIdle's own write is a no-op here:
        // once it lands, the file matches config.json and reconcile stops.
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.idleText = text();
            root.idleFileLoaded = true;
            root.reconcileIdle();
        }
        // No file at all is the same disagreement: everything the config
        // holds has to be written out.
        onLoadFailed: {
            root.idleText = "";
            root.idleFileLoaded = true;
            root.reconcileIdle();
        }
    }

    // The palette can be loaded before the config, in which case the first
    // apply from MaterialThemeLoader was skipped.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                root.applyBorderColors()
                root.applyFromConfig()
                root.reconcileIdle()
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