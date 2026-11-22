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
    readonly property string bindMode: page.get("network.bindMode", "auto")
    property bool portEdited: false
    readonly property string tailscaleAddress: (Vnc.detectedAddresses ?? []).find(a => a.kind === "tailscale")?.address ?? (Vnc.addresses ?? []).find(a => a.startsWith("100.")) ?? ""

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
                bindMode: "auto",
                address: "127.0.0.1",
                port: Vnc.configPort || 5900,
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
                lockOnDisconnect: true,
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

    function syncPortFromLive() {
        const live = Vnc.configPort
        if (live > 0 && !page.portEdited && page.get("network.port", live) !== live) {
            const next = page.copy(page.draft)
            next.network.port = live
            page.draft = next
        }
    }

    function applyDraft() {
        page.dirty = false
        Vnc.apply(page.draft)
    }

    function copyText(text) {
        Quickshell.clipboardText = text
    }

    function listenSummary() {
        const port = Vnc.configPort || page.get("network.port", 5900)
        const list = Vnc.listenAddresses ?? []
        if (list.length > 0)
            return list.map(address => `${address}:${port}`).join(", ")
        return `${page.get("network.address", "127.0.0.1")}:${port}`
    }

    function sshCommand() {
        const port = Vnc.configPort || page.get("network.port", 5900)
        const bind = page.bindMode === "auto"
            ? "127.0.0.1"
            : page.get("network.address", "127.0.0.1")
        const target = (bind === "0.0.0.0" || bind === "::") ? "127.0.0.1" : bind
        const user = page.get("network.username", "user") || "user"
        return `ssh -L ${port}:${target}:${port} ${user}@${Vnc.hostname || "<host>"}`
    }


    // ---- connected-client monitoring helpers ----------------------------

    // Per-client "Details" spoiler state. Keys are wayvnc client ids.
    property var expandedClients: ({})

    function toggleClientDetails(id) {
        const next = page.copy(page.expandedClients)
        next[id] = !next[id]
        page.expandedClients = next
    }

    function clientName(client) {
        return client.username || Translation.tr("Unnamed client")
    }

    function uptimeText(seconds) {
        const n = Number(seconds) || 0
        if (n < 60) return Translation.tr("%1s").arg(n)
        if (n < 3600) return Translation.tr("%1m").arg(Math.floor(n / 60))
        if (n < 86400) return Translation.tr("%1h %2m").arg(Math.floor(n / 3600)).arg(Math.floor((n % 3600) / 60))
        return Translation.tr("%1d %2h").arg(Math.floor(n / 86400)).arg(Math.floor((n % 86400) / 3600))
    }

    function kindLabel(kind) {
        switch (kind) {
        case "loopback": return Translation.tr("This machine")
        case "tailscale": return Translation.tr("Tailscale")
        case "lan": return Translation.tr("Local network")
        case "vpn": return Translation.tr("VPN")
        case "remote": return Translation.tr("Remote")
        default: return Translation.tr("Unknown")
        }
    }

    function kindIcon(kind) {
        switch (kind) {
        case "loopback": return "computer"
        case "tailscale": return "vpn_key"
        case "lan": return "lan"
        case "vpn": return "public"
        case "remote": return "public"
        default: return "help"
        }
    }

    function clientDetailRows(client) {
        return [
            { label: Translation.tr("User"), value: client.username || "—" },
            { label: Translation.tr("Address"), value: client.address || "—" },
            { label: Translation.tr("Via"), value: page.kindLabel(client.kind) + (client.interface ? " · " + client.interface : "") },
            { label: Translation.tr("Seat"), value: client.seat || "—" },
            { label: Translation.tr("Client ID"), value: client.id || "—" },
            { label: Translation.tr("Connected"), value: client.connectedSince || "—" },
            { label: Translation.tr("Uptime"), value: page.uptimeText(client.uptimeSeconds) }
        ]
    }

    readonly property var outputRows: Vnc.wayvncOutputs.length > 0
        ? Vnc.wayvncOutputs
        : (Vnc.outputs ?? []).filter(output => !output.headless && !output.disabled)

    Connections {
        target: Vnc
        function onUpdated() {
            if (!page.dirty)
                page.resetDraft()
            page.syncPortFromLive()
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
                spacing: 10

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
                        text: page.listenSummary()
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
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
                    id: autostartSwitch
                    buttonIcon: "autorenew"
                    text: Translation.tr("Start at login")
                    checked: page.get("autostart", false)
                    onUserToggled: value => {
                        page.set("autostart", value)
                        Vnc.setAutostart(value)
                    }

                    Binding {
                        target: autostartSwitch
                        property: "checked"
                        value: page.get("autostart", false)
                        restoreMode: Binding.RestoreBinding
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
                    id: fpsSpin
                    text: Translation.tr("Maximum FPS")
                    icon: "speed"
                    from: 1
                    to: 120
                    stepSize: 1
                    value: page.get("encoding.maxFps", 30)
                    onValueModified: page.set("encoding.maxFps", value)

                    Binding {
                        target: fpsSpin
                        property: "value"
                        value: page.get("encoding.maxFps", 30)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: cursorSwitch
                    buttonIcon: "ads_click"
                    text: Translation.tr("Render cursor")
                    checked: page.get("encoding.renderCursor", true)
                    onUserToggled: value => page.set("encoding.renderCursor", value)

                    Binding {
                        target: cursorSwitch
                        property: "checked"
                        value: page.get("encoding.renderCursor", true)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: gpuSwitch
                    buttonIcon: "memory"
                    text: Translation.tr("GPU acceleration")
                    checked: page.get("encoding.gpu", false)
                    onUserToggled: value => page.set("encoding.gpu", value)

                    Binding {
                        target: gpuSwitch
                        property: "checked"
                        value: page.get("encoding.gpu", false)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: resizeSwitch
                    buttonIcon: "aspect_ratio"
                    text: Translation.tr("Disable client-driven resizing")
                    checked: page.get("encoding.disableResizing", false)
                    onUserToggled: value => page.set("encoding.disableResizing", value)

                    Binding {
                        target: resizeSwitch
                        property: "checked"
                        value: page.get("encoding.disableResizing", false)
                        restoreMode: Binding.RestoreBinding
                    }
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

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Auto binds loopback, Ethernet/Wi-Fi and Tailscale. Custom uses one address.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                ConfigSelectionArray {
                    text: Translation.tr("Bind mode")
                    icon: "lan"
                    options: [
                        { displayName: Translation.tr("Auto"), icon: "hub", value: "auto" },
                        { displayName: Translation.tr("Custom"), icon: "settings_ethernet", value: "custom" }
                    ]
                    currentValue: page.bindMode
                    onSelected: value => page.set("network.bindMode", value)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.bindMode === "auto"
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Automatically binds:")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    Repeater {
                        model: Vnc.detectedAddresses
                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            text: `${modelData.kind === "loopback" ? "Localhost" : modelData.kind === "tailscale" ? "Tailscale" : "LAN"} · ${modelData.address}${modelData.interface ? " (" + modelData.interface + ")" : ""}`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("The firewall must allow TCP %1 on the Ethernet/Wi-Fi and Tailscale interfaces.").arg(Vnc.configPort || page.get("network.port", 5900))
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: page.bindMode === "custom"

                    MaterialTextField {
                        id: addressField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Bind address")
                        text: page.get("network.address", "127.0.0.1")
                        onTextEdited: page.set("network.address", text)

                        Binding {
                            target: addressField
                            property: "text"
                            value: page.get("network.address", "127.0.0.1")
                            restoreMode: Binding.RestoreBinding
                        }
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Localhost")
                        materialIcon: "computer"
                        onClicked: {
                            page.set("network.bindMode", "custom")
                            page.set("network.address", "127.0.0.1")
                            addressField.text = "127.0.0.1"
                        }
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("LAN + VPN")
                        materialIcon: "public"
                        onClicked: {
                            page.set("network.bindMode", "custom")
                            page.set("network.address", "0.0.0.0")
                            addressField.text = "0.0.0.0"
                        }
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Tailscale")
                        materialIcon: "vpn_lock"
                        visible: page.tailscaleAddress !== ""
                        onClicked: {
                            page.set("network.bindMode", "custom")
                            page.set("network.address", page.tailscaleAddress)
                            addressField.text = page.tailscaleAddress
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.bindMode === "custom" && page.get("network.address", "127.0.0.1") === "0.0.0.0"
                    text: Translation.tr("All interfaces: reachable from the local network and over Tailscale/VPN. Keep TLS authentication and a strong password enabled, or restrict access with a firewall.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                ConfigSpinBox {
                    id: portSpin
                    text: Translation.tr("Port")
                    icon: "lan"
                    from: 1024
                    to: 65535
                    stepSize: 1
                    value: page.get("network.port", Vnc.configPort || 5900)
                    onValueModified: {
                        page.portEdited = true
                        page.set("network.port", value)
                    }

                    Binding {
                        target: portSpin
                        property: "value"
                        value: page.get("network.port", Vnc.configPort || 5900)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: Vnc.configPort > 0

                    StyledText {
                        Layout.fillWidth: true
                        text: page.get("network.port", Vnc.configPort) !== Vnc.configPort
                            ? Translation.tr("Live port: %1 — staged change needs Apply.").arg(Vnc.configPort)
                            : Translation.tr("Live port: %1").arg(Vnc.configPort)
                        color: page.get("network.port", Vnc.configPort) !== Vnc.configPort
                            ? Appearance.colors.colError
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Use live port")
                        materialIcon: "sync"
                        visible: page.get("network.port", Vnc.configPort) !== Vnc.configPort
                        onClicked: {
                            page.portEdited = false
                            const next = page.copy(page.draft)
                            next.network.port = Vnc.configPort
                            page.draft = next
                        }
                    }
                }

                ConfigSwitch {
                    id: tlsSwitch
                    buttonIcon: "enhanced_encryption"
                    text: Translation.tr("TLS authentication")
                    checked: page.get("network.auth", true)
                    onUserToggled: value => page.set("network.auth", value)

                    Binding {
                        target: tlsSwitch
                        property: "checked"
                        value: page.get("network.auth", true)
                        restoreMode: Binding.RestoreBinding
                    }
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
                    id: usernameField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("VNC username")
                    text: page.get("network.username", "")
                    onTextEdited: page.set("network.username", text)

                    Binding {
                        target: usernameField
                        property: "text"
                        value: page.get("network.username", "")
                        restoreMode: Binding.RestoreBinding
                    }
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
                    id: pamSwitch
                    buttonIcon: "verified_user"
                    text: Translation.tr("Use PAM authentication")
                    checked: page.get("network.pam", false)
                    onUserToggled: value => page.set("network.pam", value)

                    Binding {
                        target: pamSwitch
                        property: "checked"
                        value: page.get("network.pam", false)
                        restoreMode: Binding.RestoreBinding
                    }
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
                    id: inputSwitch
                    buttonIcon: "mouse"
                    text: Translation.tr("Allow remote input")
                    checked: page.get("input.enabled", true)
                    onUserToggled: value => page.set("input.enabled", value)

                    Binding {
                        target: inputSwitch
                        property: "checked"
                        value: page.get("input.enabled", true)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: hostKeyboardSwitch
                    buttonIcon: "keyboard"
                    text: Translation.tr("Match the host keyboard layout")
                    checked: page.get("input.matchHostKeyboard", true)
                    onUserToggled: value => page.set("input.matchHostKeyboard", value)

                    Binding {
                        target: hostKeyboardSwitch
                        property: "checked"
                        value: page.get("input.matchHostKeyboard", true)
                        restoreMode: Binding.RestoreBinding
                    }
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
                    id: xkbLayoutField
                    Layout.fillWidth: true
                    visible: !page.get("input.matchHostKeyboard", true)
                    placeholderText: Translation.tr("XKB layout, e.g. us,ru")
                    text: page.get("input.xkb.layout", "")
                    onTextEdited: page.set("input.xkb.layout", text)

                    Binding {
                        target: xkbLayoutField
                        property: "text"
                        value: page.get("input.xkb.layout", "")
                        restoreMode: Binding.RestoreBinding
                    }
                }

                MaterialTextField {
                    id: xkbOptionsField
                    Layout.fillWidth: true
                    visible: !page.get("input.matchHostKeyboard", true)
                    placeholderText: Translation.tr("XKB options, e.g. grp:win_space_toggle")
                    text: page.get("input.xkb.options", "")
                    onTextEdited: page.set("input.xkb.options", text)

                    Binding {
                        target: xkbOptionsField
                        property: "text"
                        value: page.get("input.xkb.options", "")
                        restoreMode: Binding.RestoreBinding
                    }
                }

                MaterialTextField {
                    id: seatField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Seat (empty = default)")
                    text: page.get("input.seat", "")
                    onTextEdited: page.set("input.seat", text)

                    Binding {
                        target: seatField
                        property: "text"
                        value: page.get("input.seat", "")
                        restoreMode: Binding.RestoreBinding
                    }
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
                    id: lockOnDisconnectSwitch
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Lock the session when the last client disconnects")
                    checked: page.get("behavior.lockOnDisconnect", true)
                    onUserToggled: value => page.set("behavior.lockOnDisconnect", value)

                    Binding {
                        target: lockOnDisconnectSwitch
                        property: "checked"
                        value: page.get("behavior.lockOnDisconnect", false)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: inhibitIdleSwitch
                    buttonIcon: "coffee"
                    text: Translation.tr("Inhibit idle while a client is connected")
                    checked: page.get("behavior.inhibitIdle", false)
                    onUserToggled: value => page.set("behavior.inhibitIdle", value)

                    Binding {
                        target: inhibitIdleSwitch
                        property: "checked"
                        value: page.get("behavior.inhibitIdle", false)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: exitOnDisconnectSwitch
                    buttonIcon: "logout"
                    text: Translation.tr("Stop VNC when the last client disconnects")
                    checked: page.get("behavior.exitOnDisconnect", false)
                    onUserToggled: value => page.set("behavior.exitOnDisconnect", value)

                    Binding {
                        target: exitOnDisconnectSwitch
                        property: "checked"
                        value: page.get("behavior.exitOnDisconnect", false)
                        restoreMode: Binding.RestoreBinding
                    }
                }

                ConfigSwitch {
                    id: hideWallpaperSwitch
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Hide wallpaper while a client is connected")
                    // This is a shell setting, not part of the VNC JSON patch.
                    checked: Config.options.background.vnc.disableWallpaper ?? true
                    onUserToggled: value => Config.options.background.vnc.disableWallpaper = value

                    Binding {
                        target: hideWallpaperSwitch
                        property: "checked"
                        value: Config.options.background.vnc.disableWallpaper ?? true
                        restoreMode: Binding.RestoreBinding
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Hides the desktop image, pauses the video, and hides the centered and lock-screen wallpapers until the last client disconnects.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
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
            icon: "groups"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Clients")
            hint: Translation.tr("%1 connected").arg(Vnc.clients.length)
            hintIcon: "sensors"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                // Management bar: only meaningful while someone is connected.
                RowLayout {
                    Layout.fillWidth: true
                    visible: Vnc.clients.length > 0
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Refresh")
                        materialIcon: "refresh"
                        enabled: !Vnc.busy
                        onClicked: Vnc.refresh()
                    }

                    RippleButtonWithIcon {
                        mainText: Translation.tr("Disconnect all")
                        materialIcon: "link_off"
                        enabled: !Vnc.busy
                        onClicked: Vnc.disconnectAllClients()
                    }
                }

                // Empty state with the same glass-card language as a client.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: emptyRow.implicitHeight + 24
                    visible: Vnc.clients.length === 0
                    radius: Appearance.rounding.small
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)

                    RowLayout {
                        id: emptyRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            margins: 12
                        }
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            Layout.alignment: Qt.AlignVCenter
                            radius: 17
                            color: Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "hub"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("No clients connected")
                                font.bold: true
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Waiting for an incoming VNC connection.")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }
                }

                Repeater {
                    model: Vnc.clients

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: clientCard.implicitHeight + 24
                        radius: Appearance.rounding.small
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)

                        ColumnLayout {
                            id: clientCard
                            anchors {
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 17
                                    color: Appearance.colors.colSecondaryContainer
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "person"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 8

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: page.clientName(modelData)
                                            font.bold: true
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnSurface
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: Math.min(150, kindLabel.implicitWidth + 18)
                                            Layout.preferredHeight: 20
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: Appearance.rounding.small
                                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)

                                            RowLayout {
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    margins: 7
                                                }
                                                spacing: 4
                                                MaterialSymbol {
                                                    text: page.kindIcon(modelData.kind)
                                                    iconSize: Appearance.font.pixelSize.smaller + 2
                                                    color: Appearance.colors.colPrimary
                                                }
                                                StyledText {
                                                    id: kindLabel
                                                    Layout.fillWidth: true
                                                    text: page.kindLabel(modelData.kind)
                                                    color: Appearance.colors.colPrimary
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 8

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: modelData.address || "—"
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }

                                        StyledText {
                                            text: page.uptimeText(modelData.uptimeSeconds)
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }
                                }

                                RippleButtonWithIcon {
                                    Layout.alignment: Qt.AlignVCenter
                                    mainText: page.expandedClients[modelData.id] ? Translation.tr("Hide") : Translation.tr("Details")
                                    materialIcon: page.expandedClients[modelData.id] ? "expand_less" : "expand_more"
                                    onClicked: page.toggleClientDetails(modelData.id)
                                }

                                RippleButtonWithIcon {
                                    Layout.alignment: Qt.AlignVCenter
                                    mainText: Translation.tr("Disconnect")
                                    materialIcon: "link_off"
                                    enabled: !Vnc.busy
                                    onClicked: Vnc.disconnectClient(modelData.id)
                                }
                            }

                            // Spoiled monitoring details: hidden until asked for.
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !!page.expandedClients[modelData.id]
                                spacing: 3

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Appearance.colors.colOutlineVariant
                                }

                                Repeater {
                                    model: page.clientDetailRows(modelData)

                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            Layout.preferredWidth: 96
                                            text: modelData.label
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.value
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "desktop_windows"
            shape: MaterialShape.Shape.Square
            title: Translation.tr("Outputs")
            hint: Translation.tr("%1 detected").arg(Vnc.wayvncOutputs.length)
            hintIcon: "monitor"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    visible: page.outputRows.length === 0
                    text: Translation.tr("No outputs were detected.")
                    color: Appearance.colors.colSubtext
                }

                Repeater {
                    model: page.outputRows

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: outputRow.implicitHeight + 24
                        radius: Appearance.rounding.small
                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)

                        RowLayout {
                            id: outputRow
                            anchors {
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                Layout.alignment: Qt.AlignVCenter
                                radius: 17
                                color: Appearance.colors.colSecondaryContainer
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "monitor"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.description || modelData.name || "—"
                                    font.bold: true
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: `${modelData.width || 0}×${modelData.height || 0}` +
                                        (modelData.refresh ? ` · ${Math.round(modelData.refresh)} Hz` : "") +
                                        (modelData.power ? ` · ${modelData.power}` : "")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideRight
                                }
                            }

                            // Small icon chip replaces the old "CURRENT" text badge.
                            // The old badge painted colPrimary text on a colPrimary
                            // background (unreadable) and had no width, so it collapsed
                            // in the RowLayout. A fixed-size secondary-container chip
                            // with a visibility glyph is compact and unambiguous.
                            Rectangle {
                                visible: modelData.captured === true || modelData.focused === true
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                radius: 11
                                color: Appearance.colors.colSecondaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "visibility"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }

                            RippleButtonWithIcon {
                                Layout.alignment: Qt.AlignVCenter
                                mainText: Translation.tr("Capture now")
                                materialIcon: "screenshot_monitor"
                                visible: Vnc.serviceActive
                                enabled: !Vnc.busy
                                onClicked: Vnc.outputSet(modelData.name)
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: Translation.tr("Capture now switches the live stream only. Apply a new capture mode to make it persistent.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
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
                spacing: 10

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
