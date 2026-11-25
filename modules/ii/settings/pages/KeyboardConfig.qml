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
import "../../../common/functions/KeybindConflicts.js" as KeybindConflicts
import "../../../common/functions/SettingsEscape.js" as SettingsEscape

/**
 * Keyboard backlight colour, shell shortcuts and the other keybinds.
 *
 * The colour picker drives the system keyboard backlight helper; the
 * shortcut list comes from the same JSON catalog + user overlay the
 * cheatsheet uses, so it always matches the binds Hyprland loaded. A new
 * keybind is written only to ~/.config/hypr/custom/keybind-overlay.json;
 * the generator then rebuilds the Lua files and Hyprland is reloaded.
 * The keybind sections only exist on Hyprland.
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

    readonly property var visibleManaged: CF.StringUtils.filterByQueryWithCombos(
        ManagedKeybinds.editableEntries, GlobalStates.keybindFilter,
        ["name", "category", "command"], ["combo"])

    readonly property var visibleShell: CF.StringUtils.filterByQueryWithCombos(
        HyprlandKeybinds.shellActions, GlobalStates.keybindFilter,
        ["description", "action"], ["combos"])

    // Series members get one grouped row below, so they are left out of the
    // flat "Other keybinds" list. Every other bind renders exactly as before.
    function filterOtherSections(sections, query) {
        const out = [];
        const tokens = String(query ?? "").trim().toLowerCase().split(/\s+/).filter(t => t !== "");
        for (const section of (sections ?? [])) {
            const category = String(section?.name ?? "").toLowerCase();
            const categoryMatches = tokens.length > 0 && tokens.every(t => category.includes(t));
            const plain = (section?.binds ?? []).filter(
                bind => String(bind?.seriesId ?? "") === "");
            const binds = categoryMatches
                ? plain
                : CF.StringUtils.filterByQueryWithCombos(
                    plain.map(bind => Object.assign({}, bind, {
                        searchCombo: HyprlandKeybinds.comboOf(bind)
                    })),
                    query,
                    ["comment", "action", "key", "mods"],
                    ["searchCombo"]);
            if (binds.length > 0) out.push({ name: section?.name ?? "", binds: binds });
        }
        return out;
    }

    // The arguments are read here so QML tracks both services and the query.
    readonly property var visibleSeries: CF.StringUtils.filterByQuery(
        HyprlandKeybinds.series, GlobalStates.keybindFilter,
        ["seriesLabel", "mods", "memberLabels"])

    readonly property var visibleOtherSections: page.filterOtherSections(
        HyprlandKeybinds.otherSections, GlobalStates.keybindFilter)

    readonly property int keybindMatchCount: page.visibleManaged.length
        + page.visibleShell.length + page.visibleSeries.length
        + page.visibleOtherSections.length

    // ------------------------------------------------------
    // Deleting shell / compositor binds (recoverable)
    // ------------------------------------------------------
    // The delete service may only write the two keybind files it owns. Mirror
    // those paths here so the delete affordance is hidden for a bind that came
    // from anywhere else — the service would refuse it anyway.
    readonly property var deletablePaths: [
        CF.FileUtils.trimFileProtocol(DisabledKeybinds.defaultKeybindConfigPath),
        CF.FileUtils.trimFileProtocol(DisabledKeybinds.userKeybindConfigPath)
    ]

    function canDeleteBind(bind) {
        if (bind === undefined || bind === null) return false;
        const path = CF.FileUtils.trimFileProtocol(String(bind.sourcePath ?? ""));
        return path !== "" && page.deletablePaths.indexOf(path) !== -1;
    }

    function canDeleteBinds(binds) {
        const list = binds ?? [];
        return list.length > 0 && list.every(bind => page.canDeleteBind(bind));
    }

    // ------------------------------------------------------
    // Conflicting key combinations
    // ------------------------------------------------------
    // A combo held by two or more binds dispatches all of them when pressed.
    // The analyzer returns plain {combo, holders} groups, each holder reduced
    // to {id, label, file}. One fix moves exactly one holder to a free combo,
    // through one service — a group with several others gets one Move action
    // per holder, so each click is one write and one reload.
    readonly property var conflictGroups: KeybindConflicts.groupsFrom(
        HyprlandKeybinds.repeatIndex, HyprlandKeybinds.aliasIndex)

    // A short confirmation after a fix. The group itself usually disappears
    // on the reload that follows, so the flag keeps the message visible.
    property bool conflictResolved: false

    Timer {
        id: conflictResolvedTimer
        interval: 4000
        onTriggered: page.conflictResolved = false
    }

    // The group projection drops `bind` on purpose, so recover the real holder
    // (which carries it) from the index before asking which service owns it.
    function originalConflictHolder(group, holder) {
        const holders = HyprlandKeybinds.repeatIndex.get(group.combo) ?? [];
        // Two plain binds in the same file share `id`, so match by uid when
        // the holder has one. Otherwise (shell actions) id is the identity.
        const wanted = KeybindConflicts.identityOf(holder);
        return holders.find(candidate => KeybindConflicts.identityOf(candidate) === wanted) ?? holder;
    }

    function moveConflictHolder(group, holder, combo) {
        if (String(combo ?? "") === "") return false;
        const original = page.originalConflictHolder(group, holder);
        const catalogId = String(original?.bind?.id ?? "");
        // Without a catalog id there is no key the generator can write an
        // override for; refusing is better than writing a dead override file.
        if (catalogId === "") {
            page.captureError = page.formErrorMessage("unknown-path");
            return false;
        }
        if (ManagedKeybinds.isRawBind(catalogId)) {
            page.captureError = page.formErrorMessage("raw-combo");
            return false;
        }

        // A conflict fix is a rebind like any other, so it goes through the
        // same overlay service. `fixHolder` uses `overrideId` for a plain
        // bind, which is why it is set to the catalog id here.
        const fix = KeybindConflicts.fixHolder(
            Object.assign({}, original, { overrideId: catalogId }), combo,
            bind => ManagedKeybinds.entryForSource(bind),
            ManagedKeybinds,
            ManagedKeybinds);
        if (!fix.ok) {
            page.captureError = page.formErrorMessage(fix.error);
            return false;
        }
        page.conflictResolved = true;
        conflictResolvedTimer.restart();
        return true;
    }

    // Remove one combination from a shell action without touching its other
    // combos. The delete id is per combo, so Deleted keybinds can restore
    // exactly this one.
    function deleteAliasCombo(actionData, combo) {
        const action = String(actionData?.action ?? "");
        const binds = (actionData?.binds ?? []).filter(
            bind => HyprlandKeybinds.comboOf(bind) === combo);
        if (action === "" || binds.length === 0) {
            page.captureError = page.formErrorMessage("unknown-path");
            return false;
        }
        if (binds.some(bind => bind?.raw === true)) {
            page.captureError = page.formErrorMessage("raw-combo");
            return false;
        }
        const label = String(actionData?.description ?? "") !== ""
            ? actionData.description
            : action;
        const result = DisabledKeybinds.disableBinds(
            "shell:" + action + ":" + combo, label, binds);
        if (!result.ok) {
            page.captureError = page.formErrorMessage(result.error);
            return false;
        }
        return true;
    }

    // "Use only this one": every other holder on this group is removed, the
    // keeper stays. Alias groups remove a single action combo; duplicate
    // combos remove whichever service owns each other holder.
    function removeConflictOthers(group, keeperId) {
        const plan = KeybindConflicts.removalPlan(group, keeperId);
        if (plan.keeper === null || plan.keeper === undefined) {
            page.captureError = page.formErrorMessage("unknown-path");
            return false;
        }

        let ok = true;
        for (const holder of plan.remove) {
            if (group?.kind === "alias") {
                const actionData = HyprlandKeybinds.shellActions.find(
                    entry => entry.action === group.action);
                if (!page.deleteAliasCombo(actionData, holder.combo)) ok = false;
                continue;
            }

            const original = page.originalConflictHolder(group, holder);
            const bind = original?.bind ?? null;
            const managedEntry = ManagedKeybinds.entryForSource(bind);
            if (managedEntry !== null && managedEntry !== undefined) {
                const result = ManagedKeybinds.remove(managedEntry.id);
                if (!result.ok) {
                    page.captureError = page.formErrorMessage(result.error);
                    ok = false;
                }
                continue;
            }

            const action = String(bind?.action ?? "");
            if (action !== "") {
                const actionData = HyprlandKeybinds.shellActions.find(entry => entry.action === action);
                if (!page.deleteAliasCombo(actionData, HyprlandKeybinds.comboOf(bind))) ok = false;
                continue;
            }

            const catalogId = String(bind?.id ?? "");
            if (catalogId === "" || ManagedKeybinds.isRawBind(catalogId)) {
                page.captureError = page.formErrorMessage("raw-combo");
                ok = false;
                continue;
            }

            const result = DisabledKeybinds.disableBinds(
                "bind:" + String(original?.file ?? "") + ":" + String(bind?.line ?? 0),
                holder.label, [bind]);
            if (!result.ok) {
                page.captureError = page.formErrorMessage(result.error);
                ok = false;
            }
        }

        if (ok) {
            page.conflictResolved = true;
            conflictResolvedTimer.restart();
        }
        return ok;
    }

    // Move every non-keeper holder onto one of the suggested free combos.
    // Unlike pressing Move once per row, this is one action for the group;
    // it still reports success only when every write succeeded.
    function applyConflictOffers(group, keeperId) {
        if (group?.kind === "alias") return false;
        const choice = KeybindConflicts.chooseKeeper(
            group, keeperId ?? KeybindConflicts.identityOf(group?.holders?.[0]));
        const suggestions = KeybindConflicts.freeCombos(
            HyprlandKeybinds.allUsedCombos, choice.others.length, group?.combo ?? "");
        if (suggestions.length < choice.others.length) {
            page.captureError = Translation.tr("No free combination found for every binding.");
            return false;
        }

        page.conflictResolved = false;
        let ok = true;
        for (let i = 0; i < choice.others.length; ++i) {
            if (!page.moveConflictHolder(group, choice.others[i], suggestions[i])) ok = false;
        }
        if (!ok) page.conflictResolved = false;
        return ok;
    }

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
    // The frozen catalog ids behind the row being captured. A default bind is
    // rebound by writing overrides[id] in the JSON overlay; the old
    // keybind_overrides.conf was never read by the generator, so it could
    // show a combo Hyprland did not actually listen for.
    property var captureCatalogIds: []
    // Set when a row cannot be edited here (raw Lua bind) or a write failed.
    property string captureError: ""

    function startCapture(captureKey, catalogIds, raw) {
        if (raw === true) {
            page.captureError = Translation.tr("This keybind is raw Lua; its keys cannot be changed in Settings.");
            return;
        }
        page.captureError = "";
        page.captureCatalogIds = (catalogIds ?? []).map(id => String(id ?? "")).filter(id => id !== "");
        page.capturing = captureKey;
        // The window inhibitor reports `active` back; until then the hint
        // tells the user the compositor may still own the chord.
        GlobalStates.keybindCaptureArmed = true;
        GlobalStates.keybindCaptureInhibited = false;
        captureTimeout.restart();
        Qt.callLater(() => page.forceActiveFocus());
    }

    // Releasing the capture is always done here, never only by pressing a
    // key: a capture that stays alive keeps every key press inside the
    // settings panel, so Escape and plain letters never reach the app.
    function stopCapture() {
        GlobalStates.keybindCaptureArmed = false;
        GlobalStates.keybindCaptureInhibited = false;
        if (page.capturing === "") return;
        page.capturing = "";
        page.captureCatalogIds = [];
        captureTimeout.stop();
    }

    // The typed fallback: parse "super+i" into the spelling the store uses
    // and take it as the draft, exactly as a captured press would.
    function applyTypedCombo() {
        const combo = CF.StringUtils.comboFromText(comboTextField.text);
        if (combo === "") return;
        page.formCombo = combo;
        page.formError = "";
        page.stopCapture();
    }

    // Leaving the page (or the window) must release the inhibitor, otherwise
    // the compositor stays without its shortcuts.
    Component.onDestruction: page.stopCapture()

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
            if (event.key === Qt.Key_Escape) {
                // Escape closes the edit form, but never the settings panel.
                const decision = SettingsEscape.decide({
                    source: "capture", formOpen: page.formOpen
                });
                if (decision.closeForm) page.closeForm();
                if (decision.accept) return true;
            }
            return false;
        }

        if (event.key === Qt.Key_Escape) {
            // Every active capture consumes Escape so the settings window
            // never sees it. The draft below stays open after cancellation.
            const decision = SettingsEscape.decide({
                source: "capture", capturing: true
            });
            if (decision.stopCapture) page.stopCapture();
            return decision.accept;
        }

        const combo = CF.StringUtils.keyEventToCombo(event);
        if (combo === "") {
            // A modifier on its own, or a key Hyprland would not know.
            // It is deliberately not accepted: swallowing it would eat the
            // modifier of the combination that follows.
            return false;
        }

        if (page.capturing === "search") {
            // A pressed combination becomes the filter text, in the same
            // spelling the rows show.
            GlobalStates.keybindFilter = combo;
            page.stopCapture();
            return true;
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

        if (page.captureCatalogIds.length > 0) {
            // One save per captured key. A loop shortcut owns several catalog
            // binds; all of their overrides are written through the same
            // service so the cheatsheet and the generated Lua stay in step.
            let firstError = "";
            for (const catalogId of page.captureCatalogIds) {
                const result = ManagedKeybinds.setOverride(catalogId, combo);
                if (!result.ok && firstError === "") firstError = result.error;
            }
            if (firstError !== "") page.captureError = page.formErrorMessage(firstError);
            page.stopCapture();
            return true;
        }

        // Only a row with no catalog id falls back to the legacy overrides
        // file; every bind from the catalog takes the overlay path above.
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
        page.captureError = "";
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
        page.captureError = "";
        page.formMode = "edit";
        page.formEditId = entry.id;
        page.formOriginalCombo = entry.combo;
        page.formName = entry.name;
        page.formCategory = entry.category;
        page.formCommand = entry.command;
        // The form edits an overlay add: `entry.combo` is the combo the
        // generator emits, including a combo moved by a conflict fix.
        page.formCombo = entry.combo;
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
        case "raw-combo": return Translation.tr("This keybind is raw Lua; its keys cannot be changed in Settings.");
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
                    hint: Translation.tr("Search, create and rebind keyboard shortcuts. New keybinds are written to ~/.config/hypr/custom/keybind-overlay.json.")

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

                            // Search by pressing the combination instead of
                            // typing it: the window inhibitor lets a chord
                            // the compositor owns reach this button.
                            IconToolbarButton {
                                visible: page.capturing !== "search"
                                text: "keyboard"
                                onClicked: page.startCapture("search")
                                StyledToolTip {
                                    text: Translation.tr("Search by key combination")
                                }
                            }

                            IconToolbarButton {
                                visible: page.capturing === "search"
                                text: "close"
                                onClicked: page.stopCapture()
                                StyledToolTip {
                                    text: Translation.tr("Stop searching by key combination")
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

                        // A refused rebind (raw Lua) or a failed overlay write
                        // is reported here instead of silently doing nothing.
                        StyledText {
                            Layout.fillWidth: true
                            visible: page.captureError !== ""
                            text: page.captureError
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: page.conflictColor
                            wrapMode: Text.Wrap
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

                        // ---- Keybind series ------------------------------------
                        // Raw multi-key groups (workspace switching, window
                        // moving, keypad zoom) get one logical row each. The
                        // member list is collapsed until asked for, and the
                        // modifier prefix / enabled state are one write for
                        // every bind in the series.
                        StyledText {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            visible: page.visibleSeries.length > 0
                            text: Translation.tr("Keybind series")
                            font.pixelSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer1
                        }
                        Repeater {
                            model: page.visibleSeries
                            delegate: SeriesRow {
                                required property var modelData
                                seriesData: modelData
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

        // One combination held by two or more binds fires all of them when
        // pressed. Hyprland-only like the bind lists it reads, and present
        // only while there is a repeat to resolve (plus a moment after a fix
        // so the result stays visible through the reload).
        Loader {
            Layout.fillWidth: true
            active: WM.compositor === "hyprland"
                && (page.conflictGroups.length > 0 || page.conflictResolved)
            sourceComponent: Component {
                ContentSection {
                    icon: "warning"
                    title: Translation.tr("Conflicts")
                    hint: Translation.tr("Key conflicts")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        StyledText {
                            Layout.fillWidth: true
                            visible: page.conflictResolved
                            text: Translation.tr("Conflicts resolved")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }

                        Repeater {
                            model: page.conflictGroups
                            delegate: ConflictGroupPanel { }
                        }
                    }
                }
            }
        }

        // Recoverable deletions are ids in the overlay's `disabled` array.
        // This section lists them so a delete can be undone by clearing that
        // id; a later overlay save cannot undo a delete. Like the keybind
        // block it is Hyprland-only, and it only exists while there is
        // something to restore.
        Loader {
            Layout.fillWidth: true
            active: WM.compositor === "hyprland" && DisabledKeybinds.disabled.length > 0
            sourceComponent: Component {
                ContentSection {
                    icon: "delete"
                    title: Translation.tr("Deleted keybinds")
                    hint: Translation.tr("A fresh install can restore deleted base keybinds")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: DisabledKeybinds.disabled
                            delegate: Rectangle {
                                id: deletedRow
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: deletedRowLayout.implicitHeight + 16
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.normal

                                RowLayout {
                                    id: deletedRowLayout
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            // A disable re-read from the overlay
                                            // has no persisted label; the service
                                            // falls back to the catalog id.
                                            text: (deletedRow.modelData.label ?? "") !== ""
                                                ? deletedRow.modelData.label
                                                : (deletedRow.modelData.id ?? "")
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: deletedRow.modelData.file ?? ""
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Item {
                                        id: restoreButton
                                        implicitWidth: 24
                                        implicitHeight: 24
                                        property bool hovered: restoreMouseArea.containsMouse
                                        Accessible.name: Translation.tr("Restore")
                                        Accessible.role: Accessible.Button

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "restart_alt"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: Appearance.colors.colSubtext
                                        }

                                        MouseArea {
                                            id: restoreMouseArea
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: DisabledKeybinds.restore(deletedRow.modelData.id)
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Restore")
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

    // One conflicted combination. The first holder is the default keeper, so
    // a panel always leaves at least one binding on the original key. Every
    // other holder gets its own Move action; a click writes exactly one fix.
    component ConflictGroupPanel: Rectangle {
        id: panel
        required property var modelData

        // uid for plain bind holders (two same-file binds on one combo share
        // an id), id for shell actions.
        property string keeperId: KeybindConflicts.identityOf(panel.modelData?.holders?.[0])
        readonly property var choice: KeybindConflicts.chooseKeeper(panel.modelData, panel.keeperId)
        readonly property var suggestions: KeybindConflicts.freeCombos(
            HyprlandKeybinds.allUsedCombos, 3, panel.modelData?.combo ?? "")

        Layout.fillWidth: true
        implicitHeight: panelContent.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal

        ColumnLayout {
            id: panelContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    // A raw bind's code:N reads as its catalog keyLabel here
                    // too; the conflict index itself still uses the raw combo.
                    model: CF.StringUtils.keyLabels(HyprlandKeybinds.displayCombo(
                        panel.modelData?.combo ?? "", panel.modelData?.holders?.[0]?.bind))
                    delegate: KeyboardKey {
                        required property var modelData
                        key: modelData
                        pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: panel.modelData?.kind === "alias"
                        ? Translation.tr("Bound to %1 combinations").arg(panel.modelData?.holders?.length ?? 0)
                        : Translation.tr("Used by %1 bindings").arg(panel.modelData?.holders?.length ?? 0)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            // Which binding keeps the original combination.
            Repeater {
                model: panel.modelData?.holders ?? []
                delegate: Rectangle {
                    id: keeperRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: keeperInner.implicitHeight + 12
                    color: "transparent"
                    border.width: panel.keeperId === KeybindConflicts.identityOf(keeperRow.modelData) ? 1 : 0
                    border.color: Appearance.colors.colPrimary
                    radius: Appearance.rounding.small

                    RowLayout {
                        id: keeperInner
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: keeperRow.modelData.label ?? ""
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: keeperRow.modelData.file ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            id: keepButton
                            implicitWidth: keepText.implicitWidth + 16
                            implicitHeight: keepText.implicitHeight + 12
                            Accessible.name: Translation.tr("Keep this one")
                            Accessible.role: Accessible.Button

                            StyledText {
                                id: keepText
                                anchors.centerIn: parent
                                text: Translation.tr("Keep this one")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: panel.keeperId === KeybindConflicts.identityOf(keeperRow.modelData)
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.keeperId = KeybindConflicts.identityOf(keeperRow.modelData)
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: panel.modelData?.kind !== "alias" && panel.choice.others.length > 0
                text: Translation.tr("Move other bindings to")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }

            // One row per non-keeper holder: pick a free combo, then Move.
            // An alias group has no free combo to move to here: its combos
            // are removed per combo instead.
            Repeater {
                model: panel.modelData?.kind === "alias" ? [] : panel.choice.others
                delegate: Rectangle {
                    id: moveRow
                    required property var modelData
                    property string selectedCombo: ""

                    Layout.fillWidth: true
                    implicitHeight: moveInner.implicitHeight + 12
                    color: "transparent"

                    ColumnLayout {
                        id: moveInner
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            text: moveRow.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: panel.suggestions
                                delegate: Rectangle {
                                    id: comboChip
                                    required property var modelData
                                    readonly property bool isSelected:
                                        moveRow.selectedCombo === comboChip.modelData

                                    implicitWidth: chipText.implicitWidth + 16
                                    implicitHeight: chipText.implicitHeight + 10
                                    radius: Appearance.rounding.small
                                    color: comboChip.isSelected
                                        ? Appearance.colors.colPrimaryContainer
                                        : Appearance.colors.colLayer1
                                    border.width: 1
                                    border.color: comboChip.isSelected
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colOutline

                                    StyledText {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: comboChip.modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: moveRow.selectedCombo = comboChip.modelData
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: panel.suggestions.length === 0
                            text: Translation.tr("No free combination found")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: page.conflictColor
                            wrapMode: Text.Wrap
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignLeft
                            enabled: moveRow.selectedCombo !== ""
                            buttonText: Translation.tr("Move")
                            buttonRadius: Appearance.rounding.full
                            onClicked: page.moveConflictHolder(
                                panel.modelData, moveRow.modelData, moveRow.selectedCombo)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: panel.choice.others.length > 0

                RippleButton {
                    buttonText: Translation.tr("Use only this one")
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.removeConflictOthers(panel.modelData, panel.keeperId)
                }

                RippleButton {
                    visible: panel.modelData?.kind !== "alias"
                    buttonText: Translation.tr("Apply suggested keys to all others")
                    buttonRadius: Appearance.rounding.full
                    onClicked: page.applyConflictOffers(panel.modelData, panel.keeperId)
                }
            }
        }
    }

    // An editable shell shortcut.
    component ShortcutRow: Rectangle {
        id: shortcutRow
        required property var actionData
        property bool capturing: false

        // One id for the whole action: a loop shortcut generates several
        // binds (possibly in both files), and one recoverable deletion must
        // own all of them. The action name is already unique per group.
        readonly property string deleteId: "shell:" + (shortcutRow.actionData?.action ?? "")
        readonly property bool deleteEnabled: !DisabledKeybinds.isDisabled(shortcutRow.deleteId)
            && page.canDeleteBinds(shortcutRow.actionData?.binds ?? [])

        // The search index builds this exact string; ContentPage.goTo() uses
        // `title` to find the row a search result points at.
        readonly property string title: KeybindLabels.shell(actionData)

        // `combos` comes from HyprlandKeybinds' merged list, so the combo the
        // row shows is the one generated from the overlay override.
        readonly property string defaultCombo: actionData?.combos?.[0] ?? ""
        readonly property string combo: shortcutRow.defaultCombo
        readonly property var aliases: (actionData?.combos ?? []).slice(1)
        readonly property var catalogIds: (actionData?.binds ?? [])
            .map(bind => String(bind?.id ?? "")).filter(id => id !== "")
        readonly property string catalogId: shortcutRow.catalogIds[0] ?? ""
        readonly property bool raw: (actionData?.binds ?? []).some(bind => bind?.raw === true)
        readonly property bool overridden: shortcutRow.catalogIds
            .some(id => ManagedKeybinds.isOverridden(id))
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
                    onClicked: page.startCapture(
                        shortcutRow.actionData.action, shortcutRow.catalogIds, shortcutRow.raw)
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
                    onClicked: page.startCapture(
                        shortcutRow.actionData.action, shortcutRow.catalogIds, shortcutRow.raw)
                }
            }

            MaterialSymbol {
                visible: shortcutRow.overridden && !shortcutRow.capturing
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                text: "restart_alt"

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        for (const id of shortcutRow.catalogIds)
                            ManagedKeybinds.clearOverride(id);
                        page.stopCapture();
                    }
                }
            }

            // Delete is recoverable: DisabledKeybinds adds the action's ids
            // to overlay.disabled and moves the row to the Deleted section.
            Item {
                id: shortcutDeleteButton
                visible: !shortcutRow.capturing && shortcutRow.deleteEnabled
                implicitWidth: 20
                implicitHeight: 20
                property bool hovered: shortcutDeleteMouseArea.containsMouse
                Accessible.name: Translation.tr("Delete keybind")
                Accessible.role: Accessible.Button

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colError
                }

                MouseArea {
                    id: shortcutDeleteMouseArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DisabledKeybinds.disableBinds(
                        shortcutRow.deleteId,
                        (shortcutRow.actionData?.description ?? "") !== ""
                            ? shortcutRow.actionData.description
                            : (shortcutRow.actionData?.action ?? ""),
                        shortcutRow.actionData?.binds ?? [])
                }

                StyledToolTip {
                    text: (shortcutRow.actionData?.binds?.length ?? 0) > 1
                        ? Translation.tr("Delete keybind") + "\n" + Translation.tr("Deleting a loop-shortcut disables every key it generates")
                        : Translation.tr("Delete keybind")
                }
            }
        }
    }

    // One logical row for a set of raw binds that share a catalog seriesId.
    // The label and count come straight from the catalog; the member caps show
    // each bind's keyLabel and the combo it actually loads with. The edit
    // controls write one seriesOverrides entry instead of N per-bind overrides
    // (raw binds refuse those), through the same overlay save pipeline.
    component SeriesRow: Rectangle {
        id: seriesRow
        required property var seriesData

        readonly property var group: seriesRow.seriesData
        readonly property string modsText: String(seriesRow.group?.mods ?? "")
        property bool expanded: false

        function applyMods() {
            const mods = seriesModsField.text.trim();
            if (mods === "") return;
            ManagedKeybinds.setSeriesOverride(
                seriesRow.group?.seriesId ?? "", { mods: mods });
            seriesModsField.focus = false;
        }

        Layout.fillWidth: true
        implicitHeight: seriesColumn.implicitHeight + 24
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal
        opacity: seriesRow.group?.enabled === false ? 0.65 : 1

        ColumnLayout {
            id: seriesColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: seriesRow.group?.seriesLabel ?? ""
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 keybinds").arg(seriesRow.group?.count ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: seriesRow.group?.enabled === false
                        text: Translation.tr("Disabled")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: page.conflictColor
                    }
                }

                Item {
                    id: seriesExpandButton
                    implicitWidth: 24
                    implicitHeight: 24
                    property string tip: seriesRow.expanded
                        ? Translation.tr("Hide keybinds") : Translation.tr("Show keybinds")
                    property bool hovered: seriesExpandMouseArea.containsMouse
                    Accessible.name: seriesExpandButton.tip
                    Accessible.role: Accessible.Button

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: seriesRow.expanded ? "expand_less" : "expand_more"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                    MouseArea {
                        id: seriesExpandMouseArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seriesRow.expanded = !seriesRow.expanded
                    }
                    StyledToolTip {
                        extraVisibleCondition: page.enabled
                        text: seriesExpandButton.tip
                    }
                }
            }

            // One modifier prefix for all members. The field follows the
            // service when not being typed in, like the colour sliders above.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: seriesModsField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Modifiers, e.g. SUPER + CTRL")
                    text: seriesRow.modsText
                    onAccepted: seriesRow.applyMods()
                }
                Binding {
                    target: seriesModsField
                    property: "text"
                    value: seriesRow.modsText
                    when: !seriesModsField.activeFocus
                }
                RippleButton {
                    enabled: seriesModsField.text.trim() !== ""
                    buttonText: Translation.tr("Apply")
                    buttonRadius: Appearance.rounding.full
                    onClicked: seriesRow.applyMods()
                }
                Item {
                    id: seriesEnableButton
                    implicitWidth: 24
                    implicitHeight: 24
                    property string tip: seriesRow.group?.enabled === false
                        ? Translation.tr("Enable series") : Translation.tr("Disable series")
                    property bool hovered: seriesEnableMouseArea.containsMouse
                    Accessible.name: seriesEnableButton.tip
                    Accessible.role: Accessible.Button

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: seriesRow.group?.enabled === false ? "visibility_off" : "visibility"
                        iconSize: Appearance.font.pixelSize.normal
                        color: seriesRow.group?.enabled === false
                            ? page.conflictColor : Appearance.colors.colSubtext
                    }
                    MouseArea {
                        id: seriesEnableMouseArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const enabled = seriesRow.group?.enabled !== false;
                            ManagedKeybinds.setSeriesOverride(
                                seriesRow.group?.seriesId ?? "",
                                { enabled: enabled ? null : false });
                        }
                    }
                    StyledToolTip {
                        extraVisibleCondition: page.enabled
                        text: seriesEnableButton.tip
                    }
                }
                Item {
                    id: seriesResetButton
                    visible: seriesRow.group?.overridden === true
                    implicitWidth: 24
                    implicitHeight: 24
                    property bool hovered: seriesResetMouseArea.containsMouse
                    Accessible.name: Translation.tr("Reset modifiers")
                    Accessible.role: Accessible.Button

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "restart_alt"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    MouseArea {
                        id: seriesResetMouseArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ManagedKeybinds.setSeriesOverride(
                            seriesRow.group?.seriesId ?? "", { mods: null })
                    }
                    StyledToolTip {
                        extraVisibleCondition: page.enabled
                        text: Translation.tr("Reset modifiers")
                    }
                }
            }

            // Expanded member list: keyLabel first, then the combo it loads
            // with (including a series mods rewrite).
            ColumnLayout {
                Layout.fillWidth: true
                visible: seriesRow.expanded
                spacing: 4

                Repeater {
                    model: seriesRow.group?.members ?? []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        KeyboardKey {
                            key: modelData.keyLabel
                            pixelSize: Appearance.font.pixelSize.smaller
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.displayCombo
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // A keybind that is not a shell action. Rebinding it writes
    // overrides[id].combo into the JSON overlay; the generator rebuilds the
    // bind from that combo. A raw-Lua bind is exempt: its statement is emitted
    // verbatim, so the row shows a lock instead of an edit affordance.
    //
    // The layout is the shortcut row's: description on the left in the same
    // size, key caps after it, the edit affordance and the reset last.
    component OtherBindRow: Rectangle {
        id: otherBindRow
        required property var bindData

        // One id per source line, labelled by the owning file. Two plain
        // binds can share a combo (or a line number in different files), so a
        // combo-only id would collapse them. Only marker-safe characters are
        // used: the id is written verbatim into a "-- " comment line.
        readonly property string deleteId: "bind:"
            + (otherBindRow.bindData?.file ?? "") + ":"
            + (otherBindRow.bindData?.line ?? "")
        readonly property bool deleteEnabled: !DisabledKeybinds.isDisabled(otherBindRow.deleteId)
            && page.canDeleteBinds([otherBindRow.bindData])

        // Deep-link target; the index uses KeybindLabels.other() with the
        // same combo so the two strings are identical.
        readonly property string title: KeybindLabels.other(bindData, HyprlandKeybinds.comboOf(bindData))

        readonly property string originalCombo: HyprlandKeybinds.comboOf(bindData)
        readonly property string overrideId: "bind_" + otherBindRow.originalCombo.replace(/[^A-Za-z0-9_]/g, "_")
        // `bindData` comes from effectiveBinds, so this is already the combo
        // the generator emits from the overlay. Display swaps a catalog
        // `code:N` token for its human keyLabel; capture/conflicts keep combo.
        readonly property string combo: otherBindRow.originalCombo
        readonly property string displayCombo: HyprlandKeybinds.displayCombo(
            otherBindRow.combo, bindData)
        readonly property string catalogId: String(bindData?.catalogBind?.id ?? bindData?.id ?? "")
        readonly property bool raw: bindData?.raw === true
            || String(bindData?.catalogBind?.dispatch?.kind ?? "") === "raw"
        readonly property bool overridden: otherBindRow.catalogId !== ""
            && ManagedKeybinds.isOverridden(otherBindRow.catalogId)
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
                        model: CF.StringUtils.keyLabels(otherBindRow.displayCombo)
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
                    cursorShape: otherBindRow.raw ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: page.startCapture(
                        otherBindRow.overrideId, [otherBindRow.catalogId], otherBindRow.raw)
                }
            }

            // A visible edit affordance, the same one the shortcut rows have.
            // A raw bind's Lua is emitted verbatim, so there is nothing to
            // capture: show a lock and explain it in the tooltip instead.
            Item {
                visible: !otherBindRow.capturing
                implicitWidth: 20
                implicitHeight: 20
                property bool hovered: rawEditMouseArea.containsMouse
                Accessible.name: otherBindRow.raw
                    ? Translation.tr("Keys fixed (raw Lua)")
                    : Translation.tr("Edit keybind")
                Accessible.role: Accessible.Button

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: otherBindRow.raw ? "lock" : "edit"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                MouseArea {
                    id: rawEditMouseArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: otherBindRow.raw ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: page.startCapture(
                        otherBindRow.overrideId, [otherBindRow.catalogId], otherBindRow.raw)
                }

                StyledToolTip {
                    extraVisibleCondition: otherBindRow.raw
                    text: Translation.tr("This keybind is raw Lua; its keys cannot be changed in Settings.")
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
                        ManagedKeybinds.clearOverride(otherBindRow.catalogId);
                        page.stopCapture();
                    }
                }
            }

            // Delete is recoverable: DisabledKeybinds adds this id to
            // overlay.disabled and moves the row to the Deleted section.
            Item {
                id: otherBindDeleteButton
                visible: !otherBindRow.capturing && otherBindRow.deleteEnabled
                implicitWidth: 20
                implicitHeight: 20
                property bool hovered: otherBindDeleteMouseArea.containsMouse
                Accessible.name: Translation.tr("Delete keybind")
                Accessible.role: Accessible.Button

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colError
                }

                MouseArea {
                    id: otherBindDeleteMouseArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DisabledKeybinds.disableBinds(
                        otherBindRow.deleteId,
                        (otherBindRow.bindData?.comment ?? "") !== ""
                            ? otherBindRow.bindData.comment
                            : otherBindRow.originalCombo,
                        [otherBindRow.bindData])
                }

                StyledToolTip {
                    text: Translation.tr("Delete keybind")
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

        // Managed binds are removed outright rather than moved to the
        // Deleted section. Once the entry leaves the model the icon hides.
        readonly property bool deleteEnabled: ManagedKeybinds.editableEntries
            .some(item => item.id === managedRow.entry?.id)

        // Deep-link target; kept in sync with SettingsSearchIndex by the
        // shared KeybindLabels helper.
        readonly property string title: KeybindLabels.managed(entry)

        readonly property string fileCombo: entry.combo
        readonly property string overrideId: "bind_" + managedRow.fileCombo.replace(/[^A-Za-z0-9_]/g, "_")
        // An override add is rewritten in place, so the entry already holds
        // the combo the generator emits.
        readonly property string combo: managedRow.fileCombo
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
                visible: managedRow.deleteEnabled
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

                // A chord the compositor owns may never reach the capture
                // listener even with the inhibitor armed. Typing it is the
                // fallback that always works.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: comboTextField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Or type: SUPER + I")
                        onAccepted: page.applyTypedCombo()
                    }

                    DialogButton {
                        buttonText: Translation.tr("Use")
                        onClicked: page.applyTypedCombo()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.capturing === "form" && !GlobalStates.keybindCaptureInhibited
                    text: Translation.tr("The compositor is still holding this shortcut. Type the combination below instead.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: page.conflictColor
                    wrapMode: Text.Wrap
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
