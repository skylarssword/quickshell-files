import QtQuick
import Quickshell
import Quickshell.Io
import "../shared"
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import IslandBackend

// ── Idle overlay ──────────────────────────────────────────────────────
// Standalone PanelWindow shown only while root.idleMode is true. Reads
// a handful of properties passed in from DynamicIslandWindow.qml and
// renders its own minimal chrome: clock/date top-left, live workspace
// dots + title top-center (pulled directly from Hyprland, same as
// WorkspaceBubble.qml), notification bell + gear top-right, and a
// media card bottom-left that only appears when something is playing
// and the media widget is enabled in the gear popup.
//
// Entire layer fades out whenever the active workspace on this monitor
// has ANY window open — floating or tiled, fullscreen or not.
//
// Text/icon color for elements sitting directly on the wallpaper (bell/
// gear, workspace label + dots) still adapts to wallpaper brightness,
// read directly from the UserConfig singleton. The clock/date cluster
// is a fixed white (Pixel lock-screen style) with its own drop shadows.
// Every white/adaptive-white text element (and the white workspace
// dots) carries a soft black drop shadow so it stays legible on bright
// wallpaper regions.
//
// Every Text {} in this file uses renderType: Text.NativeRendering to
// avoid the chromatic-aberration edge artifacts of the default
// distance-field renderer. All non-icon text uses the "Google Sans Flex
// Freeze" font family (only the Regular weight is installed, so no
// font.weight overrides are used anywhere — same plain-weight approach
// Pixie SDDM itself uses for most of its text).
//
// Lyrics: on every track change, lyricManager.fetch() runs immediately
// (this resets any stale state from the previous track right away, then
// resolves via its own cache-or-LRCLib fallback in the background). In
// parallel, MPRIS inline metadata is checked synchronously and — if it's
// LRC-formatted — wins immediately, since that resolves faster than any
// async cache read or network call. When synced lines are available the
// media card grows to show the previous/current/next line; otherwise it
// stays in its regular compact state.

