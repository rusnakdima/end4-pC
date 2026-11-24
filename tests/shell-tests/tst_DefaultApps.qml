import QtQuick
import QtTest
import qs.services

/**
 * Integration smoke test for the Default apps service: the settings page
 * renders DefaultApps.roles directly, so a dropped role or a lost catalog
 * combo would show an empty row even though the pure store is correct.
 *
 * Read-only on purpose: writing overrides here would change the live config.
 */
TestCase {
    id: testCase
    name: "DefaultApps"
    when: true

    function test_all_eight_roles_are_exposed() {
        compare(DefaultApps.roles.length, 8);
        const ids = DefaultApps.roles.map(role => role.id);
        compare(ids.join(","),
            "terminal,filemanager,browser,codeeditor,office,texteditor,volumemixer,taskmanager");
    }

    function test_a_role_carries_its_binds_without_an_override() {
        const browser = DefaultApps.roleFor("browser");
        verify(browser !== null, "the browser role is missing");
        compare(browser.bindIds.join(","), "apps-5");
        compare(browser.overridden, false, "a clean overlay must not mark a role as overridden");
        compare(DefaultApps.commandFor("apps-5"), "", "a clean overlay has no chosen app command");
        compare(DefaultApps.comboFor("apps-5"), browser.combo);
    }

    function test_an_unknown_role_is_null() {
        compare(DefaultApps.roleFor("not-a-role"), null);
    }

    // The page is loaded dynamically by Settings. A bad property assignment
    // only surfaces at runtime, which is why compiling the file is not enough.
    function test_settings_page_component_loads() {
        const component = Qt.createComponent("modules/ii/settings/pages/DefaultAppsConfig.qml");
        compare(component.status, Component.Ready,
            "settings page failed to load: " + component.errorString());
        const page = component.createObject(null);
        verify(page !== null, "settings page failed to instantiate");
        page.destroy();
    }
}
