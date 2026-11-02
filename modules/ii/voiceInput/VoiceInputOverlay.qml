import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Floating "Listening…" pill shown while speech-to-text is recording or
 * transcribing. It is a layer-shell overlay on the focused screen, on the
 * opposite side of the bar, and never takes keyboard focus, so the transcript
 * is still typed into the window the user was working in.
 */
PanelWindow {
    id: root

    visible: SpeechToText.recording || SpeechToText.transcribing
    color: "transparent"
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

    WlrLayershell.namespace: "quickshell:voiceInput"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: !Config.options.bar.bottom
        bottom: Config.options.bar.bottom
    }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    margins {
        top: Appearance.sizes.barHeight
        bottom: Appearance.sizes.barHeight
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Only the pill itself is clickable; the rest of the layer passes through.
    mask: Region {
        item: pill
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: contentRow.implicitWidth + 28
        implicitHeight: contentRow.implicitHeight + 14
        radius: height / 2
        color: Appearance.colors.colPrimaryContainer

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 10

            MaterialSymbol {
                id: micIcon
                text: SpeechToText.transcribing ? "graphic_eq" : "mic"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnPrimaryContainer

                SequentialAnimation {
                    running: SpeechToText.recording
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: micIcon
                        property: "opacity"
                        from: 1; to: 0.45; duration: 600
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: micIcon
                        property: "opacity"
                        from: 0.45; to: 1; duration: 600
                        easing.type: Easing.InOutSine
                    }
                    onStopped: micIcon.opacity = 1
                }
            }

            StyledText {
                text: SpeechToText.transcribing
                    ? Translation.tr("Transcribing...")
                    : Translation.tr("Listening...")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimaryContainer
            }

            StyledText {
                visible: SpeechToText.recording
                text: SpeechToText.elapsedLabel
                font.pixelSize: Appearance.font.pixelSize.small
                font.features: { "tnum": 1 }
                font.letterSpacing: -0.3
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }
}
