pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick

/**
 * pavucontrol-style level meter: a thin bar that fills with the live signal
 * peak (0..1, fed from Quickshell's PwNodePeakMonitor), attacks fast, falls
 * slowly, and keeps a peak-hold tick for ~0.6 s. The fill ramps toward the
 * error colour near clipping.
 *
 * Styled to match StyledProgressBar (M3 rounded track + fill) but drawn by
 * hand: StyledProgressBar animates every value change with elementMoveEnter
 * (400 ms, alwaysRunToEnd), which would smear a 60 fps meter reading into
 * mush and restart a NumberAnimation per row per frame.
 */
Item {
    id: root

    property real peak: 0          // live peak from the monitor, 0..1
    property bool muted: false
    property real barHeight: 4
    property color highlightColor: Appearance?.colors.colPrimary ?? "#685496"
    property color trackColor: Appearance?.m3colors.m3secondaryContainer ?? "#F1D3F9"
    property color dangerColor: Appearance?.colors.colError ?? "#B3261E"
    property color peakTickColor: Appearance?.colors.colOnSurface ?? "#000000"

    // Display state, driven by step() only
    property real level: 0
    property real peakHold: 0
    property real holdTimer: 0

    readonly property real target: (root.muted || !(root.peak > 0)) ? 0 : Math.min(1, root.peak)

    implicitHeight: barHeight
    implicitWidth: 120

    // Fill colour ramps to error over the top fifth of the range
    // (ColorUtils.mix(a, b, p) is p*a + (1-p)*b, so danger is color1)
    readonly property color fillColor: {
        const t = Math.max(0, Math.min(1, (root.level - 0.8) / 0.2));
        return t <= 0 ? root.highlightColor : ColorUtils.mix(root.dangerColor, root.highlightColor, t);
    }

    opacity: root.muted ? 0.4 : 1.0
    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }

    Rectangle { // track
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
    }

    Item { // fill, clipped to the track
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.left: parent.left
            width: parent.width * root.level
            height: parent.height
            radius: height / 2
            color: root.fillColor
        }
    }

    Rectangle { // peak-hold tick
        visible: root.peakHold > 0.01 && root.width > 4
        x: Math.max(0, Math.min(root.width - width, root.width * root.peakHold - width / 2))
        width: 2
        height: parent.height
        radius: 1
        color: root.peakTickColor
        opacity: 0.9
    }

    function step(dt) {
        const tgt = root.target;
        // Fast attack, slow release — a meter that eases symmetrically
        // neither responds to transients nor reads as a level meter.
        const rate = tgt > root.level ? 30 : 6;
        root.level = Math.abs(tgt - root.level) < 0.001
            ? tgt
            : root.level + (tgt - root.level) * Math.min(1, dt * rate);

        if (root.level >= root.peakHold) {
            root.peakHold = root.level;
            root.holdTimer = 0.6;
        } else if (root.holdTimer > 0) {
            root.holdTimer -= dt;
        } else {
            root.peakHold = Math.max(root.level, root.peakHold - dt * 0.5);
        }

        // Settle exactly and stop the ticker when there is nothing to animate
        if (tgt === 0 && root.level < 0.002 && root.peakHold < 0.002) {
            root.level = 0;
            root.peakHold = 0;
            root.holdTimer = 0;
        }
    }

    FrameAnimation {
        id: ticker
        running: root.visible && (root.target > 0 || root.level > 0.001 || root.peakHold > 0.001)
        onTriggered: root.step(Math.min(frameTime, 0.1))
    }
}
