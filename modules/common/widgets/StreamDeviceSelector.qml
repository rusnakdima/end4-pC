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
    readonly property PwNode currentDevice: Audio.streamDevice(root.node)
    readonly property bool followingDefault: root.currentDevice === null || root.currentDevice === root.defaultDevice
    readonly property PwNode shownDevice: root.currentDevice ?? root.defaultDevice
    readonly property string label: root.followingDefault ? Translation.tr("Default") : Audio.friendlyDeviceName(root.shownDevice)

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

    readonly property var menuItems: {
        const items = [{
            kind: "header",
            name: Translation.tr(root.isSink ? "Output device" : "Input device")
        }, {
            kind: "default",
            name: Translation.tr("Default"),
            icon: Audio.deviceIcon(root.defaultDevice),
            subtitle: Audio.friendlyDeviceName(root.defaultDevice)
        }, {
            kind: "sep"
        }];
        for (const device of root.deviceList) {
            items.push({
                kind: "device",
                device: device,
                name: Audio.friendlyDeviceName(device),
                icon: Audio.deviceIcon(device)
            });
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
        console.log("[SDS] chip clicked; opening device popup");
        // Defer past the release event: opening from inside the release handler
        // lets CloseOnPressOutside see the still-active press and close at once.
        Qt.callLater(() => popup.open());
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
    property real placeWidth: 260
    property real placeSpaceBelow: 400
    property real placeSpaceAbove: 400
    property bool placeBelow: true
    readonly property real placeMargin: 8
    readonly property real placeGap: 6
    readonly property real estimatedPopupHeight: {
        let height = popup.padding * 2;
        for (const item of root.menuItems) {
            height += (item.kind === "header" ? 24 : item.kind === "sep" ? 9 : 36) + 1;
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
        root.placeWidth = Math.max(200, Math.min(260, bounds.w - root.placeMargin * 2));

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
            console.log("[SDS] aboutToShow; placeBelow=", root.placeBelow, "spaceBelow=", root.placeSpaceBelow, "spaceAbove=", root.placeSpaceAbove);
            root.capturePlacement();
            popup.popupAvailableHeight = Math.max(root.placeBelow ? root.placeSpaceBelow : root.placeSpaceAbove, 160);
        }
        onOpened: console.log("[SDS] popup OPENED at", popup.x, popup.y, popup.width + "x" + popup.height)
        onClosed: console.log("[SDS] popup closed")

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        exit: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
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
                    : (kind === "device" && root.currentDevice === modelData.device)

                width: ListView.view ? ListView.view.width : popup.width - popup.padding * 2
                height: isHeader ? 24 : isSep ? 9 : 36

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
                    onClicked: {
                        if (row.kind === "default") {
                            Audio.moveStreamToDevice(root.node, null); // Reset to the system default
                        } else {
                            Audio.moveStreamToDevice(root.node, row.modelData.device);
                        }
                        popup.close();
                    }
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

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: row.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                    }

                    StyledText {
                        visible: row.kind === "default" && (row.modelData.subtitle ?? "") !== ""
                        Layout.maximumWidth: 96
                        Layout.alignment: Qt.AlignVCenter
                        text: row.modelData.subtitle ?? ""
                        elide: Text.ElideLeft
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
