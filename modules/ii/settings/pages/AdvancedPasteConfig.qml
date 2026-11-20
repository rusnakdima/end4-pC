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
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "content_paste_go"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Advanced Paste")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "wand_stars"
                    text: Translation.tr("Offer AI transform (offline fallback)")
                    checked: Config.options.advancedPaste.showAi
                    onCheckedChanged: { Config.options.advancedPaste.showAi = checked; }
                }
                ConfigSelectionArray {
                    text: Translation.tr("Default transform")
                    icon: "text_fields"
                    showTooltips: true
                    currentValue: Config.options.advancedPaste.defaultTransform
                    onSelected: newValue => { Config.options.advancedPaste.defaultTransform = newValue }
                    options: [
                        { icon: "text_fields", tooltip: Translation.tr("Plain text"), value: "plain" },
                        { icon: "markdown",    tooltip: Translation.tr("Markdown"), value: "markdown" },
                        { icon: "data_object", tooltip: Translation.tr("JSON string"), value: "json_escape" },
                        { icon: "terminal",    tooltip: Translation.tr("Code block"), value: "codeblock" }
                    ]
                }
                ConfigSwitch {
                    buttonIcon: "document_scanner"
                    text: Translation.tr("OCR opens Advanced Paste")
                    checked: Config.options.advancedPaste.ocrOpensPopup
                    onCheckedChanged: { Config.options.advancedPaste.ocrOpensPopup = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "colorize"
                    text: Translation.tr("Color picker opens Advanced Paste")
                    checked: Config.options.advancedPaste.colorPickerOpensPopup
                    onCheckedChanged: { Config.options.advancedPaste.colorPickerOpensPopup = checked; }
                }
                ConfigTextArea {
                    id: aiPromptField
                    Layout.fillWidth: true
                    fieldWidth: 260
                    Layout.minimumWidth: 220
                    buttonIcon: "edit_note"
                    text: Translation.tr("AI transform prompt")
                    value: Config.options.advancedPaste.aiPrompt
                    onValueChanged: { aiPromptDebounce.restart(); }
                    Timer {
                        id: aiPromptDebounce
                        interval: 600
                        repeat: false
                        onTriggered: { Config.options.advancedPaste.aiPrompt = aiPromptField.value; }
                    }
                }
            }
        }

        ContentSection {
            icon: "keyboard"
            shape: MaterialShape.Shape.SoftBurst
            title: Translation.tr("Shortcut")

            ContentSubsection {
                title: Translation.tr("Advanced Paste")
                StyledText {
                    Layout.fillWidth: true
                    text: "SUPER + SHIFT + V — " + Translation.tr("paste clipboard text in another format")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
