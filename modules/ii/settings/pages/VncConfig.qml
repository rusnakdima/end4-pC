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
    property string passwordValue: ""
    property bool advancedOpen: false
    property var draft: page.defaultDraft()

    readonly property var outputOptions: (Vnc.monitors ?? []).map(m => ({
        displayName: `${m.name} · ${m.width}×${m.height}`,
        value: m.name
    }))

    readonly property var logOptions: [
        { displayName: Translation.tr("Error"), value: "error" },
        { displayName: Translation.tr("Warning"), value: "warning" },
        { displayName: Translation.tr("Info"), value: "info" },
        { displayName: Translation.tr("Debug"), value: "debug" },
        { displayName: Translation.tr("Trace"), value: "trace" },
        { displayName: Translation.tr("Quiet"), value: "quiet" }
    ]

    readonly property var captureOptions: [
        { displayName: Translation.tr("All monitors"), icon: "desktop_windows", value: "all" },
        { displayName: Translation.tr("Single monitor"), icon: "monitor", value: "single" }
    ]

    readonly property bool unsupportedMode: !["all", "single"].includes(page.get("capture.mode", "all"))
    readonly property bool pamMode: page.get("network.pam", false)
    readonly property bool authOff: !page.get("network.auth", true)
    readonly property string tailscaleAddress: (Vnc.addresses ?? []).find(a => a.startsWith("100.")) ?? ""

    function detectedOutput() {
        const monitors = (Vnc.monitors ?? []).filter(m => !m.disabled)
        const external = monitors.find(m => !/^(eDP|LVDS|DSI)/i.test(m.name ?? ""))
        return (external ?? monitors[0])?.name ?? ""
    }

    function defaultDraft() {
        return {
            version: 1,
            autostart: false,
            desktopName: "end4-pC",
            capture: { mode: "all", output: page.detectedOutput() },
            encoding: { maxFps: 30, renderCursor: true, gpu: false, disableResizing: false },
            network: {
                address: "127.0.0.1",
                port: 5900,
                auth: true,
                username: Quickshell.env("USER") ?? "",
                pam: false,
                relaxEncryption: false,
                allowBrokenCrypto: false
            },
            input: {
                enabled: true,
                seat: "",
                matchHostKeyboard: true,
                xkb: { layout: "", variant: "", model: "", options: "", rules: "" }
            },
            behavior: {
                lockOnDisconnect: false,
                inhibitIdle: false,
                exitOnDisconnect: false,
                logLevel: "warning"
            }
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
        if (Vnc.settings && Object.keys(Vnc.settings).length > 0) {
            page.draft = page.copy(Vnc.settings)
            // A saved output may be from a monitor that is no longer plugged
            // in; keep the combo on a real, connected output.
            const output = page.get("capture.output", "")
            if (output && !page.outputOptions.some(o => o.value === output)) {
                const fallback = page.detectedOutput()
                if (fallback) page.set("capture.output", fallback)
            }
        } else {
            page.draft = page.defaultDraft()
        }
        page.dirty = false
    }

    function applyDraft() {
        page.dirty = false
        Vnc.apply(page.draft)
    }

    function copyText(text) {
        Quickshell.clipboardText = text
    }

    function sshCommand() {
        const port = page.get("network.port", 5900)
        const bind = page.get("network.address", "127.0.0.1")
        const target = (bind === "0.0.0.0" || bind === "::") ? "127.0.0.1" : bind
        const user = page.get("network.username", "user") || "user"
        return `ssh -L ${port}:${target}:${port} ${user}@${Vnc.hostname || "<host>"}`
    }

    Connections {
        target: Vnc
        function onUpdated() {
            if (!page.dirty)
                page.resetDraft()
        }
    }

    Component.onCompleted: {
        page.resetDraft()
        Vnc.refresh()
        Vnc.monitoring = page.visible
    }

    onVisibleChanged: Vnc.monitoring = visible
    Component.onDestruction: Vnc.monitoring = false

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        NoticeBox {
            Layout.fillWidth: true
            visible: Vnc.helperChecked && !Vnc.helperAvailable
            materialIcon: "extension_off"
            text: Translation.tr("The VNC helper is not installed. Install end4pc-vnc in ~/.local/bin and the wayvnc.service user unit.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Vnc.lastError !== ""
            materialIcon: "error"
            text: Vnc.lastError
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Vnc.statusErrors.length > 0
            materialIcon: "warning"
            text: Vnc.statusErrors.join("\n")
        }

        ContentSection {
            icon: "screen_share"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("VNC")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: Vnc.serviceActive ? "#7fd18b" : "#e08a8a"
                    }

                    StyledText {
                        text: Vnc.serviceActive
                            ? Translation.tr("Running")
                            : (Vnc.status.serviceState || Translation.tr("Stopped"))
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `${page.get("network.address", "127.0.0.1")}:${page.get("network.port", 5900)}`
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        visible: Vnc.clients.length > 0
                        text: Translation.tr("%1 client(s)").arg(Vnc.clients.length)
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Start")
                        materialIcon: "play_arrow"
                        enabled: !Vnc.serviceActive && !Vnc.busy
                        onClicked: Vnc.start()
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Stop")
                        materialIcon: "stop"
                        enabled: Vnc.serviceActive && !Vnc.busy
                        onClicked: Vnc.stop()
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Restart")
                        materialIcon: "restart_alt"
                        enabled: Vnc.serviceActive && !Vnc.busy
                        onClicked: Vnc.restart()
                    }

                    RippleButtonWithIcon {
                        mainText: page.dirty ? Translation.tr("Apply") : Translation.tr("Saved")
                        materialIcon: "save"
                        enabled: page.dirty && !Vnc.busy && Vnc.helperAvailable
                        onClicked: page.applyDraft()
                    }

                    Item { Layout.fillWidth: true }
                }

                ConfigSwitch {
                    buttonIcon: "autorenew"
                    text: Translation.tr("Start at login")
                    checked: page.get("autostart", false)
                    onUserToggled: value => {
                        page.set("autostart", value)
                        Vnc.setAutostart(value)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Vnc.versionText !== ""
                    text: Translation.tr("wayvnc %1").arg(Vnc.versionText)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.dirty && Vnc.clients.length > 0
                    text: Translation.tr("Applying restarts VNC and disconnects the connected client(s).")
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }

        ContentSection {
            icon: "desktop_windows"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Display")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                NoticeBox {
                    Layout.fillWidth: true
                    visible: page.unsupportedMode
                    materialIcon: "warning"
                    text: Translation.tr("The configured capture mode is not supported. Choose All monitors or Single monitor and apply.")
                }

                ConfigSelectionArray {
                    text: Translation.tr("Capture")
                    icon: "screen_share"
                    options: page.captureOptions
                    currentValue: page.unsupportedMode ? "all" : page.get("capture.mode", "all")
                    onSelected: value => page.set("capture.mode", value)
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "monitor"
                    text: Translation.tr("Output")
                    description: Translation.tr("Used when capture is limited to one monitor.")
                    fieldWidth: 280
                    fixedWidth: true
                    model: page.outputOptions
                    currentValue: page.get("capture.output", "")
                    enabled: page.get("capture.mode", "all") === "single"
                    onSelected: value => page.set("capture.output", value)
                }

                ConfigSpinBox {
                    text: Translation.tr("Maximum FPS")
                    icon: "speed"
                    from: 1
                    to: 120
                    stepSize: 1
                    value: page.get("encoding.maxFps", 30)
                    onValueModified: page.set("encoding.maxFps", value)
                }

                ConfigSwitch {
                    buttonIcon: "ads_click"
                    text: Translation.tr("Render cursor")
                    checked: page.get("encoding.renderCursor", true)
                    onUserToggled: value => page.set("encoding.renderCursor", value)
                }

                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("GPU acceleration")
                    checked: page.get("encoding.gpu", false)
                    onUserToggled: value => page.set("encoding.gpu", value)
                }

                ConfigSwitch {
                    buttonIcon: "aspect_ratio"
                    text: Translation.tr("Disable client-driven resizing")
                    checked: page.get("encoding.disableResizing", false)
                    onUserToggled: value => page.set("encoding.disableResizing", value)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("A virtual mirror is not supported by wayvnc on this Hyprland version. Use all monitors or one physical output.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }

        ContentSection {
            icon: "lock"
            shape: MaterialShape.Shape.Pentagon
            title: Translation.tr("Network & Security")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: addressField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Bind address")
                        text: page.get("network.address", "127.0.0.1")
                        onTextEdited: page.set("network.address", text)
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Localhost")
                        materialIcon: "computer"
                        onClicked: {
                            page.set("network.address", "127.0.0.1")
                            addressField.text = "127.0.0.1"
                        }
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Tailscale")
                        materialIcon: "vpn_lock"
                        visible: page.tailscaleAddress !== ""
                        onClicked: {
                            page.set("network.address", page.tailscaleAddress)
                            addressField.text = page.tailscaleAddress
                        }
                    }
                }

                ConfigSpinBox {
                    text: Translation.tr("Port")
                    icon: "lan"
                    from: 1024
                    to: 65535
                    stepSize: 1
                    value: page.get("network.port", 5900)
                    onValueModified: page.set("network.port", value)
                }

                ConfigSwitch {
                    buttonIcon: "enhanced_encryption"
                    text: Translation.tr("TLS authentication")
                    checked: page.get("network.auth", true)
                    onUserToggled: value => page.set("network.auth", value)
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.authOff
                    text: Translation.tr("Authentication is off. This is only safe when the bind address is loopback and the connection goes through an SSH tunnel.")
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("VNC username")
                    text: page.get("network.username", "")
                    onTextEdited: page.set("network.username", text)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: passwordField
                        Layout.fillWidth: true
                        placeholderText: Vnc.hasPassword
                            ? Translation.tr("Password is set — enter a new one")
                            : Translation.tr("Set a VNC password")
                        echoMode: TextInput.Password
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Set")
                        materialIcon: "key"
                        enabled: passwordField.text.length > 0 && !Vnc.busy
                        onClicked: {
                            Vnc.setPassword(passwordField.text)
                            passwordField.text = ""
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Vnc.hasPassword
                        ? Translation.tr("A VNC password is stored in ~/.config/end4-pC/vnc.secret (mode 600).")
                        : Translation.tr("No VNC password is set. The service will refuse to start while authentication is enabled.")
                    color: Vnc.hasPassword ? Appearance.colors.colSubtext : Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                ConfigSwitch {
                    buttonIcon: "verified_user"
                    text: Translation.tr("Use PAM authentication")
                    checked: page.get("network.pam", false)
                    onUserToggled: value => page.set("network.pam", value)
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.pamMode
                    text: Translation.tr("PAM uses the system password instead of the VNC password. TLS is still required.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Vnc.fingerprint !== ""
                            ? Translation.tr("SHA256: %1").arg(Vnc.fingerprint)
                            : Translation.tr("No TLS certificate yet.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Copy")
                        materialIcon: "content_copy"
                        visible: Vnc.fingerprint !== ""
                        onClicked: page.copyText(Vnc.fingerprint)
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Regenerate")
                        materialIcon: "autorenew"
                        enabled: !Vnc.busy
                        onClicked: Vnc.regenerateCertificate()
                    }
                }
            }
        }

        ContentSection {
            icon: "keyboard"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("Input")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                ConfigSwitch {
                    buttonIcon: "mouse"
                    text: Translation.tr("Allow remote input")
                    checked: page.get("input.enabled", true)
                    onUserToggled: value => page.set("input.enabled", value)
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Match the host keyboard layout")
                    checked: page.get("input.matchHostKeyboard", true)
                    onUserToggled: value => page.set("input.matchHostKeyboard", value)
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.get("input.matchHostKeyboard", true)
                    text: Translation.tr("wayvnc will use the active Hyprland layout and options.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    visible: !page.get("input.matchHostKeyboard", true)
                    placeholderText: Translation.tr("XKB layout, e.g. us,ru")
                    text: page.get("input.xkb.layout", "")
                    onTextEdited: page.set("input.xkb.layout", text)
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    visible: !page.get("input.matchHostKeyboard", true)
                    placeholderText: Translation.tr("XKB options, e.g. grp:win_space_toggle")
                    text: page.get("input.xkb.options", "")
                    onTextEdited: page.set("input.xkb.options", text)
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Seat (empty = default)")
                    text: page.get("input.seat", "")
                    onTextEdited: page.set("input.seat", text)
                }
            }
        }

        ContentSection {
            icon: "settings"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Behaviour")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                ConfigSwitch {
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Lock the session when the last client disconnects")
                    checked: page.get("behavior.lockOnDisconnect", false)
                    onUserToggled: value => page.set("behavior.lockOnDisconnect", value)
                }

                ConfigSwitch {
                    buttonIcon: "coffee"
                    text: Translation.tr("Inhibit idle while a client is connected")
                    checked: page.get("behavior.inhibitIdle", false)
                    onUserToggled: value => page.set("behavior.inhibitIdle", value)
                }

                ConfigSwitch {
                    buttonIcon: "logout"
                    text: Translation.tr("Stop VNC when the last client disconnects")
                    checked: page.get("behavior.exitOnDisconnect", false)
                    onUserToggled: value => page.set("behavior.exitOnDisconnect", value)
                }

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "article"
                    text: Translation.tr("Log level")
                    fieldWidth: 180
                    fixedWidth: true
                    model: page.logOptions
                    currentValue: page.get("behavior.logLevel", "warning")
                    onSelected: value => page.set("behavior.logLevel", value)
                }
            }
        }

        ContentSection {
            icon: "devices"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Clients & Outputs")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    visible: Vnc.clients.length === 0
                    text: Translation.tr("No clients connected.")
                    color: Appearance.colors.colSubtext
                }

                Repeater {
                    model: Vnc.clients

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: `${modelData.address ?? Translation.tr("unknown")} · ${modelData.username ?? ""} · ${modelData.id ?? ""}`
                            elide: Text.ElideRight
                        }

                        RippleButtonWithIcon {
                            mainText: Translation.tr("Disconnect")
                            materialIcon: "link_off"
                            onClicked: Vnc.disconnectClient(modelData.id)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Appearance.colors.colOutlineVariant
                    visible: Vnc.outputs.length > 0
                }

                Repeater {
                    model: (Vnc.outputs ?? []).filter(output => !output.headless)

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: `${modelData.name} · ${modelData.width}×${modelData.height}${modelData.focused ? " · focused" : ""}`
                            elide: Text.ElideRight
                        }

                        RippleButtonWithIcon {
                            mainText: Translation.tr("Capture now")
                            materialIcon: "screenshot_monitor"
                            visible: Vnc.serviceActive
                            onClicked: Vnc.outputSet(modelData.name)
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Capture now switches the live stream only. Apply a new capture mode to make it persistent.")
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
                        mainText: Translation.tr("Copy SSH tunnel")
                        materialIcon: "terminal"
                        onClicked: page.copyText(page.sshCommand())
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Copy fingerprint")
                        materialIcon: "fingerprint"
                        enabled: Vnc.fingerprint !== ""
                        onClicked: page.copyText(Vnc.fingerprint)
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("View log")
                        materialIcon: "article"
                        onClicked: Quickshell.execDetached([
                            "kitty", "--hold", "bash", "-lc",
                            "journalctl --user -u wayvnc.service -n 200 --no-pager"
                        ])
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Vnc.serviceInstalled
                        ? Translation.tr("User unit: ~/.config/systemd/user/wayvnc.service")
                        : Translation.tr("The user unit is not installed.")
                    color: Vnc.serviceInstalled ? Appearance.colors.colSubtext : Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
