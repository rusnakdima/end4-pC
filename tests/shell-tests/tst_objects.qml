import QtQuick
import QtTest
import qs.modules.common.functions

/**
 * Tests for the object helpers.
 *
 * toPlainObject turns a Qt object into something that can be
 * serialised, and applyToQtObject writes a plain object back into a
 * Qt object. Both have to leave the parts they do not know about
 * alone.
 */
TestCase {
    id: testCase
    name: "Objects"
    when: true

    function test_to_plain_object_of_a_plain_object() {
        const result = ObjectUtils.toPlainObject({ a: 1, b: "x" });
        compare(result.a, 1);
        compare(result.b, "x");
        compare(Object.keys(result).length, 2);
    }

    function test_to_plain_object_of_an_array() {
        const result = ObjectUtils.toPlainObject([1, 2, { c: 3 }]);
        verify(Array.isArray(result));
        compare(result.length, 3);
        compare(result[0], 1);
        compare(result[1], 2);
        compare(result[2].c, 3);
    }

    function test_to_plain_object_of_an_empty_array_is_an_empty_array() {
        const result = ObjectUtils.toPlainObject([]);
        verify(Array.isArray(result));
        compare(result.length, 0);
    }

    function test_to_plain_object_of_an_array_like_object() {
        // An object with a length and numeric keys is a list.
        const result = ObjectUtils.toPlainObject({ length: 2, 0: "a", 1: "b" });
        verify(Array.isArray(result));
        compare(result.length, 2);
        compare(result[0], "a");
        compare(result[1], "b");
    }

    function test_to_plain_object_drops_the_qt_object_keys() {
        const result = ObjectUtils.toPlainObject({
            objectName: "x",
            parent: { objectName: "p" },
            children: [],
            keep: 1
        });
        compare(result.keep, 1);
        compare(result.objectName, undefined);
        compare(result.parent, undefined);
        compare(result.children, undefined);
        compare(Object.keys(result).length, 1);
    }

    function test_to_plain_object_of_null_is_null() {
        compare(ObjectUtils.toPlainObject(null), null);
    }

    function test_to_plain_object_of_a_non_object_value_is_that_value() {
        compare(ObjectUtils.toPlainObject(5), 5);
        compare(ObjectUtils.toPlainObject("s"), "s");
    }

    function test_to_plain_object_of_an_empty_object_is_empty() {
        const result = ObjectUtils.toPlainObject({});
        compare(Object.keys(result).length, 0);
    }

    function test_apply_to_qt_object_updates_an_existing_key() {
        const target = { a: 1, b: 2 };
        ObjectUtils.applyToQtObject(target, { a: 9 });
        compare(target.a, 9);
        compare(target.b, 2);
    }

    function test_apply_to_qt_object_ignores_a_key_that_does_not_exist() {
        const target = { a: 1 };
        ObjectUtils.applyToQtObject(target, { a: 9, c: 3 });
        compare(target.a, 9);
        compare(target.c, undefined);
        compare(Object.keys(target).length, 1);
    }

    function test_apply_to_qt_object_replaces_an_array_target_with_an_array_source() {
        const target = [1, 2, 3];
        ObjectUtils.applyToQtObject(target, [4, 5]);
        compare(target.length, 2);
        compare(target[0], 4);
        compare(target[1], 5);
    }

    function test_apply_to_qt_object_clears_an_array_target_with_a_non_array_source() {
        const target = [1, 2, 3];
        ObjectUtils.applyToQtObject(target, { a: 1 });
        compare(target.length, 0);
    }

    function test_apply_to_qt_object_of_a_null_source_changes_nothing() {
        const target = { a: 1 };
        ObjectUtils.applyToQtObject(target, null);
        compare(target.a, 1);
        compare(Object.keys(target).length, 1);
    }

    function test_apply_to_qt_object_of_a_null_target_does_nothing() {
        let threw = false;
        try {
            ObjectUtils.applyToQtObject(null, { a: 1 });
        } catch (e) {
            threw = true;
        }
        verify(!threw);
    }

    function test_apply_to_qt_object_updates_a_nested_object() {
        const target = { o: { x: 1, y: 2 } };
        ObjectUtils.applyToQtObject(target, { o: { x: 5, z: 9 } });
        compare(target.o.x, 5);
        compare(target.o.y, 2);
        compare(target.o.z, undefined);
    }
}
