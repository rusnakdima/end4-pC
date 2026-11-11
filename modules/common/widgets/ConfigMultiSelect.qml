import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

/**
 * A row that holds a comma-separated selection ("us,ru") as chips instead
 * of free text: the current values are shown as removable chips and the
 * dropdown adds one from a fixed list, so an invalid code cannot be typed
 * in. Used for the xkb layout / variant / option fields.
 *
 * Two modes:
 *  - append (the default): a chip is one value, values join with "," and
 *    re-adding one is a no-op. Layouts and options work like this.
 *  - positional: the value keeps one slot per entry's `slot`, which is how
 *    xkb variant lists work — the nth variant belongs to the nth layout.
 *    Entries carry `slot` and an optional `slotLabel` the chip shows
 *    ("ru: phonetic"), and an entry with an empty value clears that slot.
 *
 * The first dropdown entry is a placeholder: it opens the search on an
 * empty row and never becomes a value.
 */
RowLayout {
    id: root

    property string text: ""
    property string description: ""
    property string buttonIcon: ""
    // [{ value, displayName, slot?, slotLabel? }] — what the dropdown offers.
    property var model: []
    property string value: ""
    property bool positional: false
    property real fieldWidth: 220

    signal edited(string newValue)

    readonly property var items: root.value.split(",").map(part => part.trim()).filter(part => part.length > 0)
    readonly property var entries: [{ "value": "", "displayName": Translation.tr("Add…") }, ...root.model]

    // One chip per non-empty value. In positional mode the chip keeps the
    // slot it occupies so removing it clears exactly that position.
    readonly property var chips: {
        const parts = root.value.split(",").map(part => part.trim());
        if (!root.positional)
            return parts.filter(part => part !== "").map(part => ({ "text": part, "slot": -1 }));
        return parts
            .map((part, slot) => ({ "text": part, "slot": slot }))
            .filter(chip => chip.text !== "");
    }

    function slotLabelFor(chip) {
        if (chip.slot < 0) return "";
        const entry = root.entries.find(candidate => candidate.slot === chip.slot && candidate.value === chip.text);
        return entry !== undefined && entry.slotLabel !== undefined ? entry.slotLabel : "";
    }

    function chipText(chip) {
        const label = root.slotLabelFor(chip);
        return label !== "" ? `${label}: ${chip.text}` : chip.text;
    }

    // Trailing empty slots are dropped: "intl," and "intl" describe the
    // same keymap and the short form is what the configurator writes.
    function joined(parts) {
        const out = parts.slice();
        while (out.length > 0 && out[out.length - 1] === "") out.pop();
        return out.join(",");
    }

    function addEntry(entry) {
        // The placeholder of the dropdown: nothing to add.
        if (entry.value === "" && entry.slot === undefined) {
            combo.currentIndex = 0;
            return;
        }
        if (root.positional) {
            const parts = root.value.split(",").map(part => part.trim());
            while (parts.length <= entry.slot) parts.push("");
            parts[entry.slot] = entry.value;
            root.edited(root.joined(parts));
        } else if (entry.value !== "" && !root.items.includes(entry.value)) {
            root.edited(root.items.concat([entry.value]).join(","));
        }
        combo.currentIndex = 0;
    }

    function removeChip(chip) {
        if (root.positional) {
            const parts = root.value.split(",").map(part => part.trim());
            if (chip.slot < 0 || chip.slot >= parts.length) return;
            parts[chip.slot] = "";
            root.edited(root.joined(parts));
        } else {
            root.edited(root.items.filter(item => item !== chip.text).join(","));
        }
    }

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
        opacity: root.enabled ? 1 : 0.4
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            opacity: root.enabled ? 1 : 0.4
        }

        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: root.chips.length > 0

            Repeater {
                model: root.chips

                delegate: Rectangle {
                    id: chip
                    required property var modelData

                    // Capped so one long code cannot stretch the row; the
                    // text elides once the cap kicks in.
                    width: Math.min(chipLayout.implicitWidth + 14, 240)
                    height: chipLayout.implicitHeight + 8
                    radius: height / 2
                    color: Appearance.colors.colSecondaryContainer

                    RowLayout {
                        id: chipLayout
                        x: 7
                        y: 4
                        width: chip.width - 14
                        height: chip.height - 8
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: root.chipText(chip.modelData)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            text: "close"
                            iconSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeChip(chip.modelData)
                    }
                }
            }
        }
    }

    StyledComboBoxSearch {
        id: combo
        Layout.preferredWidth: root.fieldWidth
        Layout.alignment: Qt.AlignVCenter
        enabled: root.enabled
        textRole: "displayName"
        model: root.entries
        currentIndex: 0

        onActivated: index => {
            const entry = root.entries[index];
            if (entry !== undefined) root.addEntry(entry);
        }
    }
}