PanelWindow {
    id: idleWindow

    // Shared "black drop shadow on white text" component. Inline
    // components must be declared inside the root object's body (not as
    // a sibling before it) — referenced via layer.effect on every
    // white/adaptive-white Text and on the white workspace dots.
    component TextShadow: DropShadow {
        color: "#000000"
        radius: 5
        samples: 11
        horizontalOffset: 0
        verticalOffset: 1
        spread: 0.15
        opacity: 0.6
    }

    // ── Wired in from DynamicIslandWindow.qml ───────────────────────
    property var hyprMonitor: null
    property string hyprMonitorName: hyprMonitor && hyprMonitor.name ? String(hyprMonitor.name) : ""

    property string timeText: "00:00:00"
    property string dateText: ""

    property int currentWorkspace: 1

    property var notificationHistory: []

    property var activePlayer: null
    property string currentTrack: ""
    property string currentArtist: ""
    property string currentArtUrl: ""
    property string inlineLyricsRaw: ""
    property var lyricManager: null

    property bool idleMode: false
    signal idleModeToggleRequested(bool enabled)
    signal workspaceDotClicked(int workspaceId)

readonly property string iconFontFamily: UserConfig.iconFontFamily

    // Load custom TTF directly into Qt engine — paths from IslandConfiguration
    FontLoader { id: flexFontRegular; source: IslandConfiguration.fontRegular }
    FontLoader { id: flexFontMedium;  source: IslandConfiguration.fontMedium }
    FontLoader { id: flexFontBold;    source: IslandConfiguration.fontBold }

    // Dynamically fallback to font loader's name or exact family string
    readonly property string flexRoundedFamily: flexFontRegular.name !== "" ? flexFontRegular.name : "Google Sans Flex Freeze"
    
    property bool gearPopupOpen: false
    property bool mediaWidgetEnabled: true
    property bool showLyricsEnabled: true
    readonly property bool mediaVisible: mediaWidgetEnabled && activePlayer !== null && currentTrack !== ""
    readonly property bool lyricsAvailable: showLyricsEnabled
        && lyricManager !== null
        && lyricManager.isSynced
        && lyricManager.lines
        && lyricManager.lines.length > 0

    // ── Live workspace list (same source pattern as WorkspaceBubble.qml) ──
    readonly property var monitorWorkspaces: {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return []
        const all = Hyprland.workspaces.values
        const filtered = idleWindow.hyprMonitorName
            ? all.filter(w => w.monitor && w.monitor.name === idleWindow.hyprMonitorName)
            : all.slice()
        return filtered.sort((a, b) => a.id - b.id)
    }

    // ── Any-window detection (fullscreen OR floating OR tiled) ──────────
    property bool anyWindowOpen: false

    Process {
        id: windowCountQuery
        property string _buf: ""
        command: ["bash", "-c", "hyprctl activeworkspace -j 2>/dev/null"]
        stdout: SplitParser { onRead: windowCountQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const raw = windowCountQuery._buf
                windowCountQuery._buf = ""
                try {
                    const parsed = JSON.parse(raw)
                    const count = Number(parsed.windows)
                    idleWindow.anyWindowOpen = !isNaN(count) && count > 0
                } catch (e) {
                    // leave last known value on parse failure
                }
            }
        }
    }

    Timer {
        interval: 700
        running: idleWindow.idleMode
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!windowCountQuery.running) windowCountQuery.running = true
    }

    // ── Wallpaper brightness sampling (still used by workspace/bell/gear) ──
    readonly property string wallpaperPath: UserConfig.wallpaperPath
    property real wallpaperBrightness: 50
    readonly property color adaptiveOnWallpaperColor: wallpaperBrightness > 55 ? "#1c1c1c" : "#ffffff"

    Process {
        id: wallpaperBrightnessQuery
        property string _buf: ""
        function run(path) {
            if (!path || path === "") return
            command = ["magick", path, "-resize", "1x1",
                "-format", "%[fx:(0.299*r+0.587*g+0.114*b)*100]", "info:"]
            _buf = ""
            running = true
        }
        stdout: SplitParser { onRead: wallpaperBrightnessQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const val = parseFloat(wallpaperBrightnessQuery._buf.trim())
                if (!isNaN(val)) idleWindow.wallpaperBrightness = val
                wallpaperBrightnessQuery._buf = ""
            }
        }
    }

    onWallpaperPathChanged: if (idleMode) wallpaperBrightnessQuery.run(wallpaperPath)
    onIdleModeChanged: if (idleMode) wallpaperBrightnessQuery.run(wallpaperPath)

    // ── Clock/date parsing ────────────────────────────────────────────
    // timeText arrives as e.g. "03:46 PM" (12h) or "15:46" / "03:46:12"
    // depending on upstream formatting — handle both gracefully.
    readonly property var _timeMatch: /^(\d{1,2}:\d{2})(?::\d{2})?\s*([AaPp][Mm])?$/.exec(idleWindow.timeText || "")
    readonly property string clockTimePart: idleWindow._timeMatch ? idleWindow._timeMatch[1] : idleWindow.timeText
    readonly property string clockMeridiemPart: (idleWindow._timeMatch && idleWindow._timeMatch[2]) ? idleWindow._timeMatch[2].toUpperCase() : ""

    // dateText arrives as e.g. "Sat, Jul 25"
    readonly property var _dateMatch: /^(\w+)\s*,\s*(\w+)\s*(\d+)$/.exec(idleWindow.dateText || "")
    readonly property string dateWeekdayPart: idleWindow._dateMatch ? idleWindow._dateMatch[1] : (idleWindow.dateText || "")
    readonly property string dateMonthPart: idleWindow._dateMatch ? idleWindow._dateMatch[2].toUpperCase() : ""
    readonly property string dateDayPart: idleWindow._dateMatch ? idleWindow._dateMatch[3] : ""

    // ── Lyrics: reset-and-refetch immediately on track change, with an
    // MPRIS-inline override attempted synchronously alongside it ────────
    function _looksSynced(raw) {
        return !!raw && /\[\d{2}:\d{2}/.test(raw)
    }

    function _tryMprisInline() {
        if (!idleWindow.lyricManager) return
        if (idleWindow._looksSynced(idleWindow.inlineLyricsRaw))
            idleWindow.lyricManager.applyManual(idleWindow.inlineLyricsRaw, idleWindow.currentArtist, idleWindow.currentTrack)
    }

    onCurrentTrackChanged: {
        if (!lyricManager || !showLyricsEnabled || currentTrack === "") return
        // fetch() resets stale lines/backendStatus immediately, then
        // resolves via its own cache-or-LRCLib fallback in the background.
        lyricManager.fetch(currentArtist, currentTrack, inlineLyricsRaw)
        // If MPRIS already has LRC-formatted metadata, this wins instantly
        // since it runs synchronously — before any async cache/network
        // result can land.
        _tryMprisInline()
    }

    // Some players populate metadata a beat after the track-changed signal
    // fires — catch that case reactively instead of on a fixed timer.
    onInlineLyricsRawChanged: _tryMprisInline()

    // ── Active lyric line tracking ───────────────────────────────────
    property int lyricActiveIndex: -1

    function _positionToMs(rawPos) {
        return rawPos < 10000 ? rawPos * 1000 : rawPos / 1000
    }

    function _formatTime(ms) {
        const totalSeconds = Math.max(0, Math.floor(ms / 1000))
        const m = Math.floor(totalSeconds / 60)
        const s = totalSeconds % 60
        return m + ":" + (s < 10 ? "0" + s : "" + s)
    }

    Timer {
        id: lyricPositionPoller
        interval: 300
        repeat: true
        running: idleWindow.mediaVisible && idleWindow.lyricsAvailable && idleWindow.activePlayer !== null
        onTriggered: {
            const p = idleWindow.activePlayer
            if (!p) return
            const posMs = idleWindow._positionToMs(Number(p.position) || 0)
            const lines = idleWindow.lyricManager.lines
            let idx = 0
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].time <= posMs) idx = i
                else break
            }
            idleWindow.lyricActiveIndex = idx
        }
    }

    readonly property string lyricPrevText: (lyricsAvailable && lyricActiveIndex > 0)
        ? (lyricManager.lines[lyricActiveIndex - 1].text || "") : ""
    readonly property string lyricCurrentText: (lyricsAvailable && lyricActiveIndex >= 0)
        ? (lyricManager.lines[lyricActiveIndex].text || "") : ""
    readonly property string lyricNextText: (lyricsAvailable && lyricActiveIndex >= 0 && lyricActiveIndex + 1 < lyricManager.lines.length)
        ? (lyricManager.lines[lyricActiveIndex + 1].text || "") : ""

    property real trackProgressLocal: 0
    property string timePlayedLocal: "0:00"
    property string timeTotalLocal: "0:00"

    Timer {
        id: progressPoller
        interval: 300
        repeat: true
        running: idleWindow.mediaVisible && idleWindow.activePlayer !== null && !seekArea.pressed
        onTriggered: {
            const p = idleWindow.activePlayer
            if (!p) return
            const posMs = idleWindow._positionToMs(Number(p.position) || 0)
            const lengthMs = idleWindow._positionToMs(Number(p.length) || 0)
            idleWindow.trackProgressLocal = lengthMs > 0 ? Math.max(0, Math.min(1, posMs / lengthMs)) : 0
            idleWindow.timePlayedLocal = idleWindow._formatTime(posMs)
            idleWindow.timeTotalLocal = lengthMs > 0 ? idleWindow._formatTime(lengthMs) : "0:00"
        }
    }

    function scrubToFraction(fraction) {
        const p = idleWindow.activePlayer
        if (!p || !p.canSeek) return
        const clamped = Math.max(0, Math.min(1, fraction))
        const lengthMs = idleWindow._positionToMs(Number(p.length) || 0)
        if (lengthMs <= 0) return
        const targetMs = clamped * lengthMs
        p.position = targetMs < 10000 * 1000 ? targetMs / 1000 : targetMs
        idleWindow.trackProgressLocal = clamped
    }

    // ── Transport helpers ────────────────────────────────────────────
    function togglePlayback() {
        const p = idleWindow.activePlayer
        if (!p || !p.canControl) return
        if (p.canTogglePlaying) { p.togglePlaying(); return }
        if (p.playbackState === MprisPlaybackState.Playing) {
            if (p.canPause) p.pause()
            return
        }
        if (p.canPlay) p.play()
    }

    function toggleShuffle() {
        const p = idleWindow.activePlayer
        if (!p) return
        const next = p.shuffle ? "false" : "true"
        idleShuffleProc.command = [
            "dbus-send", "--print-reply",
            "--dest=" + p.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties.Set",
            "string:org.mpris.MediaPlayer2.Player",
            "string:Shuffle",
            "variant:boolean:" + next
        ]
        idleShuffleProc.running = true
    }

    function cycleLoop() {
        const p = idleWindow.activePlayer
        if (!p) return
        const s = p.loopState
        let next
        if (s === MprisLoopState.None) next = MprisLoopState.Playlist
        else if (s === MprisLoopState.Playlist) next = MprisLoopState.Track
        else next = MprisLoopState.None
        p.loopState = next
    }

    Process { id: idleShuffleProc }

    readonly property bool contentVisible: idleMode && !anyWindowOpen

    // ── Window setup ─────────────────────────────────────────────────
    visible: idleMode
    color: StyleTokens.transparent
    anchors { top: true; left: true; right: true; bottom: true }
    exclusiveZone: 0
    aboveWindows: false
    focusable: gearPopupOpen
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: gearPopupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: Math.floor(workspaceCluster.x)
            y: Math.floor(workspaceCluster.y)
            width: Math.ceil(workspaceCluster.width)
            height: Math.ceil(workspaceCluster.height)
        }
        Region {
            intersection: Intersection.Combine
            x: Math.floor(topRightCluster.x)
            y: Math.floor(topRightCluster.y)
            width: Math.ceil(topRightCluster.width)
            height: Math.ceil(topRightCluster.height)
        }
        Region {
            intersection: Intersection.Combine
            x: Math.floor(gearPopup.x)
            y: Math.floor(gearPopup.y)
            width: idleWindow.gearPopupOpen ? Math.ceil(gearPopup.width) : 0
            height: idleWindow.gearPopupOpen ? Math.ceil(gearPopup.height) : 0
        }
        Region {
            intersection: Intersection.Combine
            x: Math.floor(mediaCard.x)
            y: Math.floor(mediaCard.y)
            width: idleWindow.mediaVisible ? Math.ceil(mediaCard.width) : 0
            height: idleWindow.mediaVisible ? Math.ceil(mediaCard.height) : 0
        }
    }

    Item {
        id: overlayRoot
        anchors.fill: parent
        opacity: idleWindow.contentVisible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }

        // ── Top-left: clock + date ───────────────────────────────────
        // Pixel-lockscreen-style single line: big time, small AM/PM
        // offset up-right of it, a thick rounded separator pill (with
        // its own drop shadow), then the date laid out horizontally
        // (MONTH DAY weekday) instead of stacked. Fixed white, left
        // aligned, every piece still carries the same soft drop shadow.
        Row {
            id: clockCluster
            x: 30
            y: 18
            spacing: 14

            // Time + AM/PM
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Text {
                    id: clockTimeText
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: idleWindow.clockTimePart
                    color: "white"
                    font.pixelSize: 34
                    font.family: idleWindow.flexRoundedFamily
                    font.letterSpacing: -0.6
                    layer.enabled: true
                    layer.effect: TextShadow {}
                    font.weight: Font.Bold
                }

                Text {
                    renderType: Text.NativeRendering
                    text: idleWindow.clockMeridiemPart
                    visible: text !== ""
                    anchors.top: clockTimeText.top
                    anchors.topMargin: 3
                    color: "white"
                    opacity: 1
                    font.pixelSize: 15
                    font.family: idleWindow.flexRoundedFamily
                    layer.enabled: true
                    layer.effect: TextShadow {}
                    font.weight: Font.Medium
                }
            }

            // Thick rounded separator pill
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 34
                radius: 2.5
                color: "white"
                opacity: 1
                layer.enabled: true
                layer.effect: TextShadow {}
            }

            // Date — horizontal: MONTH DAY weekday
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: idleWindow.dateMonthPart
                    color: "white"
                    font.pixelSize: 19
                    font.family: idleWindow.flexRoundedFamily
                    font.letterSpacing: 0.8
                    layer.enabled: true
                    layer.effect: TextShadow {}
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: idleWindow.dateDayPart
                    color: "white"
                    font.pixelSize: 22
                    font.family: idleWindow.flexRoundedFamily
                    font.letterSpacing: -0.2
                    layer.enabled: true
                    layer.effect: TextShadow {}
                    font.weight: Font.Medium
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    text: idleWindow.dateWeekdayPart
                    color: "white"
                    font.pixelSize: 19
                    font.family: idleWindow.flexRoundedFamily
                    layer.enabled: true
                    layer.effect: TextShadow {}
                }
            }
        }

        // ── Top-center: live workspace dots + title ──────────────────
        Column {
            id: workspaceCluster
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            spacing: 8

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Repeater {
                    model: idleWindow.monitorWorkspaces

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isActive: modelData.id === idleWindow.currentWorkspace

                        width: isActive ? 34 : 12
                        height: 12
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: idleWindow.adaptiveOnWallpaperColor
                        opacity: isActive ? 1 : 0.4

                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
                        Behavior on color { ColorAnimation { duration: 300 } }
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                        layer.enabled: true
                        layer.effect: TextShadow {}

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: idleWindow.workspaceDotClicked(modelData.id)
                        }
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Workspace " + idleWindow.currentWorkspace
                color: idleWindow.adaptiveOnWallpaperColor
                font.pixelSize: 15
                font.family: idleWindow.flexRoundedFamily
                Behavior on color { ColorAnimation { duration: 300 } }
                layer.enabled: true
                layer.effect: TextShadow {}
            }
        }

        // ── Top-right: notification bell + gear ──────────────────────
        Row {
            id: topRightCluster
            anchors.right: parent.right
            anchors.rightMargin: 30
            y: 18
            spacing: 12

            Item {
                width: 30
                height: 30
                visible: idleWindow.notificationHistory.length > 0

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "\uf0f3"
                    font.family: idleWindow.iconFontFamily
                    font.pixelSize: 16
                    color: idleWindow.adaptiveOnWallpaperColor
                    Behavior on color { ColorAnimation { duration: 300 } }
                    layer.enabled: true
                    layer.effect: TextShadow {}
                }

                Rectangle {
                    width: 16; height: 16; radius: 8
                    color: "#ff6b6b"
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -2
                    anchors.rightMargin: -2

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: idleWindow.notificationHistory.length > 9 ? "9+" : idleWindow.notificationHistory.length
                        color: "white"
                        font.pixelSize: 9
                        font.family: idleWindow.flexRoundedFamily
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }
                }
            }

            Item {
                id: gearButton
                width: 30
                height: 30

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "\uf013"
                    font.family: idleWindow.iconFontFamily
                    font.pixelSize: 14
                    color: idleWindow.adaptiveOnWallpaperColor
                    opacity: gearMouse.containsMouse || idleWindow.gearPopupOpen ? 1 : 0.75
                    scale: gearMouse.containsMouse || idleWindow.gearPopupOpen ? 1.1 : 1.0
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    layer.enabled: true
                    layer.effect: TextShadow {}
                }

                MouseArea {
                    id: gearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: idleWindow.gearPopupOpen = !idleWindow.gearPopupOpen
                }
            }
        }

        // ── Gear popup ────────────────────────────────────────────────
        Rectangle {
            id: gearPopup
            anchors.right: parent.right
            anchors.rightMargin: 30
            y: 58
            width: 230
            height: gearPopupOpen ? popupColumn.implicitHeight + 24 : 0
            radius: 18
            clip: true
            color: Qt.rgba(0.08, 0.08, 0.10, 0.94)
            border.width: 1
            border.color: Qt.rgba(1,1,1,0.16)
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Column {
                id: popupColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width - 42
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Focus Mode"
                        color: "white"
                        font.pixelSize: 12
                        font.family: idleWindow.flexRoundedFamily
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 20
                        radius: 10
                        color: idleWindow.idleMode ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: idleWindow.idleMode ? 16 : 2
                            color: StyleTokens.white
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                idleWindow.idleModeToggleRequested(!idleWindow.idleMode)
                                idleWindow.gearPopupOpen = false
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width - 42
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Media Widget"
                        color: "white"
                        font.pixelSize: 12
                        font.family: idleWindow.flexRoundedFamily
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 20
                        radius: 10
                        color: idleWindow.mediaWidgetEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: idleWindow.mediaWidgetEnabled ? 16 : 2
                            color: StyleTokens.white
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: idleWindow.mediaWidgetEnabled = !idleWindow.mediaWidgetEnabled
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width - 42
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Show Lyrics"
                        color: "white"
                        font.pixelSize: 12
                        font.family: idleWindow.flexRoundedFamily
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 20
                        radius: 10
                        color: idleWindow.showLyricsEnabled ? StyleTokens.success : StyleTokens.switchOff
                        Behavior on color { ColorAnimation { duration: StyleTokens.durationFast } }

                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 2
                            x: idleWindow.showLyricsEnabled ? 16 : 2
                            color: StyleTokens.white
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: idleWindow.showLyricsEnabled = !idleWindow.showLyricsEnabled
                        }
                    }
                }
            }
        }

        // ── Bottom-left: media card ──────────────────────────────────
        Rectangle {
            id: mediaCard
            x: 30
            y: parent.height - height - 30
            width: 320
            height: idleWindow.mediaVisible ? mediaContentColumn.implicitHeight + 32 : 0
            radius: 28
            clip: true
            color: Qt.rgba(0, 0, 0, 0.42)
            border.width: 1
            border.color: Qt.rgba(1,1,1,0.14)
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            Column {
                id: mediaContentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                // ── Art + track info (text wraps to 2 lines if needed) ──
                Row {
                    width: parent.width
                    spacing: 14

                    Item {
                        width: 60
                        height: 60

                        Image {
                            id: artImage
                            anchors.fill: parent
                            source: idleWindow.currentArtUrl
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(120, 120)
                            asynchronous: true
                            visible: false
                        }

                        Rectangle {
                            id: artMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: artImage
                            maskSource: artMask
                        }

                        // Circular hairline outline, shares the shell's border tokens
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: IslandMotion.surfaceBorderWidth
                            border.color: IslandMotion.surfaceBorderColor
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 74
                        spacing: 4

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: idleWindow.currentTrack
                            color: "white"
                            font.pixelSize: 15
                            font.family: idleWindow.flexRoundedFamily
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            layer.enabled: true
                            layer.effect: TextShadow {}
                        }

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: idleWindow.currentArtist
                            color: "white"
                            opacity: 0.7
                            font.pixelSize: 12
                            font.family: idleWindow.flexRoundedFamily
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            layer.enabled: true
                            layer.effect: TextShadow {}
                        }
                    }
                }

                // ── Seek bar / playhead ───────────────────────────────
                Item {
                    width: parent.width
                    height: 16

                    Text {
                        id: seekTimeL
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: idleWindow.timePlayedLocal
                        color: "white"
                        opacity: 0.6
                        font.pixelSize: 10
                        font.family: idleWindow.flexRoundedFamily
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }

                    Rectangle {
                        id: seekTrack
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: seekTimeL.right
                        anchors.right: seekTimeR.left
                        anchors.margins: 10
                        height: 4
                        radius: 2
                        color: Qt.rgba(1,1,1,0.18)

                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: "white"
                            width: parent.width * Math.max(0, Math.min(1, idleWindow.trackProgressLocal))
                            Behavior on width {
                                enabled: !seekArea.pressed
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }

                        // Playhead knob
                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: "white"
                            y: (parent.height - height) / 2
                            x: parent.width * Math.max(0, Math.min(1, idleWindow.trackProgressLocal)) - width / 2
                            scale: seekArea.pressed ? 1.3 : (seekArea.containsMouse ? 1.15 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                            Behavior on x {
                                enabled: !seekArea.pressed
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }

                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            preventStealing: true
                            onPositionChanged: (mouse) => {
                                if (!pressed) return
                                idleWindow.scrubToFraction(mouse.x / width)
                            }
                            onReleased: (mouse) => idleWindow.scrubToFraction(mouse.x / width)
                        }
                    }

                    Text {
                        id: seekTimeR
                        renderType: Text.NativeRendering
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: idleWindow.timeTotalLocal
                        color: "white"
                        opacity: 0.6
                        font.pixelSize: 10
                        font.family: idleWindow.flexRoundedFamily
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }
                }

                // ── Synced lyric block (prev / current / next) ───────
                Column {
                    width: parent.width
                    height: idleWindow.lyricsAvailable ? implicitHeight : 0
                    visible: height > 0
                    clip: true
                    spacing: 2

                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: idleWindow.lyricPrevText
                        color: "white"
                        opacity: 0.4
                        font.pixelSize: 11
                        font.family: idleWindow.flexRoundedFamily
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: idleWindow.lyricCurrentText
                        color: "white"
                        font.pixelSize: 14
                        font.family: idleWindow.flexRoundedFamily
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: idleWindow.lyricNextText
                        color: "white"
                        opacity: 0.4
                        font.pixelSize: 11
                        font.family: idleWindow.flexRoundedFamily
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        layer.enabled: true
                        layer.effect: TextShadow {}
                    }
                }

                // ── Transport row: shuffle, prev, play/pause, next, loop ──
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 26

                    // Shuffle
                    Item {
                        width: 20; height: 20
                        opacity: idleWindow.activePlayer && idleWindow.activePlayer.shuffle ? 1.0 : 0.35
                        scale: shuffleMouse.pressed ? 0.82 : (shuffleMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "white"
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath(); ctx.moveTo(2,6); ctx.lineTo(11,6); ctx.lineTo(18,14); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(14,12); ctx.lineTo(18,14); ctx.lineTo(14,16); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(2,14); ctx.lineTo(11,14); ctx.lineTo(18,6); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(14,4); ctx.lineTo(18,6); ctx.lineTo(14,8); ctx.stroke()
                            }
                        }
                        MouseArea {
                            id: shuffleMouse
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            onClicked: idleWindow.toggleShuffle()
                        }
                    }

                    // Previous track
                    Item {
                        width: 24; height: 24
                        scale: prevMouse.pressed ? 0.82 : (prevMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Canvas {
                            anchors.fill: parent
                            property color fillColor: prevMouse.pressed ? "#cccccc" : "white"
                            onFillColorChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = fillColor
                                ctx.strokeStyle = fillColor
                                ctx.lineJoin = "round"
                                ctx.lineWidth = 2
                                ctx.beginPath()
                                ctx.rect(3, 5, 3, 14)
                                ctx.moveTo(12, 5); ctx.lineTo(6, 12); ctx.lineTo(12, 19)
                                ctx.closePath()
                                ctx.moveTo(19, 5); ctx.lineTo(13, 12); ctx.lineTo(19, 19)
                                ctx.closePath()
                                ctx.fill(); ctx.stroke()
                            }
                        }
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            onClicked: if (idleWindow.activePlayer) idleWindow.activePlayer.previous()
                        }
                    }

                    // Play / pause
                    Item {
                        width: 26; height: 26
                        scale: playMouse.pressed ? 0.82 : (playMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            visible: idleWindow.activePlayer && idleWindow.activePlayer.playbackState === MprisPlaybackState.Playing
                            Rectangle { width: 4; height: 17; radius: 2; color: "white" }
                            Rectangle { width: 4; height: 17; radius: 2; color: "white" }
                        }
                        Canvas {
                            anchors.fill: parent
                            visible: !idleWindow.activePlayer || idleWindow.activePlayer.playbackState !== MprisPlaybackState.Playing
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = "white"
                                ctx.beginPath()
                                ctx.moveTo(6, 3); ctx.lineTo(21, 13); ctx.lineTo(6, 23)
                                ctx.closePath(); ctx.fill()
                            }
                        }
                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            onClicked: idleWindow.togglePlayback()
                        }
                    }

                    // Next track
                    Item {
                        width: 24; height: 24
                        scale: nextMouse.pressed ? 0.82 : (nextMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Canvas {
                            anchors.fill: parent
                            property color fillColor: nextMouse.pressed ? "#cccccc" : "white"
                            onFillColorChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = fillColor
                                ctx.strokeStyle = fillColor
                                ctx.lineJoin = "round"
                                ctx.lineWidth = 2
                                ctx.beginPath()
                                ctx.moveTo(5, 5); ctx.lineTo(11, 12); ctx.lineTo(5, 19)
                                ctx.closePath()
                                ctx.moveTo(12, 5); ctx.lineTo(18, 12); ctx.lineTo(12, 19)
                                ctx.closePath()
                                ctx.rect(19, 5, 3, 14)
                                ctx.fill(); ctx.stroke()
                            }
                        }
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            onClicked: if (idleWindow.activePlayer) idleWindow.activePlayer.next()
                        }
                    }

                    // Loop
                    Item {
                        width: 20; height: 20
                        opacity: idleWindow.activePlayer && idleWindow.activePlayer.loopState !== MprisLoopState.None ? 1.0 : 0.35
                        scale: loopMouse.pressed ? 0.82 : (loopMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Canvas {
                            id: idleLoopCanvas
                            anchors.fill: parent
                            property bool loopOne: idleWindow.activePlayer && idleWindow.activePlayer.loopState === MprisLoopState.Track
                            onLoopOneChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "white"
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath(); ctx.moveTo(4,8); ctx.lineTo(4,14); ctx.lineTo(15,14); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(17,12); ctx.lineTo(15,14); ctx.lineTo(17,17); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(17,12); ctx.lineTo(17,6); ctx.lineTo(5,6); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(4,8); ctx.lineTo(5,6); ctx.lineTo(4,3); ctx.stroke()
                                if (loopOne) {
                                    ctx.font = "bold 7px sans-serif"
                                    ctx.fillStyle = "white"
                                    ctx.textAlign = "center"
                                    ctx.fillText("1", 10, 13)
                                }
                            }
                        }
                        MouseArea {
                            id: loopMouse
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            onClicked: idleWindow.cycleLoop()
                        }
                    }
                }
            }
        }
    }
}
