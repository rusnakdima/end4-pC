pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Alt+Tab window switcher.
 *
 * The deck prefers the focused workspace, widens to the focused monitor, then
 * to every mapped window when the chosen scope has fewer than two candidates
 * (configurable). Cards are ordered by Hyprland's focusHistoryID (most recently
 * used first), and cycling only moves the highlight; the real focus change
 * happens on commit, which keeps the compositor's focus history honest.
 *
 * Input comes from:
 *   - the bound Alt+Tab shortcut (Shift reverses via the tracked modifier),
 *   - hyprland/window_switch.lua (Alt release = commit, Shift state, no second
 *     keysym bind),
 *   - the exclusive keyboard grab while open (Escape, Enter, arrows),
 *   - the pointer (click commits, wheel cycles).
 */
Scope {
    id: root

    readonly property bool enabled: (Config.options?.windowSwitcher?.enable ?? true) && WM.compositor === "hyprland"
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property var targetScreen: Quickshell.screens.find(s => s.name === root.panelScreenName) ?? null
    readonly property real screenWidth: root.targetScreen?.width ?? 1920
    readonly property real screenHeight: root.targetScreen?.height ?? 1080
    // Material's scrim is always the scrim colour; only its opacity changes
    // between themes. Light mode uses the standard 32% dim, dark mode a
    // slightly deeper 45% so the light cards still read as elevated.
    readonly property bool darkMode: Appearance.m3colors.darkmode
    readonly property color scrimColor: ColorUtils.applyAlpha(
        Appearance.m3colors.m3scrim, root.darkMode ? 0.45 : 0.32)
    readonly property color pillColor: ColorUtils.applyAlpha(
        Appearance.m3colors.m3surfaceContainerHigh, root.darkMode ? 0.80 : 0.92)
    readonly property color pillBorderColor: ColorUtils.applyAlpha(
        Appearance.colors.colOutlineVariant, root.darkMode ? 0.50 : 0.55)
    // The scrim is dark in both themes, so the hint text is always onScrim.
    readonly property color hintColor: ColorUtils.applyAlpha("#ffffff", 0.78)
    readonly property int cardWidth: Math.max(220, Math.round(Math.min(
        Config.options?.windowSwitcher?.cardWidth ?? 400,
        root.screenWidth * 0.34,
        (root.screenHeight * 0.46) / 0.625
    )))
    readonly property real cardHeight: Math.round(root.cardWidth * 0.625)
    readonly property real cardStep: root.cardWidth * 0.62
    // Two cards on each side on a normal screen; a narrow screen only has room
    // for one, and the counter still tells the user how many windows there are.
    readonly property int visibleDistance: root.screenWidth < 1200 ? 1 : 2

    property var entries: []
    property int selectedIndex: 0
    property string openedWorkspaceId: ""
    property string openedWorkspaceLabel: ""
    property string openedScope: "workspace"
    property string panelScreenName: ""
    property bool closing: false
    // Maintained from hyprland/window_switch.lua. Hyprland keeps delivering the
    // Alt+Tab bind when Shift is also held, so the direction is decided here
    // instead of with a second key translation.
    property bool shiftHeld: false

    readonly property var selectedEntry: root.entries.length > 0
        ? root.entries[Math.max(0, Math.min(root.selectedIndex, root.entries.length - 1))]
        : null

    // In strict workspace mode the header names the focused workspace. When
    // the deck widens, follow the highlighted card instead, so the header
    // always shows the workspace the selected window actually belongs to.
    readonly property string headerLabel: {
        if (root.openedScope === "workspace" || !root.selectedEntry)
            return root.openedWorkspaceLabel;
        const workspace = root.selectedEntry.windowData?.workspace;
        return `${Translation.tr("Workspace")} ${workspace?.name ?? workspace?.id ?? ""}`;
    }

    function addressOf(toplevel) {
        const address = toplevel?.HyprlandToplevel?.address;
        return address ? `0x${address}` : "";
    }

    function workspaceBadgeFor(entry) {
        const workspace = entry?.windowData?.workspace;
        if (!workspace)
            return "";
        // The workspace name is authoritative: numeric workspaces read as "1",
        // named ones keep their name instead of collapsing to an id.
        return workspace.name ?? String(workspace.id);
    }

    function buildEntries() {
        const activeAddress = root.addressOf(ToplevelManager.activeToplevel);
        const windows = [];

        for (const toplevel of ToplevelManager.toplevels.values) {
            if (!toplevel?.HyprlandToplevel)
                continue;
            const address = root.addressOf(toplevel);
            const windowData = HyprlandData.windowByAddress[address];
            if (!windowData)
                continue;
            if (windowData.hidden || windowData.mapped === false)
                continue;
            windows.push({ toplevel: toplevel, address: address, windowData: windowData });
        }

        // focusHistoryID is Hyprland's MRU index (0 = focused). Filtering later
        // keeps the relative order of whichever scope is selected.
        windows.sort((a, b) => (a.windowData.focusHistoryID ?? 100000) - (b.windowData.focusHistoryID ?? 100000));

        // Defensive: the focused window must be the first card even if the
        // client list was refreshed a moment late.
        const currentIndex = windows.findIndex(w => w.address === activeAddress);
        if (currentIndex > 0)
            windows.unshift(windows.splice(currentIndex, 1)[0]);

        const workspaceId = root.focusedMonitor?.activeWorkspace?.id ?? 1;
        const monitorId = root.focusedMonitor?.id ?? -1;
        const inWorkspace = windows.filter(w => w.windowData.workspace?.id === workspaceId);
        const onMonitor = windows.filter(w => w.windowData.monitor === monitorId);

        const configuredScope = Config.options?.windowSwitcher?.scope ?? "workspace";
        const allowFallback = Config.options?.windowSwitcher?.fallback ?? true;
        let selected;
        let scope;

        // Prefer the focused workspace. When it cannot offer a real choice
        // (the common one-window-per-workspace layout), widen to the monitor
        // and finally to every window, instead of turning Alt+Tab into a no-op.
        if (configuredScope === "all") {
            selected = windows;
            scope = "all";
        } else if (configuredScope === "monitor") {
            if (onMonitor.length >= 2 || !allowFallback) {
                selected = onMonitor;
                scope = "monitor";
            } else {
                selected = windows;
                scope = "all";
            }
        } else {
            if (inWorkspace.length >= 2 || !allowFallback) {
                selected = inWorkspace;
                scope = "workspace";
            } else if (onMonitor.length >= 2) {
                selected = onMonitor;
                scope = "monitor";
            } else {
                selected = windows;
                scope = "all";
            }
        }

        root.openedScope = scope;
        const workspaceName = root.focusedMonitor?.activeWorkspace?.name ?? String(workspaceId);
        root.openedWorkspaceLabel = scope === "workspace"
            ? `${Translation.tr("Workspace")} ${workspaceName}`
            : (scope === "monitor" ? Translation.tr("This monitor") : Translation.tr("All windows"));

        return selected;
    }

    function openSwitcher(direction = 1) {
        if (!root.enabled)
            return;

        if (GlobalStates.windowSwitcherOpen) {
            root.step(direction);
            return;
        }

        const list = root.buildEntries();
        if (list.length < 2)
            return;

        closeTimer.stop();
        root.closing = false;
        // The two full-screen overlays would stack; the switcher wins.
        GlobalStates.overviewOpen = false;
        root.entries = list;
        // Opening shows the previous window; Shift reverses from the oldest.
        root.selectedIndex = direction < 0 ? list.length - 1 : 1;
        const workspace = root.focusedMonitor?.activeWorkspace;
        root.openedWorkspaceId = String(workspace?.id ?? 1);
        root.panelScreenName = root.focusedMonitor?.name
            ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
        GlobalStates.windowSwitcherOpen = true;
        safetyTimer.restart();
    }

    function step(delta) {
        if (!GlobalStates.windowSwitcherOpen)
            return;
        const count = root.entries.length;
        if (count < 2)
            return;
        root.selectedIndex = (root.selectedIndex + delta + count) % count;
        safetyTimer.restart();
    }

    function cycle(delta) {
        root.openSwitcher(root.shiftHeld ? -delta : delta);
    }

    function select(index) {
        if (index < 0 || index >= root.entries.length || index === root.selectedIndex)
            return;
        root.selectedIndex = index;
        safetyTimer.restart();
    }

    function commit() {
        if (!GlobalStates.windowSwitcherOpen)
            return;
        const entry = root.selectedEntry;
        root.close();
        if (entry)
            WM.focusWindow(entry.address);
    }

    function cancel() {
        if (!GlobalStates.windowSwitcherOpen)
            return;
        root.close();
    }

    function close() {
        GlobalStates.windowSwitcherOpen = false;
        root.closing = true;
        safetyTimer.stop();
        closeTimer.restart();
    }

    function pruneEntries() {
        if (!GlobalStates.windowSwitcherOpen)
            return;
        const selectedAddress = root.selectedEntry?.address;
        const next = root.entries.filter(entry => {
            const windowData = HyprlandData.windowByAddress[entry.address];
            return windowData && !windowData.hidden && windowData.mapped !== false;
        });
        if (next.length === root.entries.length)
            return;
        if (next.length < 2) {
            root.cancel();
            return;
        }
        root.entries = next;
        // Keep the highlight on the same window when the list shifts around it.
        const selectedIndex = next.findIndex(entry => entry.address === selectedAddress);
        root.selectedIndex = selectedIndex >= 0
            ? selectedIndex
            : Math.min(root.selectedIndex, next.length - 1);
    }

    // A missed compositor release must never leave a full-screen input layer
    // behind, so the switcher gives up on its own.
    Timer {
        id: safetyTimer
        interval: 8000
        onTriggered: root.commit()
    }

    Timer {
        id: closeTimer
        interval: 180
        onTriggered: root.closing = false
    }

    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            root.pruneEntries();
        }
    }

    PanelWindow {
        id: panelWindow

        visible: GlobalStates.windowSwitcherOpen || root.closing
        screen: root.targetScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "quickshell:windowSwitcher"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive only while open, so Escape/Enter/arrows are consumed by the
        // deck instead of leaking into the focused application. Compositor
        // binds (Alt+Tab) and the raw Alt-release hook keep working either way.
        WlrLayershell.keyboardFocus: GlobalStates.windowSwitcherOpen
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // The whole screen is modal while open, so a click outside cancels
        // instead of reaching the window underneath.
        mask: Region {
            item: GlobalStates.windowSwitcherOpen ? backdrop : null
        }

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: root.scrimColor
            opacity: stage.opacity

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: root.cancel()
                onWheel: wheel => {
                    if (wheel.angleDelta.y !== 0)
                        root.step(wheel.angleDelta.y < 0 ? 1 : -1);
                }
            }
        }

        Item {
            id: stage
            anchors.fill: parent
            focus: GlobalStates.windowSwitcherOpen
            opacity: GlobalStates.windowSwitcherOpen ? 1 : 0
            scale: GlobalStates.windowSwitcherOpen ? 1 : 0.93
            transformOrigin: Item.Center

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.cancel();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commit();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                    root.step(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                    root.step(1);
                    event.accepted = true;
                }
            }

            Connections {
                target: GlobalStates
                function onWindowSwitcherOpenChanged() {
                    if (GlobalStates.windowSwitcherOpen) {
                        stage.forceActiveFocus();
                        focusRetry.restart();
                    }
                }
            }

            // The surface may map one frame after the state flips, so the
            // first focus request can land on an inactive window.
            Timer {
                id: focusRetry
                interval: 40
                onTriggered: stage.forceActiveFocus()
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(stage)
            }

            Column {
                anchors.centerIn: parent
                width: stage.width
                spacing: 16

                // Workspace and position: "Workspace 2 · 3 / 7".
                Item {
                    width: parent.width
                    height: headerPill.implicitHeight

                    Rectangle {
                        id: headerPill
                        anchors.centerIn: parent
                        implicitWidth: headerRow.implicitWidth + 26
                        implicitHeight: 30
                        radius: height / 2
                        color: root.pillColor
                        border.width: 1
                        border.color: root.pillBorderColor

                        Row {
                            id: headerRow
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "workspaces"
                                iconSize: 15
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.headerLabel
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: 3
                                radius: 1.5
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnSurfaceVariant, 0.5)
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${root.selectedIndex + 1} / ${root.entries.length}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.features: ({ "tnum": 1 })
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }

                // The fan. The selected card sits in the middle; up to two
                // cards on each side peek out behind it with a lower scale and
                // opacity (one per side on a narrow monitor).
                Item {
                    id: deckArea
                    width: parent.width
                    height: root.cardHeight + 36

                    Repeater {
                        model: root.entries

                        delegate: WindowSwitcherCard {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property int offset: index - root.selectedIndex
                            readonly property int distance: Math.abs(offset)
                            readonly property bool shown: distance <= root.visibleDistance

                            entry: modelData
                            selected: index === root.selectedIndex
                            cardWidth: root.cardWidth
                            cardHeight: root.cardHeight
                            workspaceBadge: root.openedScope === "workspace"
                                ? ""
                                : root.workspaceBadgeFor(modelData)
                            visible: shown
                            x: deckArea.width / 2 - width / 2
                                + Math.max(-(root.visibleDistance + 0.4),
                                    Math.min(root.visibleDistance + 0.4, offset)) * root.cardStep
                            y: (deckArea.height - height) / 2
                                + Math.min(root.visibleDistance, distance) * 13
                            scale: Math.pow(0.86, Math.min(root.visibleDistance, distance))
                            opacity: shown
                                ? 1 - Math.min(root.visibleDistance, distance) * 0.10
                                : 0
                            z: 100 - distance

                            onRequestActivate: {
                                root.select(index);
                                root.commit();
                            }

                            Behavior on x {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                            }
                            Behavior on y {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                            }
                            Behavior on scale {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                            }
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                            }
                        }
                    }
                }

                // Caption for the highlighted card, on its own pill so the
                // text stays readable over both light and dark wallpapers.
                Item {
                    width: parent.width
                    height: captionPill.implicitHeight

                    Rectangle {
                        id: captionPill
                        anchors.centerIn: parent
                        implicitWidth: captionRow.implicitWidth + 28
                        implicitHeight: captionRow.implicitHeight + 12
                        radius: 16
                        color: root.pillColor
                        border.width: 1
                        border.color: root.pillBorderColor

                        Row {
                            id: captionRow
                            anchors.centerIn: parent
                            spacing: 10

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22

                                Image {
                                    id: captionIcon
                                    anchors.fill: parent
                                    source: root.selectedEntry
                                        ? SystemAppearance.iconPath(AppSearch.guessIcon(root.selectedEntry.windowData?.class), "")
                                        : ""
                                    sourceSize: Qt.size(22, 22)
                                    fillMode: Image.PreserveAspectFit
                                    visible: source !== "" && status === Image.Ready
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "web_asset"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurfaceVariant
                                    visible: captionIcon.status !== Image.Ready
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                StyledText {
                                    width: Math.min(implicitWidth, 620)
                                    text: root.selectedEntry?.windowData?.title ?? ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    width: Math.min(implicitWidth, 620)
                                    text: {
                                        const entry = root.selectedEntry;
                                        const className = entry?.windowData?.class ?? "";
                                        if (root.openedScope === "workspace" || !entry)
                                            return className;
                                        const workspace = entry.windowData?.workspace;
                                        return `${className}  ·  ${Translation.tr("Workspace")} ${workspace?.name ?? workspace?.id ?? ""}`;
                                    }
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }

                // Key hints, kept quiet so they do not compete with the cards.
                Item {
                    width: parent.width
                    height: hintRow.implicitHeight

                    Row {
                        id: hintRow
                        anchors.centerIn: parent
                        spacing: 7

                        KeyCap { label: "Alt" }
                        KeyCap { label: "Tab" }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("cycle")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.hintColor
                        }
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: 1
                        }
                        KeyCap { label: "Esc" }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("cancel")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.hintColor
                        }
                    }
                }
            }
        }
    }

    component KeyCap: Rectangle {
        id: keyCap
        property string label: ""

        implicitWidth: keyLabel.implicitWidth + 14
        implicitHeight: 22
        radius: 6
        color: ColorUtils.applyAlpha("#ffffff", 0.14)
        border.width: 1
        border.color: ColorUtils.applyAlpha("#ffffff", 0.24)

        StyledText {
            id: keyLabel
            anchors.centerIn: parent
            text: keyCap.label
            font.pixelSize: 11
            font.family: Appearance.font.family.monospace
            color: ColorUtils.applyAlpha("#ffffff", 0.92)
        }
    }

    IpcHandler {
        target: "windowSwitcher"

        function next(): void {
            root.openSwitcher(1);
        }
        function prev(): void {
            root.openSwitcher(-1);
        }
        function close(): void {
            root.cancel();
        }
        function commit(): void {
            root.commit();
        }
        function status(): string {
            return JSON.stringify({
                open: GlobalStates.windowSwitcherOpen,
                enabled: root.enabled,
                entries: root.entries.length,
                selected: root.selectedIndex,
                workspace: root.openedWorkspaceId,
                scope: root.openedScope,
                screen: root.panelScreenName,
                closing: root.closing,
                darkmode: Appearance.m3colors.darkmode,
                m3background: String(Appearance.m3colors.m3background),
                scrim: String(root.scrimColor),
                pill: String(root.pillColor)
            });
        }
    }

    CompositorGlobalShortcut {
        name: "windowSwitcherNext"
        description: "Cycles the workspace window switcher forward (Shift reverses)"

        onPressed: root.cycle(1)
    }

    CompositorGlobalShortcut {
        name: "windowSwitcherPrev"
        description: "Cycles the workspace window switcher backward"

        onPressed: root.openSwitcher(-1)
    }

    CompositorGlobalShortcut {
        name: "windowSwitcherShiftDown"
        description: "Tracks the Shift modifier for the window switcher"

        onPressed: root.shiftHeld = true
    }

    CompositorGlobalShortcut {
        name: "windowSwitcherShiftUp"
        description: "Tracks the Shift modifier for the window switcher"

        onPressed: root.shiftHeld = false
    }

    CompositorGlobalShortcut {
        name: "windowSwitcherCommit"
        description: "Applies the window switcher selection"

        onPressed: root.commit()
    }

    CompositorGlobalShortcut {
        name: "windowSwitcherCancel"
        description: "Closes the window switcher without switching"

        onPressed: root.cancel()
    }
}
