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
    signal bluetoothExpandRequested()
signal appearanceOpacityRequested(real value)
    signal appearanceWalColorToggleRequested(bool enabled)
signal appearanceWalColorIndexRequested(int index)
signal gamemodeToggleRequested()
signal pinToggleRequested()
    property bool pinned: false
signal bubblesToggleRequested()
    property bool bubblesEnabled: true
    
    signal dockEnabledToggleRequested()
    property bool   dockEnabled: true
    signal dockModeChangeRequested(string mode)
    property string dockMode: "pin"
    onDockModeChanged: {
        if (dockMode === "bump") smartCardFlipped = true
        else if (dockMode === "smart") smartCardFlipped = false
    }
    signal idleModeToggleRequested(bool enabled)
    property bool idleMode: false
    signal sidebarToggleRequested()
    property bool sidebarEnabled: false
    
    property string lastBubbleMode: "bar"
    property bool appearanceMenuOpen: false
    property bool smartCardFlipped: false
    property real capsuleOpacity: 0.20
    property bool capsuleUseWalColor: false
    property var capsuleWalColors: []
    property int capsuleWalColorIndex: 0
    readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex]
        : "#000000"

    readonly property real appearanceMenuTotalHeight: 428
    readonly property real preferredWidth: appearanceMenuOpen ? 480 : 440

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily

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
property bool gamemodeActive: false

    property bool hyprsunsetActive: false
    property string screenshotMode: "area"
    property bool screenshotCapturing: false
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
    property bool batteryModeBusy: false
    property bool batteryModeStateRunning: false
    property bool batteryModeSetterRunning: false
    property bool batteryTlpAvailable: false
    property bool batteryTlpChecked: false
    property int batteryModeIndex: 1
    property int batteryModeAppliedIndex: 1
    property int batteryModePendingIndex: 1
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

    readonly property color textPrimary: IslandMotion.textPrimary
    readonly property color textSecondary: IslandMotion.textSecondary
    readonly property string wifiGlyph: ""
    readonly property string bluetoothGlyph: ""
    readonly property string chargingIconGlyph: "\uf0e7"
    readonly property string brightnessIconGlyph: "\u{F00DF}"
    readonly property string volumeIconGlyph: "\u{F057E}"
    readonly property real controlCenterExtraHeight: 84
    readonly property real controlCenterMaximumExtraHeight: 108
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDeviceValues: bluetoothAdapter ? bluetoothAdapter.devices.values : []
    readonly property bool wifiSupported: wifiController ? wifiController.supported : false
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

    anchors.fill: parent
    // Kept visible (but transparent and non-interactive) while closed, so its
    // scene-graph nodes, glyphs and textures exist before the first open.
    // For the first ~1.2s after startup it renders at 1% opacity (effectively
    // invisible) so Qt really builds and uploads everything; Qt may skip
    // fully transparent (opacity 0) subtrees, which would defeat the warm-up.
    property bool warmedUp: false
    opacity: showCondition ? 1 : (warmedUp ? 0 : 0.01)
    visible: true
    enabled: showCondition

    Timer {
        id: warmUpTimer
        interval: 1200
        running: true
        repeat: false
        onTriggered: controlCenter.warmedUp = true
    }

