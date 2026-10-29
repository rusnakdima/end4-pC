import QtQuick
import QtTest
import qs.services
import qs.modules.common

/**
 * Tests for the settings search index.
 *
 * The index parses every settings page into entries (sections and options)
 * and answers a query with the matching entries, ranked by how well the
 * label matches the query text.
 */
TestCase {
    id: testCase
    name: "SettingsSearch"
    when: true

    // A synthetic settings page. The parser only looks at the type of the
    // enclosing block and at "title: Translation.tr("...")" lines.
    readonly property string fixturePage: [
        "ContentSection {",
        "    title: Translation.tr(\"Zqsection\")",
        "    ConfigSwitch {",
        "        title: Translation.tr(\"Zqalpha\")",
        "    }",
        "    ConfigSwitch {",
        "        title: Translation.tr(\"Zqalpha extra\")",
        "    }",
        "}"
    ].join("\n")

    function test_parse_page_extracts_the_section_and_the_options() {
        const entries = SettingsSearchIndex.parsePage(testCase.fixturePage);

        compare(entries.length, 3);
        compare(entries[0].kind, "section");
        compare(entries[0].label, "Zqsection");
        compare(entries[1].kind, "option");
        compare(entries[1].label, "Zqalpha");
        compare(entries[1].section, "Zqsection");
        compare(entries[2].label, "Zqalpha extra");
    }

    function test_parse_page_of_an_empty_source_is_empty() {
        compare(SettingsSearchIndex.parsePage("").length, 0);
    }

    function test_score_text_prefers_an_exact_match() {
        const tokens = ["zqalpha"];
        compare(SettingsSearchIndex.scoreText("zqalpha", tokens), 100);
        compare(SettingsSearchIndex.scoreText("zqalpha extra", tokens), 60);
        compare(SettingsSearchIndex.scoreText("the zqalpha", tokens), 40);
        compare(SettingsSearchIndex.scoreText("unrelated", tokens), 0);
    }

    function test_the_exact_label_ranks_above_the_longer_one() {
        const saved = SettingsSearchIndex.entriesByPage;
        const patched = Object.assign({}, saved);
        patched["about"] = SettingsSearchIndex.parsePage(testCase.fixturePage);
        SettingsSearchIndex.entriesByPage = patched;

        const results = SettingsSearchIndex.search("zqalpha", 10);
        verify(results.length >= 2);
        compare(results[0].label, "Zqalpha");
        compare(results[0].kind, "option");
        verify(results[0].score > results[1].score);
        compare(results[1].label, "Zqalpha extra");

        SettingsSearchIndex.entriesByPage = saved;
    }

    function test_a_query_that_only_matches_a_section_falls_back_to_the_section() {
        const saved = SettingsSearchIndex.entriesByPage;
        const patched = Object.assign({}, saved);
        patched["about"] = SettingsSearchIndex.parsePage(testCase.fixturePage);
        SettingsSearchIndex.entriesByPage = patched;

        const results = SettingsSearchIndex.search("zqsection", 10);
        verify(results.length >= 1);
        compare(results[0].kind, "section");
        compare(results[0].label, "Zqsection");
        // The section outranks the options that only carry the section name
        // in their section field.
        verify(results[0].score > 100);

        SettingsSearchIndex.entriesByPage = saved;
    }

    function test_an_empty_query_returns_nothing() {
        compare(SettingsSearchIndex.search("", 10).length, 0);
        compare(SettingsSearchIndex.search("   ", 10).length, 0);
    }

    function test_the_limit_caps_the_number_of_results() {
        const saved = SettingsSearchIndex.entriesByPage;
        const patched = Object.assign({}, saved);
        patched["about"] = SettingsSearchIndex.parsePage(testCase.fixturePage);
        SettingsSearchIndex.entriesByPage = patched;

        compare(SettingsSearchIndex.search("zqalpha", 1).length, 1);

        SettingsSearchIndex.entriesByPage = saved;
    }
}
