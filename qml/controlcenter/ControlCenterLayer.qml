import QtQuick
import Quickshell.Io
import Quickshell.Bluetooth
import IslandBackend
import QtQuick.Controls
import "../shared"
 

Item {
    id: controlCenter

signal connectivityPanelRequested(string kind, bool open)
    signal screenshotPanelRequested(bool open)
signal clearNotificationHistoryRequested()
    signal notificationEntryActivated(var entry)
signal dndToggleRequested()
    property bool dndActive: false
signal appearanceOpacityRequested(real value)
    signal appearanceWalColorToggleRequested(bool enabled)
signal appearanceWalColorIndexRequested(int index)
signal gamemodeToggleRequested()
signal pinToggleRequested()
    property bool pinned: false
signal bubblesToggleRequested()
    property bool bubblesEnabled: true
    // ── Dock ──────────────────────────────────────────────────────────
    signal dockEnabledToggleRequested()
    property bool   dockEnabled: true
    signal dockModeChangeRequested(string mode)
    property string dockMode: "pin"
    signal idleModeToggleRequested(bool enabled)
    property bool idleMode: false
    signal sidebarToggleRequested()
    property bool sidebarEnabled: false
    // Tracks which mode was last selected so the master toggle knows what to restore.
    // "bar" = WorkspaceBubble+Systray, "dock" = BubbleDockWindow pill
    property string lastBubbleMode: "bar"
    property bool appearanceMenuOpen: false
    property bool gamemodeCardFlipped: false
    property real capsuleOpacity: 0.20
    property bool capsuleUseWalColor: false
    property var capsuleWalColors: []
    property int capsuleWalColorIndex: 0
    readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex]
        : "#000000"
    readonly property real appearanceMenuTotalHeight: notificationPanelTotalHeight

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily
   

    scale: showCondition ? 1.0 : 0.12
    transformOrigin: Item.Top

    Behavior on scale {
        NumberAnimation {
            duration: IslandMotion.standard
            easing.type: IslandMotion.easeArrive
        }
    }
    property string currentTime: "00:00"
    property string currentDateLabel: ""
    property int batteryCapacity: 0
    property bool isCharging: false
    property real volumeLevel: -1
    property real brightnessLevel: -1
    property int sliderIntroDelay: 400
    property int currentWorkspace: 1
    property string currentTrack: ""
    property string currentArtist: ""

    property real localVolume: 0.5
    property real localBrightness: 0.5
    property real displayedVolume: 0.5
    property real displayedBrightness: 0.5
    property real pendingVolume: 0.5
    property real pendingBrightness: 0.5
    property real lastAppliedVolume: -1
    property real lastAppliedBrightness: -1
    property bool brightnessSetterRunning: false
    property bool volumeSetterRunning: false
    property bool sliderIntroPending: false
   property bool wifiPanelOpen: false
property bool bluetoothPanelOpen: false
property bool screenshotPanelOpen: false
   property bool batteryDrawerOpen: false
property bool powerMenuOpen: false
property bool gamemodeActive: false
property bool notificationPanelOpen: false
    property bool idleSettingsOpen: false
    property var idleTimeouts: ({ dim: 480, lock: 600, displayoff: 660, suspend: 1800 })

readonly property var idleOptions: [
        { label: "Never",       value: -1 },
        { label: "5 minutes",   value: 300 },
        { label: "8 minutes",   value: 480 },
        { label: "10 minutes",  value: 600 },
        { label: "11 minutes",  value: 660 },
        { label: "15 minutes",  value: 900 },
        { label: "30 minutes",  value: 1800 },
        { label: "45 minutes",  value: 2700 },
        { label: "60 minutes",  value: 3600 },
        { label: "120 minutes", value: 7200 }
    ]

    function idleOptionIndex(key) {
        const val = idleTimeouts[key];
        const idx = idleOptions.findIndex(o => o.value === val);
        return idx >= 0 ? idx : 0;
    }

    function setIdleTimeout(key, seconds) {
        idleTimeouts[key] = seconds;
        idleTimeoutsChanged();
        idleApplyExec.run(key, seconds);
    }
    property var notificationHistory: []
    property int expandedNotificationIndex: -1

    onNotificationHistoryChanged: {
        if (notificationHistory.length === 0)
            expandedNotificationIndex = -1
    }
    property bool hyprsunsetActive: false
    property string screenshotMode: "area"
    property bool screenshotCapturing: false
property bool batteryDrawerDragging: false
    property bool showBatteryTime: false
    property string batteryTimeText: ""

    Process {
        id: batteryTimeQuery
        property string _buf: ""
        command: ["bash", "-c", "upower -i $(upower -e | grep BAT) | awk '/state:/ {state=$2} /time to empty:/ {h=int($4); m=int(($4-h)*60)} /time to full:/ {m=int($4); h=int(m/60); m=m%60} END {if (state==\"charging\") printf \"Full in: %dh %dm\", h, m; else printf \"Left: %dh %dm\", h, m}'"]
        stdout: SplitParser { onRead: batteryTimeQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                controlCenter.batteryTimeText = batteryTimeQuery._buf.trim()
                batteryTimeQuery._buf = ""
            }
        }
    }

    Timer {
        id: batteryTimePollTimer
        interval: 30000
        running: controlCenter.showBatteryTime
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!batteryTimeQuery.running) batteryTimeQuery.running = true
    }
    property real batteryDrawerProgress: 0
    property bool batteryDrawerSettling: false
    readonly property bool batteryDrawerMoving: batteryDrawerDragging
        || batteryDrawerSettling
        || batteryDrawerProgressAnimation.running
    property bool batteryModeBusy: false
    property bool batteryModeStateRunning: false
    property bool batteryModeSetterRunning: false
    property bool batteryModeSliderDragging: false
    property bool batteryTlpAvailable: false
    property bool batteryTlpChecked: false
    property int batteryModeIndex: 1
    property int batteryModeAppliedIndex: 1
    property int batteryModePendingIndex: 1
    property real batteryModeDragOffset: 0
    property string batteryModeInfoMessage: ""
    property string batteryModeError: ""
    property string batteryModeLastCommandOutput: ""
    property int batteryModeRefreshPollsRemaining: 0

    property string wifiLocalInfoMessage: ""
    property string wifiLocalError: ""
    property string wifiPendingPasswordSsid: ""
    property string wifiPendingPasswordValue: ""

    property string bluetoothInfoMessage: ""
    property string bluetoothError: ""
    property string bluetoothPairAndConnectPath: ""
    property string bluetoothPendingSecretValue: ""
    readonly property var wifiController: WifiController
    readonly property var bluetoothPairingAgent: BluetoothPairingAgent
    readonly property var wifiNetworks: wifiController ? wifiController.networks : null

    readonly property real sliderKnobSize: 24
    readonly property color panelColor: StyleTokens.panel
    readonly property color moduleColor: StyleTokens.module
    readonly property color moduleHover: StyleTokens.moduleHover
    readonly property color trackColor: StyleTokens.track
    readonly property color textPrimary: IslandMotion.textPrimary
    readonly property color textSecondary: IslandMotion.textSecondary
    readonly property color cardAccent: StyleTokens.accent
    readonly property color cardAccentPressed: StyleTokens.accentPressed
    readonly property color cardFillActive: StyleTokens.cardFillActive
    readonly property color cardFillHover: StyleTokens.cardFillHover
    readonly property color buttonFill: StyleTokens.buttonFill
    readonly property color buttonFillHover: StyleTokens.buttonFillHover
    readonly property color buttonFillPressed: StyleTokens.buttonFillPressed
    readonly property string wifiGlyph: ""
    readonly property string bluetoothGlyph: ""
    readonly property string chargingIconGlyph: "\uf0e7"
    readonly property string brightnessIconGlyph: "\u{F00DF}"
    readonly property string volumeIconGlyph: "\u{F057E}"
    readonly property var batteryModeGlyphs: ["", "", ""]
    readonly property real batteryDrawerHandleHeight: 20
    readonly property real batteryDrawerContentGap: 8
    readonly property real batteryModeCardHeight: 80
readonly property real controlCenterExtraHeight: powerMenuOpen
        ? 0
        : (12 + batteryDrawerHandleHeight
            + batteryDrawerProgress * (batteryDrawerContentGap + batteryModeCardHeight))
    readonly property real controlCenterMaximumExtraHeight: powerMenuOpen
        ? 0
        : (12 + batteryDrawerHandleHeight
            + batteryDrawerContentGap + batteryModeCardHeight)

// Power menu height: header (28) + spacing (12) + button column (44+16) + margins (24)
   readonly property real powerMenuTotalHeight: 150
   // Bound directly to the Column's real measured height (id: controlCenterColumn, added
   // below) rather than a hand-computed constant — avoids the off-by-N clipping bug.
   readonly property real notificationPanelTotalHeight: controlCenterColumn.implicitHeight + 24
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDeviceValues: bluetoothAdapter ? bluetoothAdapter.devices.values : []
    readonly property bool wifiSupported: wifiController ? wifiController.supported : false
    readonly property bool wifiReadOnly: wifiController ? wifiController.readOnly : true
    readonly property bool wifiAvailable: wifiController ? wifiController.available : false
    readonly property bool wifiEnabled: wifiController ? wifiController.enabled : false
    readonly property bool wifiBusy: wifiController ? wifiController.busy : false
    readonly property bool wifiListRunning: wifiController ? wifiController.scanning : false
    readonly property string wifiCurrentSsid: wifiController ? wifiController.currentSsid : ""
    readonly property string wifiInfoMessage: wifiLocalInfoMessage.length > 0
        ? wifiLocalInfoMessage
        : (wifiController ? wifiController.infoMessage : "")
    readonly property string wifiError: wifiLocalError.length > 0
        ? wifiLocalError
        : (wifiController ? wifiController.errorMessage : "")
    readonly property string wifiUnsupportedReason: wifiController ? wifiController.unsupportedReason : ""
    readonly property string wifiAvailabilityMessage: {
        if (wifiUnsupportedReason.length > 0) return wifiUnsupportedReason;
        if (wifiSupported && !wifiAvailable) return "No Wi-Fi device is available.";
        return "";
    }
    readonly property bool bluetoothEnabled: bluetoothAdapter ? bluetoothAdapter.enabled : false
    readonly property bool bluetoothBusy: bluetoothAdapter
        ? bluetoothAdapter.state === BluetoothAdapterState.Enabling
            || bluetoothAdapter.state === BluetoothAdapterState.Disabling
        : false
    readonly property bool bluetoothPairingActive: bluetoothPairingAgent ? bluetoothPairingAgent.requestActive : false
    readonly property bool bluetoothPairingRequiresInput: bluetoothPairingAgent ? bluetoothPairingAgent.requestRequiresInput : false
    readonly property bool bluetoothPairingNumericInput: bluetoothPairingAgent ? bluetoothPairingAgent.requestNumericInput : false
    readonly property bool bluetoothPairingRequiresConfirmation: bluetoothPairingAgent ? bluetoothPairingAgent.requestRequiresConfirmation : false
    readonly property string bluetoothPairingTitle: bluetoothPairingAgent ? bluetoothPairingAgent.promptTitle : ""
    readonly property string bluetoothPairingMessage: bluetoothPairingAgent ? bluetoothPairingAgent.promptMessage : ""
    readonly property string bluetoothPairingDisplayedCode: bluetoothPairingAgent ? bluetoothPairingAgent.displayedCode : ""
    readonly property bool hasConnectivityPrompt: wifiPendingPasswordSsid.length > 0 || bluetoothPairingActive
    readonly property bool anyConnectivityPanelOpen: wifiPanelOpen || bluetoothPanelOpen
    readonly property string wifiStatusText: wifiController ? wifiController.statusText : "Unavailable"
    readonly property string bluetoothStatusText: buildBluetoothStatusText()
    readonly property string bluetoothAvailabilityMessage: bluetoothAvailable ? "" : "No Bluetooth adapter is available."
    readonly property string batteryModeStatusText: buildBatteryModeStatusText()

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function trimString(value) {
        if (value === undefined || value === null) return "";
        return String(value).trim();
    }

    function batteryModeLabel(index) {
        if (index <= 0) return "Power Saver";
        if (index >= 2) return "Performance";
        return "Balanced";
    }

    function batteryModeCommand(index) {
        if (index <= 0) return "power-saver";
        if (index >= 2) return "performance";
        return "balanced";
    }

    function batteryModeIndexForCommand(command) {
        const normalized = trimString(command).toLowerCase();
        if (normalized === "power-saver" || normalized === "bat") return 0;
        if (normalized === "performance" || normalized === "ac") return 2;
        return 1;
    }

    function setBatteryModeVisualIndex(index, animate) {
        const nextIndex = Math.max(0, Math.min(2, index));
        batteryModeIndex = nextIndex;
    }

    function setBatteryDrawerOpen(open) {
        const nextOpen = !!open;
        batteryDrawerOpen = nextOpen;
        batteryDrawerSettling = true;
        batteryDrawerProgress = nextOpen ? 1 : 0;
        batteryDrawerSettleTimer.restart();
        if (nextOpen && !batteryTlpChecked)
            refreshBatteryModeState();
    }

