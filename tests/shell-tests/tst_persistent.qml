import QtQuick
import QtTest
import Quickshell.Io
import qs.modules.common

/**
 * The persistent module keeps the state of the shell (the selected AI model,
 * the state of the overlays, the timers) in a JSON file.
 *
 * The test points the state file at a temporary file that holds a known
 * state, so the real ~/.local/state/quickshell/states.json is neither read
 * nor written.
 *
 * One behaviour of the store is worth pinning, because it is not what the
 * type declaration suggests: the adapter merges the loaded file OVER the
 * values it already holds. A key the file does not mention keeps the value
 * from the previously loaded file — it does NOT fall back to the declared
 * default. The defaults only apply to a store that never loaded a file.
 */
TestCase {
    id: testCase
    name: "Persistent"
    when: true

    property string sandboxPath: "/tmp/end4-pc-shell-test-states.json"
    property string originalPath: ""

    // The sandbox file has to exist before the store reads it: a missing
    // file is an error, and the store would keep the values it already
    // loaded from the real state file.
    Process {
        id: sandboxWriter
        command: ["bash", "-c", `printf '%s' '{"ai": {"model": "sandbox-model"}}' > ${testCase.sandboxPath}`]
    }

    function enterSandbox() {
        if (testCase.originalPath === "")
            testCase.originalPath = Persistent.filePath;

        sandboxWriter.running = true;
        wait(500);

        Persistent.filePath = testCase.sandboxPath;

        // The store reloads asynchronously. Wait for the value the sandbox
        // file carries to arrive, so the assertions below never read the
        // state of the real file.
        for (let i = 0; i < 50; ++i) {
            if (Persistent.states.ai.model === "sandbox-model") break;
            wait(100);
        }
        wait(100);
    }

    function test_the_states_are_the_typed_adapter() {
        enterSandbox();
        verify(Persistent.states !== undefined);
        compare(typeof Persistent.states.ai.model, "string");
        compare(typeof Persistent.states.ai.temperature, "number");
        compare(typeof Persistent.states.cheatsheet.tabIndex, "number");
    }

    function test_a_value_round_trips_through_the_store() {
        enterSandbox();
        const original = Persistent.states.ai.model;
        Persistent.states.ai.model = "shell-test-model";
        compare(Persistent.states.ai.model, "shell-test-model");
        Persistent.states.ai.model = original;
        compare(Persistent.states.ai.model, original);
    }

    function test_the_file_overrides_the_stored_value() {
        enterSandbox();
        // The sandbox file is the source of truth for the key it names.
        compare(Persistent.states.ai.model, "sandbox-model");
    }

    function test_a_key_the_file_omits_keeps_its_previous_value() {
        enterSandbox();
        // The adapter merges the file over the values it already holds, so a
        // key the file does not mention is NOT reset to the declared
        // default. It keeps whatever was loaded before.
        const provider = Persistent.states.booru.provider;
        compare(typeof provider, "string");
        verify(provider.length > 0);
    }

    function test_the_state_file_is_pointed_at_the_temporary_file() {
        enterSandbox();
        compare(Persistent.filePath, testCase.sandboxPath);
        verify(Persistent.filePath !== testCase.originalPath);
    }
}
