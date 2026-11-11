import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true


    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "palette"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("System Appearance")

            GroupedList {
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "category"
                    text: Translation.tr("Icon theme")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.toOptions(SystemAppearance.iconThemes)
                    currentValue: Config.options.appearance.icons.theme
                    onSelected: newValue => {
                        if (Config.options.appearance.icons.theme === newValue) return
                        Config.options.appearance.icons.theme = newValue
                        SystemAppearance.applyIconScheme()
                    }
                }
                ConfigSwitch {
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Follow color scheme")
                    checked: Config.options.appearance.icons.followScheme
                    onCheckedChanged: {
                        if (Config.options.appearance.icons.followScheme === checked) return
                        Config.options.appearance.icons.followScheme = checked
                        SystemAppearance.applyIconScheme()
                    }
                }
                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Dynamic accent colors")
                    checked: Config.options.appearance.icons.dynamicColor
                    enabled: SystemAppearance.iconCapability() !== "none"
                    onCheckedChanged: {
                        if (Config.options.appearance.icons.dynamicColor === checked) return
                        Config.options.appearance.icons.dynamicColor = checked
                        SystemAppearance.applyIconScheme()
                    }
                }
                ConfigSwitch {
                    buttonIcon: "shield"
                    text: Translation.tr("Prevent Breeze override")
                    checked: Config.options.appearance.icons.preventBreezeOverride
                    onCheckedChanged: {
                        if (Config.options.appearance.icons.preventBreezeOverride === checked) return
                        Config.options.appearance.icons.preventBreezeOverride = checked
                        SystemAppearance.applyIconScheme()
                    }
                }
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Restore KDE icon settings")
                    onClicked: {
                        // Stop re-syncing the wrapper before restoring its
                        // original values, otherwise the next apply would
                        // immediately overwrite them again.
                        Config.options.appearance.icons.preventBreezeOverride = false
                        SystemAppearance.restoreKdeIcons()
                    }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "mouse"
                    text: Translation.tr("Cursor theme")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.toOptions(SystemAppearance.cursorThemes)
                    currentValue: SystemAppearance.cursorTheme
                    onSelected: newValue => SystemAppearance.setCursor(newValue, SystemAppearance.cursorSize)
                }
                ConfigSpinBox {
                    icon: "ads_click"
                    text: Translation.tr("Cursor size")
                    value: SystemAppearance.cursorSize
                    from: 16
                    to: 64
                    stepSize: 2
                    onValueChanged: {
                        if (value !== SystemAppearance.cursorSize) SystemAppearance.setCursor(SystemAppearance.cursorTheme, value)
                    }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "text_fields"
                    text: Translation.tr("System font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.toOptions(SystemAppearance.fonts)
                    currentValue: SystemAppearance.fontFamily
                    onSelected: newValue => SystemAppearance.setFont("ui", newValue, SystemAppearance.fontSize)
                }
                ConfigSpinBox {
                    icon: "format_size"
                    text: Translation.tr("System font size")
                    value: SystemAppearance.fontSize
                    from: 8
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        if (value !== SystemAppearance.fontSize) SystemAppearance.setFont("ui", SystemAppearance.fontFamily, value)
                    }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "terminal"
                    text: Translation.tr("Monospace font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.toOptions(SystemAppearance.fonts)
                    currentValue: SystemAppearance.monoFamily
                    onSelected: newValue => SystemAppearance.setFont("mono", newValue, SystemAppearance.monoSize)
                }
                ConfigSpinBox {
                    icon: "format_size"
                    text: Translation.tr("Monospace font size")
                    value: SystemAppearance.monoSize
                    from: 8
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        if (value !== SystemAppearance.monoSize) SystemAppearance.setFont("mono", SystemAppearance.monoFamily, value)
                    }
                }
            }
        }

        ContentSection {
            icon: "palette"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Color Schemes")

            GroupedList {
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "format_paint"
                    text: Translation.tr("Color scheme")
                    description: Translation.tr("Material follows your wallpaper")
                    fieldWidth: 220
                    fixedWidth: true
                    model: ColorSchemes.schemeOptions()
                    currentValue: ColorSchemes.current
                    onSelected: newValue => ColorSchemes.setScheme(newValue)
                }
                RowLayout {
                    enabled: ColorSchemes.currentData !== null
                    opacity: enabled ? 1 : 0.55
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 10
                    MaterialSymbol {
                        text: "brush"
                        iconSize: Appearance.font.pixelSize.normal + 5
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: Translation.tr("Accent")
                        color: Appearance.colors.colOnLayer0
                    }
                    Item { Layout.fillWidth: true }
                    CustomColorSelectionArray {
                        spacing: 4
                        swatchSize: 36
                        options: ColorSchemes.accentOptions()
                        currentValue: ColorSchemes.currentAccent("primary")
                        onSelected: newValue => ColorSchemes.setAccent("primary", newValue)
                    }
                }
                RowLayout {
                    enabled: ColorSchemes.currentData !== null
                    opacity: enabled ? 1 : 0.55
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 10
                    MaterialSymbol {
                        text: "colors"
                        iconSize: Appearance.font.pixelSize.normal + 5
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: Translation.tr("Secondary")
                        color: Appearance.colors.colOnLayer0
                    }
                    Item { Layout.fillWidth: true }
                    CustomColorSelectionArray {
                        spacing: 4
                        swatchSize: 36
                        options: ColorSchemes.accentOptions()
                        currentValue: ColorSchemes.currentAccent("secondary")
                        onSelected: newValue => ColorSchemes.setAccent("secondary", newValue)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 8
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "add"
                        mainText: Translation.tr("Add scheme")
                        onClicked: ColorSchemes.addScheme()
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "folder_open"
                        mainText: Translation.tr("Open folder")
                        onClicked: ColorSchemes.openFolder()
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "refresh"
                        mainText: Translation.tr("Reload")
                        onClicked: ColorSchemes.reload()
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                    }
                }
            }
        }

        ContentSection {
            icon: "colors"
            title: Translation.tr("Color generation")
            shape: MaterialShape.Shape.VerySunny

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "hardware"
                    text: Translation.tr("Shell & utilities")
                    checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    onCheckedChanged: {
                        if (Config.options.appearance.wallpaperTheming.enableAppsAndShell === checked) return
                        Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked
                        ColorSchemes.regenerateTheme()
                    }
                }
                ConfigSwitch {
                    buttonIcon: "tv_options_input_settings"
                    text: Translation.tr("Qt apps")
                    checked: Config.options.appearance.wallpaperTheming.enableQtApps
                    onCheckedChanged: {
                        if (Config.options.appearance.wallpaperTheming.enableQtApps === checked) return
                        Config.options.appearance.wallpaperTheming.enableQtApps = checked
                        ColorSchemes.regenerateTheme()
                    }
                }
                ConfigSwitch {
                    buttonIcon: "terminal"
                    text: Translation.tr("Terminal")
                    checked: Config.options.appearance.wallpaperTheming.enableTerminal
                    onCheckedChanged: {
                        if (Config.options.appearance.wallpaperTheming.enableTerminal === checked) return
                        Config.options.appearance.wallpaperTheming.enableTerminal = checked
                        ColorSchemes.regenerateTheme()
                    }
                }
                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Keep Konsole color scheme")
                    checked: Config.options.appearance.wallpaperTheming.lockKonsoleColors
                    onCheckedChanged: { Config.options.appearance.wallpaperTheming.lockKonsoleColors = checked }
                }
                ConfigSwitch {
                    buttonIcon: "dark_mode"
                    text: Translation.tr("Force dark mode in terminal")
                    checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                    onCheckedChanged: {
                        if (Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode === checked) return
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked
                        ColorSchemes.regenerateTheme()
                    }
                }
                ConfigSpinBox {
                    icon: "invert_colors"
                    text: Translation.tr("Terminal: Harmony (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: {
                        if (Math.abs(Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100 - value) < 0.01) return
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100
                        ColorSchemes.regenerateTheme()
                    }
                }
                ConfigSpinBox {
                    icon: "gradient"
                    text: Translation.tr("Terminal: Harmonize threshold")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: {
                        if (Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold === value) return
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value
                        ColorSchemes.regenerateTheme()
                    }
                }
                ConfigSpinBox {
                    icon: "format_color_text"
                    text: Translation.tr("Terminal: Foreground boost (%)")
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                    from: 0; to: 100; stepSize: 10
                    onValueChanged: {
                        if (Math.abs(Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100 - value) < 0.01) return
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100
                        ColorSchemes.regenerateTheme()
                    }
                }
            }
        }

        ContentSection {
            icon: "motion_mode"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Transparency")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.appearance.transparency.enable
                    onCheckedChanged: { Config.options.appearance.transparency.enable = checked }
                }
                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Automatic (from wallpaper)")
                    checked: Config.options.appearance.transparency.automatic
                    enabled: Config.options.appearance.transparency.enable
                    onCheckedChanged: { Config.options.appearance.transparency.automatic = checked }
                }
                ConfigSlider {
                    buttonIcon: "layers"
                    text: Translation.tr("Background")
                    enabled: Config.options.appearance.transparency.enable
                            && !Config.options.appearance.transparency.automatic
                    from: 0; to: 0.6
                    stopIndicatorValues: [0.11]
                    value: Config.options.appearance.transparency.backgroundTransparency
                    onValueChanged: {
                        Config.options.appearance.transparency.backgroundTransparency = value
                    }
                }
                ConfigSlider {
                    buttonIcon: "opacity"
                    text: Translation.tr("Content")
                    enabled: Config.options.appearance.transparency.enable
                            && !Config.options.appearance.transparency.automatic
                    from: 0; to: 1
                    stopIndicatorValues: [0.57]
                    value: Config.options.appearance.transparency.contentTransparency
                    onValueChanged: {
                        Config.options.appearance.transparency.contentTransparency = value
                    }
                }
            }
        }

        ContentSection {
            icon: "text_format"
            shape: MaterialShape.Shape.Arrow
            title: Translation.tr("Fonts")

            GroupedList {
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "font_download"
                    text: Translation.tr("Main font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.main)
                    currentValue: Config.options.appearance.fonts.main
                    onSelected: newValue => { Config.options.appearance.fonts.main = newValue }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "123"
                    text: Translation.tr("Numbers font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.numbers)
                    currentValue: Config.options.appearance.fonts.numbers
                    onSelected: newValue => { Config.options.appearance.fonts.numbers = newValue }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "title"
                    text: Translation.tr("Title font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.title)
                    currentValue: Config.options.appearance.fonts.title
                    onSelected: newValue => { Config.options.appearance.fonts.title = newValue }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "space_bar"
                    text: Translation.tr("Monospace font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.monospace)
                    currentValue: Config.options.appearance.fonts.monospace
                    onSelected: newValue => { Config.options.appearance.fonts.monospace = newValue }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "emoticon"
                    text: Translation.tr("Nerd Fonts icons")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.iconNerd)
                    currentValue: Config.options.appearance.fonts.iconNerd
                    onSelected: newValue => { Config.options.appearance.fonts.iconNerd = newValue }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "book_ribbon"
                    text: Translation.tr("Reading font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.reading)
                    currentValue: Config.options.appearance.fonts.reading
                    onSelected: newValue => { Config.options.appearance.fonts.reading = newValue }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "mood_heart"
                    text: Translation.tr("Expressive font")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: SystemAppearance.fontOptions(Config.options.appearance.fonts.expressive)
                    currentValue: Config.options.appearance.fonts.expressive
                    onSelected: newValue => { Config.options.appearance.fonts.expressive = newValue }
                }
            }
        }
    }
}
