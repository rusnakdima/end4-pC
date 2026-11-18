import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    property bool dirty: false
    property var draft: page.defaultDraft()

    readonly property var backendRows: [
        { name: "waycast", available: !!Cast.backends.waycast },
        { name: "fluxcast", available: !!Cast.backends.fluxcast }
    ]

    readonly property var networkModes: [
        { displayName: Translation.tr("Local"), icon: "lan", value: "local" },
        { displayName: Translation.tr("LAN & Tailscale"), icon: "vpn_key", value: "remote" }
    ]

    readonly property var streamModes: [
        { displayName: Translation.tr("Mirror"), icon: "screen_share", value: "mirror" },
        { displayName: Translation.tr("Extend"), icon: "desktop_windows", value: "extend" }
    ]

    readonly property var codecOptions: [
        { displayName: Translation.tr("Auto"), value: "auto" },
        { displayName: "h264", value: "h264" },
        { displayName: "h264-sw", value: "h264-sw" }
    ]

    readonly property var resolutionOptions: [
        { displayName: "960 × 540", value: "960x540" },
        { displayName: "1280 × 720", value: "1280x720" },
        { displayName: "1920 × 1080", value: "1920x1080" },
        { displayName: Translation.tr("Native"), value: "native" }
    ]

    readonly property var fpsOptions: [
        { displayName: "15", value: 15 },
        { displayName: "20", value: 20 },
        { displayName: "25", value: 25 },
        { displayName: "30", value: 30 }
    ]

    readonly property var bitrateOptions: [
        { displayName: Translation.tr("Low (1M)"), value: "1M" },
        { displayName: Translation.tr("Balanced (2M)"), value: "2M" },
        { displayName: Translation.tr("High (4M)"), value: "4M" }
    ]

    readonly property string networkMode: page.get("networkMode", "local")

    function defaultDraft() {
        return {
            version: 1,
            networkMode: "local",
            target: "",
            sink: "",
            outputRes: "1280x720",
            fps: 20,
            bitrate: "2M",
            protocol: "cast",
            stream: { mode: "mirror", codec: "auto", audio: true }
        }
    }

    function copy(value) {
        return JSON.parse(JSON.stringify(value))
    }

    function get(path, fallback) {
        let obj = page.draft
        const parts = path.split(".")
        for (let i = 0; i < parts.length; ++i) {
            if (obj === undefined || obj === null) return fallback
            obj = obj[parts[i]]
        }
        return obj === undefined || obj === null ? fallback : obj
    }

    function set(path, value) {
        const next = page.copy(page.draft)
        const parts = path.split(".")
        let obj = next
        for (let i = 0; i < parts.length - 1; ++i) {
            if (!obj[parts[i]] || typeof obj[parts[i]] !== "object")
                obj[parts[i]] = {}
            obj = obj[parts[i]]
        }
        obj[parts[parts.length - 1]] = value
        page.draft = next
        page.dirty = true
    }

    function resetDraft() {
        const saved = Cast.config ?? {}
        if (Object.keys(saved).length === 0) {
            page.draft = page.defaultDraft()
        } else {
            // The helper keeps a flat config; the pane stages stream fields
            // under `stream` so the mode/codec/audio controls share a group.
            page.draft = {
                version: saved.version ?? 1,
                networkMode: saved.networkMode ?? "local",
                target: saved.target ?? "",
                sink: saved.sink ?? "",
                outputRes: saved.outputRes ?? "1280x720",
                fps: saved.fps ?? 20,
                bitrate: saved.bitrate ?? "2M",
                protocol: saved.protocol ?? "cast",
                stream: {
                    mode: saved.mode ?? "mirror",
                    codec: saved.codec ?? "auto",
                    audio: saved.audio ?? true
                }
            }
        }
        page.dirty = false
    }

    function applyDraft() {
        page.dirty = false
        Cast.apply(page.draft)
    }

    function copyText(text) {
        Quickshell.clipboardText = text
    }

    function castCommand() {
        const backend = Cast.backends.waycast ? "waycast" : "fluxcast"
        const codec = page.get("stream.codec", "auto")
        const audio = page.get("stream.audio", true) ? "--audio" : "--no-audio"
        if (page.get("networkMode", "local") === "local")
            return `${backend} --sink ${page.get("sink", "") || "<sink>"} --codec ${codec} ${audio}`
        return `${backend} --target ${page.get("target", "") || "<host>"} --codec ${codec} ${audio}`
    }

    function connectSink(sink) {
        const name = sink?.name ?? sink?.description ?? ""
        const address = sink?.address ?? ""
        if (name === "" && address === "") return
        const isWfd = sink?.type === "wfd"
        page.set("networkMode", isWfd ? "local" : "remote")
        page.set("sink", name || address)
        page.set("target", address || name)
        page.set("protocol", isWfd ? "wfd" : (sink?.type === "dlna" ? "dlna" : "cast"))
        page.dirty = false
        Cast.apply(page.draft)
        Cast.start()
    }

    function runSetup() {
        const script = Quickshell.shellPath("optional/cast/install-user.sh")
        Quickshell.execDetached([
            "kitty", "--hold", "bash", "-lc",
            `"${script}"; read -p "Done..."`
        ])
    }

    function viewLog() {
        Cast.setLogLines(200)
        Quickshell.execDetached([
            "kitty", "--hold", "bash", "-lc",
            `${Cast.helperPath} log 200`
        ])
    }

    Connections {
        target: Cast
        function onUpdated() {
            if (!page.dirty)
                page.resetDraft()
        }
    }

    Component.onCompleted: {
        page.resetDraft()
        Cast.refresh()
        Cast.discover(page.networkMode)
        Cast.monitoring = page.visible
    }

    onVisibleChanged: Cast.monitoring = visible
    Component.onDestruction: Cast.monitoring = false

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        NoticeBox {
            Layout.fillWidth: true
            visible: Cast.helperChecked && !Cast.helperAvailable
            materialIcon: "extension_off"
            text: Translation.tr("The Cast helper is not installed. Install end4pc-cast in ~/.local/bin, then run the setup script below.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Cast.lastError !== ""
            materialIcon: "error"
            text: Cast.lastError
        }

        ContentSection {
            icon: "cast"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Setup & readiness")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Backends")
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Repeater {
                        model: page.backendRows

                        delegate: RowLayout {
                            required property var modelData
                            spacing: 6

                            MaterialSymbol {
                                text: modelData.available ? "check" : "close"
                                iconSize: Appearance.font.pixelSize.large
                                color: modelData.available ? "#7fd18b" : "#e08a8a"
                            }

                            StyledText {
                                text: modelData.name
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Cast.doctor.length > 0
                    text: Translation.tr("Checks")
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: Cast.doctor

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: modelData.ok ? "check" : "close"
                            iconSize: Appearance.font.pixelSize.large
                            color: modelData.ok ? "#7fd18b" : "#e08a8a"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.label || Translation.tr("Unknown")
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: (modelData.detail || "") !== ""
                                text: modelData.detail || ""
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Run setup")
                        materialIcon: "settings"
                        onClicked: page.runSetup()
                    }

                    RippleButtonWithIcon {
                        mainText: page.dirty ? Translation.tr("Apply") : Translation.tr("Saved")
                        materialIcon: "save"
                        enabled: page.dirty && !Cast.busy && Cast.helperAvailable
                        onClicked: page.applyDraft()
                    }

                    Item { Layout.fillWidth: true }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.dirty
                    text: Translation.tr("Applying settings restarts the active cast session.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }

        ContentSection {
            icon: "cast_connected"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Scanned devices")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                ConfigSelectionArray {
                    text: Translation.tr("Network")
                    icon: "lan"
                    options: page.networkModes
                    currentValue: page.networkMode
                    onSelected: value => {
                        page.set("networkMode", value)
                        Cast.discover(value)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Scan devices")
                        materialIcon: "refresh"
                        enabled: !Cast.busy
                        onClicked: Cast.discover(page.networkMode)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 device(s) found").arg(Cast.sinks.length)
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Cast.sinks.length === 0
                    text: Translation.tr("No devices found. Install the backend for the selected network, then scan again. You can also enter an address below.")
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: Cast.sinks

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: modelData.type === "wfd" ? "cast" : (modelData.type === "cast" ? "tv" : "desktop_windows")
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.address || Translation.tr("Unknown")
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: (modelData.address || "") !== ""
                                text: `${modelData.type ?? ""} · ${modelData.address ?? ""}`
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                            }
                        }

                        RippleButtonWithIcon {
                            mainText: Translation.tr("Connect")
                            materialIcon: "cast"
                            enabled: !Cast.busy
                            onClicked: page.connectSink(modelData)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Target address (TV IP / host)")
                        text: page.get("target", "")
                        onTextEdited: page.set("target", text)
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Miracast uses Wi-Fi Direct (P2P) and is limited to 1080p. LAN and Tailscale use DLNA/Cast by address and are best effort.")
                }
            }
        }

        ContentSection {
            icon: "screen_share"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Stream")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                ConfigSelectionArray {
                    text: Translation.tr("Mode")
                    icon: "screen_share"
                    options: page.streamModes
                    currentValue: page.get("stream.mode", "mirror")
                    onSelected: value => page.set("stream.mode", value)
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.get("networkMode", "local") !== "local" && page.get("stream.mode", "mirror") === "extend"
                    text: Translation.tr("Extend mode is only meaningful for a local sink.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                ConfigSelectionArray {
                    text: Translation.tr("Codec")
                    icon: "speed"
                    options: page.codecOptions
                    currentValue: page.get("stream.codec", "auto")
                    onSelected: value => page.set("stream.codec", value)
                }

                ConfigSelectionArray {
                    text: Translation.tr("Resolution")
                    icon: "aspect_ratio"
                    options: page.resolutionOptions
                    currentValue: page.get("outputRes", "1280x720")
                    onSelected: value => page.set("outputRes", value)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        text: Translation.tr("Frame rate")
                        icon: "speed"
                        options: page.fpsOptions
                        currentValue: page.get("fps", 20)
                        onSelected: value => page.set("fps", value)
                    }

                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        text: Translation.tr("Bitrate")
                        icon: "network_check"
                        options: page.bitrateOptions
                        currentValue: page.get("bitrate", "2M")
                        onSelected: value => page.set("bitrate", value)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("720p at 20 fps is the tested-safe default for Android TV Cast. Higher settings can make the TV drop the stream.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Audio")
                    checked: page.get("stream.audio", true)
                    onUserToggled: value => page.set("stream.audio", value)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Start")
                        materialIcon: "play_arrow"
                        enabled: !Cast.session.active && !Cast.busy
                        onClicked: Cast.start()
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Stop")
                        materialIcon: "stop"
                        enabled: !!Cast.session.active && !Cast.busy
                        onClicked: Cast.stop()
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Restart")
                        materialIcon: "restart_alt"
                        enabled: !!Cast.session.active && !Cast.busy
                        onClicked: Cast.restart()
                    }

                    Item { Layout.fillWidth: true }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Cast.session.active
                        ? Translation.tr("A cast session is active.")
                        : Translation.tr("No cast session is active.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }

        ContentSection {
            icon: "terminal"
            shape: MaterialShape.Shape.Square
            title: Translation.tr("Diagnostics")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Copy command")
                        materialIcon: "content_copy"
                        onClicked: page.copyText(page.castCommand())
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("View log")
                        materialIcon: "article"
                        onClicked: page.viewLog()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    visible: Cast.logTail !== ""
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    clip: true

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 8
                        contentHeight: logText.implicitHeight
                        clip: true

                        Text {
                            id: logText
                            width: parent.width
                            text: Cast.logTail
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: "monospace"
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Cast.versionText !== ""
                        ? Translation.tr("Cast helper %1").arg(Cast.versionText)
                        : Translation.tr("Cast helper version unknown")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
