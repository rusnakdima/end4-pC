import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * Tests for the preset service.
 *
 * The service scans three directories - the local presets of the user, the
 * online gallery cache and the imported presets - always with the "*.json"
 * filter and without directories. It hands the preset name to
 * `scripts/presets.sh`, which resolves the preset file as
 * `<preset dir>/<name>.json`, so the test pins the directories of the
 * service against the directories of the shipped script and checks that the
 * resolved apply path of a listed preset points at an existing file.
 */
TestCase {
    id: testCase
    name: "Presets"
    when: true

    readonly property string fixtureName: "zz_tst_fixture_preset"

    // The shipped script, reached relative to the shell root of the harness.
    FileView {
        id: scriptView
        path: Quickshell.shellPath("../../scripts/presets.sh")
    }

    // The fixture that stands for a saved preset.
    FileView {
        id: fixtureView
        path: `${Directories.userPresetsPath}/${testCase.fixtureName}.json`
    }

    function test_the_local_preset_model_scans_json_files_only() {
        compare(Presets.folderModel.nameFilters.join(","), "*.json");
        compare(Presets.folderModel.showDirs, false);
        compare(Presets.folderModel.folder.toString(), Qt.resolvedUrl(Directories.userPresetsPath).toString());
    }

    function test_the_online_and_imported_models_scan_json_files_only() {
        compare(Presets.onlineFolderModel.nameFilters.join(","), "*.json");
        compare(Presets.onlineFolderModel.showDirs, false);
        compare(Presets.importedFolderModel.nameFilters.join(","), "*.json");
        compare(Presets.importedFolderModel.showDirs, false);
    }

    function test_the_scanned_directories_are_the_ones_of_the_user_config() {
        compare(Directories.userPresetsPath, Quickshell.env("HOME") + "/.config/illogical-impulse/presets");
        compare(Directories.shellConfig, Quickshell.env("HOME") + "/.config/illogical-impulse");
    }

    function test_the_apply_script_uses_the_same_directories_as_the_service() {
        wait(800);
        verify(scriptView.loaded);
        const text = scriptView.text();
        verify(text.includes('CONFIG_DIR="$HOME/.config/illogical-impulse"'));
        verify(text.includes('LOCAL_PRESETS_DIR="$CONFIG_DIR/presets"'));
        verify(text.includes('ONLINE_PRESETS_DIR="$HOME/.cache/quickshell/presets"'));
        verify(text.includes('IMPORTED_PRESETS_DIR="$HOME/.cache/quickshell/presets_imported"'));
        // The apply path of a preset is <preset dir>/<name>.json.
        verify(text.includes('preset_file="$PRESETS_DIR/${name}.json"'));
        verify(text.includes("--apply"));
    }

    function test_a_saved_preset_is_listed_and_its_apply_path_exists() {
        // A preset is written into the directory the service scans, the model
        // is refreshed and the preset has to show up in the listing.
        fixtureView.setText('{"fixture": true}');
        wait(600);
        Presets.refresh();
        wait(1200);

        const model = Presets.folderModel;
        let found = -1;
        for (let i = 0; i < model.count; ++i) {
            const name = model.get(i, "fileName");
            verify(name.endsWith(".json"));
            if (name === testCase.fixtureName + ".json") found = i;
        }
        verify(found >= 0);

        // The resolved apply path of the listed preset points at the file.
        compare(model.get(found, "filePath").toString(), `${Directories.userPresetsPath}/${testCase.fixtureName}.json`);
        verify(model.get(found, "filePath").toString().endsWith("/" + testCase.fixtureName + ".json"));

        Quickshell.execDetached(["rm", "-f", `${Directories.userPresetsPath}/${testCase.fixtureName}.json`]);
        Presets.refresh();
    }

    function test_preview_image_of_a_plain_wallpaper() {
        compare(Presets.previewImage({ background: { wallpaperPath: "/home/user/Pictures/a.png" } }), "/home/user/Pictures/a.png");
    }

    function test_preview_image_of_a_video_is_the_thumbnail() {
        compare(Presets.previewImage({ background: { wallpaperPath: "/home/user/Pictures/a.mp4", thumbnailPath: "/home/user/Pictures/a.jpg" } }), "/home/user/Pictures/a.jpg");
        compare(Presets.previewImage({ background: { wallpaperPath: "/home/user/Pictures/a.WEBM" } }), "");
    }

    function test_preview_image_of_a_collage_is_the_leaf_of_the_tree() {
        const tree = JSON.stringify({ t: "branch", a: { t: "leaf", img: "/home/user/Pictures/leaf.png" } });
        compare(Presets.previewImage({ background: { wallpaperPath: "/home/user/Pictures/a.png", collage: { enable: true, tree: tree } } }), "/home/user/Pictures/leaf.png");
    }

    function test_preview_image_of_a_broken_collage_falls_back_to_the_wallpaper() {
        compare(Presets.previewImage({ background: { wallpaperPath: "/home/user/Pictures/a.png", collage: { enable: true, tree: "not json" } } }), "/home/user/Pictures/a.png");
    }

    function test_preview_image_without_a_background_is_empty() {
        compare(Presets.previewImage(undefined), "");
        compare(Presets.previewImage({}), "");
    }
}
