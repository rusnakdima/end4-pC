//@ pragma UseQApplication
//
// Quickshell-hosted test harness for the end4-pC config.
//
// The services of this config can only be loaded inside a live Quickshell
// process: qmltestrunner cannot resolve "import Quickshell". So the tests
// run here, in a real shell, and this file aggregates their results.
//
// The shell prints one machine readable line per test file
//
//   TESTFILE <file> passed=<n> failed=<n> skipped=<n>
//
// and exactly one summary line
//
//   SHELL_TEST_RESULT passed=<n> failed=<n> skipped=<n> total=<n>
//
// then exits with 1 when a file failed. tests/run-shell-tests.sh reads the
// summary line and decides the exit code of the run, so a shell that exits
// without printing the line is a failure and never a pass.
//
// Two details of the QtTest module matter here:
//
//   * The test cases are created with Qt.createComponent() and not with a
//     Loader. ShellRoot is not an Item, so a Loader below it never creates
//     its delegate and the test file would silently never run.
//
//   * TestCase quits the whole application as soon as the last registered
//     test case is done, which would kill the shell before the summary is
//     printed. The keeper below stays registered with the test logger and
//     is never queued, so the logger never runs out of test cases.
//
import QtQuick
import QtTest
import Quickshell

ShellRoot {
    id: root

    // One entry per test file. tests/functional-coverage.sh keeps this list
    // and the files on disk in sync.
    property var testFiles: [
        "tst_strings.qml", "tst_numbers.qml", "tst_colors.qml", "tst_files.qml",
        "tst_dates.qml", "tst_objects.qml", "tst_notifications.qml", "tst_shapes.qml",
        "tst_fuzzy.qml", "tst_levenshtein.qml", "tst_keycombos.qml", "tst_translation.qml",
        "tst_appearance.qml", "tst_images.qml", "tst_config.qml", "tst_hyprland_config.qml",
        "tst_hyprland_keybinds.qml", "tst_wallpapers.qml", "tst_notifications_model.qml",
        "tst_updates.qml", "tst_weather.qml", "tst_mpris.qml", "tst_presets.qml",
        "tst_settings_search.qml", "tst_online_wallpapers.qml", "tst_ai.qml",
        "tst_speech_to_text.qml", "tst_bar_content.qml", "tst_bar_group.qml",
        "tst_thumbnail_image.qml", "tst_wallpaper_item.qml", "tst_settings_card.qml",
        "tst_xkb_indicator.qml", "tst_global_states.qml", "tst_persistent.qml",
        "tst_directories.qml"
    ]

    property int doneCount: 0
    property int passed: 0
    property int failed: 0
    property int skipped: 0

    // The files to run. QUICKSHELL_TEST_FILES overrides the list, so a
    // single test file can be run while it is being written:
    //
    //   QUICKSHELL_TEST_FILES=tst_colors.qml qs -p tests/shell-tests
    //
    readonly property var selectedFiles: {
        const override = Quickshell.env("QUICKSHELL_TEST_FILES");
        if (!override) return root.testFiles;
        return override.split(",").map(name => name.trim()).filter(name => name.length > 0);
    }

    // name -> { pass: int, fail: int, skip: int }
    property var perFile: ({})

    // Never queued, so it never runs, but it stays registered with the test
    // logger and keeps the logger from quitting the application.
    TestCase {
        id: keeper
        name: "HarnessKeeper"
        when: false
    }

    Component.onCompleted: root.start()

    function start() {
        for (let i = 0; i < root.selectedFiles.length; ++i) {
            root.loadTest(root.selectedFiles[i]);
        }
    }

    function loadTest(name) {
        const component = Qt.createComponent(Qt.resolvedUrl(name));
        if (component.status === Component.Error) {
            root.recordFailure(name, component.errorString());
            return;
        }

        const test = component.createObject(null);
        if (test === null) {
            root.recordFailure(name, "the test case could not be created");
            return;
        }

        root.captureFailures(name, test);

        test.completedChanged.connect(function() {
            root.onTestCompleted(name, test);
        });
    }

    // The test counters say how many assertions failed, but not which one.
    // The QtTest result object is wrapped in a proxy that reports every
    // failed assertion, so a failing run names the assertion instead of
    // just counting it.
    function captureFailures(name, test) {
        const results = test.qtest_results;
        if (results === null || results === undefined) return;

        const proxy = new Proxy(results, {
            get(target, property) {
                const value = target[property];

                if (property === "compare") {
                    return function(success, message, actual, expected, location, line) {
                        if (!success) {
                            root.reportAssertion(name, message, actual, expected, location, line);
                        }
                        return target.compare(success, message, actual, expected, location, line);
                    };
                }

                if (property === "verify") {
                    return function(success, message, location, line) {
                        if (!success) {
                            root.reportAssertion(name, message, "", "", location, line);
                        }
                        return target.verify(success, message, location, line);
                    };
                }

                if (property === "fail") {
                    return function(message, location, line) {
                        root.reportAssertion(name, message, "", "", location, line);
                        return target.fail(message, location, line);
                    };
                }

                return value;
            }
        });

        test.qtest_results = proxy;
    }

    function reportAssertion(name, message, actual, expected, location, line) {
        const where = location === undefined || location === null ? "" : (" " + String(location).split("/").pop() + ":" + line);
        console.log("ASSERTION_FAILED " + name + " " + (message === undefined ? "" : message)
            + " actual=" + actual + " expected=" + expected + where);
    }

    function recordFailure(name, message) {
        root.perFile[name] = { pass: 0, fail: 1, skip: 0 };
        console.log("TESTFILE " + name + " passed=0 failed=1 skipped=0 error=" + JSON.stringify(message));
        root.failed += 1;
        root.doneCount += 1;
        root.finish();
    }

    function onTestCompleted(name, test) {
        if (root.perFile[name] !== undefined) return; // already counted

        // The counters live on the result object of the test case.
        const result = test.qtest_results;
        const passed = result.passCount;
        const failed = result.failCount;
        const skipped = result.skipCount;

        root.perFile[name] = { pass: passed, fail: failed, skip: skipped };
        console.log("TESTFILE " + name + " passed=" + passed + " failed=" + failed + " skipped=" + skipped);

        if (failed > 0) {
            root.failed += 1;
        } else if (skipped > 0 && passed === 0) {
            root.skipped += 1;
        } else {
            root.passed += 1;
        }

        root.doneCount += 1;
        root.finish();
    }

    function finish() {
        if (root.doneCount < root.selectedFiles.length) return;

        console.log("SHELL_TEST_RESULT passed=" + root.passed + " failed=" + root.failed + " skipped=" + root.skipped + " total=" + root.selectedFiles.length);
        Qt.exit(root.failed > 0 ? 1 : 0);
    }
}
