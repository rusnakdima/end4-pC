import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

/**
 * Lets the user rebind the shell shortcuts.
 *
 * The binds come from the same parser the cheatsheet uses, so the list always
 * matches the config that Hyprland actually loaded. A rebind is written to
 * ~/.config/hypr/custom/keybind_overrides.conf and Hyprland is reloaded.
 */
ContentPage {
    id: page
    forceWidth: true
    baseWidth: 600
    focus: true

    // The action whose key combination is being captured right now.
    property string capturing: ""

    function startCapture(action) {
        page.capturing = action;
        captureTimeout.restart();
        Qt.callLater(() => page.forceActiveFocus());
    }

    // Releasing the capture is always done here, never only by pressing a
    // key: a capture that stays alive keeps every key press inside the
    // settings panel, so Escape and plain letters never reach the app.
    function stopCapture() {
        if (page.capturing === "") return;
        page.capturing = "";
        captureTimeout.stop();
    }

    onEnabledChanged: {
        if (enabled) {
            Qt.callLater(() => page.forceActiveFocus());
        } else {
            // The page was left, the capture goes with it.
            page.stopCapture();
        }
    }

    // The panel was closed, the capture goes with it.
    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            if (!GlobalStates.settingsOpen) page.stopCapture();
        }
    }

    // A capture that is never finished must not hold the keyboard forever.
    Timer {
        id: captureTimeout
        interval: 10000
        onTriggered: page.stopCapture()
    }

    Keys.onPressed: (event) => {
        if (page.capturing === "") return;

        if (event.key === Qt.Key_Escape) {
            // Cancel the capture, but let the press travel on: the panel
            // closes on Escape as well.
            page.stopCapture();
            return;
        }

        const combo = CF.StringUtils.keyEventToCombo(event);
        if (combo === "") {
            // A modifier on its own, or a key Hyprland would not know.
            // It is deliberately not accepted: swallowing it would eat the
            // modifier of the combination that follows.
            return;
        }

        HyprlandBindOverrides.setOverride(page.capturing, combo);
        page.stopCapture();
        event.accepted = true;
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20

        ContentSection {
            icon: "keyboard"
            title: Translation.tr("Shell shortcuts")
            hint: Translation.tr("Click a shortcut and press the key combination you want to use.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    visible: HyprlandKeybinds.shellActions.length === 0
                    text: Translation.tr("No keybinds found.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                Repeater {
                    model: HyprlandKeybinds.shellActions

                    delegate: ShortcutRow {
                        required property var modelData
                        actionData: modelData
                        capturing: page.capturing === modelData.action
                    }
                }
            }
        }

        ContentSection {
            icon: "keyboard"
            title: Translation.tr("Other keybinds")
            collapsible: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 20

                Repeater {
                    model: HyprlandKeybinds.otherSections

                    delegate: ColumnLayout {
                        id: sectionColumn
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: sectionColumn.modelData.name === "" ? Translation.tr("Uncategorized") : sectionColumn.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer1
                        }

                        Repeater {
                            model: sectionColumn.modelData.binds

                            delegate: OtherBindRow {
                                required property var modelData
                                bindData: modelData
                            }
                        }
                    }
                }
            }
        }
    }

    // An editable shell shortcut.
    component ShortcutRow: Rectangle {
        id: shortcutRow
        required property var actionData
        property bool capturing: false

        readonly property string defaultCombo: actionData?.combos?.[0] ?? ""
        readonly property string combo: HyprlandBindOverrides.comboFor(actionData?.action ?? "", shortcutRow.defaultCombo)
        readonly property var aliases: (actionData?.combos ?? []).slice(1)

        Layout.fillWidth: true
        implicitHeight: shortcutRowLayout.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal
        border.width: shortcutRow.capturing ? 1 : 0
        border.color: Appearance.colors.colPrimary

        RowLayout {
            id: shortcutRowLayout
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: (shortcutRow.actionData?.description ?? "") !== ""
                        ? shortcutRow.actionData.description
                        : (shortcutRow.actionData?.action ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: shortcutRow.aliases.length > 0
                    text: Translation.tr("Also bound to %1").arg(shortcutRow.aliases.join(", "))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            StyledText {
                visible: shortcutRow.capturing
                text: Translation.tr("Press a key combination...")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            Item {
                id: shortcutRowCaps
                visible: !shortcutRow.capturing
                implicitWidth: shortcutRowCapsRow.implicitWidth
                implicitHeight: shortcutRowCapsRow.implicitHeight

                Row {
                    id: shortcutRowCapsRow
                    spacing: 4

                    Repeater {
                        model: shortcutRow.combo.split(" + ")
                        delegate: KeyboardKey {
                            required property var modelData
                            key: modelData
                            pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.startCapture(shortcutRow.actionData.action)
                }
            }

            // A visible edit affordance. Without it the row only reacts to
            // the key caps, which does not look editable at all.
            Item {
                id: editButton
                visible: !shortcutRow.capturing
                implicitWidth: 20
                implicitHeight: 20

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.startCapture(shortcutRow.actionData.action)
                }
            }

            MaterialSymbol {
                visible: HyprlandBindOverrides.isOverridden(shortcutRow.actionData?.action ?? "")
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                text: "restart_alt"

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        HyprlandBindOverrides.clearOverride(shortcutRow.actionData.action);
                        page.stopCapture();
                    }
                }
            }
        }
    }

    // A keybind that is not a shell action. Read only.
    component OtherBindRow: Rectangle {
        id: otherBindRow
        required property var bindData

        Layout.fillWidth: true
        implicitHeight: otherBindRowLayout.implicitHeight + 16
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        RowLayout {
            id: otherBindRowLayout
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12

            Row {
                spacing: 4

                Repeater {
                    model: HyprlandKeybinds.comboOf(otherBindRow.bindData).split(" + ")
                    delegate: KeyboardKey {
                        required property var modelData
                        key: modelData
                        pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: otherBindRow.bindData.comment ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }
    }
}
