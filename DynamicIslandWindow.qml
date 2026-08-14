import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import IslandBackend
import "qml/common"
import "qml/controlcenter"
import "qml/connectivity"
import "qml/island"
import "qml/workspace"
import "qml/shared"

PanelWindow {
    id: root
    property var shellRootController: null
    property string overviewPhase: "closed"
    property bool overviewPreloading: false
    readonly property bool overviewPreparing: overviewPhase === "preparing"
    readonly property bool overviewVisible: overviewPhase === "preparing" || overviewPhase === "opening" || overviewPhase === "open"
    readonly property bool overviewMounted: overviewPhase !== "closed" || overviewPreloading
    readonly property bool overviewLoaderActive: overviewMounted || overviewUnloadGraceTimer.running
    readonly property bool overviewDataReady: overviewLoader.item
        ? !!overviewLoader.item.overviewDataReady
        : false
    readonly property bool overviewWallpaperReady: overviewWallpaperCache.ready
    readonly property bool overviewVisualReady: overviewDataReady && overviewWallpaperReady
    readonly property bool overviewContentVisible: (overviewPhase === "opening" || overviewPhase === "open")
        && overviewVisualReady
    readonly property var hyprMonitor: screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
    readonly property string hyprMonitorName: hyprMonitor && hyprMonitor.name ? String(hyprMonitor.name) : ""
    readonly property bool monitorFocused: hyprMonitor ? hyprMonitor.focused : false
    readonly property bool connectivityPromptActive: controlCenterLoader.item
        ? controlCenterLoader.item.hasConnectivityPrompt
        : false
    readonly property int currentMonitorWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace
        ? hyprMonitor.activeWorkspace.id
        : 1
readonly property bool screenRecordingActive: shellRootController
    && shellRootController.screenRecordingActive !== undefined
    ? !!shellRootController.screenRecordingActive || gpuRecorderActive
    : gpuRecorderActive

property bool gpuRecorderActive: false

Process {
    id: gpuRecorderPoll
    property string _buf: ""
  command: ["bash", "-c", "lsof -c gpu-screen-rec 2>/dev/null | grep -qE '\\.mp4|\\.mkv|\\.flv' && echo 1 || echo 0"]
    stdout: SplitParser { onRead: gpuRecorderPoll._buf += data }
    onRunningChanged: {
        if (!running) {
            root.gpuRecorderActive = gpuRecorderPoll._buf.trim() === "1"
            gpuRecorderPoll._buf = ""
        }
    }
}

Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!gpuRecorderPoll.running) gpuRecorderPoll.running = true
}

 readonly property var userConfig: UserConfig
property bool gamemodeActive: false
property bool pinned: false
property bool sidebarEnabled: false
    property bool bubblesEnabled: true
    property real capsuleOpacity: 0.20
property bool capsuleUseWalColor: false
    property var capsuleWalColors: []
    property int capsuleWalColorIndex: 0
property bool lyricsExpandedView: false
    property bool idleMode: false
readonly property color capsuleWalColor: (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex]
        : "#000000"
    property bool appearanceSettingsLoaded: false
    property bool   dockEnabled: true
    property string dockMode:    "pin"   // "pin" | "smart"

onCapsuleOpacityChanged:       if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onCapsuleUseWalColorChanged:   if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onCapsuleWalColorIndexChanged: if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onLyricsExpandedViewChanged:   if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onBubblesEnabledChanged:       if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onDockEnabledChanged:          if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onDockModeChanged:             if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    onIdleModeChanged:             if (appearanceSettingsLoaded && !_pollReading) appearanceSettingsSaveTimer.restart()
    HyprlandDispatch {
        id: hyprDispatch
    }

IpcHandler {
        target: "tide"

        function toggleSearch(): void {
            if (islandContainer.islandState === "search")
                islandContainer.smartRestoreState()
            else
                islandContainer.showSearch()
        }

        function toggleControlCenter(): void {
            if (islandContainer.islandState === "control_center")
                islandContainer.smartRestoreState()
            else
                islandContainer.showControlCenter()
        }

        function togglePowerMenu(): void {
            if (islandContainer.islandState === "power_menu")
                islandContainer.smartRestoreState()
            else
                islandContainer.showPowerMenu()
        }

        function toggleNotificationCenter(): void {
            if (islandContainer.islandState === "notification_center")
                islandContainer.smartRestoreState()
            else
                islandContainer.showNotificationCenter()
        }
    }

    color: StyleTokens.transparent
    anchors { top: true; left: true; right: true }
    mask: Region {
        Region {
            x: 0
            y: 0
            width: root.width
            height: Math.ceil(root.topGestureInputHeight)
        }

Region {
            intersection: Intersection.Combine
            x: Math.floor(mainCapsule.x)
            y: Math.floor(mainCapsule.y)
            width: (root.idleMode || root.sidebarEnabled) ? 0 : Math.ceil(mainCapsule.width)
            height: (root.idleMode || root.sidebarEnabled) ? 0 : Math.ceil(mainCapsule.height)
        }

Region {
            intersection: Intersection.Combine
            x: Math.floor(workspaceBubble.x)
            y: Math.floor(workspaceBubble.y)
            width: root.bubblesEnabled ? Math.ceil(workspaceBubble.width) : 0
            height: root.bubblesEnabled ? Math.ceil(workspaceBubble.height) : 0
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(systrayBubble.x)
            y: Math.floor(systrayBubble.y)
            width: root.bubblesEnabled ? Math.ceil(systrayBubble.width) : 0
            height: root.bubblesEnabled ? Math.ceil(systrayBubble.height) : 0
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(wifiConnectivityDetailShell.x)
            y: Math.floor(wifiConnectivityDetailShell.y)
            width: wifiConnectivityDetailShell.visible ? Math.ceil(wifiConnectivityDetailShell.width) : 0
            height: wifiConnectivityDetailShell.visible ? Math.ceil(wifiConnectivityDetailShell.height) : 0
        }

Region {
            intersection: Intersection.Combine
            x: Math.floor(bluetoothConnectivityDetailShell.x)
            y: Math.floor(bluetoothConnectivityDetailShell.y)
            width: bluetoothConnectivityDetailShell.visible ? Math.ceil(bluetoothConnectivityDetailShell.width) : 0
            height: bluetoothConnectivityDetailShell.visible ? Math.ceil(bluetoothConnectivityDetailShell.height) : 0
        }

Region {
            intersection: Intersection.Combine
            x: Math.floor(screenshotDetailShell.x)
            y: Math.floor(screenshotDetailShell.y)
            width: screenshotDetailShell.visible ? Math.ceil(screenshotDetailShell.width) : 0
            height: screenshotDetailShell.visible ? Math.ceil(screenshotDetailShell.height) : 0
        }
    }
implicitHeight: Math.max(
        root.overviewVisible ? Math.ceil(4 + root.overviewCapsuleHeight + 8) : 0,
        Math.ceil(4 + root.connectivityDetailHeight + 12),
        Math.ceil(root.controlCenterWindowHeight)
    )
exclusiveZone: (root.idleMode || root.sidebarEnabled) ? 0 : (root.gamemodeActive ? 60 : 35)
    aboveWindows: true
focusable: root.overviewVisible || root.connectivityPromptActive || islandContainer.islandState === "info" || islandContainer.islandState === "search" || islandContainer.islandState === "control_center"
WlrLayershell.layer: root.idleMode ? WlrLayer.Background : (root.pinned ? WlrLayer.Overlay : WlrLayer.Top)
WlrLayershell.keyboardFocus: (root.overviewVisible || islandContainer.islandState === "search")
        ? WlrKeyboardFocus.Exclusive
        : ((root.connectivityPromptActive || islandContainer.islandState === "info" || islandContainer.islandState === "control_center")
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None)

    readonly property string iconFontFamily: userConfig.iconFontFamily
    readonly property string textFontFamily: userConfig.textFontFamily
    readonly property string heroFontFamily: userConfig.heroFontFamily
    readonly property string timeFontFamily: userConfig.timeFontFamily
    readonly property string defaultSplitIcon: "\ud83c\udfa7"
    readonly property string notificationStatusIcon: "\uf0f3"
    readonly property real overviewWindowCornerRadius: 12
   readonly property int dynamicIslandAcceptedButtons: userConfig.mouseButtonsMask([
        1,
        2,
        userConfig.dynamicIslandPrimaryButton,
        userConfig.dynamicIslandSecondaryButton
    ])
    readonly property bool topGestureInputActive: !root.overviewVisible && islandContainer.canShowSideSwipe
    readonly property real topGestureInputHeight: topGestureInputActive ? root.exclusiveZone : 0
    readonly property real overviewCapsuleWidth: islandContainer.overviewView ? islandContainer.overviewView.width : 760
    readonly property real overviewCapsuleHeight: islandContainer.overviewView ? islandContainer.overviewView.height : 308
    readonly property real overviewCapsuleRadius: islandContainer.overviewView
        ? islandContainer.overviewView.largeWorkspaceRadius + islandContainer.overviewView.outerPadding
        : 44
    readonly property color overviewCapsuleColor: islandContainer.overviewView
        ? islandContainer.overviewView.cardColor
        : StyleTokens.overviewCard
    readonly property color overviewCapsuleBorderColor: islandContainer.overviewView
        ? islandContainer.overviewView.cardBorderColor
        : StyleTokens.overviewBorder
property bool wifiConnectivityDetailOpen: false
    property bool wifiConnectivityDetailMounted: false
    property bool bluetoothConnectivityDetailOpen: false
    property bool bluetoothConnectivityDetailMounted: false
    property bool screenshotDetailOpen: false
    property bool screenshotDetailMounted: false
    readonly property bool anyConnectivityDetailMounted: wifiConnectivityDetailMounted || bluetoothConnectivityDetailMounted
    readonly property real connectivityDetailWidth: 318
    readonly property real connectivityDetailHeight: 404
    readonly property real controlCenterMaximumExtraHeight: controlCenterLoader.item
        ? controlCenterLoader.item.controlCenterMaximumExtraHeight
        : 120
readonly property real controlCenterWindowHeight: {
        if (islandContainer.capturingLayerVisible)
            return 4 + 38 + 12
        if (!islandContainer.controlCenterLayerVisible && !islandContainer.lyricsControlCenterLayerVisible)
            return 0
if (controlCenterLoader.item && controlCenterLoader.item.powerMenuOpen)
            return 4 + controlCenterLoader.item.notificationPanelTotalHeight + 12
        if (controlCenterLoader.item && controlCenterLoader.item.notificationPanelOpen)
            return 4 + controlCenterLoader.item.notificationPanelTotalHeight + 12
        if (controlCenterLoader.item && controlCenterLoader.item.appearanceMenuOpen)
            return 4 + controlCenterLoader.item.appearanceMenuTotalHeight + 12
        return 4 + 320 + root.controlCenterMaximumExtraHeight + 12
    }
    readonly property real connectivityDetailGap: 16
    readonly property int connectivityDetailAnimationDuration: IslandMotion.standard
    readonly property string overviewWallpaperSource: overviewWallpaperCache.effectiveSource

    function beginOverviewOpening() {
        if (!overviewPreparing) return;
        if (overviewLoader.status !== Loader.Ready || !overviewVisualReady) return;
        overviewPreloading = false;
        overviewPhase = "opening";
        overviewRevealTimer.restart();
    }

    function prepareOverview() {
        if (overviewPhase !== "closed") return;
        overviewUnloadGraceTimer.stop();
        overviewPreloading = true;
        overviewPreloadExpireTimer.restart();
    }

    function cancelPreparedOverview() {
        if (overviewPhase !== "closed") return;
        overviewPreloadExpireTimer.stop();
        overviewPreloading = false;
    }

    function openOverview() {
        if (overviewPhase !== "closed") return;
        overviewUnloadGraceTimer.stop();
        overviewPreloadExpireTimer.stop();
        overviewPreloading = true;
        overviewPhase = "preparing";
        if (overviewLoader.status === Loader.Ready) {
            beginOverviewOpening();
        }
    }

    function closeOverview() {
        if (!overviewMounted) return;
        if (overviewLoader.status === Loader.Ready)
            overviewUnloadGraceTimer.restart();
        overviewRevealTimer.stop();
        overviewPreloadExpireTimer.stop();
        islandContainer.restoreRestingCapsule(true);
        overviewPreloading = false;
        overviewPhase = "closed";
    }

    function closeOverviewEverywhere() {
        if (shellRootController && shellRootController.closeOverviewAll) {
            shellRootController.closeOverviewAll();
            return;
        }

        closeOverview();
    }

