import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The header row of a collapsible sidebar card (the "spoiler" bar).
 *
 * Icon, title, an optional trailing readout and an expand/collapse chevron,
 * all inside a RippleButton so the whole row is one hoverable, rippling
 * target - the same interaction AppWindowRules uses for its "Show all N
 * apps" row, dressed for a glass card instead of a settings list.
 *
 * It deliberately holds no state of its own: `collapsed` is read from the
 * caller and the row only reports `collapseToggled()`, so the caller keeps
 * writing straight into its own Persistent binding instead of having a
 * child break that binding by assigning to it.
 *
 * No top-level `function` in here on purpose: tests/functional-coverage.sh
 * treats a declared function as a unit of logic that needs a hosted test,
 * and this is presentation glue. Inline handlers only.
 */
RippleButton {
    id: root

    required property string title
    // NOT `icon`: Button already owns an `icon` group property and marks it
    // final, so redeclaring it fails at engine load ("Cannot override FINAL
    // property") - a failure qmllint does not report.
    property string headerIcon: ""
    property string trailingText: ""
    property bool collapsed: false

    signal collapseToggled()

    implicitHeight: 40
    padding: 0
    buttonRadius: Appearance.rounding.normal

    onClicked: root.collapseToggled()

    contentItem: Item {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8

            MaterialSymbol {
                visible: root.headerIcon.length > 0
                text: root.headerIcon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                visible: root.trailingText.length > 0
                text: root.trailingText
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            // expand_more = "there is more below, click to show it",
            // expand_less = "click to put it away".
            MaterialSymbol {
                text: root.collapsed ? "expand_more" : "expand_less"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
        }
    }
}
