pragma ComponentBehavior: Bound

import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A regular top-level window (managed by the compositor, so dragging is
 * handled natively and stays smooth). All logic lives in the AdvancedPaste
 * singleton; this is just the view.
 */
Window {
    id: root

    title: "Advanced Paste"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    readonly property int cardWidth: 380
    width: cardWidth
    height: 560

    property int selectedIndex: 0
    readonly property bool showAi: Config.options?.advancedPaste?.showAi ?? true
    readonly property bool isColor: AdvancedPaste.detection?.primary === "color"
    property bool colorSelectionDone: false
    readonly property string currentTransform: transformsModel.get(Math.min(root.selectedIndex, transformsModel.count - 1)).transformId

    readonly property int visibleCount: {
        let count = 0;
        for (let i = 0; i < transformsModel.count; i++) {
            const entry = transformsModel.get(i);
            if (entry.colorOnly === root.isColor && (entry.transformId !== "ai" || root.showAi)) count++;
        }
        return count;
    }

    onClosing: event => {
        AdvancedPaste.close();
    }

    Connections {
        target: AdvancedPaste
        function onClosed() { root.hide(); }
    }

    Component.onCompleted: {
        root.show();
        selectedIndex = Math.max(0, findTransform(AdvancedPaste.transform));
        Qt.callLater(() => {
            root.resizeToContent();
            root.placeNearCursor();
        });
        root.requestActivate();
        keyHandler.forceActiveFocus();
    }

    function resizeToContent(): void {
        root.height = mainColumn.implicitHeight + 24;
    }

    // Only the initial spawn is anchored to the cursor. After that the
    // compositor owns the window position and the user moves it normally.
    function placeNearCursor(): void {
        const geometry = root.screen?.geometry;
        if (!geometry) return;
        const gx = AdvancedPaste.anchorX >= 0 ? AdvancedPaste.anchorX : geometry.x + geometry.width / 2;
        const gy = AdvancedPaste.anchorY >= 0 ? AdvancedPaste.anchorY : geometry.y + geometry.height / 2;
        root.x = Math.min(Math.max(gx - width / 2, geometry.x + 8), geometry.x + geometry.width - width - 8);
        root.y = Math.min(Math.max(gy + 18, geometry.y + 8), geometry.y + geometry.height - height - 8);
    }

    Connections {
        target: AdvancedPaste
        function onDetectionChanged() {
            if (root.isColor && !root.colorSelectionDone) {
                root.colorSelectionDone = true;
                root.selectedIndex = root.findTransform("color_hex");
                Qt.callLater(root.resizeToContent);
            }
        }
    }

    Item {
        id: keyHandler
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                AdvancedPaste.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier)) {
                root.moveSelection(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier)) {
                root.moveSelection(-1);
                event.accepted = true;
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const index = root.visibleIndexAt(event.key - Qt.Key_1);
                if (index >= 0) root.activate(index);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.confirm();
                event.accepted = true;
            }
        }
    }

    ListModel {
        id: transformsModel
        ListElement { transformId: "plain";        label: "Plain text";    icon: "text_fields";    hint: "Strip all formatting"; colorOnly: false }
        ListElement { transformId: "markdown";     label: "Markdown";      icon: "markdown";       hint: "HTML or tidy Markdown"; colorOnly: false }
        ListElement { transformId: "json_pretty";  label: "JSON (pretty)"; icon: "data_object";    hint: "Format valid JSON"; colorOnly: false }
        ListElement { transformId: "json_escape";  label: "JSON string";   icon: "code";           hint: "Escape into a JSON string"; colorOnly: false }
        ListElement { transformId: "codeblock";    label: "Code block";    icon: "terminal";       hint: "Wrap with language tag"; colorOnly: false }
        ListElement { transformId: "shell_escape"; label: "Shell quote";   icon: "terminal";       hint: "Escape for the shell"; colorOnly: false }
        ListElement { transformId: "upper";        label: "UPPERCASE";     icon: "arrow_upward";   hint: ""; colorOnly: false }
        ListElement { transformId: "lower";        label: "lowercase";     icon: "arrow_downward"; hint: ""; colorOnly: false }
        ListElement { transformId: "title";        label: "Title Case";    icon: "text_format";    hint: ""; colorOnly: false }
        ListElement { transformId: "ai";           label: "AI transform";  icon: "wand_stars";   hint: "Optional, needs a local or online model"; colorOnly: false }
        ListElement { transformId: "color_hex";     label: "HEX";           icon: "palette";        hint: "#RRGGBB"; colorOnly: true }
        ListElement { transformId: "color_rgb";     label: "RGB";           icon: "palette";        hint: "rgb(r, g, b)"; colorOnly: true }
        ListElement { transformId: "color_css";     label: "CSS rgba()";    icon: "code";           hint: "rgba(r, g, b, a)"; colorOnly: true }
        ListElement { transformId: "color_hsl";     label: "HSL";           icon: "palette";        hint: "hsl(h, s%, l%)"; colorOnly: true }
        ListElement { transformId: "color_flutter"; label: "Flutter";      icon: "flutter_dash";   hint: "Color(0xAARRGGBB)"; colorOnly: true }
    }

    function findTransform(id): int {
        for (let i = 0; i < transformsModel.count; i++) {
            if (transformsModel.get(i).transformId === id) return i;
        }
        return 0;
    }

    function visibleIndexAt(position): int {
        let seen = 0;
        for (let i = 0; i < transformsModel.count; i++) {
            const entry = transformsModel.get(i);
            if (entry.colorOnly !== root.isColor || (entry.transformId === "ai" && !root.showAi)) continue;
            if (seen === position) return i;
            seen++;
        }
        return -1;
    }

    function moveSelection(delta): void {
        let next = root.selectedIndex;
        const count = root.visibleCount;
        for (let step = 0; step < count; step++) {
            next = (next + delta + count) % count;
        }
        root.selectedIndex = next;
    }

    function activate(index): void {
        root.selectedIndex = index;
        if (root.currentTransform === "ai") {
            aiField.forceActiveFocus();
        } else {
            AdvancedPaste.applyTransform(root.currentTransform);
        }
    }

    function confirm(): void {
        if (AdvancedPaste.aiBusy) return;
        if (root.currentTransform === "ai") {
            if (AdvancedPaste.aiResult.length === 0) {
                if (aiField.text.trim().length > 0) AdvancedPaste.runAiTransform(aiField.text);
                return;
            }
            AdvancedPaste.commitAiResult();
            return;
        }
        AdvancedPaste.applyTransform(root.currentTransform);
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colUiPopupBackground
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        StyledRectangularShadow { target: card }

        ColumnLayout {
            id: mainColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
            }
            spacing: 6

            // Header — drag here to move the window like any normal window.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                spacing: 8
                MaterialSymbol {
                    text: "content_paste_go"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Advanced Paste")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colOnLayer1
                }
                MouseArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cursorShape: Qt.SizeAllCursor
                    onPressed: root.startSystemMove()
                }
                MaterialSymbol {
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AdvancedPaste.close()
                    }
                }
            }

            // Detected format chip + preview
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: previewColumn.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: previewColumn
                    anchors { fill: parent; margins: 8 }
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            implicitWidth: chipText.implicitWidth + 14
                            implicitHeight: chipText.implicitHeight + 6
                            radius: implicitHeight / 2
                            color: Appearance.colors.colPrimaryContainer
                            StyledText {
                                id: chipText
                                anchors.centerIn: parent
                                text: AdvancedPaste.detection?.primary ?? "text"
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: AdvancedPaste.detection?.language
                                ? `Language: ${AdvancedPaste.detection.language}`
                                : `${Math.min(AdvancedPaste.sourceText.length, 400)} chars`
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: AdvancedPaste.aiResult.length > 0 ? AdvancedPaste.aiResult : AdvancedPaste.sourceText
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            // Transform list
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: transformsModel
                    delegate: Rectangle {
                        required property int index
                        required property string transformId
                        required property string label
                        required property string icon
                        required property string hint
                        required property bool colorOnly
                        property int visiblePosition: {
                            let count = 0;
                            for (let i = 0; i < index; i++) {
                                const entry = transformsModel.get(i);
                                if (entry.colorOnly === root.isColor && (entry.transformId !== "ai" || root.showAi)) count++;
                            }
                            return count + 1;
                        }
                        Layout.fillWidth: true
                        implicitHeight: 34
                        visible: colorOnly === root.isColor && (transformId !== "ai" || root.showAi)
                        radius: Appearance.rounding.small
                        color: root.selectedIndex === index ? Appearance.colors.colSecondaryContainer : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 10
                            MaterialSymbol {
                                text: icon
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.selectedIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: label
                                color: root.selectedIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            StyledText {
                                text: visiblePosition <= 9 ? `${visiblePosition}` : ""
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = index
                            onClicked: root.activate(index)
                        }
                    }
                }
            }

            // AI prompt field
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.currentTransform === "ai" ? 38 : 0
                visible: root.currentTransform === "ai"
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                TextField {
                    id: aiField
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    placeholderText: Translation.tr("e.g. translate to English, format as a table…")
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                    background: Rectangle { color: "transparent" }
                    font.pixelSize: Appearance.font.pixelSize.small
                    onAccepted: AdvancedPaste.runAiTransform(aiField.text)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: AdvancedPaste.aiBusy
                    ? Translation.tr("AI is transforming…")
                    : Translation.tr("↑↓ select · Enter paste · Esc close")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
