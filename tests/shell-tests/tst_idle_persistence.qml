import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The settings panel promises that an idle timeout you set is still the one
 * that applies after a restart, so the value has to reach the config file
 * and not just the in-memory adapter. The panel writes the value with
 * `Config.options.hyprland.idle.<key> = seconds`; this test drives exactly
 * that assignment.
 *
 * Like tst_config, everything happens against a sandbox file, so the real
 * ~/.config/illogical-impulse/config.json is never written.
 */
TestCase {
    id: testCase
    name: "IdlePersistence"
    when: true

    property string sandboxPath: "/tmp/end4-pc-shell-test-idle-config.json"
    property string originalPath: ""
    property bool readerLoaded: false

    // A plain reader: it shows what is actually on disk after each write.
    FileView {
        id: reader
        preload: true
        onLoaded: testCase.readerLoaded = true
    }

    function enterSandbox() {
        if (testCase.originalPath === "")
            testCase.originalPath = Config.filePath;
        if (Config.filePath !== testCase.sandboxPath)
            Config.filePath = testCase.sandboxPath;
        reader.path = testCase.sandboxPath;

        // The adapter switches to the sandbox asynchronously: let it load
        // before any value is written, or the load could overwrite the
        // write the test is about to make.
        for (let i = 0; i < 100; ++i) {
            testCase.readerLoaded = false;
            reader.reload();
            tryVerify(() => testCase.readerLoaded, 2000, "sandbox never became readable");
            try { JSON.parse(reader.text()); break; } catch (e) { wait(100); }
        }
        wait(300);
    }

    function leaveSandbox() {
        if (testCase.originalPath !== "" && Config.filePath === testCase.sandboxPath)
            Config.filePath = testCase.originalPath;
    }

    function diskIdle() {
        testCase.readerLoaded = false;
        reader.reload();
        tryVerify(() => testCase.readerLoaded, 2000, "sandbox reload timed out");
        return JSON.parse(reader.text()).hyprland.idle;
    }

    function test_idle_values_reach_the_config_file() {
        enterSandbox();
        const original = {
            lock: Config.options.hyprland.idle.lock,
            screenOff: Config.options.hyprland.idle.screenOff,
            suspend: Config.options.hyprland.idle.suspend
        };

        try {
            // Seed a known baseline first: a value only counts as saved when
            // it shows up in the file, not in the adapter.
            Config.options.hyprland.idle.lock = 301;
            Config.options.hyprland.idle.screenOff = 602;
            Config.options.hyprland.idle.suspend = 903;
            tryVerify(() => {
                try { return diskIdle().lock === 301; } catch (e) { return false; }
            }, 3000, "the seeded idle baseline never reached the file");

            // The assignment the settings rows make on edit.
            Config.options.hyprland.idle.lock = 321;
            tryVerify(() => {
                try { return diskIdle().lock === 321; } catch (e) { return false; }
            }, 3000, "lock=321 never reached the config file");

            // One adapter write carries the whole section: the siblings must
            // not be dropped on the way.
            const idle = diskIdle();
            compare(idle.screenOff, 602);
            compare(idle.suspend, 903);
        } finally {
            Config.options.hyprland.idle.lock = original.lock;
            Config.options.hyprland.idle.screenOff = original.screenOff;
            Config.options.hyprland.idle.suspend = original.suspend;
            tryVerify(() => {
                try { return diskIdle().lock === original.lock; } catch (e) { return false; }
            }, 3000, "the original idle values were not written back");
            leaveSandbox();
        }
    }
}
