//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_LOGGING_RULES=qt.text.font.db.info=false
// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1
import "modules/common"
import "services"
import "panelFamilies"
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    ReloadPopup {}

    Process {
        id: autostartProc
        command: ["python3", `${Directories.scriptPath}/hyprland/autostart.py`]
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return

            if (WM.compositor === "niri") {
                Config.options.background.lockWall = ""
                Config.options.overview.enable = false
            }

            if (Config.options.hyprland.autostartApps.enable &&
                Config.options.hyprland.autostartApps.apps.length > 0) {
                autostartProc.running = true
            }
        }
    }

    // Delay before forcing the non-visual services. Keep it short: it only
    // needs to cover one rendered frame, not a human-perceptible wait.
    property int deferredInitDelay: 100

    // Only work that decides what the first frame looks like belongs here.
    // Every call below instantiates a service singleton, so doing all of them
    // synchronously used to delay the bar and wallpaper by seconds. The rest
    // is moved to deferredInitTimer, which fires after the first paint.
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        Wallpapers.load()
        // The wallpaper image is re-applied from config on every shell start;
        // restart the clip's clock the same way so a video wallpaper is part
        // of the theme and starts playing instead of sitting on its poster.
        WallpaperVideo.restart()
        // The window mode has to be back in place before the first window
        // is looked at: the rules file covers the windows that open from
        // now on, and this brings the ones that are already open in line.
        WindowMode.apply()

        deferredInitTimer.start()
    }

    // Services whose state is not visible in the first frame (clipboard,
    // football scores, update count, first-run dialog, conflict check) and
    // the lazy singletons that own global shortcuts/IPC handlers. They are
    // still instantiated at startup, just after the shell has painted.
    Timer {
        id: deferredInitTimer
        interval: root.deferredInitDelay
        repeat: false
        onTriggered: {
            FirstRunExperience.load()
            ConflictKiller.load()
            Cliphist.refresh()
            Football.load()
            Updates.load()

            // Force the lazy singletons that own global shortcuts/IPC handlers.
            // Otherwise their targets only appear after the first time the
            // corresponding window happens to be opened.
            AdvancedPaste.close();
            ImagePreview.close();
            Peek.close();
            DesktopUtilities.stopFindMouse();
            // Owns the generated "quickshell:runCommand:<id>" shortcuts; reading
            // it here registers them before any Hyprland bind can dispatch one.
            GeneratedCommandShortcuts.reload();
        }
    }
    
    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }

    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }

    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    // Waffle family sidebars use their own flags and their own namespaced IPC
    // targets, so they never fight the end4-pC sidebars for the same state.

    CompositorGlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }

    // Registered here, and not in the service, because shell.qml is the one
    // file that is always loaded. Reading SpeechToText creates the
    // singleton.
    CompositorGlobalShortcut {
        name: "sttToggle"
        description: "Toggles speech to text"

        // One gesture enables the feature when it is off and starts recording.
        onPressed: SpeechToText.toggleDictation()
    }

    // Same entry point for scripts and compositors without Hyprland global
    // shortcuts: qs ipc call stt toggle
    IpcHandler {
        target: "stt"

        function toggle(): void {
            SpeechToText.toggleDictation();
        }

        function start(): void {
            if (!SpeechToText.recording) SpeechToText.toggleDictation();
        }

        function stop(): void {
            if (SpeechToText.recording) SpeechToText.stopRecording();
        }
    }
}