function setConnectivityDetailVisible(kind, open) {
        console.log("setConnectivityDetailVisible:", kind, open)
        const nextOpen = !!open;

        if (kind === "wifi") {
            if (nextOpen) {
                wifiConnectivityDetailCleanupTimer.stop();
                wifiConnectivityDetailMounted = true;
                wifiConnectivityDetailOpen = true;
            } else {
                if (!wifiConnectivityDetailMounted && !wifiConnectivityDetailOpen)
                    return;
                wifiConnectivityDetailOpen = false;
                wifiConnectivityDetailCleanupTimer.restart();
            }
            return;
        }

        if (kind === "bluetooth") {
            if (nextOpen) {
                bluetoothConnectivityDetailCleanupTimer.stop();
                bluetoothConnectivityDetailMounted = true;
                bluetoothConnectivityDetailOpen = true;
            } else {
                if (!bluetoothConnectivityDetailMounted && !bluetoothConnectivityDetailOpen)
                    return;
                bluetoothConnectivityDetailOpen = false;
                bluetoothConnectivityDetailCleanupTimer.restart();
            }
        }
    }

    function closeAllConnectivityDetails() {
        setConnectivityDetailVisible("wifi", false);
        setConnectivityDetailVisible("bluetooth", false);
    }

    function openOverviewEverywhere() {
        if (shellRootController && shellRootController.openOverviewAll) {
            shellRootController.openOverviewAll();
            return;
        }

        openOverview();
    }

    function prepareOverviewEverywhere() {
        if (shellRootController && shellRootController.prepareOverviewAll) {
            shellRootController.prepareOverviewAll();
            return;
        }

        prepareOverview();
    }

    function cancelPreparedOverviewEverywhere() {
        if (shellRootController && shellRootController.cancelPreparedOverviewAll) {
            shellRootController.cancelPreparedOverviewAll();
            return;
        }

        cancelPreparedOverview();
    }

    function toggleOverviewEverywhere() {
        if (shellRootController && shellRootController.toggleOverviewAll) {
            shellRootController.toggleOverviewAll();
            return;
        }

        if (overviewMounted)
            closeOverviewEverywhere();
        else
            openOverviewEverywhere();
    }

    function prewarmWallpaperCache() {
        overviewWallpaperCache.prewarm();
    }

function showNotification(appName, summary, body) {
        islandContainer.addNotificationToHistory(appName, summary, body);
        if (!islandContainer.dndActive)
            islandContainer.showNotificationCapsule(appName, summary, body);
    }

    onOverviewVisibleChanged: {
        if (overviewVisible && monitorFocused) overviewFocusTimer.restart();
    }
    onConnectivityPromptActiveChanged: {
        if (connectivityPromptActive && monitorFocused)
            connectivityPromptFocusTimer.restart();
    }
    onOverviewVisualReadyChanged: {
        if (overviewVisualReady) beginOverviewOpening();
    }
  onMonitorFocusedChanged: {
        if (overviewVisible && monitorFocused) overviewFocusTimer.restart();
        if (connectivityPromptActive && monitorFocused) connectivityPromptFocusTimer.restart();
    }

Connections {
        target: islandContainer
        function onIslandStateChanged() {
            if (islandContainer.islandState === "info") infoLayerFocusTimer.restart()
            if (islandContainer.islandState === "search") searchFocusTimer.restart()
            if (islandContainer.islandState === "control_center") controlCenterFocusTimer.restart()
        }
    }

    Timer {
        id: overviewFocusTimer
        interval: 0
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

 Timer {
        id: connectivityPromptFocusTimer
        interval: 0
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

Timer {
        id: infoLayerFocusTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (infoLoader.item) infoLoader.item.forceActiveFocus()
        }
    }

Timer {
        id: searchFocusTimer
        interval: 150
        repeat: false
        onTriggered: {
            searchKeyboardNudge.restart()
            if (searchLoader.item) {
                searchLoader.item.forceActiveFocus()
                searchLoader.item.focusInput()
            }
        }
    }

    Timer {
        id: searchKeyboardNudge
        interval: 32
        repeat: false
        onTriggered: {
            root.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None
            root.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive
        }
    }

Timer {
        id: searchFocusHoldTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (islandContainer.islandState === "search" && searchLoader.item)
                searchLoader.item.focusInput()
        }
    }

    Timer {
        id: controlCenterFocusTimer
        interval: 50
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

    Timer {
        id: overviewRevealTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.overviewPhase === "opening") root.overviewPhase = "open";
        }
    }

    Timer {
        id: overviewPreloadExpireTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.overviewPhase === "closed")
                root.overviewPreloading = false;
        }
    }

    Timer {
        id: overviewUnloadGraceTimer
        interval: 260
        repeat: false
    }

    Timer {
        id: wifiConnectivityDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.wifiConnectivityDetailMounted = false
    }

Timer {
        id: bluetoothConnectivityDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.bluetoothConnectivityDetailMounted = false
    }

    Timer {
        id: screenshotDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.screenshotDetailMounted = false
    }

    OverviewWallpaperCacheController {
        id: overviewWallpaperCache

        active: root.overviewLoaderActive
        wallpaperPath: userConfig.wallpaperPath
        hyprMonitor: root.hyprMonitor
        screenObject: root.screen
    }

IslandClock {
        id: timeObj
    }

Process {
        id: walColorQuery
        property string _buf: ""
        command: ["bash", "-c", "cat \"$HOME/.cache/wal/colors\" 2>/dev/null"]
        stdout: SplitParser { onRead: walColorQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const lines = walColorQuery._buf.trim().split("\n")
                walColorQuery._buf = ""
                const parsed = []
                for (let i = 0; i < lines.length; i++) {
                    const raw = lines[i].trim()
                    if (/^#?[0-9A-Fa-f]{6}$/.test(raw))
                        parsed.push(raw.startsWith("#") ? raw : ("#" + raw))
                }
                if (parsed.length > 0) {
                    root.capsuleWalColors = parsed
                    if (root.capsuleWalColorIndex >= parsed.length)
                        root.capsuleWalColorIndex = 0
                }
            }
        }
    }

Timer {
        id: walColorPollTimer
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!walColorQuery.running) walColorQuery.running = true
        }
    }

    function toggleGamemode() {
        root.gamemodeActive = !root.gamemodeActive
        gamemodeToggleExec.running = true
    }

    Process {
        id: gamemodeToggleExec
        command: ["bash", "-c", "~/.config/hypr/scripts/gamemode.sh"]
    }

    Process {
        id: gamemodePollQuery
        property string _buf: ""
        command: ["bash", "-c",
            "[ -f \"$HOME/.config/ml4w/settings/gamemode-enabled\" ] && echo 1 || echo 0"]
        stdout: SplitParser { onRead: gamemodePollQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                root.gamemodeActive = gamemodePollQuery._buf.trim() === "1"
                gamemodePollQuery._buf = ""
            }
        }
    }

Timer {
        id: gamemodePollTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!gamemodePollQuery.running) gamemodePollQuery.running = true
        }
    }

    // When this is true, property changes triggered by a JSON read must NOT
    // re-trigger the save timer — otherwise DynamicIslandWindow would
    // immediately overwrite whatever SidebarWindow just wrote.
    property bool _pollReading: false

    Process {
        id: appearanceSettingsLoader
        property string _buf: ""
        command: ["bash", "-c",
            "cat \"$HOME/.cache/quickshell/appearance-settings.json\" 2>/dev/null"]
        stdout: SplitParser { onRead: appearanceSettingsLoader._buf += data }
        onRunningChanged: {
            if (!running) {
                const raw = appearanceSettingsLoader._buf.trim()
                appearanceSettingsLoader._buf = ""
                if (raw.length > 0) {
                    try {
                        const parsed = JSON.parse(raw)
                        // On first load only, restore our own appearance settings
                        if (!root.appearanceSettingsLoaded) {
                            root._pollReading = true
                            if (typeof parsed.mainBar_capsuleOpacity === "number")
                                root.capsuleOpacity = parsed.mainBar_capsuleOpacity
                            if (typeof parsed.mainBar_capsuleUseWalColor === "boolean")
                                root.capsuleUseWalColor = parsed.mainBar_capsuleUseWalColor
                            if (typeof parsed.mainBar_capsuleWalColorIndex === "number")
                                root.capsuleWalColorIndex = parsed.mainBar_capsuleWalColorIndex
                            if (typeof parsed.lyricsExpandedView === "boolean")
                                root.lyricsExpandedView = parsed.lyricsExpandedView
                            if (typeof parsed.bubblesEnabled === "boolean")
                                root.bubblesEnabled = parsed.bubblesEnabled
                            if (typeof parsed.dockEnabled === "boolean")
                                root.dockEnabled = parsed.dockEnabled
                            if (typeof parsed.dockMode === "string")
                                root.dockMode = parsed.dockMode
                            if (typeof parsed.idleMode === "boolean")
                                root.idleMode = parsed.idleMode
                            root._pollReading = false
                        }
                        // Always sync sidebarEnabled so toggling from sidebar is reflected here
                        if (typeof parsed.sidebarEnabled === "boolean")
                            root.sidebarEnabled = parsed.sidebarEnabled
                    } catch (e) {
                        root._pollReading = false
                        console.log("appearance-settings.json parse error:", e)
                    }
                }
                root.appearanceSettingsLoaded = true
            }
        }
    }

    // Poll only for sidebarEnabled changes — appearance keys are owned by this window
    Timer {
        id: sidebarSyncTimer
        interval: 500; repeat: true; running: true; triggeredOnStart: false
        onTriggered: {
            if (!appearanceSettingsLoader.running)
                appearanceSettingsLoader.running = true
        }
    }

    Timer {
        id: appearanceSettingsSaveTimer
        interval: 400
        repeat: false
        onTriggered: root.saveAppearanceSettingsNow()
    }

    function saveAppearanceSettingsNow() {
        appearanceSettingsSaveExec.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "F=\"$HOME/.cache/quickshell/appearance-settings.json\"; " +
            "existing=$(cat \"$F\" 2>/dev/null || echo '{}'); " +
            "echo \"$existing\" | python3 -c \"" +
            "import json,sys; d=json.load(sys.stdin); d.update(json.loads(sys.argv[1])); print(json.dumps(d))\" '" +
            JSON.stringify({
                mainBar_capsuleOpacity:       root.capsuleOpacity,
                mainBar_capsuleUseWalColor:   root.capsuleUseWalColor,
                mainBar_capsuleWalColorIndex: root.capsuleWalColorIndex,
                lyricsExpandedView:           root.lyricsExpandedView,
                sidebarEnabled:               root.sidebarEnabled,
                bubblesEnabled:               root.bubblesEnabled,
                idleMode:                     root.idleMode,
                gamemodeActive:               root.gamemodeActive,
                dockEnabled:                  root.dockEnabled,
                dockMode:                     root.dockMode
            }) + "' > \"$F\""]
        appearanceSettingsSaveExec.running = true
    }

    Process { id: appearanceSettingsSaveExec }

    Component.onCompleted: appearanceSettingsLoader.running = true

    FocusScope {
        id: islandContainer
        anchors.fill: parent
focus: root.monitorFocused && (root.overviewVisible || root.connectivityPromptActive || islandContainer.islandState === "search" || islandContainer.islandState === "info" || islandContainer.islandState === "control_center")
        activeFocusOnTab: false

        property string islandState: "normal"
        property string splitIcon: root.defaultSplitIcon
        property real osdProgress: -1.0
        property bool osdProgressAnimationEnabled: true
        property string osdCustomText: ""
        property int currentWs: root.currentMonitorWorkspaceId > 0 ? root.currentMonitorWorkspaceId : 1
        readonly property int batteryCapacity: systemState.batteryCapacity
        readonly property bool isCharging: systemState.isCharging
        readonly property real currentVolume: systemState.currentVolume
        readonly property bool isMuted: systemState.isMuted
        readonly property real currentBrightness: systemState.currentBrightness
        readonly property real currentCpuUsage: systemState.currentCpuUsage
        readonly property real currentRamUsage: systemState.currentRamUsage
property string notificationAppName: ""
        property string notificationSummary: ""
        property string notificationBody: ""
        property var bluetoothExpandedDevice: null
property var notificationHistory: []
        property int notificationHistoryCounter: 0
property int unseenNotificationCount: 0
        property bool notificationPulseToggle: false
property bool dndActive: false
property int mediaWorkspaceId: -1
property string mediaPlayerName: ""

        Process {
            id: mediaWorkspaceQuery
            property string _buf: ""
            command: ["bash", "-c", "hyprctl clients -j 2>/dev/null"]
            stdout: SplitParser { onRead: mediaWorkspaceQuery._buf += data + "\n" }
            onRunningChanged: {
                if (!running) {
                    const raw = mediaWorkspaceQuery._buf
                    mediaWorkspaceQuery._buf = ""
                    islandContainer.resolveMediaWorkspace(raw)
                }
            }
        }

        Timer {
            id: mediaWorkspacePollTimer
            interval: 2000
            running: islandContainer.activePlayer !== null
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                if (!mediaWorkspaceQuery.running) mediaWorkspaceQuery.running = true
            }
        }

        function resolveMediaWorkspace(rawJson) {
            const player = islandContainer.activePlayer
            if (!player) { mediaWorkspaceId = -1; mediaPlayerName = ""; return }
            const needle = String(player.identity || "").toLowerCase().trim()
            if (needle === "") { mediaWorkspaceId = -1; mediaPlayerName = ""; return }
            try {
                const clients = JSON.parse(rawJson)
                for (let i = 0; i < clients.length; i++) {
                    const c = clients[i]
                    const cls = String(c.class || "").toLowerCase()
                    const title = String(c.title || "").toLowerCase()
                    // ytm runs inside kitty — match by title containing "ytm"
                    const isYtm = title.indexOf("ytm") >= 0
                    const isSpotify = cls.indexOf("spotify") >= 0
                    if (isYtm || isSpotify || cls.indexOf(needle) >= 0 || needle.indexOf(cls) >= 0
                            || title.indexOf(needle) >= 0) {
                        mediaWorkspaceId = (c.workspace && c.workspace.id !== undefined)
                            ? c.workspace.id : -1
                        if (isSpotify) mediaPlayerName = "Spotify"
                        else if (isYtm) mediaPlayerName = "YouTube Music"
                        else mediaPlayerName = player.identity || ""
                        return
                    }
                }
            } catch (e) {
            }
            mediaWorkspaceId = -1
            mediaPlayerName = ""
        }
        readonly property bool dndBubbleEligibleState: islandState === "normal"
            || islandState === "custom"
            || islandState === "lyrics"
