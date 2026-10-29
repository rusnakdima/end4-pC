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
}
