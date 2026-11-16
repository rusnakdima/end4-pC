import QtQuick
import QtQuick.Layouts
import qs.modules.waffle.looks

/**
 * The search row of a waffle page: a rounded outline, the search glyph,
 * the text field with its placeholder, and a dismiss button that only
 * exists while there is something to clear.
 *
 * It keeps the contract of the ii family's DialogSearchField - text,
 * placeholderText, autoFocus, accepted - so both families behave the
 * same way while each keeps its own look. The Escape handling is part of
 * the contract: with text it clears and swallows the key, with an empty
 * field it lets the key through to whatever handles it next.
 */
Item {
    id: root

    property alias text: field.text
    property alias placeholderText: placeholder.text
    property bool autoFocus: true

    signal accepted()

    implicitHeight: 44
    Layout.fillWidth: true

    Rectangle {
        id: outline
        anchors.fill: parent
        color: "transparent"
        radius: height / 2
        border.width: 1
        border.color: Looks.colors.bg2Border
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: Looks.colors.inputBg

        RowLayout {
            anchors.fill: parent
            spacing: 8

            WAppIcon {
                Layout.leftMargin: 16
                iconName: "system-search"
                separateLightDark: true
                implicitSize: 20
            }

            Item {
                id: fieldBox
                Layout.fillWidth: true
                implicitHeight: 30

                WTextInput {
                    id: field
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    clip: true

                    onAccepted: root.accepted()

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape && field.text !== "") {
                            field.text = "";
                            event.accepted = true;
                        }
                    }
                }

                WText {
                    id: placeholder
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    elide: Text.ElideRight
                    font.pixelSize: Looks.font.pixelSize.large
                    color: Looks.colors.accentUnfocused
                    visible: field.text.length === 0
                }
            }

            WBorderlessButton {
                objectName: "clearButton"
                implicitHeight: 28
                implicitWidth: 28
                visible: field.text.length > 0
                onClicked: field.text = ""

                contentItem: FluentIcon {
                    icon: "dismiss"
                    implicitSize: 16
                }
            }

            // Keeps the right edge where it is when the clear button comes
            // and goes, so the field does not jump.
            Item {
                width: 16
            }
        }
    }

    Component.onCompleted: {
        // Qt.callLater, not a direct call: the host focuses its own item
        // after the page has been created, and a call made here would lose
        // that race.
        if (root.autoFocus)
            Qt.callLater(() => field.forceActiveFocus());
    }
}