readonly property bool dndBubbleVisible: dndActive && dndBubbleEligibleState && !root.overviewVisible
        readonly property var cavaLevels: systemState.cavaLevels
        property real swipeTransitionProgress: 0
        property string workspaceOriginSide: "none"
        property string splitOriginSide: "none"
        property string restingState: "normal"
property bool expandedByPlayerAutoOpen: false
        property string capturingText: "Capturing…"
        property real customCapsuleWidth: 220
        property real lyricsCapsuleWidth: 220
        property bool sideSwipeSettling: false
        readonly property int defaultAutoHideInterval: 1250
        readonly property int notificationAutoHideInterval: 4200
        readonly property int bluetoothExpandedAutoHideInterval: 2500
        readonly property int swipeAnimationDuration: IslandMotion.fast
       readonly property bool blocksTransientSplit: islandState === "expanded"
            || islandState === "bluetooth_expanded"
            || islandState === "control_center"
            || islandState === "lyrics_control_center"
            || islandState === "equalizer"
            || islandState === "power_menu"
            || islandState === "notification_center"
            || islandState === "notification"
        readonly property bool splitShowsProgress: islandState === "split" && osdProgress >= 0
        readonly property bool splitShowsText: islandState === "split" && osdProgress < 0 && osdCustomText !== ""
        readonly property bool splitShowsIconOnly: islandState === "split" && osdProgress < 0 && osdCustomText === ""
        readonly property bool splitUsesExtendedLayout: splitShowsProgress || splitShowsText
        readonly property real splitCapsuleWidth: splitShowsProgress ? 248 : (splitShowsText ? 220 : 140)
        readonly property bool canShowSideSwipe: islandState === "normal"
            || islandState === "custom"
            || islandState === "lyrics"
            || (islandState === "long_capsule" && workspaceOriginSide === "none")
        readonly property real rightSwipeProgress: Math.max(0, swipeTransitionProgress)
        readonly property var customLeftItems: systemState.customLeftItems
        readonly property bool hasCustomLeftItems: systemState.hasCustomLeftItems
        readonly property bool customSwipeVisible: !root.overviewVisible
            && hasCustomLeftItems
            && (
                capsuleMouseArea.sideSwipeInteractive
                ? swipeTransitionProgress < 0
                : (
                    islandState === "custom"
                    || (islandState === "normal" && swipeTransitionProgress < 0)
                    || (islandState === "split" && splitOriginSide === "left")
                    || (islandState === "long_capsule"
                        && workspaceOriginSide === "left")
                )
            )
        readonly property bool lyricsSwipeVisible: !root.overviewVisible && (
            capsuleMouseArea.sideSwipeInteractive
            ? swipeTransitionProgress >= 0
            : (
                islandState === "lyrics"
                || (islandState === "normal" && swipeTransitionProgress >= 0)
                || (islandState === "split" && splitOriginSide === "right")
                || (islandState === "long_capsule"
                    && workspaceOriginSide === "right")
            )
        )
        readonly property bool expandedLayerVisible: !root.overviewVisible && islandState === "expanded"
        readonly property bool bluetoothExpandedLayerVisible: !root.overviewVisible && islandState === "bluetooth_expanded"
                readonly property bool notificationLayerVisible: !root.overviewVisible && islandState === "notification"
readonly property bool controlCenterLayerVisible: !root.overviewVisible && islandState === "control_center"
readonly property bool powerMenuLayerVisible: !root.overviewVisible && islandState === "power_menu"
readonly property bool notificationCenterLayerVisible: !root.overviewVisible && islandState === "notification_center"
readonly property bool capturingLayerVisible: !root.overviewVisible && islandState === "capturing"
        readonly property bool searchLayerVisible: !root.overviewVisible && islandState === "search"
        readonly property bool lyricsControlCenterLayerVisible: !root.overviewVisible && islandState === "lyrics_control_center"
        readonly property bool equalizerLayerVisible: !root.overviewVisible && islandState === "equalizer"
        readonly property var activePlayer: mediaController.activePlayer
        readonly property string lyricsDisplayText: mediaController.displayText
        readonly property string currentTrack: mediaController.currentTrack
        readonly property string currentArtist: mediaController.currentArtist
        readonly property string currentArtUrl: mediaController.currentArtUrl
        readonly property bool mediaHasNoLyrics: mediaController.hasNoLyrics
        readonly property real trackProgress: mediaController.trackProgress
        readonly property string timePlayed: mediaController.timePlayed
        readonly property string timeTotal: mediaController.timeTotal
        readonly property bool screenRecordingActive: root.screenRecordingActive
        readonly property var bluetoothDevices: bluetoothConnectionTracker.devices
        readonly property var overviewView: overviewLoader.item && overviewLoader.item.overviewView
            ? overviewLoader.item.overviewView
            : null

        onControlCenterLayerVisibleChanged: {
            if (!controlCenterLayerVisible) {
                if (controlCenterLoader.item)
                    controlCenterLoader.item.closeConnectivityPanels();
                else
                    root.closeAllConnectivityDetails();
            }
        }

        onLyricsControlCenterLayerVisibleChanged: {
            if (!lyricsControlCenterLayerVisible && lyricsControlCenterLoader.item) {
                lyricsControlCenterLoader.item.lrclibPanelOpen    = false
                lyricsControlCenterLoader.item.localFilePanelOpen = false
            }
        }

        onCustomLeftItemsChanged: {
            if (restingState === "custom" && !hasCustomLeftItems) {
                restingState = "normal";

                if (islandState === "custom"
                        || (islandState === "split" && splitOriginSide === "left")
                        || (islandState === "long_capsule" && workspaceOriginSide === "left")) {
                    restoreRestingCapsule(true);
                } else {
                    applyRestingVisuals();
                }
            } else if (restingState === "custom") {
                syncCustomCapsuleWidth();
            }
        }

        property LyricManager lyricManagerInstance: LyricManager {}

        IslandMprisController {
            id: mediaController

          expanded: islandContainer.islandState === "expanded"
        }

        BluetoothConnectionTracker {
            id: bluetoothConnectionTracker

            onAdapterChanged: islandContainer.bluetoothExpandedDevice = null

            onNewConnection: function(device) {
                islandContainer.showBluetoothExpanded(device);
            }
        }

        IslandSystemState {
            id: systemState

            configuredLeftSwipeItems: userConfig.dynamicIslandLeftSwipeItems
            timeText: timeObj.currentTime
            dateText: timeObj.currentDateLabel
            currentWorkspace: islandContainer.currentWs
            customSwipeActive: customSwipeLoader.active
            expandedPlayerActive: islandContainer.expandedLayerVisible
            lyricsSwipeActive: islandContainer.lyricsSwipeVisible

            onTransientRequested: function(icon, progress, text) {
                islandContainer.showTransientCapsule(icon, progress, text);
            }
        }

        HyprlandWorkspaceTracker {
            id: workspaceTracker

            hyprMonitor: root.hyprMonitor
            monitorName: root.hyprMonitorName
            monitorFocused: root.monitorFocused

            onWorkspaceSynced: function(workspaceId) {
                islandContainer.currentWs = workspaceId;
            }

            onWorkspaceActivated: function(workspaceId) {
                islandContainer.showWorkspaceCapsule(workspaceId);
            }
        }

        Behavior on osdProgress {
            enabled: islandContainer.osdProgressAnimationEnabled

            SmoothedAnimation { velocity: 1.5; duration: 160; easing.type: IslandMotion.easeOrganic }
        }
        Behavior on swipeTransitionProgress {
            NumberAnimation {
                duration: capsuleMouseArea.sideSwipeInteractive ? 0 : islandContainer.swipeAnimationDuration
                easing.type: IslandMotion.easeArrive
            }
        }

