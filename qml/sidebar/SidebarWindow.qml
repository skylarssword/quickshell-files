import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import IslandBackend
import "../shared"
import "../island"
import "../common"

PanelWindow {
    id: root

    readonly property var userConfig: UserConfig

    property bool sidebarEnabled: false

    // ── Gamemode — turns entire sidebar black ─────────────────────────
    property bool gamemodeActive: false

    // ── Pywal / capsule color ─────────────────────────────────────────
    property bool  capsuleUseWalColor:   false
    property var   capsuleWalColors:     []
    property int   capsuleWalColorIndex: 0
    property real  capsuleOpacityValue:  0.20

    readonly property color capsuleWalColor:
        (capsuleWalColorIndex >= 0 && capsuleWalColorIndex < capsuleWalColors.length)
        ? capsuleWalColors[capsuleWalColorIndex] : "#000000"

    // Pill background: if gamemode → pure black; else pywal or plain black at opacity
    readonly property color pillColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (capsuleUseWalColor
            ? Qt.rgba(capsuleWalColor.r, capsuleWalColor.g, capsuleWalColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    // ── Workspace tracking (live, per-monitor) ────────────────────────
    readonly property var hyprMonitor: screen
        ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor

    readonly property int currentWorkspace: hyprMonitor && hyprMonitor.activeWorkspace
        ? hyprMonitor.activeWorkspace.id : 1

    readonly property var monitorWorkspaces: {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return []
        const mon = root.hyprMonitor
        if (!mon) return []
        const all = Hyprland.workspaces.values
        return all.filter(w => w.monitor && w.monitor.name === mon.name)
                  .sort((a, b) => a.id - b.id)
    }

    // ── Active window title ───────────────────────────────────────────
    readonly property var focusedClient: {
        if (!Hyprland.toplevels || !Hyprland.toplevels.values) return null
        const all = Hyprland.toplevels.values
        for (let i = 0; i < all.length; i++)
            if (all[i].activated) return all[i]
        return null
    }
    readonly property string windowTitle: {
        if (!focusedClient) return ""
        const title = focusedClient.title || ""
        const cls   = (focusedClient.wayland && focusedClient.wayland.appId) || ""
        if (title === "") return cls
        return title.length > 22 ? cls : title
    }

    // ── MPRIS ─────────────────────────────────────────────────────────
    IslandMprisController {
        id: mediaController
        expanded: true
    }

    readonly property var   activePlayer:  mediaController.activePlayer
    readonly property string currentTrack:  mediaController.currentTrack
    readonly property string currentArtist: mediaController.currentArtist
    readonly property string currentArtUrl: mediaController.currentArtUrl
    readonly property real   trackProgress: mediaController.trackProgress
    readonly property string timePlayed:    mediaController.timePlayed
    readonly property string timeTotal:     mediaController.timeTotal

    // ── System state ──────────────────────────────────────────────────
    property int  batteryCapacity:   0
    property bool isCharging:        false
    property real currentVolume:     0.5
    property real currentBrightness: 0.5

    // ── Notifications ─────────────────────────────────────────────────
    property bool   dndActive:          false
    property var    notificationHistory: []
    property int    unreadCount:         0

    // ── Notification sound ────────────────────────────────────────────
    SoundEffect {
        id: notifSound
        source: Quickshell.shellDir + "/qml/shared/assets/sounds/notification.wav"
        volume: IslandConfiguration.notificationSoundVolume / 100.0
    }

    property int _notifIdCounter: 0
    property var _notifIconQueue: []

    function showNotification(appName, summary, body) {
        const entry = {
            id:        ++root._notifIdCounter,
            appName:   appName || "Notification",
            summary:   summary || body || "New notification",
            body:      summary !== "" ? body : "",
            appIcon:   "",
            timestamp: Date.now()
        }
        const updated = notificationHistory.slice()
        updated.unshift(entry)
        if (updated.length > 20) updated.length = 20
        notificationHistory = updated
        unreadCount++

        if (notifWidget.item) notifWidget.item.shake()

        // Play sound if not DND
        if (!root.dndActive && IslandConfiguration.notificationSoundEnabled)
            notifSound.play()

        // Kick off async icon lookup — toast will get icon once resolved
        queueNotificationIconLookup(entry.id, entry.appName)

        if (root.sidebarEnabled && !root.dndActive)
            notifToast.showToast(entry.appName, entry.summary)
    }

    function queueNotificationIconLookup(entryId, appName) {
        if (!appName || String(appName).trim() === "") return
        root._notifIconQueue.push({ id: entryId, name: String(appName).trim() })
        processNextNotificationIconLookup()
    }

    function processNextNotificationIconLookup() {
        if (notifIconLookup.running) return
        if (root._notifIconQueue.length === 0) return
        const item = root._notifIconQueue.shift()
        notifIconLookup.pendingEntryId = item.id
        const needle = item.name.toLowerCase().replace(/'/g, "")
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
        ]
        notifIconLookup.running = true
    }

    function updateNotificationIcon(entryId, iconPath) {
        const trimmed = String(iconPath || "").trim()
        if (trimmed === "") return
        let matchedAppName = ""
        notificationHistory = notificationHistory.map(function(e) {
            if (e.id !== entryId) return e
            matchedAppName = e.appName
            const next = Object.assign({}, e)
            next.appIcon = trimmed
            return next
        })
        // Update toast by appName — entryId isn't tracked there
        if (matchedAppName !== "")
            notifToast.updateIcon(matchedAppName, trimmed)
    }

    Process {
        id: notifIconLookup
        property int pendingEntryId: -1
        property string _buf: ""
        stdout: SplitParser { onRead: notifIconLookup._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const line = notifIconLookup._buf.trim()
                notifIconLookup._buf = ""
                if (line !== "" && notifIconLookup.pendingEntryId >= 0)
                    root.updateNotificationIcon(notifIconLookup.pendingEntryId, line)
                notifIconLookup.pendingEntryId = -1
                root.processNextNotificationIconLookup()
            }
        }
    }

    readonly property real pillWidth:    38
    readonly property real pillRadius:   19
    readonly property real edgeGap:      12
    readonly property real pillBaseHeight: 640
    readonly property int  wsOverflow: Math.max(0, (monitorWorkspaces ? monitorWorkspaces.length : 0) - 3)
    readonly property real pillMaxHeight: pillBaseHeight
        + wsOverflow * 23
        + (systraySection.expanded ? systraySection.expandedHeight - systraySection.collapsedHeight : 0)

    // ── Window setup ─────────────────────────────────────────────────
    color: "transparent"
    anchors { top: true; bottom: true; left: true }
    exclusiveZone: root.sidebarEnabled
        ? (pillWidth + edgeGap + (root.gamemodeActive ? 8 : 0))
        : -1
    aboveWindows: true
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: pillWidth + edgeGap * 2
    // Always keep the window alive so the exclusiveZone can animate back
    // to -1 before the compositor releases the reserved margin.
    // The pill uses opacity + Behavior to fade in/out instead.
    visible: true

    Behavior on exclusiveZone {
        NumberAnimation { duration: IslandMotion.durationMedium; easing.type: Easing.OutCubic }
    }

    mask: Region {
        x: Math.floor(sidePill.x)
        y: Math.floor(sidePill.y)
        width:  root.sidebarEnabled ? Math.ceil(sidePill.width)  : 0
        height: root.sidebarEnabled ? Math.ceil(sidePill.height) : 0
    }

    // ── IPC: same target as main bar, guards on sidebarEnabled ───────
    IpcHandler {
        target: "tide-sidebar"

        function toggleSearch(): void {
            appLauncher.toggle()
            if (appLauncher.launcherOpen) {
                musicPopup.close(); infoPopup.close()
                notifCenter.close(); controlCenter.close(); powerMenu.close()
            }
        }
        function toggleControlCenter(): void {
            controlCenter.toggle()
            if (controlCenter.popupOpen) {
                appLauncher.close(); musicPopup.close()
                infoPopup.close(); notifCenter.close(); powerMenu.close()
            }
        }
        function togglePowerMenu(): void {
            powerMenu.toggle()
            if (powerMenu.popupOpen) {
                appLauncher.close(); musicPopup.close()
                infoPopup.close(); notifCenter.close(); controlCenter.close()
            }
        }
        function toggleNotificationCenter(): void {
            notifCenter.toggle()
            if (notifCenter.popupOpen) {
                root.unreadCount = 0
                appLauncher.close(); musicPopup.close()
                infoPopup.close(); controlCenter.close(); powerMenu.close()
            }
        }
    }

    // ── Settings polling — reads appearance-settings.json like main bar ─
    Process {
        id: settingsQuery
        property string _buf: ""
        command: ["bash", "-c",
            "cat \"$HOME/.cache/quickshell/appearance-settings.json\" 2>/dev/null"]
        stdout: SplitParser { onRead: settingsQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const raw = settingsQuery._buf.trim()
                settingsQuery._buf = ""
                if (raw.length > 0) {
                    try {
                        const p = JSON.parse(raw)
                        if (typeof p.sidebarEnabled       === "boolean") root.sidebarEnabled      = p.sidebarEnabled
                        if (typeof p.capsuleOpacity       === "number")  root.capsuleOpacityValue  = p.capsuleOpacity
                        if (typeof p.capsuleUseWalColor   === "boolean") root.capsuleUseWalColor   = p.capsuleUseWalColor
                        if (typeof p.capsuleWalColorIndex === "number")  root.capsuleWalColorIndex = p.capsuleWalColorIndex
                    } catch (e) {}
                }
            }
        }
    }
    Timer {
        id: settingsPollTimer
        interval: 600; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!settingsQuery.running && !root._skipRead) settingsQuery.running = true
    }

    // ── Gamemode polling — same file as DynamicIslandWindow ───────────
    // ~/.config/ml4w/settings/gamemode-enabled exists → gamemode ON
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
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!gamemodePollQuery.running) gamemodePollQuery.running = true
    }

    // ── Pywal polling ─────────────────────────────────────────────────
    Process {
        id: walColorQuery
        property string _buf: ""
        command: ["bash", "-c", "cat \"$HOME/.cache/wal/colors\" 2>/dev/null"]
        stdout: SplitParser { onRead: walColorQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const lines = walColorQuery._buf.trim().split("\n")
                walColorQuery._buf = ""
                const parsed = lines.map(l => l.trim())
                                    .filter(l => /^#?[0-9A-Fa-f]{6}$/.test(l))
                                    .map(l => l.startsWith("#") ? l : "#" + l)
                if (parsed.length > 0) {
                    root.capsuleWalColors = parsed
                    if (root.capsuleWalColorIndex >= parsed.length)
                        root.capsuleWalColorIndex = 0
                }
            }
        }
    }
    Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!walColorQuery.running) walColorQuery.running = true
    }

    // ── Appearance persistence ────────────────────────────────────────
    // Skip one poll cycle after a local write so we don't read our own
    // write back before DynamicIslandWindow has had a chance to see it.
    property bool _skipRead: false

    Process { id: appearanceSaveExec }
    Process { id: sidebarToggleSaveExec }

    function saveAppearanceSettings() {
        root._skipRead = true
        appearanceSaveExec.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "F=\"$HOME/.cache/quickshell/appearance-settings.json\"; " +
            "existing=$(cat \"$F\" 2>/dev/null || echo '{}'); " +
            "echo \"$existing\" | python3 -c \"" +
            "import json,sys; d=json.load(sys.stdin); " +
            "d.update(json.loads(sys.argv[1])); print(json.dumps(d))\" '" +
            JSON.stringify({
                capsuleOpacity:       root.capsuleOpacityValue,
                capsuleUseWalColor:   root.capsuleUseWalColor,
                capsuleWalColorIndex: root.capsuleWalColorIndex
            }) + "' > \"$F\""]
        appearanceSaveExec.running = true
        skipReadTimer.restart()
    }

    function saveSidebarEnabled() {
        root._skipRead = true
        const val = root.sidebarEnabled ? "True" : "False"
        sidebarToggleSaveExec.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "F=\"$HOME/.cache/quickshell/appearance-settings.json\"; " +
            "existing=$(cat \"$F\" 2>/dev/null || echo '{}'); " +
            "echo \"$existing\" | python3 -c \"" +
            "import json,sys; d=json.load(sys.stdin); d['sidebarEnabled']=" + val + "; " +
            "print(json.dumps(d))\" > \"$F\""]
        sidebarToggleSaveExec.running = true
        skipReadTimer.restart()
    }

    Timer {
        id: skipReadTimer
        interval: 1500; repeat: false
        onTriggered: root._skipRead = false
    }

    // ── Workspace dispatch ────────────────────────────────────────────
    HyprlandDispatch {
        id: wsDispatch
        function go(id) { focusWorkspace(String(id)) }
    }

    // ── Popup windows ─────────────────────────────────────────────────
    SidebarAppLauncher {
        id: appLauncher
        gamemodeActive:      root.gamemodeActive
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        iconFontFamily:      root.userConfig.iconFontFamily
        textFontFamily:      root.userConfig.textFontFamily
    }

    SidebarMusicPopup {
        id: musicPopup
        gamemodeActive:      root.gamemodeActive
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        iconFontFamily:      root.userConfig.iconFontFamily
        textFontFamily:      root.userConfig.textFontFamily
        activePlayer:        root.activePlayer
        currentTrack:        root.currentTrack
        currentArtist:       root.currentArtist
        currentArtUrl:       root.currentArtUrl
        trackProgress:       root.trackProgress
        timePlayed:          root.timePlayed
        timeTotal:           root.timeTotal
    }

    SidebarPowerLayer {
        id: powerMenu
        gamemodeActive:      root.gamemodeActive
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        iconFontFamily:      root.userConfig.iconFontFamily
        textFontFamily:      root.userConfig.textFontFamily
    }

    SidebarInfoPopup {
        id: infoPopup
        gamemodeActive:      root.gamemodeActive
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        textFontFamily:      root.userConfig.textFontFamily
        iconFontFamily:      root.userConfig.iconFontFamily
    }

    SidebarNotifCenter {
        id: notifCenter
        iconFontFamily:      root.userConfig.iconFontFamily
        textFontFamily:      root.userConfig.textFontFamily
        notificationHistory: root.notificationHistory
        dndActive:           root.dndActive
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        gamemodeActive:      root.gamemodeActive
        onClearRequested:    { root.notificationHistory = []; root.unreadCount = 0 }
        onDismissRequested: function(entryId) {
            root.notificationHistory = root.notificationHistory.filter(e => e.id != entryId)
        }
        onDndToggleRequested: root.dndActive = !root.dndActive
    }

    SidebarNotifToast {
        id: notifToast
        textFontFamily:      root.userConfig.textFontFamily
        iconFontFamily:      root.userConfig.iconFontFamily
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        gamemodeActive:      root.gamemodeActive
    }

    IslandClock { id: sidebarClock }

    Connections {
        target: SystemServices
        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "") root.currentBrightness = value
        }
        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString === "") root.currentVolume = value
        }
    }

    Connections {
        target: SysBackend
        function onBrightnessChanged(value) {
            root.currentBrightness = value
        }
        function onVolumeChanged(volPercentage, isMuted) {
            root.currentVolume = volPercentage / 100.0
        }
    }

    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            SystemServices.requestBrightness()
            SystemServices.requestVolume()
            if (!batteryQuery.running) batteryQuery.running = true
        }
    }

    Process {
        id: batteryQuery
        property string _buf: ""
        command: ["bash", "-c",
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1"]
        stdout: SplitParser { onRead: batteryQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const lines = batteryQuery._buf.trim().split("\n")
                batteryQuery._buf = ""
                if (lines.length >= 1) {
                    const cap = parseInt(lines[0])
                    if (!isNaN(cap)) root.batteryCapacity = cap
                }
                if (lines.length >= 2) {
                    const status = lines[1].trim().toLowerCase()
                    root.isCharging = (status === "charging")
                }
            }
        }
    }

    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!batteryQuery.running) batteryQuery.running = true
    }

    SidebarControlCenterLayer {
        id: controlCenter
        iconFontFamily:      root.userConfig.iconFontFamily
        textFontFamily:      root.userConfig.textFontFamily
        heroFontFamily:      root.userConfig.heroFontFamily
        gamemodeActive:      root.gamemodeActive
        useWalColor:         root.capsuleUseWalColor
        walColor:            root.capsuleWalColor
        capsuleOpacityValue: root.capsuleOpacityValue
        dndActive:           root.dndActive
        sidebarEnabled:      root.sidebarEnabled
        currentTime:         sidebarClock.currentTime
        currentDateLabel:    sidebarClock.currentDateLabel
        batteryCapacity:     root.batteryCapacity
        isCharging:          root.isCharging
        volumeLevel:         root.currentVolume
        brightnessLevel:     root.currentBrightness
        capsuleUseWalColor:  root.capsuleUseWalColor
        capsuleWalColors:    root.capsuleWalColors
        capsuleWalColorIndex: root.capsuleWalColorIndex
        onDndToggleRequested:      root.dndActive = !root.dndActive
        onGamemodeToggleRequested: gamemodeToggleExec.running = true
        onSidebarToggleRequested: {
            controlCenter.close()
            root.sidebarEnabled = false
            root.saveSidebarEnabled()
        }
        onAppearanceWalColorToggleRequested: function(enabled) {
            root.capsuleUseWalColor = enabled
            root.saveAppearanceSettings()
        }
        onAppearanceWalColorIndexRequested: function(index) {
            root.capsuleWalColorIndex = index
            root.saveAppearanceSettings()
        }
        onAppearanceOpacityRequested: function(value) {
            root.capsuleOpacityValue = value
            root.saveAppearanceSettings()
        }
    }

    // Runs gamemode.sh so the file toggle matches DynamicIslandWindow's keybind
    Process {
        id: gamemodeToggleExec
        command: ["bash", "-c", "~/.config/hypr/scripts/gamemode.sh"]
    }

    // ── Pill ─────────────────────────────────────────────────────────
    Rectangle {
        id: sidePill
        anchors.left:           parent.left
        anchors.leftMargin:     root.edgeGap
        anchors.verticalCenter: parent.verticalCenter
        width:  root.pillWidth
        height: Math.min(parent.height - root.edgeGap * 2, root.pillMaxHeight)
        radius: root.pillRadius
        color:  root.pillColor
        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor
        clip: true

        Behavior on height  { NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive } }
        Behavior on color   { ColorAnimation  { duration: IslandMotion.durationMedium } }
        opacity: root.sidebarEnabled ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: Easing.OutCubic } }

        // ── Fixed top block (app launcher + divider) ─────────────────
        Column {
            id: topBlock
            anchors.top:              parent.top
            anchors.topMargin:        14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            // ── App launcher button ──────────────────────────────────
            Item {
                width: root.pillWidth; height: root.pillWidth
                Image {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    source: Quickshell.shellDir + "/qml/shared/assets/app-launcher.svg"
                    sourceSize: Qt.size(40, 40)
                    fillMode: Image.PreserveAspectFit
                    opacity: appBtnMouse.containsMouse || appLauncher.launcherOpen ? 1.0 : 0.65
                    scale:   appBtnMouse.containsMouse ? 1.15 : (appBtnMouse.pressed ? 0.85 : 1.0)
                    Behavior on opacity { NumberAnimation { duration: IslandMotion.micro } }
                    Behavior on scale   { NumberAnimation { duration: IslandMotion.micro; easing.type: Easing.OutBack } }
                }
                MouseArea {
                    id: appBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        appLauncher.toggle()
                        if (appLauncher.launcherOpen) musicPopup.close()
                    }
                }
            }

            // ── Divider ──────────────────────────────────────────────
            Rectangle {
                width: 20; height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: IslandMotion.surfaceBorderColor
            }
        }

        // ── Workspace dots — only this grows/shrinks ──────────────────
        Item {
            id: wsMiddle
            anchors.top:              topBlock.bottom
            anchors.topMargin:        10
            anchors.bottom:           lowerBlock.top
            anchors.bottomMargin:     10
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.pillWidth
            clip: true

            Column {
                anchors.centerIn: parent
                spacing: 5

                Repeater {
                    model: root.monitorWorkspaces
                    delegate: Item {
                        required property var modelData
                        readonly property bool isActive: modelData.id === root.currentWorkspace

                        width: root.pillWidth
                        height: 18
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            anchors.centerIn: parent
                            width:  8
                            height: isActive ? 18 : 8
                            radius: 4
                            color: isActive
                                ? "white"
                                : (dotMouse.containsMouse ? Qt.rgba(1,1,1,0.65) : Qt.rgba(1,1,1,0.30))

                            Behavior on height { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutBack } }
                            Behavior on color  { ColorAnimation  { duration: IslandMotion.micro } }
                        }

                        MouseArea {
                            id: dotMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wsDispatch.go(modelData.id)
                        }
                    }
                }
            }
        }

        // ── Fixed lower block (window title, music, clock, battery) ──
        Column {
            id: lowerBlock
            anchors.bottom:           bottomSection.top
            anchors.bottomMargin:     10
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            // ── Active window title — always constant height ───────────
            Item {
                width:   root.pillWidth
                height:  70
                clip:    true

                Text {
                    anchors.centerIn: parent
                    text:  root.windowTitle
                    color: "white"
                    opacity: root.windowTitle !== "" ? 0.50 : 0
                    font.family:    root.userConfig.textFontFamily
                    font.pixelSize: 11
                    font.weight:    Font.Medium
                    renderType:     Text.NativeRendering
                    rotation:       90
                    transformOrigin: Item.Center
                    elide:          Text.ElideRight
                    width:          60
                    horizontalAlignment: Text.AlignHCenter
                    Behavior on opacity { NumberAnimation { duration: IslandMotion.fast } }
                }
            }

            // ── Divider (only when window title showing) ──────────────
            Rectangle {
                width: 20; height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: IslandMotion.surfaceBorderColor
                opacity: root.windowTitle !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: IslandMotion.fast } }
            }

            // ── Music widget ─────────────────────────────────────────
            SidebarMusicWidget {
                anchors.horizontalCenter: parent.horizontalCenter
                pillWidth:      root.pillWidth
                activePlayer:   root.activePlayer
                currentArtUrl:  root.currentArtUrl
                iconFontFamily: root.userConfig.iconFontFamily
                isOpen:         musicPopup.popupOpen
                onToggled: {
                    musicPopup.toggle()
                    if (musicPopup.popupOpen) {
                        appLauncher.close()
                        infoPopup.close()
                    }
                }
            }

            // ── Divider ──────────────────────────────────────────────
            Rectangle {
                width: 20; height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                color: IslandMotion.surfaceBorderColor
            }

            // ── Clock ────────────────────────────────────────────────
            SidebarClockWidget {
                anchors.horizontalCenter: parent.horizontalCenter
                pillWidth:      root.pillWidth
                textFontFamily: root.userConfig.textFontFamily
                isOpen:         infoPopup.popupOpen
                onToggled: {
                    infoPopup.toggle()
                    if (infoPopup.popupOpen) {
                        appLauncher.close()
                        musicPopup.close()
                        notifCenter.close()
                    }
                }
            }

            // ── Battery ───────────────────────────────────────────────
            Item {
                width: root.pillWidth; height: 32
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.batteryCapacity >= 0

                Item {
                    id: vertBattery
                    width: 13; height: 26
                    anchors.centerIn: parent

                    // Nub on top
                    Rectangle {
                        width: 6; height: 3; radius: 1
                        color: Qt.rgba(1,1,1,0.70)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                    }

                    // Outer shell
                    Rectangle {
                        id: battShell
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height - 4
                        radius: 4
                        color: "transparent"
                        border.color: root.batteryCapacity <= 10 && !root.isCharging
                            ? "#ff3b30" : Qt.rgba(1,1,1,0.70)
                        border.width: 1.5
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        // Fill bar — rises from bottom
                        Rectangle {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            radius: 2
                            height: Math.max(0, (parent.height - 4) * (root.batteryCapacity / 100))
                            color: root.batteryCapacity <= 10 ? "#ff3b30"
                                 : root.batteryCapacity <= 20 ? "#ffcc00"
                                 : (root.isCharging ? "#7be17b" : "white")
                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on color  { ColorAnimation  { duration: 300 } }
                        }

                        // Charging bolt overlay
                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "\uf0e7"; color: "#7be17b"
                            font.family: root.userConfig.iconFontFamily
                            font.pixelSize: 10
                            visible: root.isCharging
                        }
                    }
                }
            }
        }

        // ── Bottom section (always pinned to bottom of pill) ──────────
        Column {
            id: bottomSection
            anchors.bottom:           parent.bottom
            anchors.bottomMargin:     10
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            // ── Notification bell ─────────────────────────────────────
            Loader {
                id: notifWidget
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: SidebarNotifWidget {
                    pillWidth:      root.pillWidth
                    iconFontFamily: root.userConfig.iconFontFamily
                    dndActive:      root.dndActive
                    unreadCount:    root.unreadCount
                    isOpen:         notifCenter.popupOpen
                    onToggled: {
                        notifCenter.toggle()
                        if (notifCenter.popupOpen) {
                            root.unreadCount = 0
                            appLauncher.close()
                            musicPopup.close()
                            infoPopup.close()
                            controlCenter.close()
                        }
                    }
                    onDndToggleRequested: root.dndActive = !root.dndActive
                }
            }

            // ── Cog / Control Center button ───────────────────────────
            SidebarControlCenterWidget {
                anchors.horizontalCenter: parent.horizontalCenter
                pillWidth:      root.pillWidth
                iconFontFamily: root.userConfig.iconFontFamily
                gamemodeActive: root.gamemodeActive
                isOpen:         controlCenter.popupOpen
                onToggled: {
                    controlCenter.toggle()
                    if (controlCenter.popupOpen) {
                        appLauncher.close()
                        musicPopup.close()
                        infoPopup.close()
                        notifCenter.close()
                        powerMenu.close()
                    }
                }
            }

            // ── Power button ──────────────────────────────────────────
            SidebarPowerWidget {
                anchors.horizontalCenter: parent.horizontalCenter
                pillWidth:      root.pillWidth
                iconFontFamily: root.userConfig.iconFontFamily
                gamemodeActive: root.gamemodeActive
                isOpen:         powerMenu.popupOpen
                onToggled: {
                    powerMenu.toggle()
                    if (powerMenu.popupOpen) {
                        appLauncher.close()
                        musicPopup.close()
                        infoPopup.close()
                        notifCenter.close()
                        controlCenter.close()
                    }
                }
            }

            // ── Systray expander ──────────────────────────────────────
            SidebarSystraySection {
                id: systraySection
                anchors.horizontalCenter: parent.horizontalCenter
                pillWidth:      root.pillWidth
                iconFontFamily: root.userConfig.iconFontFamily
                textFontFamily: root.userConfig.textFontFamily
                gamemodeActive: root.gamemodeActive
            }
        }
    }
}
