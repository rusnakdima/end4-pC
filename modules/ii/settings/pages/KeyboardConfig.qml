import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

/**
 * Keyboard backlight colour, shell shortcuts and the other keybinds.
 *
 * The colour picker drives the system keyboard backlight helper; the
 * shortcut list comes from the same parser the cheatsheet uses, so it
 * always matches the config the compositor loaded. A rebind is written
 * to ~/.config/hypr/custom/keybind_overrides.conf and Hyprland is
 * reloaded. The keybind sections only exist on Hyprland.
 */
ContentPage {
    id: page
    forceWidth: true
    baseWidth: 600
    focus: true

    // The colour of a "this combination is already taken" hint. Amber
    // rather than the palette's tertiary, which follows the wallpaper and
    // is not always yellow; the shade follows the mode so it stays
    // readable on light and dark surfaces alike.
    readonly property color conflictColor: Appearance.m3colors.darkmode ? "#FFCA5B" : "#8A5300"

    // ------------------------------------------------------
    // Keyboard colour
    // ------------------------------------------------------

    readonly property int saturationSteps: 30
    readonly property int valueSteps: 30
    readonly property int hueSteps: 360

    // Store and apply together: picking a colour implies you want it kept, so
    // it also turns colour management on. The swatches, the hex field and the
    // Apply button all go through here instead of having three paths.
    function pickColour(hex: string): void {
        Config.options.light.keyboardColor.color = hex;
        Config.options.light.keyboardColor.enable = true;
        Brightness.kbMonitor.setColorHex(hex);
    }

    Component.onCompleted: {
        // Whatever is already on the hardware wins, then the stored choice.
        const applied = Brightness.kbMonitor?.color;
        const stored = Config.options.light.keyboardColor.color;
        currentColor = applied || (stored && stored !== "" ? stored : "#FFFFFF");
    }

    property string currentColor: "#FFFFFF"
    property real hue: 0
    property real saturation: 100
    property real value: 100

    // Update currentColor when HSV changes
    property var hsvColor: Qt.hsva(hue / 360, saturation / 100, value / 100, 1)

    onHueChanged: currentColor = hsvColor
    onSaturationChanged: currentColor = hsvColor
    onValueChanged: currentColor = hsvColor

    // When currentColor changes externally, update HSV
    onCurrentColorChanged: {
        const col = Qt.color(currentColor);
        hue = col.h * 360;
        saturation = col.s * 100;
        value = col.v * 100;
    }

    // A labelled slider for the three HSV controls. The caller keeps a
    // one-way binding on `value` and listens for `valueEdited`, so a reset
    // coming from outside still moves the thumb.
    component SliderCard: Rectangle {
        id: card

        property string title: ""
        property real value: 0
        property real from: 0
        property real to: 100
        property real step: 1
        signal valueEdited(real newValue)

        implicitWidth: 300
        implicitHeight: cardContent.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: card.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurface
                }

                Text {
                    text: Math.round(card.value).toString()
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colPrimary
                }
            }

            Slider {
                id: slider
                Layout.fillWidth: true
                from: card.from
                to: card.to
                stepSize: card.step
                // Follow the model again as soon as the user lets go, so an
                // outside reset is not swallowed by the drag binding.
                Binding {
                    target: slider
                    property: "value"
                    value: card.value
                    when: !slider.pressed
                }
                onMoved: card.valueEdited(value)
            }
        }
    }

    // ------------------------------------------------------
    // Shortcut capture
    // ------------------------------------------------------
    // The id whose key combination is being captured right now: the name of
    // a shell action, or the bind_<key> id of one of the compositor's own
    // binds.
    property string capturing: ""

    function startCapture(action) {
        page.capturing = action;
        captureTimeout.restart();
        Qt.callLater(() => page.forceActiveFocus());
    }

    // Releasing the capture is always done here, never only by pressing a
    // key: a capture that stays alive keeps every key press inside the
    // settings panel, so Escape and plain letters never reach the app.
    function stopCapture() {
        if (page.capturing === "") return;
        page.capturing = "";
        captureTimeout.stop();
    }

    onEnabledChanged: {
        if (enabled) {
            Qt.callLater(() => page.forceActiveFocus());
        } else {
            // The page was left, the capture goes with it.
            page.stopCapture();
        }
    }

    // The panel was closed, the capture goes with it.
    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            if (!GlobalStates.settingsOpen) page.stopCapture();
        }
    }

    // A capture that is never finished must not hold the keyboard forever.
    Timer {
        id: captureTimeout
        interval: 10000
        onTriggered: page.stopCapture()
    }

    // The press of a capture, as the settings window hands it over. A click
    // inside the list does not always move the focus to this page, so the
    // window forwards the press here as well; returning true means the
    // combination was taken and the event must not travel on.
    function handleCapturedKey(event) {
        if (page.capturing === "") return false;

        if (event.key === Qt.Key_Escape) {
            // Cancel the capture, but let the press travel on: the panel
            // closes on Escape as well.
            page.stopCapture();
            return false;
        }

        const combo = CF.StringUtils.keyEventToCombo(event);
        if (combo === "") {
            // A modifier on its own, or a key Hyprland would not know.
            // It is deliberately not accepted: swallowing it would eat the
            // modifier of the combination that follows.
            return false;
        }

        HyprlandBindOverrides.setOverride(page.capturing, combo);
        page.stopCapture();
        return true;
    }

    Keys.onPressed: (event) => {
        if (page.handleCapturedKey(event)) event.accepted = true;
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20

        ContentSection {
            icon: "light_mode"
            title: Translation.tr("Keyboard Color")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 20

                Text {
                    text: Translation.tr("Set the keyboard backlight colour and brightness. Colours go through the system's keyboard backlight helper.")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                    Layout.maximumWidth: 500
                    wrapMode: Text.WordWrap
                }

                // Named colours, applied as soon as they are clicked. The same table
                // backs the quick-control select, so the two cannot drift apart.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 700
                    spacing: 10
                    visible: Brightness.kbMonitor.available

                    MaterialSymbol {
                        text: "palette"
                        iconSize: Appearance.font.pixelSize.normal + 5
                        color: Appearance.colors.colOnLayer1
                    }

                    CustomColorSelectionArray {
                        spacing: 4
                        swatchSize: 36
                        options: Brightness.keyboardColors
                        currentValue: Config.options.light.keyboardColor.color
                        onSelected: newValue => page.pickColour(newValue)
                    }
                }

                GridLayout {
                    visible: Brightness.kbMonitor.available
                    columns: 2
                    columnSpacing: 16
                    rowSpacing: 16
                    Layout.maximumWidth: 700

                    SliderCard {
                        title: Translation.tr("Hue")
                        value: hue
                        from: 0
                        to: 360
                        step: 1
                        onValueEdited: page.hue = newValue
                        Layout.fillWidth: true
                    }

                    SliderCard {
                        title: Translation.tr("Saturation")
                        value: saturation
                        from: 0
                        to: 100
                        step: 1
                        onValueEdited: page.saturation = newValue
                        Layout.fillWidth: true
                    }

                    SliderCard {
                        title: Translation.tr("Brightness")
                        // page.value, not `value`: unqualified it would bind to the
                        // card's own property and never read the model.
                        value: page.value
                        from: 0
                        to: 100
                        step: 1
                        onValueEdited: page.value = newValue
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        id: colorPreview
                        width: 120
                        height: 120
                        radius: 12
                        color: currentColor
                        border.width: 1
                        border.color: Appearance.colors.colOutline
                        Layout.rowSpan: 2
                        Layout.columnSpan: 1

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "color_lens"
                            iconSize: 48
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    TextField {
                        id: colorInput
                        text: currentColor
                        placeholderText: Translation.tr("#RRGGBB")
                        Layout.fillWidth: true
                        Layout.columnSpan: 1
                        Layout.rowSpan: 1

                        onEditingFinished: {
                            const c = Qt.color(text);
                            if (c.isValid) {
                                page.currentColor = c.name();
                                page.pickColour(c.name());
                            }
                        }
                    }

                    Rectangle {
                        Layout.rowSpan: 1
                        Layout.columnSpan: 1
                        Layout.minimumWidth: 120
                        Layout.minimumHeight: 48
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8

                            RippleButton {
                                text: Translation.tr("Apply")
                                colBackground: currentColor
                                colBackgroundHover: Qt.darker(currentColor, 1.1)
                                colRipple: Appearance.colors.colPrimaryHover
                                onClicked: page.pickColour(page.currentColor)
                                Layout.fillWidth: true
                            }

                            RippleButton {
                                text: Translation.tr("Reset")
                                colBackground: Appearance.colors.colSurfaceContainer
                                colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                                colRipple: Appearance.colors.colPrimaryHover
                                onClicked: {
                                    page.currentColor = "#FFFFFF";
                                    page.hue = 0;
                                    page.saturation = 0;
                                    page.value = 100;
                                    page.pickColour("#FFFFFF");
                                }
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // Say exactly what is missing rather than the old vague "may appear
                // disabled": on this machine the LED comes from the uniwill_wmi
                // module, which is listed in /etc/modules-load.d/ but is not loaded.
                NoticeBox {
                    Layout.fillWidth: true
                    visible: !Brightness.kbMonitor.available
                    materialIcon: "memory"
                    text: Translation.tr("No keyboard backlight device was found. It is provided by the uniwill_wmi module, which is listed in /etc/modules-load.d/ but is not loaded. Run: sudo modprobe uniwill_wmi - then reopen this page.")
                }

                // sudo -n cannot prompt from a background process, so whatever the
                // helper wrote to stderr is shown verbatim instead of being dropped.
                NoticeBox {
                    Layout.fillWidth: true
                    visible: !Brightness.kbMonitor.statusOk && Brightness.kbMonitor.statusMessage !== ""
                    materialIcon: "error"
                    text: Brightness.kbMonitor.statusMessage
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "palette"
                    text: Translation.tr('Manage keyboard colour')
                    checked: Config.options.light.keyboardColor.enable
                    onCheckedChanged: {
                        Config.options.light.keyboardColor.enable = checked;
                        if (checked) Brightness.kbMonitor.applyFromConfig();
                    }
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "wallpaper"
                    text: Translation.tr('Match the wallpaper colour')
                    enabled: Config.options.light.keyboardColor.enable
                    checked: Config.options.light.keyboardColor.followWallpaper
                    onCheckedChanged: {
                        Config.options.light.keyboardColor.followWallpaper = checked;
                        if (checked) Brightness.kbMonitor.applyFromConfig();
                    }
                }

            }
        }

        // The bind lists talk to Hyprland services; on any other
        // compositor the Loader stays inactive so they are never
        // created.
        Loader {
            Layout.fillWidth: true
            active: WM.compositor === "hyprland"
            sourceComponent: Component {
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    ContentSection {
                        icon: "keyboard"
                        title: Translation.tr("Shell shortcuts")
                        hint: Translation.tr("Click a shortcut and press the key combination you want to use.")
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                visible: HyprlandKeybinds.shellActions.length === 0
                                text: Translation.tr("No keybinds found.")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: HyprlandKeybinds.shellActions
                                delegate: ShortcutRow {
                                    required property var modelData
                                    actionData: modelData
                                    capturing: page.capturing === modelData.action
                                }
                            }
                        }
                    }
                    ContentSection {
                        icon: "keyboard"
                        title: Translation.tr("Other keybinds")
                        hint: Translation.tr("The compositor's own binds. Click a bind to give it another key combination.")
                        collapsible: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 20
                            Repeater {
                                model: HyprlandKeybinds.otherSections
                                delegate: ColumnLayout {
                                    id: sectionColumn
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sectionColumn.modelData.name === "" ? Translation.tr("Uncategorized") : sectionColumn.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.title
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    Repeater {
                                        model: sectionColumn.modelData.binds
                                        delegate: OtherBindRow {
                                            required property var modelData
                                            bindData: modelData
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
            }
        }
    }

    // An editable shell shortcut.
    component ShortcutRow: Rectangle {
        id: shortcutRow
        required property var actionData
        property bool capturing: false

        readonly property string defaultCombo: actionData?.combos?.[0] ?? ""
        readonly property string combo: HyprlandBindOverrides.comboFor(actionData?.action ?? "", shortcutRow.defaultCombo)
        readonly property var aliases: (actionData?.combos ?? []).slice(1)
        // Who else uses this combination, so a clash is visible before the
        // user has to discover it by pressing the key. Shell shortcuts
        // only: a shared key that is a deliberate fallback is not a clash.
        readonly property var conflicts: HyprlandKeybinds.comboUsers(shortcutRow.combo, shortcutRow.actionData?.action ?? "")

        Layout.fillWidth: true
        implicitHeight: shortcutRowLayout.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal
        border.width: shortcutRow.capturing ? 1 : 0
        border.color: Appearance.colors.colPrimary

        RowLayout {
            id: shortcutRowLayout
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: (shortcutRow.actionData?.description ?? "") !== ""
                        ? shortcutRow.actionData.description
                        : (shortcutRow.actionData?.action ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: shortcutRow.aliases.length > 0
                    text: Translation.tr("Also bound to %1").arg(shortcutRow.aliases.join(", "))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                // Yellow under the option: who else is on this combination.
                StyledText {
                    Layout.fillWidth: true
                    visible: !shortcutRow.capturing && shortcutRow.conflicts.length > 0
                    text: Translation.tr("Also used by %1").arg(shortcutRow.conflicts.map(c => c.label).join(", "))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: page.conflictColor
                    wrapMode: Text.Wrap
                }
            }

            StyledText {
                visible: shortcutRow.capturing
                text: Translation.tr("Press a key combination...")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            Item {
                id: shortcutRowCaps
                visible: !shortcutRow.capturing
                implicitWidth: shortcutRowCapsRow.implicitWidth
                implicitHeight: shortcutRowCapsRow.implicitHeight

                Row {
                    id: shortcutRowCapsRow
                    spacing: 4

                    Repeater {
                        model: shortcutRow.combo.split(" + ")
                        delegate: KeyboardKey {
                            required property var modelData
                            key: modelData
                            pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.startCapture(shortcutRow.actionData.action)
                }
            }

            // A visible edit affordance. Without it the row only reacts to
            // the key caps, which does not look editable at all.
            Item {
                id: editButton
                visible: !shortcutRow.capturing
                implicitWidth: 20
                implicitHeight: 20

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.startCapture(shortcutRow.actionData.action)
                }
            }

            MaterialSymbol {
                visible: HyprlandBindOverrides.isOverridden(shortcutRow.actionData?.action ?? "")
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                text: "restart_alt"

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        HyprlandBindOverrides.clearOverride(shortcutRow.actionData.action);
                        page.stopCapture();
                    }
                }
            }
        }
    }

    // A keybind that is not a shell action. It is stored under the key it
    // was written with, so a rebind writes "bind_<key> = <combo>" into the
    // overrides file and the wrapper in custom/env.lua moves the bind on
    // the next reload. That wrapper skips shell shortcuts, which is why
    // this bind and a shortcut can share a key without moving together.
    component OtherBindRow: Rectangle {
        id: otherBindRow
        required property var bindData

        readonly property string originalCombo: HyprlandKeybinds.comboOf(bindData)
        readonly property string overrideId: "bind_" + otherBindRow.originalCombo.replace(/[^A-Za-z0-9_]/g, "_")
        readonly property string combo: HyprlandBindOverrides.comboFor(otherBindRow.overrideId, otherBindRow.originalCombo)
        readonly property bool overridden: HyprlandBindOverrides.isOverridden(otherBindRow.overrideId)
        readonly property bool capturing: page.capturing === otherBindRow.overrideId

        Layout.fillWidth: true
        implicitHeight: otherBindRowLayout.implicitHeight + 16
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        RowLayout {
            id: otherBindRowLayout
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12

            StyledText {
                visible: otherBindRow.capturing
                text: Translation.tr("Press a key combination...")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            Item {
                id: otherCaps
                visible: !otherBindRow.capturing
                implicitWidth: otherCapsRow.implicitWidth
                implicitHeight: otherCapsRow.implicitHeight

                Row {
                    id: otherCapsRow
                    spacing: 4

                    Repeater {
                        model: otherBindRow.combo.split(" + ")
                        delegate: KeyboardKey {
                            required property var modelData
                            key: modelData
                            pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.startCapture(otherBindRow.overrideId)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: (otherBindRow.bindData.comment ?? "") !== ""
                        ? otherBindRow.bindData.comment
                        : otherBindRow.originalCombo
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }

            // A visible edit affordance, the same one the shortcut rows have.
            Item {
                visible: !otherBindRow.capturing
                implicitWidth: 20
                implicitHeight: 20

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.startCapture(otherBindRow.overrideId)
                }
            }

            MaterialSymbol {
                visible: otherBindRow.overridden && !otherBindRow.capturing
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                text: "restart_alt"

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        HyprlandBindOverrides.clearOverride(otherBindRow.overrideId);
                        page.stopCapture();
                    }
                }
            }
        }
    }
}
