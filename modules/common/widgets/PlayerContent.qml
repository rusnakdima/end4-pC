pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

Item {
    id: root
    required property MprisPlayer player
    required property QtObject blendedColors
    required property string displayedArtFilePath

    readonly property real pad: 13
    readonly property real gap: 15

    readonly property real artSize: 114
    readonly property real textX: pad + 114 + gap
    readonly property real textWidth: Math.max(0, width - textX - pad)
    readonly property real bottomPad: 13
    readonly property real rowSpacing: 5
    readonly property real rowHeight: Math.max(24, progressBarContainer.implicitHeight)
    readonly property real rowY: root.height - root.bottomPad - root.rowHeight

    component TrackChangeButton: RippleButton {
        implicitWidth: 24
        implicitHeight: 24
        property var iconName
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.blendedColors.colOnSecondaryContainer
            text: iconName
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Rectangle {
        id: artBackground
        x: root.pad
        y: root.pad
        width: root.artSize
        height: root.artSize
        radius: Appearance.rounding.verysmall
        color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: artBackground.width
                height: artBackground.height
                radius: artBackground.radius + 6
            }
        }

        StyledImage {
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            sourceSize.width: 150
            sourceSize.height: 150
        }

        HoverHandler {
            id: artHover
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: artHover.hovered ? 0.6 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animationCurves.expressiveFastSpatialDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.normal
            color: root.blendedColors.colOnLayer0
            text: (root.player?.volume ?? 0) === 0 ? "volume_off" : ((root.player?.volume ?? 0) < 0.5 ? "volume_down" : "volume_up")
            opacity: artHover.hovered ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animationCurves.expressiveFastSpatialDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }
            }
        }

        MaterialDial {
            anchors.fill: parent
            anchors.margins: 14
            colPrimary: root.blendedColors.colPrimary
            colSecondary: root.blendedColors.colSecondaryContainer
            value: root.player?.volume ?? 0
            waveAmplitude: 3.2 * (root.player?.volume ?? 0)
            opacity: artHover.hovered ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animationCurves.expressiveFastSpatialDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }
            }

            onMoved: {
                if (root.player)
                    root.player.volume = value;
            }
        }
    }

    StyledText {
        id: trackTime
        x: root.textX
        y: root.rowY - height - 5
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.blendedColors.colSubtext
        elide: Text.ElideRight
        font.features: { "tnum": 1 }
        text: `${StringUtils.friendlyTimeForSeconds(root.player?.position)} / ${StringUtils.friendlyTimeForSeconds(root.player?.length)}`
    }

    TrackChangeButton {
        id: prevButton
        x: root.textX
        y: root.rowY + (root.rowHeight - height) / 2
        iconName: "skip_previous"
        downAction: () => root.player?.previous()
    }

    Item {
        id: progressBarContainer
        x: prevButton.x + prevButton.width + root.rowSpacing
        y: root.rowY
        width: Math.max(0, rightButtons.x - root.rowSpacing - x)
        implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)
        height: root.rowHeight

        Loader {
            id: sliderLoader
            anchors.fill: parent
            active: root.player?.canSeek ?? false
            sourceComponent: StyledSlider {
                configuration: StyledSlider.Configuration.Wavy
                highlightColor: root.blendedColors.colPrimary
                trackColor: root.blendedColors.colSecondaryContainer
                handleColor: root.blendedColors.colPrimary
                value: root.player?.position / root.player?.length
                onMoved: {
                    root.player.position = value * root.player.length
                }
            }
        }

        Loader {
            id: progressBarLoader
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                right: parent.right
            }
            active: !(root.player?.canSeek ?? false)
            sourceComponent: StyledProgressBar {
                wavy: root.player?.isPlaying
                highlightColor: root.blendedColors.colPrimary
                trackColor: root.blendedColors.colSecondaryContainer
                value: root.player?.position / root.player?.length
            }
        }
    }

    Row {
        id: rightButtons
        x: root.width - root.pad - width
        y: root.rowY + (root.rowHeight - height) / 2
        spacing: root.rowSpacing

        TrackChangeButton {
            iconName: "skip_next"
            downAction: () => root.player?.next()
        }

        TrackChangeButton {
            iconName: "equalizer"
            downAction: () => GlobalStates.equalizerOpen = !GlobalStates.equalizerOpen
        }
    }

    RippleButton {
        id: playPauseButton
        x: root.width - root.pad - width
        y: root.rowY - height - 5
        property real size: 44
        implicitWidth: size
        implicitHeight: size
        downAction: () => root.player.togglePlaying()

        buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal : size / 2
        colBackground: root.player?.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
        colBackgroundHover: root.player?.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
        colRipple: root.player?.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive

        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.player?.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
            text: root.player?.isPlaying ? "pause" : "play_arrow"
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