function toggleBatteryDrawer() {
        setBatteryDrawerOpen(!batteryDrawerOpen);
    }

    function toggleGamemodeCardFlip() {
        gamemodeCardFlipped = !gamemodeCardFlipped;
        if (gamemodeCardFlipped && !batteryTlpChecked)
            refreshBatteryModeState();
    }

    // Reset to the front face once the drawer fully closes, so it doesn't
    // silently reopen already flipped to Battery next time.
    onBatteryDrawerOpenChanged: if (!batteryDrawerOpen) gamemodeCardFlipped = false

    function refreshBatteryModeState() {
        if (batteryModeStateRunning)
            return;

        batteryModeStateRunning = true;
        SystemServices.requestTlpState();
    }

    function applyBatteryModeState(available, profile, output, errorString) {
        batteryModeStateRunning = false;
        batteryTlpChecked = true;
        batteryTlpAvailable = !!available;

        if (!batteryTlpAvailable) {
            batteryModeBusy = false;
            batteryModeError = trimString(errorString).length > 0 ? errorString : "TLP is not installed.";
            setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
            return;
        }

        if (batteryModeError === "TLP is not installed.")
            batteryModeError = "";

        let resolvedProfile = trimString(profile);
        if (resolvedProfile.length === 0) {
            const profileMatch = String(output || "").match(/TLP profile\s*=\s*([a-z-]+)/i);
            if (profileMatch)
                resolvedProfile = profileMatch[1];
        }

        if (resolvedProfile.length > 0) {
            const nextIndex = batteryModeIndexForCommand(resolvedProfile);
            batteryModeAppliedIndex = nextIndex;
            setBatteryModeVisualIndex(nextIndex, true);

            if (batteryModeRefreshPollsRemaining > 0 && nextIndex === batteryModePendingIndex) {
                batteryModeRefreshPollsRemaining = 0;
                batteryModeRefreshTimer.stop();
                batteryModeError = "";
                batteryModeInfoMessage = batteryModeLabel(nextIndex) + " active.";
            }
        }
    }

    function buildBatteryModeStatusText() {
        if (batteryModeBusy) return "Applying " + batteryModeLabel(batteryModePendingIndex);
        if (trimString(userConfig.tlpPermissionMode) === "skip") return "TLP disabled";
        if (!batteryTlpChecked) return "Checking TLP";
        if (!batteryTlpAvailable) return "TLP is not installed";
        return batteryModeLabel(batteryModeIndex);
    }

    function rollbackBatteryMode(message) {
        batteryModeBusy = false;
        batteryModeError = message;
        batteryModeInfoMessage = "";
        batteryModeDragOffset = 0;
        setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
    }

    function classifyBatteryModeFailure(exitCode) {
        const details = trimString(batteryModeLastCommandOutput).toLowerCase();

        if (details.indexOf("sorry, try again") >= 0 || details.indexOf("incorrect password attempt") >= 0)
            return "The configured sudo password did not work.";
        if (details.indexOf("pkexec") >= 0 && details.indexOf("not installed") >= 0)
            return "Install pkexec or set tlpSudoPassword in userconfig.json.";
        if (details.indexOf("sudo is not installed") >= 0)
            return "sudo is not installed.";
        if (details.indexOf("sudo:") >= 0 && details.indexOf("password") >= 0) {
            if (trimString(userConfig.tlpPermissionMode) === "ask")
                return "Install pkexec or set tlpSudoPassword in userconfig.json.";
            return "sudo needs a password; set tlpSudoPassword in userconfig.json.";
        }
        if (details.indexOf("sudo:") >= 0 && details.indexOf("no new privileges") >= 0)
            return "sudo is blocked by the current process security flags.";
        if (details.indexOf("sudo:") >= 0 && details.indexOf("a terminal is required") >= 0)
            return "sudo needs a real terminal, but the panel could not open one.";
        if (details.indexOf("missing root privilege") >= 0)
            return "TLP needs admin permission.";
        if (details.indexOf("command not found") >= 0 || details.indexOf("not found") >= 0) {
            if (details.indexOf("tlp") >= 0)
                return "TLP is not installed.";
        }

        if (exitCode === 127)
            return "TLP is not installed.";
        if (exitCode === 126)
            return "Install pkexec or set tlpSudoPassword in userconfig.json.";
        return "TLP could not apply that mode.";
    }

    function queueBatteryModeStateRefresh(polls) {
        batteryModeRefreshPollsRemaining = Math.max(0, polls);
        if (batteryModeRefreshPollsRemaining > 0)
            batteryModeRefreshTimer.restart();
        else
            batteryModeRefreshTimer.stop();
    }

    function selectBatteryMode(index) {
        if (batteryModeBusy) {
            if (batteryModeSetterRunning)
                SystemServices.cancelTlpApply();
            batteryModeBusy = false;
            batteryModeSetterRunning = false;
        }

        queueBatteryModeStateRefresh(0);

        const nextIndex = Math.max(0, Math.min(2, index));

        if (trimString(userConfig.tlpPermissionMode) === "skip") {
            rollbackBatteryMode("TLP mode switching is disabled in userconfig.json.");
            return;
        }

        if (!batteryTlpChecked) {
            refreshBatteryModeState();
            rollbackBatteryMode("Checking TLP. Try again in a moment.");
            return;
        }

        if (!batteryTlpAvailable) {
            rollbackBatteryMode("TLP is not installed.");
            return;
        }

        if (nextIndex === batteryModeAppliedIndex) {
            batteryModeError = "";
            batteryModeInfoMessage = batteryModeLabel(nextIndex) + " active.";
            setBatteryModeVisualIndex(nextIndex, true);
            return;
        }

        batteryModePendingIndex = nextIndex;
        batteryModeBusy = true;
        batteryModeSetterRunning = true;
        batteryModeError = "";
        batteryModeInfoMessage = "Applying " + batteryModeLabel(nextIndex) + "...";
        setBatteryModeVisualIndex(nextIndex, true);
        batteryModeLastCommandOutput = "";
        SystemServices.setTlpMode(batteryModeCommand(nextIndex), trimString(userConfig.tlpSudoPassword));
    }

    function finishBatteryModeApply(success, exitCode, output, errorString) {
        batteryModeSetterRunning = false;
        batteryModeBusy = false;
        batteryModeLastCommandOutput = trimString(output);
        if (batteryModeLastCommandOutput.length === 0)
            batteryModeLastCommandOutput = trimString(errorString);

        if (!success) {
            rollbackBatteryMode(classifyBatteryModeFailure(exitCode));
            return;
        }

        batteryModeAppliedIndex = batteryModePendingIndex;
        batteryModeError = "";
        batteryModeInfoMessage = batteryModeLabel(batteryModeAppliedIndex) + " active.";
        setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
        refreshBatteryModeState();
    }

    function clearWifiPrompt() {
        wifiPendingPasswordSsid = "";
        wifiPendingPasswordValue = "";
        wifiLocalInfoMessage = "";
        wifiLocalError = "";
    }

    function clearWifiMessages() {
        wifiLocalInfoMessage = "";
        wifiLocalError = "";
        if (wifiController)
            wifiController.clearMessages();
    }

    function clearBluetoothMessages() {
        bluetoothInfoMessage = "";
        bluetoothError = "";
    }

    function submitBluetoothPairingSecret() {
        if (!bluetoothPairingAgent || !bluetoothPairingRequiresInput)
            return;

        const secret = trimString(bluetoothPendingSecretValue);
        if (!secret) {
            bluetoothError = bluetoothPairingNumericInput
                ? "Enter the 6-digit passkey first."
                : "Enter the PIN first.";
            return;
        }

        if (bluetoothPairingNumericInput && !/^\d{1,6}$/.test(secret)) {
            bluetoothError = "Passkeys must be 1 to 6 digits.";
            return;
        }

        bluetoothError = "";
        bluetoothPairingAgent.submitSecret(secret);
        bluetoothPendingSecretValue = "";
    }

    function confirmBluetoothPairing() {
        if (!bluetoothPairingAgent)
            return;

        bluetoothError = "";
        bluetoothPairingAgent.confirmRequest();
    }

    function cancelBluetoothPairing() {
        if (!bluetoothPairingAgent)
            return;

        bluetoothPairingAgent.cancelRequest();
        bluetoothPendingSecretValue = "";
    }

    function isConnectivityPanelOpen(kind) {
        if (kind === "wifi") return wifiPanelOpen;
        if (kind === "bluetooth") return bluetoothPanelOpen;
        return false;
    }

    function setConnectivityPanelOpen(kind, open, emitSignal) {
        if (emitSignal === undefined)
            emitSignal = true;

        const nextOpen = !!open;
        let changed = false;

        if (kind === "wifi") {
            changed = wifiPanelOpen !== nextOpen;
            wifiPanelOpen = nextOpen;

            if (nextOpen) {
                if (showCondition) {
                    requestWifiStateRefresh();
                    if (wifiSupported && wifiEnabled)
                        requestWifiListRefresh(true);
                }
            } else {
                clearWifiPrompt();
                clearWifiMessages();
            }
        } else if (kind === "bluetooth") {
            changed = bluetoothPanelOpen !== nextOpen;
            bluetoothPanelOpen = nextOpen;

            if (!nextOpen) {
                if (bluetoothPairingActive)
                    cancelBluetoothPairing();
                if (bluetoothAdapter && bluetoothAdapter.discovering)
                    bluetoothAdapter.discovering = false;
                bluetoothScanStopTimer.stop();
                bluetoothPairAndConnectPath = "";
                bluetoothPendingSecretValue = "";
                clearBluetoothMessages();
            }
        } else {
            return;
        }

        if (changed && emitSignal)
            connectivityPanelRequested(kind, nextOpen);
    }

    function toggleConnectivityOverlay(kind) {
    setConnectivityPanelOpen(kind, !isConnectivityPanelOpen(kind));
}

