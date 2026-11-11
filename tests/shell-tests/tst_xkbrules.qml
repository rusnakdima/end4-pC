import QtQuick
import QtTest
import qs.services

/**
 * The xkb rule list parser behind the keyboard dropdowns: a layout is a
 * code and a name, a variant belongs to one layout, and a colon-less entry
 * in the options is a category header rather than an option you can pick.
 */
TestCase {
    id: testCase
    name: "XkbRules"
    when: true

    property string fixture: [
        "! model",
        "  pc105           Generic 105-key PC",
        "! layout",
        "  us              English (US)",
        "  latam           Spanish (Latin American)",
        "! variant",
        "  intl            us: English (US, intl., with dead keys)",
        "  dvorak          us: English (Dvorak)",
        "  phonetic        am: Armenian (phonetic)",
        "! option",
        "  grp             Switching to another layout",
        "  grp:alt_shift_toggle   Alt+Shift",
        "  caps:escape     Make Caps Lock an additional Escape"
    ].join("\n")

    property var savedVariants: null

    function test_layouts_are_code_and_name() {
        const layouts = XkbRules.layoutsFrom(testCase.fixture);
        compare(layouts.length, 2);
        compare(layouts[0].value, "us");
        compare(layouts[0].displayName, "English (US)");
        compare(layouts[1].value, "latam");
        // The model section is not a layout list.
        compare(layouts.findIndex(entry => entry.value === "pc105"), -1);
    }

    function test_variants_know_their_layout() {
        const variants = XkbRules.variantsFrom(testCase.fixture);
        compare(variants.length, 3);
        compare(variants[0].variant, "intl");
        compare(variants[0].layout, "us");
        compare(variants[0].displayName, "English (US, intl., with dead keys)");
        compare(variants[2].layout, "am");
    }

    function test_options_skip_the_category_headers() {
        const options = XkbRules.optionsFrom(testCase.fixture);
        compare(options.length, 2);
        compare(options[0].value, "grp:alt_shift_toggle");
        compare(options[0].displayName, "Alt+Shift");
        compare(options[1].value, "caps:escape");
    }

    function test_variant_options_follow_the_first_layout() {
        testCase.savedVariants = XkbRules.variants;
        try {
            XkbRules.variants = XkbRules.variantsFrom(testCase.fixture);
            const usVariants = XkbRules.variantOptions("us, latam");
            compare(usVariants.length, 2);
            compare(usVariants[0].value, "intl");
            // Before a layout is chosen a bare variant name would be
            // ambiguous, so nothing is offered.
            compare(XkbRules.variantOptions("").length, 0);
            compare(XkbRules.variantOptions("nope").length, 0);
        } finally {
            XkbRules.variants = testCase.savedVariants;
        }
    }

    function test_variant_entries_give_each_layout_its_own_slot() {
        testCase.savedVariants = XkbRules.variants;
        const savedLoaded = XkbRules.loaded;
        try {
            XkbRules.variants = XkbRules.variantsFrom(testCase.fixture);
            XkbRules.loaded = true;
            // us has Default + intl + dvorak; am has Default + phonetic.
            const entries = XkbRules.variantEntries("us, am");
            compare(entries.filter(entry => entry.slot === 0).length, 3);
            compare(entries.filter(entry => entry.slot === 1).length, 2);
            const amDefault = entries.find(entry => entry.slot === 1 && entry.value === "");
            compare(amDefault.slotLabel, "am");
            const usDefault = entries.find(entry => entry.slot === 0 && entry.value === "");
            compare(usDefault.slotLabel, "us");
            // Nothing can be slotted before the rule lists have loaded.
            XkbRules.loaded = false;
            compare(XkbRules.variantEntries("us").length, 0);
        } finally {
            XkbRules.variants = testCase.savedVariants;
            XkbRules.loaded = savedLoaded;
        }
    }

    function test_an_invalid_variant_slot_is_dropped() {
        testCase.savedVariants = XkbRules.variants;
        const savedLoaded = XkbRules.loaded;
        try {
            XkbRules.variants = XkbRules.variantsFrom(testCase.fixture);
            XkbRules.loaded = true;
            // Valid slots stay where they are.
            compare(XkbRules.sanitizeVariant("intl", "us"), "intl");
            compare(XkbRules.sanitizeVariant("intl,phonetic", "us,am"), "intl,phonetic");
            // A variant that does not belong to the layout at its position
            // is what made xkb reject the whole keymap: it is dropped, and
            // so are the empty slots it leaves behind.
            compare(XkbRules.sanitizeVariant("weird", "us"), "");
            compare(XkbRules.sanitizeVariant("intl,weird", "us,am"), "intl");
            compare(XkbRules.sanitizeVariant("intl,phonetic", "us,ru"), "intl");
            // Before the lists load no judgement is possible: keep the raw
            // value instead of erasing it.
            XkbRules.loaded = false;
            compare(XkbRules.sanitizeVariant("intl,weird", "us"), "intl,weird");
        } finally {
            XkbRules.variants = testCase.savedVariants;
            XkbRules.loaded = savedLoaded;
        }
    }

    function test_the_system_rules_file_parses_into_real_lists() {
        tryVerify(() => XkbRules.loaded, 5000, "the system rules file never loaded");
        // Generous floors: the exact counts belong to the distribution.
        verify(XkbRules.layouts.length > 20, "expected a real layout list");
        verify(XkbRules.options.length > 20, "expected a real option list");
        verify(XkbRules.layouts.some(entry => entry.value === "us"), "us is missing");
    }
}
