import QtQuick
import QtTest
import Quickshell
import qs.modules.common

/**
 * The directories module resolves the XDG directories of the user and derives
 * the paths the shell writes to from them.
 *
 * The XDG constants are file:// URLs, the derived ones are plain paths.
 */
TestCase {
    id: testCase
    name: "Directories"
    when: true

    property string home: Directories.home

    function test_the_xdg_directories_are_file_urls() {
        verify(Directories.home.startsWith("file://"));
        verify(Directories.config.startsWith("file://"));
        verify(Directories.state.startsWith("file://"));
        verify(Directories.cache.startsWith("file://"));
    }

    function test_the_xdg_directories_are_below_the_home_directory() {
        compare(Directories.config, Directories.home + "/.config");
        compare(Directories.state, Directories.home + "/.local/state/quickshell");
        compare(Directories.cache, Directories.home + "/.cache/quickshell");
    }

    function test_the_derived_paths_are_plain_paths() {
        verify(!Directories.shellConfig.startsWith("file://"));
        verify(!Directories.shellConfigPath.startsWith("file://"));
        verify(!Directories.todoPath.startsWith("file://"));
    }

    function test_the_shell_config_path_is_the_config_file() {
        compare(Directories.shellConfig, Directories.config.replace("file://", "") + "/illogical-impulse");
        compare(Directories.shellConfigPath, Directories.shellConfig + "/" + Directories.shellConfigName);
        compare(Directories.shellConfigName, "config.json");
    }

    function test_the_todo_path_is_below_the_state_directory() {
        compare(Directories.todoPath, Directories.state.replace("file://", "") + "/user/todo.json");
    }

    function test_the_asset_and_script_paths_point_at_the_shell_directory() {
        // The shell path is the directory of the running shell, which under
        // the test harness is tests/shell-tests.
        compare(Directories.assetsPath, Quickshell.shellPath("assets"));
        compare(Directories.scriptPath, Quickshell.shellPath("scripts"));
        verify(Directories.assetsPath.endsWith("tests/shell-tests/assets"));
        verify(Directories.scriptPath.endsWith("tests/shell-tests/scripts"));
    }

    function test_the_media_directories_are_below_the_cache() {
        const cache = Directories.cache.replace("file://", "");
        verify(Directories.favicons.startsWith(cache));
        verify(Directories.favicons.endsWith("/media/favicons"));
        verify(Directories.coverArt.endsWith("/media/coverart"));
    }
}
