pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Column {
    id: root
    required property string categoryName
    readonly property bool isCategorized: categoryName?.length > 0
    property int maxBindWidth: 0
    property real columnSpacing: 40
    property real titleSpacing: 7

    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["SUPER_L", "SUPER_R"]
    property var keySubstitutions: Object.assign({
        "Super": "",
        "Mouse_up": "Scroll ↓",    // ikr, weird
        "Mouse_down": "Scroll ↑",  // trust me bro
        "Mouse:272": "LMB",
        "Mouse:273": "RMB",
        "Mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    // The parser reports the modifiers in the spelling the config uses, the
    // symbol maps below are keyed by the name people recognise.
    property var modNames: ({
        "SUPER": "Super",
        "SHIFT": "Shift",
        "CTRL": "Ctrl",
        "ALT": "Alt",
        "META": "Meta",
    })

    function displayMod(mod) {
        return root.modNames[mod] ?? mod;
    }

    spacing: titleSpacing

    StyledText {
        text: root.isCategorized ? root.categoryName : "Uncategorized"
        font.pixelSize: Appearance.font.pixelSize.title
    }

    Column {
        spacing: 4
        Repeater {
            model: HyprlandKeybinds.bindsFor(root.categoryName)
            delegate: BindLine {
                required property var modelData
                keyData: modelData
                categoryName: root.categoryName
            }
        }
    }

    component BindLine: Row {
        id: bindLine
        required property var keyData
        property string categoryName: ""

        Row {
            spacing: 16
            Row {
                id: modRow
                Component.onCompleted: root.maxBindWidth = Math.max(root.maxBindWidth, implicitWidth)
                width: root.maxBindWidth
                spacing: 4
                Repeater {
                    model: {
                        const modList = (bindLine.keyData.mods ?? []).map(mod => {
                            const name = root.displayMod(mod);
                            return root.keySubstitutions[name] || name;
                        })
                        if (modList.length == 0) return []
                        if (Config.options.cheatsheet.splitButtons) return modList;
                        return [modList.join(" ")]
                    }
                    delegate: KeyboardKey {
                        required property var modelData
                        key: modelData
                        pixelSize: Config.options.cheatsheet.fontSize.key || Appearance.font.pixelSize.smaller
                    }
                }
                StyledText {
                    id: keybindPlus
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !keyBlacklist.includes(bindLine.keyData.key) && (bindLine.keyData.mods ?? []).length > 0
                    text: "+"
                }
                KeyboardKey {
                    id: keybindKey
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !keyBlacklist.includes(bindLine.keyData.key)
                    key: {
                        const k = StringUtils.toTitleCase(bindLine.keyData.key)
                        return root.keySubstitutions[k] || k
                    }
                    pixelSize: Config.options.cheatsheet.fontSize.key || Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                }
            }
            Item {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: commentText.implicitWidth + root.columnSpacing
                implicitHeight: commentText.implicitHeight
                StyledText {
                    id: commentText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                    text: {
                        const regex = new RegExp("\\s*" + bindLine.categoryName + "\\s*:\\s*");
                        return (bindLine.keyData.comment ?? "").replace(regex, "");
                    }
                }
            }
        }
    }
}