Keys.onPressed: (event) => {
            if (islandContainer.islandState === "control_center" && event.key === Qt.Key_Escape) {
                islandContainer.smartRestoreState();
                event.accepted = true;
                return;
            }
            if (!root.overviewVisible) return;

            if ((event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab) {
                hyprDispatch.focusWorkspace("r-1");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Tab) {
                hyprDispatch.focusWorkspace("r+1");
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return) {
                root.closeOverviewEverywhere();
                event.accepted = true;
                return;
            }

            const ov = islandContainer.overviewView;
            const rows    = ov ? ov.rows    : 2;
            const columns = ov ? ov.columns : 5;
            const wpg     = rows * columns;
            const curId   = hyprMonitor && hyprMonitor.activeWorkspace
                ? hyprMonitor.activeWorkspace.id : 1;
            const group  = Math.floor((curId - 1) / wpg);
            const minId  = group * wpg + 1;
            const maxId  = minId + wpg - 1;

            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                let t = curId - 1; if (t < minId) t = maxId;
                hyprDispatch.focusWorkspace(t);
                event.accepted = true; return;
            }
            if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                let t = curId + 1; if (t > maxId) t = minId;
                hyprDispatch.focusWorkspace(t);
                event.accepted = true; return;
            }
            if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                let t = curId - columns; if (t < minId) t += wpg;
                hyprDispatch.focusWorkspace(t);
                event.accepted = true; return;
            }
            if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                let t = curId + columns; if (t > maxId) t -= wpg;
                hyprDispatch.focusWorkspace(t);
                event.accepted = true; return;
            }

            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const pos = event.key - Qt.Key_0;
                if (pos <= wpg) { hyprDispatch.focusWorkspace(minId + pos - 1); event.accepted = true; }
                return;
            }
            if (event.key === Qt.Key_0 && wpg >= 10) {
                hyprDispatch.focusWorkspace(minId + 9);
                event.accepted = true; return;
            }
        }

        function handleConfiguredClickAction(actionName) {
            if ((actionName === "toggleControlCenter" || actionName === "openControlCenter")
                    && (islandState === "lyrics" || restingState === "lyrics")) {
                if (islandState === "lyrics_control_center")
                    smartRestoreState()
                else
                    showLyricsControlCenter()
                return
            }

            if ((actionName === "toggleControlCenter" || actionName === "openControlCenter")
                    && (islandState === "expanded" || islandState === "equalizer")) {
                if (islandState === "equalizer")
                    showExpandedPlayer(false)
                else
                    showEqualizer()
                return
            }

            switch (actionName) {
            case "":
            case "none":
                return;
            case "toggleExpandedPlayer":
                if (islandState === "expanded") {
                    autoHideTimer.stop();
                    smartRestoreState();
                } else {
                    showExpandedPlayer(false);
                }
                return;
            case "openExpandedPlayer":
                showExpandedPlayer(false);
                return;
            case "closeExpandedPlayer":
                if (islandState === "expanded")
                    smartRestoreState();
                return;
            case "toggleControlCenter":
                if (islandState === "control_center")
                    smartRestoreState();
                else
                    showControlCenter();
                return;
            case "toggleInfoPanel":
                if (islandState === "info")
                    smartRestoreState();
                else
                    showInfoPanel();
                return;
            case "openControlCenter":
                showControlCenter();
                return;
            case "closeControlCenter":
                if (islandState === "control_center")
                    smartRestoreState();
                return;
            case "toggleOverview":
                root.toggleOverviewEverywhere();
                return;
            case "openOverview":
                root.openOverviewEverywhere();
                return;
            case "closeOverview":
                root.closeOverviewEverywhere();
                return;
            case "toggleLyrics":
                if (restingState === "lyrics")
                    showTimeCapsule();
                else
                    showLyricsCapsule();
                return;
            case "showLyrics":
                showLyricsCapsule();
                return;
            case "showTime":
                showTimeCapsule();
                return;
            case "restoreRestingCapsule":
                smartRestoreState();
                return;
            default:
            }
        }

        function clamp01(value) {
            return Math.max(0, Math.min(1, value));
        }

        function normalizeRestingState(nextState) {
            if (nextState === "lyrics") return "lyrics";
            if (nextState === "custom" && hasCustomLeftItems) return "custom";
            return "normal";
        }

        function restingStateProgress(nextState) {
            switch (normalizeRestingState(nextState)) {
            case "custom":
                return -1;
            case "lyrics":
                return 1;
            default:
                return 0;
            }
        }

        function restingStateSide(nextState) {
            switch (normalizeRestingState(nextState)) {
            case "custom":
                return "left";
            case "lyrics":
                return "right";
            default:
                return "none";
            }
        }

        function swipeRestProgressForState() {
            switch (islandState) {
            case "custom":
                return -1;
            case "lyrics":
                return 1;
            default:
                return 0;
            }
        }

        function currentTransientOriginSide() {
            switch (islandState) {
            case "custom":
                return "left";
            case "lyrics":
                return "right";
            case "long_capsule":
                return workspaceOriginSide;
            case "split":
                return splitOriginSide;
            default:
                return "none";
            }
        }

        function setOsdProgress(nextProgress, animate) {
            osdProgressAnimationReset.stop();
            osdProgressAnimationEnabled = animate;
            osdProgress = nextProgress;
            if (!animate) osdProgressAnimationReset.restart();
        }

        function abortSideTransientMode() {
            sideTransientRestoreTimer.stop();
            workspaceOriginSide = "none";
            splitOriginSide = "none";
        }

        function clearTransientCapsule() {
            setOsdProgress(-1.0, false);
            osdCustomText = "";
            notificationAppName = "";
            notificationSummary = "";
            notificationBody = "";
            bluetoothExpandedDevice = null;
        }

        function cleanNotificationText(text) {
            return String(text === undefined || text === null ? "" : text)
                .replace(/<[^>]*>/g, " ")
                .replace(/&nbsp;/g, " ")
                .replace(/&amp;/g, "&")
                .replace(/&quot;/g, "\"")
                .replace(/&lt;/g, "<")
                .replace(/&gt;/g, ">")
                .replace(/\s+/g, " ")
                .trim();
        }

        function prepareRestingCapsuleGeometry() {
            if (restingState === "custom")
                syncCustomCapsuleWidth();
            if (restingState === "lyrics")
                syncLyricsCapsuleWidth();
        }

        function applyRestingVisuals() {
            prepareRestingCapsuleGeometry();
            swipeTransitionProgress = restingStateProgress(restingState);
        }

        function sideSwipeRestProgressForProgress(progressValue) {
            if (progressValue <= -0.5) return -1;
            if (progressValue >= 0.5) return 1;
            return 0;
        }

        function sideSwipeRestWidthForProgress(progressValue) {
            if (progressValue <= -0.5) return customCapsuleWidth;
            if (progressValue >= 0.5) return lyricsCapsuleWidth;
            return 140;
        }

        function customSideSwipeDragDistance() {
            const view = customSwipeLoader.item;
            if (view && view.dragDistance > 0) return view.dragDistance;
            return Math.max(140, customCapsuleWidth + 4);
        }

        function lyricsSideSwipeDragDistance() {
            const view = lyricsSwipeLoader.item;
            if (view && view.dragDistance > 0) return view.dragDistance;
            return Math.max(140, lyricsCapsuleWidth + 2);
        }

        function sideSwipeDragDistanceForDirection(direction) {
            if (direction === "left") return customSideSwipeDragDistance();
            if (direction === "right") return lyricsSideSwipeDragDistance();
            return 140;
        }

        function advanceSideSwipeProgress(currentProgress, deltaX) {
            const minProgress = -1;
            let nextProgress = Math.max(minProgress, Math.min(1, currentProgress));
            let remainingDelta = deltaX;

            if (remainingDelta > 0) {
                if (nextProgress < 0) {
                    const leftDistance = Math.max(1, sideSwipeDragDistanceForDirection("left"));
                    const progressToCenter = Math.min(-nextProgress, remainingDelta / leftDistance);
                    nextProgress += progressToCenter;
                    remainingDelta -= progressToCenter * leftDistance;
                }

                if (remainingDelta > 0 && nextProgress < 1) {
                    const rightDistance = Math.max(1, sideSwipeDragDistanceForDirection("right"));
                    nextProgress = Math.min(1, nextProgress + remainingDelta / rightDistance);
                }
            } else if (remainingDelta < 0) {
                if (nextProgress > 0) {
                    const rightDistance = Math.max(1, sideSwipeDragDistanceForDirection("right"));
                    const progressToCenter = Math.min(nextProgress, -remainingDelta / rightDistance);
                    nextProgress -= progressToCenter;
                    remainingDelta += progressToCenter * rightDistance;
                }

                if (remainingDelta < 0 && nextProgress > minProgress) {
                    const leftDistance = Math.max(1, sideSwipeDragDistanceForDirection("left"));
                    nextProgress = Math.max(minProgress, nextProgress + remainingDelta / leftDistance);
                }
            }

            return Math.max(minProgress, Math.min(1, nextProgress));
        }

        function resolveSideSwipeSettle(startProgress, finalProgress) {
            let settleAction = "";
            let settleProgress = sideSwipeRestProgressForProgress(startProgress);
            let settleWidth = sideSwipeRestWidthForProgress(startProgress);

            if (finalProgress >= 0.56) {
                settleAction = "lyrics";
                settleProgress = 1;
                settleWidth = lyricsCapsuleWidth;
            } else if (hasCustomLeftItems && finalProgress <= -0.56) {
                settleAction = "custom";
                settleProgress = -1;
                settleWidth = customCapsuleWidth;
            } else if (startProgress <= -0.5) {
                if (finalProgress >= -0.44) {
                    settleAction = "time";
                    settleProgress = 0;
                    settleWidth = 140;
                }
            } else if (startProgress >= 0.5) {
                if (finalProgress <= 0.44) {
                    settleAction = "time";
                    settleProgress = 0;
                    settleWidth = 140;
                }
            } else {
                settleAction = "time";
                settleProgress = 0;
                settleWidth = 140;
            }

            return {
                action: settleAction,
                progress: settleProgress,
                width: settleWidth
            };
        }

        function beginSideSwipeSettle(targetWidth) {
            sideSwipeSettling = true;
            mainCapsule.displayedWidth = targetWidth;
            sideSwipeSettleReset.restart();
        }

        function cancelSideSwipeSettle() {
            sideSwipeSettleReset.stop();
            sideSwipeSettling = false;
        }

        function finishSideSwipeSettle() {
            sideSwipeSettling = false;
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
        }

        function restartAutoHideTimer(duration) {
            autoHideTimer.interval = duration === undefined ? defaultAutoHideInterval : duration;
            autoHideTimer.restart();
        }

        function stopAutoHideTimer() {
            autoHideTimer.stop();
            autoHideTimer.interval = defaultAutoHideInterval;
        }

        function showTransientCapsule(icon, progress, customText) {
            if (progress === undefined)    progress = -1.0;
            if (customText === undefined)  customText = "";

            if (blocksTransientSplit) return;

            const nextProgress = progress >= 0 ? progress : -1.0;
            const animateProgress = islandState === "split" && osdProgress >= 0 && nextProgress >= 0;
            const animateFromSide = currentTransientOriginSide();

            abortSideTransientMode();
            splitIcon = icon;
            osdCustomText = customText;
            setOsdProgress(nextProgress, animateProgress);
            splitOriginSide = animateFromSide;
            islandState = "split";
            swipeTransitionProgress = 0;
            restartAutoHideTimer();
        }

function showNotificationCapsule(appName, summary, body) {
            if (root.overviewVisible || islandState === "control_center" || islandState === "expanded" || islandState === "notification_center") return;

            const cleanedAppName = cleanNotificationText(appName);
            const cleanedSummary = cleanNotificationText(summary);
            const cleanedBody = cleanNotificationText(body);
            const resolvedSummary = cleanedSummary !== ""
                ? cleanedSummary
                : (cleanedBody !== "" ? cleanedBody : "New notification");

            abortSideTransientMode();
            clearTransientCapsule();
            notificationAppName = cleanedAppName !== "" ? cleanedAppName : "Notification";
            notificationSummary = resolvedSummary;
            notificationBody = cleanedSummary !== "" ? cleanedBody : "";
islandState = "notification";
            restartAutoHideTimer(notificationAutoHideInterval);
        }

        function addNotificationToHistory(appName, summary, body) {
            notificationHistoryCounter++;
            const cleanedAppName = cleanNotificationText(appName);
            const cleanedSummary = cleanNotificationText(summary);
            const cleanedBody = cleanNotificationText(body);
            const resolvedSummary = cleanedSummary !== ""
                ? cleanedSummary
                : (cleanedBody !== "" ? cleanedBody : "New notification");

const entry = {
                id: notificationHistoryCounter,
                appName: cleanedAppName !== "" ? cleanedAppName : "Notification",
                summary: resolvedSummary,
                body: cleanedSummary !== "" ? cleanedBody : "",
                appIcon: "",
                timestamp: Date.now()
            };

            const updated = notificationHistory.slice();
            updated.unshift(entry);
            if (updated.length > 20)
                updated.length = 20;
            notificationHistory = updated;
            queueNotificationIconLookup(entry.id, entry.appName);

            if (islandState !== "notification_center")
                unseenNotificationCount++;
            notificationPulseToggle = !notificationPulseToggle;
        }

