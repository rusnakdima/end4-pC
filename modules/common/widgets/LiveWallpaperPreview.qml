import QtQuick
import Quickshell.Io
import qs.modules.common

/**
 * Local live preview for the wallpaper picker's hovered/selected cell.
 *
 * This is deliberately self-contained: it does not touch the desktop player,
 * the settings banners, the quick panel, or any shared media service. The
 * picker creates it only for the cell under the pointer / keyboard selection,
 * and the Loader destroys it as soon as the selection moves, so at most one
 * extra decode exists while browsing.
 *
 * The still under the cell stays as the fallback if the decode fails.
 */
Item {
    id: root

    property string path: ""
    property int fillMode: Image.PreserveAspectCrop

    readonly property bool isVideo: root.path !== "" && Images.isVideoPath(root.path)
    readonly property string scriptPath: `${Directories.scriptPath}/wallpapers/frame_stream.py`

    property string frameUrl: ""
    property bool frameReady: false
    property bool failed: false
    property int restarts: 0
    property bool closing: false

    function startStream() {
        if (root.closing || !root.isVideo || root.failed || proc.running) return
        proc.command = ["python3", root.scriptPath, root.path]
        proc.startedAt = Date.now()
        proc.running = true
    }

    function stopStream() {
        retry.stop()
        if (proc.running) proc.running = false
        root.frameReady = false
        root.frameUrl = ""
    }

    onPathChanged: {
        root.stopStream()
        root.failed = false
        root.restarts = 0
        if (root.visible) root.startStream()
    }

    onVisibleChanged: {
        if (root.visible) root.startStream()
        else root.stopStream()
    }

    Component.onCompleted: if (root.visible) root.startStream()
    Component.onDestruction: {
        root.closing = true
        root.stopStream()
    }

    Process {
        id: proc
        property real startedAt: 0

        stdout: SplitParser {
            onRead: data => {
                const frame = data.trim()
                if (frame.length === 0) return
                root.restarts = 0
                root.failed = false
                root.frameUrl = `data:image/jpeg;base64,${frame}`
                root.frameReady = true
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.closing || !root.visible) return
            const quick = Date.now() - proc.startedAt < 2000
            root.restarts = quick ? root.restarts + 1 : 0
            if (root.restarts >= 3 || exitCode === 2) {
                root.failed = true
                root.frameReady = false
                return
            }
            retry.interval = Math.min(3000, 300 * Math.pow(2, root.restarts))
            retry.restart()
        }
    }

    Timer {
        id: retry
        repeat: false
        onTriggered: root.startStream()
    }

    Image {
        anchors.fill: parent
        visible: root.frameReady
        source: visible ? root.frameUrl : ""
        fillMode: root.fillMode
        cache: false
        smooth: true
        mipmap: false
    }
}
