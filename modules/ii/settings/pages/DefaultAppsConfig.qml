import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.functions as CF
import "../../../common/functions/DefaultAppsStore.js" as Store

/**
 * Default apps = the app each quick-launch shortcut opens.
 *
 * The rows are the frozen catalog's Apps binds, so the combo shown here is the
 * one Hyprland actually listens to. Choosing an app writes a command override
 * through DefaultApps -> ManagedKeybinds; clearing one puts the catalog's
 * fallback chain back. Nothing is written to XDG/mimeapps: file associations
 * are a different question and this page does not pretend to answer it.
 */
ContentPage {
    id: page
    forceWidth: true
    baseWidth: 680
    bottomContentPadding: 24

    property string pickerRole: ""
    property string capturingRole: ""
    property string captureError: ""
    property string searchText: ""
    property bool showAllApps: false

    // The ids behind the row being captured. All of a role's binds get the
    // same combination, so e.g. all three terminal shortcuts stay in step.
    property var captureIds: []

    function closePicker() {
        page.pickerRole = "";
        page.searchText = "";
        page.showAllApps = false;
    }

    function stopCapture() {
        page.capturingRole = "";
        page.captureIds = [];
        captureTimeout.stop();
    }

    function startCapture(role) {
        if (role === null) return;
        page.captureError = "";
        page.captureIds = role.bindIds.map(id => String(id));
        page.capturingRole = role.id;
        captureTimeout.restart();
        Qt.callLater(() => page.forceActiveFocus());
    }

    // Settings forwards unhandled presses to the active page; the page also
    // has its own Keys handler below so capture works with focus inside a row.
    function handleCapturedKey(event) {
        if (page.pickerRole !== "") {
            if (event.key === Qt.Key_Escape) {
                page.closePicker();
                return true;
            }
            return false;
        }
        if (page.capturingRole === "") return false;
        if (event.key === Qt.Key_Escape) {
            page.stopCapture();
            return true;
        }
        const combo = CF.StringUtils.keyEventToCombo(event);
        if (combo === "") return false;

        let firstError = "";
        for (const id of page.captureIds) {
            const result = ManagedKeybinds.setOverride(id, combo);
            if (!result.ok && firstError === "") firstError = result.error;
        }
        page.captureError = firstError;
        page.stopCapture();
        return true;
    }

    Keys.onPressed: event => {
        if (page.handleCapturedKey(event)) event.accepted = true;
    }

    Timer {
        id: captureTimeout
        interval: 10000
        onTriggered: page.stopCapture()
    }

    onEnabledChanged: {
        if (!enabled) {
            page.stopCapture();
            page.closePicker();
        }
    }

    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            if (!GlobalStates.settingsOpen) {
                page.stopCapture();
                page.closePicker();
            }
        }
    }

    // Desktop entries are filtered to the freedesktop categories the catalog
    // fallback chains used. "Show all" turns the filter off for exotic apps.
    function candidates(role) {
        const all = Array.from(DesktopEntries.applications.values)
            .filter(entry => entry && !entry.noDisplay && String(entry.name ?? "") !== "");
        const query = page.searchText.trim().toLowerCase();
        const picked = all.filter(entry => {
            const categories = entry.categories ?? [];
            const execString = String(entry.execString ?? "");
            const relevant = role.categories.some(c => categories.includes(c))
                || role.hints.some(hint => execString.includes(hint) || entry.id === hint);
            return (page.showAllApps || relevant)
                && (query === "" || String(entry.name).toLowerCase().includes(query)
                    || execString.toLowerCase().includes(query));
        });
        picked.sort((a, b) => {
            const ai = role.hints.findIndex(hint => String(a.execString ?? "").includes(hint));
            const bi = role.hints.findIndex(hint => String(b.execString ?? "").includes(hint));
            const ar = ai === -1 ? 100 : ai;
            const br = bi === -1 ? 100 : bi;
            if (ar !== br) return ar - br;
            return String(a.name).localeCompare(String(b.name));
        });
        return picked;
    }

    function choose(role, entry) {
        const result = DefaultApps.choose(role.id, entry);
        if (!result.ok) {
            page.captureError = result.error;
            return;
        }
        page.captureError = "";
        page.closePicker();
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 18

        ContentSection {
            icon: "apps"
            title: Translation.tr("Default apps")
            hint: Translation.tr("Choose the app each quick-launch shortcut opens. Changes are saved to your keybind overrides; the original shortcut keys are kept.")

            ContentSubsection {
                title: Translation.tr("Applications")
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: DefaultApps.roles

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 68
                            radius: Appearance.rounding.normal
                            color: rowMouse.containsMouse
                                ? ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                                : Appearance.colors.colLayer1
                            border.width: 1
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.4)

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: page.pickerRole = row.modelData.id
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12
                                spacing: 12

                                Item {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    AppIcon {
                                        anchors.fill: parent
                                        visible: row.modelData.appIcon !== ""
                                        source: row.modelData.appIcon
                                    }
                                    MaterialSymbol {
                                        anchors.fill: parent
                                        visible: row.modelData.appIcon === ""
                                        iconSize: 26
                                        text: row.modelData.icon
                                        color: Appearance.colors.colPrimary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr(row.modelData.label)
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.bold: true
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.appName !== ""
                                            ? row.modelData.appName
                                            : (row.modelData.command !== ""
                                                ? row.modelData.command
                                                : Translation.tr("System default"))
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        elide: Text.ElideRight
                                    }
                                }

                                RippleButton {
                                    id: comboButton
                                    Layout.preferredWidth: Math.max(86, comboText.implicitWidth + 22)
                                    Layout.preferredHeight: 34
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                                    implicitWidth: Layout.preferredWidth
                                    implicitHeight: Layout.preferredHeight
                                    onClicked: page.startCapture(row.modelData)
                                    contentItem: StyledText {
                                        id: comboText
                                        anchors.centerIn: parent
                                        text: row.modelData.combo.replace(/\s*\+\s*/g, " + ")
                                        color: page.capturingRole === row.modelData.id
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }

                                RippleButton {
                                    visible: row.modelData.overridden
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                                    implicitWidth: Layout.preferredWidth
                                    implicitHeight: Layout.preferredHeight
                                    onClicked: page.choose(row.modelData, null)
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 18
                                        text: "restart_alt"
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: page.captureError !== ""
                        Layout.fillWidth: true
                        text: Translation.tr(page.captureError)
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // App picker. It lives on the page, not in a Loader, because key capture
    // routes through the page and Escape has to close this before anything
    // else sees it.
    Rectangle {
        id: picker
        // ContentPage drops its children into a ColumnLayout. Reparent to the
        // page itself so the scrim can cover the whole viewport, not a cell.
        parent: page
        visible: page.pickerRole !== ""
        anchors.fill: parent
        z: 10
        color: Appearance.colors.colScrim
        radius: Appearance.rounding.normal

        MouseArea {
            anchors.fill: parent
            onClicked: page.closePicker()
        }

        Rectangle {
            id: pickerPanel
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 440)
            height: Math.min(parent.height - 40, 520)
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.3)

            MouseArea {
                anchors.fill: parent
                // Stay above the scrim's MouseArea.
                propagateComposedEvents: false
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Choose app")
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.bold: true
                    }
                    RippleButton {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                        onClicked: page.closePicker()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 18
                            text: "close"
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                DialogSearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search applications")
                    text: page.searchText
                    onTextChanged: page.searchText = text
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    text: Translation.tr("Show all applications")
                    buttonIcon: "apps"
                    checked: page.showAllApps
                    onCheckedChanged: page.showAllApps = checked
                }

                StyledListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: page.pickerRole !== ""
                        ? page.candidates(DefaultApps.roleFor(page.pickerRole) ?? { categories: [], hints: [] })
                        : []

                    header: Rectangle {
                        width: appList.width
                        height: page.pickerRole !== "" && DefaultApps.roleFor(page.pickerRole)?.overridden ? 46 : 0
                        radius: Appearance.rounding.small
                        color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                        visible: height > 0
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            MaterialSymbol {
                                iconSize: 18
                                text: "restart_alt"
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Reset to system default")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.visible
                            onClicked: page.choose(DefaultApps.roleFor(page.pickerRole), null)
                        }
                    }

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        width: appList.width
                        height: 50
                        radius: Appearance.rounding.small
                        color: appMouse.containsMouse
                            ? ColorUtils.transparentize(Appearance.colors.colLayer2, 0.6)
                            : "transparent"

                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: page.choose(DefaultApps.roleFor(page.pickerRole), appRow.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            AppIcon {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                source: appRow.modelData.icon
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Store.commandFromExec(appRow.modelData.execString)
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
