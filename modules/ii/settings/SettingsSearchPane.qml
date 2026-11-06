import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The list of settings matches for the search field in SettingsContent.
 *
 * Rows come from SettingsSearchIndex, the same index the shell-wide search
 * queries, so both searches agree on what matches. Activating a row goes
 * through GlobalStates.openSettingsAt, the deep link the settings window
 * already implements: open the page, scroll to the section, flash the row.
 */
Rectangle {
    id: pane

    property string query: ""
    property var results: []
    property string appliedQuery: ""

    readonly property bool hasQuery: query.trim().length > 0
    readonly property real targetHeight: results.length > 0
        ? Math.min(listView.contentHeight + 12, 320)
        : 170

    signal dismissed()

    visible: pane.hasQuery
    implicitHeight: pane.visible ? pane.targetHeight : 0
    // Opaque on purpose. colLayer* colours carry alpha = 1 - contentTransparency,
    // which is 0.9 here, so a colLayer2 card sits at 10% and the rows behind it
    // are unreadable over the page content. This is the shell's own popup
    // surface and it has no alpha.
    color: Appearance.colors.colUiPopupBackground
    radius: Appearance.rounding.normal

    onQueryChanged: searchDebounce.restart()

    Timer {
        id: searchDebounce
        interval: 150
        onTriggered: pane.runSearch()
    }

    function runSearch() {
        const term = pane.query.trim();
        pane.appliedQuery = term;
        pane.results = term === "" ? [] : SettingsSearchIndex.search(term, 15);
        if (listView.count > 0)
            listView.currentIndex = 0;
    }

    function moveSelection(delta) {
        if (listView.count === 0)
            return;
        const next = Math.max(0, Math.min(listView.count - 1, listView.currentIndex + delta));
        listView.currentIndex = next;
        listView.positionViewAtIndex(next, ListView.Contain);
    }

    function accept(result) {
        if (!result)
            return false;
        GlobalStates.openSettingsAt(result.pageId, result.kind === "page" ? "" : result.label, result.section, result.subsection);
        pane.dismissed();
        return true;
    }

    function acceptCurrent() {
        return pane.accept(pane.results[listView.currentIndex]);
    }

    function breadcrumbOf(result) {
        if (!result)
            return "";
        if (result.kind === "page")
            return Translation.tr("Settings");
        return [result.pageName, result.kind === "option" ? result.section : "", result.kind === "option" ? result.subsection : ""]
            .filter(part => part).join(" › ");
    }

    component ResultRow: RippleButton {
        id: row

        property var result
        property bool keyboardSelected: false
        readonly property color colForeground: keyboardSelected
            ? Appearance.colors.colOnPrimaryContainer
            : Appearance.colors.colOnLayer1

        implicitHeight: rowContent.implicitHeight + 16
        buttonRadius: Appearance.rounding.normal
        // Both states opaque: "transparent" left the resting rows at alpha 0,
        // so a result had no block of its own. m3surfaceContainerHigh is the
        // raw M3 surface colour, i.e. colLayer3Base without the alpha that the
        // layer colours multiply in.
        colBackground: keyboardSelected
            ? Appearance.colors.colPrimaryContainer
            : Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: Appearance.colors.colPrimaryContainer
        colRipple: Appearance.colors.colPrimaryContainerActive

        // The overview's SearchItem builds its row the same way: children of
        // the button itself, anchored to fill it.
        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            MaterialSymbol {
                text: row.result?.icon ?? "settings"
                iconSize: Appearance.font.pixelSize.large
                color: row.colForeground
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: row.result?.label ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: row.colForeground
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: text !== ""
                    text: pane.breadcrumbOf(row.result)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: row.keyboardSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
            }
        }
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        anchors.margins: 6
        clip: true
        spacing: 2
        model: pane.results

        delegate: ResultRow {
            required property var modelData

            width: listView.width
            result: modelData
            keyboardSelected: ListView.isCurrentItem
            onClicked: pane.accept(modelData)
        }
    }

    PagePlaceholder {
        shown: pane.visible && pane.results.length === 0
        icon: "search_off"
        title: Translation.tr("No settings match")
        description: Translation.tr("Try a different word")
    }
}
