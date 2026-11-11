import QtQuick
import QtTest
import qs.modules.common.widgets

/**
 * The chip row behind the keyboard dropdowns: a comma-separated value
 * becomes removable chips, values join without spaces (xkb rejects a list
 * with "us, ru"), and in positional mode every chip owns the slot of the
 * layout it belongs to, which is how xkb variant lists are read.
 */
TestCase {
    id: testCase
    name: "ConfigMultiSelect"
    when: true

    property var row: null
    property var received: []

    Component {
        id: rowComponent
        ConfigMultiSelect {}
    }

    function init() {
        testCase.row = rowComponent.createObject(null);
        testCase.received = [];
        testCase.row.edited.connect(value => testCase.received.push(value));
    }

    function cleanup() {
        if (testCase.row !== null) {
            testCase.row.destroy();
            testCase.row = null;
        }
    }

    function test_the_value_becomes_clean_chips() {
        row.value = " us , , ru ";
        compare(row.items.length, 2);
        compare(row.items[0], "us");
        compare(row.items[1], "ru");
    }

    function test_adding_appends_once_without_spaces() {
        row.value = "us";
        row.addEntry({ "value": "ru", "displayName": "Russian" });
        compare(testCase.received.length, 1);
        compare(testCase.received[0], "us,ru");
        // The same value again is a no-op, and so is the placeholder the
        // dropdown opens on.
        row.value = "us,ru";
        row.addEntry({ "value": "ru", "displayName": "Russian" });
        row.addEntry({ "value": "", "displayName": "Add…" });
        compare(testCase.received.length, 1);
    }

    function test_removing_leaves_the_others() {
        row.value = "us,ru";
        row.removeChip({ "text": "ru", "slot": -1 });
        compare(testCase.received[0], "us");
    }

    function test_positional_chips_own_one_slot_per_layout() {
        row.positional = true;
        row.model = [
            { "value": "", "displayName": "Default", "slot": 0, "slotLabel": "us" },
            { "value": "intl", "displayName": "intl", "slot": 0, "slotLabel": "us" },
            { "value": "", "displayName": "Default", "slot": 1, "slotLabel": "ru" },
            { "value": "phonetic", "displayName": "phonetic", "slot": 1, "slotLabel": "ru" }
        ];
        row.value = "intl";

        // Adding the second layout's variant fills slot 1, it does not
        // append blindly, and the trailing empty slot never shows.
        row.addEntry({ "value": "phonetic", "displayName": "phonetic", "slot": 1, "slotLabel": "ru" });
        compare(testCase.received[0], "intl,phonetic");

        // Clearing slot 1 keeps slot 0 and drops the trailing comma.
        row.value = "intl,phonetic";
        row.removeChip({ "text": "phonetic", "slot": 1 });
        compare(testCase.received[1], "intl");

        // The Default entry of a slot clears exactly that slot.
        row.value = "intl,phonetic";
        row.addEntry({ "value": "", "displayName": "Default", "slot": 1, "slotLabel": "ru" });
        compare(testCase.received[2], "intl");
    }

    function test_positional_chips_say_which_layout_they_belong_to() {
        row.positional = true;
        row.model = [
            { "value": "intl", "displayName": "intl", "slot": 0, "slotLabel": "us" },
            { "value": "phonetic", "displayName": "phonetic", "slot": 1, "slotLabel": "ru" }
        ];
        row.value = "intl,phonetic";
        compare(row.chipText(row.chips[0]), "us: intl");
        compare(row.chipText(row.chips[1]), "ru: phonetic");
        // A value no entry claims (one the sanitizer would drop) shows raw.
        compare(row.chipText({ "text": "weird", "slot": 1 }), "weird");
    }

    function test_the_dropdown_starts_with_the_placeholder_entry() {
        row.model = [{ "value": "us", "displayName": "English (US)" }];
        compare(row.entries.length, 2);
        compare(row.entries[0].value, "");
        compare(row.entries[1].value, "us");
    }
}