function toggleScreenshotPanel() {
    screenshotPanelOpen = !screenshotPanelOpen;
    screenshotPanelRequested(screenshotPanelOpen);
}

    function closeConnectivityPanels(emitSignals) {
        if (emitSignals === undefined)
            emitSignals = true;

        setConnectivityPanelOpen("wifi", false, emitSignals);
        setConnectivityPanelOpen("bluetooth", false, emitSignals);
        clearWifiPrompt();
        clearWifiMessages();
        clearBluetoothMessages();
    }

    function requestWifiStateRefresh() {
        if (!showCondition || !wifiController) return;
        wifiController.refreshState();
    }

    function requestWifiListRefresh(rescan) {
        if (!showCondition || !wifiController) return;
        if (!wifiSupported || !wifiAvailable || !wifiEnabled) return;
        wifiController.refreshNetworks(!!rescan);
    }

    function toggleWifiEnabled() {
        clearWifiPrompt();
        clearWifiMessages();
        if (wifiController)
            wifiController.setEnabled(!wifiEnabled);
    }

    function disconnectWifi() {
        if (!wifiSupported || !wifiAvailable) {
            wifiLocalError = wifiAvailabilityMessage.length > 0 ? wifiAvailabilityMessage : "No Wi-Fi device is available.";
            return;
        }

        clearWifiPrompt();
        clearWifiMessages();
        if (wifiController)
            wifiController.disconnectCurrent();
    }

    function connectWifiNetwork(network) {
        if (!network) return;
        if (!wifiSupported) {
            wifiLocalError = wifiAvailabilityMessage.length > 0 ? wifiAvailabilityMessage : "Wi-Fi control is unavailable.";
            return;
        }
        if (!wifiAvailable) {
            wifiLocalError = wifiAvailabilityMessage.length > 0 ? wifiAvailabilityMessage : "No Wi-Fi device is available.";
            return;
        }
        if (!wifiEnabled) {
            wifiLocalError = "Turn on Wi-Fi first.";
            return;
        }
        if (network.connected) return;

        const ssid = trimString(network.ssid);
        const networkType = trimString(network.type);
        const secure = !!network.secure;
        const savedConnection = !!network.savedConnection;

        if (!ssid) {
            wifiLocalError = "Hidden networks are not supported in this panel yet.";
            return;
        }

        if (!savedConnection && networkType === "wep") {
            wifiLocalError = "WEP networks aren't supported by this panel.";
            return;
        }

        if (!savedConnection && networkType === "8021x") {
            wifiLocalError = "802.1X networks need to be provisioned first.";
            return;
        }

        clearWifiPrompt();
        clearWifiMessages();

        if (savedConnection) {
            if (wifiController)
                wifiController.connectToNetwork(ssid);
            return;
        }

        if (!secure) {
            if (wifiController)
                wifiController.connectToNetwork(ssid);
            return;
        }

        wifiPendingPasswordSsid = ssid;
        wifiPendingPasswordValue = "";
        wifiLocalInfoMessage = "Enter the password for " + ssid + ".";
    }

    function submitWifiPassword() {
        const ssid = trimString(wifiPendingPasswordSsid);
        if (!ssid) return;

        if (trimString(wifiPendingPasswordValue).length === 0) {
            wifiLocalError = "Enter a password first.";
            return;
        }

        const password = wifiPendingPasswordValue;
        clearWifiPrompt();
        clearWifiMessages();
        if (wifiController)
            wifiController.connectToNetwork(ssid, password);
    }

    function applyBrightnessSnapshot(value) {
        if (value >= 0)
            syncBrightnessFromLevel(value);
    }

    function applyVolumeSnapshot(value) {
        if (value >= 0)
            syncVolumeFromLevel(value);
    }

    function flushBrightness(force) {
        const nextValue = clamp01(pendingBrightness);
        if (!force && Math.abs(nextValue - lastAppliedBrightness) < 0.01) return;
        if (brightnessSetterRunning) {
            brightnessApplyTimer.restart();
            return;
        }

        lastAppliedBrightness = nextValue;
        brightnessSetterRunning = true;
        SystemServices.setBrightness(nextValue);
    }

    function queueBrightness(value) {
        localBrightness = clamp01(value);
        if (showCondition && !sliderIntroPending) displayedBrightness = localBrightness;
        pendingBrightness = localBrightness;
        brightnessApplyTimer.restart();
    }

    function flushVolume(force) {
        const nextValue = clamp01(pendingVolume);
        if (!force && Math.abs(nextValue - lastAppliedVolume) < 0.01) return;
        if (volumeSetterRunning) {
            volumeApplyTimer.restart();
            return;
        }

        lastAppliedVolume = nextValue;
        volumeSetterRunning = true;
        SystemServices.setVolume(nextValue);
    }

    function queueVolume(value) {
        localVolume = clamp01(value);
        if (showCondition && !sliderIntroPending) displayedVolume = localVolume;
        pendingVolume = localVolume;
        volumeApplyTimer.restart();
    }

    function syncBrightnessFromLevel(level) {
        if (level < 0) return;
        localBrightness = clamp01(level);
        if (showCondition && !sliderIntroPending) displayedBrightness = localBrightness;
        pendingBrightness = localBrightness;
        lastAppliedBrightness = localBrightness;
    }

    function syncVolumeFromLevel(level) {
        if (level < 0) return;
        localVolume = clamp01(level);
        if (showCondition && !sliderIntroPending) displayedVolume = localVolume;
        pendingVolume = localVolume;
        lastAppliedVolume = localVolume;
    }

    function syncLevelsFromProps() {
        syncBrightnessFromLevel(brightnessLevel);
        syncVolumeFromLevel(volumeLevel);
    }

    function bluetoothDeviceName(device) {
        if (!device) return "Unknown device";
        const preferred = trimString(device.deviceName);
        if (preferred.length > 0) return preferred;

        const alias = trimString(device.name);
        if (alias.length > 0) return alias;

        const address = trimString(device.address);
        return address.length > 0 ? address : "Unknown device";
    }

    function bluetoothDeviceStateText(device) {
        if (!device) return "";
        if (device.pairing) return "Pairing";

        switch (device.state) {
        case BluetoothDeviceState.Connecting:
            return "Connecting";
        case BluetoothDeviceState.Connected:
            return "Connected";
        case BluetoothDeviceState.Disconnecting:
            return "Disconnecting";
        default:
            break;
        }

        if (device.paired || device.bonded) return "Paired";
        return "Available";
    }

    function bluetoothDeviceSubtitle(device) {
        const parts = [];
        const stateLabel = bluetoothDeviceStateText(device);
        if (stateLabel.length > 0) parts.push(stateLabel);
        if (device && device.batteryAvailable) parts.push(bluetoothBatteryPercent(device) + "%");
        return parts.join(" • ");
    }

    function bluetoothBatteryPercent(device) {
        if (!device || !device.batteryAvailable)
            return -1;

        const rawValue = Math.max(0, Number(device.battery) || 0);
        return Math.max(0, Math.min(100, Math.round(rawValue <= 1 ? rawValue * 100 : rawValue)));
    }

    function bluetoothDeviceMatchesSection(device, section) {
        if (!device) return false;

        const paired = device.paired || device.bonded;
        if (section === "connected") return device.connected;
        if (section === "paired") return !device.connected && paired;
        if (section === "available") return !paired;
        return false;
    }

    function buildBluetoothStatusText() {
        if (!bluetoothAvailable) return "Unavailable";
        if (!bluetoothEnabled) return "Off";

        const devices = bluetoothDeviceValues || [];
        const connectedNames = [];

        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (device && device.connected)
                connectedNames.push(bluetoothDeviceName(device));
        }

        if (connectedNames.length === 1) return connectedNames[0];
        if (connectedNames.length > 1) return connectedNames[0] + " +" + (connectedNames.length - 1);
        if (bluetoothAdapter.discovering) return "Scanning";
        return bluetoothBusy ? "Working..." : "On";
    }

    function toggleBluetoothEnabled() {
        if (!bluetoothAdapter) {
            bluetoothError = "No Bluetooth adapter is available.";
            return;
        }

        bluetoothError = "";
        bluetoothInfoMessage = "";
        bluetoothPairAndConnectPath = "";

        if (bluetoothAdapter.discovering)
            bluetoothAdapter.discovering = false;

        bluetoothAdapter.enabled = !bluetoothAdapter.enabled;
    }

    function toggleBluetoothScan() {
        if (!bluetoothAdapter) {
            bluetoothError = "No Bluetooth adapter is available.";
            return;
        }
        if (!bluetoothEnabled) {
            bluetoothError = "Turn on Bluetooth first.";
            return;
        }

        bluetoothError = "";
        if (bluetoothAdapter.discovering) {
            bluetoothAdapter.discovering = false;
            bluetoothInfoMessage = "";
            bluetoothScanStopTimer.stop();
        } else {
            bluetoothAdapter.discovering = true;
            bluetoothInfoMessage = "Scanning for nearby devices...";
            bluetoothScanStopTimer.restart();
        }
    }

    function handleBluetoothDevicePressed(device) {
        if (!device) return;
        if (!bluetoothAdapter || !bluetoothEnabled) {
            bluetoothError = "Turn on Bluetooth first.";
            return;
        }

        bluetoothError = "";

        if (device.connected) {
            bluetoothInfoMessage = "";
            device.disconnect();
            return;
        }

        if (device.paired || device.bonded) {
            bluetoothInfoMessage = "";
            device.connect();
            return;
        }

        bluetoothPairAndConnectPath = device.dbusPath;
        bluetoothInfoMessage = "Pairing " + bluetoothDeviceName(device) + "...";
        device.pair();
    }

    function forgetBluetoothDevice(device) {
        if (!device) return;
        if (bluetoothPairAndConnectPath === device.dbusPath)
            bluetoothPairAndConnectPath = "";
        device.forget();
    }

    anchors.fill: parent
    anchors.margins: 12
    opacity: showCondition ? 1 : 0
    visible: opacity > 0

onBrightnessLevelChanged: syncBrightnessFromLevel(brightnessLevel)
    onVolumeLevelChanged: syncVolumeFromLevel(volumeLevel)
    onIsChargingChanged: if (showBatteryTime && !batteryTimeQuery.running) batteryTimeQuery.running = true
    onShowConditionChanged: {
if (showCondition) {
            syncLevelsFromProps();
            sliderIntroPending = true;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
            sliderIntroTimer.interval = sliderIntroDelay;
            sliderIntroTimer.restart();
            refreshBatteryModeState();
            requestWifiStateRefresh();
            hyprsunsetChecker.running = true;
            if (wifiPanelOpen && wifiSupported && wifiEnabled)
                requestWifiListRefresh(true);
} else {
            sliderIntroTimer.stop();
            sliderIntroPending = false;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
closeConnectivityPanels();
            powerMenuOpen = false;
            notificationPanelOpen = false;
            expandedNotificationIndex = -1;
            appearanceMenuOpen = false;
            screenshotPanelOpen = false;
            screenshotPanelRequested(false);
            gamemodeCardFlipped = false;
        }
}
    Component.onCompleted: {
        syncLevelsFromProps();
        displayedBrightness = localBrightness;
        displayedVolume = localVolume;
        SystemServices.requestBrightness();
        SystemServices.requestVolume();
        refreshBatteryModeState();
    }

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: showCondition ? IslandMotion.contentEnterDelay : 0 }
            NumberAnimation {
                duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
            }
        }
    }

    Behavior on displayedBrightness {
        enabled: controlCenter.showCondition && !controlCenter.sliderIntroPending && !brightnessCard.pressed

        NumberAnimation {
            duration: 130
            easing.type: Easing.OutCubic
        }
    }

    Behavior on displayedVolume {
        enabled: controlCenter.showCondition && !controlCenter.sliderIntroPending && !volumeCard.pressed

        NumberAnimation {
            duration: 130
            easing.type: Easing.OutCubic
        }
    }

    Behavior on batteryDrawerProgress {
        enabled: !controlCenter.batteryDrawerDragging

        NumberAnimation {
            id: batteryDrawerProgressAnimation
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    Connections {
        target: SystemServices

        function onTlpStateReady(available, profile, output, errorString) {
            controlCenter.applyBatteryModeState(available, profile, output, errorString);
        }

        function onTlpSetFinished(success, exitCode, output, errorString) {
            controlCenter.finishBatteryModeApply(success, exitCode, output, errorString);
        }

        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "")
                controlCenter.applyBrightnessSnapshot(value);
        }

        function onBrightnessSetFinished(value, success, errorString) {
            controlCenter.brightnessSetterRunning = false;
            if (success)
                controlCenter.applyBrightnessSnapshot(value);
            if (success && Math.abs(controlCenter.pendingBrightness - controlCenter.lastAppliedBrightness) >= 0.01)
                brightnessApplyTimer.restart();
        }

        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString === "")
                controlCenter.applyVolumeSnapshot(value);
        }

        function onVolumeSetFinished(value, success, errorString) {
            controlCenter.volumeSetterRunning = false;
            if (success)
                controlCenter.applyVolumeSnapshot(value);
            if (success && Math.abs(controlCenter.pendingVolume - controlCenter.lastAppliedVolume) >= 0.01)
                volumeApplyTimer.restart();
        }
    }

