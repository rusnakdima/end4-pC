import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    signal requestBluetoothDialog()
    property bool advancedPasteOpen: false
    property bool imagePreviewOpen: false
    property bool barOpen: true
    // True while the bar is hidden by its auto hide, so that everything the
    // bar draws below itself (the music line under the island pill) can go
    // away with it.
    property bool barHidden: false
    property bool barStyleEditorOpen: false
    property bool crosshairOpen: false
    property bool equalizerOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    // The waffle family drives its own sidebars, so it never fights the
    // end4-pC sidebars for the same state.
    property bool waffleSidebarLeftOpen: false
    property bool waffleSidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool settingsOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool windowSwitcherOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property var settingsTarget: null

    // The single filter shared by the consolidated keybind block on the
    // Keyboard page and by search navigation. Activating a keybind result
    // clears it before opening the page, so the row being highlighted is
    // never hidden by a filter typed earlier.
    property string keybindFilter: ""

    // True while the Keyboard page is listening for a combination. The
    // settings window arms a compositor shortcut inhibitor with this, so a
    // chord that is already bound (SUPER+I, the settings toggle) reaches the
    // window instead of closing it. `keybindCaptureInhibited` is the
    // inhibitor's own report: when it stays false the compositor is still
    // holding the chord and the page offers the typed fallback.
    property bool keybindCaptureArmed: false
    property bool keybindCaptureInhibited: false

    // The theme's own WlSessionLock is the lock screen. A Quickshell reload or
    // a full qs restart destroys its lock surface; Hyprland then paints its
    // "lock screen died" fallback. misc:allow_session_lock_restore is enabled,
    // so the reloaded shell can take the lock back, but it has to remember that
    // the session is locked. This marker lives in the runtime dir (tmpfs) and
    // records the Hyprland instance, so a reboot or a compositor restart does
    // not inherit a stale lock.
    property bool lockStateInitialized: false
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"
    readonly property string lockStatePath: `${root.runtimeDir}/end4-pC-locked`
    // Set while Quickshell is reloading. Lives in tmpfs so a reboot clears it.
    readonly property string reloadMarkerPath: `${root.runtimeDir}/end4-pC-reloading`
    readonly property string lockStateSession: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "1"

    function initLockState(): void {
        if (root.lockStateInitialized || !Config.ready) return
        root.lockStateInitialized = true
        // A reload marker cannot outlive the shell instance that wrote it.
        reloadMarkerFile.setText("")
        if (Config.options.lock.useHyprlock) return
        const saved = lockStateFile.text().trim()
        if (saved !== "" && saved === root.lockStateSession) root.screenLocked = true
    }
    function writeLockState(locked: bool): void {
        lockStateFile.setText(locked ? root.lockStateSession : " ")
    }
    FileView {
        id: lockStateFile
        path: root.lockStatePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }
    FileView {
        id: reloadMarkerFile
        path: root.reloadMarkerPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }
    Connections {
        target: Config
        function onReadyChanged(): void { root.initLockState() }
    }
    Component.onCompleted: root.initLockState()

    onScreenLockedChanged: {
        root.writeLockState(root.screenLocked)
    }

    // Reloads while locked are safe: the lock marker makes the reloaded shell
    // acquire the theme lock again. Do not defer them, or verification reloads
    // while locked would silently do nothing.
    function requestShellReload(): void {
        reloadMarkerFile.setText(root.lockStateSession)
        Quickshell.reload(true);
    }

    CompositorGlobalShortcut {
        name: "shellReload"
        description: "Reload the theme"
        onPressed: root.requestShellReload()
    }

    // Lock with the theme's own lock screen. hyprlock remains an opt-in
    // fallback (Settings > Use Hyprlock), but the theme lock is the default.
    function lock(): void {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        // Write before changing the state so an immediate reload cannot lose it.
        root.writeLockState(true)
        root.screenLocked = true
    }

    function openSettingsAt(pageId, label, section, subsection) {
        root.settingsOpen = true;
        Qt.callLater(() => {
            root.settingsTarget = { page: pageId, label: label ?? "", section: section ?? "", subsection: subsection ?? "" };
        });
    }
    property Item currentPageInstance: null
    property list<real> visualizerPoints: []
    property bool desktopWidgetKeyboardFocus: false
    property bool desktopMenuOpen: false
    property var desktopMenuScreen: null
    property real desktopMenuX: 0
    property real desktopMenuY: 0
    property string wallpaperSelectorTarget: "wallpaper"
    property bool dropShelfOpen: false
    property real dropShelfX: 0
    property real dropShelfY: 0
    property string osdIndicatorType: "volume"
    property bool barCenterOnly: false
    property int dashboardPage: 0
    property string dashboardGroup: ""
    property var frameHover: ({})
    function setFrameHover(screenName, side, hovered) {
        const key = `${screenName}:${side}`;
        if ((root.frameHover[key] ?? false) === hovered) return;
        const next = Object.assign({}, root.frameHover);
        next[key] = hovered;
        root.frameHover = next;
    }
    function isFrameHovered(screenName, side) {
        return root.frameHover[`${screenName}:${side}`] ?? false;
    }
    property bool startupLockPending: true

    Timer {
        interval: 3000
        running: true
        onTriggered: root.startupLockPending = false
    }


    signal centeredWallpaperThumpRequested()

    // Shared by desktop (Background) and lock screen (LockSurface) scroll-to-cycle
    readonly property var centeredShapeOptions: [
        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
    ]
    function cycleCenteredWallpaperShape(direction) {
        const opts = root.centeredShapeOptions
        const i = opts.indexOf(Config.options.background.centeredWallpaperShape)
        Config.options.background.centeredWallpaperShape = opts[(i + direction + opts.length) % opts.length]
    }

    readonly property var hotCornerOptions: [
        { displayName: Translation.tr("None"),                  value: "none" },
        { displayName: Translation.tr("Left Sidebar"),           value: "sidebarLeftOpen" },
        { displayName: Translation.tr("Right Sidebar"),          value: "sidebarRightOpen" },
        { displayName: Translation.tr("Overview Launcher"),               value: "overviewOpen" },
        { displayName: Translation.tr("Wallpaper Selector"),     value: "wallpaperSelectorOpen" },
        { displayName: Translation.tr("Media Controls"),         value: "mediaControlsOpen" },
        { displayName: Translation.tr("Overlay"),                value: "overlayOpen" },
        { displayName: Translation.tr("ScreenShot Region"),        value: "regionSelectorOpen" },
        { displayName: Translation.tr("Screen Translator"),      value: "screenTranslatorOpen" },
        { displayName: Translation.tr("On-screen Keyboard"),     value: "oskOpen" },
        { displayName: Translation.tr("Session Menu"),           value: "sessionOpen" },
        { displayName: Translation.tr("Equalizer"),           value: "equalizerOpen" }
    ]

    function toggleState(name) {
        if (!name || name === "none") return;
        root[name] = !root[name];
    }
    
    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    Timer {
        id: barRefreshTimer
        interval: 200
        repeat: false
        onTriggered: {
            root.barOpen = true
        }
    }

    function refreshBar() {
        if (!root.barOpen) return;
        root.barOpen = false
        barRefreshTimer.restart()
    }

    CompositorGlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: { root.superDown = true }
        onReleased: { root.superDown = false }
    }

    IpcHandler {
        target: "background"
        function toggleCenteredWallpaper(): void {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
        }
    }

     CompositorGlobalShortcut {
        name: "centeredWallpaperToggle"
        description: "Toggles centered wallpaper"
        onPressed: {
            Config.options.background.centeredWallpaper = !Config.options.background.centeredWallpaper
        }
    }
}