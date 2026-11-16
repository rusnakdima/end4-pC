import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The search row of a dialog: a leading search glyph, the text field and
 * a clear button that only exists while there is something to clear.
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
RowLayout {
    id: root

    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property bool autoFocus: true

    signal accepted()

    spacing: 8
    Layout.fillWidth: true

    MaterialSymbol {
        text: "search"
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colOnSurfaceVariant
    }

    ToolbarTextField {
        id: field
        Layout.fillWidth: true

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

    Component.onCompleted: {
        // Qt.callLater, not a direct call: the dialog's host focuses the
        // dialog itself after it has been created (SidebarRightContent
        // ToggleDialog), and a call made here would lose that race.
        if (root.autoFocus)
            Qt.callLater(() => field.forceActiveFocus());
    }
}
