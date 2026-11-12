pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Chip + popup that routes a single audio stream (an app source) to a specific
 * output/input device, while the global default device keeps serving every
 * other stream. The first popup entry, "Default", resets the stream back to
 * the system default device (it is just a move to that device, so the stream
 * keeps following default-device changes afterwards).
 *
 * The chip shows the device the audio really ends on: filter chains
 * (easyeffects_sink -> ...) are resolved to their hardware output, so a
 * stream playing through EasyEffects reads "Default" when EasyEffects
 * outputs to the default device instead of naming the filter.
 *
 * EasyEffects re-pins every stream it claims back to itself within ~400 ms,
 * so a pick arbitrates it: routing into EasyEffects turns it on first,
 * routing anywhere else turns it off, and the move waits for the filter
 * node to appear/disappear. If the stream still is not where it was picked
 * after `bounceTimeout` ms, the user gets a desktop notice instead of a
 * chip that silently keeps showing another device.
 *
 * The popup is clamped to `clampItem` (the mixer card/widget hosting this
 * chip) so it is never clipped by list clipping, small overlay widgets or
 * input masks.
 */
RippleButton {
    id: root

    required property PwNode node
    // Item whose bounds the popup stays inside. Falls back to the window.
    property Item clampItem: null
    property real maximumWidth: 130

    readonly property bool isSink: node?.isSink ?? true
    readonly property PwNode defaultDevice: Audio.defaultDevice(root.isSink)
    // Chain-resolved: filter nodes (EasyEffects) are followed to their output.
    readonly property PwNode currentDevice: Audio.streamDevice(root.node)
    readonly property bool followingDefault: root.currentDevice === null
        || (root.defaultDevice !== null && root.currentDevice.id === root.defaultDevice.id)
    readonly property PwNode shownDevice: root.currentDevice ?? root.defaultDevice
    readonly property string label: root.followingDefault ? Translation.tr("Default") : Audio.friendlyDeviceName(root.shownDevice)
    // Set while a pick is in flight; checked after `bounceTimeout` ms.
    property int pendingTargetId: -1
    // Routing state machine: a pick that must pass through an EasyEffects
    // on/off transition defers its move until the filter node settles.
    property string routeStage: ""          // "", "wait-off", "wait-on"
    property var routeTarget: null          // PwNode to move to once settled
    property bool routeFollowDefault: false // "Default" pick: move, never pin
    property bool routeWasActive: false     // filter node present when pick started
    property int routeTicks: 0

    // Devices of this direction. Keep the stream's live device in the list even
    // when it is not part of the regular device list (e.g. a filter node).
    readonly property list<var> deviceList: {
        const source = root.isSink ? Audio.outputDevices : Audio.inputDevices;
        const devices = [];
        for (let i = 0; i < source.length; i++) devices.push(source[i]);
        const current = root.currentDevice;
        if (current && devices.indexOf(current) === -1) devices.unshift(current);
        return devices;
    }

    // Menu: Default first, then hardware devices, then virtual filters
    // (EasyEffects) under their own header. Every row carries its height so
    // the popup can size itself without waiting for list layout (a
    // contentHeight-driven popup deadlocks at its padding size).
    readonly property var menuItems: {
        const items = [{
            kind: "header",
            h: 26,
            name: Translation.tr(root.isSink ? "Output device" : "Input device")
        }, {
            kind: "default",
            h: 42,
            name: Translation.tr("Default"),
            icon: Audio.deviceIcon(root.defaultDevice),
            subtitle: Audio.friendlyDeviceName(root.defaultDevice)
        }];
        const hardware = [];
        const virtuals = [];
        for (const device of root.deviceList) {
            const name = Audio.friendlyDeviceName(device);
            const desc = device.description ?? "";
            const subtitle = (desc && desc !== name) ? desc : "";
            const entry = {
                kind: "device",
                device: device,
                name: name,
                icon: Audio.deviceIcon(device),
                subtitle: subtitle,
                defaultBadge: root.defaultDevice !== null && device.id === root.defaultDevice.id,
                h: subtitle ? 44 : 34
            };
            (Audio.isHardwareDevice(device) ? hardware : virtuals).push(entry);
        }
        if (hardware.length > 0) {
            items.push({ kind: "sep", h: 9 });
            for (const entry of hardware) items.push(entry);
        }
        if (virtuals.length > 0) {
            items.push({ kind: "sep", h: 9 });
            items.push({ kind: "header", h: 24, name: Translation.tr("Effects") });
            for (const entry of virtuals) items.push(entry);
        }
        return items;
    }

    visible: Audio.routeAvailable && root.node?.isStream === true && Audio.streamSerial(root.node) !== null

    hoverEnabled: true
    implicitHeight: 24
    implicitWidth: Math.min(contentRow.implicitWidth + root.leftPadding + root.rightPadding, root.maximumWidth)
    leftPadding: 9
    rightPadding: 6
    topPadding: 0
    bottomPadding: 0

    buttonRadius: height / 2
    toggled: !root.followingDefault
    border: root.followingDefault
    borderWidth: 1
    colBorder: Appearance.colors.colOutlineVariant
    colBackgroundHover: Appearance.colors.colLayer2
    colRipple: Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    onClicked: {
        console.log("[SDS] chip clicked");
        // Defer past the release event: opening from inside the release handler
        // lets CloseOnPressOutside see the still-active press and close at once.
        Qt.callLater(() => popup.open());
    }

    // The EasyEffects filter node for this direction right now, if any.
    // Node presence is the ground truth: it is direction-correct (capture
    // filters may be off while playback filters run) and immune to a stale
    // `EasyEffects.active` flag.
    function easyEffectsNode() {
        const want = root.isSink ? "easyeffects_sink" : "easyeffects_source";
        for (const n of Pipewire.nodes.values) {
            if (n.name === want && !n.isStream) return n;
        }
        return null;
    }

    // PwNodes are recreated when their producer restarts (EasyEffects):
    // keep the pick while the id still exists, else re-resolve by name.
    function resolveTarget(target) {
        if (!target) return null;
        for (const n of Pipewire.nodes.values) {
            if (n.id === target.id && !n.isStream) return target;
        }
        for (const n of Pipewire.nodes.values) {
            if (n.name === target.name && !n.isStream) return n;
        }
        return null;
    }

    // Apply a pick (device = null resets to the system default: a plain move
    // with no pin, so the stream keeps following default-device changes).
    // A pick that already matches the chain-resolved device is a no-op --
    // e.g. choosing the device EasyEffects already outputs to must not bounce.
    //
    // EasyEffects re-pins every stream it claims back to itself within
    // ~400 ms, so a pick arbitrates it: routing into EasyEffects turns it on
    // first, routing anywhere else turns it off, and the actual move waits
    // for the filter node to settle (eeWait: 100 ms ticks, ~2 s cap).
    function chooseDevice(device) {
        const target = device ?? Audio.defaultDevice(root.isSink);
        if (!target) {
            popup.close();
            return;
        }
        const direct = Audio.directStreamDevice(root.node);
        const chain = Audio.streamDevice(root.node);
        const already = (direct && direct.id === target.id) || (chain && chain.id === target.id);
        if (already) {
            popup.close();
            return;
        }
        popup.close();
        root.routeTarget = target;
        root.routeFollowDefault = device === null;
        const eeNode = root.easyEffectsNode();
        root.routeWasActive = eeNode !== null;
        const targetIsEE = String(target.name ?? "").startsWith("easyeffects_");
        if (targetIsEE) {
            if (eeNode === null) EasyEffects.enable();
            root.routeStage = "wait-on";
            root.routeTicks = 0;
            eeWait.restart();
        } else if (eeNode !== null) {
            EasyEffects.disable();
            root.routeStage = "wait-off";
            root.routeTicks = 0;
            eeWait.restart();
        } else {
            root.applyRoute();
        }
    }

    // The filter node settled (or the wait timed out: still move, the
    // bounce check below reports a move that does not stick). Perform the
    // deferred move and pin.
    function applyRoute() {
        eeWait.stop();
        root.routeStage = "";
        const followDefault = root.routeFollowDefault;
        const label = root.routeTarget ? Audio.friendlyDeviceName(root.routeTarget) : "";
        const wanted = root.resolveTarget(root.routeTarget);
        root.routeTarget = null;
        if (!wanted) {
            root.pendingTargetId = -1;
            if (label) root.notify(`${Translation.tr("Device not available")}: ${label}`);
            return;
        }
        Audio.moveStreamToDevice(root.node, followDefault ? null : wanted);
        root.pendingTargetId = wanted.id;
        bounceCheck.restart();
    }

    function notify(message) {
        Quickshell.execDetached(["notify-send", "-a", "Shell",
            Translation.tr("Volume Mixer"), message]);
    }

    Timer {
        id: eeWait
        interval: 100
        repeat: true
        onTriggered: {
            const stage = root.routeStage;
            if (stage === "") {
                eeWait.stop();
                return;
            }
            const eeGone = root.easyEffectsNode() === null;
            const settled = stage === "wait-off" ? eeGone : !eeGone;
            if (settled || ++root.routeTicks >= 20) {
                const timedOut = !settled;
                const label = root.routeTarget ? Audio.friendlyDeviceName(root.routeTarget) : "";
                const wasActive = root.routeWasActive;
                root.applyRoute();
                if (timedOut) return;
                if (stage === "wait-off") {
                    root.notify(`${Translation.tr("EasyEffects turned off to route this stream to")} ${label}`);
                } else if (stage === "wait-on" && !wasActive) {
                    root.notify(Translation.tr("EasyEffects turned on — this stream now plays through it"));
                }
            }
        }
    }

    Timer {
        id: bounceCheck
        interval: 800
        onTriggered: {
            const wanted = root.pendingTargetId;
            root.pendingTargetId = -1;
            if (wanted < 0) return;
            const direct = Audio.directStreamDevice(root.node);
            const chain = Audio.streamDevice(root.node);
            const landed = (direct && direct.id === wanted) || (chain && chain.id === wanted);
            if (!landed) {
                root.notify(Translation.tr("EasyEffects holds this stream — turn it off for per-app device routing"));
            }
        }
    }

    contentItem: RowLayout {
        id: contentRow
        spacing: 5

        MaterialSymbol {
            text: Audio.deviceIcon(root.shownDevice)
            iconSize: 15
            color: root.followingDefault ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.followingDefault ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer
        }

        MaterialSymbol {
            text: "keyboard_arrow_down"
            iconSize: Appearance.font.pixelSize.smaller
            color: root.followingDefault ? Appearance.colors.colSubtext : Appearance.colors.colOnSecondaryContainer
            opacity: 0.8
            Layout.alignment: Qt.AlignVCenter
            rotation: popup.opened ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        text: root.followingDefault
            ? `${Translation.tr("System default")}: ${Audio.friendlyDeviceName(root.defaultDevice)}`
            : `${Translation.tr(root.isSink ? "Output device" : "Input device")}: ${Audio.friendlyDeviceName(root.shownDevice)}`
    }

    // Popup placement state, captured just before opening so the x/y/height
    // bindings can react to the final height while opening.
    property real placeChipX: 0
    property real placeChipY: 0
    property real placeBoundsX: 0
    property real placeBoundsY: 0
    property real placeBoundsW: 0
    property real placeBoundsH: 0
    property real placeWidth: 300
    property real placeSpaceBelow: 400
    property real placeSpaceAbove: 400
    property bool placeBelow: true
    readonly property real placeMargin: 8
    readonly property real placeGap: 6
    readonly property real estimatedPopupHeight: {
        let height = popup.padding * 2;
        for (const item of root.menuItems) {
            height += (item.h ?? 36) + 1;
        }
        return height;
    }

    function popupBounds() {
        const target = root.clampItem;
        if (target) {
            const p = target.mapToItem(null, 0, 0);
            return { x: p.x, y: p.y, w: target.width, h: target.height };
        }
        const win = root.QsWindow?.window;
        return { x: 8, y: 8, w: (win?.width ?? 1920) - 16, h: (win?.height ?? 1080) - 16 };
    }

    function capturePlacement() {
        const bounds = root.popupBounds();
        const chip = root.mapToItem(null, 0, 0);
        root.placeChipX = chip.x;
        root.placeChipY = chip.y;
        root.placeBoundsX = bounds.x;
        root.placeBoundsY = bounds.y;
        root.placeBoundsW = bounds.w;
        root.placeBoundsH = bounds.h;
        root.placeWidth = Math.max(200, Math.min(300, bounds.w - root.placeMargin * 2));

        const spaceBelow = (bounds.y + bounds.h) - (chip.y + root.height) - root.placeGap - root.placeMargin;
        const spaceAbove = chip.y - bounds.y - root.placeGap - root.placeMargin;
        root.placeSpaceBelow = spaceBelow;
        root.placeSpaceAbove = spaceAbove;
        // Prefer below; flip above when there is not enough room underneath.
        const estimate = root.estimatedPopupHeight;
        root.placeBelow = spaceBelow >= Math.min(estimate, 160) || spaceBelow >= spaceAbove;
    }

    Popup {
        id: popup
        // Render in-tree: the Qt default (a separate popup window) cannot be
        // positioned over a layer-shell surface, so the list opens but never
        // paints. As an item it draws inside the overlay window like any widget.
        popupType: Popup.Item
        property real popupAvailableHeight: 400

        width: root.placeWidth
        // Sized from the known item heights, not from listView.contentHeight:
        // a contentHeight-driven popup deadlocks at its padding size when the
        // list has not laid out yet (contentItem height 0 -> no delegates).
        height: Math.min(root.estimatedPopupHeight, popup.popupAvailableHeight)
        x: Math.max(root.placeBoundsX + root.placeMargin,
            Math.min(root.placeChipX, root.placeBoundsX + root.placeBoundsW - width - root.placeMargin))
        y: root.placeBelow
            ? root.placeChipY + root.height + root.placeGap
            : root.placeChipY - root.placeGap - height

        padding: 6
        focus: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        onAboutToShow: {
            root.capturePlacement();
            popup.popupAvailableHeight = Math.max(root.placeBelow ? root.placeSpaceBelow : root.placeSpaceAbove, 160);
        }
        onOpened: console.log("[SDS] popup opened at", popup.x, popup.y, popup.width + "x" + popup.height, "opacity=" + popup.opacity, "scale=" + popup.scale, "below=" + root.placeBelow)
        onClosed: console.log("[SDS] popup closed")

        // Pop out from the edge the chip sits on; a scale + fade entrance
        // without touching the popup's bound x/y.
        transformOrigin: root.placeBelow ? Item.Top : Item.Bottom

        enter: Transition {
            ParallelAnimation {
                PropertyAnimation {
                    properties: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                PropertyAnimation {
                    properties: "scale"
                    from: 0.96
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        exit: Transition {
            ParallelAnimation {
                PropertyAnimation {
                    properties: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                PropertyAnimation {
                    properties: "scale"
                    to: 0.96
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: StyledListView {
            id: listView
            clip: true
            spacing: 1
            implicitHeight: contentHeight
            animateAppearance: false
            model: root.menuItems

            delegate: Item {
                id: row
                required property var modelData
                required property int index

                readonly property string kind: modelData.kind
                readonly property bool isHeader: kind === "header"
                readonly property bool isSep: kind === "sep"
                readonly property bool selectable: kind === "default" || kind === "device"
                readonly property bool selected: kind === "default"
                    ? root.followingDefault
                    : (kind === "device" && root.currentDevice !== null
                        && root.currentDevice.id === modelData.device.id)

                width: ListView.view ? ListView.view.width : popup.width - popup.padding * 2
                height: row.modelData.h ?? 36

                Rectangle {
                    visible: row.selectable
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: {
                        if (row.selected) {
                            if (rowMouse.pressed) return Appearance.colors.colSecondaryContainerActive;
                            if (rowMouse.containsMouse) return Appearance.colors.colSecondaryContainerHover;
                            return Appearance.colors.colSecondaryContainer;
                        } else {
                            if (rowMouse.pressed) return Appearance.colors.colLayer3Active;
                            if (rowMouse.containsMouse) return Appearance.colors.colLayer3Hover;
                            return ColorUtils.transparentize(Appearance.colors.colLayer3);
                        }
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    visible: row.selectable
                    enabled: row.selectable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chooseDevice(row.kind === "default" ? null : row.modelData.device)
                }

                StyledText {
                    visible: row.isHeader
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 10
                    }
                    text: row.modelData.name ?? ""
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: row.isSep
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 6
                        rightMargin: 6
                    }
                    height: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.6
                }

                RowLayout {
                    visible: row.selectable
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 10
                    spacing: 8

                    Item {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: row.selected
                            text: "check"
                            fill: 1
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                    }

                    MaterialSymbol {
                        text: row.modelData.icon ?? ""
                        iconSize: 17
                        color: row.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.name ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: row.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: (row.modelData.subtitle ?? "") !== ""
                            text: row.modelData.subtitle ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        visible: row.modelData.defaultBadge === true
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Default")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
