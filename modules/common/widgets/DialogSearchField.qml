import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The search row of a dialog: one bar that spans the whole panel, with the
 * search glyph inside it, the text field, and a clear button that only
 * exists while there is something to clear.
 *
 * The row bleeds past the dialog's content inset (Appearance.rounding.large
 * on each side) exactly like the separators and the list below it, and pads
 * its own contents by the same amount, so the glyph lands on the same x as
 * the icons of the rows it filters.
 *
 * The contract is deliberately tiny - text, placeholderText, autoFocus,
 * accepted - so every dialog that embeds it behaves the same way. The
 * Escape handling is part of that contract: with text in the field it
 * clears and swallows the key, with an empty field it lets the key through
 * so the dialog's own Escape handler still closes the window.
 *
 * This file declares no top-level function: tests/functional-coverage.sh
 * scans modules/common/widgets and would demand a tst_ file for it.
 */
Item {
    id: root

    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property bool autoFocus: true

    signal accepted()

    implicitHeight: 48
    Layout.fillWidth: true
    Layout.leftMargin: -Appearance.rounding.large
    Layout.rightMargin: -Appearance.rounding.large

    Rectangle {
        // The bar itself: full panel width, pill shaped, one step above
        // the panel background like every other field in the shell.
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        spacing: 12

        MaterialSymbol {
            text: "search"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurfaceVariant
        }

        ToolbarTextField {
            id: field
            colBackground: "transparent"
            padding: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            font.pixelSize: Appearance.font.pixelSize.large

            onAccepted: root.accepted()

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape && field.text !== "") {
                    field.text = "";
                    event.accepted = true;
                }
            }
        }

        IconToolbarButton {
            objectName: "clearButton"
            text: "close"
            visible: field.text.length > 0
            onClicked: field.text = ""

            StyledToolTip {
                text: Translation.tr("Clear")
            }
        }
    }

    Component.onCompleted: {
        // Qt.callLater, not a direct call: the dialog's host focuses the
        // dialog itself after it has been created (SidebarRightContent
        // ToggleDialog), and a call made here would lose that race.
        if (root.autoFocus)
            Qt.callLater(() => field.forceActiveFocus());
    }
}
