pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * PowerToys-style Screen Ruler (Measure Tool).
 *
 * A modal overlay with a toolbar of four measuring modes — bounds, spacing,
 * horizontal and vertical. Spacing, horizontal and vertical snap to colour
 * edges found in a screen snapshot; bounds is drawn by dragging. Ctrl+1..4
 * switch modes, Esc or the toolbar's ✕ dismisses the tool, and a click copies
 * the current measurement to the clipboard before closing.
 */
Scope {
    id: root

    // Open on the monitor that had focus, and keep it there while the tool is
    // active so measurements do not jump when focus moves to another screen.
    property var activeScreen: null

    function pickScreen() {
        if (root.activeScreen !== null && DesktopUtilities.rulerActive) return root.activeScreen;
        const focusedName = WM.focusedMonitor?.name ?? Hyprland.focusedMonitor?.name ?? null;
        root.activeScreen = Quickshell.screens.find(s => s.name === focusedName) ?? Quickshell.screens[0] ?? null;
        return root.activeScreen;
    }

    Connections {
        target: DesktopUtilities
        function onRulerActiveChanged(active: bool) {
            if (!active) root.activeScreen = null;
        }
    }

    Loader {
        active: DesktopUtilities.rulerActive

        sourceComponent: PanelWindow {
            id: window
            screen: root.pickScreen()

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            focusable: true
            WlrLayershell.namespace: "quickshell:screenRuler"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // While the tool is open it owns the whole screen, like PowerToys:
            // clicks measure (or copy) instead of reaching the windows below.
            mask: Region { item: inputArea }

            readonly property real ratio: (window.screen?.devicePixelRatio ?? 1) || 1
            readonly property color measureColor: "#ff4d4f"
            // Sit below the panel instead of behind it (unless the bar is vertical).
            readonly property real toolbarY: Config.options.bar.vertical
                ? 16 : Appearance.sizes.barHeight + 12
            // Keep readouts clear of the toolbar and hint strip at the top.
            readonly property real labelTopSafe: window.toolbarY + 90
            readonly property bool edgeEnabled: DesktopUtilities.rulerMode === "spacing"
                || DesktopUtilities.rulerMode === "horizontal"
                || DesktopUtilities.rulerMode === "vertical"

            property bool dragging: false
            property bool moved: false
            property var dragStart: null
            property string copyText: ""
            property string edgeError: ""

            property bool showBounds: false
            property real boundsX: 0
            property real boundsY: 0
            property real boundsWidth: 0
            property real boundsHeight: 0
            property string boundsText: ""

            property bool showHorizontal: false
            property real hx1: 0
            property real hx2: 0
            property real hy: 0
            property string hText: ""

            property bool showVertical: false
            property real vx: 0
            property real vy1: 0
            property real vy2: 0
            property string vText: ""

            readonly property bool hasMeasurement: window.showBounds || window.showHorizontal || window.showVertical

            function clamp(value: real, low: real, high: real): real {
                return Math.min(Math.max(value, low), high);
            }

            function clearMeasurement(): void {
                window.showBounds = false;
                window.showHorizontal = false;
                window.showVertical = false;
                window.copyText = "";
                window.boundsText = "";
                window.hText = "";
                window.vText = "";
            }

            function setBounds(x: real, y: real, widthPx: real, heightPx: real, label: string): void {
                window.boundsX = window.clamp(Math.min(x, x + widthPx), 0, window.width);
                window.boundsY = window.clamp(Math.min(y, y + heightPx), 0, window.height);
                window.boundsWidth = Math.abs(widthPx);
                window.boundsHeight = Math.abs(heightPx);
                window.boundsText = label;
                window.copyText = label;
                window.showBounds = true;
            }

            function setHorizontal(x1: real, x2: real, y: real, label: string): void {
                window.hx1 = window.clamp(Math.min(x1, x2), 0, window.width);
                window.hx2 = window.clamp(Math.max(x1, x2), 0, window.width);
                window.hy = window.clamp(y, 0, window.height);
                window.hText = label;
                window.copyText = label;
                window.showHorizontal = true;
            }

            function setVertical(x: real, y1: real, y2: real, label: string): void {
                window.vx = window.clamp(x, 0, window.width);
                window.vy1 = window.clamp(Math.min(y1, y2), 0, window.height);
                window.vy2 = window.clamp(Math.max(y1, y2), 0, window.height);
                window.vText = label;
                window.copyText = label;
                window.showVertical = true;
            }

            function pixelLabel(value: real): string {
                return `${Math.round(value * window.ratio)} px`;
            }

            function edgeQueryMode(): string {
                switch (DesktopUtilities.rulerMode) {
                case "horizontal": return "h";
                case "vertical": return "v";
                default: return "b";
                }
            }

            function startEdgeProcess(): void {
                if (!window.edgeEnabled) {
                    edgeProc.running = false;
                    window.edgeError = "";
                    return;
                }
                edgeProc.running = false;
                const command = [
                    "python3", `${Directories.scriptPath}/screen_ruler_edges.py`,
                    "--ratio", String(window.ratio),
                    "--tolerance", String(DesktopUtilities.rulerTolerance)
                ];
                const outputName = window.screen?.name ?? "";
                if (outputName.length > 0) command.push("--output", outputName);
                edgeProc.command = command;
                edgeProc.running = true;
            }

            function applyEdgeResult(result: var): void {
                if (result.error) {
                    window.edgeError = "Edge detection unavailable — drag to measure";
                    window.clearMeasurement();
                    return;
                }
                window.edgeError = "";
                const mode = DesktopUtilities.rulerMode;
                if (mode === "horizontal") {
                    window.setHorizontal(result.left, result.right, result.y, window.pixelLabel(result.width));
                } else if (mode === "vertical") {
                    window.setVertical(result.x, result.top, result.bottom, window.pixelLabel(result.height));
                } else if (mode === "spacing") {
                    window.clearMeasurement();
                    window.setHorizontal(result.left, result.right, result.y, window.pixelLabel(result.width));
                    window.setVertical(result.x, result.top, result.bottom, window.pixelLabel(result.height));
                    window.copyText = `${window.hText} × ${window.vText}`;
                }
            }

            function beginDrag(point: var): void {
                window.dragging = true;
                window.moved = false;
                window.dragStart = point;
                if (DesktopUtilities.rulerMode === "bounds") {
                    window.clearMeasurement();
                    window.setBounds(point.x, point.y, 0, 0, "0 × 0 px");
                }
            }

            function updateDrag(point: var): void {
                if (!window.dragging || !window.dragStart) return;
                const start = window.dragStart;
                if (Math.abs(point.x - start.x) > 4 || Math.abs(point.y - start.y) > 4) window.moved = true;
                const mode = DesktopUtilities.rulerMode;
                if (mode === "bounds") {
                    window.setBounds(start.x, start.y, point.x - start.x, point.y - start.y,
                        `${window.pixelLabel(Math.abs(point.x - start.x))} × ${window.pixelLabel(Math.abs(point.y - start.y))}`);
                } else if (mode === "horizontal") {
                    window.setHorizontal(start.x, point.x, start.y, window.pixelLabel(Math.abs(point.x - start.x)));
                } else if (mode === "vertical") {
                    window.setVertical(start.x, start.y, point.y, window.pixelLabel(Math.abs(point.y - start.y)));
                } else if (mode === "spacing") {
                    window.clearMeasurement();
                    window.setHorizontal(start.x, point.x, start.y, window.pixelLabel(Math.abs(point.x - start.x)));
                    window.setVertical(start.x, start.y, point.y, window.pixelLabel(Math.abs(point.y - start.y)));
                    window.copyText = `${window.hText} × ${window.vText}`;
                }
            }

            function finishClick(): void {
                if (window.moved) {
                    window.moved = false;
                    return;
                }
                if (window.copyText.length > 0) DesktopUtilities.copyRulerMeasurement(window.copyText);
                DesktopUtilities.closeRuler();
            }

            Connections {
                target: DesktopUtilities
                function onRulerModeChanged(): void {
                    window.clearMeasurement();
                    window.startEdgeProcess();
                }
                function onRulerToleranceChanged(): void {
                    window.startEdgeProcess();
                }
                function onRulerContinuousChanged(): void {
                    window.startEdgeProcess();
                }
            }

            Process {
                id: edgeProc
                stdinEnabled: true
                stdout: SplitParser {
                    onRead: line => {
                        try {
                            window.applyEdgeResult(JSON.parse(line));
                        } catch (error) {
                            window.edgeError = "Edge detection unavailable — drag to measure";
                        }
                    }
                }
            }

            // Snapshot-based detection only needs re-capturing when the user
            // asks for continuous mode; otherwise one grab per activation.
            Timer {
                id: recaptureTimer
                interval: 500
                repeat: true
                running: DesktopUtilities.rulerContinuous && window.edgeEnabled
                onTriggered: window.startEdgeProcess()
            }

            // Mouse moves are throttled so the helper is not flooded.
            Timer {
                id: hoverTimer
                interval: 50
                repeat: false
                property real pointX: 0
                property real pointY: 0
                onTriggered: {
                    if (!edgeProc.running || window.dragging) return;
                    edgeProc.write(`${window.edgeQueryMode()} ${hoverTimer.pointX} ${hoverTimer.pointY}\n`);
                }
            }

            Item {
                id: keyHandler
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        DesktopUtilities.closeRuler();
                        event.accepted = true;
                    } else if (event.modifiers & Qt.ControlModifier) {
                        const modes = {
                            [Qt.Key_1]: "bounds",
                            [Qt.Key_2]: "spacing",
                            [Qt.Key_3]: "horizontal",
                            [Qt.Key_4]: "vertical"
                        };
                        const mode = modes[event.key];
                        if (mode) {
                            DesktopUtilities.setRulerMode(mode);
                            event.accepted = true;
                        }
                    }
                }
                Component.onCompleted: Qt.callLater(() => keyHandler.forceActiveFocus())
            }

            Item {
                id: inputArea
                anchors.fill: parent
                z: 1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onPressed: mouse => {
                        if (mouse.button === Qt.LeftButton) window.beginDrag({ x: mouse.x, y: mouse.y });
                    }
                    onPositionChanged: mouse => {
                        if (window.dragging) {
                            window.updateDrag({ x: mouse.x, y: mouse.y });
                        } else if (window.edgeEnabled && edgeProc.running) {
                            hoverTimer.pointX = mouse.x;
                            hoverTimer.pointY = mouse.y;
                            if (!hoverTimer.running) hoverTimer.restart();
                        }
                    }
                    onReleased: mouse => {
                        if (mouse.button === Qt.LeftButton) window.dragging = false;
                    }
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) window.finishClick();
                    }
                }
            }

            // Measurement lines, drawn above the desktop but below the toolbar.
            Item {
                id: graphics
                anchors.fill: parent
                z: 2
                visible: window.hasMeasurement

                Rectangle {
                    visible: window.showBounds
                    x: window.boundsX
                    y: window.boundsY
                    width: window.boundsWidth
                    height: window.boundsHeight
                    color: "transparent"
                    border.width: 2
                    border.color: window.measureColor
                }

                Rectangle {
                    visible: window.showHorizontal
                    x: window.hx1
                    y: window.hy - 1
                    width: Math.max(2, window.hx2 - window.hx1)
                    height: 2
                    color: window.measureColor
                }
                Rectangle {
                    visible: window.showHorizontal && window.hx2 - window.hx1 > 2
                    x: window.hx1
                    y: window.hy - 5
                    width: 2
                    height: 10
                    color: window.measureColor
                }
                Rectangle {
                    visible: window.showHorizontal && window.hx2 - window.hx1 > 2
                    x: window.hx2 - 2
                    y: window.hy - 5
                    width: 2
                    height: 10
                    color: window.measureColor
                }

                Rectangle {
                    visible: window.showVertical
                    x: window.vx - 1
                    y: window.vy1
                    width: 2
                    height: Math.max(2, window.vy2 - window.vy1)
                    color: window.measureColor
                }
                Rectangle {
                    visible: window.showVertical && window.vy2 - window.vy1 > 2
                    x: window.vx - 5
                    y: window.vy1
                    width: 10
                    height: 2
                    color: window.measureColor
                }
                Rectangle {
                    visible: window.showVertical && window.vy2 - window.vy1 > 2
                    x: window.vx - 5
                    y: window.vy2 - 2
                    width: 10
                    height: 2
                    color: window.measureColor
                }

                // Labels flip to the free side and clamp inside the monitor so
                // a measurement started at a screen corner stays readable.
                Rectangle {
                    id: boundsLabelBox
                    visible: window.showBounds
                    implicitWidth: boundsLabel.implicitWidth + 12
                    implicitHeight: boundsLabel.implicitHeight + 6
                    x: {
                        const w = boundsLabelBox.implicitWidth;
                        return window.clamp(window.boundsX - w / 2, 6, Math.max(6, window.width - w - 6));
                    }
                    y: {
                        const h = boundsLabelBox.implicitHeight;
                        const above = window.boundsY - h - 6;
                        if (above >= window.labelTopSafe) return above;
                        return window.clamp(Math.max(window.boundsY + 6, window.labelTopSafe),
                            window.labelTopSafe, Math.max(window.labelTopSafe, window.height - h - 6));
                    }
                    radius: 6
                    color: Appearance.colors.colSecondaryContainer
                    StyledText {
                        id: boundsLabel
                        anchors.centerIn: parent
                        text: window.boundsText
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                Rectangle {
                    id: hLabelBox
                    visible: window.showHorizontal
                    implicitWidth: hLabel.implicitWidth + 12
                    implicitHeight: hLabel.implicitHeight + 6
                    x: {
                        const w = hLabelBox.implicitWidth;
                        return window.clamp((window.hx1 + window.hx2) / 2 - w / 2, 6, Math.max(6, window.width - w - 6));
                    }
                    y: {
                        const h = hLabelBox.implicitHeight;
                        const above = window.hy - h - 8;
                        if (above >= window.labelTopSafe) return above;
                        return window.clamp(Math.max(window.hy + 8, window.labelTopSafe),
                            window.labelTopSafe, Math.max(window.labelTopSafe, window.height - h - 6));
                    }
                    radius: 6
                    color: Appearance.colors.colSecondaryContainer
                    StyledText {
                        id: hLabel
                        anchors.centerIn: parent
                        text: window.hText
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                Rectangle {
                    id: vLabelBox
                    visible: window.showVertical
                    implicitWidth: vLabel.implicitWidth + 12
                    implicitHeight: vLabel.implicitHeight + 6
                    x: {
                        const w = vLabelBox.implicitWidth;
                        const right = window.vx + 8;
                        if (right + w + 6 <= window.width) return right;
                        return window.clamp(window.vx - w - 8, 6, Math.max(6, window.width - w - 6));
                    }
                    y: {
                        const h = vLabelBox.implicitHeight;
                        return window.clamp((window.vy1 + window.vy2) / 2 - h / 2,
                            window.labelTopSafe, Math.max(window.labelTopSafe, window.height - h - 6));
                    }
                    radius: 6
                    color: Appearance.colors.colSecondaryContainer
                    StyledText {
                        id: vLabel
                        anchors.centerIn: parent
                        text: window.vText
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            Rectangle {
                id: toolbar
                z: 3
                anchors.horizontalCenter: parent.horizontalCenter
                y: window.toolbarY
                width: toolbarRow.implicitWidth + 16
                height: 48
                radius: 14
                color: Appearance.colors.colLayer2Base
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                Row {
                    id: toolbarRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "bounds", icon: "crop_free", key: "1" },
                            { id: "spacing", icon: "add", key: "2" },
                            { id: "horizontal", icon: "horizontal_rule", key: "3" },
                            { id: "vertical", icon: "horizontal_rule", key: "4" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 44
                            height: 36
                            radius: 8
                            color: DesktopUtilities.rulerMode === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : (modeArea.containsMouse
                                    ? Appearance.colors.colLayer4Base
                                    : Appearance.colors.colLayer3Base)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.larger
                                color: DesktopUtilities.rulerMode === modelData.id
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurfaceVariant
                                rotation: modelData.id === "vertical" ? 90 : 0
                            }
                            StyledText {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 3
                                text: modelData.key
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea {
                                id: modeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: DesktopUtilities.setRulerMode(modelData.id)
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        color: Appearance.colors.colOutlineVariant
                    }

                    // Live readout for the active mode, so switching modes
                    // immediately shows the number that mode is measuring.
                    Rectangle {
                        implicitWidth: readoutText.implicitWidth + 16
                        height: 36
                        radius: 8
                        color: Appearance.colors.colLayer4Base
                        StyledText {
                            id: readoutText
                            anchors.centerIn: parent
                            text: window.copyText.length > 0
                                ? window.copyText
                                : (DesktopUtilities.rulerMode === "none" ? "—" : "— px")
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: 40
                        height: 36
                        radius: 8
                        color: closeArea.containsMouse
                            ? Appearance.colors.colLayer4Base
                            : Appearance.colors.colLayer3Base
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: DesktopUtilities.closeRuler()
                        }
                    }
                }
            }

            StyledText {
                id: hint
                z: 3
                anchors.horizontalCenter: parent.horizontalCenter
                y: window.toolbarY + 56
                text: window.edgeError.length > 0
                    ? window.edgeError
                    : (DesktopUtilities.rulerMode === "none"
                        ? "Choose a mode · Ctrl+1–4 · Esc to close"
                        : (window.hasMeasurement ? "Click to copy · Esc to close" : "Drag to measure · Click to copy"))
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            Component.onCompleted: {
                window.startEdgeProcess();
                Qt.callLater(() => keyHandler.forceActiveFocus());
            }
        }
    }
}
