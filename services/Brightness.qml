pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * For managing brightness of monitors. Supports both brightnessctl and ddcutil.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    readonly property list<BrightnessMonitor> monitors: Quickshell.screens.map(screen => monitorComp.createObject(root, {
        screen
    }))

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    function increaseBrightness(): void {
        // if gamma is not yet 100, first increase gamma
        if (Hyprsunset.gamma !== 100) {
            Hyprsunset.setGamma(Hyprsunset.gamma + 5);
            return;
        }

        const focusedName = Hyprland.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness + 0.05);
    }

    function decreaseBrightness(): void {
        const focusedName = Hyprland.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor && monitor.brightness > 0) 
            monitor.setBrightness(monitor.brightness - 0.05);
        // if brightness is 0, then decrease gamma
        else {
            Hyprsunset.setGamma(Hyprsunset.gamma - 5);
        }
    }

    function increaseKeyboardBrightness(): void {
        // Delegates to the monitor: the old brightnessctl call was broken here
        // twice over (a wrapper that forces -d amdgpu_bl1, and no such class).
        kbMonitor.increase();
    }

    function decreaseKeyboardBrightness(): void {
        kbMonitor.decrease();
    }
    reloadableId: "brightness"


    onMonitorsChanged: {
        ddcMonitors = [];
        ddcProc.running = true;
    }

    function initializeMonitor(i: int): void {
        if (i >= monitors.length)
            return;
        monitors[i].initialize();
    }

    function ddcDetectFinished(): void {
        initializeMonitor(0);
    }

    Process {
        id: ddcProc

        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                if (data.startsWith("Display ")) {
                    const lines = data.split("\n").map(l => l.trim());
                    root.ddcMonitors.push({
                        name: lines.find(l => l.startsWith("DRM connector:")).split("-").slice(1).join('-'),
                        busNum: lines.find(l => l.startsWith("I2C bus:")).split("/dev/i2c-")[1]
                    });
                }
            }
        }
        onExited: root.ddcDetectFinished()
    }

    Process {
        id: setProc
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        property bool isDdc
        property string busNum
        property int rawMaxBrightness: 100
        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (Config.options.light.antiFlashbang.enable ? brightnessMultiplier : 1)))
        property bool ready: false
        property bool animateChanges: !monitor.isDdc

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.brightnessChanged();
        }

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        onMultipliedBrightnessChanged: {
            if (monitor.animationEnabled) syncBrightness();
            else setTimer.restart();
        }

        function initialize() {
            monitor.ready = false;
            const match = root.ddcMonitors.find(m => m.name === screen.name && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum));
            isDdc = !!match;
            busNum = match?.busNum ?? "";
            initProc.command = isDdc ? ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"] : ["sh", "-c", `echo "a b c $(brightnessctl g) $(brightnessctl m)"`];
            initProc.running = true;
        }

        readonly property Process initProc: Process {
            stdout: SplitParser {
                onRead: data => {
                    const [, , , current, max] = data.split(" ");
                    monitor.rawMaxBrightness = parseInt(max);
                    monitor.brightness = parseInt(current) / monitor.rawMaxBrightness;
                    monitor.ready = true;
                }
            }
            onExited: (exitCode, exitStatus) => {
                initializeMonitor(root.monitors.indexOf(monitor) + 1);
            }
        }

        // We need a delay for DDC monitors because they can be quite slow and might act weird with rapid changes
        property var setTimer: Timer {
            id: setTimer
            interval: monitor.isDdc ? 300 : 0
            onTriggered: {
                syncBrightness();
            }
        }

        function syncBrightness() {
            const brightnessValue = Math.max(monitor.multipliedBrightness, 0);
            if (isDdc) {
                const rawValueRounded = Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1);
                setProc.exec(["ddcutil", "-b", busNum, "setvcp", "10", rawValueRounded]);
            } else {
                const valuePercentNumber = Math.floor(brightnessValue * 100);
                let valuePercent = `${valuePercentNumber}%`;
                if (valuePercentNumber == 0) valuePercent = "1"; // Prevent fully black
                setProc.exec(["brightnessctl", "--class", "backlight", "s", valuePercent, "--quiet"])
            }
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }
    component KeyboardBrightnessMonitor: QtObject {
        id: kbMonitor

        property real brightness: 1 // 0..1, brightness / max
        readonly property real brightnessPercent: Math.round(brightness * 100)
        property int maxBrightness: 100
        property var color: null

        // Result of the last apply, rendered by the Keyboard page so a failure
        // is visible instead of silently doing nothing.
        property bool statusOk: true
        property string statusMessage: ""

        // This machine is a Maibenben X16C: the keyboard LED is the Tuxedo
        // uniwill_wmi device, not an ASUS aura zone, and it is driven by the
        // two helpers below. Capability therefore means "the sysfs device with
        // per-channel colour exists" -- which also replaces the old
        // Config.options.keyboard.hasColor read of a key that never existed.
        readonly property string ledDir: "/sys/class/leds/rgb:kbd_backlight"
        property bool available: false
        readonly property bool hasColor: available

        function increase(): void { kbMonitor.set(kbMonitor.brightnessPercent + 5); }
        function decrease(): void { kbMonitor.set(kbMonitor.brightnessPercent - 5); }

        // percent is 0..100, the shape SettingsQuickControls and the sidebar
        // slider already speak.
        function set(percent: int): void {
            if (!kbMonitor.available) {
                kbMonitor.report(false, Translation.tr("No keyboard backlight device"));
                return;
            }
            const p = Math.max(0, Math.min(100, Math.round(percent)));
            // kbd-backlight clamps against max_brightness itself, and save
            // feeds the boot service that restores the state after a reboot.
            kbMonitor.run([
                "sh", "-c",
                `sudo -n /usr/local/bin/kbd-backlight set-brightness ${p} && sudo -n /usr/local/bin/kbd-backlight save`
            ]);
        }

        function setColor(r: int, g: int, b: int): void {
            kbMonitor.setColorHex(kbMonitor.toHex(r, g, b));
        }

        function setColorHex(hex: string): void {
            if (!kbMonitor.available) {
                kbMonitor.report(false, Translation.tr("No keyboard backlight device"));
                return;
            }
            const c = Qt.color(hex);
            if (!c.isValid) {
                kbMonitor.report(false, Translation.tr("Not a valid colour: ") + hex);
                return;
            }
            kbMonitor.color = hex;
            // kbd-color takes 0-255 channels, scales them to the sysfs 0-4
            // range and swaps R and B for the hardware's BGR order -- which is
            // exactly why the raw values must not be written by hand.
            const r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255);
            kbMonitor.run([
                "sh", "-c",
                `sudo -n /usr/local/bin/kbd-color ${r} ${g} ${b} && sudo -n /usr/local/bin/kbd-backlight save`
            ]);
        }

        // What the wallpaper-follow option feeds it: Appearance.colPrimary is
        // already derived from the wallpaper, so there is nothing to sample.
        function applyColor(color): void {
            const c = Qt.color(color);
            kbMonitor.setColor(kbMonitor.channel(c.r), kbMonitor.channel(c.g), kbMonitor.channel(c.b));
        }

        function applyFromConfig(): void {
            if (!kbMonitor.available || !Config.options.light.keyboardColor.enable) return;
            if (Config.options.light.keyboardColor.followWallpaper) {
                kbMonitor.applyColor(Appearance.colors.colPrimary);
                return;
            }
            const stored = Config.options.light.keyboardColor.color;
            if (stored && stored !== "")
                kbMonitor.setColorHex(stored);
        }

        function channel(v: real): int {
            return Math.max(0, Math.min(255, Math.round(v * 255)));
        }

        function toHex(r: int, g: int, b: int): string {
            return "#" + [r, g, b]
                .map(v => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0"))
                .join("");
        }

        function report(ok: bool, message: string): void {
            kbMonitor.statusOk = ok;
            kbMonitor.statusMessage = message;
        }

        function refresh(): void {
            kbReadProc.exec([]);
        }

        function run(cmd): void {
            applyProc.exec(cmd);
        }

        // QtObject has no default property, so every child is a property --
        // the same trick BrightnessMonitor uses for initProc.

        // One probe for the device and its range: without the LED there is
        // nothing to control, and the page says so instead of pretending.
        readonly property Process probeProc: Process {
            command: ["sh", "-c",
                `d="${kbMonitor.ledDir}"; if [ -e "$d/multi_intensity" ]; then printf 'yes %s\n' "$(cat "$d/max_brightness" 2>/dev/null || echo 100)"; else printf 'no 100\n'; fi`]
            stdout: StdioCollector {
                onStreamFinished: {
                    const parts = text.trim().split(/\s+/);
                    kbMonitor.available = parts[0] === "yes";
                    const max = parseInt(parts[1]);
                    kbMonitor.maxBrightness = (!isNaN(max) && max > 0) ? max : 100;
                }
            }
        }

        // brightnessctl cannot be used here: /usr/local/bin/brightnessctl is a
        // wrapper that forces -d amdgpu_bl1, and there is no kbd_backlight
        // class anyway. Read the LED directly.
        readonly property Process kbReadProc: Process {
            command: ["sh", "-c",
                `d="${kbMonitor.ledDir}"; printf '%s %s\n' "$(cat "$d/brightness" 2>/dev/null || echo 0)" "$(cat "$d/max_brightness" 2>/dev/null || echo 100)"`]
            stdout: SplitParser {
                onRead: data => {
                    const parts = data.trim().split(/\s+/);
                    const cur = parseInt(parts[0]);
                    const max = parseInt(parts[1]);
                    if (isNaN(cur) || isNaN(max) || max <= 0) return;
                    kbMonitor.maxBrightness = max;
                    kbMonitor.brightness = Math.max(0, Math.min(1, cur / max));
                }
            }
        }

        readonly property Process applyProc: Process {
            stderr: StdioCollector { id: applyErr }
            onExited: (exitCode) => {
                if (exitCode === 0) {
                    kbMonitor.report(true, "");
                    kbMonitor.refresh();
                    return;
                }
                // sudo -n cannot prompt here, so the message has to say what
                // would have to be granted.
                const err = applyErr.text.trim();
                kbMonitor.report(false, err !== ""
                    ? err
                    : Translation.tr("Could not set the keyboard colour. Check sudo access to /usr/local/bin/kbd-color."));
            }
        }

        // Singletons are created lazily (see MaterialThemeLoader), so a stored
        // colour has to be re-applied when the config is ready, not on
        // construction -- otherwise a restart would leave the keyboard dark.
        readonly property Connections configReady: Connections {
            target: Config
            function onReadyChanged() {
                if (Config.ready) kbMonitor.applyFromConfig();
            }
        }

        // matugen emits several colour changes for one wallpaper; coalesce them
        // (the same reason ColorSchemes delays its regenerations).
        readonly property Timer followTimer: Timer {
            interval: 300
            onTriggered: kbMonitor.applyFromConfig()
        }

        readonly property Connections wallpaperColour: Connections {
            target: Appearance.colors
            function onColPrimaryChanged() {
                if (!Config.options.light.keyboardColor.enable) return;
                if (!Config.options.light.keyboardColor.followWallpaper) return;
                followTimer.restart();
            }
        }

        Component.onCompleted: {
            probeProc.exec([]);
            kbReadProc.exec([]);
        }
    }

    // Exposed so the settings pages and the quick controls can read the level
    // and apply a colour. Nothing else in the shell owns this object.
    readonly property KeyboardBrightnessMonitor kbMonitor: KeyboardBrightnessMonitor {}

    // The named colours the settings UI offers, as hex: kbd-color takes
    // channels, not names, and one table keeps the Keyboard page swatches and
    // the quick-control select from drifting apart. "Off" is 0 0 0, which is
    // what kbd-color's own `off` argument writes.
    readonly property var keyboardColors: [
        { value: "#ffffff", displayName: Translation.tr("White") },
        { value: "#ff5252", displayName: Translation.tr("Red") },
        { value: "#ff9800", displayName: Translation.tr("Orange") },
        { value: "#ffd600", displayName: Translation.tr("Yellow") },
        { value: "#4caf50", displayName: Translation.tr("Green") },
        { value: "#26c6da", displayName: Translation.tr("Cyan") },
        { value: "#42a5f5", displayName: Translation.tr("Blue") },
        { value: "#ab47bc", displayName: Translation.tr("Purple") },
        { value: "#ec407a", displayName: Translation.tr("Magenta") },
        { value: "#000000", displayName: Translation.tr("Off") }
    ]

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    // Anti-flashbang
    property int workspaceAnimationDelay: 500
    property int contentSwitchDelay: 30
    property string screenshotDir: "/tmp/quickshell/brightness/antiflashbang"
    function brightnessMultiplierForLightness(x: real): real {
        // I hand picked some values and fitted an exponential curve for this
        // 6.600135 + 216.360356 * e^(-0.0811129189x)
        // Division by 100 is to normalize to [0, 1]
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property string screenName: modelData.name
            property string screenshotPath: `${root.screenshotDir}/screenshot-${screenName}.png`
            Connections {
                enabled: Config.options.light.antiFlashbang.enable && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700 // This is what I have for a Hyprland ws anim
                onTriggered: {
                    screenshotProc.running = false;
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        Quickshell.execDetached(["rm", screenScope.screenshotPath]); // Cleanup
                        const lightness = lightnessCollector.text
                        const newMultiplier = root.brightnessMultiplierForLightness(parseFloat(lightness))
                        Brightness.getMonitorForScreen(screenScope.modelData).setBrightnessMultiplier(newMultiplier)
                    }
                }
            }
        }
    }

    // External trigger points

    IpcHandler {
        target: "brightness"

        function increment() {
            onPressed: root.increaseBrightness()
        }

        function decrement() {
            onPressed: root.decreaseBrightness()
        }
    }

    CompositorGlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    CompositorGlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
    CompositorGlobalShortcut {
        name: "keyboardBrightnessIncrease"
        description: "Increase keyboard brightness"
        onPressed: root.increaseKeyboardBrightness()
    }

    CompositorGlobalShortcut {
        name: "keyboardBrightnessDecrease"
        description: "Decrease keyboard brightness"
        onPressed: root.decreaseKeyboardBrightness()
    }
}
