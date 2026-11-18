import QtQuick
import QtTest
import "KeybindLabels.js" as KeybindLabels

TestCase {
    id: root
    name: "KeybindLabels"

    function test_managed_label_includes_the_name_and_combo() {
        compare(KeybindLabels.managed({ name: "Terminal", combo: "SUPER + T" }),
                "Terminal (SUPER + T)");
        compare(KeybindLabels.managed({ name: "Terminal", combo: "" }), "Terminal");
        compare(KeybindLabels.managed({ name: "", combo: "SUPER + T" }), "SUPER + T");
    }

    function test_shell_label_uses_every_alias() {
        compare(KeybindLabels.shell({ description: "Overview", action: "overview", combos: ["SUPER", "SUPER + A"] }),
                "Overview (SUPER, SUPER + A)");
        compare(KeybindLabels.shell({ description: "", action: "overview", combos: ["SUPER"] }),
                "overview (SUPER)");
        compare(KeybindLabels.shell({ description: "Overview", action: "", combos: [] }),
                "Overview");
    }

    function test_other_label_falls_back_to_the_combo() {
        compare(KeybindLabels.other({ comment: "Volume up" }, "XF86AudioRaiseVolume"),
                "Volume up (XF86AudioRaiseVolume)");
        compare(KeybindLabels.other({ comment: "" }, "XF86AudioRaiseVolume"),
                "XF86AudioRaiseVolume");
    }
}
