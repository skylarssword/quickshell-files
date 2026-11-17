import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import IslandBackend
import "../shared"

Item {
    id: controlCenter

    property bool   showCondition:   false
    property string iconFontFamily:  ""
    property string textFontFamily:  ""
    property string heroFontFamily:  ""
    property int    sliderIntroDelay: 400
    property string currentTrack:   ""
    property string currentArtist:  ""

    property var lyricManager: null

    property var    activePlayer: null
    property string currentArtUrl: ""

    property bool expandedView: false
    signal expandedViewToggleRequested(bool expanded)

    property string lyricStatus: lyricManager ? lyricManager.backendStatus : "idle"
    property bool   hasSynced:   lyricManager ? lyricManager.isSynced : false

    // ── tabs: 0 = LRCLib search, 1 = local files, 2 = now playing (the expanded view) ──
    property int tab: 0
    onTabChanged: {
        const want = (tab === 2)
        if (want !== expandedView) expandedViewToggleRequested(want)
    }
    // size the island asks for (same for every tab)
    readonly property real preferredWidth:  640
    readonly property real preferredHeight: 340
    readonly property color accent: "white"
    readonly property bool hasLyrics: viewerMode !== "none"

    // files loaded from disk this session (re-loadable from the Local Files tab)
    property var recentFiles: []
    property string _pendingFilePath: ""

    readonly property real viewerHeight: 160
    readonly property real resultsPanelHeight: 160
    readonly property real fileSectionHeight: 90

    readonly property real expandedViewerHeight: 220

    readonly property real controlCenterExtraHeight: {
        if (expandedView && viewerMode !== "none") return expandedViewerHeight + 12
        if (viewerMode !== "none") return viewerHeight + 12
        if (lrclibPanelOpen)       return resultsPanelHeight + 12
        if (localFilePanelOpen)    return fileSectionHeight + 12
        return 0
    }
    readonly property real controlCenterMaximumExtraHeight: Math.max(expandedViewerHeight, viewerHeight, resultsPanelHeight, fileSectionHeight) + 12

    readonly property color panelColor:       StyleTokens.panel
    readonly property color moduleColor:      StyleTokens.module
    readonly property color moduleHover:      StyleTokens.moduleHover
    readonly property color textPrimary:      IslandMotion.textPrimary
    readonly property color textSecondary:    IslandMotion.textSecondary
    readonly property color cardAccent:       StyleTokens.accent
    readonly property color connectivityCard: StyleTokens.connectivityCard
    readonly property color connectivityCardHover: StyleTokens.connectivityCardHover

    property bool lrclibPanelOpen:   false
    property bool localFilePanelOpen: false

    property string lrclibStatusText: buildLrclibStatus()
    property string lrclibErrorText:  ""
    property var    lrclibResults:    []
    property bool   lrclibSearching:  false
    property int    selectedResultIndex: -1

    property string fileErrorText: ""
    property string fileInfoText:  ""

    property var _playersList: Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players
    property var _selfDetectedPlayer: {
        if (!_playersList || _playersList.length === 0) return null
        for (let i = 0; i < _playersList.length; i++) {
            if (_playersList[i].playbackState === MprisPlaybackState.Playing)
                return _playersList[i]
        }
        return _playersList.length > 0 ? _playersList[0] : null
    }
    readonly property var _effectivePlayer: activePlayer || _selfDetectedPlayer
    readonly property bool isPlayingNow: controlCenter._effectivePlayer !== null
        && controlCenter._effectivePlayer.playbackState === MprisPlaybackState.Playing

    property string viewerMode: "none"   
    property var    viewerLines: []      
    property string viewerPlainText: ""  
    property int    viewerActiveIndex: -1

    property real   trackProgressLocal: 0
    property string timePlayedLocal: "0:00"
    property string timeTotalLocal: "0:00"

    Timer {
        id: positionPoller
        interval: 300
        running: controlCenter.showCondition && controlCenter._effectivePlayer !== null
            && (controlCenter.viewerMode === "synced" || controlCenter.expandedView)
        repeat: true
        onTriggered: {
            const p = controlCenter._effectivePlayer
            if (!p) return

            const rawPos = Number(p.position) || 0
            const posMs = controlCenter._positionToMs(rawPos)
            const rawLen = Number(p.length) || 0
            const lengthMs = controlCenter._positionToMs(rawLen)

            if (controlCenter.expandedView) {
                controlCenter.trackProgressLocal = lengthMs > 0 ? Math.max(0, Math.min(1, posMs / lengthMs)) : 0
                controlCenter.timePlayedLocal = controlCenter._formatTime(posMs)
                controlCenter.timeTotalLocal = controlCenter._formatTime(lengthMs)
            }

            if (controlCenter.viewerMode !== "synced" || controlCenter.viewerLines.length === 0) return

            let idx = 0
            const lines = controlCenter.viewerLines
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].time <= posMs) idx = i
                else break
            }
            if (idx !== controlCenter.viewerActiveIndex)
                controlCenter.viewerActiveIndex = idx
        }
    }

    function _positionToMs(rawPos) {
        return rawPos < 10000 ? rawPos * 1000 : rawPos / 1000
    }
    function _msToPosition(ms) {
        return ms < 10000 * 1000 ? ms / 1000 : ms
    }
    function _formatTime(ms) {
        const totalSeconds = Math.max(0, Math.floor(ms / 1000))
        const m = Math.floor(totalSeconds / 60)
        const s = totalSeconds % 60
        return m + ":" + (s < 10 ? "0" + s : "" + s)
    }

    function seekBy(deltaMs) {
        const p = controlCenter._effectivePlayer
        if (!p || !p.canSeek) return
        const rawPos = Number(p.position) || 0
        const posMs = controlCenter._positionToMs(rawPos)
        const rawLen = Number(p.length) || 0
        const lengthMs = controlCenter._positionToMs(rawLen)

        let targetMs = posMs + deltaMs
        if (targetMs < 0) targetMs = 0
        if (lengthMs > 0 && targetMs > lengthMs) targetMs = lengthMs
        p.position = controlCenter._msToPosition(targetMs)
    }

    function _scrubToFraction(fraction) {
        const p = controlCenter._effectivePlayer
        if (!p || !p.canSeek) return
        const clamped = Math.max(0, Math.min(1, fraction))
        const rawLen = Number(p.length) || 0
        const lengthMs = controlCenter._positionToMs(rawLen)
        if (lengthMs <= 0) return
        p.position = controlCenter._msToPosition(clamped * lengthMs)
    }

    function togglePlayback() {
        const p = controlCenter._effectivePlayer
        if (!p || !p.canControl) return
        if (p.canTogglePlaying) { p.togglePlaying(); return }
        if (p.playbackState === MprisPlaybackState.Playing) {
            if (p.canPause) p.pause()
            return
        }
        if (p.canPlay) p.play()
    }

    function toggleShuffle() {
        const p = controlCenter._effectivePlayer
        if (!p) return
        const next = p.shuffle ? "false" : "true"
        shuffleProc.command = [
            "dbus-send", "--print-reply",
            "--dest=" + p.dbusName,
            "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties.Set",
            "string:org.mpris.MediaPlayer2.Player",
            "string:Shuffle",
            "variant:boolean:" + next
        ]
        shuffleProc.running = true
    }

    function cycleLoop() {
        const p = controlCenter._effectivePlayer
        if (!p) return
        const s = p.loopState
        let next
        if (s === MprisLoopState.None) next = MprisLoopState.Playlist
        else if (s === MprisLoopState.Playlist) next = MprisLoopState.Track
        else next = MprisLoopState.None
        p.loopState = next
    }

    Process { id: shuffleProc }
    Process { id: loopProc }

    function _parseLrcLocal(text) {
        const result = []
        const re = /\[(\d{2}):(\d{2})[\.:](\d{2,3})\](.*)/
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            let rest = lines[i].trim()
            const times = []
            let m
            while ((m = re.exec(rest)) !== null) {
                const frac = m[3]
                const ms = parseInt(m[1]) * 60000
                         + parseInt(m[2]) * 1000
                         + (frac.length === 2 ? parseInt(frac) * 10 : parseInt(frac))
                times.push(ms)
                rest = m[4]
            }
            if (times.length === 0) continue
            const lineText = rest.trim()
            for (let t = 0; t < times.length; t++)
                result.push({ time: times[t], text: lineText })
        }
        result.sort(function(a, b) { return a.time - b.time })
        return result
    }

    function setViewerContent(text) {
        const parsed = _parseLrcLocal(text)
        viewerActiveIndex = -1
        if (parsed.length > 0) {
            viewerMode = "synced"
            viewerLines = parsed
            viewerPlainText = ""
        } else {
            viewerMode = "plain"
            viewerLines = []
            viewerPlainText = text
        }
    }

    anchors.fill: parent
    // No scale or fade: appear/disappear instantly with the capsule morph.
    // Warm-up: 1% opacity for 1.2s at startup so Qt builds textures early.
    property bool warmedUp: false
    opacity: showCondition ? 1 : (warmedUp ? 0 : 0.01)
    visible: true
    enabled: showCondition

    Timer {
        id: lccWarmUpTimer
        interval: 1200
        running: true
        repeat: false
        onTriggered: controlCenter.warmedUp = true
    }

    function buildLrclibStatus() {
        if (!currentTrack || currentTrack === "") return "No track playing"
        switch (lyricStatus) {
        case "ready":   return hasSynced ? "Synced" : "Plain"
        case "missing": return "No lyrics found"
        case "loading": return "Searching..."
        case "error":   return "Error fetching lyrics"
        default:        return "Idle"
        }
    }

    onLyricStatusChanged:  lrclibStatusText = buildLrclibStatus()
    onHasSyncedChanged:    lrclibStatusText = buildLrclibStatus()
    onCurrentTrackChanged: lrclibStatusText = buildLrclibStatus()

    function _restoreFromLyricManager() {
        if (!lyricManager) return
        if (lyricManager.isSynced && lyricManager.lines && lyricManager.lines.length > 0) {
            viewerMode = "synced"
            viewerLines = lyricManager.lines
            viewerPlainText = ""
            fileInfoText = "Lyrics loaded for this track"
        } else if (lyricManager.backendStatus === "ready" && !lyricManager.isSynced && lyricManager.fullPlainText !== "") {
            viewerMode = "plain"
            viewerLines = []
            viewerPlainText = lyricManager.fullPlainText
            fileInfoText = "Lyrics loaded for this track"
        } else {
            viewerMode = "none"
            viewerLines = []
            viewerPlainText = ""
            fileInfoText = ""
        }
    }

    Connections {
        target: lyricManager
        function onBackendStatusChanged() { controlCenter._restoreFromLyricManager() }
    }

    Component.onCompleted: {
        tab = expandedView ? 2 : 0
        if (!lyricManager) return
        if (currentArtist !== "" && currentTrack !== "") {
            lyricManager.fetch(currentArtist, currentTrack, "")
        }
        _restoreFromLyricManager()
    }

    function searchLrcLib() {
        if (!currentTrack || currentTrack === "") return
        lrclibResults    = []
        lrclibSearching  = true
        lrclibErrorText  = ""
        selectedResultIndex = -1

        const url = "https://lrclib.net/api/search"
                  + "?track_name="  + encodeURIComponent(currentTrack)
                  + "&artist_name=" + encodeURIComponent(currentArtist)
        lrclibProc.command = [
            "curl", "-s", "-f", "--max-time", "15",
            "-H", "Lrclib-Client: tide-island/1.0 (quickshell)",
            url
        ]
        lrclibProc.running = true
    }

    function applyResult(index) {
        const result = lrclibResults[index]
        if (!result) return
        selectedResultIndex = index

        if (result.syncedLyrics && result.syncedLyrics.trim() !== "") {
            setViewerContent(result.syncedLyrics)
            if (lyricManager) lyricManager.applyManual(result.syncedLyrics, currentArtist, currentTrack)
        } else if (result.plainLyrics && result.plainLyrics.trim() !== "") {
            setViewerContent(result.plainLyrics)
            if (lyricManager) lyricManager.applyManual(result.plainLyrics, currentArtist, currentTrack)
        }
        lrclibStatusText = buildLrclibStatus()
        lrclibPanelOpen = false
    }

    Process {
        id: lrclibProc
        stdout: StdioCollector {
            id: lrclibOut
        }
        onExited: (exitCode, exitStatus) => {
            controlCenter.lrclibSearching = false
            if (exitCode !== 0) {
                controlCenter.lrclibErrorText = "Search failed (curl error " + exitCode + ")"
                return
            }
            try {
                const data = JSON.parse(lrclibOut.text)
                if (!Array.isArray(data) || data.length === 0) {
                    controlCenter.lrclibErrorText = "No results found on LRCLib"
                    return
                }
                controlCenter.lrclibResults = data
                        .filter(function(item) {
                            const hasSync  = item.syncedLyrics && item.syncedLyrics.trim() !== ""
                            const hasPlain = item.plainLyrics  && item.plainLyrics.trim()  !== ""
                            return hasSync || hasPlain
                        })
                        .slice(0, 8)
                        .map(function(item) {
                            return {
                                id:           item.id,
                                title:        item.trackName   || "",
                                artist:       item.artistName  || "",
                                album:        item.albumName   || "",
                                duration:     item.duration    || 0,
                                hasSynced:    !!(item.syncedLyrics && item.syncedLyrics.trim() !== ""),
                                syncedLyrics: item.syncedLyrics || "",
                                plainLyrics:  item.plainLyrics  || ""
                            }
                        })
            } catch(e) {
                controlCenter.lrclibErrorText = "Failed to parse results"
            }
        }
    }

    function pickLocalFile() {
        fileErrorText = ""
        fileInfoText  = ""
        filePickerProc.command = [
            "zenity", "--file-selection",
            "--title=Select Lyrics File",
            "--file-filter=Lyrics files (*.lrc *.txt) | *.lrc *.txt",
            "--file-filter=All files | *"
        ]
        filePickerProc.running = true
    }

    Process {
        id: filePickerProc
        stdout: StdioCollector {
            id: filePickerOut
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return
            const path = filePickerOut.text.trim()
            if (path === "") return

            controlCenter.viewerMode = "none"
            controlCenter.viewerLines = []
            controlCenter.viewerPlainText = ""
            controlCenter.fileInfoText = ""
            controlCenter.fileErrorText = ""

            controlCenter.loadLocalPath(path)
        }
    }

    function loadLocalPath(path) {
        fileErrorText = ""
        fileInfoText  = ""
        _pendingFilePath = path
        fileCatProc.command = ["cat", path]
        fileCatProc.running = true
    }

    function _rememberFile(path, text) {
        const name = path.split("/").pop()
        const size = text.length >= 1024 ? (text.length / 1024).toFixed(1) + " KB" : text.length + " B"
        const rest = recentFiles.filter(function(f) { return f.path !== path })
        recentFiles = [{ name: name, path: path, size: size }].concat(rest).slice(0, 8)
    }

    Process {
        id: fileCatProc
        stdout: StdioCollector { id: fileCatOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                controlCenter.fileErrorText = "Could not read file"
                return
            }
            const text = fileCatOut.text
            if (!text || text.trim() === "") {
                controlCenter.fileErrorText = "File is empty"
                return
            }
            controlCenter.setViewerContent(text)
            controlCenter._rememberFile(controlCenter._pendingFilePath, text)
            if (controlCenter.lyricManager)
                controlCenter.lyricManager.applyManual(text, controlCenter.currentArtist, controlCenter.currentTrack)
            controlCenter.fileInfoText  = "Lyrics loaded from file"
            controlCenter.fileErrorText = ""
            controlCenter.lrclibStatusText = controlCenter.buildLrclibStatus()
            controlCenter.localFilePanelOpen = false
        }
    }


    // ═════════════════════════════════════════════════════════════════════════
    //  UI
    // ═════════════════════════════════════════════════════════════════════════

    readonly property var npLines: {
        if (viewerMode === "synced" && viewerLines.length > 0) {
            const a = Math.max(0, viewerActiveIndex)
            const out = []
            for (let i = a; i < Math.min(a + 4, viewerLines.length); i++)
                out.push(viewerLines[i].text || "♪")
            return out
        }
        if (viewerMode === "plain") {
            return viewerPlainText.split("\n").filter(function(l) { return l.trim() !== "" }).slice(0, 4)
        }
        return ["No lyrics loaded"]
    }

    function clearLyrics() {
        if (lyricManager) lyricManager.clearCache()
        viewerMode = "none"
        viewerLines = []
        viewerPlainText = ""
        fileInfoText = ""
        lrclibResults = []
        lrclibErrorText = ""
        lrclibStatusText = buildLrclibStatus()
    }

    // ── header ──────────────────────────────────────────────────────────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56

        LyricIcon { id: spark; kind: "sparkle"; sz: 22; col: controlCenter.accent
              anchors.left: parent.left; anchors.leftMargin: 24; anchors.verticalCenter: parent.verticalCenter }
        Text {
            renderType: Text.NativeRendering
            anchors.left: spark.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
            text: "Lyric Control Center"
            color: IslandMotion.textPrimary
            font.family: controlCenter.textFontFamily; font.pixelSize: 17; font.weight: Font.DemiBold
        }

        Item {
            id: clearBtn
            anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26
            LyricIcon {
                id: trashIcon
                anchors.centerIn: parent; kind: "trash"; sz: 22
                col: clearMouse.pressed ? Qt.rgba(1, 1, 1, 0.5) : (clearMouse.containsMouse ? StyleTokens.error : Qt.rgba(1, 1, 1, 0.85))
                scale: clearMouse.pressed ? 0.78 : 1.0
                Behavior on scale { NumberAnimation { duration: clearMouse.pressed ? 90 : 340; easing.type: clearMouse.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } }
                // confirmation: a quick wiggle that springs back to upright
                SequentialAnimation {
                    id: trashWiggle
                    NumberAnimation { target: trashIcon; property: "rotation"; to: -18; duration: 70; easing.type: Easing.OutQuad }
                    NumberAnimation { target: trashIcon; property: "rotation"; to: 14;  duration: 90; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: trashIcon; property: "rotation"; to: -8;  duration: 80; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: trashIcon; property: "rotation"; to: 0;   duration: 260; easing.type: Easing.OutElastic; easing.amplitude: 1.2 }
                }
            }
            MouseArea { id: clearMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { trashWiggle.restart(); controlCenter.clearLyrics() } }
        }
        Rectangle {
            anchors.right: clearBtn.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
            height: 28; radius: 14
            width: pillRow.width + 24
            visible: controlCenter.hasLyrics
            color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.40)
            Row {
                id: pillRow
                anchors.centerIn: parent; spacing: 7
                Text { renderType: Text.NativeRendering; anchors.verticalCenter: parent.verticalCenter
                       text: controlCenter.viewerMode === "synced" ? "Synced" : "Plain"
                       color: controlCenter.accent
                       font.family: controlCenter.textFontFamily; font.pixelSize: 13; font.weight: Font.Medium }
                Rectangle { width: 9; height: 9; radius: 4.5; color: controlCenter.accent; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ── tab rail ────────────────────────────────────────────────────────────
    Item {
        id: rail
        anchors { left: parent.left; top: header.bottom; bottom: parent.bottom; bottomMargin: 16 }
        width: 70

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Repeater {
                model: ["note", "folder", "star"]
                delegate: Item {
                    id: tb
                    required property int index
                    required property string modelData
                    readonly property bool active: controlCenter.tab === index
                    width: 48; height: 48
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: tbm.pressed ? Qt.rgba(1, 1, 1, 0.24)
                             : (tb.active ? Qt.rgba(1, 1, 1, 0.16) : (tbm.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"))
                        border.width: tb.active ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.45)
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    LyricIcon { anchors.centerIn: parent; kind: tb.modelData; sz: 26
                          col: tb.active ? controlCenter.accent : Qt.rgba(1, 1, 1, 0.6)
                          scale: tbm.pressed ? 0.8 : 1.0
                          Behavior on scale { NumberAnimation { duration: tbm.pressed ? 90 : 340; easing.type: tbm.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } } }
                    MouseArea { id: tbm; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: controlCenter.tab = tb.index }
                }
            }
        }
    }

    // ── content panel ───────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors { left: rail.right; right: parent.right; rightMargin: 18; top: header.bottom; bottom: parent.bottom; bottomMargin: 16 }
        radius: 22
        color: "transparent"      // no gray body behind the tab content
        clip: true

        // ───── tab 0: LRCLib search / nothing found ─────
        Item {
            anchors.fill: parent; anchors.margins: 14
            visible: controlCenter.tab === 0

            readonly property bool emptyState: !controlCenter.hasLyrics && controlCenter.lrclibResults.length === 0
                                               && !controlCenter.lrclibSearching && controlCenter.lrclibErrorText === ""

            // search view
            Item {
                anchors.fill: parent
                visible: !parent.emptyState

                Rectangle {
                    id: searchBox
                    width: parent.width; height: 42; radius: 21
                    color: searchMouse.pressed ? Qt.rgba(1, 1, 1, 0.16) : (searchMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.07))
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    LyricIcon { id: sIco; kind: "search"; sz: 20; col: Qt.rgba(1, 1, 1, 0.75)
                          scale: searchMouse.pressed ? 0.8 : 1.0
                          Behavior on scale { NumberAnimation { duration: searchMouse.pressed ? 90 : 340; easing.type: searchMouse.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } }

                          anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: sIco.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: controlCenter.currentTrack !== ""
                              ? controlCenter.currentTrack + (controlCenter.currentArtist !== "" ? " — " + controlCenter.currentArtist : "")
                              : "Search on LRCLib…"
                        color: IslandMotion.textSecondary
                        font.family: controlCenter.textFontFamily; font.pixelSize: 15
                    }
                    MouseArea { id: searchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: controlCenter.searchLrcLib() }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors { top: searchBox.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                    visible: controlCenter.lrclibSearching || controlCenter.lrclibErrorText !== "" || controlCenter.lrclibResults.length === 0
                    text: controlCenter.lrclibSearching ? "Searching…"
                          : (controlCenter.lrclibErrorText !== "" ? controlCenter.lrclibErrorText : "Tap the field to search LRCLib")
                    color: controlCenter.lrclibErrorText !== "" ? StyleTokens.error : IslandMotion.textSecondary
                    font.family: controlCenter.textFontFamily; font.pixelSize: 14
                }

                ListView {
                    anchors { top: searchBox.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true; interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: controlCenter.lrclibResults
                    delegate: Item {
                        width: ListView.view.width; height: 60
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                        Rectangle {
                            id: badge; width: 48; height: 26; radius: 13
                            color: modelData.hasSynced ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.18)
                            anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            Text { renderType: Text.NativeRendering; anchors.centerIn: parent
                                   text: modelData.hasSynced ? "LRC" : "TXT"; color: modelData.hasSynced ? "#111" : "white"
                                   font.family: controlCenter.textFontFamily; font.pixelSize: 12; font.weight: Font.Bold }
                        }
                        Column {
                            anchors.left: badge.right; anchors.leftMargin: 14; anchors.right: dur.left; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { renderType: Text.NativeRendering; width: parent.width; elide: Text.ElideRight
                                   text: modelData.title; color: IslandMotion.textPrimary
                                   font.family: controlCenter.textFontFamily; font.pixelSize: 16; font.weight: Font.Medium }
                            Text { renderType: Text.NativeRendering; width: parent.width; elide: Text.ElideRight
                                   text: modelData.artist + (modelData.album !== "" ? " · " + modelData.album : "")
                                   color: IslandMotion.textSecondary; font.family: controlCenter.textFontFamily; font.pixelSize: 13 }
                        }
                        Text { id: dur; renderType: Text.NativeRendering
                               anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                               text: controlCenter._formatTime((modelData.duration || 0) * 1000)
                               color: IslandMotion.textSecondary; font.family: controlCenter.textFontFamily; font.pixelSize: 14 }
                        Rectangle { anchors.fill: parent; radius: 12; color: Qt.rgba(1, 1, 1, rowMouse.pressed ? 0.12 : (rowMouse.containsMouse ? 0.06 : 0)); z: -1 }
                        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: controlCenter.applyResult(index) }
                    }
                }
            }

            // nothing found / nothing loaded
            Column {
                anchors.centerIn: parent
                visible: parent.emptyState
                spacing: 8
                LyricIcon { anchors.horizontalCenter: parent.horizontalCenter; kind: "filequestion"; sz: 54; col: IslandMotion.textPrimary }
                Item { width: 1; height: 4 }
                Text { renderType: Text.NativeRendering; anchors.horizontalCenter: parent.horizontalCenter
                       text: controlCenter.lyricStatus === "loading" ? "Looking for lyrics…" : "No lyrics found"
                       color: IslandMotion.textPrimary
                       font.family: controlCenter.textFontFamily; font.pixelSize: 24; font.weight: Font.DemiBold }
                Text { renderType: Text.NativeRendering; anchors.horizontalCenter: parent.horizontalCenter
                       text: controlCenter.currentTrack === "" ? "Nothing is playing." : "We couldn't find lyrics for this track."
                       color: IslandMotion.textSecondary; font.family: controlCenter.textFontFamily; font.pixelSize: 15 }
                Item { width: 1; height: 6 }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 12
                    Rectangle {
                        width: 176; height: 44; radius: 22
                        color: nlSearch.pressed ? Qt.rgba(1, 1, 1, 0.26) : (nlSearch.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.14))
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.40)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        opacity: controlCenter.currentTrack !== "" ? 1 : 0.4
                        Row { anchors.centerIn: parent; spacing: 9
                            scale: nlSearch.pressed ? 0.92 : 1.0
                            Behavior on scale { NumberAnimation { duration: nlSearch.pressed ? 90 : 340; easing.type: nlSearch.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } }
                            LyricIcon { kind: "search"; sz: 20; col: controlCenter.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { renderType: Text.NativeRendering; anchors.verticalCenter: parent.verticalCenter
                                   text: "Search on LRCLib"; color: IslandMotion.textPrimary
                                   font.family: controlCenter.textFontFamily; font.pixelSize: 15; font.weight: Font.Medium } }
                        MouseArea { id: nlSearch; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: controlCenter.searchLrcLib() }
                    }
                    Rectangle {
                        width: 168; height: 44; radius: 22
                        color: nlFile.pressed ? Qt.rgba(1, 1, 1, 0.18) : (nlFile.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07))
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row { anchors.centerIn: parent; spacing: 9
                            scale: nlFile.pressed ? 0.92 : 1.0
                            Behavior on scale { NumberAnimation { duration: nlFile.pressed ? 90 : 340; easing.type: nlFile.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } }
                            LyricIcon { kind: "folder"; sz: 20; col: IslandMotion.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                            Text { renderType: Text.NativeRendering; anchors.verticalCenter: parent.verticalCenter
                                   text: "Load a local file"; color: IslandMotion.textPrimary
                                   font.family: controlCenter.textFontFamily; font.pixelSize: 15; font.weight: Font.Medium } }
                        MouseArea { id: nlFile; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: controlCenter.tab = 1 }
                    }
                }
            }
        }

        // ───── tab 1: local files ─────
        Item {
            anchors.fill: parent; anchors.margins: 14
            visible: controlCenter.tab === 1

            Rectangle {
                id: fileHead
                width: parent.width; height: 42; radius: 21
                color: Qt.rgba(1, 1, 1, 0.07); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                LyricIcon { id: fIco; kind: "folder"; sz: 22; col: IslandMotion.textPrimary
                      anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter }
                Text { renderType: Text.NativeRendering
                       anchors.left: fIco.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                       text: "Local Files"; color: IslandMotion.textPrimary
                       font.family: controlCenter.textFontFamily; font.pixelSize: 16; font.weight: Font.Medium }
            }

            Text {
                renderType: Text.NativeRendering
                anchors { top: fileHead.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                visible: controlCenter.recentFiles.length === 0
                text: "Files you load show up here"
                color: IslandMotion.textSecondary; font.family: controlCenter.textFontFamily; font.pixelSize: 14
            }

            ListView {
                anchors { top: fileHead.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: fileStatus.top; bottomMargin: 6 }
                clip: true; interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: controlCenter.recentFiles
                delegate: Item {
                    width: ListView.view.width; height: 46
                    LyricIcon { id: dIco; kind: "doc"; sz: 28; col: IslandMotion.textPrimary
                          anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter }
                    Text { renderType: Text.NativeRendering
                           anchors.left: dIco.right; anchors.leftMargin: 14; anchors.right: sz.left; anchors.rightMargin: 10
                           anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                           text: modelData.name; color: IslandMotion.textPrimary
                           font.family: controlCenter.textFontFamily; font.pixelSize: 16 }
                    Text { id: sz; renderType: Text.NativeRendering
                           anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                           text: modelData.size; color: IslandMotion.textSecondary
                           font.family: controlCenter.textFontFamily; font.pixelSize: 14 }
                    Rectangle { anchors.fill: parent; radius: 12; color: Qt.rgba(1, 1, 1, fileRow.pressed ? 0.12 : (fileRow.containsMouse ? 0.06 : 0)); z: -1 }
                    MouseArea { id: fileRow; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: controlCenter.loadLocalPath(modelData.path) }
                }
            }

            Text {
                id: fileStatus
                renderType: Text.NativeRendering
                anchors { bottom: browse.top; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                height: 18
                text: controlCenter.fileErrorText !== "" ? controlCenter.fileErrorText : controlCenter.fileInfoText
                color: controlCenter.fileErrorText !== "" ? StyleTokens.error : IslandMotion.textSecondary
                font.family: controlCenter.textFontFamily; font.pixelSize: 13
            }

            Rectangle {
                id: browse
                anchors.bottom: parent.bottom; width: parent.width; height: 44; radius: 22
                color: browseMouse.pressed ? Qt.rgba(1, 1, 1, 0.20) : (browseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07))
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                Behavior on color { ColorAnimation { duration: 120 } }
                Row { anchors.centerIn: parent; spacing: 10
                    scale: browseMouse.pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: browseMouse.pressed ? 90 : 340; easing.type: browseMouse.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 3.2 } }
                    LyricIcon { kind: "folder"; sz: 20; col: IslandMotion.textPrimary; anchors.verticalCenter: parent.verticalCenter }
                    Text { renderType: Text.NativeRendering; anchors.verticalCenter: parent.verticalCenter
                           text: "Browse for .lrc files…"; color: IslandMotion.textPrimary
                           font.family: controlCenter.textFontFamily; font.pixelSize: 15; font.weight: Font.Medium } }
                MouseArea { id: browseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: controlCenter.pickLocalFile() }
            }
        }

        // ───── tab 2: now playing (expanded view) ─────
        Item {
            anchors.fill: parent; anchors.margins: 16
            visible: controlCenter.tab === 2

            Item {
                id: np
                width: parent.width; height: 140

                // round spinning disc (dims when paused, pulsing ring while playing)
                Item {
                    id: disc
                    width: 132; height: 132
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    property real angle: 0

                    RotationAnimation on angle {
                        from: 0; to: 360; duration: 9000
                        direction: RotationAnimation.Clockwise
                        loops: Animation.Infinite
                        running: controlCenter.isPlayingNow && controlCenter.tab === 2 && controlCenter.showCondition
                    }

                    Item {
                        id: discSrc
                        anchors.fill: parent
                        visible: false
                        Image {
                            id: discImg
                            anchors.fill: parent
                            source: controlCenter.currentArtUrl
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(400, 400)
                            smooth: true; mipmap: true
                            rotation: disc.angle
                        }
                    }
                    Rectangle { id: discMask; anchors.fill: parent; radius: width / 2; visible: false }
                    OpacityMask {
                        anchors.fill: parent; source: discSrc; maskSource: discMask
                        visible: controlCenter.currentArtUrl !== "" && discImg.status === Image.Ready
                    }
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.07)
                        visible: controlCenter.currentArtUrl === "" || discImg.status !== Image.Ready
                        LyricIcon { anchors.centerIn: parent; kind: "note"; sz: 48; col: Qt.rgba(1, 1, 1, 0.5) }
                    }
                    // dim when paused
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: "black"
                        opacity: controlCenter.isPlayingNow ? 0 : 0.40
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                    // ring
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: "transparent"
                        border.width: controlCenter.isPlayingNow ? 2 : IslandMotion.surfaceBorderWidth
                        border.color: controlCenter.isPlayingNow ? Qt.rgba(1, 1, 1, 0.55) : IslandMotion.surfaceBorderColor
                        SequentialAnimation on border.color {
                            running: controlCenter.isPlayingNow && controlCenter.tab === 2 && controlCenter.showCondition
                            loops: Animation.Infinite
                            ColorAnimation { to: Qt.rgba(1, 1, 1, 0.85); duration: 700; easing.type: Easing.InOutSine }
                            ColorAnimation { to: Qt.rgba(1, 1, 1, 0.20); duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                }

                // title / artist (scroll when too long) + clickable, scrollable lyrics
                Item {
                    id: npText
                    anchors { left: disc.right; leftMargin: 22; right: parent.right; top: parent.top; bottom: parent.bottom }

                    LyricMarqueeText {
                        id: npTitle
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        active: controlCenter.tab === 2 && controlCenter.showCondition
                        text: controlCenter.currentTrack !== "" ? controlCenter.currentTrack : "No track"
                        color: IslandMotion.textPrimary
                        family: controlCenter.textFontFamily
                        pixelSize: 21; weight: Font.DemiBold
                    }
                    LyricMarqueeText {
                        id: npArtist
                        anchors { left: parent.left; right: parent.right; top: npTitle.bottom; topMargin: 2 }
                        active: controlCenter.tab === 2 && controlCenter.showCondition
                        text: controlCenter.currentArtist
                        color: IslandMotion.textSecondary
                        family: controlCenter.textFontFamily
                        pixelSize: 14; weight: Font.Medium
                    }

                    ListView {
                        id: npLyricList
                        anchors { left: parent.left; right: parent.right; top: npArtist.bottom; topMargin: 8; bottom: parent.bottom }
                        visible: controlCenter.viewerMode === "synced"
                        clip: true
                        model: controlCenter.viewerLines
                        boundsBehavior: Flickable.StopAtBounds
                        currentIndex: Math.max(0, controlCenter.viewerActiveIndex)
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: height / 2 - 14
                        preferredHighlightEnd: height / 2 + 14
                        highlightMoveDuration: 260
                        highlight: Item {}
                        delegate: Text {
                            id: lineText
                            renderType: Text.NativeRendering
                            width: npLyricList.width
                            readonly property bool active: index === controlCenter.viewerActiveIndex
                            text: modelData.text || ". . ."
                            color: lineMouse.containsMouse ? IslandMotion.textPrimary
                                 : (active ? IslandMotion.textPrimary : IslandMotion.textSecondary)
                            font.family: controlCenter.textFontFamily
                            font.pixelSize: active ? 18 : 14
                            font.weight: active ? Font.Bold : Font.Normal
                            wrapMode: Text.WordWrap
                            topPadding: 3; bottomPadding: 3
                            opacity: lineMouse.pressed ? 0.55 : 1.0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                            MouseArea {
                                id: lineMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const p = controlCenter._effectivePlayer
                                    if (!p || !modelData) return
                                    p.position = controlCenter._msToPosition(modelData.time)
                                    controlCenter.viewerActiveIndex = index
                                }
                            }
                        }
                    }

                    Flickable {
                        anchors { left: parent.left; right: parent.right; top: npArtist.bottom; topMargin: 8; bottom: parent.bottom }
                        visible: controlCenter.viewerMode === "plain"
                        contentHeight: npPlain.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: npPlain
                            renderType: Text.NativeRendering
                            width: parent.width
                            text: controlCenter.viewerPlainText
                            color: IslandMotion.textSecondary
                            font.family: controlCenter.textFontFamily; font.pixelSize: 14
                            wrapMode: Text.WordWrap
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors { left: parent.left; top: npArtist.bottom; topMargin: 12 }
                        visible: controlCenter.viewerMode === "none"
                        text: "No lyrics loaded"
                        color: IslandMotion.textFaint
                        font.family: controlCenter.textFontFamily; font.pixelSize: 14
                    }
                }
            }

            Item {
                id: prog
                anchors { top: np.bottom; topMargin: 12; left: parent.left; right: parent.right }
                height: 20
                Text { id: tl; renderType: Text.NativeRendering
                       anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                       text: controlCenter.timePlayedLocal; color: IslandMotion.textSecondary
                       font.family: controlCenter.textFontFamily; font.pixelSize: 13; font.weight: Font.Medium }
                Text { id: tr; renderType: Text.NativeRendering
                       anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                       text: controlCenter.timeTotalLocal; color: IslandMotion.textSecondary
                       font.family: controlCenter.textFontFamily; font.pixelSize: 13; font.weight: Font.Medium }
                Rectangle {
                    id: track
                    anchors.left: tl.right; anchors.right: tr.left; anchors.leftMargin: 12; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 5; radius: 3
                    color: Qt.rgba(1, 1, 1, 0.18)
                    Rectangle {
                        height: parent.height; radius: parent.radius; color: "white"
                        width: track.width * Math.max(0, Math.min(1, controlCenter.trackProgressLocal))
                        Behavior on width { enabled: !scrub.pressed; NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: scrub
                        anchors.fill: parent; anchors.margins: -10
                        preventStealing: true
                        // same wiring as the sidebar player: click = seek
                        onClicked: (mouse) => controlCenter._scrubToFraction((mouse.x - 10) / track.width)
                    }
                }
            }

            Item {
                anchors { top: prog.bottom; topMargin: 8; left: parent.left; right: parent.right }
                height: 36
                Row {
                    anchors.centerIn: parent
                    spacing: 24

                    LyricTransportButton {
                        iconOpacity: controlCenter._effectivePlayer && controlCenter._effectivePlayer.shuffle ? 1.0 : 0.45
                        onActivated: controlCenter.toggleShuffle()
                        LyricIcon { anchors.centerIn: parent; kind: "shuffle"; sz: 28 }
                    }
                    LyricTransportButton {
                        onActivated: if (controlCenter._effectivePlayer) controlCenter._effectivePlayer.previous()
                        LyricIcon { anchors.centerIn: parent; kind: "prev"; sz: 28 }
                    }
                    LyricTransportButton {
                        onActivated: controlCenter.seekBy(-15000)
                        LyricIcon { anchors.centerIn: parent; kind: "back15"; sz: 28 }
                    }
                    LyricTransportButton {
                        onActivated: controlCenter.togglePlayback()
                        Row { anchors.centerIn: parent; spacing: 6; visible: controlCenter.isPlayingNow
                              Rectangle { width: 7; height: 22; radius: 2; color: "white" }
                              Rectangle { width: 7; height: 22; radius: 2; color: "white" } }
                        LyricIcon { anchors.centerIn: parent; kind: "play"; sz: 28; visible: !controlCenter.isPlayingNow }
                    }
                    LyricTransportButton {
                        onActivated: controlCenter.seekBy(15000)
                        LyricIcon { anchors.centerIn: parent; kind: "fwd15"; sz: 28 }
                    }
                    LyricTransportButton {
                        onActivated: if (controlCenter._effectivePlayer) controlCenter._effectivePlayer.next()
                        LyricIcon { anchors.centerIn: parent; kind: "next"; sz: 28 }
                    }
                    LyricTransportButton {
                        iconOpacity: controlCenter._effectivePlayer && controlCenter._effectivePlayer.loopState !== MprisLoopState.None ? 1.0 : 0.45
                        onActivated: controlCenter.cycleLoop()
                        LyricIcon { anchors.centerIn: parent; sz: 28
                              kind: controlCenter._effectivePlayer && controlCenter._effectivePlayer.loopState === MprisLoopState.Track ? "loopone" : "loop" }
                    }
                }
            }
        }
    }
}
