import QtQuick
import QtTest
import qs.services

/**
 * The translation service resolves the UI language, loads the matching
 * translation file and looks strings up. A missing key has to fall back to
 * the key itself so the UI never shows an empty string.
 */
TestCase {
    id: testCase
    name: "Translation"
    when: true

    // The language scan and the translation file both load asynchronously.
    function waitForLanguages() {
        for (let i = 0; i < 150; ++i) {
            if (Translation.availableLanguages.indexOf("de_DE") >= 0
                    && Translation.availableLanguages.indexOf("en_US") >= 0)
                return true;
            wait(100);
        }
        return false;
    }

    function waitForTranslations(minKeys) {
        for (let i = 0; i < 150; ++i) {
            if (Object.keys(Translation.translations).length >= minKeys)
                return true;
            wait(100);
        }
        return false;
    }

    function test_the_translations_directory_is_the_harness_fixture_directory() {
        // The harness keeps a directory of symlinks to the shipped
        // translations, so the service has to read that directory.
        verify(Translation.translationsDir.endsWith("tests/shell-tests/translations"));
    }

    function test_the_language_scan_finds_the_shipped_translations() {
        verify(waitForLanguages());
        verify(Translation.availableLanguages.indexOf("de_DE") >= 0);
        verify(Translation.availableLanguages.indexOf("en_US") >= 0);
        verify(Translation.allAvailableLanguages.indexOf("en_US") >= 0);
    }

    function test_resolve_language_falls_back_to_english() {
        verify(waitForLanguages());
        compare(Translation.resolveLanguage("C"), "en_US");
        compare(Translation.resolveLanguage("POSIX"), "en_US");
        compare(Translation.resolveLanguage(""), "en_US");
        compare(Translation.resolveLanguage("en_GB"), "en_US");
        compare(Translation.resolveLanguage("de_DE"), "de_DE");
    }

    function test_resolve_language_maps_a_language_without_a_region() {
        verify(waitForLanguages());
        compare(Translation.resolveLanguage("de"), "de_DE");
    }

    function test_resolve_language_returns_an_unknown_locale_unchanged() {
        // DEFECT: an unknown locale is returned verbatim instead of falling
        // back to en_US, so the service asks for a translation file that does
        // not exist. The behaviour is asserted as it is today.
        verify(waitForLanguages());
        compare(Translation.resolveLanguage("xx_YY"), "xx_YY");
    }

    function test_the_english_translations_are_loaded() {
        verify(waitForTranslations(1189));
        compare(Object.keys(Translation.translations).length, 1189);
    }

    function test_tr_returns_the_translation_of_an_existing_key() {
        verify(waitForTranslations(1189));
        verify("Unknown device" in Translation.translations);
        compare(Translation.tr("Unknown device"), Translation.translations["Unknown device"]);
        compare(Translation.tr("Unknown device"), "Unknown device");
    }

    function test_tr_returns_the_key_when_the_translation_is_missing() {
        verify(waitForTranslations(1189));
        compare(Translation.tr("No Such Key At All"), "No Such Key At All");
    }

    function test_tr_of_an_empty_string_is_empty() {
        verify(waitForTranslations(1189));
        compare(Translation.tr(""), "");
    }
}
