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

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Football.load()
        Updates.load()
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

        onPressed: {
            if (!SpeechToText.enabled) {
                Quickshell.execDetached(["notify-send", "Speech to text",
                    "Enable speech to text in the settings", "-a", "Hyprland"]);
                return;
            }
            SpeechToText.toggleRecording();
        }
    }
}