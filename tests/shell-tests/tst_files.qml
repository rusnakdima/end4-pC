import QtQuick
import QtTest
import Quickshell
import qs.modules.common.functions

/**
 * Tests for the file path helpers.
 *
 * The helpers turn what a user typed into a path or a file url, so
 * the empty input, a path without a protocol and a path with a
 * trailing slash all matter.
 */
TestCase {
    id: testCase
    name: "Files"
    when: true

    function test_trim_file_protocol_removes_the_prefix() {
        compare(FileUtils.trimFileProtocol("file:///home/user/file.txt"), "/home/user/file.txt");
        compare(FileUtils.trimFileProtocol("file://relative/path"), "relative/path");
    }

    function test_trim_file_protocol_leaves_a_path_without_a_prefix_alone() {
        compare(FileUtils.trimFileProtocol("/home/user/file.txt"), "/home/user/file.txt");
        compare(FileUtils.trimFileProtocol(""), "");
    }

    function test_trim_file_protocol_converts_a_non_string_input() {
        // A number is turned into its string form, a path without the
        // prefix is returned unchanged.
        compare(FileUtils.trimFileProtocol(42), "42");
        compare(FileUtils.trimFileProtocol(42), "42");
    }

    function test_trim_file_protocol_of_null_throws() {
        // null has no toString, so the conversion throws. The caller
        // has to guard against null itself.
        let threw = false;
        try {
            FileUtils.trimFileProtocol(null);
        } catch (e) {
            threw = true;
        }
        verify(threw);
    }

    function test_folder_url_expands_the_home_directory() {
        const home = Quickshell.env("HOME");
        compare(FileUtils.folderUrl("~/Downloads"), "file://" + home + "/Downloads");
        compare(FileUtils.folderUrl("~"), "file://" + home);
    }

    function test_folder_url_removes_the_trailing_slash() {
        const home = Quickshell.env("HOME");
        compare(FileUtils.folderUrl("~/Downloads/"), "file://" + home + "/Downloads");
        compare(FileUtils.folderUrl("/tmp/"), "file:///tmp");
    }

    function test_folder_url_of_an_empty_input_is_empty() {
        compare(FileUtils.folderUrl(""), "");
        compare(FileUtils.folderUrl("   "), "");
        compare(FileUtils.folderUrl(null), "");
    }

    function test_folder_url_of_an_absolute_path_keeps_it() {
        compare(FileUtils.folderUrl("/tmp"), "file:///tmp");
    }

    function test_file_name_for_path_takes_the_last_segment() {
        compare(FileUtils.fileNameForPath("/a/b/c.png"), "c.png");
        compare(FileUtils.fileNameForPath("file:///a/b/c.png"), "c.png");
        compare(FileUtils.fileNameForPath("c.png"), "c.png");
    }

    function test_file_name_for_path_of_an_empty_or_non_string_input_is_empty() {
        compare(FileUtils.fileNameForPath(""), "");
        compare(FileUtils.fileNameForPath("/a/b/"), "");
        compare(FileUtils.fileNameForPath(5), "");
    }

    function test_folder_name_for_path_ignores_the_trailing_slash() {
        compare(FileUtils.folderNameForPath("/a/b/"), "b");
        compare(FileUtils.folderNameForPath("/a/b"), "b");
        compare(FileUtils.folderNameForPath("file:///a/b/"), "b");
    }

    function test_folder_name_for_path_of_a_root_or_non_string_input_is_empty() {
        compare(FileUtils.folderNameForPath("/"), "");
        compare(FileUtils.folderNameForPath(""), "");
        compare(FileUtils.folderNameForPath(5), "");
    }

    function test_trim_file_ext_removes_the_extension() {
        compare(FileUtils.trimFileExt("/a/b/c.png"), "/a/b/c");
        compare(FileUtils.trimFileExt("c.png"), "c");
        compare(FileUtils.trimFileExt("/a/b/file"), "/a/b/file");
    }

    function test_trim_file_ext_ignores_a_dot_in_a_directory_name() {
        // The dot of "user.name" is in a directory, so it is not an
        // extension.
        compare(FileUtils.trimFileExt("/home/user.name/file"), "/home/user.name/file");
        compare(FileUtils.trimFileExt("/home/user.name/file.txt"), "/home/user.name/file");
    }

    function test_parent_directory_of_a_nested_path() {
        compare(FileUtils.parentDirectory("/a/b/c"), "/a/b");
        compare(FileUtils.parentDirectory("/a/b"), "/a");
        compare(FileUtils.parentDirectory("file:///a/b/c"), "/a/b");
    }

    function test_parent_directory_of_a_path_with_only_a_name_is_empty() {
        compare(FileUtils.parentDirectory("name"), "");
        compare(FileUtils.parentDirectory("/a"), "");
        compare(FileUtils.parentDirectory("/"), "");
        compare(FileUtils.parentDirectory(""), "");
        compare(FileUtils.parentDirectory(5), "");
    }

    function test_parent_directory_splits_on_a_windows_separator() {
        // The path is split on both separators but joined with a slash.
        compare(FileUtils.parentDirectory("C:\\foo\\bar"), "C:/foo");
        compare(FileUtils.parentDirectory("C:\\foo"), "C:");
    }
}
