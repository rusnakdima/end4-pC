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

        // 0..100 percent. Both existing callers already speak it: the sidebar
        // slider divides brightnessPercent by 100, and the settings spin passes
        // the value straight back into set().
        property real brightness: 100
        readonly property real brightnessPercent: Math.round(brightness)

        // What the user asked for. Kept apart from `color` below so that the
        // snapped value the hardware reports can be shown without being fed
        // back into the next write as if it had been chosen.
        property string requestedColor: "#ffffff"

        // What the hardware is actually showing, snapped to the ten levels per
        // channel the panel has. A string rather than a color so it round-trips
        // into the page's string field as #RRGGBB instead of Qt's #AARRGGBB.
        property string color: "#ffffff"
        property var levels: [0, 0, 0]
        property bool rainbow: false
        property bool off: false
        property string backend: ""
        property bool available: false
        readonly property bool hasColor: available

        // Result of the last apply, rendered by the Keyboard page so a failure
        // is visible instead of silently doing nothing.
        property bool statusOk: true
        property string statusMessage: ""

        // The combination last handed to the hardware, so a repeated wallpaper
        // colour or a re-opened page does not hammer the EC.
        property string appliedKey: ""
        property string pendingKey: ""
        // True while a write is in flight: a probe that lands mid-drag must not
        // yank the slider back to the value the hardware already had.
        property bool applying: false
        // Whether the stored choice has been pushed once the config was ready.
        property bool configApplied: false

        readonly property string helper: "/usr/local/bin/kbd-rgb"

        function increase(): void { kbMonitor.set(kbMonitor.brightnessPercent + 5); }
        function decrease(): void { kbMonitor.set(kbMonitor.brightnessPercent - 5); }

        function report(ok: bool, message: string): void {
            kbMonitor.statusOk = ok;
            kbMonitor.statusMessage = message;
        }

        function clampPercent(p: real): int {
            return Math.max(0, Math.min(100, Math.round(p)));
        }

        // percent is 0..100, the shape SettingsQuickControls and the sidebar
        // slider already speak.
        function set(percent: int): void {
            if (!kbMonitor.available) {
                kbMonitor.report(false, Translation.tr("No keyboard backlight device"));
                return;
            }
            kbMonitor.brightness = kbMonitor.clampPercent(percent);
            kbMonitor.off = false;
            kbMonitor.schedule();
        }

        function setColor(r: int, g: int, b: int): void {
            kbMonitor.setColorHex(kbMonitor.toHex(r, g, b));
        }

        // Qt.color() in this Qt build hands back an object that carries r/g/b/a
        // and toString() but *no* isValid, *no* name() and *no* h/s/v -- so the
        // old `if (!c.isValid)` rejected every colour and `c.name()` threw.
        // Parsing is done with a regular expression instead; #rgb and #aarrggbb
        // are accepted and folded onto #rrggbb. Returns "" for anything else.
        function normalizeHex(value): string {
            let s = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
            if (s.charAt(0) === "#") s = s.slice(1);
            if (/^[0-9a-f]{3}$/.test(s))
                s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2);
            else if (/^[0-9a-f]{8}$/.test(s)) s = s.slice(2); // #aarrggbb -> rrggbb
            if (!/^[0-9a-f]{6}$/.test(s)) return "";
            return "#" + s;
        }

        function setColorHex(hex: string): void {
            if (!kbMonitor.available) {
                kbMonitor.report(false, Translation.tr("No keyboard backlight device"));
                return;
            }
            const normalized = kbMonitor.normalizeHex(hex);
            if (normalized === "") {
                kbMonitor.report(false, Translation.tr("Not a valid colour: ") + hex);
                return;
            }
            kbMonitor.requestedColor = normalized;
            kbMonitor.color = normalized;
            kbMonitor.off = false;
            kbMonitor.schedule();
        }

        // What the wallpaper-follow option feeds it: Appearance.colPrimary is
        // already derived from the wallpaper, so there is nothing to sample.
        // Invalid input is dropped silently -- a wallpaper change must never
        // paint an error into the page.
        function applyColor(colour): void {
            const normalized = kbMonitor.normalizeHex(colour);
            if (normalized === "") return;
            kbMonitor.requestedColor = normalized;
            kbMonitor.color = normalized;
            kbMonitor.off = false;
            kbMonitor.schedule();
        }

        function setMode(mode: string): void {
            if (!kbMonitor.available) return;
            kbMonitor.rainbow = mode === "rainbow";
            kbMonitor.off = false;
            kbMonitor.schedule();
        }

        // The panel has no true off, so "Off" is the pure black colour, which
        // the helper maps onto the darkest state it can hold.
        function switchOff(): void {
            kbMonitor.setColorHex("#000000");
        }

        // The configured Appearance.colors role. Every one of these is a
        // property of the same object MaterialThemeLoader rewrites, so choosing
        // among them changes which colour is followed, never which mechanism.
        function roleColour() {
            switch (Config.options.light.keyboardColor.role) {
            case "primaryActive": return Appearance.colors.colPrimaryActive;
            case "secondary":      return Appearance.colors.colSecondary;
            case "tertiary":       return Appearance.colors.colTertiary;
            default:               return Appearance.colors.colPrimary;
            }
        }

        // One gate for every role watcher: colour management has to be on and
        // the keyboard has to be following the wallpaper.
        function restartFollow(): void {
            if (!Config.options.light.keyboardColor.followWallpaper) return;
            followTimer.restart();
        }

        // A Material colour is chosen to read on a surface, where a lightly
        // saturated tone looks calm and correct; laid on a keyboard it reads as
        // white-lit and washed out. The theme's *hue* and *lightness* are kept
        // exactly -- same role, same signal, same mechanism -- and only
        // saturation is taken to full, which is what the palette's lower rows
        // show. This is applied only to the followed colour: a colour picked by
        // hand from the palette is sent as chosen.
        function hardwareColour(value): string {
            const c = Qt.color(value);
            const r = c.r, g = c.g, b = c.b;
            const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
            if (mx <= 0) return "#000000";
            let h = 0;
            if (d > 0) {
                if (mx === r) h = ((g - b) / d + 6) % 6;
                else if (mx === g) h = (b - r) / d + 2;
                else h = (r - g) / d + 4;
                h *= 60;
            }
            // HSV, full saturation, same value as the theme picked.
            const out = Qt.hsva(h / 360, 1, mx, 1);
            const two = x => Math.round(Math.max(0, Math.min(1, x)) * 255)
                .toString(16).padStart(2, "0");
            return "#" + two(out.r) + two(out.g) + two(out.b);
        }

        // The exact colour "match the wallpaper" sends: the configured role,
        // then rendered for the keyboard.
        function followColour(): string {
            return kbMonitor.hardwareColour(kbMonitor.roleColour());
        }

        function applyFromConfig(): void {
            if (!kbMonitor.available) return;
            kbMonitor.configApplied = true;
            if (Config.options.light.keyboardColor.followWallpaper) {
                kbMonitor.applyColor(kbMonitor.followColour());
                return;
            }
            const stored = Config.options.light.keyboardColor.color;
            if (stored && stored !== "")
                kbMonitor.setColorHex(stored);
        }

        function toHex(r: int, g: int, b: int): string {
            return "#" + [r, g, b]
                .map(v => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0"))
                .join("");
        }

        // Coalesce: a hue drag and matugen both emit bursts, and every write
        // costs a sudo spawn plus an EC transaction.
        function schedule(): void {
            applyTimer.restart();
        }

        function buildKey(): string {
            // Only what the helper is actually asked for. `off` is display state
            // read back from probe; it never keys an apply, so a dark colour
            // cannot turn the next apply into a different command.
            return [
                kbMonitor.requestedColor,
                kbMonitor.brightnessPercent,
                kbMonitor.rainbow ? "rainbow" : "static"
            ].join("|");
        }

        function doApply(): void {
            if (!kbMonitor.available) {
                kbMonitor.report(false, Translation.tr("No keyboard backlight device"));
                return;
            }
            // exec() stops whatever is already running, so firing it mid-flight
            // would kill an in-process write and have its signal-driven exit
            // reported as a failure ("check sudo access"). Wait for it instead;
            // the timer keeps coming back until the state matches.
            if (applyProc.running) {
                applyTimer.restart();
                return;
            }
            const key = kbMonitor.buildKey();
            if (key === kbMonitor.appliedKey) return;
            kbMonitor.pendingKey = key;
            kbMonitor.applying = true;
            // Arguments go in as an array, never through a shell: a malformed
            // colour cannot reach sh even if it slipped the validation above.
            applyProc.exec([
                "sudo", "-n", kbMonitor.helper, "set",
                "--color", kbMonitor.requestedColor,
                "--brightness", String(kbMonitor.brightnessPercent),
                "--mode", kbMonitor.rainbow ? "rainbow" : "static"
            ]);
        }

        function probe(): void {
            // exec() assigns its argument to `command`, so the whole argv must be
            // passed here: an empty list starts an empty command, which is why the
            // panel used to report "no device" even with a working helper.
            probeProc.exec(["sudo", "-n", kbMonitor.helper, "probe"]);
        }

        // Applies the state from a successful `set` reply instead of probing
        // for it again. The driving fields are only taken when no further apply
        // is queued, so a fast run of clicks cannot be undone by a reply that
        // describes an earlier one.
        function adoptApply(data): void {
            kbMonitor.available = true;
            if (typeof data.backend === "string") kbMonitor.backend = data.backend;
            if (typeof data.color === "string") kbMonitor.color = data.color;
            if (Array.isArray(data.levels)) kbMonitor.levels = data.levels;
            if (typeof data.off === "boolean") kbMonitor.off = data.off;
            if (!applyTimer.running) {
                if (typeof data.mode === "string") kbMonitor.rainbow = data.mode === "rainbow";
                if (typeof data.brightness === "number")
                    kbMonitor.brightness = kbMonitor.clampPercent(data.brightness);
            }
        }

        function adoptProbe(data): void {
            kbMonitor.available = data.available !== false;
            if (!kbMonitor.available) return;
            kbMonitor.backend = typeof data.backend === "string" ? data.backend : "";
            // The helper reports the closest colour it could display, which is
            // what the page must preview -- not the value that was requested.
            if (typeof data.color === "string") kbMonitor.color = data.color;
            if (Array.isArray(data.levels)) kbMonitor.levels = data.levels;
            kbMonitor.off = data.off === true;

            // A probe that lands while an apply is queued describes the state
            // from *before* that apply. Adopting it flips the control the user
            // just moved back to its old value, and the queued write then builds
            // the same key it already has -- so it never runs. That is exactly
            // what made the rainbow switch look dead, so the driving properties
            // are only taken from the hardware when nothing is in flight.
            const idle = !kbMonitor.applying && !applyTimer.running;
            if (idle) {
                kbMonitor.rainbow = data.rainbow === true;
                if (typeof data.brightness === "number")
                    kbMonitor.brightness = kbMonitor.clampPercent(data.brightness);
            }
            // The config may have been ready before the device was: this is the
            // first moment the stored colour can actually be pushed.
            if (Config.ready && !kbMonitor.configApplied) kbMonitor.applyFromConfig();
        }

        // QtObject has no default property, so every child is a property --
        // the same trick BrightnessMonitor uses for initProc.

        // One probe tells us the backend, the current colour and the stored
        // brightness; without a device the page says so instead of pretending.
        // The command is supplied by probe() below.
        readonly property Process probeProc: Process {
            stdout: StdioCollector { id: kbProbeOut }
            stderr: StdioCollector { id: kbProbeErr }
            onExited: (exitCode) => {
                if (exitCode !== 0) {
                    // sudo -n cannot prompt here, so the helper's own message
                    // (or sudo's) has to be shown verbatim.
                    const err = kbProbeErr.text.trim();
                    kbMonitor.available = false;
                    kbMonitor.report(false, err !== ""
                        ? err
                        : Translation.tr("Could not read the keyboard backlight."));
                    return;
                }
                const text = kbProbeOut.text.trim();
                if (text === "") return;
                let data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    kbMonitor.report(false, Translation.tr("Unexpected reply from the keyboard helper."));
                    return;
                }
                kbMonitor.adoptProbe(data);
                if (data.available === false) {
                    kbMonitor.report(false, data.error || Translation.tr("No keyboard backlight device"));
                } else if (!kbMonitor.applying) {
                    kbMonitor.report(true, "");
                }
            }
        }

        readonly property Process applyProc: Process {
            stdout: StdioCollector { id: kbApplyOut }
            stderr: StdioCollector { id: kbApplyErr }
            onExited: (exitCode) => {
                kbMonitor.applying = false;
                if (exitCode === 0) {
                    kbMonitor.appliedKey = kbMonitor.pendingKey;
                    kbMonitor.report(true, "");
                    // The helper's reply already carries the resulting colour,
                    // levels, brightness and mode, so the old follow-up probe()
                    // -- a second sudo spawn plus a second EC read after every
                    // single write -- is dropped. Fall back to it only if the
                    // reply could not be read.
                    let data = null;
                    try {
                        data = JSON.parse(kbApplyOut.text.trim());
                    } catch (e) {
                        data = null;
                    }
                    if (data && data.ok === true) kbMonitor.adoptApply(data);
                    else kbMonitor.probe();
                    return;
                }
                // Prefer the JSON error the helper wrote; fall back to whatever
                // sudo itself printed when it refused without a password.
                let detail = kbApplyErr.text.trim();
                if (detail === "") {
                    try {
                        const data = JSON.parse(kbApplyOut.text.trim());
                        if (data && data.error) detail = data.error;
                    } catch (e) { /* nothing better to show */ }
                }
                kbMonitor.report(false, detail !== ""
                    ? detail
                    : Translation.tr("Could not set the keyboard colour. Check sudo access to /usr/local/bin/kbd-rgb."));
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

        readonly property Timer applyTimer: Timer {
            interval: 80
            onTriggered: kbMonitor.doApply()
        }

        // The same mechanism every dynamic appearance element uses:
        // MaterialThemeLoader watches the generated theme file and rewrites
        // Appearance.colors, so this listens to the very signal the rest of the
        // shell already reacts to rather than sampling the wallpaper itself.
        readonly property Connections wallpaperColour: Connections {
            target: Appearance.colors
            function onColPrimaryChanged() { kbMonitor.restartFollow(); }
            function onColPrimaryActiveChanged() { kbMonitor.restartFollow(); }
            function onColSecondaryChanged() { kbMonitor.restartFollow(); }
            function onColTertiaryChanged() { kbMonitor.restartFollow(); }
        }


        Component.onCompleted: kbMonitor.probe()
    }

    // Exposed so the settings pages and the quick controls can read the level
    // and apply a colour. Nothing else in the shell owns this object.
    readonly property KeyboardBrightnessMonitor kbMonitor: KeyboardBrightnessMonitor {}

    // The named colours the settings UI offers, as hex: one table keeps the
    // Keyboard page swatches and the quick-control select from drifting apart.
    // These are the *requested* values; kbd-rgb snaps them to the ten levels
    // per channel the panel has, and the page previews the snapped result.
    readonly property var keyboardColors: [
        { value: "#ffffff", color: "#ffffff", displayName: Translation.tr("White") },
        { value: "#ff5252", color: "#ff5252", displayName: Translation.tr("Red") },
        { value: "#ff9800", color: "#ff9800", displayName: Translation.tr("Orange") },
        { value: "#ffd600", color: "#ffd600", displayName: Translation.tr("Yellow") },
        { value: "#4caf50", color: "#4caf50", displayName: Translation.tr("Green") },
        { value: "#26c6da", color: "#26c6da", displayName: Translation.tr("Cyan") },
        { value: "#42a5f5", color: "#42a5f5", displayName: Translation.tr("Blue") },
        { value: "#ab47bc", color: "#ab47bc", displayName: Translation.tr("Purple") },
        { value: "#ec407a", color: "#ec407a", displayName: Translation.tr("Magenta") },
        { value: "#000000", color: "#000000", displayName: Translation.tr("Off") }
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
