import QtQuick
import QtTest
import qs
import qs.modules.common

TestCase {
    id: testCase
    name: "ProbeWidget"
    when: true

    function walk(o, path, depth) {
        if (depth > 4 || !o) return;
        let names = [];
        try { names = Object.keys(o); } catch (e) { }
        console.log("PROBEW " + path, o);
        for (let i = 0; i < names.length; ++i) {
            const n = names[i];
            if (n === "parent" || n === "children") continue;
            let v;
            try { v = o[n]; } catch (e) { continue; }
            if (v && typeof v === "object" && v.toString && v.toString().indexOf("QML") >= 0) {
                console.log("PROBEW " + path + "." + n, v);
            }
        }
        try {
            const c = o.children;
            if (c) for (let i = 0; i < c.length; ++i) walk(c[i], path + ".child" + i, depth + 1);
        } catch (e) { }
    }

    function test_probe() {
        const base = "file:///mnt/external/THEMES/end4-pC/";
        const sc = Qt.createComponent(base + "modules/ii/settings/SettingsContent.qml");
        console.log("PROBEW settingsContent status", sc.status, sc.errorString());
        const s2 = Qt.createComponent(base + "modules/ii/settings/Settings.qml");
        console.log("PROBEW settings status", s2.status, s2.errorString());
        if (s2.status === Component.Ready) {
            const so = s2.createObject(null);
            console.log("PROBEW settings obj", so);
            if (so) walk(so, "settings", 0);
        }
        compare(1, 1);
    }
}
