import QtQuick
import QtTest
import "modules/common/functions/KeybindDisableStore.js" as Store

/**
 * The pure text layer behind "delete keybind": disable() comments out the
 * exact source lines of a bind and wraps them in a recoverable marker block,
 * restore() puts the original bytes back. Both operate on a plain string, so
 * they are tested here without any service, file or Qt types.
 *
 * These tests deliberately spell the marker format out instead of importing
 * it from the implementation, so a change to the on-disk format is caught.
 */
TestCase {
    id: testCase
    name: "KeybindDisableStore"
    when: true

    // The on-disk format, written literally so the test is independent of
    // the constants under test.
    function startLine(id) { return "-- >>> end4-pC disabled keybind: " + id; }
    function endLine() { return "-- <<< end4-pC disabled keybind <<<"; }

    // A realistic keybinds.lua fragment: theme markers and user lines around
    // two binds, with a trailing newline. Everything outside the targeted
    // line must survive a disable byte-for-byte.
    function originalText() {
        return "-- >>> end4-pC theme keybinds >>>\n"
            + "-- user line before\n"
            + "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"kitty\"), {description = \"Terminal\"})\n"
            + "hl.bind(\"SUPER + B\", hl.dsp.exec_cmd(\"firefox\"), {description = \"Browser\"})\n"
            + "-- user line after\n"
            + "-- <<< end4-pC theme keybinds <<<\n";
    }

    function terminalLine() {
        return "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"kitty\"), {description = \"Terminal\"})";
    }

    function test_marker_constants_are_exact() {
        compare(Store.START, "-- >>> end4-pC disabled keybind: ");
        compare(Store.END, "-- <<< end4-pC disabled keybind <<<");
    }

    function test_disable_comments_exact_line_and_preserves_other_bytes() {
        const result = Store.disable(testCase.originalText(), {
            id: "main:Terminal", line: 3, endLine: 3
        });
        verify(result.ok, "disable failed: " + result.error);

        const expected = "-- >>> end4-pC theme keybinds >>>\n"
            + "-- user line before\n"
            + testCase.startLine("main:Terminal") + "\n"
            + "-- " + testCase.terminalLine() + "\n"
            + testCase.endLine() + "\n"
            + "hl.bind(\"SUPER + B\", hl.dsp.exec_cmd(\"firefox\"), {description = \"Browser\"})\n"
            + "-- user line after\n"
            + "-- <<< end4-pC theme keybinds <<<\n";
        compare(result.text, expected);
    }

    function test_parse_disabled_round_trips_the_original_lines() {
        const result = Store.disable(testCase.originalText(), {
            id: "main:Terminal", line: 3, endLine: 3
        });
        verify(result.ok, "disable failed: " + result.error);

        const blocks = Store.parseDisabled(result.text);
        compare(blocks.length, 1);
        compare(blocks[0].id, "main:Terminal");
        compare(blocks[0].lines.length, 1);
        compare(blocks[0].lines[0], testCase.terminalLine());
    }

    function test_restore_reproduces_original_text_exactly() {
        const original = testCase.originalText();
        const result = Store.disable(original, {
            id: "main:Terminal", line: 3, endLine: 3
        });
        verify(result.ok, "disable failed: " + result.error);

        const restored = Store.restore(result.text, "main:Terminal");
        verify(restored.ok, "restore failed: " + restored.error);
        compare(restored.text, original);
    }

    function test_disable_rejects_an_already_disabled_id() {
        const once = Store.disable(testCase.originalText(), {
            id: "main:Terminal", line: 3, endLine: 3
        });
        verify(once.ok, "first disable failed: " + once.error);

        const twice = Store.disable(once.text, {
            id: "main:Terminal", line: 6, endLine: 6
        });
        verify(!twice.ok, "a second disable of the same id must be rejected");
        compare(twice.error, "already-disabled");
    }

    function test_disable_rejects_out_of_range_lines() {
        const beyond = Store.disable(testCase.originalText(), {
            id: "main:X", line: 3, endLine: 99
        });
        verify(!beyond.ok, "endLine beyond the text must be rejected");
        compare(beyond.error, "bad-range");

        const zero = Store.disable(testCase.originalText(), {
            id: "main:X", line: 0, endLine: 1
        });
        verify(!zero.ok, "line 0 must be rejected");
        compare(zero.error, "bad-range");

        const backwards = Store.disable(testCase.originalText(), {
            id: "main:X", line: 4, endLine: 3
        });
        verify(!backwards.ok, "endLine before line must be rejected");
        compare(backwards.error, "bad-range");
    }

    function test_disable_placeholder_line() {
        // A --#/# loop placeholder must become "-- --#/# ...", which the
        // parser no longer treats as a bind directive.
        const text = "--#/# bind = SUPER, kitty, Terminal\n"
            + "hl.bind(\"A\", hl.dsp.exec_cmd(\"x\"), {description = \"A\"})\n";
        const result = Store.disable(text, {
            id: "main:placeholder", line: 1, endLine: 1
        });
        verify(result.ok, "disable failed: " + result.error);

        const lines = result.text.split("\n");
        compare(lines[0], testCase.startLine("main:placeholder"));
        compare(lines[1], "-- --#/# bind = SUPER, kitty, Terminal");

        const blocks = Store.parseDisabled(result.text);
        compare(blocks.length, 1);
        compare(blocks[0].lines[0], "--#/# bind = SUPER, kitty, Terminal");

        const restored = Store.restore(result.text, "main:placeholder");
        verify(restored.ok, "restore failed: " + restored.error);
        compare(restored.text, text);
    }

    function test_disable_multiline_restores_verbatim() {
        // A three-line bind: commenting only the first line would leave a
        // half-active bind, so the whole line..endLine range is wrapped.
        const text = "-- head\n"
            + "hl.bind(\"SUPER + M\",\n"
            + "  hl.dsp.exec_cmd(\"one; two; three\"),\n"
            + "  {description = \"Multi\"})\n"
            + "-- tail\n";
        const result = Store.disable(text, {
            id: "main:Multi", line: 2, endLine: 4
        });
        verify(result.ok, "disable failed: " + result.error);

        const lines = result.text.split("\n");
        compare(lines[1], testCase.startLine("main:Multi"));
        compare(lines[2], "-- hl.bind(\"SUPER + M\",");
        compare(lines[3], "--   hl.dsp.exec_cmd(\"one; two; three\"),");
        compare(lines[4], "--   {description = \"Multi\"})");
        compare(lines[5], testCase.endLine());

        const blocks = Store.parseDisabled(result.text);
        compare(blocks.length, 1);
        compare(blocks[0].lines.length, 3);
        compare(blocks[0].lines[0], "hl.bind(\"SUPER + M\",");
        compare(blocks[0].lines[1], "  hl.dsp.exec_cmd(\"one; two; three\"),");
        compare(blocks[0].lines[2], "  {description = \"Multi\"})");

        const restored = Store.restore(result.text, "main:Multi");
        verify(restored.ok, "restore failed: " + restored.error);
        compare(restored.text, text);
    }

    function test_is_disabled_and_restore_of_a_missing_id() {
        const once = Store.disable(testCase.originalText(), {
            id: "main:Terminal", line: 3, endLine: 3
        });
        verify(once.ok, "disable failed: " + once.error);

        verify(Store.isDisabled(once.text, "main:Terminal"));
        verify(!Store.isDisabled(once.text, "main:Other"));
        verify(!Store.isDisabled(testCase.originalText(), "main:Terminal"));

        const missing = Store.restore(testCase.originalText(), "main:Terminal");
        verify(!missing.ok, "restoring an unknown id must fail");
        compare(missing.error, "not-found");
    }

    function test_id_for_bind_is_stable_safe_and_ignores_line_numbers() {
        const first = Store.idForBind({
            action: "actionOpen", comment: "Open thing",
            mods: ["SUPER"], key: "O", line: 12, endLine: 14
        }, "main");
        const second = Store.idForBind({
            action: "actionOpen", comment: "Open thing",
            mods: ["SUPER"], key: "O", line: 99, endLine: 101
        }, "main");
        compare(first, second, "the id must not depend on line numbers");
        verify(first.indexOf("\"") === -1, "the id must not contain a quote");
        verify(first.indexOf("\n") === -1, "the id must not contain a newline");

        // Falls back to the comment when there is no action, sanitising a
        // quote and a newline so the id stays safe inside a "-- " comment.
        const byComment = Store.idForBind({
            comment: "Say \"hi\"\nthere", mods: ["CTRL"], key: "Q"
        }, "custom");
        verify(byComment.indexOf("\"") === -1, "comment id leaked a quote");
        verify(byComment.indexOf("\n") === -1, "comment id leaked a newline");

        // Falls back to mods + key when neither action nor comment exists,
        // deterministically.
        const byCombo = Store.idForBind({ mods: ["SUPER", "SHIFT"], key: "F6" }, "main");
        compare(byCombo, Store.idForBind({ mods: ["SUPER", "SHIFT"], key: "F6" }, "main"));
        verify(byCombo.length > 0, "the combo fallback produced an empty id");
    }

    function test_restore_removes_only_the_requested_block() {
        // Two disabled binds; line numbers are taken fresh after each write
        // because commenting the first one shifts the second one down.
        const first = Store.disable(testCase.originalText(), {
            id: "main:Terminal", line: 3, endLine: 3
        });
        verify(first.ok, "first disable failed: " + first.error);
        const second = Store.disable(first.text, {
            id: "main:Browser", line: 6, endLine: 6
        });
        verify(second.ok, "second disable failed: " + second.error);
        compare(Store.parseDisabled(second.text).length, 2);

        const restored = Store.restore(second.text, "main:Terminal");
        verify(restored.ok, "restore failed: " + restored.error);
        const remaining = Store.parseDisabled(restored.text);
        compare(remaining.length, 1);
        compare(remaining[0].id, "main:Browser");
    }

    function test_disable_all_multiple_ranges_in_one_file_and_restore() {
        // One logical bind can own several source ranges in the same file.
        // A single id must produce one block per range, and restore must put
        // every range back verbatim. Lines are deliberately out of order to
        // prove the batch applies bottom-up against the original numbering.
        const original = testCase.originalText();
        const result = Store.disableAll(original, {
            id: "main:Grouped",
            ranges: [{ line: 4, endLine: 4 }, { line: 3, endLine: 3 }]
        });
        verify(result.ok, "disableAll failed: " + result.error);
        compare(result.error, "");

        const lines = result.text.split("\n");
        compare(lines[2], testCase.startLine("main:Grouped"));
        compare(lines[3], "-- " + testCase.terminalLine());
        compare(lines[4], testCase.endLine());
        compare(lines[5], testCase.startLine("main:Grouped"));
        compare(lines[6], "-- hl.bind(\"SUPER + B\", hl.dsp.exec_cmd(\"firefox\"), {description = \"Browser\"})");
        compare(lines[7], testCase.endLine());

        const blocks = Store.parseDisabled(result.text);
        compare(blocks.length, 2);
        compare(blocks[0].id, "main:Grouped");
        compare(blocks[1].id, "main:Grouped");
        compare(blocks[0].lines.length, 1);
        compare(blocks[0].lines[0], testCase.terminalLine());
        compare(blocks[1].lines.length, 1);
        verify(Store.isDisabled(result.text, "main:Grouped"));

        const restored = Store.restore(result.text, "main:Grouped");
        verify(restored.ok, "restore of the grouped id failed: " + restored.error);
        compare(restored.text, original);
        compare(Store.parseDisabled(restored.text).length, 0);
    }

    function test_disable_all_rejects_overlapping_and_bad_ranges() {
        const original = testCase.originalText();

        const overlap = Store.disableAll(original, {
            id: "main:Overlap",
            ranges: [{ line: 3, endLine: 4 }, { line: 4, endLine: 4 }]
        });
        verify(!overlap.ok, "overlapping ranges must be rejected");
        compare(overlap.error, "overlapping-range");
        compare(overlap.text, original);

        const bad = Store.disableAll(original, {
            id: "main:Bad",
            ranges: [{ line: 3, endLine: 3 }, { line: 2, endLine: 99 }]
        });
        verify(!bad.ok, "an out-of-range member must reject the whole batch");
        compare(bad.error, "bad-range");
        compare(bad.text, original);

        const empty = Store.disableAll(original, { id: "main:Empty", ranges: [] });
        verify(!empty.ok, "an empty batch must be rejected");
        compare(empty.error, "no-ranges");
    }
}
