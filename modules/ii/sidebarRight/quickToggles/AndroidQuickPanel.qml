import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    visible: root.editMode || root.toggles.length > 0

    implicitHeight: (editMode ? contentItem.implicitHeight : usedRows.implicitHeight) + root.padding * 2
    Behavior on implicitHeight {
        // During a drag the row spacer animates the content directly; a
        // second animation here would drag the background behind it.
        enabled: !root.dragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    readonly property list<string> availableToggleTypes: {
        const base = ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang", "vpn", "liveWallpaper", "hotspot"]
        return WM.compositor === "hyprland" ? base : base.filter(t => t !== "gameMode")
    }
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: {
        if (!Config.ready) return []
        const raw = Config.options.sidebar.quickToggles.android.toggles
        return WM.compositor === "hyprland" ? raw : raw.filter(t => !t || t.type !== "gameMode")
    }
    readonly property list<var> toggleRows: toggleRowsForList(toggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    property alias dropIndicator: dropIndicator

    // --- drag state ---------------------------------------------------
    // The panel owns the drag: buttons report pointer positions here,
    // the panel computes where the dragged tile would land and the
    // offsets the other tiles glide by. Nothing walks the scene graph.
    property string dragType: ""
    property var previewOrder: null
    property bool dragging: false

    readonly property var previewShifts: {
        if (!previewOrder) return {};
        return QuickToggles.shiftsFor(toggles, previewOrder, dragType,
                                      baseCellWidth, baseCellHeight, spacing, columns);
    }
    readonly property int dragExtraRows: {
        if (!dragging || !previewOrder) return 0;
        return Math.max(0, QuickToggles.rowCount(previewOrder, columns) - toggleRows.length);
    }

    function beginDrag(type) {
        dragType = type;
        previewOrder = toggles.slice();
        dragging = true;
        moveDropIndicator();
    }

    function updateDrag(sceneX, sceneY) {
        if (!dragging) return;
        const point = usedRows.mapFromItem(null, sceneX, sceneY);
        const index = QuickToggles.insertionIndex(toggles, dragType, point,
                                                  baseCellWidth, baseCellHeight, spacing, columns);
        if (index < 0) return;
        const next = QuickToggles.previewOrderOf(toggles, dragType, index);
        // Only touch previewOrder when the insertion point actually moved,
        // so the glide animations are not restarted on every mousemove.
        if (previewOrder && next.length === previewOrder.length
            && next.every((t, i) => t === previewOrder[i])) return;
        previewOrder = next;
        moveDropIndicator();
    }

    function moveDropIndicator() {
        const rects = QuickToggles.slotRects(previewOrder, columns, baseCellWidth, baseCellHeight, spacing);
        const rect = rects[dragType];
        if (!rect) return;
        const topLeft = usedRows.mapToItem(root, rect.x, rect.y);
        dropIndicator.x = topLeft.x;
        dropIndicator.y = topLeft.y;
        dropIndicator.width = rect.w;
        dropIndicator.height = rect.h;
        dropIndicator.visible = true;
    }

    function endDrag() {
        if (!dragging) return;
        const previous = previewOrder;
        dragging = false;
        commitOrder(previous);
        dragType = "";
        previewOrder = null;
        dropIndicator.visible = false;
    }

    // Write the new order in one shot (the JsonAdapter notifies and
    // persists on whole-array assignment). Called from endDrag, which
    // itself runs via Qt.callLater so we never reorder delegates from
    // inside the DragHandler's own signal handler. Entries the panel
    // does not show (gameMode on non-hyprland) are kept in place.
    function commitOrder(order) {
        if (!order) return;
        const raw = Config.options.sidebar.quickToggles.android.toggles;
        // The config list can hold null entries; they are kept as-is.
        const shownTypes = new Set(order.filter(t => t && t.type).map(t => t.type));
        let next = 0;
        const merged = raw.map(t => (t && shownTypes.has(t.type)) ? order[next++] : t);
        if (merged.length === raw.length && merged.every((t, i) => t === raw[i])) return;
        Config.options.sidebar.quickToggles.android.toggles = merged;
    }

    function rowKeys(rows) {
        return rows.map(row => row.map(toggle => `${toggle.type}:${toggle.size}`).join("|"));
    }

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0;
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) rows.push(row);
        return rows;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        Column {
            id: usedRows
            spacing: root.spacing

            Repeater {
                id: usedRowsRepeater
                model: ScriptModel {
                    values: root.rowKeys(root.toggleRows)
                }
                delegate: ButtonGroup {
                    id: toggleRow
                    required property int index
                    property var rowData: root.toggleRows[index]
                    property int startingIndex: {
                        const rows = root.toggleRows;
                        let sum = 0;
                        for (let i = 0; i < index; i++) sum += rows[i].length;
                        return sum;
                    }
                    spacing: root.spacing
                    // ButtonGroup.contentWidth counts a spacing for the
                    // zero-width Repeater child too, which stretches the
                    // first tile by one gap. Size the row from the tiles
                    // themselves so every slot matches QuickToggles.js.
                    width: QuickToggles.rowWidth(rowData, root.baseCellWidth, root.spacing)

                    Repeater {
                        model: ScriptModel {
                            values: toggleRow?.rowData ?? []
                            objectProp: "type"
                        }
                        delegate: AndroidToggleDelegateChooser {
                            startingIndex: toggleRow.startingIndex
                            editMode: root.editMode
                            panelRef: root
                            isUnused: false
                            baseCellWidth: root.baseCellWidth
                            baseCellHeight: root.baseCellHeight
                            spacing: root.spacing
                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                            onOpenAudioInputDialog: root.openAudioInputDialog()
                            onOpenBluetoothDialog: root.openBluetoothDialog()
                            onOpenNightLightDialog: root.openNightLightDialog()
                            onOpenWifiDialog: root.openWifiDialog()
                            onOpenVpnDialog: root.openVpnDialog()
                            onOpenHotspotDialog: root.openHotspotDialog()
                        }
                    }
                }
            }

            // Holds the extra rows a preview packing needs while a tile is
            // dragged, so gliding tiles never overlap the divider. Column
            // ignores it at height 0.
            Item {
                id: dragRowSpacer
                width: 1
                // A non-zero child costs one Column gap on top of its
                // height, so subtract it to make the growth exact.
                height: Math.max(0, root.dragExtraRows * (root.baseCellHeight + root.spacing) - root.spacing)
                Behavior on height {
                    enabled: root.dragging
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        FadeLoader {
            shown: root.editMode
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: root.rowKeys(root.unusedToggleRows)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var rowData: root.unusedToggleRows[index]
                        spacing: root.spacing
                        // Same phantom-Repeater-gap fix as the used rows.
                        width: QuickToggles.rowWidth(rowData, root.baseCellWidth, root.spacing)

                        Repeater {
                            model: ScriptModel {
                                values: unusedToggleRow?.rowData ?? []
                                objectProp: "type"
                            }
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: -1
                                editMode: root.editMode
                                isUnused: true
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                            }
                        }
                    }
                }
            }
        }

        ConfigSpinBox {
            visible: root.editMode
            width: parent.width 
            enabled: Config.options.sidebar.quickToggles.style === "android"
            icon: "add_column_left"
            text: Translation.tr("Columns")
            value: Config.options.sidebar.quickToggles.android.columns
            from: 1
            to: 8
            stepSize: 1
            onValueChanged: {
                Config.options.sidebar.quickToggles.android.columns = value;
            }
        }
    }
    Rectangle {
        id: dropIndicator
        visible: false
        z: 99
        radius: Appearance.rounding.large
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
        border.width: 2
        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)

        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
}