function clearNotificationHistory() {
            notificationHistory = [];
            unseenNotificationCount = 0;
        }

        property var _notifIconQueue: []

        function queueNotificationIconLookup(entryId, appName) {
            if (!appName || String(appName).trim() === "") return;
            _notifIconQueue.push({ id: entryId, name: String(appName).trim() });
            processNextNotificationIconLookup();
        }

        function processNextNotificationIconLookup() {
            if (notifIconLookup.running) return;
            if (_notifIconQueue.length === 0) return;
            const item = _notifIconQueue.shift();
            notifIconLookup.pendingEntryId = item.id;
            const needle = item.name.toLowerCase().replace(/'/g, "");
            notifIconLookup.command = ["bash", "-c",
                "n='" + needle + "'; " +
                "f=\"$HOME/.cache/quickshell/dock-apps-v2.tsv\"; " +
                "if [ -f \"$f\" ]; then " +
                  "r=$(awk -F'\\t' -v n=\"$n\" '{ ln=tolower($1); if (index(ln, n) > 0 && $3 != \"\") { print $3; exit } }' \"$f\"); " +
                  "[ -n \"$r\" ] && echo \"$r\" && exit 0; " +
                "fi; " +
                "icon=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons $HOME/.local/share/pixmaps 2>/dev/null " +
                  "-type f \\( -name \"${n}.png\" -o -name \"${n}.svg\" -o -name \"${n}.xpm\" \\) " +
                  "| grep -i '48x48\\|scalable\\|256x256\\|128x128' | head -1); " +
                "[ -z \"$icon\" ] && " +
                  "icon=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons $HOME/.local/share/pixmaps 2>/dev/null " +
                  "-type f \\( -name \"${n}.png\" -o -name \"${n}.svg\" \\) | head -1); " +
                "[ -n \"$icon\" ] && echo \"$icon\" && exit 0; " +
                "desktop=$(grep -ril \"^Name=.*${n}\\|^Exec=.*${n}\" /usr/share/applications $HOME/.local/share/applications 2>/dev/null | head -1); " +
                "if [ -n \"$desktop\" ]; then " +
                  "iname=$(grep -m1 '^Icon=' \"$desktop\" | cut -d= -f2); " +
                  "[ -n \"$iname\" ] && [ -f \"$iname\" ] && echo \"$iname\" && exit 0; " +
                  "r=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons 2>/dev/null " +
                    "-type f \\( -name \"${iname}.png\" -o -name \"${iname}.svg\" \\) " +
                    "| grep -i '48x48\\|scalable\\|256x256' | head -1); " +
                  "[ -z \"$r\" ] && " +
                    "r=$(find /usr/share/icons /usr/share/pixmaps $HOME/.local/share/icons 2>/dev/null " +
                    "-type f \\( -name \"${iname}.png\" -o -name \"${iname}.svg\" \\) | head -1); " +
                  "[ -n \"$r\" ] && echo \"$r\"; " +
                "fi"
            ];
            notifIconLookup.running = true;
        }

        function updateNotificationIcon(entryId, iconPath) {
            const trimmed = String(iconPath || "").trim();
            if (trimmed === "") return;
            notificationHistory = notificationHistory.map(function(e) {
                if (e.id !== entryId) return e;
                const next = Object.assign({}, e);
                next.appIcon = trimmed;
                return next;
            });
        }

        Process {
            id: notifIconLookup
            property int pendingEntryId: -1
            property string _buf: ""
            stdout: SplitParser { onRead: notifIconLookup._buf += data + "\n" }
            onRunningChanged: {
                if (!running) {
                    const line = notifIconLookup._buf.trim();
                    notifIconLookup._buf = "";
                    if (line !== "" && notifIconLookup.pendingEntryId >= 0)
                        islandContainer.updateNotificationIcon(notifIconLookup.pendingEntryId, line);
                    notifIconLookup.pendingEntryId = -1;
                    islandContainer.processNextNotificationIconLookup();
                }
            }
        }

function toggleDnd() {
            dndActive = !dndActive
            dndToggleExec.running = true
        }

        Process {
            id: dndToggleExec
            command: ["bash", "-c", "swaync-client -d >/dev/null 2>&1"]
            onRunningChanged: {
                if (!running) dndPollTimer.triggered()
            }
        }

        Process {
            id: dndQuery
            property string _buf: ""
            command: ["bash", "-c", "swaync-client -D 2>/dev/null"]
            stdout: SplitParser { onRead: dndQuery._buf += data }
            onRunningChanged: {
                if (!running) {
                    islandContainer.dndActive = dndQuery._buf.trim() === "true"
                    dndQuery._buf = ""
                }
            }
        }

        Timer {
            id: dndPollTimer
            interval: 3000
            running: !root.sidebarEnabled
            repeat: true
            triggeredOnStart: true
            onTriggered: dndQuery.running = true
        }

        function openNotificationHistory() {
            showNotificationCenter();
        }

        function dismissNotificationFromHistory(entryId) {
            notificationHistory = notificationHistory.filter(function(e) {
                return e.id !== entryId;
            });
            if (unseenNotificationCount > 0)
                unseenNotificationCount--;
        }

        function suppressCapsuleClick() {
            capsuleMouseArea.suppressNextClick = true;
            swipeSuppressReset.restart();
        }

        function restoreRestingCapsule(forceImmediate) {
            if (forceImmediate === undefined) forceImmediate = false;
            const normalizedRestingState = normalizeRestingState(restingState);
            const targetSide = restingStateSide(normalizedRestingState);
            const shouldAnimateToSide = targetSide !== "none"
                && ((islandState === "long_capsule" && workspaceOriginSide === targetSide)
                    || (islandState === "split" && splitOriginSide === targetSide));

            if (!forceImmediate && shouldAnimateToSide) {
                expandedByPlayerAutoOpen = false;
                prepareRestingCapsuleGeometry();
                swipeTransitionProgress = restingStateProgress(normalizedRestingState);
                stopAutoHideTimer();
                sideTransientRestoreTimer.restart();
                return;
            }

            abortSideTransientMode();
            prepareRestingCapsuleGeometry();
            islandState = normalizedRestingState;
            clearTransientCapsule();
            applyRestingVisuals();
            expandedByPlayerAutoOpen = false;
            stopAutoHideTimer();
        }

        function setRestingState(nextState) {
            restingState = normalizeRestingState(nextState);
        }

        function smartRestoreState() {
            if (islandState === "notification_center")
                unseenNotificationCount = 0;
            restoreRestingCapsule();
        }

        function showRestingCapsule(nextState) {
            setRestingState(nextState);
            restoreRestingCapsule();
            stopAutoHideTimer();
        }

        function showExpandedPlayer(autoOpened) {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "expanded";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            expandedByPlayerAutoOpen = autoOpened;
            if (autoOpened) restartAutoHideTimer();
            else stopAutoHideTimer();
        }

        function showBluetoothExpanded(device) {
            if (!device || root.overviewVisible || islandState === "control_center" || islandState === "notification")
                return;

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            bluetoothExpandedDevice = device;
            islandState = "bluetooth_expanded";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            expandedByPlayerAutoOpen = false;
            restartAutoHideTimer(bluetoothExpandedAutoHideInterval);
        }

        function showControlCenter() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "control_center";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showPowerMenu() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "power_menu";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showNotificationCenter() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "notification_center";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
            unseenNotificationCount = 0;
        }

function showSearch() {
            cancelSideSwipeSettle()
            abortSideTransientMode()
            clearTransientCapsule()
            islandState = "search"
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth
            stopAutoHideTimer()
        }

        function showCapturing(text) {
            cancelSideSwipeSettle()
            abortSideTransientMode()
            clearTransientCapsule()
            capturingText = text || "Capturing…"
            islandState = "capturing"
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth
            stopAutoHideTimer()
        }

        function finishCapturing() {
            capturingText = "Saved!"
            savedTextTimer.restart()
        }

        Timer {
            id: savedTextTimer
            interval: 900
            repeat: false
            onTriggered: islandContainer.smartRestoreState()
        }

        function showInfoPanel() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "info";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showLyricsControlCenter() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "lyrics_control_center";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showEqualizer() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "equalizer";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function hideEqualizer() {
            if (islandState === "equalizer")
                showExpandedPlayer(false);
        }

        function showCustomCapsule() {
            if (!hasCustomLeftItems) {
                showTimeCapsule();
                return;
            }

            systemState.refreshMissingValues();
            showRestingCapsule("custom");
        }

        function showLyricsCapsule() {
            showRestingCapsule("lyrics");
        }

        function showTimeCapsule() {
            showRestingCapsule("normal");
        }

        function showWorkspaceCapsule(wsId) {
            currentWs = wsId;
            if (islandState === "control_center" || islandState === "notification") return;
            const animateFromSide = currentTransientOriginSide();
            clearTransientCapsule();
            sideTransientRestoreTimer.stop();
            workspaceOriginSide = animateFromSide;
            splitOriginSide = "none";
            islandState = "long_capsule";
            swipeTransitionProgress = 0;
            restartAutoHideTimer();
        }

Timer { id: autoHideTimer; interval: islandContainer.defaultAutoHideInterval; onTriggered: islandContainer.smartRestoreState() }
        Timer {
            id: osdProgressAnimationReset
            interval: 0
            onTriggered: islandContainer.osdProgressAnimationEnabled = true
        }
        Timer {
            id: sideTransientRestoreTimer
            interval: islandContainer.swipeAnimationDuration
            onTriggered: {
                islandContainer.workspaceOriginSide = "none";
                islandContainer.splitOriginSide = "none";
                islandContainer.prepareRestingCapsuleGeometry();
                islandContainer.islandState = islandContainer.normalizeRestingState(islandContainer.restingState);
                islandContainer.clearTransientCapsule();
                islandContainer.applyRestingVisuals();
                islandContainer.expandedByPlayerAutoOpen = false;
            }
        }
        Timer {
            id: sideSwipeSettleReset
            interval: mainCapsule.morphDuration
            onTriggered: islandContainer.finishSideSwipeSettle()
        }

        function syncCustomCapsuleWidth() {
            const view = customSwipeLoader.item;
            if (!view) return;
            customCapsuleWidth = Math.max(220, Math.min(root.width - 48, view.preferredWidth));
        }

        function syncLyricsCapsuleWidth() {
            const view = lyricsSwipeLoader.item;
            if (!view) return;
            lyricsCapsuleWidth = Math.max(220, Math.min(root.width - 48, view.preferredWidth));
        }

        onCurrentTrackChanged: {
            if (currentTrack !== ""
                    && islandState !== "control_center"
                    && islandState !== "notification"
                    && islandState !== "bluetooth_expanded") {
                if (islandState === "expanded" && !expandedByPlayerAutoOpen) return;
                showExpandedPlayer(true);
            }
        }

       Rectangle {
id: mainCapsule
                z: 5
                property int morphDuration: IslandMotion.standard
                readonly property int infoActiveTab: infoLoader.item ? infoLoader.item.activeTab : 0
            property real outlineWidth: IslandMotion.surfaceBorderWidth
            property color outlineColor: root.overviewContentVisible ? root.overviewCapsuleBorderColor : IslandMotion.surfaceBorderColor
            property real displayedWidth: baseTargetWidth
            readonly property real baseTargetWidth: {
                if (root.overviewVisible) return root.overviewCapsuleWidth;
                if (sideTransientRestoreTimer.running) {
                    if (islandContainer.restingState === "lyrics"
                            && ((islandContainer.islandState === "split" && islandContainer.splitOriginSide === "right")
                                || (islandContainer.islandState === "long_capsule" && islandContainer.workspaceOriginSide === "right"))) {
                        return islandContainer.lyricsCapsuleWidth;
                    }

                    if (islandContainer.restingState === "custom"
                            && ((islandContainer.islandState === "split" && islandContainer.splitOriginSide === "left")
                                || (islandContainer.islandState === "long_capsule" && islandContainer.workspaceOriginSide === "left"))) {
                        return islandContainer.customCapsuleWidth;
                    }
                }

                switch (islandContainer.islandState) {
                case "split":
                    return islandContainer.splitCapsuleWidth;
                case "long_capsule":
                    return 220;
                case "custom":
                    return islandContainer.customCapsuleWidth;
                case "lyrics":
                    return islandContainer.lyricsCapsuleWidth;
case "capturing":
                    return 220;
                case "search":
                    return searchLoader.item ? searchLoader.item.capsuleWidth : 500;
                case "control_center":
                case "lyrics_control_center":
                    return 420;
                case "power_menu":
                    return 340;
                case "notification_center":
                    return 340;
                case "info":
                    return 600;
                case "expanded":
                case "bluetooth_expanded":
                    return 400;
                case "equalizer":
                    return 700;
                case "notification":
                    if (!notificationLoader.item) return 272;
                    return Math.max(
                        notificationLoader.item.minimumWidth,
                        Math.min(notificationLoader.item.maximumWidth, notificationLoader.item.preferredWidth)
                    );
default:
                    return 140;
                }
            }
            readonly property real targetHeight: {
                if (root.overviewVisible) return root.overviewCapsuleHeight;

                switch (islandContainer.islandState) {
case "capturing":
                    return 38;
                case "search":
                    return searchLoader.item ? searchLoader.item.capsuleHeight : 38;
case "control_center":
                    if (controlCenterLoader.item && controlCenterLoader.item.powerMenuOpen)
                        return controlCenterLoader.item.notificationPanelTotalHeight
                    if (controlCenterLoader.item && controlCenterLoader.item.notificationPanelOpen)
                        return controlCenterLoader.item.notificationPanelTotalHeight
                    if (controlCenterLoader.item && controlCenterLoader.item.appearanceMenuOpen)
                        return controlCenterLoader.item.appearanceMenuTotalHeight
                    return 320 + (controlCenterLoader.item ? controlCenterLoader.item.controlCenterExtraHeight : 32);
case "power_menu":
                    return 72;
                case "notification_center":
                    return notificationCenterLoader.item
                        ? Math.min(420, notificationCenterLoader.item.contentHeight)
                        : 92;
case "lyrics_control_center": {
                    const lyricsItem = lyricsControlCenterLoader.item;
                    if (lyricsItem && lyricsItem.expandedView && lyricsItem.viewerMode !== "none")
                        return 64 + lyricsItem.expandedViewerHeight;
                    return 150 + (lyricsItem ? lyricsItem.controlCenterExtraHeight : 0);
                }
case "info":
                    return (mainCapsule.infoActiveTab === 0 || mainCapsule.infoActiveTab === 1) ? 360 : 300;
case "expanded":
                    return 193;
                case "bluetooth_expanded":
                    return 165;
                case "equalizer":
                    return 210;
                case "notification":
                    return notificationLoader.item
                        ? Math.max(56, Math.min(68, notificationLoader.item.preferredHeight))
                        : 56;
                default:
                    return 38;
                }
            }
            readonly property real targetRadius: {
                if (root.overviewVisible) return root.overviewCapsuleRadius;

                switch (islandContainer.islandState) {
case "capturing":
                    return 19;
                case "search":
                    return 19;
                case "control_center":
                case "lyrics_control_center":
                    return 34;
                case "power_menu":
                    return 36;
                case "notification_center":
                    return 26;
                    case "info":
                    return 34;
                case "expanded":
                case "bluetooth_expanded":
                    return 40;
               case "equalizer":
                    return 36;
                case "notification":
                    return mainCapsule.targetHeight / 2;
                default:
                    return 19;
                }
            }
            function sideSwipeWidthForProgress(progressValue) {
                if (progressValue < 0)
                    return 140 + (islandContainer.customCapsuleWidth - 140)
                        * islandContainer.clamp01(-progressValue);
                if (progressValue > 0)
                    return 140 + (islandContainer.lyricsCapsuleWidth - 140)
                        * islandContainer.clamp01(progressValue);
                return 140;
            }
            readonly property real sideSwipePreviewWidth: mainCapsule.sideSwipeWidthForProgress(
                islandContainer.swipeTransitionProgress
            )
opacity: (root.idleMode || root.sidebarEnabled) ? 0 : 1
visible: !root.idleMode
Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeOut } }
color: root.overviewContentVisible
    ? root.overviewCapsuleColor
    : (root.gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (root.capsuleUseWalColor
            ? Qt.rgba(root.capsuleWalColor.r, root.capsuleWalColor.g, root.capsuleWalColor.b, root.capsuleOpacity)
            : Qt.rgba(0, 0, 0, root.capsuleOpacity)))
            y: 5
            anchors.horizontalCenter: parent.horizontalCenter
            clip: true
            width: displayedWidth
            height: targetHeight
            radius: targetRadius

            onBaseTargetWidthChanged: {
                if (!capsuleMouseArea.sideSwipeInteractive && !islandContainer.sideSwipeSettling)
                    displayedWidth = baseTargetWidth;
            }

