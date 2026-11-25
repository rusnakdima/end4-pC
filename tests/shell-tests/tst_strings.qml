import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the string helpers.
 *
 * The helpers are used to clean up titles, to escape values for shell
 * commands and to wrap text into lines, so the empty and the whitespace
 * only input matter as much as the ordinary one.
 */
TestCase {
    id: testCase
    name: "Strings"
    when: true

    function test_format_substitutes_the_arguments() {
        compare(StringUtils.format("hello {0}", "world"), "hello world");
        compare(StringUtils.format("{0} and {1}", "a", "b"), "a and b");
    }

    function test_format_keeps_the_placeholder_when_the_argument_is_missing() {
        compare(StringUtils.format("hello {0}"), "hello {0}");
        compare(StringUtils.format("{1}", "a"), "{1}");
    }

    function test_format_without_arguments_returns_the_input() {
        compare(StringUtils.format("plain"), "plain");
        compare(StringUtils.format(""), "");
    }

    function test_get_domain_strips_the_scheme_and_the_www() {
        compare(StringUtils.getDomain("https://www.example.com/path"), "example.com");
        compare(StringUtils.getDomain("http://example.com"), "example.com");
        compare(StringUtils.getDomain("example.com/path"), "example.com");
    }

    function test_get_domain_of_an_empty_string_is_null() {
        compare(StringUtils.getDomain(""), null);
    }

    function test_get_base_url_keeps_the_scheme() {
        compare(StringUtils.getBaseUrl("https://example.com/path?x=1"), "https://example.com");
        compare(StringUtils.getBaseUrl("https://example.com"), "https://example.com");
    }

    function test_get_base_url_of_a_path_without_a_host_is_null() {
        compare(StringUtils.getBaseUrl("/only/a/path"), null);
    }

    function test_shell_single_quote_escape() {
        compare(StringUtils.shellSingleQuoteEscape("it's"), "it'\\''s");
        compare(StringUtils.shellSingleQuoteEscape("plain"), "plain");
    }

    function test_escape_backslashes() {
        compare(StringUtils.escapeBackslashes("a\\b"), "a\\\\b");
        compare(StringUtils.escapeBackslashes("ab"), "ab");
    }

    function test_escape_html() {
        compare(StringUtils.escapeHtml("<b>&\"'</b>"), "&lt;b&gt;&amp;&quot;&#39;&lt;/b&gt;");
        compare(StringUtils.escapeHtml("plain"), "plain");
    }

    function test_escape_html_leaves_a_non_string_alone() {
        compare(StringUtils.escapeHtml(5), 5);
    }

    function test_word_wrap_breaks_on_the_maximum_length() {
        compare(StringUtils.wordWrap("one two three", 7), "one two\nthree");
    }

    function test_word_wrap_of_an_empty_string_is_empty() {
        compare(StringUtils.wordWrap("", 10), "");
        compare(StringUtils.wordWrap(null, 10), "");
    }

    function test_word_wrap_of_a_whitespace_only_string_is_empty() {
        // The words are empty, so every line is empty and the result is a
        // single empty line.
        compare(StringUtils.wordWrap("   ", 10), "");
    }

    function test_word_wrap_keeps_a_word_that_is_longer_than_the_limit() {
        compare(StringUtils.wordWrap("abcdefghijk", 5), "abcdefghijk");
    }

    function test_clean_music_title_removes_the_brackets() {
        compare(StringUtils.cleanMusicTitle("(Artist) Title"), "Title");
        compare(StringUtils.cleanMusicTitle("[Artist] Title"), "Title");
        compare(StringUtils.cleanMusicTitle("{Artist} Title"), "Title");
        compare(StringUtils.cleanMusicTitle("【Touhou】Title"), "Title");
    }

    function test_clean_music_title_keeps_a_plain_title() {
        compare(StringUtils.cleanMusicTitle("Title"), "Title");
    }

    function test_clean_music_title_of_an_empty_string_is_empty() {
        compare(StringUtils.cleanMusicTitle(""), "");
        compare(StringUtils.cleanMusicTitle(null), "");
    }

    function test_friendly_time_for_seconds() {
        compare(StringUtils.friendlyTimeForSeconds(0), "0:00");
        compare(StringUtils.friendlyTimeForSeconds(5), "0:05");
        compare(StringUtils.friendlyTimeForSeconds(83), "1:23");
        compare(StringUtils.friendlyTimeForSeconds(3723), "1:02:03");
    }

    function test_friendly_time_for_an_invalid_value_is_zero() {
        compare(StringUtils.friendlyTimeForSeconds(NaN), "0:00");
        compare(StringUtils.friendlyTimeForSeconds(-10), "0:00");
    }

    function test_clean_cliphist_entry_removes_the_leading_number() {
        compare(StringUtils.cleanCliphistEntry("42\ttext"), "text");
        compare(StringUtils.cleanCliphistEntry("text"), "text");
    }

    function test_string_list_contains_substring() {
        verify(StringUtils.stringListContainsSubstring("hello world", ["world"]));
        verify(!StringUtils.stringListContainsSubstring("hello world", ["nope"]));
        verify(!StringUtils.stringListContainsSubstring("hello world", []));
    }

    function test_clean_prefix() {
        compare(StringUtils.cleanPrefix("prefix-value", "prefix-"), "value");
        compare(StringUtils.cleanPrefix("value", "prefix-"), "value");
    }

    function test_clean_one_prefix() {
        compare(StringUtils.cleanOnePrefix("prefix-value", ["other-", "prefix-"]), "value");
        compare(StringUtils.cleanOnePrefix("value", ["other-"]), "value");
    }

    function test_to_title_case() {
        compare(StringUtils.toTitleCase("hello-world"), "Hello World");
        compare(StringUtils.toTitleCase("hello_world"), "Hello World");
        compare(StringUtils.toTitleCase("HELLO"), "Hello");
    }

    function test_split_markdown_blocks_splits_the_code_block() {
        const blocks = StringUtils.splitMarkdownBlocks("text\n```js\ncode\n```");
        verify(blocks.length === 2);
        compare(blocks[0].type, "text");
        compare(blocks[1].type, "code");
        compare(blocks[1].lang, "js");
        compare(blocks[1].content, "code\n");
        verify(blocks[1].completed);
    }

    function test_split_markdown_blocks_marks_an_unfinished_block() {
        const blocks = StringUtils.splitMarkdownBlocks("```js\ncode");
        verify(blocks.length === 1);
        compare(blocks[0].type, "code");
        verify(!blocks[0].completed);
    }

    function test_split_markdown_blocks_of_an_empty_string_is_empty() {
        verify(StringUtils.splitMarkdownBlocks("").length === 0);
    }

    /**
     * The search field of the Wi-Fi and Bluetooth windows narrows their
     * lists with this, so the empty query, the case folding, the token
     * rules and the order are all part of the contract.
     */
    function test_filter_by_query_returns_everything_for_an_empty_query() {
        const items = [{ ssid: "Home" }, { ssid: "Office" }];
        // An untouched field costs nothing: the same list comes back.
        verify(StringUtils.filterByQuery(items, "", ["ssid"]) === items);
        compare(StringUtils.filterByQuery(items, "   ", ["ssid"]).length, 2);
        compare(StringUtils.filterByQuery(items, null, ["ssid"]).length, 2);
    }

    function test_filter_by_query_matches_any_field_case_insensitively() {
        const items = [{ ssid: "Home-5G", security: "WPA2" }, { ssid: "Office" }];
        const matched = StringUtils.filterByQuery(items, "home-5g", ["ssid"]);
        compare(matched.length, 1);
        compare(matched[0].ssid, "Home-5G");
        compare(StringUtils.filterByQuery(items, "HOME", ["ssid"]).length, 1);
        // The keys are OR-ed: any one of them may carry the token.
        compare(StringUtils.filterByQuery(items, "wpa2", ["ssid", "security"]).length, 1);
    }

    function test_filter_by_query_requires_every_token_to_match() {
        const items = [{ ssid: "Home", security: "WPA2" }, { ssid: "Office", security: "" }];
        // The tokens may match different keys of the same entry.
        compare(StringUtils.filterByQuery(items, "home wpa2", ["ssid", "security"]).length, 1);
        compare(StringUtils.filterByQuery(items, "office wpa2", ["ssid", "security"]).length, 0);
        compare(StringUtils.filterByQuery(items, "home office", ["ssid", "security"]).length, 0);
    }

    function test_filter_by_query_preserves_the_input_order() {
        const items = [{ ssid: "net-a" }, { ssid: "other" }, { ssid: "net-b" }, { ssid: "net-c" }];
        const matched = StringUtils.filterByQuery(items, "net", ["ssid"]);
        compare(matched.length, 3);
        compare(matched[0].ssid, "net-a");
        compare(matched[1].ssid, "net-b");
        compare(matched[2].ssid, "net-c");
    }

    function test_filter_by_query_skips_missing_and_null_entries() {
        const items = [null, { ssid: "Home" }, { other: "value" }, undefined];
        const matched = StringUtils.filterByQuery(items, "home", ["ssid"]);
        compare(matched.length, 1);
        compare(matched[0].ssid, "Home");
        // A missing key reads as an empty string, it never throws.
        compare(StringUtils.filterByQuery(items, "", ["ssid"]).length, 4);
        // Non-string fields are coerced before the comparison.
        const strength = [{ ssid: "Home", strength: 42 }];
        compare(StringUtils.filterByQuery(strength, "42", ["strength"]).length, 1);
        compare(StringUtils.filterByQuery(strength, "4", ["strength"]).length, 1);
        compare(StringUtils.filterByQuery(strength, "seven", ["strength"]).length, 0);
    }

    function test_filter_by_query_of_nothing_is_empty() {
        compare(StringUtils.filterByQuery([], "home", ["ssid"]).length, 0);
        compare(StringUtils.filterByQuery(null, "home", ["ssid"]).length, 0);
        compare(StringUtils.filterByQuery(undefined, "", ["ssid"]).length, 0);
    }

    /**
     * The keybind search accepts a typed combination ("super+i") as well as
     * ordinary text, and a pressed combination is written with "+" separators.
     */
    function test_filter_by_query_with_combos_matches_pressed_and_typed_combos() {
        const items = [
            { name: "Terminal", combo: "SUPER + Return" },
            { name: "Sidebar", combo: "SUPER + B" },
            { name: "Settings", combo: "SUPER + I" }
        ];
        compare(StringUtils.filterByQueryWithCombos(items, "super+i", ["name"], ["combo"]).length, 1);
        compare(StringUtils.filterByQueryWithCombos(items, "SUPER + I", ["name"], ["combo"])[0].name, "Settings");
        compare(StringUtils.filterByQueryWithCombos(items, "super", ["name"], ["combo"]).length, 3);
        compare(StringUtils.filterByQueryWithCombos(items, "terminal", ["name"], ["combo"]).length, 1);
        compare(StringUtils.filterByQueryWithCombos(items, "", ["name"], ["combo"]).length, 3);
    }

    /**
     * The second-precision switch adds or removes the seconds field of the
     * clock format, so the helpers have to keep the chosen base format and
     * the am/pm marker intact.
     */
    function test_format_has_seconds() {
        verify(!StringUtils.formatHasSeconds("hh:mm"));
        verify(!StringUtils.formatHasSeconds("h:mm ap"));
        verify(StringUtils.formatHasSeconds("hh:mm:ss"));
        verify(StringUtils.formatHasSeconds("h:mm:ss ap"));
        verify(StringUtils.formatHasSeconds("h:mm:ss AP"));
        verify(StringUtils.formatHasSeconds("ss"));
        verify(!StringUtils.formatHasSeconds("ddd, dd/MM"));
        verify(!StringUtils.formatHasSeconds(""));
    }

    function test_remove_seconds_from_format_keeps_the_base_format() {
        compare(StringUtils.removeSecondsFromFormat("hh:mm:ss"), "hh:mm");
        compare(StringUtils.removeSecondsFromFormat("h:mm:ss ap"), "h:mm ap");
        compare(StringUtils.removeSecondsFromFormat("h:mm:ss AP"), "h:mm AP");
        compare(StringUtils.removeSecondsFromFormat("hh:mm"), "hh:mm");
        // A literal word that happens to end in "s" is not a seconds field.
        compare(StringUtils.removeSecondsFromFormat("HH 'hours' mm"), "HH 'hours' mm");
    }

    function test_set_format_seconds_round_trips() {
        compare(StringUtils.setFormatSeconds("hh:mm", true), "hh:mm:ss");
        compare(StringUtils.setFormatSeconds("hh:mm:ss", false), "hh:mm");
        compare(StringUtils.setFormatSeconds("h:mm ap", true), "h:mm:ss ap");
        compare(StringUtils.setFormatSeconds("h:mm:ss ap", false), "h:mm ap");
        compare(StringUtils.setFormatSeconds("h:mm AP", true), "h:mm:ss AP");
        compare(StringUtils.setFormatSeconds("h:mm AP", false), "h:mm AP");
        // Already in the requested state: unchanged.
        compare(StringUtils.setFormatSeconds("hh:mm:ss", true), "hh:mm:ss");
        compare(StringUtils.setFormatSeconds("", false), "");
        compare(StringUtils.setFormatSeconds("", true), "hh:mm:ss");
    }
}
