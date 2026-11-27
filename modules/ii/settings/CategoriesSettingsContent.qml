import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "."

/**
 * Android-17-like categorized Settings: an icon rail of categories, a list
 * of pages inside the selected category, and one lazy page pane. Narrow
 * windows drill down in place with a Windows-style back button and breadcrumb.
 */
Item {
    id: root

    readonly property bool narrow: root.width < 700
    property string selectedCategory: SettingsPages.categories[0] ?? ""
    property string selectedPageId: ""
    readonly property var currentPage: SettingsPages.byId(root.selectedPageId)

    // Test-visible aliases (the hosted Qt Test harness cannot call findChild).
    readonly property var categoryRepeater: categoryListRepeater
    readonly property var pageRepeater: pageListRepeater
    readonly property var contentLoader: pageContentLoader
    readonly property var backButtonItem: backButton
    readonly property var breadcrumbItem: breadcrumb
    readonly property var pageListPane: pageListRectangle
    readonly property var searchFieldItem: categorySearchField
    readonly property int activeLoaderCount: pageContentLoader.active ? 1 : 0

    function selectCategory(category) {
        if (SettingsPages.pagesInCategory(category).length === 0) return;
        root.selectedCategory = category;
        root.back();
        root.ensureWidePage();
    }

    // A wide three-pane window has nowhere to show an empty selection, so it
    // always opens the first page of the category. Narrow windows keep the
    // page list until a page is tapped, then drill down with a back button.
    function ensureWidePage() {
        if (root.narrow || root.selectedPageId !== "") return;
        const pages = SettingsPages.pagesInCategory(root.selectedCategory);
        if (pages.length > 0) root.selectedPageId = pages[0].id;
    }

    function openPage(pageId) {
        const page = SettingsPages.byId(pageId);
        if (!page) return;
        if ((page.category ?? "System") !== root.selectedCategory)
            root.selectedCategory = page.category ?? "System";
        root.selectedPageId = pageId;
    }

    function back() {
        root.selectedPageId = "";
    }

    function goToTarget(target) {
        const page = SettingsPages.byId(target.page);
        if (!page) return;
        root.selectedCategory = page.category ?? "System";
        root.openPage(page.id);
        const run = () => pageContentLoader.item?.goTo(target.label, target.section, target.subsection);
        if (pageContentLoader.item) run();
        else {
            const onceLoaded = () => {
                pageContentLoader.loaded.disconnect(onceLoaded);
                run();
            };
            pageContentLoader.loaded.connect(onceLoaded);
        }
    }

    function focusSearch() {
        settingsSearch.forceActiveFocus();
    }

    // A tile sets settingsTarget before settingsOpen; the window creates this
    // component a few frames later, so the Connections handler below misses
    // that change. Resolve a target that was already pending at creation here.
    Component.onCompleted: {
        const pendingTarget = GlobalStates.settingsTarget;
        if (pendingTarget) {
            root.goToTarget(pendingTarget);
            GlobalStates.settingsTarget = null;
        }
        root.ensureWidePage();
    }

    onNarrowChanged: root.ensureWidePage()

    Connections {
        target: GlobalStates
        function onSettingsTargetChanged() {
            const target = GlobalStates.settingsTarget;
            if (!target) return;
            root.goToTarget(target);
            GlobalStates.settingsTarget = null;
        }
    }

    onSelectedPageIdChanged: {
        if (root.selectedPageId === "") GlobalStates.currentPageInstance = null;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Category rail (macOS Settings-like icon sidebar).
        Rectangle {
            Layout.preferredWidth: 180
            Layout.fillHeight: true
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal

            // A plain Column packs the items from the top down. ColumnLayout
            // distributes the leftover height into the gaps, which spread the
            // navigation items across the whole window.
            Column {
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 6

                ToolbarTextField {
                    id: categorySearchField
                    width: parent.width
                    placeholderText: Translation.tr("Search settings…")
                    onAccepted: settingsSearch.acceptCurrent()
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) {
                            settingsSearch.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            settingsSearch.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape && text !== "") {
                            text = "";
                            event.accepted = true;
                        }
                    }
                }

                Repeater {
                    id: categoryListRepeater
                    model: SettingsPages.categories
                    delegate: RippleButton {
                        buttonText: modelData
                        width: parent.width
                        height: 40
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedCategory === modelData
                            ? Appearance.colors.colPrimaryContainer
                            : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                        onClicked: root.selectCategory(modelData)
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            MaterialSymbol {
                                iconSize: 20
                                text: {
                                    switch (modelData) {
                                    case "Network & internet": return "wifi";
                                    case "Connected devices": return "devices";
                                    case "Personalization": return "palette";
                                    case "System": return "tune";
                                    default: return "info";
                                    }
                                }
                                color: root.selectedCategory === modelData
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData
                                color: root.selectedCategory === modelData
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // Overhang the rail instead of pushing the navigation items down.
            SettingsSearchPane {
                id: settingsSearch
                z: 3
                anchors {
                    top: categorySearchField.bottom
                    topMargin: 6
                    left: parent.left
                    right: parent.right
                    margins: 12
                }
                query: categorySearchField.text
                onDismissed: categorySearchField.text = ""
            }
        }

        // Page list — hidden on narrow windows while a page is open.
        Rectangle {
            id: pageListRectangle
            objectName: "categoriesPageList"
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            visible: !root.narrow || root.selectedPageId === ""
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.normal

            Column {
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 6

                StyledText {
                    width: parent.width
                    visible: !root.narrow || root.selectedPageId === ""
                    text: root.selectedCategory
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Repeater {
                    id: pageListRepeater
                    model: SettingsPages.pagesInCategory(root.selectedCategory)
                    delegate: RippleButton {
                        buttonText: modelData.name
                        width: parent.width
                        height: 40
                        buttonRadius: Appearance.rounding.small
                        colBackground: root.selectedPageId === modelData.id
                            ? Appearance.colors.colSecondaryContainer
                            : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.7)
                        onClicked: root.openPage(modelData.id)
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            MaterialSymbol {
                                iconSize: 20
                                text: modelData.icon ?? "settings"
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // Single lazy page pane.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.narrow || root.selectedPageId !== ""
            color: Appearance.colors.colSurface
            radius: Appearance.rounding.normal

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RippleButton {
                    id: backButton
                    objectName: "categoriesBackButton"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    visible: root.narrow && root.selectedPageId !== ""
                    buttonRadius: Appearance.rounding.small
                    onClicked: root.back()
                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        MaterialSymbol {
                            iconSize: 20
                            text: "arrow_back"
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Settings")
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }

                StyledText {
                    id: breadcrumb
                    objectName: "categoriesBreadcrumb"
                    Layout.fillWidth: true
                    visible: root.narrow && root.selectedPageId !== ""
                    text: root.selectedCategory + " › " + (root.currentPage?.name ?? root.selectedPageId)
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }

                Loader {
                    id: pageContentLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: root.selectedPageId !== ""
                    source: root.currentPage?.component ?? ""
                    onLoaded: {
                        if (item) GlobalStates.currentPageInstance = item;
                    }
                }
            }
        }
    }
}
