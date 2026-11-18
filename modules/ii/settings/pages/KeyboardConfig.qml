import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import "../../../common/functions/KeybindLabels.js" as KeybindLabels

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

    // The yellow line under a row: the other binds that hold the same
    // combination, with a tag for the ones that live in the user's own
    // custom/keybinds.lua instead of the theme's config.
    function repeatSentence(repeats) {
        const labels = repeats.map(holder => holder.file === "custom"
            ? Translation.tr("%1 (custom)").arg(holder.label)
            : holder.label);
        return Translation.tr("Also used by %1").arg(labels.join(", "));
    }

    // ------------------------------------------------------
    // The single keybind filter
    // ------------------------------------------------------
    // All three bind lists go through the same query, so one field filters
    // the whole block. The query lives in GlobalStates rather than on the
    // page: accepting a keybind in search clears it before the deep link
    // opens this page, otherwise the target row could be filtered out.

    readonly property bool keybindFiltering:
        String(GlobalStates.keybindFilter ?? "").trim() !== ""

    readonly property var visibleManaged: CF.StringUtils.filterByQuery(
        ManagedKeybinds.editableEntries, GlobalStates.keybindFilter,
        ["name", "category", "combo", "command"])

    readonly property var visibleShell: CF.StringUtils.filterByQuery(
        HyprlandKeybinds.shellActions, GlobalStates.keybindFilter,
        ["description", "action", "combos"])

    // A category name matches every bind below it; otherwise match the bind's
    // own text and its combination. The extra searchCombo field is only used
    // by the filter — the row still receives the original bind object.
    function filterOtherSections(sections, query) {
        const out = [];
        const tokens = String(query ?? "").trim().toLowerCase().split(/\s+/).filter(t => t !== "");
        for (const section of (sections ?? [])) {
            const category = String(section?.name ?? "").toLowerCase();
            const categoryMatches = tokens.length > 0 && tokens.every(t => category.includes(t));
            const binds = categoryMatches
                ? (section?.binds ?? [])
                : CF.StringUtils.filterByQuery(
                    (section?.binds ?? []).map(bind => Object.assign({}, bind, {
                        searchCombo: HyprlandKeybinds.comboOf(bind)
                    })),
                    query,
                    ["comment", "searchCombo", "action", "key", "mods"]);
            if (binds.length > 0) out.push({ name: section?.name ?? "", binds: binds });
        }
        return out;
    }

    // The arguments are read here so QML tracks both services and the query.
    readonly property var visibleOtherSections: page.filterOtherSections(
        HyprlandKeybinds.otherSections, GlobalStates.keybindFilter)

    readonly property int keybindMatchCount: page.visibleManaged.length
        + page.visibleShell.length + page.visibleOtherSections.length

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
        // There is now one switch: choosing a colour by hand *is* the off side
        // of "Match the wallpaper colour", so the toggle reflects it instead of
        // two sources fighting over the panel.
        if (Config.options.light.keyboardColor.followWallpaper)
            Config.options.light.keyboardColor.followWallpaper = false;
        // "Off" is a real panel state rather than merely a black colour: the
        // helper has a command for it, and it is visible in probe() as off:true.
        if (hex === "#000000")
            Brightness.kbMonitor.switchOff();
        else
            Brightness.kbMonitor.setColorHex(hex);
    }

    // While a drag is in progress only the hardware is told -- Brightness
    // debounces the writes, so a whole gesture costs one EC transaction per
    // 120ms instead of one per frame. config.json is written only when the
    // gesture ends, so a drag cannot rewrite the file hundreds of times.

    Component.onCompleted: {
        // Re-sync on open rather than only at startup. When following the
        // wallpaper, the preview is seeded with the colour matugen derived from
        // it and the state is pushed again -- so opening this page is itself a
        // check that wallpaper following is alive, without having to change the
        // wallpaper first. Otherwise the hardware colour wins, then the stored
        // choice.
        if (Config.options.light.keyboardColor.followWallpaper) {
            const fromWall = Brightness.kbMonitor.normalizeHex(Brightness.kbMonitor.followColour());
            currentColor = fromWall !== "" ? fromWall : "#FFFFFF";
            Brightness.kbMonitor.applyFromConfig();
        } else {
            const applied = Brightness.kbMonitor?.color;
            const stored = Config.options.light.keyboardColor.color;
            currentColor = applied || (stored && stored !== "" ? stored : "#FFFFFF");
        }
    }

    property string currentColor: "#FFFFFF"
    property real hue: 0
    property real saturation: 100
    property real value: 100

    // Update currentColor when HSV changes
    // Built channel by channel rather than assigned straight from Qt.hsva():
    // this Qt build's colour objects stringify reliably, but reading h/s/v back
    // from them does not, and the picker needs one canonical hex string.
    function hsvHex(h: real, s: real, v: real): string {
        const c = Qt.hsva(Math.max(0, Math.min(1, h / 360)),
                          Math.max(0, Math.min(1, s / 100)),
                          Math.max(0, Math.min(1, v / 100)), 1);
        const two = x => Math.round(Math.max(0, Math.min(1, x)) * 255)
            .toString(16).padStart(2, "0");
        return "#" + two(c.r) + two(c.g) + two(c.b);
    }
    // An HTML-style palette: every cell is one colour you can see and press,
    // laid out hue by hue across and lightness down -- no separate sliders, so
    // what is on screen is exactly what can be picked.
    readonly property int paletteCols: 16
    readonly property int paletteRows: 8
    function paletteCell(i: int): var {
        const c = i % paletteCols
        const r = Math.floor(i / paletteCols)
        const h = c / paletteCols
        const t = r / (paletteRows - 1)
        let s, v
        if (t <= 0.5) {          // light -> vivid: lift saturation, full value
            s = 0.2 + 0.8 * (t / 0.5)
            v = 1
        } else {                 // vivid -> dark: keep saturation, drop value
            s = 1
            v = 1 - 0.88 * ((t - 0.5) / 0.5)
        }
        return { h: h, s: s, v: v, hex: hsvHex(h * 360, s * 100, v * 100) }
    }
    property var hsvColor: hsvHex(hue, saturation, value)

    onHueChanged: currentColor = hsvColor
    onSaturationChanged: currentColor = hsvColor
    onValueChanged: currentColor = hsvColor

    // When currentColor changes externally (a swatch, the hex field), follow it.
    // Qt.color() exposes r/g/b here but *not* h/s/v -- reading them yielded
    // undefined and turned hue into NaN, which is what made the sliders die.
    // The HSV axes are therefore derived from the channels, and only material
    // differences are applied so a slider drag cannot feed back on itself.
    onCurrentColorChanged: {
        const c = Qt.color(currentColor);
        const r = c.r, g = c.g, b = c.b;
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
        let h = 0;
        if (d > 0) {
            if (mx === r) h = ((g - b) / d + 6) % 6;
            else if (mx === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h *= 60;
        }
        const s = mx === 0 ? 0 : d / mx * 100;
        const v = mx * 100;
        if (!isFinite(h) || !isFinite(s) || !isFinite(v)) return;
        if (Math.abs(h - hue) > 1) hue = h;
        if (Math.abs(s - saturation) > 1) saturation = s;
        if (Math.abs(v - value) > 1) value = v;
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

    // Saturation/value square, in the shape every HTML colour picker uses:
    // horizontal axis is saturation, vertical axis is value. Both are 0..100.
    // One square holds every colour: the whole hue range runs top to bottom and
    // saturation runs left to right (white at the far left). This replaces the
    // saturation/value square plus the separate hue strip with a single control.
    // Hue strip, 0..360 left to right.
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
        if (page.capturing === "") {
            // Escape closes the form first; only the next press closes the
            // panel, so one key never throws away the draft.
            if (page.formOpen && event.key === Qt.Key_Escape) {
                page.closeForm();
                return true;
            }
            return false;
        }

        if (event.key === Qt.Key_Escape) {
            const formCapture = page.capturing === "form";
            // Cancel the capture, but let the press travel on: the panel
            // closes on Escape as well. The form capture only cancels
            // itself — the draft below is still open.
            page.stopCapture();
            return formCapture;
        }

        const combo = CF.StringUtils.keyEventToCombo(event);
        if (combo === "") {
            // A modifier on its own, or a key Hyprland would not know.
            // It is deliberately not accepted: swallowing it would eat the
            // modifier of the combination that follows.
            return false;
        }

        if (page.capturing === "form") {
            // The form takes the combination instead of writing an
            // override: it belongs to the draft until Save.
            console.log("[kbd] form capture: " + combo);
            page.formCombo = combo;
            page.formError = "";
            page.stopCapture();
            return true;
        }

        HyprlandBindOverrides.setOverride(page.capturing, combo);
        page.stopCapture();
        return true;
    }

    // ------------------------------------------------------
    // Keybind manager form
    // ------------------------------------------------------
    // The draft of the create/edit form. It lives on the page, not inside
    // the section, because the capture handler above needs it and because
    // the form itself only exists while formOpen is true: the Loader
    // destroys it on close, so every open starts from these values with
    // fresh field bindings.
    property bool formOpen: false
    property string formMode: "create"
    property string formEditId: ""
    onFormOpenChanged: console.log("[kbd] formOpen=" + formOpen
        + " mode=" + formMode + " capturing=" + JSON.stringify(capturing))
    // The combo the entry is written with in the file. It differs from
    // formCombo while an override moves the bind, and it is what the
    // entry's own id in the conflict index is built from.
    property string formOriginalCombo: ""
    property string formName: ""
    property string formCategory: ""
    property string formCommand: ""
    property string formCombo: ""
    property string formError: ""

    function openCreateForm() {
        page.stopCapture();
        page.formMode = "create";
        page.formEditId = "";
        page.formOriginalCombo = "";
        page.formName = "";
        page.formCategory = "";
        page.formCommand = "";
        page.formCombo = "";
        page.formError = "";
        page.formOpen = true;
    }

    function openEditForm(entry) {
        page.stopCapture();
        page.formMode = "edit";
        page.formEditId = entry.id;
        page.formOriginalCombo = entry.combo;
        page.formName = entry.name;
        page.formCategory = entry.category;
        page.formCommand = entry.command;
        // Show what the bind does right now: an override written through
        // the other-bind rows moves it, and the form must not display a key
        // the compositor does not actually listen for.
        page.formCombo = HyprlandBindOverrides.comboFor(
            "bind_" + entry.combo.replace(/[^A-Za-z0-9_]/g, "_"), entry.combo);
        page.formError = "";
        page.formOpen = true;
    }

    function closeForm() {
        page.stopCapture();
        page.formOpen = false;
        page.formError = "";
    }

    // The id of the entry itself in HyprlandKeybinds' conflict index, so
    // the status line does not report the bind as its own conflict. The id
    // is built from the file combo, the same way a plain bind row builds it.
    function formSelfId() {
        if (page.formMode !== "edit" || page.formOriginalCombo === "") return "";
        return "custom\u0000bind_" + page.formOriginalCombo.replace(/[^A-Za-z0-9_]/g, "_");
    }

    // Validation and service failures are codes, not sentences: the code
    // stays testable and this is the one place that translates them.
    function formErrorMessage(code) {
        switch (code) {
        case "empty-name": return Translation.tr("Give the keybind a name.");
        case "quote-name": return Translation.tr("The name cannot contain a double quote.");
        case "newline-name": return Translation.tr("The name must be on one line.");
        case "empty-command": return Translation.tr("Enter an app or command to run.");
        case "newline-command": return Translation.tr("The command must be on one line.");
        case "newline-category": return Translation.tr("The category must be on one line.");
        case "empty-combo": return Translation.tr("Press a key combination first.");
        case "not-loaded": return Translation.tr("The keybind file has not loaded yet. Try again.");
        case "not-found": return Translation.tr("That keybind is no longer in the file.");
        default: return Translation.tr("The keybind could not be saved.");
        }
    }

    function saveForm() {
        const entry = {
            name: page.formName.trim(),
            category: page.formCategory.trim(),
            command: page.formCommand.trim(),
            combo: page.formCombo
        };
        console.log("[kbd] saveForm mode=" + page.formMode
            + " name=" + JSON.stringify(entry.name)
            + " combo=" + JSON.stringify(entry.combo)
            + " command=" + JSON.stringify(entry.command)
            + " category=" + JSON.stringify(entry.category));
        const error = ManagedKeybinds.validate(entry);
        if (error !== "") {
            console.error("[kbd] saveForm validate: " + error);
            page.formError = page.formErrorMessage(error);
            return;
        }
        const result = page.formMode === "edit"
            ? ManagedKeybinds.update(page.formEditId, entry)
            : ManagedKeybinds.create(entry);
        if (!result.ok) {
            console.error("[kbd] saveForm service: " + result.error);
            page.formError = page.formErrorMessage(result.error);
            return;
        }
        console.log("[kbd] saveForm ok, closing");
        page.closeForm();
    }

    function deleteFormEntry() {
        if (page.formMode !== "edit") return;
        const result = ManagedKeybinds.remove(page.formEditId);
        if (!result.ok) {
            page.formError = page.formErrorMessage(result.error);
            return;
        }
        page.closeForm();
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

                // The picker, in the shape people already know: a saturation/
                // value square over a hue strip, the way an HTML colour picker
                // is laid out. It applies as you drag.
                // The palette itself: one block of visible colours, clicked to
                // be applied. Hue runs across, lightness down, so both the
                // saturation and the darkness of a colour are reachable without
                // a slider beside it.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 700
                    columns: page.paletteCols
                    columnSpacing: 3
                    rowSpacing: 3
                    visible: Brightness.kbMonitor.available

                    Repeater {
                        model: page.paletteCols * page.paletteRows
                        delegate: Rectangle {
                            required property int index
                            readonly property var cell: page.paletteCell(index)
                            readonly property bool isSelected:
                                page.currentColor.toLowerCase() === cell.hex

                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            // verysmall (8) rather than small (12): at ~40px a
                            // cell would otherwise read as a pill, not a swatch.
                            radius: Appearance.rounding.verysmall
                            color: cell.hex
                            border.width: isSelected ? 2 : 1
                            border.color: isSelected
                                ? Appearance.colors.colOnSurface
                                : Appearance.colors.colOutline

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    page.hue = cell.h * 360
                                    page.saturation = cell.s * 100
                                    page.value = cell.v * 100
                                    page.pickColour(cell.hex)
                                }
                            }
                        }
                    }
                }

                // The panel's own level. Distinct from anything in the palette
                // above: this is written to the hardware and scales all three
                // channels together, so it survives a colour change.
                SliderCard {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 700
                    visible: Brightness.kbMonitor.available
                    title: Translation.tr("Keyboard brightness")
                    value: Brightness.kbMonitor.brightnessPercent
                    from: 0
                    to: 100
                    step: 5
                    onValueEdited: Brightness.kbMonitor.set(newValue)
                }

                // The panel does exactly two things with colour: a static level
                // per channel, or the firmware's own cycling effect.
                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: Brightness.kbMonitor.available
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Rainbow cycling")
                    checked: Brightness.kbMonitor.rainbow
                    onCheckedChanged: Brightness.kbMonitor.setMode(checked ? "rainbow" : "static")
                }

                // The panel has 51 steps per channel, so some picks land a shade
                // away from what was chosen. Shown only when that actually
                // happens, as one quiet line -- a permanent notice box here just
                // filled the page.
                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 500
                    visible: Brightness.kbMonitor.available
                        && !Brightness.kbMonitor.rainbow
                        && Brightness.kbMonitor.color !== ""
                        && Brightness.kbMonitor.color.toLowerCase()
                            !== String(page.currentColor).toLowerCase()
                    text: Translation.tr("Panel shows %1").arg(Brightness.kbMonitor.color)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                // Say exactly what is missing: on this machine the qc71_laptop
                // driver never registers a lightbar LED (the BIOS reports the
                // capability bit as clear), so the only path is the helper.
                NoticeBox {
                    Layout.fillWidth: true
                    visible: !Brightness.kbMonitor.available
                    materialIcon: "memory"
                    text: Translation.tr("No keyboard backlight device was found. Run: cd scripts/keyboard-rgb && sudo ./setup-keyboard-rgb.sh - then reopen this page.")
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
                    buttonIcon: "wallpaper"
                    text: Translation.tr('Match the wallpaper colour')
                    checked: Config.options.light.keyboardColor.followWallpaper
                    onCheckedChanged: {
                        Config.options.light.keyboardColor.followWallpaper = checked;
                        if (checked) Brightness.kbMonitor.applyFromConfig();
                    }
                }

                // Which Appearance.colors role to follow. Still the theme's own
                // signal -- only the colour picked out of it changes. Plain
                // primary is pale by design (it sits on a UI surface), so the
                // active shade is offered as a deeper default.
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    visible: Config.options.light.keyboardColor.followWallpaper
                    text: Translation.tr("Accent role")
                    icon: "palette"
                    currentValue: Config.options.light.keyboardColor.role
                    options: [
                        { displayName: Translation.tr("Primary active"), icon: "contrast", value: "primaryActive" },
                        { displayName: Translation.tr("Primary"), icon: "palette", value: "primary" },
                        { displayName: Translation.tr("Secondary"), icon: "tonality", value: "secondary" },
                        { displayName: Translation.tr("Tertiary"), icon: "auto_awesome", value: "tertiary" }
                    ]
                    onSelected: v => {
                        if (Config.options.light.keyboardColor.role === v) return;
                        Config.options.light.keyboardColor.role = v;
                        Brightness.kbMonitor.applyFromConfig();
                    }
                }

            }
        }

        // The bind lists talk to Hyprland services; on any other
        // compositor the Loader stays inactive so they are never
        // created. The manager, the shell shortcuts and the compositor's own
        // binds are one block now, with a single filter over all of them.
        Loader {
            Layout.fillWidth: true
            active: WM.compositor === "hyprland"
            sourceComponent: Component {
                ContentSection {
                    icon: "keyboard"
                    title: Translation.tr("Keybinds")
                    hint: Translation.tr("Search, create and rebind keyboard shortcuts. New keybinds are written to ~/.config/hypr/custom/keybinds.lua.")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // One filter for the whole block, not per list. The
                        // query lives in GlobalStates so accepting a search
                        // result can clear it before the target row flashes.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: "search"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            ToolbarTextField {
                                id: keybindFilterField
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Search keybinds…")
                                text: GlobalStates.keybindFilter
                                onTextChanged: GlobalStates.keybindFilter = text

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape && text !== "") {
                                        text = "";
                                        event.accepted = true;
                                    }
                                }
                            }

                            IconToolbarButton {
                                visible: keybindFilterField.text !== ""
                                text: "close"
                                onClicked: {
                                    keybindFilterField.text = "";
                                    keybindFilterField.forceActiveFocus();
                                }
                                StyledToolTip {
                                    text: Translation.tr("Clear filter")
                                }
                            }
                        }

                        // ---- Panel-managed keybinds ---------------------------
                        // The form replaces the button and the list while it is
                        // open. The Loader destroys it on close, so every open
                        // starts from the draft with fresh field bindings — a
                        // typed-in TextField drops its binding and a surviving
                        // instance would show stale text.
                        //
                        // preferredHeight is pinned to the live item on purpose:
                        // after the item is destroyed the Loader keeps its last
                        // height, which is exactly the leftover space after
                        // Cancel/Save.
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight:
                                (active && item !== null && item !== undefined)
                                    ? item.implicitHeight : 0
                            active: page.formOpen
                            sourceComponent: Component {
                                KeybindForm {
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        RippleButton {
                            visible: !page.formOpen
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignLeft
                            buttonText: Translation.tr("New keybind")
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                            onClicked: page.openCreateForm()
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !page.formOpen && !page.keybindFiltering
                                && ManagedKeybinds.editableEntries.length === 0
                            text: Translation.tr("No keybinds created yet. Press New keybind to add one.")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                        }

                        ColumnLayout {
                            visible: !page.formOpen
                            Layout.fillWidth: true
                            spacing: 2
                            Repeater {
                                model: page.visibleManaged
                                delegate: ManagedRow {
                                    required property var modelData
                                    entry: modelData
                                }
                            }
                        }

                        // ---- Shell shortcuts ----------------------------------
                        StyledText {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            visible: page.visibleShell.length > 0
                            text: Translation.tr("Shell shortcuts")
                            font.pixelSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: !page.keybindFiltering && HyprlandKeybinds.shellActions.length === 0
                            text: Translation.tr("No keybinds found.")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Repeater {
                                model: page.visibleShell
                                delegate: ShortcutRow {
                                    required property var modelData
                                    actionData: modelData
                                    capturing: page.capturing === modelData.action
                                }
                            }
                        }

                        // ---- The compositor's own binds ------------------------
                        StyledText {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            visible: page.visibleOtherSections.length > 0
                            text: Translation.tr("Other keybinds")
                            font.pixelSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer1
                        }
                        Repeater {
                            model: page.visibleOtherSections
                            delegate: ColumnLayout {
                                id: sectionColumn
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: sectionColumn.modelData.name === "" ? Translation.tr("Uncategorized") : sectionColumn.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
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

                        StyledText {
                            Layout.fillWidth: true
                            visible: page.keybindFiltering && page.keybindMatchCount === 0
                            text: Translation.tr("No keybinds match")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
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

        // The search index builds this exact string; ContentPage.goTo() uses
        // `title` to find the row a search result points at.
        readonly property string title: KeybindLabels.shell(actionData)

        readonly property string defaultCombo: actionData?.combos?.[0] ?? ""
        readonly property string combo: HyprlandBindOverrides.comboFor(actionData?.action ?? "", shortcutRow.defaultCombo)
        readonly property var aliases: (actionData?.combos ?? []).slice(1)
        // Who else holds this combination right now, so a repeat is visible
        // before the user has to discover it by pressing the key. Counted
        // across the theme's and the user's keybind file; the row's own
        // action is left out.
        readonly property var repeats: HyprlandKeybinds.repeatUsers(shortcutRow.combo, shortcutRow.actionData?.action ?? "")

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
                    visible: !shortcutRow.capturing && shortcutRow.repeats.length > 0
                    text: page.repeatSentence(shortcutRow.repeats)
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
    // the next reload. The wrapper skips shell shortcuts, which is why
    // this bind and a shortcut can share a key without moving together —
    // the yellow line still shows the share, because both dispatches run.
    //
    // The layout is the shortcut row's: description on the left in the same
    // size, key caps after it, the edit affordance and the reset last.
    component OtherBindRow: Rectangle {
        id: otherBindRow
        required property var bindData

        // Deep-link target; the index uses KeybindLabels.other() with the
        // same combo so the two strings are identical.
        readonly property string title: KeybindLabels.other(bindData, HyprlandKeybinds.comboOf(bindData))

        readonly property string originalCombo: HyprlandKeybinds.comboOf(bindData)
        readonly property string overrideId: "bind_" + otherBindRow.originalCombo.replace(/[^A-Za-z0-9_]/g, "_")
        readonly property string combo: HyprlandBindOverrides.comboFor(otherBindRow.overrideId, otherBindRow.originalCombo)
        readonly property bool overridden: HyprlandBindOverrides.isOverridden(otherBindRow.overrideId)
        readonly property bool capturing: page.capturing === otherBindRow.overrideId
        // Same combination, other holder: the keybind files are counted
        // per file, so the row excludes itself by file and id and still
        // sees the twin written in the other config file.
        readonly property var repeats: HyprlandKeybinds.repeatUsers(
            otherBindRow.combo,
            (otherBindRow.bindData?.file ?? "main") + "\u0000" + otherBindRow.overrideId)

        Layout.fillWidth: true
        implicitHeight: otherBindRowLayout.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal
        border.width: otherBindRow.capturing ? 1 : 0
        border.color: Appearance.colors.colPrimary

        RowLayout {
            id: otherBindRowLayout
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: (otherBindRow.bindData.comment ?? "") !== ""
                        ? otherBindRow.bindData.comment
                        : otherBindRow.originalCombo
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                // Yellow under the row: who else is on this combination.
                StyledText {
                    Layout.fillWidth: true
                    visible: !otherBindRow.capturing && otherBindRow.repeats.length > 0
                    text: page.repeatSentence(otherBindRow.repeats)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: page.conflictColor
                    wrapMode: Text.Wrap
                }
            }

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

    // A keybind the panel owns: name, group, the keys as word caps and the
    // conflict line, with edit and delete at the right. Edit fills the form
    // above; the caps are clickable for the same thing.
    component ManagedRow: Rectangle {
        id: managedRow
        required property var entry

        // Deep-link target; kept in sync with SettingsSearchIndex by the
        // shared KeybindLabels helper.
        readonly property string title: KeybindLabels.managed(entry)

        readonly property string fileCombo: entry.combo
        readonly property string overrideId: "bind_" + managedRow.fileCombo.replace(/[^A-Za-z0-9_]/g, "_")
        // What the bind does right now: another row's override may have
        // moved it off the combo written in the file.
        readonly property string combo: HyprlandBindOverrides.comboFor(managedRow.overrideId, managedRow.fileCombo)
        // The id the conflict index gives a plain bind in the custom file,
        // so the row never reports itself as a conflict.
        readonly property var repeats: HyprlandKeybinds.repeatUsers(
            managedRow.combo, "custom\u0000" + managedRow.overrideId)

        Layout.fillWidth: true
        implicitHeight: managedRowLayout.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        RowLayout {
            id: managedRowLayout
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: managedRow.entry.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: managedRow.entry.category !== ""
                    text: managedRow.entry.category
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                // Yellow under the row: who else is on this combination.
                StyledText {
                    Layout.fillWidth: true
                    visible: managedRow.repeats.length > 0
                    text: page.repeatSentence(managedRow.repeats)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: page.conflictColor
                    wrapMode: Text.Wrap
                }
            }

            // The keys as word caps; clicking them edits the keybind.
            Item {
                implicitWidth: managedCapsRow.implicitWidth
                implicitHeight: managedCapsRow.implicitHeight

                Row {
                    id: managedCapsRow
                    spacing: 4

                    Repeater {
                        model: CF.StringUtils.keyLabels(managedRow.combo)
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
                    onClicked: page.openEditForm(managedRow.entry)
                }
            }

            // A visible edit affordance, the same one the other rows have.
            Item {
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
                    onClicked: page.openEditForm(managedRow.entry)
                }
            }

            // Delete removes the line from custom/keybinds.lua and reloads.
            Item {
                implicitWidth: 20
                implicitHeight: 20

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colError
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ManagedKeybinds.remove(managedRow.entry.id)
                }
            }
        }
    }

    // The create/edit form for one managed keybind. It lives inside the
    // section's Loader, so closing the form destroys it: every open starts
    // from the draft with fresh field bindings — a typed-in TextField drops
    // its binding, and a surviving instance would show stale text.
    component KeybindForm: Rectangle {
        id: form

        // Who else holds the keys in the draft. The entry being edited is
        // left out through its file combo, so it never reports itself.
        readonly property var repeats: page.formCombo === ""
            ? [] : HyprlandKeybinds.repeatUsers(page.formCombo, page.formSelfId())

        // One desktop entry's argv as a shell command: parts that could be
        // misread are single-quoted, everything else passes through so the
        // usual case stays readable.
        function appCommand(argv) {
            return argv
                .filter(part => part !== "" && !/^%[a-zA-Z]$/.test(part))
                .map(part => /^[\w@%+=:,.\/~-]+$/.test(part)
                    ? part
                    : "'" + CF.StringUtils.shellSingleQuoteEscape(part) + "'")
                .join(" ");
        }

        // The apps the picker offers, sorted by name, behind a neutral
        // "pick" row that keeps the combo from claiming a selection the
        // command field does not have.
        readonly property var appOptions: {
            const apps = AppSearch.list
                .map(app => ({ displayName: app.name, value: form.appCommand(app.command ?? []) }))
                .filter(app => app.displayName !== "" && app.value !== "");
            apps.sort((a, b) => a.displayName.localeCompare(b.displayName));
            return [{ displayName: Translation.tr("Pick an app"), value: "" }].concat(apps);
        }

        Layout.fillWidth: true
        implicitHeight: formColumn.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        ColumnLayout {
            id: formColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            StyledText {
                Layout.fillWidth: true
                text: page.formMode === "edit"
                    ? Translation.tr("Edit keybind")
                    : Translation.tr("New keybind")
                font.pixelSize: Appearance.font.pixelSize.title
                color: Appearance.colors.colOnLayer1
            }

            // ---- Name ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Name")
                    text: page.formName
                    onTextChanged: page.formName = text
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("How the keybind is described in the cheatsheet and in this list.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }

            // ---- Category ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialTextField {
                    id: categoryField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Category")
                    text: page.formCategory
                    onTextChanged: page.formCategory = text
                }

                // Existing groups as one-tap chips; picking one fills the
                // field above, a typed name simply joins the list next time.
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    options: HyprlandKeybinds.categories.map(category => ({
                        displayName: category === "" ? Translation.tr("Uncategorized") : category,
                        value: category
                    }))
                    currentValue: page.formCategory
                    onSelected: newValue => categoryField.text = newValue
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Groups the keybind in the cheatsheet, for example Apps. Pick a group above or type a new name.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }

            // ---- App or command ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialTextField {
                    id: commandField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("App or command")
                    text: page.formCommand
                    onTextChanged: page.formCommand = text
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "apps"
                    text: Translation.tr("App")
                    searchable: true
                    model: form.appOptions
                    currentValue: page.formCommand
                    onSelected: newValue => {
                        if (newValue !== "") commandField.text = newValue;
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("The program that runs when the keys are pressed, for example kitty or xdg-open ~/Documents.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }

            // ---- Keys ----
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    id: keysBox
                    Layout.fillWidth: true
                    implicitHeight: keysBoxColumn.implicitHeight + 24
                    color: Appearance.colors.colLayer2
                    radius: Appearance.rounding.normal
                    border.width: page.capturing === "form" ? 1 : 0
                    border.color: Appearance.colors.colPrimary

                    ColumnLayout {
                        id: keysBoxColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6

                        Row {
                            spacing: 4
                            visible: page.formCombo !== "" && page.capturing !== "form"

                            Repeater {
                                model: CF.StringUtils.keyLabels(page.formCombo)
                                delegate: KeyboardKey {
                                    required property var modelData
                                    key: modelData
                                    pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }

                        StyledText {
                            visible: page.formCombo === "" || page.capturing === "form"
                            text: Translation.tr("Press a key combination...")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: page.capturing === "form"
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                        }

                        // Green light: the draft combination is free.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: page.formCombo !== "" && page.capturing !== "form"
                                && form.repeats.length === 0

                            MaterialSymbol {
                                text: "check_circle"
                                iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: Translation.tr("Available")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }

                        // Yellow: the same combination is bound elsewhere.
                        StyledText {
                            Layout.fillWidth: true
                            visible: page.formCombo !== "" && page.capturing !== "form"
                                && form.repeats.length > 0
                            text: page.repeatSentence(form.repeats)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: page.conflictColor
                            wrapMode: Text.Wrap
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.startCapture("form")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Click the box, then press the key combination you want, for example Super + Ctrl + K.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }

            // Validation and save failures, verbatim from the store codes.
            NoticeBox {
                Layout.fillWidth: true
                visible: page.formError !== ""
                materialIcon: "error"
                text: page.formError
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                DialogButton {
                    visible: page.formMode === "edit"
                    buttonText: Translation.tr("Delete")
                    colText: Appearance.colors.colError
                    onClicked: page.deleteFormEntry()
                }

                Item {
                    Layout.fillWidth: true
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: page.closeForm()
                }

                DialogButton {
                    buttonText: Translation.tr("Save")
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colText: Appearance.colors.colOnPrimaryContainer
                    onClicked: page.saveForm()
                }
            }
        }
    }
}
