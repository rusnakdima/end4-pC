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
 * One adaptive Settings shell for every style value. The old style names are
 * kept as density presets so existing configs keep working. Both side panels
 * can collapse, and the content pane always keeps a usable minimum width.
 */
Item {
    id: root

    readonly property bool narrow: root.width < 700
    readonly property bool medium: root.width < 1000
    readonly property int minimumContentWidth: 360

    property string selectedCategory: SettingsPages.categories[0] ?? ""
    property string selectedPageId: ""
    readonly property var currentPageData: SettingsPages.byId(root.selectedPageId)

    // Compatibility surface used by Settings.qml's Tab handling. The flat
    // index model stays available even though navigation is page-id based.
    readonly property var pages: SettingsPages.pages
    property int currentPage: 0
    property bool showingProfile: false

    property bool userCategoryCollapsed: false
    property bool userPageListCollapsed: false
    property bool categoryIconsOnly: false
    property bool autoCategoryCollapsed: false
    property bool autoPageListCollapsed: false
    readonly property bool categoryCollapsed: root.userCategoryCollapsed || root.autoCategoryCollapsed
    readonly property bool pageListCollapsed: root.userPageListCollapsed || root.autoPageListCollapsed

    readonly property var categoryRepeater: categoryListRepeater
    readonly property var pageRepeater: pageListRepeater
    readonly property var contentLoader: pageContentLoader
    readonly property var backButtonItem: backButton
    readonly property var breadcrumbItem: breadcrumb
    readonly property var pageListPane: pageListRectangle
    readonly property var searchFieldItem: toolbarSearch
    readonly property var contentPaneItem: contentPane
    readonly property var categoryListPaneItem: categoryListRectangle
    readonly property int activeLoaderCount: pageContentLoader.active ? 1 : 0

    readonly property int categoryWidth: root.categoryCollapsed ? 0 : (root.categoryIconsOnly ? 72 : 180)
    readonly property int pageListWidth: root.pageListCollapsed || (root.narrow && root.selectedPageId !== "") ? 0 : 240

    function applyStylePreset() {
        switch (Config.options.settings.style) {
        case "minimal":
            root.categoryIconsOnly = true;
            break;
        default:
            root.categoryIconsOnly = false;
            break;
        }
        root.userCategoryCollapsed = false;
        root.userPageListCollapsed = false;
        root.applyWidthPolicy();
    }

    // Auto-collapse is transient: widening the window restores the user's
    // own choice instead of leaving panels closed forever.
    function applyWidthPolicy() {
        const rail = root.categoryIconsOnly ? 72 : 180;
        let pageCollapsed = false;
        let categoryCollapsed = false;
        if (root.width - 40 - rail - 240 < root.minimumContentWidth) pageCollapsed = true;
        if (root.width - 40 - rail < root.minimumContentWidth) categoryCollapsed = true;
        root.autoPageListCollapsed = pageCollapsed;
        root.autoCategoryCollapsed = categoryCollapsed;
    }

    function toggleCategoryPanel() {
        root.userCategoryCollapsed = !root.categoryCollapsed;
    }

    function togglePageListPanel() {
        root.userPageListCollapsed = !root.pageListCollapsed;
    }

    function selectCategory(category) {
        if (SettingsPages.pagesInCategory(category).length === 0) return;
        root.selectedCategory = category;
        root.back();
        root.ensureWidePage();
    }

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
        toolbarSearch.forceActiveFocus();
    }

    function pageSectionIds() {
        const ids = [];
        const walk = item => {
            if (!item) return;
            if (item.sectionId !== undefined && item.collapsible === true) ids.push(item.sectionId);
            const kids = item.children ?? [];
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(GlobalStates.currentPageInstance);
        return ids;
    }

    function setPageSectionsCollapsed(collapsed) {
        const ids = root.pageSectionIds();
        if (ids.length === 0) return;
        let list = Config.options.settings.collapsedSections.slice();
        for (let i = 0; i < ids.length; i++) {
            const idx = list.indexOf(ids[i]);
            if (collapsed && idx === -1) list.push(ids[i]);
            else if (!collapsed && idx !== -1) list.splice(idx, 1);
        }
        Config.options.settings.collapsedSections = list;
    }

    // ContentPage centres a fixed 600px column by default. Match it to the
    // pane so cards compress instead of being clipped on narrow windows.
    function fitLoadedPage() {
        const loader = pageContentLoader;
        if (!loader.item) return;
        loader.item.forceWidth = true;
        loader.item.baseWidth = Math.max(0, contentPane.width - 40);
    }

    Component.onCompleted: {
        root.applyStylePreset();
        const pendingTarget = GlobalStates.settingsTarget;
        if (pendingTarget) {
            root.goToTarget(pendingTarget);
            GlobalStates.settingsTarget = null;
        }
        root.ensureWidePage();
    }

    onWidthChanged: root.applyWidthPolicy()
    onNarrowChanged: root.ensureWidePage()
    onSelectedPageIdChanged: {
        const idx = root.pages.findIndex(page => page.id === root.selectedPageId);
        root.currentPage = idx < 0 ? 0 : idx;
        if (root.selectedPageId === "") GlobalStates.currentPageInstance = null;
    }

    Connections {
        target: Config.options.settings
        function onStyleChanged() { root.applyStylePreset(); }
    }

    Connections {
        target: GlobalStates
        function onSettingsTargetChanged() {
            const target = GlobalStates.settingsTarget;
            if (!target) return;
            root.goToTarget(target);
            GlobalStates.settingsTarget = null;
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 8

        Item {
            id: searchHeader
            z: 3
            Layout.fillWidth: true
            Layout.minimumHeight: 40
            implicitHeight: searchRow.implicitHeight

            RowLayout {
                id: searchRow
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                spacing: 8

                IconToolbarButton {
                    text: root.categoryCollapsed ? "left_panel_open" : "left_panel_close"
                    onClicked: root.toggleCategoryPanel()
                    StyledToolTip {
                        text: root.categoryCollapsed
                            ? Translation.tr("Expand categories")
                            : Translation.tr("Collapse categories")
                    }
                }

                IconToolbarButton {
                    text: root.pageListCollapsed ? "menu_open" : "menu"
                    onClicked: root.togglePageListPanel()
                    StyledToolTip {
                        text: root.pageListCollapsed
                            ? Translation.tr("Expand page list")
                            : Translation.tr("Collapse page list")
                    }
                }

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                ToolbarTextField {
                    id: toolbarSearch
                    Layout.fillWidth: true
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

                IconToolbarButton {
                    text: "unfold_less"
                    onClicked: root.setPageSectionsCollapsed(true)
                    StyledToolTip { text: Translation.tr("Collapse all") }
                }
                IconToolbarButton {
                    text: "unfold_more"
                    onClicked: root.setPageSectionsCollapsed(false)
                    StyledToolTip { text: Translation.tr("Expand all") }
                }
            }

            SettingsSearchPane {
                id: settingsSearch
                z: 4
                anchors {
                    top: searchRow.bottom
                    topMargin: 6
                    left: searchRow.left
                    right: searchRow.right
                }
                query: toolbarSearch.text
                onDismissed: toolbarSearch.text = ""
            }
        }

        Item {
            id: panesRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0

            Rectangle {
                id: categoryListRectangle
                visible: !root.categoryCollapsed && (!root.narrow || root.selectedPageId === "")
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: visible ? root.categoryWidth : 0
                color: Appearance.colors.colLayer1Base
                radius: Appearance.rounding.normal

                Column {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 6

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
                                    visible: !root.categoryIconsOnly
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
            }

            Rectangle {
                id: pageListRectangle
                objectName: "unifiedPageList"
                visible: !root.pageListCollapsed && (!root.narrow || root.selectedPageId === "")
                anchors {
                    left: categoryListRectangle.right
                    leftMargin: visible ? 8 : 0
                    top: parent.top
                    bottom: parent.bottom
                }
                width: visible ? root.pageListWidth : 0
                color: Appearance.colors.colLayer0Base
                radius: Appearance.rounding.normal

                Column {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 6

                    StyledText {
                        width: parent.width
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

            Rectangle {
                id: contentPane
                anchors {
                    left: pageListRectangle.right
                    leftMargin: pageListRectangle.visible ? 8 : 0
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                color: "transparent"
                radius: Appearance.rounding.normal
                clip: true

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    RippleButton {
                        id: backButton
                        objectName: "unifiedBackButton"
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
                        objectName: "unifiedBreadcrumb"
                        Layout.fillWidth: true
                        visible: root.narrow && root.selectedPageId !== ""
                        text: root.selectedCategory + " › " + (root.currentPageData?.name ?? root.selectedPageId)
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }

                    Loader {
                        id: pageContentLoader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: Math.max(0, root.width - 32 - root.categoryWidth - root.pageListWidth)
                        Layout.maximumWidth: Math.max(0, root.width - 32 - root.categoryWidth - root.pageListWidth)
                        active: root.selectedPageId !== ""
                        source: root.currentPageData?.component ?? ""

                        onLoaded: {
                            Qt.callLater(root.fitLoadedPage);
                            if (item) GlobalStates.currentPageInstance = item;
                        }
                        onWidthChanged: Qt.callLater(root.fitLoadedPage)
                    }
                }
            }
        }
    }
}
