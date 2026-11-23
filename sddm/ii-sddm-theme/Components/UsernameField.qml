// Typed-username replacement for the collapsed user dropdown.
// Keeps the `selectUser` API used by InputLogin.qml (currentText/currentIndex/
// selectionChanged) while remaining usable when userModel is empty.
import "Commons"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: usernameIsland

    property alias currentText: usernameField.text
    property int currentIndex: -1
    signal selectionChanged()

    readonly property int baseHeight: 42

    implicitWidth: 220
    implicitHeight: baseHeight
    focusPolicy: Qt.ClickFocus

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container
        radius: Appearance.rounding.full
    }

    TextField {
        id: usernameField
        anchors.fill: parent
        leftPadding: 14
        rightPadding: 14
        verticalAlignment: TextInput.AlignVCenter
        font.family: Appearance.font_family_main
        font.pixelSize: Appearance.font.pixelSize.normal
        color: Colors.on_surface_variant
        placeholderText: qsTr("Username")
        placeholderTextColor: Colors.on_surface_variant
        background: Item {}
        selectByMouse: true

        onTextEdited: {
            usernameIsland.currentIndex = -1;
            usernameIsland.selectionChanged();
            suggestions.open();
        }

        Keys.onDownPressed: function(event) {
            suggestions.open();
            event.accepted = true;
        }

        Keys.onEscapePressed: function(event) {
            suggestions.close();
            event.accepted = true;
        }

        // Enter is deliberately not accepted: the greeter's password field
        // keeps its normal onAccepted -> sddm.login path.
        Keys.onReturnPressed: function(event) {
            suggestions.close();
        }
    }

    Popup {
        id: suggestions
        parent: usernameIsland
        x: 0
        y: usernameIsland.height + 4
        width: usernameIsland.width
        implicitHeight: Math.min(280, suggestionList.contentHeight + 12)
        padding: 6
        modal: false
        focus: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            color: Colors.primary_container
            radius: 12
        }

        contentItem: ListView {
            id: suggestionList
            model: userModel
            clip: true
            spacing: 4

            delegate: Item {
                id: suggestionRow
                width: suggestionList.width
                height: 40

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: rowMouse.containsMouse
                           ? Colors.colPrimaryContainerHover
                           : Colors.primary_container
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Avatar {
                        size: 24
                        userName: userModel.data(userModel.index(index, 0), 257) || ""
                        source: userName === "dmitriy"
                                ? "file:///home/dmitriy/Pictures/ava/ava-violet-2x.png"
                                : (userModel.data(userModel.index(index, 0), 260) || "")
                        iconColor: Colors.on_primary_container
                    }

                    Text {
                        Layout.fillWidth: true
                        text: userModel.data(userModel.index(index, 0), 257) || ""
                        font.family: Appearance.font_family_main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        elide: Text.ElideRight
                        color: Colors.on_primary_container
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        usernameIsland.currentIndex = index;
                        usernameField.text = userModel.data(userModel.index(index, 0), 257) || "";
                        usernameIsland.selectionChanged();
                        suggestions.close();
                        usernameField.forceActiveFocus();
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        const lastName = userModel.data(userModel.index(userModel.lastIndex, 0), 257) || "";
        if (lastName !== "")
            usernameField.text = lastName;
    }
}