Process {
        id: powerExec
        function run(cmd) { command = ["bash", "-c", cmd]; running = true }
    }

    Process {
        id: idleApplyExec
        function run(key, seconds) {
            command = ["set-hypridle", key, String(seconds)]
            running = true
        }
    }


    // ── Hyprsunset Executive Toggler ───────────────────────────────────────
    Process {
        id: hyprsunsetExec
        // Fix: Use separate array indexing for shell arguments to prevent multi-word parsing faults
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && pkill -x hyprsunset || hyprsunset --temperature 4500 &"]
    }




    Process {
        id: hyprsunsetChecker
        command: ["bash", "-c", "pgrep -x hyprsunset > /dev/null && echo 1 || echo 0"]
        function run() { running = true }
        stdout: SplitParser {
            onRead: (data) => {
                controlCenter.hyprsunsetActive = (data.trim() === "1")
            }
        }
    }

    // ── Auto-Sync Timer Loop ───────────────────────────────────────────────
    Timer {
        id: hyprsunsetTimer
        interval: 2500       // Check every 2.5 seconds
        running: true        // Starts checking automatically on launch
        repeat: true         // Keep looping indefinitely
        triggeredOnStart: true // Runs once the exact millisecond the bar loads!
        onTriggered: hyprsunsetChecker.run()
    }


    Process {
        id: screenshotExec
        function shoot(mode) {
            controlCenter.screenshotCapturing = true
            let cmd = `
                DIR="$HOME/Pictures/Screenshots"
                mkdir -p "$DIR"
                FILENAME="screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
                FINAL="$DIR/$FILENAME"
                sleep 0.3
                success=false
                if [ "${mode}" = "screen" ]; then
                    grim "$FINAL" && success=true
                elif [ "${mode}" = "active" ]; then
                    GEOM=$(hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print(f"{w[\\"at\\"][0]},{w[\\"at\\"][1]} {w[\\"size\\"][0]}x{w[\\"size\\"][1]}")' 2>/dev/null)
                    [ -n "$GEOM" ] && grim -g "$GEOM" "$FINAL" && success=true || grimblast save active "$FINAL" && success=true
                elif [ "${mode}" = "area" ]; then
                    grimblast save area "$FINAL" && success=true
                fi
                if [ "$success" = true ] && [ -f "$FINAL" ]; then
                    wl-copy < "$FINAL"
                    notify-send -a "Screenshot" -i "$FINAL" "Saved & copied" "$FILENAME"
                fi
            `
            command = ["bash", "-c", cmd]
            running = true
        }
        onRunningChanged: {
            if (!running) controlCenter.screenshotCapturing = false
        }
    }

    Timer {
        id: brightnessApplyTimer
        interval: 55
        repeat: false
        onTriggered: controlCenter.flushBrightness(false)
    }

    Timer {
        id: volumeApplyTimer
        interval: 55
        repeat: false
        onTriggered: controlCenter.flushVolume(false)
    }

    Timer {
        id: sliderIntroTimer
        interval: controlCenter.sliderIntroDelay
        repeat: false

        onTriggered: {
            controlCenter.sliderIntroPending = false;
            controlCenter.displayedBrightness = controlCenter.localBrightness;
            controlCenter.displayedVolume = controlCenter.localVolume;
        }
    }

    Timer {
        id: batteryModeRefreshTimer
        interval: 1500
        repeat: true
        onTriggered: {
            if (controlCenter.batteryModeRefreshPollsRemaining <= 0) {
                stop();
                return;
            }

            controlCenter.batteryModeRefreshPollsRemaining -= 1;
            controlCenter.refreshBatteryModeState();

            if (controlCenter.batteryModeRefreshPollsRemaining <= 0)
                stop();
        }
    }

    Timer {
        id: bluetoothScanStopTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (controlCenter.bluetoothAdapter && controlCenter.bluetoothAdapter.discovering)
                controlCenter.bluetoothAdapter.discovering = false;
            controlCenter.bluetoothInfoMessage = "";
        }
    }

    Timer {
        id: batteryDrawerSettleTimer
        interval: 300
        repeat: false
        onTriggered: controlCenter.batteryDrawerSettling = false
    }

    Connections {
        target: wifiController

        function onEnabledChanged() {
            if (!controlCenter.wifiEnabled)
                controlCenter.clearWifiPrompt();
        }
    }

    Connections {
        target: bluetoothAdapter

        function onEnabledChanged() {
            if (!controlCenter.bluetoothAdapter.enabled) {
                controlCenter.bluetoothPairAndConnectPath = "";
                controlCenter.bluetoothInfoMessage = "";
                controlCenter.bluetoothError = "";
                controlCenter.bluetoothScanStopTimer.stop();
            }
        }

        function onDiscoveringChanged() {
            if (!controlCenter.bluetoothAdapter.discovering)
                controlCenter.bluetoothScanStopTimer.stop();
        }
    }

    Connections {
        target: bluetoothPairingAgent

        function onRequestChanged() {
            controlCenter.bluetoothPendingSecretValue = "";
            if (controlCenter.bluetoothPairingActive) {
                controlCenter.bluetoothError = "";
                controlCenter.setConnectivityPanelOpen("bluetooth", true);
            }
        }

        function onRegistrationErrorChanged() {
            if (!controlCenter.bluetoothPairingAgent)
                return;

            if (!controlCenter.bluetoothPairingAgent.registered
                    && controlCenter.bluetoothPairingAgent.registrationError.length > 0
                    && controlCenter.bluetoothPanelOpen) {
                controlCenter.bluetoothError = controlCenter.bluetoothPairingAgent.registrationError;
            }
        }
    }

Column {
        id: controlCenterColumn
        anchors.fill: parent
        spacing: 12

        Item {
            width: parent.width
            height: 28

            Item {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 220
                height: parent.height

                Text {
                    renderType: Text.NativeRendering
                    id: timeLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: currentTime
                    color: IslandMotion.textPrimary
                    font.pixelSize: 19
                    font.family: heroFontFamily
                    font.weight: Font.Bold
                    font.letterSpacing: -0.45
                }

Text {
    renderType: Text.NativeRendering
                    anchors.left: timeLabel.right
                    anchors.leftMargin: 10
                    anchors.baseline: timeLabel.baseline
                    text: currentDateLabel
                    color: textSecondary
                    font.pixelSize: 12
                    font.family: textFontFamily
                    font.weight: Font.Medium
                    visible: true
                }
            }

Row {
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Text {
                    renderType: Text.NativeRendering
                    text: controlCenter.chargingIconGlyph
                    color: StyleTokens.white
                    font.pixelSize: 13
                    font.family: iconFontFamily
                    visible: isCharging
                    anchors.verticalCenter: parent.verticalCenter
                }

Text {
    renderType: Text.NativeRendering
                    text: controlCenter.showBatteryTime
                          ? controlCenter.batteryTimeText
                          : batteryCapacity + "%"
                    color: StyleTokens.white
                    font.pixelSize: 13
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: controlCenter.showBatteryTime = !controlCenter.showBatteryTime
                    }
                }

                Item {
                    width: 28
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 2
                        radius: 4
                        color: StyleTokens.transparent
                        border.color: IslandMotion.textSecondary
                        border.width: 1

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            radius: 2
                            width: (parent.width - 4) * (batteryCapacity / 100.0)
                            color: {
                                if (batteryCapacity <= 10) return StyleTokens.danger;
                                if (batteryCapacity <= 20) return StyleTokens.warning;
                                return StyleTokens.success;
                            }

                            Behavior on width {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 2
                        height: 6
                        radius: 1
                        color: IslandMotion.textSecondary
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // ── Hyprsunset button ──────────────────────────────────────
                Rectangle {
                    id: hyprsunsetBtn
                    width: 26
                    height: 26
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: controlCenter.hyprsunsetActive
                           ? Qt.rgba(0.9, 0.66, 0.29, 0.25)
                           : (sunsetBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.08))
                    border.color: controlCenter.hyprsunsetActive
                                  ? "#e5a84b"
                                  : (sunsetBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.2))
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "\uf186"
                        font.family: iconFontFamily
                        font.pixelSize: 13
                        color: controlCenter.hyprsunsetActive
                               ? "#e5a84b"
                               : (sunsetBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.9) : IslandMotion.textPrimary)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: sunsetBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // 1. Instantly flip the UI color state without waiting
                            controlCenter.hyprsunsetActive = !controlCenter.hyprsunsetActive;
                            
                            // 2. Fire the system background toggle
                            hyprsunsetExec.startDetached();
                            
                            // 3. Double-check system state after 300ms just to be certain
                            var t = _delayedCheckTimer;
                            if (!t) {
                                t = Qt.createQmlObject('import QtQuick; Timer { interval: 300; onTriggered: hyprsunsetChecker.run() }', sunsetBtnMouse);
                            }
                            t.start();
                        }
                    }


                }

// ── Appearance (capsule opacity / pywal color) button ───────
                Rectangle {
                    id: appearanceBtn
                    width: 26
                    height: 26
                    radius: 13
                    anchors.verticalCenter: parent.verticalCenter
                    color: appearanceBtnMouse.containsMouse || controlCenter.appearanceMenuOpen
                           ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                    border.color: controlCenter.appearanceMenuOpen
                                  ? Qt.rgba(1,1,1,0.4)
                                  : (appearanceBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2))
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "\uf1fc"
                        font.family: iconFontFamily
                        font.pixelSize: 13
                        color: controlCenter.appearanceMenuOpen ? StyleTokens.white : IslandMotion.textPrimary
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: appearanceBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            controlCenter.appearanceMenuOpen = !controlCenter.appearanceMenuOpen
                            if (controlCenter.appearanceMenuOpen) {
                                controlCenter.powerMenuOpen = false
                                controlCenter.notificationPanelOpen = false
                            }
                        }
                    }
                }
            }
        }

Item {
            width: parent.width
            height: 80
visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Row {
                id: connectivityCardsRow
                anchors.fill: parent
                spacing: 12

Rectangle {
                    id: wifiCard
                    width: (connectivityCardsRow.width - connectivityCardsRow.spacing) / 2
                    height: connectivityCardsRow.height
                    radius: 20
                    color: (wifiCardMouse.containsMouse || wifiPanelOpen) ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: (wifiCardMouse.containsMouse || wifiPanelOpen) ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)

                    Behavior on color {
                        ColorAnimation {
                            duration: StyleTokens.durationFast
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: StyleTokens.durationFast
                        }
                    }

                    MouseArea {
                        id: wifiCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        text: wifiGlyph
                        color: wifiEnabled ? cardAccent : IslandMotion.textFaint
                        font.pixelSize: 18
                        font.family: iconFontFamily
                    }

                    Rectangle {
                        id: wifiSwitchTrack
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 34
                        height: 20
                        radius: 10
                        color: wifiEnabled ? StyleTokens.success : StyleTokens.switchOff

                        Behavior on color {
                            ColorAnimation {
                                duration: StyleTokens.durationFast
                            }
                        }

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            y: 2
                            x: wifiEnabled ? 16 : 2
                            color: StyleTokens.white

                            Behavior on x {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            id: wifiToggleArea
                            anchors.fill: parent
                            enabled: wifiSupported && wifiAvailable && !wifiBusy
                            onClicked: controlCenter.toggleWifiEnabled()
                        }
                    }

                    Item {
                        id: wifiDetailButton
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 8
                        height: 30

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: wifiChevron.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            text: "Wi-Fi"
                            color: textPrimary
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: wifiChevron.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            text: wifiStatusText
                            color: IslandMotion.textFaint
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            id: wifiChevron
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: wifiPanelOpen ? "#c7c9cf" : IslandMotion.textFaint
                            font.pixelSize: 17
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                controlCenter.toggleConnectivityOverlay("wifi")
                            }
                        }
                    }
                }

