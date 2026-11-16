import QtQuick
import QtTest
import "KeybindStore.js" as KeybindStore

TestCase {
    id: root
    name: "KeybindStore"

    function entry(id, name, category, command, combo) {
        return { id: id, name: name, category: category, command: command, combo: combo };
    }

    // --- markers and round-trip -------------------------------------------------

    function test_block_round_trips_through_parse() {
        const entries = [
            entry("aaa111", "Terminal", "Apps", "kitty", "SUPER + T"),
            entry("bbb222", "Browser", "Apps", "firefox", "SUPER + B"),
            entry("ccc333", "Volume up", "", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+", "XF86AudioRaiseVolume")
        ];
        // render groups by category (empty first), so the round-trip order is
        // the grouped order, not the input order.
        const parsed = KeybindStore.parseBlock(KeybindStore.renderBlock(entries));
        compare(parsed.length, 3);
        compare(parsed[0].id, "ccc333");
        compare(parsed[0].category, "");
        compare(parsed[0].combo, "XF86AudioRaiseVolume");
        compare(parsed[1].id, "aaa111");
        compare(parsed[1].name, "Terminal");
        compare(parsed[1].category, "Apps");
        compare(parsed[1].command, "kitty");
        compare(parsed[1].combo, "SUPER + T");
        compare(parsed[2].id, "bbb222");
        compare(parsed[2].category, "Apps");
    }

    function test_parse_returns_empty_without_markers() {
        compare(KeybindStore.parseBlock("").length, 0);
        compare(KeybindStore.parseBlock("hl.bind(\"A\", hl.dsp.exec_cmd(\"x\"), {description = \"y\"})\n").length, 0);
        compare(KeybindStore.parseBlock(undefined).length, 0);
    }

    function test_heading_reopens_category_for_following_entries() {
        const text = KeybindStore.MARKER_START + "\n"
            + "--##! Media\n"
            + KeybindStore.ID_PREFIX + "one1\n"
            + "hl.bind(\"F9\", hl.dsp.exec_cmd(\"playerctl play\"), {description = \"Play\"})\n"
            + "--##! Window\n"
            + KeybindStore.ID_PREFIX + "two2\n"
            + "hl.bind(\"SUPER + Q\", hl.dsp.exec_cmd(\"killactive\"), {description = \"Close\"})\n"
            + KeybindStore.MARKER_END + "\n";
        const parsed = KeybindStore.parseBlock(text);
        compare(parsed.length, 2);
        compare(parsed[0].category, "Media");
        compare(parsed[1].category, "Window");
        compare(parsed[1].id, "two2");
    }

    // --- group ordering ----------------------------------------------------------

    function test_empty_category_is_grouped_before_headings() {
        const entries = [
            entry("one1", "With cat", "Apps", "kitty", "SUPER + T"),
            entry("two2", "No cat", "", "true", "SUPER + N")
        ];
        const block = KeybindStore.renderBlock(entries);
        const emptyIndex = block.indexOf(KeybindStore.MARKER_START);
        const headingIndex = block.indexOf("--##! Apps");
        compare(emptyIndex >= 0, true);
        compare(headingIndex > emptyIndex, true);
        const parsed = KeybindStore.parseBlock(block);
        compare(parsed[0].category, "");
        compare(parsed[1].category, "Apps");
    }

    function test_same_category_is_emitted_once_as_one_heading() {
        const entries = [
            entry("one1", "A", "Apps", "kitty", "SUPER + A"),
            entry("two2", "B", "Apps", "firefox", "SUPER + B"),
            entry("three3", "C", "Media", "playerctl", "SUPER + C")
        ];
        const block = KeybindStore.renderBlock(entries);
        const first = block.indexOf("--##! Apps");
        compare(first, block.lastIndexOf("--##! Apps"), "one heading per category");
        compare(block.indexOf("--##! Media") > first, true);
    }

    // --- escaping ----------------------------------------------------------------

    function test_render_escapes_quotes_and_backslashes_in_command() {
        const entries = [entry("one1", "Quote", "", "sh -c \"echo hi\" \\path", "SUPER + Q")];
        const block = KeybindStore.renderBlock(entries);
        const parsed = KeybindStore.parseBlock(block);
        compare(parsed.length, 1);
        compare(parsed[0].command, "sh -c \"echo hi\" \\path");
    }

    function test_render_keeps_name_without_quote_as_written() {
        const entries = [entry("one1", "It's fine", "", "true", "SUPER + I")];
        const parsed = KeybindStore.parseBlock(KeybindStore.renderBlock(entries));
        compare(parsed[0].name, "It's fine");
    }

    // --- validation --------------------------------------------------------------

    function test_validate_accepts_a_complete_entry() {
        compare(KeybindStore.validate(entry("one1", "Name", "Apps", "kitty", "SUPER + T")), "");
    }

    function test_validate_rejects_missing_fields() {
        compare(KeybindStore.validate(entry("one1", "  ", "Apps", "kitty", "SUPER + T")), "empty-name");
        compare(KeybindStore.validate(entry("one1", "Name", "", "", "SUPER + T")), "empty-command");
        compare(KeybindStore.validate(entry("one1", "Name", "", "kitty", "")), "empty-combo");
        compare(KeybindStore.validate(undefined), "empty-name");
    }

    function test_validate_rejects_double_quote_in_name() {
        // get_keybinds.py reads the description back with "([^"]+)".
        compare(KeybindStore.validate(entry("one1", "Say \"hi\"", "", "true", "SUPER + S")), "quote-name");
    }

    function test_validate_rejects_newlines() {
        compare(KeybindStore.validate(entry("one1", "line1\nline2", "", "true", "SUPER + S")), "newline-name");
        compare(KeybindStore.validate(entry("one1", "Name", "", "line1\nline2", "SUPER + S")), "newline-command");
        compare(KeybindStore.validate(entry("one1", "Name", "a\nb", "true", "SUPER + S")), "newline-category");
    }

    // --- splice ------------------------------------------------------------------

    function test_splice_appends_block_when_markers_missing() {
        const userText = "-- my own binds\nhl.bind(\"SUPER + X\", hl.dsp.exec_cmd(\"x\"), {description = \"Mine\"})\n";
        const block = KeybindStore.renderBlock([entry("one1", "New", "", "true", "SUPER + N")]);
        const result = KeybindStore.splice(userText, block);
        compare(result.startsWith(userText), true, "user content untouched");
        compare(result.includes(KeybindStore.MARKER_START), true);
        compare(result.includes("hl.bind(\"SUPER + N\""), true);
    }

    function test_splice_appends_to_empty_file_without_extra_leading_newline() {
        const block = KeybindStore.renderBlock([entry("one1", "New", "", "true", "SUPER + N")]);
        compare(KeybindStore.splice("", block), block);
    }

    function test_splice_replaces_only_the_marker_region() {
        const before = "-- user line before\n";
        const after = "-- user line after\n";
        const oldBlock = KeybindStore.renderBlock([entry("old1", "Old", "", "true", "SUPER + O")]);
        const first = before + oldBlock + after;
        const newBlock = KeybindStore.renderBlock([entry("new1", "New", "", "true", "SUPER + N")]);
        const result = KeybindStore.splice(first, newBlock);
        compare(result.startsWith(before), true);
        compare(result.endsWith(after), true);
        compare(result.includes("Old"), false);
        compare(result.includes("New"), true);
        // Splicing again with the same block is idempotent.
        compare(KeybindStore.splice(result, newBlock), result);
    }

    function test_splice_preserves_user_content_after_end_marker() {
        const userTail = "hl.bind(\"SUPER + Y\", hl.dsp.exec_cmd(\"y\"), {description = \"Tail\"})\n";
        const oldBlock = KeybindStore.renderBlock([entry("old1", "Old", "", "true", "SUPER + O")]);
        const result = KeybindStore.splice("-- head\n" + oldBlock + userTail,
            KeybindStore.renderBlock([entry("new1", "New", "", "true", "SUPER + N")]));
        compare(result.includes(userTail), true);
        compare(result.includes("old1"), false);
    }

    function test_splice_heals_a_dangling_start_marker() {
        const broken = "-- head\n" + KeybindStore.MARKER_START + "\norphan line\n";
        const result = KeybindStore.splice(broken, KeybindStore.renderBlock([entry("one1", "New", "", "true", "SUPER + N")]));
        compare(result.startsWith("-- head\n"), true);
        compare(result.includes("orphan line"), false);
        compare(result.includes(KeybindStore.MARKER_END), true);
    }

    // --- residue ------------------------------------------------------------------

    function test_unrecognised_lines_between_markers_are_preserved() {
        const text = KeybindStore.MARKER_START + "\n"
            + "-- a comment I do not know\n"
            + KeybindStore.ID_PREFIX + "one1\n"
            + "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"kitty\"), {description = \"Term\"})\n"
            + KeybindStore.MARKER_END + "\n";
        const parsed = KeybindStore.parseBlock(text);
        compare(parsed.length, 2);
        compare(parsed[0].raw, "-- a comment I do not know");
        compare(parsed[1].id, "one1");
        const block = KeybindStore.renderBlock(parsed);
        compare(block.includes("-- a comment I do not know"), true, "residue survives render");
        compare(block.includes("hl.bind(\"SUPER + T\""), true);
    }

    // --- ids -----------------------------------------------------------------------

    function test_new_id_is_unique_and_safe_for_the_comment_line() {
        const first = KeybindStore.newId();
        const second = KeybindStore.newId();
        compare(first === second, false);
        verify(/^[A-Za-z0-9-]+$/.test(first), "id must be a single comment-safe token: " + first);
    }

    function test_entries_without_id_get_a_generated_one_on_parse() {
        const text = KeybindStore.MARKER_START + "\n"
            + "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"kitty\"), {description = \"Term\"})\n"
            + KeybindStore.MARKER_END + "\n";
        const parsed = KeybindStore.parseBlock(text);
        compare(parsed.length, 1);
        verify(parsed[0].id.length > 0);
    }
}
