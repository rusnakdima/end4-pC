import QtQuick
import QtTest

/**
 * The typed capture fallback lives on the page, but the field lives in the
 * inline KeybindForm. The function therefore takes the text as an argument;
 * a page-level reference to the field's id would throw ReferenceError.
 */
TestCase {
    id: testCase
    name: "KeyboardConfigTypedCombo"
    when: true

    property var page: null

    function initTestCase() {
        const component = Qt.createComponent("modules/ii/settings/pages/KeyboardConfig.qml");
        verify(component.status === Component.Ready,
            "KeyboardConfig did not load: " + component.errorString());
        testCase.page = component.createObject(testCase);
        verify(testCase.page !== null, "KeyboardConfig could not be created");
    }

    function cleanupTestCase() {
        if (testCase.page !== null) testCase.page.destroy();
    }

    function test_typed_combo_sets_the_draft() {
        testCase.page.formCombo = "";
        testCase.page.applyTypedCombo("super+i");
        compare(testCase.page.formCombo, "SUPER + I");
        compare(testCase.page.formError, "");
    }

    function test_unparseable_typed_text_keeps_the_draft() {
        testCase.page.formCombo = "SUPER + T";
        testCase.page.applyTypedCombo("definitely not a combo");
        compare(testCase.page.formCombo, "SUPER + T");
    }
}