Rectangle {
                    id: bluetoothCard
                    width: (connectivityCardsRow.width - connectivityCardsRow.spacing) / 2
                    height: connectivityCardsRow.height
                    radius: 20
                    color: (bluetoothCardMouse.containsMouse || bluetoothPanelOpen) ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: (bluetoothCardMouse.containsMouse || bluetoothPanelOpen) ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)

                    Behavior on color {
                        ColorAnimation {
                            duration: StyleTokens.durationFast
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: StyleTokens.durationFast
                        }
                    }

                    MouseArea {
                        id: bluetoothCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        text: bluetoothGlyph
                        color: bluetoothEnabled ? cardAccent : IslandMotion.textFaint
                        font.pixelSize: 18
                        font.family: iconFontFamily
                    }

                    Rectangle {
                        id: bluetoothSwitchTrack
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 34
                        height: 20
                        radius: 10
                        color: bluetoothEnabled ? StyleTokens.success : StyleTokens.switchOff

                        Behavior on color {
                            ColorAnimation {
                                duration: StyleTokens.durationFast
                            }
                        }

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            y: 2
                            x: bluetoothEnabled ? 16 : 2
                            color: StyleTokens.white

                            Behavior on x {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MouseArea {
                            id: bluetoothToggleArea
                            anchors.fill: parent
                            enabled: bluetoothAvailable && !bluetoothBusy
                            onClicked: controlCenter.toggleBluetoothEnabled()
                        }
                    }

                    Item {
                        id: bluetoothDetailButton
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 8
                        height: 30

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: bluetoothChevron.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            text: "Bluetooth"
                            color: textPrimary
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: bluetoothChevron.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            text: bluetoothStatusText
                            color: IslandMotion.textFaint
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            id: bluetoothChevron
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: bluetoothPanelOpen ? "#c7c9cf" : IslandMotion.textFaint
                            font.pixelSize: 17
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: controlCenter.toggleConnectivityOverlay("bluetooth")
                        }
                    }
                }
            }
        }

Item {
            id: batteryDrawer
            visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            readonly property real cardWidth: (width - connectivityCardsRow.spacing) / 2
            readonly property real modeSlotWidth: 44
            readonly property real openDistance: controlCenter.batteryModeCardHeight
                + controlCenter.batteryDrawerContentGap

            width: parent.width
            height: controlCenter.batteryDrawerHandleHeight
                + controlCenter.batteryDrawerProgress * openDistance
            clip: true

// ── LEFT: Gamemode / Battery card (flippable) ───────────────────
Rectangle {
                id: gamemodeCard
                anchors.left: parent.left
                y: -height + controlCenter.batteryDrawerProgress * height
                width: batteryDrawer.cardWidth
                height: controlCenter.batteryModeCardHeight
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)
                opacity: Math.min(1, controlCenter.batteryDrawerProgress * 1.35)
                clip: true

                // Which face is actually drawn — flipped mid-animation
                // (at the 90° squash point) rather than the instant the
                // button is pressed, so the swap lines up with the visual.
                property bool showBackFace: false

                transform: Rotation {
                    id: gamemodeFlipRotation
                    origin.x: gamemodeCard.width / 2
                    origin.y: gamemodeCard.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: 0
                }

                state: controlCenter.gamemodeCardFlipped ? "back" : "front"

                states: [
                    State { name: "front"; PropertyChanges { target: gamemodeFlipRotation; angle: 0 } },
                    State { name: "back";  PropertyChanges { target: gamemodeFlipRotation; angle: 180 } }
                ]

                transitions: Transition {
                    SequentialAnimation {
                        NumberAnimation {
                            target: gamemodeFlipRotation
                            property: "angle"
                            to: 90
                            duration: 150
                            easing.type: Easing.InQuad
                        }
                        ScriptAction {
                            script: gamemodeCard.showBackFace = controlCenter.gamemodeCardFlipped
                        }
                        NumberAnimation {
                            target: gamemodeFlipRotation
                            property: "angle"
                            duration: 150
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                // ── Front face: Game Mode ────────────────────────────────
                Item {
                    id: gamemodeFrontFace
                    anchors.fill: parent
                    visible: !gamemodeCard.showBackFace

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        text: "\uf11b"
                        font.family: iconFontFamily
                        font.pixelSize: 18
                        color: controlCenter.gamemodeActive ? "#60a5fa" : IslandMotion.textFaint
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 34
                        height: 20
                        radius: 10
                        color: controlCenter.gamemodeActive ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: controlCenter.gamemodeActive ? 16 : 2
                            color: StyleTokens.white
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: controlCenter.gamemodeToggleRequested()
                        }
                    }

                    // Bottom row — whole row is clickable to flip, same
                    // pattern as wifiDetailButton / bluetoothDetailButton.
                    Item {
                        id: gamemodeFrontDetailButton
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 8
                        height: 30

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: gamemodeFrontChevron.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            text: "Game Mode"
                            color: textPrimary
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: gamemodeFrontChevron.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            text: controlCenter.gamemodeActive ? "Animations disabled" : "Animations enabled"
                            color: IslandMotion.textFaint
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            id: gamemodeFrontChevron
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: IslandMotion.textFaint
                            font.pixelSize: 17
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: controlCenter.toggleGamemodeCardFlip()
                        }
                    }
                }

// ── Back face: Battery / TLP power plan (OG carousel) ────
                Item {
                    id: gamemodeBackFace
                    anchors.fill: parent
                    visible: gamemodeCard.showBackFace

                    // Counter-rotates this face by a fixed 180°. Combined with
                    // gamemodeCard's own 0→180° sweep, this cancels the mirroring
                    // that would otherwise happen — a plane rotated 180° around Y
                    // shows its content backwards, since you're looking at what
                    // would be "the other side of the glass." This keeps text
                    // and layout reading normally once the card settles at 180°.
                    transform: Rotation {
                        origin.x: gamemodeCard.width / 2
                        origin.y: gamemodeCard.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: 180
                    }

                    // Whole top row is clickable to flip back — same pattern
                    // as the front face's bottom detail row.
                    Item {
                        id: gamemodeBackDetailButton
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 8
                        height: 24

                        Text {
                            renderType: Text.NativeRendering
                            id: gamemodeBackChevron
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹"
                            color: IslandMotion.textFaint
                            font.pixelSize: 15
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: gamemodeBackChevron.right
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Battery"
                            color: textPrimary
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: controlCenter.toggleGamemodeCardFlip()
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: Math.max(0, parent.width - 88)
                        text: controlCenter.batteryModeError.length > 0
                            ? controlCenter.batteryModeError
                            : (controlCenter.batteryModeInfoMessage.length > 0
                                ? controlCenter.batteryModeInfoMessage
                                : controlCenter.batteryModeStatusText)
                        color: controlCenter.batteryModeError.length > 0 ? StyleTokens.error : IslandMotion.textFaint
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: 9
                        font.family: textFontFamily
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Item {
                        id: batteryModeCarousel
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        height: 34
                        clip: true

                        Item {
                            id: batteryModeItems
                            width: batteryDrawer.modeSlotWidth * 3
                            height: parent.height
                            x: batteryModeCarousel.width / 2
                                - batteryDrawer.modeSlotWidth / 2
                                - controlCenter.batteryModeIndex * batteryDrawer.modeSlotWidth
                                + controlCenter.batteryModeDragOffset

                            Behavior on x {
                                enabled: !controlCenter.batteryModeSliderDragging
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }

                            Repeater {
                                model: 3
                                delegate: Item {
                                    x: index * batteryDrawer.modeSlotWidth
                                    width: batteryDrawer.modeSlotWidth
                                    height: batteryModeCarousel.height
                                    opacity: index === controlCenter.batteryModeIndex ? 1 : 0.42
                                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: index === controlCenter.batteryModeIndex ? 32 : 28
                                        height: index === controlCenter.batteryModeIndex ? 28 : 24
                                        radius: 12
                                        color: index === controlCenter.batteryModeIndex ? IslandMotion.textPrimary : "#292a2f"
                                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on color { ColorAnimation { duration: 140 } }

                                        Text {
                                            renderType: Text.NativeRendering
                                            anchors.centerIn: parent
                                            text: controlCenter.batteryModeGlyphs[index]
                                            color: index === controlCenter.batteryModeIndex ? StyleTokens.module : IslandMotion.textSecondary
                                            font.pixelSize: index === controlCenter.batteryModeIndex ? 15 : 13
                                            font.family: iconFontFamily
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: 22
                            height: 2
                            radius: 1
                            color: "#5d6068"
                            opacity: 0.75
                        }

                        MouseArea {
                            anchors.fill: parent
                            property real startX: 0
                            property int startIndex: 1
                            property bool moved: false

                            function clampDrag(delta) {
                                return Math.max(-batteryDrawer.modeSlotWidth, Math.min(batteryDrawer.modeSlotWidth, delta));
                            }

                            onPressed: function(mouse) {
                                startX = mouse.x;
                                startIndex = controlCenter.batteryModeIndex;
                                moved = false;
                                controlCenter.batteryModeInfoMessage = "";
                                controlCenter.batteryModeError = "";
                                controlCenter.batteryModeSliderDragging = true;
                                controlCenter.batteryModeDragOffset = 0;
                            }

                            onPositionChanged: function(mouse) {
                                if (!pressed) return;
                                const delta = mouse.x - startX;
                                if (!moved && Math.abs(delta) < 4) return;
                                moved = true;
                                controlCenter.batteryModeDragOffset = clampDrag(delta);
                            }

                            onReleased: function(mouse) {
                                const delta = mouse.x - startX;
                                let nextIndex = startIndex;
                                if (delta <= -18) nextIndex = Math.min(2, startIndex + 1);
                                else if (delta >= 18) nextIndex = Math.max(0, startIndex - 1);
                                else if (mouse.x < width / 2 - batteryDrawer.modeSlotWidth / 2) nextIndex = Math.max(0, startIndex - 1);
                                else if (mouse.x > width / 2 + batteryDrawer.modeSlotWidth / 2) nextIndex = Math.min(2, startIndex + 1);

                                controlCenter.batteryModeSliderDragging = false;
                                controlCenter.batteryModeDragOffset = 0;
                                controlCenter.selectBatteryMode(nextIndex);
                            }

                            onCanceled: {
                                controlCenter.batteryModeSliderDragging = false;
                                controlCenter.batteryModeDragOffset = 0;
                                controlCenter.setBatteryModeVisualIndex(controlCenter.batteryModeAppliedIndex, true);
                            }
                        }
                    }
                }
            }

// ── RIGHT: Screenshot card ─────────────────────────────────────
	Rectangle {
                id: screenshotCard
                anchors.right: parent.right
                y: -height + controlCenter.batteryDrawerProgress * height
                width: batteryDrawer.cardWidth
                height: controlCenter.batteryModeCardHeight
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)
                opacity: Math.min(1, controlCenter.batteryDrawerProgress * 1.35)
                clip: true

               // Camera icon top-left
                Text {
                    renderType: Text.NativeRendering
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    text: "\uf030"
                    font.family: iconFontFamily
                    font.pixelSize: 18
                    color: controlCenter.screenshotPanelOpen
                           ? cardAccent
                           : IslandMotion.textFaint
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                // Toggle button top-right — matches wifi/bluetooth switch size
                Rectangle {
                    id: captureBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    width: 34
                    height: 20
                    radius: 10
                    color: controlCenter.screenshotPanelOpen
                           ? StyleTokens.success
                           : StyleTokens.switchOff
                    Behavior on color { ColorAnimation { duration: 140 } }

                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: controlCenter.screenshotPanelOpen ? 16 : 2
                        color: StyleTokens.white
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: capBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: controlCenter.toggleScreenshotPanel()
                    }
                }

// Bottom row — label + hint, matches gamemode card style
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 8
                    height: 30

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: "Screenshot Menu"
                        color: textPrimary
                        font.pixelSize: 13
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        text: "Press toggle icon to open"
                        color: IslandMotion.textFaint
                        font.pixelSize: 10
                        font.family: textFontFamily
                        font.weight: Font.Medium
                    }
                }
            }

            Rectangle {
                id: batteryDrawerTunnelShade
                anchors.left: parent.left
                anchors.top: parent.top
                width: batteryDrawer.cardWidth
                height: Math.max(1, controlCenter.batteryDrawerContentGap * 0.35)
                z: 6
                opacity: Math.min(0.34, controlCenter.batteryDrawerProgress * 0.45)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#9a000000"
                    }
                    GradientStop {
                        position: 1
                        color: StyleTokens.clearBlack
                    }
                }
            }

            Item {
                id: batteryDrawerHandle
                anchors.left: parent.left
                anchors.right: parent.right
                y: controlCenter.batteryDrawerProgress * batteryDrawer.openDistance
                height: controlCenter.batteryDrawerHandleHeight
                z: 10

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    width: 48
                    height: 5
                    radius: 3
                    color: controlCenter.batteryDrawerOpen ? "#d4d6dc" : IslandMotion.textFaint
                    opacity: 0.88
                }

                MouseArea {
                    id: batteryDrawerHandleArea
                    anchors.fill: parent
                    property real pointerGrabOffset: 0
                    property bool moved: false
                    property bool suppressClick: false

                    function pointerY(mouse) {
                        return batteryDrawerHandle.mapToItem(controlCenter, mouse.x, mouse.y).y;
                    }

                    function itemTop(item) {
                        return item.mapToItem(controlCenter, 0, 0).y;
                    }

                    onPressed: function(mouse) {
                        batteryDrawerSettleTimer.stop();
                        controlCenter.batteryDrawerSettling = false;
                        pointerGrabOffset = pointerY(mouse) - itemTop(batteryDrawerHandle);
                        moved = false;
                        suppressClick = false;
                        controlCenter.batteryDrawerDragging = true;
                    }

                    onPositionChanged: function(mouse) {
                        const nextHandleY = pointerY(mouse) - pointerGrabOffset - itemTop(batteryDrawer);
                        if (!moved && Math.abs(nextHandleY - batteryDrawerHandle.y) < 4)
                            return;

                        moved = true;
                        suppressClick = true;
                        controlCenter.batteryDrawerProgress = controlCenter.clamp01(nextHandleY / batteryDrawer.openDistance);
                    }

                    onReleased: {
                        controlCenter.batteryDrawerDragging = false;
                        if (moved)
                            controlCenter.setBatteryDrawerOpen(controlCenter.batteryDrawerProgress >= 0.55);
                    }

                    onCanceled: {
                        controlCenter.batteryDrawerDragging = false;
                        controlCenter.setBatteryDrawerOpen(controlCenter.batteryDrawerOpen);
                    }

                    onClicked: {
                        if (suppressClick) {
                            suppressClick = false;
                            return;
                        }

                        controlCenter.toggleBatteryDrawer();
                    }
                }
            }
        }

     // ── Power menu (inline, decoupled) ─────────────────────────────────
        Item {
            id: powerMenuDrawer
            width: parent.width
            height: controlCenter.powerMenuOpen ? powerMenuContent.height + 12 : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

Rectangle {
                id: powerMenuContent
                anchors.top: parent.top
                anchors.topMargin: 0
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: powerRow.implicitHeight + 20
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Row {
                    id: powerRow
                    anchors.centerIn: parent
                    spacing: 10
                    height: 54

                    Repeater {
                        model: [
                            { icon: "\uf023", label: "Lock",     cmd: "pidof hyprlock || hyprlock" },
                            { icon: "\uf186", label: "Sleep",    cmd: "systemctl suspend" },
                            { icon: "\uf011", label: "Logout",   cmd: "uwsm stop" },
                            { icon: "\uf021", label: "Reboot",   cmd: "systemctl reboot" },
                            { icon: "\uf08d", label: "Shutdown", cmd: "systemctl poweroff" }
                        ]

                        delegate: Column {
                            required property var modelData
                            spacing: 4

Rectangle {
                                width: 44
                                height: 44
                                radius: 14
                                color: pwrItemMouse.containsMouse
                                       ? Qt.rgba(1,1,1,0.09)
                                       : Qt.rgba(1,1,1,0.05)
                                border.color: pwrItemMouse.containsMouse
                                              ? Qt.rgba(1,1,1,0.30)
                                              : Qt.rgba(1,1,1,0.16)
                                border.width: 1
                                anchors.horizontalCenter: parent.horizontalCenter

                                Behavior on color { ColorAnimation { duration: 130 } }
                                Behavior on border.color { ColorAnimation { duration: 130 } }

                                scale: pwrItemMouse.pressed ? 0.9 : 1.0
                                Behavior on scale {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                                }

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: iconFontFamily
                                    font.pixelSize: 18
                                    color: IslandMotion.textPrimary
                                }

                                MouseArea {
                                    id: pwrItemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        controlCenter.powerMenuOpen = false
                                        powerExec.run(modelData.cmd)
                                    }
                                }
                            }

Text {
    renderType: Text.NativeRendering
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: IslandMotion.textFaint
                                font.pixelSize: 9
                                font.family: textFontFamily
                                font.weight: Font.Medium
                            }
                        }
                    }
                }

            }
        }

