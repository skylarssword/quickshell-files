import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Io
import IslandBackend
import "../shared"

// ── Sidebar Control Center popup — centered, replica of ControlCenterLayer ───
// Opened by the cog icon below the notification bell in the sidebar pill.

PanelWindow {
    id: root

    // ── Theming ───────────────────────────────────────────────────────
    property bool  useWalColor:         false
    property color walColor:            "#000000"
    property real  capsuleOpacityValue: 0.20
    property bool  gamemodeActive:      false

    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: ""

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    readonly property color moduleColor:  Qt.rgba(1,1,1, gamemodeActive ? 0.03 : 0.05)
    readonly property color moduleHover:  Qt.rgba(1,1,1, gamemodeActive ? 0.06 : 0.09)
    readonly property color trackColor:   StyleTokens.track
    readonly property color textPrimary:  IslandMotion.textPrimary
    readonly property color textSecondary: IslandMotion.textSecondary

    // ── Open/close ────────────────────────────────────────────────────
    property bool popupOpen: false
    function open()  { popupOpen = true  }
    function close() { popupOpen = false }
    function toggle(){ popupOpen = !popupOpen }

    // ── Signals ───────────────────────────────────────────────────────
    signal dndToggleRequested()
    signal gamemodeToggleRequested()
    signal sidebarToggleRequested()
    signal appearanceOpacityRequested(real value)
    signal appearanceWalColorToggleRequested(bool enabled)
    signal appearanceWalColorIndexRequested(int index)
    signal dockEnabledToggleRequested()
    signal dockModeChangeRequested(string mode)
    property bool dndActive:      false
    property bool sidebarEnabled: true
    property bool appearanceMenuOpen: false
    property bool capsuleUseWalColor: false
    property var  capsuleWalColors:   []
    property bool dockEnabled: false
    property string dockMode:  "pin"
    property int  capsuleWalColorIndex: 0
    readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex] : "#000000"

    // ── System state ──────────────────────────────────────────────────
    property string currentTime:       "00:00"
    property string currentDateLabel:  ""
    property int    batteryCapacity:   0
    property bool   isCharging:        false
    property real   volumeLevel:       -1
    property real   brightnessLevel:   -1

    property real  localVolume:      0.5
    property real  localBrightness:  0.5
    property real  displayedVolume:  0.5
    property real  displayedBrightness: 0.5
    property real  pendingVolume:    0.5
    property real  pendingBrightness: 0.5
    property real  lastAppliedVolume: -1
    property real  lastAppliedBrightness: -1
    property bool  brightnessSetterRunning: false
    property bool  volumeSetterRunning: false
    property bool  sliderIntroPending: false
    property int   sliderIntroDelay: 400

    property bool  hyprsunsetActive: false
    property bool  wifiPanelOpen:    false
    property bool  bluetoothPanelOpen: false

    readonly property var wifiController:      WifiController
    readonly property var bluetoothPairingAgent: BluetoothPairingAgent
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property var  bluetoothAdapter:   Bluetooth.defaultAdapter
    readonly property bool bluetoothEnabled:   bluetoothAdapter ? bluetoothAdapter.enabled : false
    readonly property bool bluetoothBusy:      bluetoothAdapter
        ? (bluetoothAdapter.state === BluetoothAdapterState.Enabling || bluetoothAdapter.state === BluetoothAdapterState.Disabling)
        : false
    readonly property bool wifiSupported:  wifiController ? wifiController.supported  : false
    readonly property bool wifiAvailable:  wifiController ? wifiController.available  : false
    readonly property bool wifiEnabled:    wifiController ? wifiController.enabled    : false
    readonly property bool wifiBusy:       wifiController ? wifiController.busy       : false
    readonly property string wifiCurrentSsid: wifiController ? wifiController.currentSsid : ""
    readonly property string wifiStatusText:  wifiController ? wifiController.statusText  : "Unavailable"

    readonly property string wifiGlyph:        ""
    readonly property string bluetoothGlyph:   ""
    readonly property string brightnessGlyph:  "\u{F00DF}"
    readonly property string volumeGlyph:      "\u{F057E}"

    readonly property var wifiNetworks: wifiController ? wifiController.networks : null
    readonly property bool wifiListRunning: wifiController ? wifiController.scanning : false

    // ── Helpers ───────────────────────────────────────────────────────
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function trimString(v) { return (v === undefined || v === null) ? "" : String(v).trim() }

    function bluetoothDeviceName(device) {
        if (!device) return "Unknown"
        const n = trimString(device.deviceName) || trimString(device.name) || trimString(device.address)
        return n || "Unknown"
    }
    function buildBluetoothStatusText() {
        if (!bluetoothAvailable) return "Unavailable"
        if (!bluetoothEnabled) return "Off"
        const devs = bluetoothAdapter ? bluetoothAdapter.devices.values : []
        const names = devs.filter(d => d && d.connected).map(d => bluetoothDeviceName(d))
        if (names.length === 1) return names[0]
        if (names.length > 1) return names[0] + " +" + (names.length - 1)
        if (bluetoothAdapter && bluetoothAdapter.discovering) return "Scanning"
        return bluetoothBusy ? "Working..." : "On"
    }
    function toggleWifiEnabled() {
        if (wifiController) wifiController.setEnabled(!wifiEnabled)
    }
    function toggleBluetoothEnabled() {
        if (!bluetoothAdapter) return
        if (bluetoothAdapter.discovering) bluetoothAdapter.discovering = false
        bluetoothAdapter.enabled = !bluetoothAdapter.enabled
    }

    function syncBrightnessFromLevel(level) {
        if (level < 0) return
        localBrightness = clamp01(level)
        if (popupOpen && !sliderIntroPending) displayedBrightness = localBrightness
        pendingBrightness = localBrightness; lastAppliedBrightness = localBrightness
    }
    function syncVolumeFromLevel(level) {
        if (level < 0) return
        localVolume = clamp01(level)
        if (popupOpen && !sliderIntroPending) displayedVolume = localVolume
        pendingVolume = localVolume; lastAppliedVolume = localVolume
    }
    function queueBrightness(value) {
        localBrightness = clamp01(value)
        if (popupOpen && !sliderIntroPending) displayedBrightness = localBrightness
        pendingBrightness = localBrightness; brightnessApplyTimer.restart()
    }
    function queueVolume(value) {
        localVolume = clamp01(value)
        if (popupOpen && !sliderIntroPending) displayedVolume = localVolume
        pendingVolume = localVolume; volumeApplyTimer.restart()
    }
    function flushBrightness(force) {
        const v = clamp01(pendingBrightness)
        if (!force && Math.abs(v - lastAppliedBrightness) < 0.01) return
        if (brightnessSetterRunning) { brightnessApplyTimer.restart(); return }
        lastAppliedBrightness = v; brightnessSetterRunning = true; SystemServices.setBrightness(v)
    }
    function flushVolume(force) {
        const v = clamp01(pendingVolume)
        if (!force && Math.abs(v - lastAppliedVolume) < 0.01) return
        if (volumeSetterRunning) { volumeApplyTimer.restart(); return }
        lastAppliedVolume = v; volumeSetterRunning = true; SystemServices.setVolume(v)
    }

    // ── Window setup ──────────────────────────────────────────────────
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: popupOpen

    mask: Region {
        Region {
            x: Math.floor(card.x); y: Math.floor(card.y)
            width:  root.popupOpen ? Math.ceil(card.width)  : 0
            height: root.popupOpen ? Math.ceil(card.height) : 0
        }
        Region {
            intersection: Intersection.Combine
            x: Math.floor(wifiFlyout.x); y: Math.floor(wifiFlyout.y)
            width:  (root.popupOpen && root.wifiPanelOpen) ? Math.ceil(wifiFlyout.width)  : 0
            height: (root.popupOpen && root.wifiPanelOpen) ? Math.ceil(wifiFlyout.height) : 0
        }
        Region {
            intersection: Intersection.Combine
            x: Math.floor(btFlyout.x); y: Math.floor(btFlyout.y)
            width:  (root.popupOpen && root.bluetoothPanelOpen) ? Math.ceil(btFlyout.width)  : 0
            height: (root.popupOpen && root.bluetoothPanelOpen) ? Math.ceil(btFlyout.height) : 0
        }
    }

    MouseArea { anchors.fill: parent; enabled: root.popupOpen; onClicked: root.close(); z: -1 }
    Keys.onEscapePressed: root.close()

    // ── Timers ────────────────────────────────────────────────────────
    Timer { id: brightnessApplyTimer; interval: 55; repeat: false; onTriggered: root.flushBrightness(false) }
    Timer { id: volumeApplyTimer;     interval: 55; repeat: false; onTriggered: root.flushVolume(false) }
    Timer {
        id: sliderIntroTimer; interval: root.sliderIntroDelay; repeat: false
        onTriggered: {
            root.sliderIntroPending = false
            root.displayedBrightness = root.localBrightness
            root.displayedVolume = root.localVolume
        }
    }

    // ── Hyprsunset ────────────────────────────────────────────────────
    Process {
        id: hyprsunsetExec
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && pkill -x hyprsunset || hyprsunset --temperature 4500 &"]
    }
    Process {
        id: hyprsunsetChecker
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && echo 1 || echo 0"]
        stdout: SplitParser { onRead: (data) => { root.hyprsunsetActive = (data.trim() === "1") } }
    }
    // Delayed re-check after toggle — gives the process 300 ms to actually start/stop
    // before querying pgrep, matching how the main ControlCenterLayer does it.
    Timer {
        id: hyprsunsetDelayedCheck
        interval: 300; repeat: false
        onTriggered: if (!hyprsunsetChecker.running) hyprsunsetChecker.running = true
    }
    // Poll only while the popup is open — no point running when hidden.
    Timer {
        interval: 3000; running: root.popupOpen; repeat: true; triggeredOnStart: true
        onTriggered: if (!hyprsunsetChecker.running) hyprsunsetChecker.running = true
    }

    // ── SystemServices connections ────────────────────────────────────
    Connections {
        target: SystemServices
        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "") root.syncBrightnessFromLevel(value)
        }
        function onBrightnessSetFinished(value, success, errorString) {
            root.brightnessSetterRunning = false
            if (success) root.syncBrightnessFromLevel(value)
        }
        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString === "") root.syncVolumeFromLevel(value)
        }
        function onVolumeSetFinished(value, success, errorString) {
            root.volumeSetterRunning = false
            if (success) root.syncVolumeFromLevel(value)
        }
    }

    onBrightnessLevelChanged: syncBrightnessFromLevel(brightnessLevel)
    onVolumeLevelChanged: syncVolumeFromLevel(volumeLevel)

    onPopupOpenChanged: {
        if (popupOpen) {
            syncBrightnessFromLevel(brightnessLevel)
            syncVolumeFromLevel(volumeLevel)
            sliderIntroPending = true
            displayedBrightness = localBrightness
            displayedVolume = localVolume
            sliderIntroTimer.restart()
            hyprsunsetChecker.running = true
            SystemServices.requestBrightness()
            SystemServices.requestVolume()
        } else {
            sliderIntroTimer.stop()
            sliderIntroPending = false
            displayedBrightness = localBrightness
            displayedVolume = localVolume
            root.wifiPanelOpen = false
            root.bluetoothPanelOpen = false
        }
    }

    Component.onCompleted: {
        syncBrightnessFromLevel(brightnessLevel)
        syncVolumeFromLevel(volumeLevel)
        SystemServices.requestBrightness()
        SystemServices.requestVolume()
    }

    Behavior on displayedBrightness {
        enabled: root.popupOpen && !root.sliderIntroPending && !brightnessSliderCard.pressed
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }
    Behavior on displayedVolume {
        enabled: root.popupOpen && !root.sliderIntroPending && !volumeSliderCard.pressed
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    // ── Card ──────────────────────────────────────────────────────────
    Item {
        id: card
        width: 440
        anchors.centerIn: parent
        height: contentCol.implicitHeight + 24

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        Rectangle {
            anchors.fill: parent; radius: 28
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Column {
            id: contentCol
            anchors.top: parent.top; anchors.topMargin: 12
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.right: parent.right; anchors.rightMargin: 12
            spacing: 12

            // ── Header row: time + battery ────────────────────────────
            Item {
                width: parent.width; height: 28

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.currentTime
                    color: IslandMotion.textPrimary
                    font.pixelSize: 19; font.family: root.heroFontFamily
                    font.weight: Font.Bold; font.letterSpacing: -0.45
                }

                Row {
                    anchors.right: parent.right; anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    // Charging bolt
                    Text {
                        renderType: Text.NativeRendering
                        text: "\uf0e7"; color: "#7be17b"
                        font.pixelSize: 11; font.family: root.iconFontFamily
                        visible: root.isCharging
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Drawn battery — exact main bar spec: 30×15, r5/r3, tip 3×7
                    Item {
                        width: 30; height: 15
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent; anchors.rightMargin: 3
                            radius: 5; color: "transparent"
                            border.color: Qt.rgba(1,1,1,0.70); border.width: 1.5

                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 2 }
                                radius: 3
                                width: Math.max(0, (parent.width - 4) * (root.batteryCapacity / 100))
                                color: root.batteryCapacity <= 10 ? "#ff3b30"
                                     : root.batteryCapacity <= 20 ? "#ffcc00"
                                     : (root.isCharging ? "#7be17b" : "#ffffff")
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }
                        Rectangle {
                            width: 3; height: 7; radius: 2
                            color: Qt.rgba(1,1,1,0.70)
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    // Percentage
                    Text {
                        renderType: Text.NativeRendering
                        text: root.batteryCapacity + "%"; color: "white"
                        font.pixelSize: 12; font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Hyprsunset button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.hyprsunsetActive ? Qt.rgba(0.9,0.66,0.29,0.25)
                             : (sunMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.08))
                        border.color: root.hyprsunsetActive ? "#e5a84b"
                                    : (sunMouse.containsMouse ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.2))
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text {
                            renderType: Text.NativeRendering; anchors.centerIn: parent
                            text: "\uf186"; font.family: root.iconFontFamily; font.pixelSize: 13
                            color: root.hyprsunsetActive ? "#e5a84b" : IslandMotion.textPrimary
                        }
                        MouseArea {
                            id: sunMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                // Optimistically flip UI immediately so it feels instant
                                root.hyprsunsetActive = !root.hyprsunsetActive
                                // Fire the toggle — startDetached so it doesn't block
                                hyprsunsetExec.startDetached()
                                // Re-check after 300 ms to confirm process actually changed
                                hyprsunsetDelayedCheck.restart()
                            }
                        }
                    }
                    // Appearance button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.appearanceMenuOpen || appearBtnMouse.containsMouse
                             ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                        border.color: root.appearanceMenuOpen
                                    ? Qt.rgba(1,1,1,0.4)
                                    : (appearBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2))
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text {
                            renderType: Text.NativeRendering; anchors.centerIn: parent
                            text: "\uf1fc"; font.family: root.iconFontFamily; font.pixelSize: 13
                            color: root.appearanceMenuOpen ? "white" : IslandMotion.textPrimary
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: appearBtnMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.appearanceMenuOpen = !root.appearanceMenuOpen
                        }
                    }
                }
            }

            // ── Wi-Fi + Bluetooth cards ───────────────────────────────
            Row {
                width: parent.width; height: 80; spacing: 12

                Rectangle {
                    width: (parent.width - 12) / 2; height: parent.height; radius: 20
                    color: (wifiHover.containsMouse || root.wifiPanelOpen) ? root.moduleHover : root.moduleColor
                    border.width: 1
                    border.color: root.wifiPanelOpen ? Qt.rgba(1,1,1,0.35) : Qt.rgba(1,1,1,0.16)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: wifiHover; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            root.wifiPanelOpen = !root.wifiPanelOpen
                            root.bluetoothPanelOpen = false
                            if (root.wifiPanelOpen && root.wifiController)
                                root.wifiController.refreshNetworks(true)
                        }
                    }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.top: parent.top; anchors.topMargin: 12
                        text: root.wifiGlyph; font.family: root.iconFontFamily; font.pixelSize: 18
                        color: root.wifiEnabled ? StyleTokens.accent : IslandMotion.textFaint
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: 34; height: 20; radius: 10
                        color: root.wifiEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: root.wifiEnabled ? 16 : 2; color: "white"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.wifiSupported && root.wifiAvailable && !root.wifiBusy
                            onClicked: root.toggleWifiEnabled()
                        }
                    }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        spacing: 2
                        Text {
                            renderType: Text.NativeRendering; text: "Wi-Fi"
                            color: IslandMotion.textPrimary; font.pixelSize: 13
                            font.family: root.textFontFamily; font.weight: Font.DemiBold
                        }
                        Text {
                            renderType: Text.NativeRendering; text: root.wifiStatusText
                            color: IslandMotion.textFaint; font.pixelSize: 10
                            font.family: root.textFontFamily
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 12) / 2; height: parent.height; radius: 20
                    color: (btHover.containsMouse || root.bluetoothPanelOpen) ? root.moduleHover : root.moduleColor
                    border.width: 1
                    border.color: root.bluetoothPanelOpen ? Qt.rgba(1,1,1,0.35) : Qt.rgba(1,1,1,0.16)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: btHover; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            root.bluetoothPanelOpen = !root.bluetoothPanelOpen
                            root.wifiPanelOpen = false
                            if (root.bluetoothPanelOpen && root.bluetoothAdapter)
                                root.bluetoothAdapter.discovering = true
                        }
                    }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.top: parent.top; anchors.topMargin: 12
                        text: root.bluetoothGlyph; font.family: root.iconFontFamily; font.pixelSize: 18
                        color: root.bluetoothEnabled ? StyleTokens.accent : IslandMotion.textFaint
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.top: parent.top; anchors.topMargin: 12
                        width: 34; height: 20; radius: 10
                        color: root.bluetoothEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: root.bluetoothEnabled ? 16 : 2; color: "white"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.bluetoothAvailable && !root.bluetoothBusy
                            onClicked: root.toggleBluetoothEnabled()
                        }
                    }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                        spacing: 2
                        Text {
                            renderType: Text.NativeRendering; text: "Bluetooth"
                            color: IslandMotion.textPrimary; font.pixelSize: 13
                            font.family: root.textFontFamily; font.weight: Font.DemiBold
                        }
                        Text {
                            renderType: Text.NativeRendering; text: root.buildBluetoothStatusText()
                            color: IslandMotion.textFaint; font.pixelSize: 10
                            font.family: root.textFontFamily
                        }
                    }
                }
            }

            // ── Game Mode card ────────────────────────────────────────
            Rectangle {
                width: parent.width; height: 56; radius: 20
                color: gamemodeHover.containsMouse ? root.moduleHover : root.moduleColor
                border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea { id: gamemodeHover; anchors.fill: parent; hoverEnabled: true }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf11b"; font.family: root.iconFontFamily; font.pixelSize: 18
                    color: root.gamemodeActive ? "#60a5fa" : IslandMotion.textFaint
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Game Mode"
                    color: IslandMotion.textPrimary; font.pixelSize: 13
                    font.family: root.textFontFamily; font.weight: Font.DemiBold
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 9
                    text: root.gamemodeActive ? "Sidebar blacked out" : "Normal mode"
                    color: IslandMotion.textFaint; font.pixelSize: 10
                    font.family: root.textFontFamily
                }

                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 20; radius: 10
                    color: root.gamemodeActive ? StyleTokens.success : StyleTokens.switchOff
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: root.gamemodeActive ? 16 : 2; color: "white"
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.gamemodeToggleRequested()
                    }
                }
            }

            // ── Sidebar toggle card ───────────────────────────────────
            Rectangle {
                width: parent.width; height: 56; radius: 20
                color: sidebarHover.containsMouse ? root.moduleHover : root.moduleColor
                border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea { id: sidebarHover; anchors.fill: parent; hoverEnabled: true }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf0c9"; font.family: root.iconFontFamily; font.pixelSize: 18
                    color: root.sidebarEnabled ? StyleTokens.accent : IslandMotion.textFaint
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.top: parent.top; anchors.topMargin: 10
                    text: "Sidebar"
                    color: IslandMotion.textPrimary; font.pixelSize: 13
                    font.family: root.textFontFamily; font.weight: Font.DemiBold
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 9
                    text: "Tap to hide sidebar"
                    color: IslandMotion.textFaint; font.pixelSize: 10
                    font.family: root.textFontFamily
                }

                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 20; radius: 10
                    color: root.sidebarEnabled ? StyleTokens.success : StyleTokens.switchOff
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: root.sidebarEnabled ? 16 : 2; color: "white"
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.sidebarToggleRequested()
                            sidebarCloseTimer.start()
                        }
                    }
                }
            }

            Timer {
                id: sidebarCloseTimer
                interval: 50; repeat: false
                onTriggered: root.close()
            }

            // ── Brightness slider ─────────────────────────────────────
            SidebarSliderCard {
                id: brightnessSliderCard
                visible: !root.appearanceMenuOpen
                opacity: root.appearanceMenuOpen ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                width: parent.width; height: 76
                title: "Display"; iconText: root.brightnessGlyph
                iconFontFamily: root.iconFontFamily; textFontFamily: root.textFontFamily
                value: root.displayedBrightness
                moduleColor: root.moduleColor; moduleHover: root.moduleHover
                trackColor: root.trackColor
                textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onInteractionStarted: {
                    if (root.sliderIntroPending) {
                        sliderIntroTimer.stop(); root.sliderIntroPending = false
                        root.displayedBrightness = root.localBrightness
                        root.displayedVolume = root.localVolume
                    }
                }
                onValueMoved: function(v) { root.queueBrightness(v) }
                onCommitRequested: { brightnessApplyTimer.stop(); root.flushBrightness(true) }
                onCancelRequested: SystemServices.requestBrightness()
            }

            // ── Volume slider ─────────────────────────────────────────
            SidebarSliderCard {
                id: volumeSliderCard
                visible: !root.appearanceMenuOpen
                opacity: root.appearanceMenuOpen ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                width: parent.width; height: 76
                title: "Sound"; iconText: root.volumeGlyph
                iconFontFamily: root.iconFontFamily; textFontFamily: root.textFontFamily
                value: root.displayedVolume
                moduleColor: root.moduleColor; moduleHover: root.moduleHover
                trackColor: root.trackColor
                textPrimary: root.textPrimary; textSecondary: root.textSecondary
                onInteractionStarted: {
                    if (root.sliderIntroPending) {
                        sliderIntroTimer.stop(); root.sliderIntroPending = false
                        root.displayedBrightness = root.localBrightness
                        root.displayedVolume = root.localVolume
                    }
                }
                onValueMoved: function(v) { root.queueVolume(v) }
                onCommitRequested: { volumeApplyTimer.stop(); root.flushVolume(true) }
                onCancelRequested: SystemServices.requestVolume()
            }

            // ── Appearance drawer ─────────────────────────────────────
            Item {
                id: appearanceMenuDrawer
                width: parent.width
                height: root.appearanceMenuOpen ? appearanceMenuContent.implicitHeight + 12 : 0
                clip: true
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: appearanceMenuContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: appearanceColumn.implicitHeight + 28
                    radius: 20
                    color: Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.16)

                    Column {
                        id: appearanceColumn
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 14
                        spacing: 10

                        // Header row: label + Pywal switch
                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                renderType: Text.NativeRendering
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Appearance"
                                color: root.textPrimary
                                font.pixelSize: 13
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Pywal"
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.family: root.textFontFamily
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 20; radius: 10
                                    color: root.capsuleUseWalColor ? StyleTokens.success : StyleTokens.switchOff
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Rectangle {
                                        width: 16; height: 16; radius: 8; y: 2
                                        x: root.capsuleUseWalColor ? 16 : 2; color: "white"
                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.appearanceWalColorToggleRequested(!root.capsuleUseWalColor)
                                    }
                                }
                            }
                        }

                        // Preview pill
                        Rectangle {
                            width: parent.width; height: 40; radius: 14
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.15)
                            color: root.capsuleUseWalColor
                                 ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g, root.capsuleWalColor.b, root.capsuleOpacityValue)
                                 : Qt.rgba(0, 0, 0, root.capsuleOpacityValue)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "Preview"
                                color: "white"; opacity: 0.55
                                font.pixelSize: 10; font.family: root.textFontFamily
                                font.weight: Font.Medium
                            }
                        }

                        // Pywal color swatches (only when pywal enabled)
                        Item {
                            width: parent.width
                            height: root.capsuleUseWalColor && root.capsuleWalColors.length > 0 ? 40 : 0
                            clip: true
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            ListView {
                                anchors.fill: parent
                                anchors.bottomMargin: 8
                                orientation: ListView.Horizontal
                                spacing: 6
                                clip: true
                                interactive: true
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.capsuleWalColors.length
                                readonly property real contentNaturalWidth: count > 0
                                    ? (count * 26 + Math.max(0, count - 1) * spacing) : 0
                                leftMargin:  Math.max(0, (width - contentNaturalWidth) / 2)
                                rightMargin: Math.max(0, (width - contentNaturalWidth) / 2)

                                ScrollBar.horizontal: ScrollBar {
                                    policy: ScrollBar.AsNeeded; height: 4
                                    contentItem: Rectangle { implicitHeight: 4; radius: 2; color: Qt.rgba(1,1,1,0.25) }
                                    background: Item {}
                                }

                                delegate: Rectangle {
                                    id: swatchDelegate
                                    required property int index
                                    readonly property bool isActive: root.capsuleWalColorIndex === index
                                    width: 26; height: 26; radius: 13
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                    color: root.capsuleWalColors[index] || "#000000"
                                    border.width: isActive ? 2 : 1
                                    border.color: isActive ? "white" : Qt.rgba(1,1,1,0.25)
                                    scale: isActive ? 1.12 : (swatchMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    Text {
                                        renderType: Text.NativeRendering; anchors.centerIn: parent
                                        text: swatchDelegate.index; color: "white"
                                        font.pixelSize: 8; font.weight: Font.Bold
                                        font.family: root.textFontFamily
                                        style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.65)
                                    }

                                    MouseArea {
                                        id: swatchMouse; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.appearanceWalColorIndexRequested(swatchDelegate.index)
                                    }
                                }
                            }
                        }

                        // Opacity presets
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Repeater {
                                model: [0.20, 0.40, 0.60, 0.80, 1.0]
                                delegate: Rectangle {
                                    required property real modelData
                                    readonly property bool isActive: Math.abs(root.capsuleOpacityValue - modelData) < 0.01
                                    width: presetLbl.implicitWidth + 16; height: 26; radius: 13
                                    color: isActive ? Qt.rgba(1,1,1,0.20)
                                         : (presetMouse2.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06))
                                    border.color: isActive ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.12)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        renderType: Text.NativeRendering
                                        id: presetLbl; anchors.centerIn: parent
                                        text: Math.round(parent.modelData * 100) + "%"
                                        color: "white"
                                        opacity: parent.isActive ? 0.95 : 0.55
                                        font.pixelSize: 10; font.family: root.textFontFamily
                                        font.weight: parent.isActive ? Font.DemiBold : Font.Medium
                                    }

                                    MouseArea {
                                        id: presetMouse2; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.appearanceOpacityRequested(parent.modelData)
                                    }
                                }
                            }
                        }

                        // ── Dock section ──────────────────────────────
                        Item { width: parent.width; height: 1
                            Rectangle { anchors.fill: parent; color: Qt.rgba(1,1,1,0.10) }
                        }

                        // Header: "Dock" + enable toggle
                        Item {
                            width: parent.width; height: 24
                            Text {
                                renderType: Text.NativeRendering
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Dock"
                                color: root.textPrimary
                                font.pixelSize: 13; font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Enable"
                                    color: root.textSecondary
                                    font.pixelSize: 10; font.family: root.textFontFamily
                                    font.weight: Font.Medium
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 20; radius: 10
                                    color: root.dockEnabled ? StyleTokens.success : StyleTokens.switchOff
                                    Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }
                                    Rectangle {
                                        width: 16; height: 16; radius: 8; y: 2
                                        x: root.dockEnabled ? 16 : 2
                                        color: StyleTokens.white
                                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.dockEnabledToggleRequested()
                                    }
                                }
                            }
                        }

                        // Pin / Smart mode bubbles (only when dock enabled)
                        Grid {
                            width: parent.width
                            columns: 2; rowSpacing: 6; columnSpacing: 6
                            visible: root.dockEnabled
                            opacity: root.dockEnabled ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            Rectangle {
                                width: (parent.width - 6) / 2; height: 36; radius: 12
                                color: root.dockEnabled && root.dockMode === "pin"
                                    ? Qt.rgba(1,1,1,0.15)
                                    : (sbPinMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05))
                                border.color: root.dockEnabled && root.dockMode === "pin"
                                    ? Qt.rgba(1,1,1,0.40) : Qt.rgba(1,1,1,0.12)
                                border.width: 1
                                Behavior on color        { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Text {
                                    renderType: Text.NativeRendering; anchors.centerIn: parent
                                    text: "Pin"
                                    color: (root.dockEnabled && root.dockMode === "pin") ? "white" : Qt.rgba(1,1,1,0.45)
                                    font.pixelSize: 12; font.family: root.textFontFamily
                                    font.weight: (root.dockEnabled && root.dockMode === "pin") ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    id: sbPinMouse; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.dockModeChangeRequested("pin")
                                }
                            }

                            Rectangle {
                                width: (parent.width - 6) / 2; height: 36; radius: 12
                                color: root.dockEnabled && root.dockMode === "smart"
                                    ? Qt.rgba(1,1,1,0.15)
                                    : (sbSmartMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05))
                                border.color: root.dockEnabled && root.dockMode === "smart"
                                    ? Qt.rgba(1,1,1,0.40) : Qt.rgba(1,1,1,0.12)
                                border.width: 1
                                Behavior on color        { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Text {
                                    renderType: Text.NativeRendering; anchors.centerIn: parent
                                    text: "Smart"
                                    color: (root.dockEnabled && root.dockMode === "smart") ? "white" : Qt.rgba(1,1,1,0.45)
                                    font.pixelSize: 12; font.family: root.textFontFamily
                                    font.weight: (root.dockEnabled && root.dockMode === "smart") ? Font.DemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    id: sbSmartMouse; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.dockModeChangeRequested("smart")
                                }
                            }
                        }
                    }
                }
            }
        }

    // ── Wi-Fi flyout panel ────────────────────────────────────────────
    Item {
        id: wifiFlyout
        width: 300
        height: Math.min(wifiFlyoutContent.implicitHeight + 24, root.height - 48)
        x: card.x + card.width + 12
        y: card.y

        opacity: (root.popupOpen && root.wifiPanelOpen) ? 1 : 0
        scale:   (root.popupOpen && root.wifiPanelOpen) ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        Rectangle {
            anchors.fill: parent; radius: 20
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Column {
            id: wifiFlyoutContent
            anchors.top: parent.top; anchors.topMargin: 14
            anchors.left: parent.left; anchors.leftMargin: 14
            anchors.right: parent.right; anchors.rightMargin: 14
            spacing: 8

            // Header
            Row {
                width: parent.width; spacing: 8

                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.wifiGlyph; font.family: root.iconFontFamily; font.pixelSize: 16
                    color: root.wifiEnabled ? StyleTokens.accent : IslandMotion.textFaint
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"; color: IslandMotion.textPrimary
                    font.pixelSize: 14; font.family: root.textFontFamily; font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.wifiListRunning ? "Scanning…" : root.wifiStatusText
                    color: IslandMotion.textFaint; font.pixelSize: 10; font.family: root.textFontFamily
                    visible: root.wifiEnabled
                }
            }

            // Divider
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.10) }

            // Network list
            Column {
                width: parent.width
                spacing: 4
                visible: root.wifiEnabled && root.wifiSupported

                Repeater {
                    model: root.wifiNetworks ? root.wifiNetworks.values : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isConnected: modelData.ssid === root.wifiCurrentSsid
                        width: parent.width; height: 40; radius: 10
                        color: netHover.containsMouse
                            ? Qt.rgba(1,1,1, isConnected ? 0.12 : 0.08)
                            : Qt.rgba(1,1,1, isConnected ? 0.08 : 0.04)
                        border.width: isConnected ? 1 : 0
                        border.color: Qt.rgba(1,1,1,0.25)
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.ssid || "Hidden Network"
                            color: isConnected ? "white" : IslandMotion.textPrimary
                            font.pixelSize: 12; font.family: root.textFontFamily
                            font.weight: isConnected ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            width: parent.width - 70
                        }

                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                renderType: Text.NativeRendering
                                text: "\uf023"
                                font.family: root.iconFontFamily; font.pixelSize: 10
                                color: IslandMotion.textFaint
                                visible: modelData.secured || false
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                renderType: Text.NativeRendering
                                text: {
                                    const s = modelData.strength || 0
                                    if (s >= 75) return "\uf1eb"
                                    if (s >= 50) return "\uf5a0"
                                    if (s >= 25) return "\uf5a2"
                                    return "\uf5a4"
                                }
                                font.family: root.iconFontFamily; font.pixelSize: 12
                                color: isConnected ? StyleTokens.accent : IslandMotion.textFaint
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: netHover; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!isConnected && root.wifiController)
                                    root.wifiController.connectToNetwork(modelData)
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    renderType: Text.NativeRendering
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: root.wifiListRunning ? "Scanning for networks…" : "No networks found"
                    color: IslandMotion.textFaint; font.pixelSize: 11; font.family: root.textFontFamily
                    visible: !root.wifiNetworks || root.wifiNetworks.values.length === 0
                    topPadding: 8; bottomPadding: 8
                }
            }

            // Wi-Fi off state
            Text {
                renderType: Text.NativeRendering
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Wi-Fi is off"
                color: IslandMotion.textFaint; font.pixelSize: 11; font.family: root.textFontFamily
                visible: !root.wifiEnabled
                topPadding: 4; bottomPadding: 4
            }

            Item { width: 1; height: 2 }
        }
    }

    // ── Bluetooth flyout panel ────────────────────────────────────────
    Item {
        id: btFlyout
        width: 300
        height: Math.min(btFlyoutContent.implicitHeight + 24, root.height - 48)
        x: card.x + card.width + 12
        y: card.y

        opacity: (root.popupOpen && root.bluetoothPanelOpen) ? 1 : 0
        scale:   (root.popupOpen && root.bluetoothPanelOpen) ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        Rectangle {
            anchors.fill: parent; radius: 20
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Column {
            id: btFlyoutContent
            anchors.top: parent.top; anchors.topMargin: 14
            anchors.left: parent.left; anchors.leftMargin: 14
            anchors.right: parent.right; anchors.rightMargin: 14
            spacing: 8

            // Header
            Row {
                width: parent.width
                spacing: 8

                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.bluetoothGlyph; font.family: root.iconFontFamily; font.pixelSize: 16
                    color: root.bluetoothEnabled ? StyleTokens.accent : IslandMotion.textFaint
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Bluetooth"; color: IslandMotion.textPrimary
                    font.pixelSize: 14; font.family: root.textFontFamily; font.weight: Font.DemiBold
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.bluetoothAdapter && root.bluetoothAdapter.discovering ? "Scanning…" : ""
                    color: IslandMotion.textFaint; font.pixelSize: 10; font.family: root.textFontFamily
                    visible: root.bluetoothEnabled
                }
            }

            // Divider
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.10) }

            // Device list
            Column {
                width: parent.width
                spacing: 4
                visible: root.bluetoothEnabled && root.bluetoothAvailable

                Repeater {
                    model: root.bluetoothAdapter ? root.bluetoothAdapter.devices.values : []
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isConnected: modelData.connected || false
                        readonly property bool isPaired: modelData.paired || false
                        width: parent.width; height: 44; radius: 10
                        color: btDevHover.containsMouse
                            ? Qt.rgba(1,1,1, isConnected ? 0.12 : 0.08)
                            : Qt.rgba(1,1,1, isConnected ? 0.08 : 0.04)
                        border.width: isConnected ? 1 : 0
                        border.color: Qt.rgba(1,1,1,0.25)
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                renderType: Text.NativeRendering
                                text: root.bluetoothDeviceName(modelData)
                                color: isConnected ? "white" : IslandMotion.textPrimary
                                font.pixelSize: 12; font.family: root.textFontFamily
                                font.weight: isConnected ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight; width: 180
                            }
                            Text {
                                renderType: Text.NativeRendering
                                text: isConnected ? "Connected" : (isPaired ? "Paired" : "Available")
                                color: isConnected ? StyleTokens.accent : IslandMotion.textFaint
                                font.pixelSize: 10; font.family: root.textFontFamily
                            }
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: isConnected ? "\uf127" : "\uf293"
                            font.family: root.iconFontFamily; font.pixelSize: 14
                            color: isConnected ? StyleTokens.accent : IslandMotion.textFaint
                        }

                        MouseArea {
                            id: btDevHover; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (isConnected) modelData.disconnect()
                                else modelData.connectToDevice()
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    renderType: Text.NativeRendering
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: root.bluetoothAdapter && root.bluetoothAdapter.discovering
                        ? "Scanning for devices…" : "No devices found"
                    color: IslandMotion.textFaint; font.pixelSize: 11; font.family: root.textFontFamily
                    visible: !root.bluetoothAdapter || root.bluetoothAdapter.devices.values.length === 0
                    topPadding: 8; bottomPadding: 8
                }
            }

            // BT off state
            Text {
                renderType: Text.NativeRendering
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Bluetooth is off"
                color: IslandMotion.textFaint; font.pixelSize: 11; font.family: root.textFontFamily
                visible: !root.bluetoothEnabled
                topPadding: 4; bottomPadding: 4
            }

            Item { width: 1; height: 2 }
        }
    }
}
}
