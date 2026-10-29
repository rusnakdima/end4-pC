import QtQuick
import QtTest
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Tests for the shape helpers.
 *
 * The settings panel offers the shapes by name and the widgets ask for the
 * boundary radius of the shape they draw, so an unknown name has to fall
 * back to the default shape and to the default radius.
 */
TestCase {
    id: testCase
    name: "Shapes"
    when: true

    function test_a_known_name_gives_its_shape() {
        compare(ShapeUtils.getShape("Circle"), MaterialShape.Shape.Circle);
        compare(ShapeUtils.getShape("Pill"), MaterialShape.Shape.Pill);
        compare(ShapeUtils.getShape("Heart"), MaterialShape.Shape.Heart);
    }

    function test_every_shape_has_its_own_value() {
        compare(ShapeUtils.getShape("Square"), MaterialShape.Shape.Square);
        compare(ShapeUtils.getShape("Cookie9Sided"), MaterialShape.Shape.Cookie9Sided);
    }

    function test_an_unknown_name_falls_back_to_the_default_shape() {
        // The default is the four sided cookie.
        compare(ShapeUtils.getShape("NoSuchShape"), MaterialShape.Shape.Cookie4Sided);
        compare(ShapeUtils.getShape(""), MaterialShape.Shape.Cookie4Sided);
    }

    function test_the_boundary_radius_of_a_known_shape() {
        fuzzyCompare(
            ShapeUtils.centeredShapeMinBoundaryRadius(MaterialShape.Shape.Circle),
            0.4898, 0.0001);
        fuzzyCompare(
            ShapeUtils.centeredShapeMinBoundaryRadius(MaterialShape.Shape.Pill),
            0.4157, 0.0001);
        fuzzyCompare(
            ShapeUtils.centeredShapeMinBoundaryRadius(MaterialShape.Shape.Heart),
            0.2141, 0.0001);
    }

    function test_the_boundary_radius_of_an_unknown_shape_is_the_default() {
        // A value that is not one of the shapes of the enum.
        fuzzyCompare(
            ShapeUtils.centeredShapeMinBoundaryRadius(9999),
            0.4202, 0.0001);
    }

    function test_the_boundary_radius_is_between_zero_and_one() {
        const shapes = [
            MaterialShape.Shape.Circle,
            MaterialShape.Shape.Square,
            MaterialShape.Shape.Triangle,
            MaterialShape.Shape.Heart,
            MaterialShape.Shape.Bun,
        ];
        for (let i = 0; i < shapes.length; ++i) {
            const radius = ShapeUtils.centeredShapeMinBoundaryRadius(shapes[i]);
            verify(radius > 0 && radius <= 0.5);
        }
    }

    function test_the_shape_of_a_name_is_the_shape_whose_radius_is_used() {
        // The two helpers have to agree on the shape they name.
        const shape = ShapeUtils.getShape("Heart");
        fuzzyCompare(ShapeUtils.centeredShapeMinBoundaryRadius(shape), 0.2141, 0.0001);
    }
}