// ── Idle settings (separate bubble, tied to power menu) ─────────────
        Item {
            id: idleSettingsPanel
            width: parent.width
            height: controlCenter.powerMenuOpen ? idleSettingsContent.height : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: idleSettingsContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: idleSettingsColumn.implicitHeight + 28
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: idleSettingsColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 14
                    spacing: 8

Item {
                        width: parent.width
                        height: 26

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Idle Settings"
                            color: IslandMotion.textSecondary
                            font.pixelSize: 11
                            font.family: textFontFamily
                            font.weight: Font.Medium
                        }

                        Rectangle {
                            id: idleHeaderToggleBtn
                            width: 26
                            height: 26
                            radius: 13
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            color: controlCenter.idleSettingsOpen || idleHeaderToggleMouse.containsMouse
                                   ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.08)
                            border.width: 1
                            border.color: controlCenter.idleSettingsOpen
                                          ? Qt.rgba(1,1,1,0.4)
                                          : (idleHeaderToggleMouse.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2))

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "\u25BE"
                                color: controlCenter.idleSettingsOpen ? IslandMotion.textPrimary : IslandMotion.textSecondary
                                font.pixelSize: 12
                                rotation: controlCenter.idleSettingsOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: idleHeaderToggleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: controlCenter.idleSettingsOpen = !controlCenter.idleSettingsOpen
                            }
                        }
                    }

                    Item {
                        id: idleSettingsDrawer
                        width: parent.width
                        height: controlCenter.idleSettingsOpen ? idleColumn.implicitHeight : 0
                        clip: true
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Column {
                            id: idleColumn
                            width: parent.width
                            spacing: 8
                            topPadding: 4

                            Repeater {
                                model: [
                                    { key: "dim",        label: "Dim Display" },
                                    { key: "lock",       label: "Lock Screen" },
                                    { key: "displayoff", label: "Turn Display Off" },
                                    { key: "suspend",    label: "Suspend" }
                                ]

                                delegate: Row {
                                    required property var modelData
                                    width: idleColumn.width
                                    spacing: 8

Text {
    renderType: Text.NativeRendering
                                        width: 108
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: controlCenter.textSecondary
                                        font.pixelSize: 10
                                        font.family: textFontFamily
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }

ComboBox {
                                        id: idleCombo
                                        width: idleColumn.width - 116
                                        height: 30
                                        model: controlCenter.idleOptions.map(o => o.label)
                                        currentIndex: controlCenter.idleOptionIndex(modelData.key)
                                        onActivated: index => {
                                            controlCenter.setIdleTimeout(
                                                modelData.key,
                                                controlCenter.idleOptions[index].value
                                            )
                                        }

                                        background: Rectangle {
                                            radius: 10
                                            color: idleCombo.hovered ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                                            border.width: 1
                                            border.color: idleCombo.popup.visible ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                        }

                                        contentItem: Text {
     renderType: Text.NativeRendering
                                            text: idleCombo.displayText
                                            color: IslandMotion.textSecondary
                                            font.pixelSize: 11
                                            font.family: controlCenter.textFontFamily
                                            font.weight: Font.Medium
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 10
                                            rightPadding: 22
                                            elide: Text.ElideRight
                                        }

                                        indicator: Text {
     renderType: Text.NativeRendering
                                            text: "\u25BE"
                                            color: IslandMotion.textSecondary
                                            font.pixelSize: 10
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        popup: Popup {
                                            y: idleCombo.height + 4
                                            width: idleCombo.width
                                            implicitHeight: Math.min(contentItem.implicitHeight, 200)
                                            padding: 4

                                            background: Rectangle {
                                                radius: 12
                                                color: Qt.rgba(0.08, 0.08, 0.10, 0.97)
                                                border.width: 1
                                                border.color: Qt.rgba(1,1,1,0.16)
                                            }

                                            contentItem: ListView {
                                                clip: true
                                                implicitHeight: contentHeight
                                                model: idleCombo.popup.visible ? idleCombo.delegateModel : null
                                                currentIndex: idleCombo.highlightedIndex
                                                ScrollIndicator.vertical: ScrollIndicator {}
                                            }
                                        }

                                        delegate: ItemDelegate {
                                            id: idleComboDelegate
                                            width: idleCombo.width
                                            height: 28
                                            highlighted: idleCombo.highlightedIndex === index

                                            background: Rectangle {
                                                radius: 8
                                                color: idleComboDelegate.highlighted ? Qt.rgba(1,1,1,0.10) : StyleTokens.transparent
                                            }

                                            contentItem: Text {
     renderType: Text.NativeRendering
                                                text: modelData
                                                color: idleComboDelegate.highlighted ? IslandMotion.textPrimary : IslandMotion.textSecondary
                                                font.pixelSize: 11
                                                font.family: controlCenter.textFontFamily
                                                font.weight: Font.Medium
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 10
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

// ── Notification history (inline, decoupled) ───────────────────────
        Item {
            id: notificationPanelDrawer
            width: parent.width
            height: controlCenter.notificationPanelOpen ? notificationPanelContent.height + 12 : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

Rectangle {
                id: notificationPanelContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: notifPanelColumn.implicitHeight + 28
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: notifPanelColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 14
                    spacing: 8

Item {
                        width: parent.width
                        height: 24

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            color: controlCenter.textPrimary
                            font.pixelSize: 13
                            font.family: controlCenter.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Row {
                                spacing: 6
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "DND"
                                    color: controlCenter.textSecondary
                                    font.pixelSize: 10
                                    font.family: controlCenter.textFontFamily
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    id: dndSwitchTrack
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    height: 20
                                    radius: 10
                                    color: controlCenter.dndActive ? StyleTokens.success : StyleTokens.switchOff

                                    Behavior on color {
                                        ColorAnimation { duration: StyleTokens.durationFast }
                                    }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        y: 2
                                        x: controlCenter.dndActive ? 16 : 2
                                        color: StyleTokens.white

                                        Behavior on x {
                                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: controlCenter.dndToggleRequested()
                                    }
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear All"
                                visible: controlCenter.notificationHistory.length > 0
                                color: clearAllMouse.containsMouse ? "#ff6b6b" : controlCenter.textSecondary
                                font.pixelSize: 11
                                font.family: controlCenter.textFontFamily
                                font.weight: Font.Medium

                                MouseArea {
                                    id: clearAllMouse
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: controlCenter.clearNotificationHistoryRequested()
                                }
                            }
                        }
                    }

Item {
                        width: parent.width
                        height: controlCenter.notificationHistory.length > 0 ? 220 : 50

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            visible: controlCenter.notificationHistory.length === 0
                            text: "No notifications yet"
                            color: controlCenter.textSecondary
                            font.pixelSize: 11
                            font.family: controlCenter.textFontFamily
                        }

                        ListView {
                            id: notifListView
                            anchors.fill: parent
                            visible: controlCenter.notificationHistory.length > 0
                            clip: true
                            spacing: 4
                            model: controlCenter.notificationHistory.length
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                id: notifRow
                                width: notifListView.width
                                required property int index
                                property var entry: controlCenter.notificationHistory[index] || {}
                                readonly property bool isExpanded: controlCenter.expandedNotificationIndex === index
                                readonly property bool hasBody: (entry.body || "") !== "" && entry.body !== entry.summary
                                height: isExpanded ? (hasBody ? 96 : 64) : 44

                                Behavior on height {
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }

                                function relativeTime() {
                                    if (!entry.timestamp) return ""
                                    const diffMs = Date.now() - entry.timestamp
                                    const mins = Math.floor(diffMs / 60000)
                                    if (mins < 1) return "now"
                                    if (mins < 60) return mins + "m ago"
                                    const hrs = Math.floor(mins / 60)
                                    if (hrs < 24) return hrs + "h ago"
                                    return Math.floor(hrs / 24) + "d ago"
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 12
                                    clip: true
                                    color: notifRowMouse.containsMouse || notifRow.isExpanded
                                           ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.03)
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Item {
                                        width: 26; height: 26
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 9

                                        Image {
                                            id: notifIconImg
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true; cache: true
                                            visible: status === Image.Ready
                                            source: notifRow.entry.appIcon && notifRow.entry.appIcon !== ""
                                                    ? "file://" + notifRow.entry.appIcon : ""
                                        }
                                        Text {
                                            renderType: Text.NativeRendering
                                            anchors.centerIn: parent
                                            visible: !notifIconImg.visible
                                            text: "\uf0f3"
                                            font.family: controlCenter.iconFontFamily
                                            font.pixelSize: 13
                                            color: controlCenter.textSecondary
                                            opacity: 0.6
                                        }
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 9
                                        text: notifRow.relativeTime()
                                        color: controlCenter.textSecondary
                                        font.pixelSize: 9
                                        font.family: controlCenter.textFontFamily
                                        opacity: 0.6
                                    }

                                    Column {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 44
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 6
                                        spacing: 2

                                        Text {
                                            renderType: Text.NativeRendering
                                            width: parent.width
                                            text: notifRow.entry.appName || ""
                                            color: controlCenter.textPrimary
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.family: controlCenter.textFontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            renderType: Text.NativeRendering
                                            width: parent.width
                                            text: notifRow.entry.summary || ""
                                            color: controlCenter.textSecondary
                                            font.pixelSize: 10
                                            font.family: controlCenter.textFontFamily
                                            elide: notifRow.isExpanded ? Text.ElideNone : Text.ElideRight
                                            wrapMode: notifRow.isExpanded ? Text.WordWrap : Text.NoWrap
                                            maximumLineCount: notifRow.isExpanded ? 2 : 1
                                        }
                                        Text {
                                            renderType: Text.NativeRendering
                                            width: parent.width
                                            visible: notifRow.isExpanded && notifRow.hasBody
                                            text: notifRow.entry.body || ""
                                            color: controlCenter.textSecondary
                                            opacity: 0.85
                                            font.pixelSize: 10
                                            font.family: controlCenter.textFontFamily
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: notifRowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            controlCenter.expandedNotificationIndex =
                                                notifRow.isExpanded ? -1 : notifRow.index
                                            controlCenter.notificationEntryActivated(notifRow.entry)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

// ── Appearance (opacity / pywal color) drawer, inline & decoupled ──
        Item {
            id: appearanceMenuDrawer
            width: parent.width
            height: controlCenter.appearanceMenuOpen ? appearanceMenuContent.height + 12 : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

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

                    Item {
                        width: parent.width
                        height: 24

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Appearance"
                            color: controlCenter.textPrimary
                            font.pixelSize: 13
                            font.family: controlCenter.textFontFamily
                            font.weight: Font.DemiBold
                        }

Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 14

Row {
                                spacing: 6
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Pin Island"
                                    color: controlCenter.textSecondary
                                    font.pixelSize: 10
                                    font.family: controlCenter.textFontFamily
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    id: pinSwitchTrack
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    height: 20
                                    radius: 10
                                    color: controlCenter.pinned ? StyleTokens.success : StyleTokens.switchOff

                                    Behavior on color {
                                        ColorAnimation { duration: StyleTokens.durationFast }
                                    }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        y: 2
                                        x: controlCenter.pinned ? 16 : 2
                                        color: StyleTokens.white

                                        Behavior on x {
                                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                        }
                                    }

MouseArea {
                                        anchors.fill: parent
                                        onClicked: controlCenter.pinToggleRequested()
                                    }
                                }
                            }

                            Row {
                                spacing: 6
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Pywal"
                                    color: controlCenter.textSecondary
                                    font.pixelSize: 10
                                    font.family: controlCenter.textFontFamily
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    id: walSwitchTrack
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    height: 20
                                    radius: 10
                                    color: controlCenter.capsuleUseWalColor ? StyleTokens.success : StyleTokens.switchOff

                                    Behavior on color {
                                        ColorAnimation { duration: StyleTokens.durationFast }
                                    }

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        y: 2
                                        x: controlCenter.capsuleUseWalColor ? 16 : 2
                                        color: StyleTokens.white

                                        Behavior on x {
                                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: controlCenter.appearanceWalColorToggleRequested(!controlCenter.capsuleUseWalColor)
                                    }
                                }
                            }
                        }
                    }

Rectangle {
                        width: parent.width
                        height: 40
                        radius: 14
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.15)
                        color: controlCenter.capsuleUseWalColor
                               ? Qt.rgba(controlCenter.capsuleWalColor.r, controlCenter.capsuleWalColor.g, controlCenter.capsuleWalColor.b, controlCenter.capsuleOpacity)
                               : Qt.rgba(0, 0, 0, controlCenter.capsuleOpacity)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "Preview"
                            color: "white"
                            opacity: 0.55
                            font.pixelSize: 10
                            font.family: controlCenter.textFontFamily
                            font.weight: Font.Medium
                        }
                    }

// ── Pywal color swatches — only shown while Pywal is on ──
                    Item {
                        id: walSwatchRow
                        width: parent.width
                        height: controlCenter.capsuleUseWalColor && controlCenter.capsuleWalColors.length > 0 ? 40 : 0
                        clip: true
                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        ListView {
                            id: walSwatchList
                            anchors.fill: parent
                            anchors.bottomMargin: 8
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            interactive: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: controlCenter.capsuleWalColors.length

                            // Center the row when it's narrower than the viewport,
                            // left-align (normal scroll) once it overflows.
                            readonly property real contentNaturalWidth: count > 0
                                ? (count * 26 + Math.max(0, count - 1) * spacing)
                                : 0
                            leftMargin: Math.max(0, (width - contentNaturalWidth) / 2)
                            rightMargin: leftMargin

                            ScrollBar.horizontal: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                height: 4
                                contentItem: Rectangle {
                                    implicitHeight: 4; radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                }
                                background: Item {}
                            }

                            delegate: Rectangle {
                                id: swatchDelegate
                                required property int index
                                readonly property bool isActive: controlCenter.capsuleWalColorIndex === index
                                width: 26; height: 26; radius: 13
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                color: controlCenter.capsuleWalColors[index] || "#000000"
                                border.width: isActive ? 2 : 1
                                border.color: isActive ? "white" : Qt.rgba(1,1,1,0.25)
                                scale: isActive ? 1.12 : (swatchMouse.containsMouse ? 1.06 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: swatchDelegate.index
                                    color: "white"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.family: controlCenter.textFontFamily
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.65)
                                }

                                MouseArea {
                                    id: swatchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: controlCenter.appearanceWalColorIndexRequested(swatchDelegate.index)
                                }
                            }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6

                        Repeater {
                            model: [0.20, 0.40, 0.60, 0.80, 1.0]

                            delegate: Rectangle {
                                required property real modelData
                                readonly property bool isActive: Math.abs(controlCenter.capsuleOpacity - modelData) < 0.01
                                width: presetLabel.implicitWidth + 16
                                height: 26
                                radius: 13
                                color: isActive
                                       ? Qt.rgba(1,1,1,0.20)
                                       : (presetMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06))
                                border.color: isActive ? Qt.rgba(1,1,1,0.4) : Qt.rgba(1,1,1,0.12)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    renderType: Text.NativeRendering
                                    id: presetLabel
                                    anchors.centerIn: parent
                                    text: Math.round(parent.modelData * 100) + "%"
                                    color: "white"
                                    opacity: parent.isActive ? 0.95 : 0.55
                                    font.pixelSize: 10
                                    font.family: controlCenter.textFontFamily
                                    font.weight: parent.isActive ? Font.DemiBold : Font.Medium
                                }

                                MouseArea {
                                    id: presetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: controlCenter.appearanceOpacityRequested(parent.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }


// ── Dock settings drawer ─────────────────────────────────────────────
        Item {
            id: dockSettingsDrawer
            width: parent.width
            height: controlCenter.appearanceMenuOpen ? dockSettingsContent.height + 12 : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: dockSettingsContent
                anchors.top:   parent.top
                anchors.left:  parent.left
                anchors.right: parent.right
                implicitHeight: dockColumn.implicitHeight + 28
                radius: 20
                color:  Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: dockColumn
                    anchors.top:    parent.top
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    anchors.margins: 14
                    spacing: 10

                    // ── Header: "Bubble" label + on/off master toggle ────
                    // The master toggle controls BOTH bar (WorkspaceBubble + SystrayBubble)
                    // AND the dock pill. Turning it off disables everything.
                    // Turning it on re-enables whichever mode (Bar or Dock) was selected.
                    Item {
                        width: parent.width
                        height: 24

                        Text {
                            renderType:          Text.NativeRendering
                            anchors.left:        parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text:  "Bubble"
                            color: controlCenter.textPrimary
                            font.pixelSize: 13
                            font.family:    controlCenter.textFontFamily
                            font.weight:    Font.DemiBold
                        }

                        Row {
                            anchors.right:         parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                renderType:          Text.NativeRendering
                                anchors.verticalCenter: parent.verticalCenter
                                // "on" if either bar or dock is enabled
                                text:  (controlCenter.bubblesEnabled || controlCenter.dockEnabled) ? "On" : "Off"
                                color: controlCenter.textSecondary
                                font.pixelSize: 10
                                font.family:    controlCenter.textFontFamily
                                font.weight:    Font.Medium
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 20; radius: 10
                                // Active if either bar bubbles or dock pill is on
                                readonly property bool anyEnabled: controlCenter.bubblesEnabled || controlCenter.dockEnabled
                                color: anyEnabled ? StyleTokens.success : StyleTokens.switchOff
                                Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                                Rectangle {
                                    width: 16; height: 16; radius: 8; y: 2
                                    x: parent.anyEnabled ? 16 : 2
                                    color: StyleTokens.white
                                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const anyOn = controlCenter.bubblesEnabled || controlCenter.dockEnabled
                                        if (anyOn) {
                                            // Turn OFF everything — remember which mode was on
                                            if (controlCenter.bubblesEnabled) {
                                                controlCenter.lastBubbleMode = "bar"
                                                controlCenter.bubblesToggleRequested()
                                            }
                                            if (controlCenter.dockEnabled) {
                                                controlCenter.lastBubbleMode = "dock"
                                                controlCenter.dockEnabledToggleRequested()
                                            }
                                        } else {
                                            // Turn ON: restore last selected mode
                                            if (controlCenter.lastBubbleMode === "dock") {
                                                controlCenter.dockEnabledToggleRequested()
                                                if (controlCenter.bubblesEnabled)
                                                    controlCenter.bubblesToggleRequested()
                                            } else {
                                                // default: restore bar
                                                controlCenter.bubblesToggleRequested()
                                                if (controlCenter.dockEnabled)
                                                    controlCenter.dockEnabledToggleRequested()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Mode grid: [Bar | Dock] then [Pin | Smart] when Dock active ──
                    // Bar  = WorkspaceBubble + SystrayBubble only (dockEnabled=false, bubblesEnabled=true)
                    // Dock = BubbleDockWindow pill only          (dockEnabled=true,  bubblesEnabled=false)
                    // These are mutually exclusive. Enabling Bar removes Dock and vice-versa.
                    Grid {
                        width: parent.width
                        columns: 2
                        rowSpacing:    6
                        columnSpacing: 6

                        // ── Bar bubble ────────────────────────────────────
                        // Active when bubblesEnabled=true AND dockEnabled=false
                        Rectangle {
                            width:  (parent.width - 6) / 2
                            height: 36
                            radius: 12
                            readonly property bool isActive: controlCenter.bubblesEnabled && !controlCenter.dockEnabled
                            color:  isActive
                                    ? Qt.rgba(1,1,1,0.15)
                                    : (barBubbleMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05))
                            border.color: isActive ? Qt.rgba(1,1,1,0.40) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                renderType:       Text.NativeRendering
                                anchors.centerIn: parent
                                text:  "Bar"
                                color: parent.isActive ? "white" : Qt.rgba(1,1,1,0.45)
                                font.pixelSize: 12
                                font.family:    controlCenter.textFontFamily
                                font.weight:    parent.isActive ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: barBubbleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: {
                                    // Switch to Bar: disable dock, enable bubbles
                                    controlCenter.lastBubbleMode = "bar"
                                    if (controlCenter.dockEnabled)
                                        controlCenter.dockEnabledToggleRequested()
                                    if (!controlCenter.bubblesEnabled)
                                        controlCenter.bubblesToggleRequested()
                                }
                            }
                        }

                        // ── Dock bubble ───────────────────────────────────
                        // Active when dockEnabled=true AND bubblesEnabled=false
                        Rectangle {
                            width:  (parent.width - 6) / 2
                            height: 36
                            radius: 12
                            readonly property bool isActive: controlCenter.dockEnabled && !controlCenter.bubblesEnabled
                            color:  isActive
                                    ? Qt.rgba(1,1,1,0.15)
                                    : (dockBubbleMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05))
                            border.color: isActive ? Qt.rgba(1,1,1,0.40) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                renderType:       Text.NativeRendering
                                anchors.centerIn: parent
                                text:  "Dock"
                                color: parent.isActive ? "white" : Qt.rgba(1,1,1,0.45)
                                font.pixelSize: 12
                                font.family:    controlCenter.textFontFamily
                                font.weight:    parent.isActive ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: dockBubbleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: {
                                    // Switch to Dock: enable dock, disable bar bubbles
                                    controlCenter.lastBubbleMode = "dock"
                                    if (!controlCenter.dockEnabled)
                                        controlCenter.dockEnabledToggleRequested()
                                    if (controlCenter.bubblesEnabled)
                                        controlCenter.bubblesToggleRequested()
                                }
                            }
                        }

                        // ── Pin bubble — only shown when Dock is the active mode ──
                        Rectangle {
                            width:   (parent.width - 6) / 2
                            height:  controlCenter.dockEnabled ? 36 : 0
                            opacity: controlCenter.dockEnabled ? 1 : 0
                            clip: true
                            radius: 12
                            readonly property bool isActive: controlCenter.dockEnabled && controlCenter.dockMode === "pin"
                            color:  isActive
                                    ? Qt.rgba(1,1,1,0.15)
                                    : (pinBubbleMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05))
                            border.color: isActive ? Qt.rgba(1,1,1,0.40) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            Behavior on height       { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutCubic } }
                            Behavior on opacity      { NumberAnimation { duration: IslandMotion.fast } }
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                renderType:       Text.NativeRendering
                                anchors.centerIn: parent
                                text:  "Pin"
                                color: parent.isActive ? "white" : Qt.rgba(1,1,1,0.45)
                                font.pixelSize: 12
                                font.family:    controlCenter.textFontFamily
                                font.weight:    parent.isActive ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: pinBubbleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    controlCenter.dockModeChangeRequested("pin")
                            }
                        }

                        // ── Smart bubble — only shown when Dock is the active mode ──
                        Rectangle {
                            width:   (parent.width - 6) / 2
                            height:  controlCenter.dockEnabled ? 36 : 0
                            opacity: controlCenter.dockEnabled ? 1 : 0
                            clip: true
                            radius: 12
                            readonly property bool isActive: controlCenter.dockEnabled && controlCenter.dockMode === "smart"
                            color:  isActive
                                    ? Qt.rgba(1,1,1,0.15)
                                    : (smartBubbleMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05))
                            border.color: isActive ? Qt.rgba(1,1,1,0.40) : Qt.rgba(1,1,1,0.12)
                            border.width: 1
                            Behavior on height       { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutCubic } }
                            Behavior on opacity      { NumberAnimation { duration: IslandMotion.fast } }
                            Behavior on color        { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                renderType:       Text.NativeRendering
                                anchors.centerIn: parent
                                text:  "Smart"
                                color: parent.isActive ? "white" : Qt.rgba(1,1,1,0.45)
                                font.pixelSize: 12
                                font.family:    controlCenter.textFontFamily
                                font.weight:    parent.isActive ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: smartBubbleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    controlCenter.dockModeChangeRequested("smart")
                            }
                        }
                    }
                }
            }
        }

// ── Island Settings drawer ─────────────────────────────────────────
        Item {
            id: islandSettingsDrawer
            width: parent.width
            height: controlCenter.appearanceMenuOpen ? islandSettingsContent.height + 12 : 0
            clip: true

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: islandSettingsContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: islandSettingsColumn.implicitHeight + 28
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: islandSettingsColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 14
                    spacing: 10

                    Item {
                        width: parent.width
                        height: 24

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Focus Settings"
                            color: controlCenter.textPrimary
                            font.pixelSize: 13
                            font.family: controlCenter.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                renderType: Text.NativeRendering
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Focus Mode"
                                color: controlCenter.textSecondary
                                font.pixelSize: 10
                                font.family: controlCenter.textFontFamily
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                id: idleModeSwitchTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 20
                                radius: 10
                                color: controlCenter.idleMode ? StyleTokens.success : StyleTokens.switchOff

                                Behavior on color {
                                    ColorAnimation { duration: StyleTokens.durationFast }
                                }

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    y: 2
                                    x: controlCenter.idleMode ? 16 : 2
                                    color: StyleTokens.white

                                    Behavior on x {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        controlCenter.idleMode = !controlCenter.idleMode
                                        controlCenter.idleModeToggleRequested(controlCenter.idleMode)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: "Hides the island and moves widgets to the background layer. Everything is visible on empty workspaces and hidden when windows are open."
                        color: controlCenter.textSecondary
                        font.pixelSize: 10
                        font.family: controlCenter.textFontFamily
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                    }

                    // ── Sidebar ───────────────────────────────────────────
                    Item {
                        width: parent.width
                        height: 24

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Sidebar"
                            color: controlCenter.textPrimary
                            font.pixelSize: 13
                            font.family: controlCenter.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                renderType: Text.NativeRendering
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Show Sidebar"
                                color: controlCenter.textSecondary
                                font.pixelSize: 10
                                font.family: controlCenter.textFontFamily
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                id: sidebarSwitchTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 20
                                radius: 10
                                color: controlCenter.sidebarEnabled ? StyleTokens.success : StyleTokens.switchOff

                                Behavior on color {
                                    ColorAnimation { duration: StyleTokens.durationFast }
                                }

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    y: 2
                                    x: controlCenter.sidebarEnabled ? 16 : 2
                                    color: StyleTokens.white

                                    Behavior on x {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: controlCenter.sidebarToggleRequested()
                                }
                            }
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: "Shows a slim pill on the left edge of the screen that replaces the main bar."
                        color: controlCenter.textSecondary
                        font.pixelSize: 10
                        font.family: controlCenter.textFontFamily
                        wrapMode: Text.WordWrap
                        opacity: 0.7
                    }
                }
            }
        }

        ControlSliderCard {
            id: brightnessCard
            visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            width: parent.width
            height: 76
            title: "Display"
            iconText: controlCenter.brightnessIconGlyph
            iconFontFamily: controlCenter.iconFontFamily
            textFontFamily: controlCenter.textFontFamily
            value: controlCenter.displayedBrightness
            knobSize: controlCenter.sliderKnobSize
            moduleColor: Qt.rgba(1,1,1,0.05)
            moduleHover: Qt.rgba(1,1,1,0.09)
            trackColor: controlCenter.trackColor
            textPrimary: controlCenter.textPrimary
            textSecondary: controlCenter.textSecondary

            onInteractionStarted: {
                if (controlCenter.sliderIntroPending) {
                    sliderIntroTimer.stop();
                    controlCenter.sliderIntroPending = false;
                    controlCenter.displayedBrightness = controlCenter.localBrightness;
                    controlCenter.displayedVolume = controlCenter.localVolume;
                }
            }
            onValueMoved: function(value) {
                controlCenter.queueBrightness(value);
            }
            onCommitRequested: {
                brightnessApplyTimer.stop();
                controlCenter.flushBrightness(true);
            }
            onCancelRequested: SystemServices.requestBrightness()
        }

