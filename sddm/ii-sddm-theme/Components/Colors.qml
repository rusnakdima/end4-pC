import QtQuick
pragma Singleton

// Don't edit this file or the script won't pick up the right background
// /home/dmitriy/.config/hypr/custom/scripts/mpvpaper_thumbnails/changli-autumn-umbrella-wuthering-waves-moewalls-com.mp4.jpg
QtObject {
    property real contentTransparency: 0.57
    property real backgroundTransparency: 0
    property color background: "#1a1110"
    property color error: "#ffb4ab"
    property color error_container: "#93000a"
    property color inverse_on_surface: "#392e2c"
    property color inverse_primary: "#904a41"
    property color inverse_surface: "#f1dedc"
    property color on_background: "#f1dedc"
    property color on_error: "#690005"
    property color on_error_container: "#ffdad6"
    property color on_primary: "#561e17"
    property color on_primary_container: "#ffdad5"
    property color on_primary_fixed: "#3b0905"
    property color on_primary_fixed_variant: "#73342b"
    property color on_secondary: "#442926"
    property color on_secondary_container: "#ffdad5"
    property color on_secondary_fixed: "#2c1512"
    property color on_secondary_fixed_variant: "#5d3f3b"
    property color on_surface: "#f1dedc"
    property color on_surface_variant: "#d8c2be"
    property color on_tertiary: "#3e2e04"
    property color on_tertiary_container: "#fcdfa6"
    property color on_tertiary_fixed: "#251a00"
    property color on_tertiary_fixed_variant: "#574419"
    property color outline: "#a08c89"
    property color outline_variant: "#534341"
    property color primary: "#ffb4a9"
    property color primary_container: "#73342b"
    property color primary_fixed: "#ffdad5"
    property color primary_fixed_dim: "#ffb4a9"
    property color scrim: "#000000"
    property color secondary: "#e7bdb6"
    property color secondary_container: "#5d3f3b"
    property color secondary_fixed: "#ffdad5"
    property color secondary_fixed_dim: "#e7bdb6"
    property color shadow: "#000000"
    property color surface: "#1a1110"
    property color surface_bright: "#423735"
    property color surface_container: "#271d1c"
    property color surface_container_high: "#322826"
    property color surface_container_highest: "#3d3231"
    property color surface_container_low: "#231918"
    property color surface_container_lowest: "#140c0b"
    property color surface_dim: "#1a1110"
    property color surface_tint: "#ffb4a9"
    property color surface_variant: "#534341"
    property color tertiary: "#dec38c"
    property color tertiary_container: "#574419"
    property color tertiary_fixed: "#fcdfa6"
    property color tertiary_fixed_dim: "#dec38c"
    property color colSubtext: outline
    property color colLayer0: mix(transparentize(background, backgroundTransparency), primary, 0.99)
    property color colOnLayer0: on_background
    property color colLayer0Hover: transparentize(mix(colLayer0, colOnLayer0, 0.9), contentTransparency)
    property color colLayer0Active: transparentize(mix(colLayer0, colOnLayer0, 0.8), contentTransparency)
    property color colLayer0Border: mix(outline_variant, colLayer0, 0.4)
    property color colLayer1: transparentize(surface_container_low, contentTransparency)
    property color colOnLayer1: on_surface_variant
    property color colOnLayer1Inactive: mix(colOnLayer1, colLayer1, 0.45)
    property color colLayer2: transparentize(surface_container, contentTransparency)
    property color colOnLayer2: on_surface
    property color colOnLayer2Disabled: mix(colOnLayer2, background, 0.4)
    property color colLayer1Hover: transparentize(mix(colLayer1, colOnLayer1, 0.92), contentTransparency)
    property color colLayer1Active: transparentize(mix(colLayer1, colOnLayer1, 0.85), contentTransparency)
    property color colLayer2Hover: transparentize(mix(colLayer2, colOnLayer2, 0.9), contentTransparency)
    property color colLayer2Active: transparentize(mix(colLayer2, colOnLayer2, 0.8), contentTransparency)
    property color colLayer2Disabled: transparentize(mix(colLayer2, background, 0.8), contentTransparency)
    property color colLayer3: transparentize(surface_container_high, contentTransparency)
    property color colOnLayer3: on_surface
    property color colLayer3Hover: transparentize(mix(colLayer3, colOnLayer3, 0.9), contentTransparency)
    property color colLayer3Active: transparentize(mix(colLayer3, colOnLayer3, 0.8), contentTransparency)
    property color colLayer4: transparentize(surface_container_highest, contentTransparency)
    property color colOnLayer4: on_surface
    property color colLayer4Hover: transparentize(mix(colLayer4, colOnLayer4, 0.9), contentTransparency)
    property color colLayer4Active: transparentize(mix(colLayer4, colOnLayer4, 0.8), contentTransparency)
    property color colPrimary: primary
    property color colOnPrimary: on_primary
    property color colPrimaryHover: mix(colPrimary, colLayer1Hover, 0.87)
    property color colPrimaryActive: mix(colPrimary, colLayer1Active, 0.7)
    property color colPrimaryContainer: primary_container
    property color colPrimaryContainerHover: mix(colPrimaryContainer, on_primary_container, 0.9)
    property color colPrimaryContainerActive: mix(colPrimaryContainer, on_primary_container, 0.8)
    property color colSecondary: secondary
    property color colSecondaryHover: mix(secondary, colLayer1Hover, 0.85)
    property color colSecondaryActive: mix(secondary, colLayer1Active, 0.4)
    property color colSecondaryContainer: secondary_container
    property color colSecondaryContainerHover: mix(secondary_container, on_secondary_container, 0.9)
    property color colSecondaryContainerActive: mix(secondary_container, on_secondary_container, 0.54)
    property color colTertiary: tertiary
    property color colTertiaryHover: mix(tertiary, colLayer1Hover, 0.85)
    property color colTertiaryActive: mix(tertiary, colLayer1Active, 0.4)
    property color colTertiaryContainer: tertiary_container
    property color colTertiaryContainerHover: mix(tertiary_container, on_tertiary_container, 0.9)
    property color colTertiaryContainerActive: mix(tertiary_container, colLayer1Active, 0.54)
    property color colSurfaceContainerLow: transparentize(surface_container_low, contentTransparency)
    property color colSurfaceContainer: transparentize(surface_container, contentTransparency)
    property color colSurfaceContainerHigh: transparentize(surface_container_high, contentTransparency)
    property color colSurfaceContainerHighest: transparentize(surface_container_highest, contentTransparency)
    property color colSurfaceContainerHighestHover: mix(surface_container_highest, on_surface, 0.95)
    property color colSurfaceContainerHighestActive: mix(surface_container_highest, on_surface, 0.85)
    property color colOnSurface: on_surface
    property color colOnSurfaceVariant: on_surface_variant
    property color colTooltip: inverse_surface
    property color colOnTooltip: inverse_on_surface
    property color colScrim: transparentize(scrim, 0.5)
    property color colShadow: transparentize(shadow, 0.7)
    property color colOutline: outline
    property color colOutlineVariant: outline_variant
    property color colError: error
    property color colErrorHover: mix(error, colLayer1Hover, 0.85)
    property color colErrorActive: mix(error, colLayer1Active, 0.7)
    property color colOnError: on_error
    property color colErrorContainer: error_container
    property color colErrorContainerHover: mix(error_container, on_error_container, 0.9)
    property color colErrorContainerActive: mix(error_container, on_error_container, 0.7)

    function transparentize(color, percentage) {
        if (percentage === undefined)
            percentage = 1;

        var c = Qt.color(color);
        return Qt.rgba(c.r, c.g, c.b, c.a * (1 - percentage));
    }

    function mix(color1, color2, percentage) {
        if (percentage === undefined)
            percentage = 0.5;

        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);
        return Qt.rgba(percentage * c1.r + (1 - percentage) * c2.r, percentage * c1.g + (1 - percentage) * c2.g, percentage * c1.b + (1 - percentage) * c2.b, percentage * c1.a + (1 - percentage) * c2.a);
    }

}