Behavior on displayedWidth  {
                NumberAnimation {
                    duration: capsuleMouseArea.sideSwipeInteractive ? 0 : mainCapsule.morphDuration
                    easing.type: IslandMotion.easeArrive
                }
            }
Behavior on height {
                enabled: !(controlCenterLoader.item && controlCenterLoader.item.batteryDrawerMoving)

                NumberAnimation {
                    duration: mainCapsule.morphDuration
                    easing.type: IslandMotion.easeArrive
                }
            }
Behavior on radius { NumberAnimation { duration: mainCapsule.morphDuration; easing.type: IslandMotion.easeArrive } }
            Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }
            Behavior on outlineWidth { NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeMove } }
            Behavior on outlineColor { ColorAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeMove } }
            border.width: outlineWidth
            border.color: outlineColor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(parent.radius - 1, 0)
                color: StyleTokens.transparent
                border.width: IslandMotion.surfaceBorderWidth
                border.color: StyleTokens.overviewInnerBorder
                opacity: root.overviewContentVisible ? 1 : 0

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: root.overviewContentVisible ? IslandMotion.contentEnterDelay : 0 }
                        NumberAnimation {
                            duration: root.overviewContentVisible ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                            easing.type: root.overviewContentVisible ? IslandMotion.easeMove : IslandMotion.easeOut
                        }
                    }
                }
            }

MouseArea {
                id: capsuleMouseArea
                anchors.fill: parent
                z: -1
enabled: !root.overviewVisible && twoFingerTouchArea.touchPoints.length < 2
acceptedButtons: root.dynamicIslandAcceptedButtons
                preventStealing: islandContainer.islandState !== "info"
                property real swipeStartX: 0
                property real swipeStartY: 0
                property real swipeStartProgress: 0
                property real swipeLastX: 0
                readonly property real sideSwipeVerticalTolerance: 24
                property bool swipeArmed: false
                property bool swipeMoved: false
                property bool sideSwipeInteractive: false
                property bool suppressNextClick: false
                property bool preparedOverviewOnPress: false

                Timer {
                    id: swipeSuppressReset
                    interval: 180
                    repeat: false
                    onTriggered: capsuleMouseArea.suppressNextClick = false
                }

onPressed: (mouse) => {
                    if (islandContainer.islandState === "info" || islandContainer.islandState === "search") {
                        swipeArmed = false
                        sideSwipeInteractive = false
                        return
                    }
                    const mappedPoint = capsuleMouseArea.mapToItem(islandContainer, mouse.x, mouse.y);
                    swipeStartX = mappedPoint.x;
                    swipeStartY = mappedPoint.y;
                    islandContainer.cancelSideSwipeSettle();
                    swipeArmed = mouse.button === Qt.LeftButton
                        && islandContainer.canShowSideSwipe;
                    swipeStartProgress = islandContainer.swipeTransitionProgress;
                    swipeLastX = mappedPoint.x;
                    swipeMoved = false;
                    sideSwipeInteractive = swipeArmed;
                    islandContainer.swipeTransitionProgress = swipeStartProgress;

                    let pressedAction = "";
                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)) {
                        pressedAction = userConfig.dynamicIslandPrimaryAction;
                    } else if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandSecondaryButton)) {
                        pressedAction = userConfig.dynamicIslandSecondaryAction;
                    }

                    preparedOverviewOnPress = pressedAction === "openOverview"
                        || (pressedAction === "toggleOverview" && root.overviewPhase === "closed");
                    if (preparedOverviewOnPress)
                        root.prepareOverviewEverywhere();
                }

                onPositionChanged: (mouse) => {
                    if (!pressed || !swipeArmed || suppressNextClick || twoFingerTouchArea.touchPoints.length >= 2) return;

                    const mappedPoint = capsuleMouseArea.mapToItem(islandContainer, mouse.x, mouse.y);
                    const deltaX = mappedPoint.x - swipeLastX;
                    const deltaY = Math.abs(mappedPoint.y - swipeStartY);
                    const adjustedDeltaX = deltaY < sideSwipeVerticalTolerance ? deltaX : 0;
                    const nextProgress = islandContainer.advanceSideSwipeProgress(
                        islandContainer.swipeTransitionProgress,
                        adjustedDeltaX
                    );

                    swipeMoved = swipeMoved || Math.abs(nextProgress - swipeStartProgress) > 0.03 || deltaY > 6;
                    swipeLastX = mappedPoint.x;
                    islandContainer.swipeTransitionProgress = nextProgress;
                    mainCapsule.displayedWidth = mainCapsule.sideSwipePreviewWidth;
                }

                onReleased: {
                    if (swipeMoved) {
                        if (preparedOverviewOnPress)
                            root.cancelPreparedOverviewEverywhere();
                        preparedOverviewOnPress = false;
                        suppressNextClick = true;
                        swipeSuppressReset.restart();
                    }
                    let settleResult = {
                        action: "",
                        progress: islandContainer.sideSwipeRestProgressForProgress(swipeStartProgress),
                        width: islandContainer.sideSwipeRestWidthForProgress(swipeStartProgress)
                    };

                    if (swipeArmed)
                        settleResult = islandContainer.resolveSideSwipeSettle(
                            swipeStartProgress,
                            islandContainer.swipeTransitionProgress
                        );

                    sideSwipeInteractive = false;

                    if (swipeArmed)
                        islandContainer.beginSideSwipeSettle(settleResult.width);
                    else
                        mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;

                    if (swipeArmed) {
                        switch (settleResult.action) {
                        case "time":
                            islandContainer.showTimeCapsule();
                            break;
                        case "custom":
                            islandContainer.showCustomCapsule();
                            break;
                        case "lyrics":
                            islandContainer.showLyricsCapsule();
                            break;
                        default:
                            islandContainer.swipeTransitionProgress = settleResult.progress;
                        }
                    } else {
                        islandContainer.swipeTransitionProgress = settleResult.progress;
                    }
                    swipeArmed = false;
                    swipeMoved = false;
                }

                onCanceled: {
                    if (preparedOverviewOnPress)
                        root.cancelPreparedOverviewEverywhere();
                    swipeArmed = false;
                    swipeMoved = false;
                    sideSwipeInteractive = false;
                    suppressNextClick = false;
                    preparedOverviewOnPress = false;
                    swipeSuppressReset.stop();
                    mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
                    islandContainer.swipeTransitionProgress = islandContainer.swipeRestProgressForState();
                }

                onClicked: (mouse) => {
                    if (suppressNextClick) {
                        swipeSuppressReset.stop();
                        suppressNextClick = false;
                        preparedOverviewOnPress = false;
                        return;
                    }

if (islandContainer.islandState === "info") {
                        preparedOverviewOnPress = false;
                        if (mouse.button === Qt.MiddleButton)
                            islandContainer.smartRestoreState();
                        return;
                    }

                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)) {
                        preparedOverviewOnPress = false;
                        islandContainer.handleConfiguredClickAction(userConfig.dynamicIslandPrimaryAction);
                        return;
                    }

                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandSecondaryButton)) {
                        preparedOverviewOnPress = false;
                        islandContainer.handleConfiguredClickAction(userConfig.dynamicIslandSecondaryAction);
                        return;
                    }
                    if (mouse.button === Qt.MiddleButton) {
                        preparedOverviewOnPress = false;
                        islandContainer.handleConfiguredClickAction("toggleInfoPanel");
                        return;
                    }
                }
            }
            MultiPointTouchArea {
                id: twoFingerTouchArea
                anchors.fill: parent
                z: 0
                enabled: !root.overviewVisible
                mouseEnabled: false
                minimumTouchPoints: 2
                maximumTouchPoints: 2

                property real swipeStartX: 0
                property real swipeStartProgress: 0
                property bool swipeMoved: false

                onPressed: (touchPoints) => {
                    const centerPoint = islandContainer.mapFromItem(twoFingerTouchArea, 
                        (touchPoints[0].x + touchPoints[1].x) / 2,
                        (touchPoints[0].y + touchPoints[1].y) / 2);
                    swipeStartX = centerPoint.x;
                    swipeStartProgress = islandContainer.swipeTransitionProgress;
                    swipeMoved = false;
                    islandContainer.cancelSideSwipeSettle();
                }

                onUpdated: (touchPoints) => {
                    const centerPoint = islandContainer.mapFromItem(twoFingerTouchArea, 
                        (touchPoints[0].x + touchPoints[1].x) / 2,
                        (touchPoints[0].y + touchPoints[1].y) / 2);
                    
                    const deltaX = centerPoint.x - swipeStartX;
                    const nextProgress = islandContainer.advanceSideSwipeProgress(
                        swipeStartProgress,
                        deltaX
                    );

                    if (Math.abs(nextProgress - swipeStartProgress) > 0.03) {
                        swipeMoved = true;
                    }

                    islandContainer.swipeTransitionProgress = nextProgress;
                    mainCapsule.displayedWidth = mainCapsule.sideSwipePreviewWidth;
                }

                onReleased: {
                    if (swipeMoved) {
                        const settleResult = islandContainer.resolveSideSwipeSettle(
                            swipeStartProgress,
                            islandContainer.swipeTransitionProgress
                        );

                        islandContainer.beginSideSwipeSettle(settleResult.width);

                        switch (settleResult.action) {
                        case "time":
                            islandContainer.showTimeCapsule();
                            break;
                        case "custom":
                            islandContainer.showCustomCapsule();
                            break;
                        case "lyrics":
                            islandContainer.showLyricsCapsule();
                            break;
                        default:
                            islandContainer.swipeTransitionProgress = settleResult.progress;
                        }
                    } else {
                        islandContainer.swipeTransitionProgress = islandContainer.sideSwipeRestProgressForProgress(swipeStartProgress);
                    }
                    swipeMoved = false;
                }
            }

            Loader {
                id: customSwipeLoader
                anchors.fill: parent
                active: islandContainer.customSwipeVisible
                asynchronous: false
                visible: active

                onLoaded: islandContainer.syncCustomCapsuleWidth()

sourceComponent: Component {
                    SwipeCustomInfoLayer {
                        items: islandContainer.customLeftItems
                        cavaLevels: islandContainer.cavaLevels
                        timeText: timeObj.currentTime
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.heroFontFamily
                        timeFontFamily: root.heroFontFamily
                        minimumWidth: 220
                        maximumWidth: Math.max(220, root.width - 48)
                        transitionProgress: islandContainer.swipeTransitionProgress
                        recordingActive: islandContainer.screenRecordingActive
                        showSecondaryText: islandContainer.workspaceOriginSide !== "left"
                            && islandContainer.splitOriginSide !== "left"
                        showCondition: true
                        onPreferredWidthChanged: islandContainer.syncCustomCapsuleWidth()
                        activePlayer: islandContainer.activePlayer
                        currentArtUrl: islandContainer.currentArtUrl
                    }
                }
            }

            Loader {
                id: lyricsSwipeLoader
                anchors.fill: parent
                active: islandContainer.lyricsSwipeVisible
                asynchronous: false
                visible: active

                onLoaded: islandContainer.syncLyricsCapsuleWidth()

                sourceComponent: Component {
                    SwipeLyricsLayer {
showTray: false
                        lyricText: islandContainer.lyricsDisplayText
                        timeText: timeObj.currentTime
                        textFontFamily: root.textFontFamily
                        timeFontFamily: root.timeFontFamily
                        textPixelSize: 16
                        minimumWidth: 220
                        maximumWidth: Math.max(220, root.width - 48)
                        transitionProgress: islandContainer.rightSwipeProgress
                        recordingActive: islandContainer.screenRecordingActive
                        showSecondaryText: islandContainer.workspaceOriginSide !== "right"
                            && islandContainer.splitOriginSide !== "right"
showCondition: true
                        onPreferredWidthChanged: islandContainer.syncLyricsCapsuleWidth()
                        currentArtUrl: islandContainer.currentArtUrl
                        cavaLevels: islandContainer.cavaLevels
                    }
                }
            }

            Loader {
                id: splitIconLoader
                anchors.fill: parent
                active: !root.overviewVisible && islandContainer.splitShowsIconOnly
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    SplitIconLayer {
                        iconText: islandContainer.splitIcon
                        iconFontFamily: root.iconFontFamily
                        transitionProgress: islandContainer.swipeTransitionProgress
                        slideDirection: islandContainer.splitOriginSide
                        showCondition: true
                    }
                }
            }

            Loader {
                id: osdLayerLoader
                anchors.fill: parent
                active: !root.overviewVisible && islandContainer.splitUsesExtendedLayout
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    OsdLayer {
                        iconText: islandContainer.splitIcon
                        progress: islandContainer.osdProgress
                        customText: islandContainer.osdCustomText
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        transitionProgress: islandContainer.swipeTransitionProgress
                        slideDirection: islandContainer.splitOriginSide
                        showCondition: true
                    }
                }
            }

            Loader {
                id: workspaceLayerLoader
                anchors.fill: parent
                active: !root.overviewVisible
                    && islandContainer.islandState === "long_capsule"
                    && (islandContainer.workspaceOriginSide !== "none"
                        || Math.abs(islandContainer.swipeTransitionProgress) < 0.001)
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    WorkspaceLayer {
                        workspaceId: islandContainer.currentWs
                        displayText: "Workspace " + islandContainer.currentWs
                        textFontFamily: root.textFontFamily
                        textPixelSize: 16
                        animateVisibility: islandContainer.restingState === "normal"
                        transitionProgress: islandContainer.swipeTransitionProgress
                        showCondition: true
                        slideDirection: islandContainer.workspaceOriginSide
                    }
                }
            }

