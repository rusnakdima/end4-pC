import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The per-app half of the window mode: a list of window classes that
 * always stack, always tile, or always stretch over every monitor, no
 * matter which mode the session is in.
 *
 * The list is edited through a ListModel so a half typed class name does
 * not write itself into the config on every keystroke - the model is
 * committed back on a debounce, the way the autostart list does it.
 */
ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8

    property bool writing: false

    // The rule list gets long once several apps have one. Only the first
    // few rows are shown until the rest are opened, and a row keeps its
    // parameters folded until it is opened itself.
    readonly property int collapsedRows: 3
    property bool listExpanded: false
    property int expandOnCreate: -1

    function modeLabel(mode) {
        if (mode === "span") return Translation.tr("All monitors");
        return mode === "tiling" ? Translation.tr("Tiling") : Translation.tr("Stacking");
    }

    // The config can hold a rule that a newer version wrote. Keep the
    // known modes exactly as they are: rewriting a span rule to stacking
    // would silently drop the stretch on the next edit.
    function normalizeMode(mode) {
        return (mode === "tiling" || mode === "span") ? mode : "stacking";
    }

    ListModel {
        id: entries
    }

    // The windows that are open right now, so a window can be picked
    // instead of typed. Every app offers one entry for the app as a whole
    // and one entry per single window with its title: picking a single
    // window is what targets one sub-window (a browser PiP) without
    // dragging every window of the app in, and picking the app entry keeps
    // the rule on the class alone. The value carries both halves, joined
    // by a separator no window title contains.
    readonly property string windowSeparator: "\u0001"
    readonly property var runningWindows: {
        const sep = root.windowSeparator;
        const seen = new Set();
        const list = [];
        for (const win of (HyprlandData.windowList ?? [])) {
            const winClass = String(win.class ?? "");
            const winTitle = String(win.title ?? "");
            if (winClass.length === 0) continue;
            if (!seen.has(winClass + sep)) {
                seen.add(winClass + sep);
                list.push({
                    "displayName": Translation.tr("%1 (all windows)").arg(winClass),
                    "value": winClass + sep,
                    "winClass": winClass,
                    "winTitle": ""
                });
            }
            if (winTitle.length === 0 || seen.has(winClass + sep + winTitle)) continue;
            seen.add(winClass + sep + winTitle);
            list.push({
                "displayName": Translation.tr("%1 — %2").arg(winClass).arg(winTitle),
                "value": winClass + sep + winTitle,
                "winClass": winClass,
                "winTitle": winTitle
            });
        }
        // Grouped by class with the whole-app entry first, so an app and
        // its windows stay together whatever the translations say.
        list.sort((a, b) => a.winClass.localeCompare(b.winClass)
            || (a.winTitle.length === 0 ? -1 : b.winTitle.length === 0 ? 1 : 0)
            || a.winTitle.localeCompare(b.winTitle));
        return list;
    }

    // The picker entry that describes the rule of this row: the single
    // window when the rule carries a title, the whole-app entry when it
    // does not, and the placeholder when nothing running matches - a
    // typed title must never be shown as if it were a picked one.
    function currentPickerValue(winClass, winTitle) {
        if (winClass.length === 0) return "";
        const match = root.runningWindows.find(w => w.winClass === winClass && w.winTitle === winTitle);
        return match ? match.value : "";
    }

    function snapshot() {
        const list = [];
        for (let i = 0; i < entries.count; i++) {
            const entry = entries.get(i);
            list.push({ "class": String(entry.winClass), "title": String(entry.winTitle ?? ""), "mode": entry.mode, "disableOpacity": entry.disableOpacity === true });
        }
        return list;
    }

    function configSnapshot() {
        return (WindowMode.appRules ?? []).map(rule => ({
            "class": String(rule?.class ?? ""),
            "title": String(rule?.title ?? ""),
            "mode": root.normalizeMode(rule?.mode),
            "disableOpacity": rule?.disableOpacity === true
        }));
    }

    function loadFromConfig() {
        entries.clear();
        for (const rule of root.configSnapshot()) {
            entries.append({ "winClass": rule.class, "winTitle": rule.title, "mode": rule.mode, "disableOpacity": rule.disableOpacity === true });
        }
    }

    function commit() {
        root.writing = true;
        WindowMode.setAppRules(root.snapshot());
        root.writing = false;
    }

    function setField(index, key, value) {
        if (index < 0 || index >= entries.count || entries.get(index)[key] === value) return;
        entries.setProperty(index, key, value);
        root.commit();
    }

    function addEntry() {
        entries.append({ "winClass": "", "winTitle": "", "mode": "stacking", "disableOpacity": false });
        // The new row opens itself, and so does the list when the row would
        // otherwise land below the fold.
        root.expandOnCreate = entries.count - 1;
        if (entries.count > root.collapsedRows) root.listExpanded = true;
        root.commit();
    }

    function removeEntry(index) {
        entries.remove(index);
        root.commit();
    }

    Component.onCompleted: root.loadFromConfig()

    Connections {
        target: Config.options.hyprland.windowMode
        function onAppRulesChanged() {
            // A commit of this widget owns the list until it is done.
            if (root.writing) return;
            if (JSON.stringify(root.snapshot()) !== JSON.stringify(root.configSnapshot())) root.loadFromConfig();
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: "info"
        text: Translation.tr("Stacking floats every window so they overlap, tiling keeps the layout. A rule below keeps one app on the other side of that choice; All monitors also floats it, stretches it over every screen and ignores fullscreen requests. Window class plus Window subclass narrow a rule to one window of an app (a picture-in-picture, for example), and Disable opacity makes exactly that window ignore the global opacity.")
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        visible: entries.count === 0
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
        text: Translation.tr("No rules yet. Every app then follows the mode of the session.")
    }

    Repeater {
        model: entries

        delegate: ColumnLayout {
            id: entryItem
            Layout.fillWidth: true
            spacing: 4

            visible: root.listExpanded || index < root.collapsedRows

            readonly property string entryClass: model.winClass
            readonly property string entryTitle: model.winTitle ?? ""
            readonly property string entryMode: model.mode
            readonly property bool entryDisableOpacity: model.disableOpacity === true
            property bool expanded: false

            Component.onCompleted: {
                if (index === root.expandOnCreate) {
                    expanded = true;
                    root.expandOnCreate = -1;
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 4
                spacing: 8

                // The header folds and unfolds this app's parameters. The
                // mode stays readable while the row is folded, so the list
                // still says what each rule decides.
                Item {
                    id: headerTarget
                    Layout.fillWidth: true
                    implicitHeight: headerRow.implicitHeight

                    RowLayout {
                        id: headerRow
                        anchors.fill: parent
                        spacing: 6

                        MaterialSymbol {
                            text: entryItem.expanded ? "expand_less" : "expand_more"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            // The subclass belongs in the folded row too:
                            // two rules of the same app differ only by it.
                            text: {
                                const label = entryItem.entryClass !== ""
                                    ? entryItem.entryClass
                                    : Translation.tr("App %1").arg(index + 1);
                                return entryItem.entryTitle !== ""
                                    ? Translation.tr("%1 — %2").arg(label).arg(entryItem.entryTitle)
                                    : label;
                            }
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: !entryItem.expanded
                            text: root.modeLabel(entryItem.entryMode)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: entryItem.expanded = !entryItem.expanded
                    }
                }

                RippleButton {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    buttonRadius: width / 2
                    colBackground: ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.6)
                    colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.5)
                    onClicked: root.removeEntry(index)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colError
                    }
                    StyledToolTip {
                        text: Translation.tr("Remove")
                    }
                }
            }

            GroupedList {
                Layout.fillWidth: true
                visible: entryItem.expanded

                ConfigTextArea {
                    id: classField
                    Layout.fillWidth: true
                    buttonIcon: "select_window"
                    text: Translation.tr("Window class")
                    description: Translation.tr("Regex matched against the window class, e.g. zen")
                    placeholderText: Translation.tr("e.g. firefox")
                    fieldWidth: 320
                    value: entryItem.entryClass

                    property bool ready: false
                    Component.onCompleted: ready = true

                    onValueChanged: if (ready) classDebounce.restart()
                    onConfirmClicked: {
                        classDebounce.stop()
                        root.setField(index, "winClass", value)
                    }
                    textArea.onActiveFocusChanged: {
                        if (!textArea.activeFocus && ready) {
                            classDebounce.stop()
                            root.setField(index, "winClass", value)
                        }
                    }

                    Timer {
                        id: classDebounce
                        interval: 600
                        onTriggered: root.setField(index, "winClass", classField.value)
                    }
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "apps"
                    text: Translation.tr("Running window")
                    description: Translation.tr("Pick a single window to target only it, or the app entry to target every window of the app")
                    searchable: true
                    fixedWidth: true
                    fieldWidth: 260
                    // The first entry is the placeholder: the combo box
                    // falls back to the first item of its model, so a rule
                    // that matches nothing running has to say so.
                    model: [{ "displayName": Translation.tr("Choose one"), "value": "" }].concat(root.runningWindows)
                    currentValue: root.currentPickerValue(entryItem.entryClass, entryItem.entryTitle)
                    onSelected: newValue => {
                        const picked = root.runningWindows.find(win => win.value === newValue);
                        if (!picked) return;
                        // Both halves come from the entry that was picked:
                        // the app entry carries an empty title (all windows
                        // of the class), a window entry carries its title.
                        root.setField(index, "winClass", picked.winClass);
                        root.setField(index, "winTitle", picked.winTitle);
                    }
                }

                ConfigTextArea {
                    id: titleField
                    Layout.fillWidth: true
                    buttonIcon: "title"
                    text: Translation.tr("Window subclass (title regex)")
                    description: Translation.tr("Narrows the rule to one window, e.g. Picture-in-Picture. Leave empty to match every window of the app")
                    placeholderText: Translation.tr("e.g. Picture-in-Picture (regex)")
                    fieldWidth: 320
                    value: entryItem.entryTitle

                    property bool ready: false
                    Component.onCompleted: ready = true

                    onValueChanged: if (ready) titleDebounce.restart()
                    onConfirmClicked: {
                        titleDebounce.stop()
                        root.setField(index, "winTitle", value)
                    }
                    textArea.onActiveFocusChanged: {
                        if (!textArea.activeFocus && ready) {
                            titleDebounce.stop()
                            root.setField(index, "winTitle", value)
                        }
                    }

                    Timer {
                        id: titleDebounce
                        interval: 600
                        onTriggered: root.setField(index, "winTitle", titleField.value)
                    }
                }

                ConfigSelectionArray {
                    text: Translation.tr("Always")
                    icon: "swap_horiz"
                    currentValue: entryItem.entryMode
                    onSelected: newValue => root.setField(index, "mode", newValue)
                    options: [
                        { displayName: Translation.tr("Stacking"), icon: "layers", value: "stacking" },
                        { displayName: Translation.tr("Tiling"), icon: "grid_view", value: "tiling" },
                        { displayName: Translation.tr("All monitors"), icon: "desktop_windows", value: "span" },
                    ]
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "opacity"
                    text: Translation.tr("Disable opacity (ignore global)")
                    checked: entryItem.entryDisableOpacity
                    onCheckedChanged: {
                        if (checked === entryItem.entryDisableOpacity) return
                        root.setField(index, "disableOpacity", checked)
                    }
                }
            }
        }
    }

    // The rest of the list, once there is a rest.
    RippleButton {
        visible: entries.count > root.collapsedRows
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        buttonRadius: Appearance.rounding.normal
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)
        colRipple: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.7)
        onClicked: root.listExpanded = !root.listExpanded
        contentItem: Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: root.listExpanded ? "expand_less" : "expand_more"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: root.listExpanded
                        ? Translation.tr("Show fewer")
                        : Translation.tr("Show all %1 apps").arg(entries.count)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }
            }
        }
    }

    RippleButton {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        buttonRadius: Appearance.rounding.normal
        colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
        colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.5)
        onClicked: root.addEntry()
        contentItem: Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    text: "add"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Add app")
                    color: Appearance.colors.colPrimary
                    font.weight: Font.Medium
                }
            }
        }
    }
}
