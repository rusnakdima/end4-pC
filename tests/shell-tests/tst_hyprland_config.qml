import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * The Hyprland side of the config: the colours that go into the compositor
 * and the options that are read back from it.
 *
 * The live parsing of "hyprctl getoption" lives in services/HyprlandOptions.qml
 * and happens in a jq pipeline, so it is tested against the program that is
 * really in the service instead of a copy of it.
 */
TestCase {
    id: testCase
    name: "HyprlandConfig"
    when: true

    // The service source, read to get the jq program that coerces the
    // options. The test asserts against the program the service runs, so a
    // change in the service cannot pass unnoticed here.
    Process {
        id: sourceProc
        stdout: StdioCollector {
            onStreamFinished: {
                testCase.sourceText = text;
                testCase.sourceDone = true;
            }
        }
    }

    property string sourceText: ""
    property bool sourceDone: false
    property string jqProgram: ""
    property string jqOutput: ""

    // The service source, relative to the config root of the harness.
    function serviceSourcePath() {
        return FileUtils.trimFileProtocol(Quickshell.shellPath("services/HyprlandOptions.qml"));
    }
    property bool jqDone: false

    Process {
        id: jqProc
        stdout: StdioCollector {
            onStreamFinished: {
                testCase.jqOutput = text;
                testCase.jqDone = true;
            }
        }
    }

    // Runs the jq program of the service over a fixture of raw
    // "hyprctl getoption -j" answers.
    function runJq(rawLines) {
        testCase.jqDone = false;
        testCase.jqOutput = "";
        const quoted = rawLines.map(line => "'" + line + "'").join(" ");
        jqProc.command = ["bash", "-c", "printf '%s\\n' " + quoted + " | jq -c '" + testCase.jqProgram + "'"];
        jqProc.running = false;
        jqProc.running = true;
        let waited = 0;
        while (!testCase.jqDone && waited < 4000) {
            wait(50);
            waited += 50;
        }
    }

    function test_to_hypr_color_keeps_only_the_rgb() {
        compare(HyprlandConfig.toHyprColor("#ff0000", 1), "rgba(ff0000ff)");
        compare(HyprlandConfig.toHyprColor("#000000", 1), "rgba(000000ff)");
        compare(HyprlandConfig.toHyprColor("#ffffff", 1), "rgba(ffffffff)");
        // Qt reads an eight digit hex as #AARRGGBB, not #RRGGBBAA, so
        // "#ff000080" is opaque navy rather than a half transparent red.
        // The function only ever receives a #RRGGBB colour, so the shell
        // alpha never reaches the compositor.
        compare(HyprlandConfig.toHyprColor("#ff000080", 1), "rgba(000080ff)");
    }

    function test_to_hypr_color_maps_the_opacity_to_one_alpha_byte() {
        compare(HyprlandConfig.toHyprColor("#ff0000", 0), "rgba(ff000000)");
        compare(HyprlandConfig.toHyprColor("#ff0000", 0.5), "rgba(ff000080)");
        compare(HyprlandConfig.toHyprColor("#ff0000", 1), "rgba(ff0000ff)");
    }

    function test_config_entries_carry_the_stored_options() {
        const entries = HyprlandConfig.configEntries();
        // The values come from the user's config, so they are compared against
        // the config itself instead of against fixed numbers.
        compare(entries["decoration:rounding"], Config.options.hyprland.decoration.rounding);
        compare(entries["decoration:blur:size"], Config.options.hyprland.decoration.blur.size);
        compare(entries["general:border_size"], Config.options.hyprland.general.borderSize);
        compare(entries["general:layout"], Config.options.hyprland.general.layout);
        compare(entries["input:kb_layout"], Config.options.hyprland.input.kbLayout);
        // The booleans are turned into the 0/1 the compositor expects.
        compare(entries["animations:enabled"], Config.options.hyprland.animations.enable ? 1 : 0);
        compare(entries["decoration:blur:enabled"], Config.options.hyprland.decoration.blur.enabled ? 1 : 0);
        verify(entries["input:numlock_by_default"] === 0 || entries["input:numlock_by_default"] === 1);
    }

    function test_config_entries_hold_every_expected_key() {
        const entries = HyprlandConfig.configEntries();
        const expected = [
            "decoration:rounding", "decoration:blur:enabled", "decoration:blur:size",
            "decoration:blur:passes", "decoration:active_opacity", "decoration:inactive_opacity",
            "general:border_size", "general:gaps_in", "general:gaps_out", "general:layout",
            "animations:enabled", "input:kb_layout", "input:numlock_by_default",
            "input:repeat_delay", "input:repeat_rate", "input:follow_mouse",
            "input:touchpad:natural_scroll", "input:touchpad:disable_while_typing",
            "input:touchpad:clickfinger_behavior", "input:touchpad:scroll_factor",
            "misc:focus_on_activate"
        ];
        compare(Object.keys(entries).length, expected.length);
        for (const key of expected) verify(entries[key] !== undefined);
    }

    function test_border_color_entries_are_empty_while_the_option_is_off() {
        // The border colours are off by default, so the matugen colours in
        // colors.lua keep applying and no override is written.
        if (Config.options.hyprland.general.borderColor.enable) return;
        compare(Object.keys(HyprlandConfig.borderColorEntries()).length, 0);
    }

    function test_hyprland_options_get_returns_the_fallback_for_an_unknown_key() {
        HyprlandOptions.values = ({ "misc:vrr": true });
        compare(HyprlandOptions.get("misc:vrr", false), true);
        compare(HyprlandOptions.get("misc:unknown", "fallback"), "fallback");
        compare(HyprlandOptions.get("misc:unknown", 42), 42);
        compare(HyprlandOptions.get("misc:unknown"), undefined);
    }

    function test_hyprland_options_keep_the_type_of_every_value() {
        HyprlandOptions.values = ({
            "a:bool": true,
            "a:int": 7,
            "a:float": 1.5,
            "a:str": "text"
        });
        compare(HyprlandOptions.get("a:bool"), true);
        compare(HyprlandOptions.get("a:int"), 7);
        compare(HyprlandOptions.get("a:float"), 1.5);
        compare(HyprlandOptions.get("a:str"), "text");
        compare(typeof HyprlandOptions.get("a:bool"), "boolean");
        compare(typeof HyprlandOptions.get("a:int"), "number");
        compare(typeof HyprlandOptions.get("a:str"), "string");
    }

    function test_the_option_pipeline_coerces_and_drops() {
        // The coercion of the raw compositor answers happens in the jq
        // program of the service, so the program is taken from the service
        // source and run over a fixture.
        testCase.sourceDone = false;
        testCase.sourceText = "";
        sourceProc.command = ["bash", "-c", "cat " + serviceSourcePath()];
        sourceProc.running = false;
        sourceProc.running = true;
        let waited = 0;
        while (!testCase.sourceDone && waited < 4000) {
            wait(50);
            waited += 50;
        }
        const source = testCase.sourceText;
        verify(source.length > 0);
        const match = /jq -c '([^']*)'/.exec(source);
        verify(match !== null);
        testCase.jqProgram = match[1];
        verify(testCase.jqProgram.length > 0);

        runJq([
            '{"option":"misc:vrr","int":0,"bool":true}',
            '{"option":"general:border_size","int":4}',
            '{"option":"input:sensitivity","float":-0.5}',
            '{"option":"input:kb_variant","str":"[[EMPTY]]"}',
            '{"option":"input:kb_options","str":"grp:alt_shift_toggle"}',
            '{"option":"binds:allow_workspace_cycles","unknown_type":1}'
        ]);

        const lines = testCase.jqOutput.split("\n").filter(line => line.trim().length > 0);
        // The entry whose type is none of bool/int/float/str is dropped.
        compare(lines.length, 5);
        const parsed = lines.map(line => JSON.parse(line));
        const byKey = {};
        for (const entry of parsed) byKey[entry.key] = entry.value;

        compare(byKey["misc:vrr"], true);
        compare(typeof byKey["misc:vrr"], "boolean");
        compare(byKey["general:border_size"], 4);
        compare(typeof byKey["general:border_size"], "number");
        compare(byKey["input:sensitivity"], -0.5);
        compare(typeof byKey["input:sensitivity"], "number");
        // The "[[EMPTY]]" placeholder becomes an empty string.
        compare(byKey["input:kb_variant"], "");
        compare(byKey["input:kb_options"], "grp:alt_shift_toggle");
        verify(byKey["binds:allow_workspace_cycles"] === undefined);
    }
}