Loader {
                id: expandedPlayerLoader
                anchors.fill: parent
                active: islandContainer.expandedLayerVisible
                asynchronous: false
                visible: active

sourceComponent: Component {
                    ExpandedPlayerLayer {
                        currentArtUrl: islandContainer.currentArtUrl
                        currentTrack: islandContainer.currentTrack
                        currentArtist: islandContainer.currentArtist
timePlayed: islandContainer.timePlayed
                        timeTotal: islandContainer.timeTotal
                        trackProgress: islandContainer.trackProgress
activePlayer: islandContainer.activePlayer
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.expandedLayerVisible
                        onControlPressed: islandContainer.suppressCapsuleClick()
                        cavaLevels: islandContainer.cavaLevels
                        mediaWorkspaceId: islandContainer.mediaWorkspaceId
                        mediaPlayerName: islandContainer.mediaPlayerName
                    }
                }
            }

            Loader {
                id: equalizerLoader
                anchors.fill: parent
                active: islandContainer.equalizerLayerVisible
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    EqualizerPanel {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.equalizerLayerVisible
                    }
                }
            }

            Loader {
                id: bluetoothExpandedLoader
                anchors.fill: parent
                active: islandContainer.bluetoothExpandedLayerVisible
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    BluetoothExpandedLayer {
                        device: islandContainer.bluetoothExpandedDevice
                        volumeLevel: islandContainer.currentVolume
                        iconText: ""
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.bluetoothExpandedLayerVisible
                    }
                }
            }

Loader {
    id: notificationLoader
    anchors.fill: parent
    active: true
    asynchronous: false
    visible: islandContainer.notificationLayerVisible

sourceComponent: Component {
                    NotificationLayer {
                        appName: islandContainer.notificationAppName
                        summary: islandContainer.notificationSummary
                        body: islandContainer.notificationBody
                        iconText: root.notificationStatusIcon
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: true
                        onActivated: islandContainer.openNotificationHistory()
                    }
                }
            }
Loader {
                id: infoLoader
                anchors.fill: parent
                active: true
                asynchronous: false
                visible: islandContainer.islandState === "info"
                sourceComponent: Component {
                    InfoLayer {
                        showCondition: islandContainer.islandState === "info"
                        textFontFamily: root.textFontFamily
                        iconFontFamily: root.iconFontFamily
                        onRequestClose: islandContainer.smartRestoreState()
                    }
                }
            }
Loader {
                id: searchLoader
                anchors.fill: parent
                active: true
                asynchronous: false
                visible: islandContainer.searchLayerVisible
                focus: islandContainer.searchLayerVisible

                property int capsuleWidth: 500
                property int capsuleHeight: 38

                sourceComponent: Component {
SearchPillLayer {
                        anchors.fill: parent
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.searchLayerVisible
                        onCapsuleWidthChanged: searchLoader.capsuleWidth = capsuleWidth
                        onCapsuleHeightChanged: searchLoader.capsuleHeight = capsuleHeight
                        onCloseRequested: islandContainer.smartRestoreState()
onLaunchRequested: function(exec, isCmd) {
                            if (isCmd)
                                searchExec.run(exec)
                            else
                                searchExec.launch(exec)
                            islandContainer.smartRestoreState()
                        }
                    }
                }
            }

            Loader {
                id: capturingLoader
                anchors.fill: parent
                active: islandContainer.capturingLayerVisible
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    Item {
                        anchors.fill: parent
                        opacity: islandContainer.capturingLayerVisible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "\uf030"
                                font.family: root.iconFontFamily
                                font.pixelSize: 13
                                color: "white"
                                opacity: 0.7
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: capturingLabel
                                text: "Capturing…"
                                color: "white"
                                font.pixelSize: 13
                                font.family: root.textFontFamily
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter

                                Connections {
                                    target: islandContainer
                                    function onCapturingTextChanged() {
                                        capturingLabel.text = islandContainer.capturingText
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Loader {
                id: controlCenterLoader
                anchors.fill: parent
                active: islandContainer.controlCenterLayerVisible || root.anyConnectivityDetailMounted
                asynchronous: false
                visible: active

sourceComponent: Component {
                    ControlCenterLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        sliderIntroDelay: mainCapsule.morphDuration
                        currentTime: timeObj.currentTime
                        currentDateLabel: timeObj.currentDateLabel
                        batteryCapacity: islandContainer.batteryCapacity
                        isCharging: islandContainer.isCharging
                        volumeLevel: islandContainer.currentVolume
                        brightnessLevel: islandContainer.currentBrightness
                        currentWorkspace: islandContainer.currentWs
notificationHistory: islandContainer.notificationHistory
                        onClearNotificationHistoryRequested: islandContainer.clearNotificationHistory()
dndActive: islandContainer.dndActive
                        onDndToggleRequested: islandContainer.toggleDnd()
capsuleOpacity: root.capsuleOpacity
                        capsuleUseWalColor: root.capsuleUseWalColor
                        capsuleWalColors: root.capsuleWalColors
                        capsuleWalColorIndex: root.capsuleWalColorIndex
                        onAppearanceOpacityRequested: function(value) { root.capsuleOpacity = value }
                        onAppearanceWalColorToggleRequested: function(enabled) { root.capsuleUseWalColor = enabled }
onAppearanceWalColorIndexRequested: function(index) { root.capsuleWalColorIndex = index }
			gamemodeActive: root.gamemodeActive
                        onGamemodeToggleRequested: root.toggleGamemode()
pinned: root.pinned
                        onPinToggleRequested: root.pinned = !root.pinned
bubblesEnabled: root.bubblesEnabled
                        onBubblesToggleRequested: root.bubblesEnabled = !root.bubblesEnabled
dockEnabled: root.dockEnabled
                        onDockEnabledToggleRequested: root.dockEnabled = !root.dockEnabled
dockMode: root.dockMode
                        onDockModeChangeRequested: function(mode) { root.dockMode = mode }
idleMode: root.idleMode
                        onIdleModeToggleRequested: function(enabled) { root.idleMode = enabled }
sidebarEnabled: root.sidebarEnabled
                        onSidebarToggleRequested: {
                            root.sidebarEnabled = !root.sidebarEnabled
                            appearanceSettingsSaveTimer.stop()
                            root.saveAppearanceSettingsNow()
                        }
                        showCondition: islandContainer.controlCenterLayerVisible
                        onConnectivityPanelRequested: function(kind, open) {
                            root.setConnectivityDetailVisible(kind, open)
                        }
                        onScreenshotPanelRequested: function(open) {
                            if (open) {
                                screenshotDetailCleanupTimer.stop()
                                root.screenshotDetailMounted = true
                                root.screenshotDetailOpen = true
                            } else {
                                root.screenshotDetailOpen = false
                                screenshotDetailCleanupTimer.restart()
                            }
                        }
                    }
                }
            }

            Loader {
                id: powerMenuLoader
                anchors.fill: parent
                active: islandContainer.powerMenuLayerVisible
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    PowerMenuLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.powerMenuLayerVisible
                            onOpenControlCenterRequested: islandContainer.showControlCenter()
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            Loader {
                id: notificationCenterLoader
                anchors.fill: parent
                active: islandContainer.notificationCenterLayerVisible
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    NotificationCenterLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        notificationHistory: islandContainer.notificationHistory
                        showCondition: islandContainer.notificationCenterLayerVisible
                        onClearRequested: islandContainer.clearNotificationHistory()
                        onCloseRequested: islandContainer.smartRestoreState()
                        onDismissRequested: function(entryId) {
                            islandContainer.dismissNotificationFromHistory(entryId)
                        }
                    }
                }
            }

            Loader {
                id: lyricsControlCenterLoader
                anchors.fill: parent
                active: islandContainer.lyricsControlCenterLayerVisible
                asynchronous: false
                visible: active

sourceComponent: Component {
                    LyricsControlCenter {
                        iconFontFamily:   root.iconFontFamily
                        textFontFamily:   root.textFontFamily
                        heroFontFamily:   root.heroFontFamily
                        sliderIntroDelay: mainCapsule.morphDuration
                        currentTrack:     islandContainer.currentTrack
                        currentArtist:    islandContainer.currentArtist
                        showCondition:    islandContainer.lyricsControlCenterLayerVisible
                        lyricManager:     islandContainer.lyricManagerInstance
                        activePlayer:     islandContainer.activePlayer
                        currentArtUrl:    islandContainer.currentArtUrl
                        expandedView:     root.lyricsExpandedView
                        onExpandedViewToggleRequested: function(expanded) {
                            root.lyricsExpandedView = expanded
                        }
                    }
                }
            }

            Loader {
                id: overviewLoader

                anchors.fill: parent
                active: root.overviewLoaderActive
                asynchronous: false
                visible: root.overviewContentVisible

                onStatusChanged: {
                    if (status === Loader.Ready && root.overviewPreparing) {
                        root.beginOverviewOpening();
                    }
                }

sourceComponent: Component {
                    WorkspaceOverviewScene {
                        screen: root.screen
                        showCondition: root.overviewVisible
                        previewsEnabled: root.overviewContentVisible
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        wallpaperPath: root.overviewWallpaperSource
                        windowCornerRadius: root.overviewWindowCornerRadius
                        onCloseRequested: root.closeOverviewEverywhere()
                    }
                }

                WheelHandler {
                    enabled: root.overviewVisible
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const ov = islandContainer.overviewView;
                        const rows    = ov ? ov.rows    : 2;
                        const columns = ov ? ov.columns : 5;
                        const wpg     = rows * columns;
                        const curId   = root.hyprMonitor && root.hyprMonitor.activeWorkspace
                            ? root.hyprMonitor.activeWorkspace.id : 1;
                        const group = Math.floor((curId - 1) / wpg);
                        const minId = group * wpg + 1;
                        const maxId = minId + wpg - 1;
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                        let t = delta < 0 ? curId + 1 : curId - 1;
                        if (t > maxId) t = minId;
                        if (t < minId) t = maxId;
                        hyprDispatch.focusWorkspace(t);
                    }
                }
            }

}