onBrightnessLevelChanged: syncBrightnessFromLevel(brightnessLevel)
    onVolumeLevelChanged: syncVolumeFromLevel(volumeLevel)
    onIsChargingChanged: if (showBatteryTime && !batteryTimeQuery.running) batteryTimeQuery.running = true
    function resetTransientState() {
        showBatteryTime = false;
        batteryTimeText = "";
    }

    onShowConditionChanged: {
if (showCondition) {
            syncLevelsFromProps();
            sliderIntroPending = true;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
            sliderIntroTimer.interval = sliderIntroDelay;
            sliderIntroTimer.restart();
            openRefreshTimer.restart();
} else {
            resetTransientState();
            sliderIntroTimer.stop();
            openRefreshTimer.stop();
            sliderIntroPending = false;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
closeConnectivityPanels();
            appearanceMenuOpen = false;
            screenshotPanelOpen = false;
            screenshotPanelRequested(false);
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

    // No fade on opacity: the other layers (power menu, player, ...) are created
    // and destroyed with their state, so their content appears and disappears
    // instantly. A fade here made the control center linger over the next layer
    // on close and arrive ~400ms late on open.

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
        id: hyprsunsetExec
        
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

    // Runs the state refreshes (battery, wifi, hyprsunset) after the capsule
    // has finished morphing so process spawns don't compete with the first frames.
    Timer {
        id: openRefreshTimer
        interval: IslandMotion.standard
        repeat: false

        onTriggered: {
            if (!controlCenter.showCondition) return;
            controlCenter.refreshBatteryModeState();
            controlCenter.requestWifiStateRefresh();
            hyprsunsetChecker.running = true;
            if (controlCenter.wifiPanelOpen && controlCenter.wifiSupported && controlCenter.wifiEnabled)
                controlCenter.requestWifiListRefresh(true);
        }
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

    Timer {
        id: hyprsunsetCheckTimer
        interval: 300
        repeat: false
        onTriggered: hyprsunsetChecker.run()
    }

    function toggleHyprsunset() {
        hyprsunsetActive = !hyprsunsetActive;
        hyprsunsetExec.startDetached();
        hyprsunsetCheckTimer.restart();
    }

    function toggleBubbleMaster() {
        const anyOn = bubblesEnabled || dockEnabled;
        if (anyOn) {
            if (bubblesEnabled) {
                lastBubbleMode = "bar";
                bubblesToggleRequested();
            }
            if (dockEnabled) {
                lastBubbleMode = "dock";
                dockEnabledToggleRequested();
            }
        } else if (lastBubbleMode === "dock") {
            dockEnabledToggleRequested();
            if (bubblesEnabled)
                bubblesToggleRequested();
        } else {
            bubblesToggleRequested();
            if (dockEnabled)
                dockEnabledToggleRequested();
        }
    }

    function toggleSmartBump() {
        const targetMode = smartCardFlipped ? "bump" : "smart";
        if (dockEnabled && dockMode === targetMode) {
            dockEnabledToggleRequested();
        } else {
            dockModeChangeRequested(targetMode);
            if (!dockEnabled)
                dockEnabledToggleRequested();
        }
    }

    function toggleIdleMode() {
        idleMode = !idleMode;
        idleModeToggleRequested(idleMode);
    }

    Item {
        id: mainPage
        anchors.fill: parent
        visible: opacity > 0
        enabled: !controlCenter.appearanceMenuOpen
        opacity: controlCenter.appearanceMenuOpen ? 0 : 1

        transform: Translate {
            x: controlCenter.appearanceMenuOpen ? -28 : 0

            Behavior on x {
                NumberAnimation {
                    duration: 240
                    easing.type: IslandMotion.easeOut
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        readonly property real sideMargin: 20
        readonly property real columnGap: 24
        readonly property real rightColumnWidth: 140
        readonly property real leftColumnWidth: width - sideMargin * 2 - columnGap - rightColumnWidth

        Item {
            id: headerRow
            width: parent.width
            height: 52

            Text {
                id: timeLabel
                renderType: Text.NativeRendering
                anchors.left: parent.left
                anchors.leftMargin: mainPage.sideMargin
                anchors.verticalCenter: parent.verticalCenter
                text: currentTime
                color: IslandMotion.textPrimary
                font.pixelSize: 26
                font.family: heroFontFamily
                font.weight: Font.Medium
                font.letterSpacing: -0.45
            }
            Text {
                renderType: Text.NativeRendering
                anchors.left: timeLabel.right
                anchors.leftMargin: 10
                anchors.baseline: timeLabel.baseline
                text: currentDateLabel
                color: textSecondary
                font.pixelSize: 13
                font.family: textFontFamily
                font.weight: Font.Medium
            }

            MouseArea {
                anchors.fill: batteryGroup
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: controlCenter.showBatteryTime = !controlCenter.showBatteryTime
            }

            Row {
                id: batteryGroup
                anchors.right: parent.right
                anchors.rightMargin: mainPage.sideMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    renderType: Text.NativeRendering
                    text: controlCenter.chargingIconGlyph
                    color: IslandMotion.textPrimary
                    font.pixelSize: 13
                    font.family: iconFontFamily
                    visible: isCharging
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    renderType: Text.NativeRendering
                    text: (controlCenter.showBatteryTime && controlCenter.batteryTimeText.length > 0)
                          ? controlCenter.batteryTimeText
                          : batteryCapacity + "%"
                    color: IslandMotion.textPrimary
                    font.pixelSize: 14
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    width: 28
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 2
                        radius: 4
                        color: "transparent"
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
                                return IslandMotion.textPrimary;
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
            }
        }

        Row {
            id: toggleRow
            x: mainPage.sideMargin
            y: 52
            width: parent.width - mainPage.sideMargin * 2

            ControlToggle {
                width: toggleRow.width / 4
                glyph: controlCenter.wifiGlyph.length > 0 ? controlCenter.wifiGlyph : "\uf1eb"
                label: "Wi-Fi"
                status: controlCenter.wifiEnabled && controlCenter.wifiCurrentSsid.length > 0
                        ? controlCenter.wifiCurrentSsid
                        : controlCenter.wifiStatusText
                active: controlCenter.wifiEnabled
                hasDetail: true
                detailOpen: controlCenter.wifiPanelOpen
                toggleEnabled: controlCenter.wifiSupported && controlCenter.wifiAvailable && !controlCenter.wifiBusy
                iconFontFamily: controlCenter.iconFontFamily
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.toggleWifiEnabled()
                onDetailRequested: controlCenter.toggleConnectivityOverlay("wifi")
            }
            ControlToggle {
                width: toggleRow.width / 4
                glyph: controlCenter.bluetoothGlyph.length > 0 ? controlCenter.bluetoothGlyph : "\uf294"
                label: "Bluetooth"
                status: controlCenter.bluetoothStatusText
                active: controlCenter.bluetoothEnabled
                hasDetail: true
                detailOpen: controlCenter.bluetoothPanelOpen
                toggleEnabled: controlCenter.bluetoothAvailable && !controlCenter.bluetoothBusy
                iconFontFamily: controlCenter.iconFontFamily
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.toggleBluetoothEnabled()
                onDetailRequested: controlCenter.toggleConnectivityOverlay("bluetooth")
                onContextRequested: controlCenter.bluetoothExpandRequested()
            }
            ControlToggle {
                width: toggleRow.width / 4
                glyph: "\uf186"
                label: "Night Light"
                active: controlCenter.hyprsunsetActive
                iconFontFamily: controlCenter.iconFontFamily
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.toggleHyprsunset()
            }
            ControlToggle {
                width: toggleRow.width / 4
                glyph: "\uf1fc"
                label: "Appearance"
                active: controlCenter.appearanceMenuOpen
                iconFontFamily: controlCenter.iconFontFamily
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.appearanceMenuOpen = true
            }
        }

        Rectangle {
            x: mainPage.sideMargin
            y: 146
            width: parent.width - mainPage.sideMargin * 2
            height: 1
            color: IslandMotion.hairlineColor
        }

        Column {
            x: mainPage.sideMargin
            y: 162
            width: mainPage.leftColumnWidth

            Item {
                width: parent.width
                height: 84

                ControlRow {
                    width: parent.width
                    glyph: controlCenter.brightnessIconGlyph
                    title: "Display"
                    sub: Math.round(controlCenter.displayedBrightness * 100) + "%"
                    clickable: false
                    iconFontFamily: controlCenter.iconFontFamily
                    textFontFamily: controlCenter.textFontFamily
                }
                ControlTrack {
                    id: brightnessCard
                    y: 52
                    width: parent.width
                    value: controlCenter.displayedBrightness
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
            }

            Item {
                width: parent.width
                height: 84

                ControlRow {
                    width: parent.width
                    glyph: controlCenter.volumeIconGlyph
                    title: "Sound"
                    sub: Math.round(controlCenter.displayedVolume * 100) + "%"
                    clickable: false
                    iconFontFamily: controlCenter.iconFontFamily
                    textFontFamily: controlCenter.textFontFamily
                }
                ControlTrack {
                    id: volumeCard
                    y: 52
                    width: parent.width
                    value: controlCenter.displayedVolume
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

        Column {
            x: mainPage.sideMargin + mainPage.leftColumnWidth + mainPage.columnGap
            y: 162
            width: mainPage.rightColumnWidth

            Item {
                width: parent.width
                height: 84

                ControlRow {
                    width: parent.width
                    glyph: "\uf11b"
                    title: "Game Mode"
                    sub: controlCenter.gamemodeActive ? "Animations off" : "Animations on"
                    active: controlCenter.gamemodeActive
                    iconFontFamily: controlCenter.iconFontFamily
                    textFontFamily: controlCenter.textFontFamily
                    onClicked: controlCenter.gamemodeToggleRequested()
                }
            }

            Item {
                width: parent.width
                height: 84

                ControlRow {
                    width: parent.width
                    glyph: "\uf030"
                    title: "Screenshot"
                    sub: "Menu  ›"
                    active: controlCenter.screenshotPanelOpen
                    iconFontFamily: controlCenter.iconFontFamily
                    textFontFamily: controlCenter.textFontFamily
                    onClicked: controlCenter.toggleScreenshotPanel()
                }
            }
        }

        Column {
            x: mainPage.sideMargin
            y: 342
            width: 120
            spacing: 1

            Text {
                renderType: Text.NativeRendering
                text: "Power Mode"
                color: IslandMotion.textPrimary
                font.pixelSize: 13
                font.family: textFontFamily
                font.weight: Font.DemiBold
            }
            Text {
                renderType: Text.NativeRendering
                width: parent.width
                text: controlCenter.batteryModeError.length > 0
                      ? controlCenter.batteryModeError
                      : (controlCenter.batteryModeInfoMessage.length > 0
                         ? controlCenter.batteryModeInfoMessage
                         : controlCenter.batteryModeStatusText)
                color: controlCenter.batteryModeError.length > 0 ? StyleTokens.error : IslandMotion.textFaint
                font.pixelSize: 10
                font.family: textFontFamily
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        ControlPillGroup {
            anchors.right: parent.right
            anchors.rightMargin: mainPage.sideMargin - 4
            y: 346
            model: ["Saver", "Balanced", "Performance"]
            currentIndex: controlCenter.batteryModeIndex
            textFontFamily: controlCenter.textFontFamily
            onActivated: function(index) {
                controlCenter.selectBatteryMode(index);
            }
        }
    }

    Item {
        id: appearancePage
        anchors.fill: parent
        visible: opacity > 0
        enabled: controlCenter.appearanceMenuOpen
        opacity: controlCenter.appearanceMenuOpen ? 1 : 0

        transform: Translate {
            x: controlCenter.appearanceMenuOpen ? 0 : 28

            Behavior on x {
                NumberAnimation {
                    duration: 240
                    easing.type: IslandMotion.easeOut
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        readonly property real sideMargin: 20
        readonly property real columnGap: 24
        readonly property real columnWidth: (width - sideMargin * 2 - columnGap) / 2

        Item {
            width: parent.width
            height: 52

            Text {
                id: backGlyph
                renderType: Text.NativeRendering
                anchors.left: parent.left
                anchors.leftMargin: appearancePage.sideMargin
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf053"
                color: IslandMotion.textPrimary
                font.pixelSize: 15
                font.family: iconFontFamily
            }
            Text {
                renderType: Text.NativeRendering
                anchors.left: backGlyph.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "Appearance"
                color: IslandMotion.textPrimary
                font.pixelSize: 20
                font.family: heroFontFamily
                font.weight: Font.Medium
            }
            MouseArea {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                height: parent.height
                cursorShape: Qt.PointingHandCursor
                onClicked: controlCenter.appearanceMenuOpen = false
            }
        }

        Column {
            id: appearanceColumn
            x: appearancePage.sideMargin
            y: 60
            width: appearancePage.columnWidth

            ControlSwitchRow {
                width: parent.width
                label: "Pin Island"
                on: controlCenter.pinned
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.pinToggleRequested()
            }
            ControlSwitchRow {
                width: parent.width
                label: "Liquid Glass"
                on: Glass.enabled
                textFontFamily: controlCenter.textFontFamily
                onToggled: Glass.setEnabled(!Glass.enabled)
            }
            ControlSwitchRow {
                width: parent.width
                label: "Pywal"
                on: controlCenter.capsuleUseWalColor
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.appearanceWalColorToggleRequested(!controlCenter.capsuleUseWalColor)
            }

            Item { width: 1; height: 12 }

            Rectangle {
                width: parent.width
                height: 36
                radius: 12
                color: controlCenter.capsuleUseWalColor
                       ? Qt.rgba(controlCenter.capsuleWalColor.r, controlCenter.capsuleWalColor.g, controlCenter.capsuleWalColor.b, controlCenter.capsuleOpacity)
                       : Qt.rgba(0, 0, 0, controlCenter.capsuleOpacity)

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "Preview"
                    color: IslandMotion.textPrimary
                    opacity: 0.7
                    font.pixelSize: 12
                    font.family: textFontFamily
                    font.weight: Font.Medium
                }
            }

            Item {
                width: parent.width
                height: controlCenter.capsuleUseWalColor && controlCenter.capsuleWalColors.length > 0 ? 40 : 0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.topMargin: 10
                    orientation: ListView.Horizontal
                    spacing: 4
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: controlCenter.capsuleWalColors.length

                    ScrollBar.horizontal: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        height: 4

                        contentItem: Rectangle {
                            implicitHeight: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.25)
                        }
                    }

                    delegate: Item {
                        id: swatchDelegate
                        required property int index
                        readonly property bool isActive: controlCenter.capsuleWalColorIndex === index
                        width: 26
                        height: 26

                        Rectangle {
                            anchors.centerIn: parent
                            width: swatchDelegate.isActive ? 26 : 22
                            height: width
                            radius: width / 2
                            color: controlCenter.capsuleWalColors[swatchDelegate.index] || "#000000"

                            scale: swatchArea.containsMouse ? 1.14 : 1.0

                            Behavior on width {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: IslandMotion.easeSpring
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                visible: swatchDelegate.isActive
                                text: swatchDelegate.index
                                color: "white"
                                font.pixelSize: 11
                                font.family: textFontFamily
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: swatchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: controlCenter.appearanceWalColorIndexRequested(swatchDelegate.index)
                        }
                    }
                }
            }

            Item { width: 1; height: 10 }

            ControlPillGroup {
                readonly property var levels: [0.20, 0.40, 0.60, 0.80, 1.0]
                model: ["20%", "40%", "60%", "80%", "100%"]
                currentIndex: {
                    for (let i = 0; i < levels.length; i++) {
                        if (Math.abs(controlCenter.capsuleOpacity - levels[i]) < 0.01)
                            return i;
                    }
                    return -1;
                }
                pillHeight: 26
                sidePadding: 7
                fontSize: 11
                spacing: 3
                textFontFamily: controlCenter.textFontFamily
                onActivated: function(index) {
                    controlCenter.appearanceOpacityRequested(levels[index]);
                }
            }
        }

        Rectangle {
            x: appearancePage.sideMargin + appearancePage.columnWidth + appearancePage.columnGap / 2
            y: 64
            width: 1
            height: 236
            color: IslandMotion.hairlineColor
        }

        Column {
            x: appearancePage.sideMargin + appearancePage.columnWidth + appearancePage.columnGap
            y: 60
            width: appearancePage.columnWidth

            ControlSwitchRow {
                width: parent.width
                label: "Bubble"
                on: controlCenter.bubblesEnabled || controlCenter.dockEnabled
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.toggleBubbleMaster()
            }

            Item { width: 1; height: 8 }

            Row {
                spacing: 6

                ControlPill {
                    width: (appearancePage.columnWidth - 6) / 2
                    height: 30
                    label: "Bar"
                    active: controlCenter.bubblesEnabled
                    textFontFamily: controlCenter.textFontFamily
                    onClicked: controlCenter.bubblesToggleRequested()
                }
                ControlPill {
                    width: (appearancePage.columnWidth - 6) / 2
                    height: 30
                    label: "Dock"
                    active: controlCenter.dockEnabled
                    textFontFamily: controlCenter.textFontFamily
                    onClicked: controlCenter.dockEnabledToggleRequested()
                }
            }

            Item {
                width: parent.width
                height: controlCenter.dockEnabled ? 38 : 0
                opacity: controlCenter.dockEnabled ? 1 : 0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                    }
                }

                Row {
                    y: 8
                    spacing: 6

                    ControlPill {
                        width: (appearancePage.columnWidth - 6) / 2
                        height: 30
                        label: "Pin"
                        active: controlCenter.dockEnabled && controlCenter.dockMode === "pin"
                        textFontFamily: controlCenter.textFontFamily
                        onClicked: controlCenter.dockModeChangeRequested("pin")
                    }
                    ControlPill {
                        width: (appearancePage.columnWidth - 6) / 2
                        height: 30
                        label: (controlCenter.smartCardFlipped ? "Bump" : "Smart") + "  ⇄"
                        active: controlCenter.dockEnabled
                                && ((!controlCenter.smartCardFlipped && controlCenter.dockMode === "smart")
                                    || (controlCenter.smartCardFlipped && controlCenter.dockMode === "bump"))
                        textFontFamily: controlCenter.textFontFamily
                        onClicked: controlCenter.toggleSmartBump()
                        onRightClicked: controlCenter.smartCardFlipped = !controlCenter.smartCardFlipped
                    }
                }
            }

            Item { width: 1; height: 16 }

            Text {
                renderType: Text.NativeRendering
                text: "Focus Settings"
                color: IslandMotion.textSecondary
                font.pixelSize: 11
                font.family: textFontFamily
                font.weight: Font.Medium
            }
            ControlSwitchRow {
                width: parent.width
                label: "Focus Mode"
                on: controlCenter.idleMode
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.toggleIdleMode()
            }
            Text {
                renderType: Text.NativeRendering
                width: parent.width
                text: "Hides the island and moves widgets to the background layer. Everything is visible on empty workspaces and hidden when windows are open."
                color: IslandMotion.textFaint
                font.pixelSize: 10
                font.family: textFontFamily
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
        }

        Item {
            x: appearancePage.sideMargin
            y: 328
            width: parent.width - appearancePage.sideMargin * 2
            height: 80

            Text {
                renderType: Text.NativeRendering
                text: "Sidebar"
                color: IslandMotion.textSecondary
                font.pixelSize: 11
                font.family: textFontFamily
                font.weight: Font.Medium
            }
            ControlSwitchRow {
                y: 16
                width: parent.width
                label: "Show Sidebar"
                on: controlCenter.sidebarEnabled
                textFontFamily: controlCenter.textFontFamily
                onToggled: controlCenter.sidebarToggleRequested()
            }
            Text {
                renderType: Text.NativeRendering
                y: 58
                width: parent.width
                text: "Shows a slim pill on the left edge of the screen that replaces the main bar."
                color: IslandMotion.textFaint
                font.pixelSize: 10
                font.family: textFontFamily
                font.weight: Font.Medium
            }
        }
    }
}