ControlSliderCard {
            id: volumeCard
            visible: !controlCenter.powerMenuOpen && !controlCenter.notificationPanelOpen && !controlCenter.appearanceMenuOpen
            opacity: (controlCenter.powerMenuOpen || controlCenter.notificationPanelOpen || controlCenter.appearanceMenuOpen) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            width: parent.width
            height: 76
            title: "Sound"
            iconText: controlCenter.volumeIconGlyph
            iconFontFamily: controlCenter.iconFontFamily
            textFontFamily: controlCenter.textFontFamily
            value: controlCenter.displayedVolume
            knobSize: controlCenter.sliderKnobSize
            moduleColor: Qt.rgba(1,1,1,0.05)
            moduleHover: Qt.rgba(1,1,1,0.09)
            trackColor: controlCenter.trackColor
            textPrimary: controlCenter.textPrimary
            textSecondary: controlCenter.textSecondary

            onInteractionStarted: {
                if (controlCenter.sliderIntroPending) {
                    sliderIntroTimer.stop();
                    controlCenter.sliderIntroPending = false;
                    controlCenter.displayedBrightness = controlCenter.localBrightness;
                    controlCenter.displayedVolume = controlCenter.localVolume;
                }
            }
            onValueMoved: function(value) {
                controlCenter.queueVolume(value);
            }
            onCommitRequested: {
                volumeApplyTimer.stop();
                controlCenter.flushVolume(true);
            }
            onCancelRequested: SystemServices.requestVolume()
        }
    }

}