WorkspaceBubble {
            id: workspaceBubble
            x: 16
            monitorName: root.hyprMonitorName
            currentWorkspace: islandContainer.currentWs
            textFontFamily: root.heroFontFamily
            iconFontFamily: root.iconFontFamily
            useWalColor: root.capsuleUseWalColor
            walColor: root.capsuleWalColor
            capsuleOpacityValue: root.capsuleOpacity
            gamemodeActive: root.gamemodeActive
            opacity: (root.bubblesEnabled && !root.idleMode && !root.sidebarEnabled) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }
            onDotClicked: function(workspaceId) { hyprDispatch.focusWorkspace(workspaceId) }
        }

SystrayBubble {
            id: systrayBubble
            x: root.width - width - 16
            useWalColor: root.capsuleUseWalColor
            walColor: root.capsuleWalColor
            capsuleOpacityValue: root.capsuleOpacity
            gamemodeActive: root.gamemodeActive
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            dndActive: islandContainer.dndActive
            unseenCount: islandContainer.unseenNotificationCount
            notificationPulseToggle: islandContainer.notificationPulseToggle
            onDndToggleRequested: islandContainer.toggleDnd()
            onNotificationCenterRequested: {
                if (islandContainer.islandState === "notification_center") islandContainer.smartRestoreState()
                else islandContainer.showNotificationCenter()
            }
            onPowerMenuRequested: {
                if (islandContainer.islandState === "power_menu") islandContainer.smartRestoreState()
                else islandContainer.showPowerMenu()
            }
            opacity: (root.bubblesEnabled && !root.idleMode && !root.sidebarEnabled) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }
        }

Item {
            id: dndBubble
            readonly property bool shouldShow: !root.bubblesEnabled && islandContainer.dndBubbleVisible
            property bool mounted: false
            property real reveal: 0
readonly property int bubbleSize: 26
            readonly property real stackOffset: 0
            readonly property real hiddenX: mainCapsule.x + mainCapsule.width - width * 0.62
            readonly property real shownX: mainCapsule.x + mainCapsule.width + 8 + stackOffset
            readonly property real centerY: mainCapsule.y + mainCapsule.height / 2 - height / 2

            width: bubbleSize
            height: bubbleSize
            x: hiddenX + (shownX - hiddenX) * reveal
            y: centerY + (1 - reveal) * 10
            z: 5
            visible: mounted
            opacity: reveal
            scale: 0.55 + reveal * 0.45
            transformOrigin: Item.Center

            onShouldShowChanged: {
                if (shouldShow) {
                    dndBubbleShowDelayTimer.restart();
                } else {
                    dndBubbleShowDelayTimer.stop();
                    dndBubbleShowAnimation.stop();
                    dndBubbleHideAnimation.stop();
                    if (dndBubble.mounted)
                        dndBubbleHideAnimation.restart();
                }
            }

            Timer {
                id: dndBubbleShowDelayTimer
                interval: 260
                repeat: false
                onTriggered: {
                    if (!dndBubble.shouldShow) return;
                    dndBubble.mounted = true;
                    dndBubbleHideAnimation.stop();
                    dndBubbleShowAnimation.restart();
                }
            }

            NumberAnimation {
                id: dndBubbleShowAnimation
                target: dndBubble; property: "reveal"
                from: dndBubble.reveal; to: 1
                duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive
            }

            NumberAnimation {
                id: dndBubbleHideAnimation
                target: dndBubble; property: "reveal"
                from: dndBubble.reveal; to: 0
                duration: IslandMotion.fast; easing.type: Easing.InCubic
                onStopped: {
                    if (!dndBubble.shouldShow && dndBubble.reveal <= 0.001)
                        dndBubble.mounted = false;
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(0.55, 0.35, 0.85, 0.92)
            }

            Text {
                anchors.centerIn: parent
                text: "\uf1f6"
                font.family: root.iconFontFamily
                font.pixelSize: 12
                color: "white"
            }
        }

        ConnectivityDetailShell {
            id: wifiConnectivityDetailShell

            open: root.wifiConnectivityDetailOpen
            mounted: root.wifiConnectivityDetailMounted
            rightSide: false
            panelKind: "wifi"
            provider: controlCenterLoader.item
            mainCapsule: mainCapsule
            availableWidth: root.width
            detailWidth: root.connectivityDetailWidth
            detailHeight: root.connectivityDetailHeight
            detailGap: root.connectivityDetailGap
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            heroFontFamily: root.heroFontFamily
        }

        ConnectivityDetailShell {
            id: bluetoothConnectivityDetailShell

            open: root.bluetoothConnectivityDetailOpen
            mounted: root.bluetoothConnectivityDetailMounted
            rightSide: true
            panelKind: "bluetooth"
            provider: controlCenterLoader.item
            mainCapsule: mainCapsule
            availableWidth: root.width
            detailWidth: root.connectivityDetailWidth
            detailHeight: root.connectivityDetailHeight
            detailGap: root.connectivityDetailGap
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            heroFontFamily: root.heroFontFamily
        }
        
        Item {
            id: screenshotDetailShell
            visible: root.screenshotDetailMounted
            width: root.connectivityDetailWidth
            height: root.connectivityDetailHeight

            x: mainCapsule.x + mainCapsule.width + root.connectivityDetailGap
            y: mainCapsule.y

            opacity: root.screenshotDetailOpen ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.connectivityDetailAnimationDuration; easing.type: Easing.OutCubic }
            }

            transform: Translate {
                x: root.screenshotDetailOpen ? 0 : -12
                Behavior on x {
                    NumberAnimation { duration: root.connectivityDetailAnimationDuration; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 28
                color: Qt.rgba(0.08, 0.08, 0.10, 0.95)
                border.color: Qt.rgba(1,1,1,0.12)
                border.width: 1

                ScreenshotDetailPanel {
                    anchors.fill: parent
                    anchors.margins: 16
                    iconFontFamily: root.iconFontFamily
                    textFontFamily: root.textFontFamily
                    onCaptureRequested: function(mode, delay) {
                        root.screenshotDetailOpen = false
                        screenshotDetailCleanupTimer.restart()
                        islandContainer.showCapturing(
                            delay > 0 ? "Capturing in " + delay + "s…" : "Capturing…"
                        )
                        screenshotDelayTimer.pendingMode = mode
                        screenshotDelayTimer.pendingDelay = delay
                        screenshotDelayTimer.totalWait = Math.max(1000, delay * 1000 + 1000)
                        screenshotDelayTimer.elapsed = 0
                        screenshotDelayTimer.restart()
                    }
                }
            }

        }

    Timer {
        id: screenshotDelayTimer
        property string pendingMode: "area"
        property int pendingDelay: 0
        property int totalWait: 1000
        property int elapsed: 0
        interval: 100
        repeat: true
        onTriggered: {
            elapsed += 100
            let remaining = Math.ceil((totalWait - elapsed) / 1000)
            if (remaining > 0)
                islandContainer.capturingText = remaining > 0 ? "Capturing in " + remaining + "s…" : "Capturing…"
            if (elapsed >= totalWait) {
                stop()
                islandContainer.capturingText = "Capturing…"
                screenshotShooter.shoot(pendingMode)
            }
        }
    }

QtObject {
    id: searchExec

    function run(cmd) {
        let p = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
        p.command = ["bash", "-c", cmd]
        p.running = true
    }

    function launch(exec) {
        let args = exec.replace(/%[UuFfDdNnickvm]/g, "").trim().split(/\s+/).filter(function(s) { return s.length > 0 })
        let p = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
        p.command = args
        p.running = true
    }
}

    Process {
        id: screenshotShooter
        function shoot(mode) {
            let cmd = `
                DIR="$HOME/Pictures/Screenshots"
                mkdir -p "$DIR"
                FILENAME="screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
                FINAL="$DIR/$FILENAME"
                success=false
                if [ "${mode}" = "screen" ]; then
                    grim "$FINAL" && success=true
                elif [ "${mode}" = "active" ]; then
                    GEOM=$(hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print(f"{w[\\"at\\"][0]},{w[\\"at\\"][1]} {w[\\"size\\"][0]}x{w[\\"size\\"][1]}")' 2>/dev/null)
                    if [ -n "$GEOM" ]; then
                        grim -g "$GEOM" "$FINAL" && success=true
                    else
                        grimblast save active "$FINAL" && success=true
                    fi
                elif [ "${mode}" = "area" ]; then
                    grimblast save area "$FINAL" && success=true
                fi
                if [ "$success" = true ] && [ -f "$FINAL" ]; then
                    wl-copy < "$FINAL"
                    notify-send -a "Screenshot" -i "$FINAL" "Saved & copied" "$FILENAME"
                    echo "$FINAL"
                fi
            `
            command = ["bash", "-c", cmd]
            running = true
        }
        stdout: SplitParser { onRead: {} }
        onRunningChanged: {
            if (!running) islandContainer.finishCapturing()
        }
    }

IslandRootGestureArea {
        anchors.fill: parent
        enabled: root.topGestureInputActive
        islandController: islandContainer
        capsule: mainCapsule
    }

    IdleOverlayWindow {
        screen: root.screen
        hyprMonitor: root.hyprMonitor
        idleMode: root.idleMode
        onIdleModeToggleRequested: function(enabled) { root.idleMode = enabled }

        timeText: timeObj.currentTime
        dateText: timeObj.currentDateLabel

currentWorkspace: islandContainer.currentWs
        onWorkspaceDotClicked: function(id) { hyprDispatch.focusWorkspace(id) }

        notificationHistory: islandContainer.notificationHistory

        lyricManager: islandContainer.lyricManagerInstance
        inlineLyricsRaw: islandContainer.mediaController.inlineLyricsRaw

        activePlayer: islandContainer.activePlayer
        currentTrack: islandContainer.currentTrack
        currentArtist: islandContainer.currentArtist
        currentArtUrl: islandContainer.currentArtUrl
    }
}
}
