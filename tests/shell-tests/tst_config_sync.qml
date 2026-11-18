import QtQuick
import QtTest
import qs.modules.common.widgets
import qs.modules.common

/**
 * The duplicated controls (Settings and another surface) share one config
 * leaf. A Config* editor writes its own checked/value property when the
 * user interacts, which destroys the declarative binding to the config and
 * leaves the copy stale for the rest of the session.
 *
 * ConfigBinding re-applies the config value whenever it changes. These tests
 * create two live copies, self-assign one the way a user interaction does,
 * and assert that an external write reaches both.
 */
TestCase {
    id: testCase
    name: "ConfigSync"
    when: true

    property var host: null

    Component {
        id: hostComponent
        Item {
            id: box
            property bool sharedChecked: false
            property real sharedValue: 5
            property string sharedText: "one"

            property alias plainSwitch: plainSwitch
            property alias guardedSwitch: guardedSwitch
            property alias secondGuardedSwitch: secondGuardedSwitch
            property alias plainSpin: plainSpin
            property alias guardedSpin: guardedSpin
            property alias plainSlider: plainSlider
            property alias guardedSlider: guardedSlider
            property alias plainText: plainText
            property alias guardedText: guardedText
            property alias combo: combo

            readonly property var comboModel: [
                { displayName: "A", value: "a" },
                { displayName: "B", value: "b" },
                { displayName: "C", value: "c" }
            ]

            ConfigSwitch {
                id: plainSwitch
                checked: box.sharedChecked
                onCheckedChanged: box.sharedChecked = checked
            }

            ConfigSwitch {
                id: guardedSwitch
                checked: box.sharedChecked
                onCheckedChanged: {
                    if (checked === box.sharedChecked) return;
                    box.sharedChecked = checked;
                }
                ConfigBinding {
                    target: guardedSwitch
                    property: "checked"
                    value: box.sharedChecked
                }
            }

            ConfigSwitch {
                id: secondGuardedSwitch
                checked: box.sharedChecked
                onCheckedChanged: {
                    if (checked === box.sharedChecked) return;
                    box.sharedChecked = checked;
                }
                ConfigBinding {
                    target: secondGuardedSwitch
                    property: "checked"
                    value: box.sharedChecked
                }
            }

            ConfigSpinBox {
                id: plainSpin
                value: box.sharedValue
                onValueChanged: box.sharedValue = value
            }

            ConfigSpinBox {
                id: guardedSpin
                value: box.sharedValue
                onValueChanged: {
                    if (value === box.sharedValue) return;
                    box.sharedValue = value;
                }
                ConfigBinding {
                    target: guardedSpin
                    property: "value"
                    value: box.sharedValue
                }
            }

            ConfigSlider {
                id: plainSlider
                from: 0
                to: 10
                value: box.sharedValue
                onValueChanged: box.sharedValue = value
            }

            ConfigSlider {
                id: guardedSlider
                from: 0
                to: 10
                value: box.sharedValue
                onValueChanged: {
                    if (value === box.sharedValue) return;
                    box.sharedValue = value;
                }
                ConfigBinding {
                    target: guardedSlider
                    property: "value"
                    value: box.sharedValue
                }
            }

            ConfigTextArea {
                id: plainText
                value: box.sharedText
                onValueChanged: box.sharedText = value
            }

            ConfigTextArea {
                id: guardedText
                value: box.sharedText
                onValueChanged: {
                    if (value === box.sharedText) return;
                    box.sharedText = value;
                }
                ConfigBinding {
                    target: guardedText
                    property: "value"
                    value: box.sharedText
                }
            }

            ConfigComboBox {
                id: combo
                model: box.comboModel
                currentValue: box.sharedText
            }
        }
    }

    function init() {
        testCase.host = hostComponent.createObject(testCase);
        verify(testCase.host !== null, "the sync host failed to create");
    }

    function cleanup() {
        if (testCase.host !== null) {
            testCase.host.destroy();
            testCase.host = null;
        }
    }

    function test_plain_switch_goes_stale() {
        host.sharedChecked = false;
        host.plainSwitch.checked = true;      // ConfigSwitch self-assignment
        host.sharedChecked = true;
        host.sharedChecked = false;
        compare(host.plainSwitch.checked, true, "the plain control should be stale");
    }

    function test_config_binding_switch_follows_external_change() {
        host.sharedChecked = false;
        host.guardedSwitch.checked = true;
        host.sharedChecked = true;
        compare(host.guardedSwitch.checked, true);
        host.sharedChecked = false;
        compare(host.guardedSwitch.checked, false, "ConfigBinding should re-apply");
    }

    function test_two_guarded_switches_converge() {
        host.sharedChecked = false;
        host.guardedSwitch.checked = true;    // one surface changes it
        compare(host.sharedChecked, true);
        compare(host.secondGuardedSwitch.checked, true, "the other surface follows");
        host.secondGuardedSwitch.checked = false;
        compare(host.sharedChecked, false);
        compare(host.guardedSwitch.checked, false);
    }

    function test_plain_spin_goes_stale() {
        host.sharedValue = 5;
        host.plainSpin.value = 8;
        host.sharedValue = 9;
        compare(host.plainSpin.value, 8, "the plain control should be stale");
    }

    function test_config_binding_spin_follows_external_change() {
        host.sharedValue = 5;
        host.guardedSpin.value = 8;
        host.sharedValue = 9;
        compare(host.guardedSpin.value, 9, "ConfigBinding should re-apply");
    }

    function test_plain_slider_goes_stale() {
        host.sharedValue = 5;
        wait(150);
        host.plainSlider.value = 3;
        wait(150);
        host.sharedValue = 7;
        wait(150);
        compare(host.plainSlider.value, 3, "the plain control should be stale");
    }

    function test_config_binding_slider_follows_external_change() {
        host.sharedValue = 5;
        wait(150);
        host.guardedSlider.value = 3;
        wait(150);
        host.sharedValue = 7;
        wait(150);
        compare(host.guardedSlider.value, 7, "ConfigBinding should re-apply");
    }

    function test_plain_text_goes_stale() {
        host.sharedText = "one";
        host.plainText.value = "typed";
        host.sharedText = "two";
        compare(host.plainText.value, "typed", "the plain control should be stale");
    }

    function test_config_binding_text_follows_external_change() {
        host.sharedText = "one";
        host.guardedText.value = "typed";
        host.sharedText = "two";
        compare(host.guardedText.value, "two", "ConfigBinding should re-apply");
    }

    function test_combo_index_follows_current_value_after_selection() {
        // ConfigComboBox keeps its own currentIndex in sync: the user picks
        // an item (imperative write), then currentValue changes externally.
        host.sharedText = "a";
        compare(host.combo.comboBox.currentIndex, 0);
        host.combo.comboBox.currentIndex = 2;
        host.sharedText = "c";
        compare(host.combo.comboBox.currentIndex, 2);
        host.sharedText = "a";
        compare(host.combo.comboBox.currentIndex, 0, "the widget should re-apply the index");
    }
}
