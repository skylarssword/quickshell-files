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

    // ── Wired in from islandContainer so we can drive real transport
    // controls (seek / shuffle / loop / play-pause) and show album art. ──
    property var    activePlayer: null
    property string currentArtUrl: ""

    // expandedView is bound in from root (persisted in appearance-settings.json,
    // same pattern as capsuleUseWalColor etc). We never assign it locally —
    // only request a change via this signal so the parent binding stays intact.
    property bool expandedView: false
    signal expandedViewToggleRequested(bool expanded)

    property string lyricStatus: lyricManager ? lyricManager.backendStatus : "idle"
    property bool   hasSynced:   lyricManager ? lyricManager.isSynced : false

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

    // ── Independent playback polling (self-contained fallback, used only
    // if no activePlayer is bound in from the parent) ──────────────────
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

    // ── Local lyric viewer state (independent of LyricManager's own display state) ──
    property string viewerMode: "none"   // "none" | "synced" | "plain"
    property var    viewerLines: []      // [{time, text}] for synced mode
    property string viewerPlainText: ""  // raw text for plain mode
    property int    viewerActiveIndex: -1

    // ── Expanded transport display state ──
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
            if (idx !== controlCenter.viewerActiveIndex) {
                controlCenter.viewerActiveIndex = idx
                if (!controlCenter.expandedView && lyricViewerList.count > 0)
                    lyricViewerList.positionViewAtIndex(idx, ListView.Center)
                if (controlCenter.expandedView && expandedLyricList.count > 0)
                    expandedLyricList.positionViewAtIndex(idx, ListView.Center)
            }
        }
    }

    // ── Position/time helpers — same seconds-vs-ms heuristic used throughout ──
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

    scale: showCondition ? 1.0 : 0.12
    transformOrigin: Item.Top
    anchors.fill: parent
    anchors.margins: 12
    opacity: showCondition ? 1 : 0
    visible: opacity > 0

    Behavior on scale {
        NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? 240 : 100
            easing.type: Easing.InOutQuad
        }
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

            fileCatProc.command = ["cat", path]
            fileCatProc.running = true
        }
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
            if (controlCenter.lyricManager)
                controlCenter.lyricManager.applyManual(text, controlCenter.currentArtist, controlCenter.currentTrack)
            controlCenter.fileInfoText  = "Lyrics loaded from file"
            controlCenter.fileErrorText = ""
            controlCenter.lrclibStatusText = controlCenter.buildLrclibStatus()
            controlCenter.localFilePanelOpen = false
        }
    }

    Column {
        anchors.fill: parent
        spacing: 12

        Item {
            width: parent.width
            height: 28

            Text {
                renderType: Text.NativeRendering
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: currentTrack !== "" ? currentTrack : "No track"
                color: IslandMotion.textPrimary
                font.pixelSize: 16
                font.family: heroFontFamily
                font.weight: Font.Bold
                font.letterSpacing: -0.45
                elide: Text.ElideRight
                width: parent.width * 0.65
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 140)
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: lrclibStatusText
                    color: {
                        if (lyricStatus === "ready" && hasSynced) return StyleTokens.success
                        if (lyricStatus === "missing" || lyricStatus === "error") return StyleTokens.error
                        return textSecondary
                    }
                    font.pixelSize: 11
                    font.family: textFontFamily
                    font.weight: Font.Medium
                }

                Rectangle {
                    visible: controlCenter.viewerMode !== "none"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    radius: 4
                    color: expandToggleMouse.containsMouse
                        ? Qt.rgba(1, 1, 1, 0.12)
                        : (controlCenter.expandedView ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: controlCenter.expandedView ? "⤡" : "⤢"
                        color: controlCenter.expandedView ? cardAccent : IslandMotion.textFaint
                        font.pixelSize: 11
                        font.family: textFontFamily
                    }

                    MouseArea {
                        id: expandToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: controlCenter.expandedViewToggleRequested(!controlCenter.expandedView)
                    }
                }

                Rectangle {
                    visible: controlCenter.viewerMode !== "none"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    radius: 4
                    color: deleteCacheMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.15) : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "🗑"
                        color: deleteCacheMouse.containsMouse ? StyleTokens.error : IslandMotion.textFaint
                        font.pixelSize: 10
                        font.family: textFontFamily
                    }

                    MouseArea {
                        id: deleteCacheMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (controlCenter.lyricManager)
                                controlCenter.lyricManager.clearCache()
                            controlCenter.viewerMode = "none"
                            controlCenter.viewerLines = []
                            controlCenter.viewerPlainText = ""
                            if (controlCenter.expandedView)
                                controlCenter.expandedViewToggleRequested(false)
                            controlCenter.fileInfoText = ""
                            controlCenter.lrclibStatusText = controlCenter.buildLrclibStatus()
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: controlCenter.expandedView ? 0 : 80
            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Row {
                id: cardsRow
                anchors.fill: parent
                spacing: 12

 Rectangle {
                    id: lrclibCard
                    width: (cardsRow.width - cardsRow.spacing) / 2
                    height: cardsRow.height
                    radius: 20
                    color: (lrclibCardMouse.containsMouse || lrclibPanelOpen)
                        ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: (lrclibCardMouse.containsMouse || lrclibPanelOpen)
                        ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: lrclibCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        text: "\uf001"
                        color: lrclibPanelOpen ? cardAccent : textSecondary
                        font.pixelSize: 18
                        font.family: iconFontFamily
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 16
                        width: 8; height: 8; radius: 4
                        color: {
                            if (lyricStatus === "ready" && hasSynced) return StyleTokens.success
                            if (lyricStatus === "ready")               return StyleTokens.warning
                            if (lyricStatus === "missing")             return StyleTokens.error
                            return IslandMotion.textFaint
                        }
                    }

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
                            anchors.right: lrclibChevron.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            text: "LRCLib"
                            color: textPrimary
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: lrclibChevron.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            text: lrclibSearching ? "Searching..." :
                                  (lrclibResults.length > 0 ? lrclibResults.length + " results" :
                                  (lrclibErrorText !== "" ? lrclibErrorText : "Tap to search"))
                            color: lrclibErrorText !== "" ? StyleTokens.error : IslandMotion.textFaint
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            id: lrclibChevron
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: lrclibPanelOpen ? "#c7c9cf" : IslandMotion.textFaint
                            font.pixelSize: 17
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                localFilePanelOpen = false
                                lrclibPanelOpen = !lrclibPanelOpen
                                
                                if (lrclibPanelOpen) {
                                    // Instantly force the lyric box away
                                    controlCenter.viewerMode = "none"
                                    if (lrclibResults.length === 0)
                                        controlCenter.searchLrcLib()
                                } else {
                                    // If closing the panel, restore the correct lyric layout state
                                    controlCenter._restoreFromLyricManager()
                                }
                            }
                        }
                    }
                }

Rectangle {
                    id: localFileCard
                    width: (cardsRow.width - cardsRow.spacing) / 2
                    height: cardsRow.height
                    radius: 20
                    color: (localFileMouse.containsMouse || localFilePanelOpen)
                        ? Qt.rgba(1,1,1,0.09) : Qt.rgba(1,1,1,0.05)
                    border.width: 1
                    border.color: (localFileMouse.containsMouse || localFilePanelOpen)
                        ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: localFileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        text: "\uf15b"
                        color: localFilePanelOpen ? cardAccent : textSecondary
                        font.pixelSize: 18
                        font.family: iconFontFamily
                    }

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
                            anchors.right: fileChevron.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            text: "Local File"
                            color: textPrimary
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.left: parent.left
                            anchors.right: fileChevron.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            text: fileErrorText !== "" ? fileErrorText :
                                  (fileInfoText  !== "" ? fileInfoText  : "Load .lrc / .txt file")
                            color: fileErrorText !== "" ? StyleTokens.error :
                                   (fileInfoText !== "" ? StyleTokens.success : IslandMotion.textFaint)
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            renderType: Text.NativeRendering
                            id: fileChevron
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: localFilePanelOpen ? "#c7c9cf" : IslandMotion.textFaint
                            font.pixelSize: 17
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                lrclibPanelOpen = false
                                localFilePanelOpen = !localFilePanelOpen
                                
                                if (localFilePanelOpen) {
                                    // Instantly force the lyric box away
                                    controlCenter.viewerMode = "none"
                                } else {
                                    // If closing the panel, restore the correct lyric layout state
                                    controlCenter._restoreFromLyricManager()
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: lrclibResultsPanel
            width: parent.width
            height: (!controlCenter.expandedView && lrclibPanelOpen)
                ? Math.min(lrclibResultsColumn.implicitHeight + 16, 150)
                : 0
            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

Rectangle {
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Item {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 12
                    anchors.topMargin: 8
                    width: 52; height: 22

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: refreshMouse.containsMouse ? moduleHover : moduleColor

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "Retry"
                            color: textPrimary
                            font.pixelSize: 10
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: controlCenter.searchLrcLib()
                        }
                    }
                }

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    contentHeight: lrclibResultsColumn.implicitHeight
                    clip: true

                    Column {
                        id: lrclibResultsColumn
                        width: parent.width
                        spacing: 4

                        Item {
                            width: parent.width
                            height: lrclibSearching ? 28 : 0
                            visible: height > 0
                            clip: true
                            Behavior on height { NumberAnimation { duration: 160 } }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "Searching LRCLib..."
                                color: textSecondary
                                font.pixelSize: 12
                                font.family: textFontFamily
                            }
                        }

                        Item {
                            width: parent.width
                            height: (!lrclibSearching && lrclibErrorText !== "") ? 28 : 0
                            visible: height > 0
                            clip: true
                            Behavior on height { NumberAnimation { duration: 160 } }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: lrclibErrorText
                                color: StyleTokens.error
                                font.pixelSize: 12
                                font.family: textFontFamily
                            }
                        }

                        Repeater {
                            model: lrclibResults

                            delegate: Rectangle {
                                width: lrclibResultsColumn.width
                                height: 36
                                radius: 12
                                color: selectedResultIndex === index
                                    ? Qt.rgba(StyleTokens.accent.r, StyleTokens.accent.g, StyleTokens.accent.b, 0.18)
                                    : (resultMouse.containsMouse ? moduleHover : "transparent")

                                Behavior on color { ColorAnimation { duration: 100 } }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Rectangle {
                                        width: 28; height: 16
                                        radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: modelData.hasSynced ? StyleTokens.success : IslandMotion.textFaint
                                        opacity: 0.85

                                        Text {
                                            renderType: Text.NativeRendering
                                            anchors.centerIn: parent
                                            text: modelData.hasSynced ? "LRC" : "TXT"
                                            color: "white"
                                            font.pixelSize: 8
                                            font.family: textFontFamily
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 36 - 8 - (durationLabel.visible ? durationLabel.width + 8 : 0)
                                        spacing: 1

                                        Text {
                                            renderType: Text.NativeRendering
                                            width: parent.width
                                            text: modelData.title
                                            color: textPrimary
                                            font.pixelSize: 11
                                            font.family: textFontFamily
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            renderType: Text.NativeRendering
                                            width: parent.width
                                            text: modelData.artist + (modelData.album !== "" ? " · " + modelData.album : "")
                                            color: IslandMotion.textFaint
                                            font.pixelSize: 9
                                            font.family: textFontFamily
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        id: durationLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: modelData.duration > 0
                                        text: {
                                            const s = Math.round(modelData.duration)
                                            return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
                                        }
                                        color: IslandMotion.textFaint
                                        font.pixelSize: 9
                                        font.family: textFontFamily
                                    }
                                }

                                MouseArea {
                                    id: resultMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: controlCenter.applyResult(index)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: localFilePanel
            width: parent.width
            height: (!controlCenter.expandedView && localFilePanelOpen) ? localFileContent.implicitHeight + 16 : 0
            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

Rectangle {
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)

                Column {
                    id: localFileContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: "Load a .lrc or .txt file for this track. It will be saved to the\nlyrics cache and used automatically next time."
                        color: textSecondary
                        font.pixelSize: 11
                        font.family: textFontFamily
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 12
                        color: browseButtonMouse.containsMouse
                            ? StyleTokens.accentPressed : StyleTokens.accent

                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: "Browse for .lrc file…"
                            color: "white"
                            font.pixelSize: 13
                            font.family: textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: browseButtonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: controlCenter.pickLocalFile()
                        }
                    }
                }
            }
        }

        // ── Lyric viewer — minimized (compact card) or maximized
        //    (spinning art + right-side lyrics + transport controls) ──
        Item {
            id: lyricViewer
            width: parent.width
            height: controlCenter.viewerMode === "none"
                ? 0
                : (controlCenter.expandedView ? controlCenter.expandedViewerHeight : controlCenter.viewerHeight)

            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

// ── Minimized presentation ──
            Rectangle {
                anchors.fill: parent
                radius: 16
                color: Qt.rgba(1,1,1,0.05)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.16)
                visible: !controlCenter.expandedView

                ListView {
                    id: lyricViewerList
                    anchors.fill: parent
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    visible: controlCenter.viewerMode === "synced"
                    model: controlCenter.viewerLines
                    clip: true
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: height / 2 - 10
                    preferredHighlightEnd: height / 2 + 10
                    highlightMoveDuration: 200

                    delegate: Text {
     renderType: Text.NativeRendering
                        width: lyricViewerList.width
                        text: modelData.text || ". . ."
                        color: index === controlCenter.viewerActiveIndex ? cardAccent : IslandMotion.textFaint
                        font.pixelSize: index === controlCenter.viewerActiveIndex ? 13 : 11
                        font.family: textFontFamily
                        font.weight: index === controlCenter.viewerActiveIndex ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on font.pixelSize { NumberAnimation { duration: 150 } }

                        MouseArea {
                            anchors.fill: parent
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
                    anchors.fill: parent
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    visible: controlCenter.viewerMode === "plain"
                    contentHeight: plainViewerText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        renderType: Text.NativeRendering
                        id: plainViewerText
                        width: parent.width
                        text: controlCenter.viewerPlainText
                        color: textSecondary
                        font.pixelSize: 11
                        font.family: textFontFamily
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    visible: controlCenter.viewerMode === "none"
                    text: "No lyrics loaded"
                    color: IslandMotion.textFaint
                    font.pixelSize: 11
                    font.family: textFontFamily
                }
            }

            // ── Maximized presentation ──
            Column {
                anchors.fill: parent
                visible: controlCenter.expandedView
                spacing: 10

                // Spinning art + lyric lines
                Item {
                    width: parent.width
                    height: 150

                    Item {
                        id: expandedArtSpinner
                        width: 108
                        height: 108
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            id: expandedArtImage
                            anchors.fill: parent
                            source: controlCenter.currentArtUrl
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            sourceSize: Qt.size(220, 220)
                        }

                        Rectangle {
                            id: expandedArtMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: expandedArtImage
                            maskSource: expandedArtMask
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: IslandMotion.surfaceBorderWidth
                            border.color: IslandMotion.surfaceBorderColor
                        }

                        RotationAnimation {
                            target: expandedArtSpinner
                            property: "rotation"
                            from: expandedArtSpinner.rotation
                            to: expandedArtSpinner.rotation + 360
                            duration: 9000
                            loops: Animation.Infinite
                            running: controlCenter.expandedView && controlCenter.isPlayingNow
                        }
                    }

                    ListView {
                        id: expandedLyricList
                        anchors.left: expandedArtSpinner.right
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: controlCenter.viewerMode === "synced"
                        model: controlCenter.viewerLines
                        clip: true
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: height / 2 - 10
                        preferredHighlightEnd: height / 2 + 10
                        highlightMoveDuration: 200

                        delegate: Text {
     renderType: Text.NativeRendering
                            width: expandedLyricList.width
                            text: modelData.text || ". . ."
                            color: index === controlCenter.viewerActiveIndex ? IslandMotion.textPrimary : IslandMotion.textSecondary
                            font.pixelSize: index === controlCenter.viewerActiveIndex ? 15 : 12
                            font.family: textFontFamily
                            font.weight: index === controlCenter.viewerActiveIndex ? Font.Bold : Font.Normal
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.WordWrap

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }

                            MouseArea {
                                anchors.fill: parent
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
                        anchors.left: expandedArtSpinner.right
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        visible: controlCenter.viewerMode === "plain"
                        contentHeight: expandedPlainText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Text {
                            renderType: Text.NativeRendering
                            id: expandedPlainText
                            width: parent.width
                            text: controlCenter.viewerPlainText
                            color: IslandMotion.textSecondary
                            font.pixelSize: 12
                            font.family: textFontFamily
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignLeft
                        }
                    }
                }

                // Progress / seek bar
                Item {
                    width: parent.width
                    height: 16

                    Text {
                        renderType: Text.NativeRendering
                        id: expTimeL
                        anchors.left: parent.left
                        text: controlCenter.timePlayedLocal
                        color: IslandMotion.textSecondary
                        font.pixelSize: 11
                        font.family: textFontFamily
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: expTimeL.right
                        anchors.right: expTimeR.left
                        anchors.margins: 10
                        height: 5
                        radius: 2.5
                        color: "#333333"

                        Rectangle {
                            height: parent.height
                            radius: 2.5
                            color: "white"
                            width: parent.width * Math.max(0, Math.min(1, controlCenter.trackProgressLocal))
                            Behavior on width {
                                enabled: !expScrubArea.pressed
                                NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                            }
                        }

                        MouseArea {
                            id: expScrubArea
                            anchors.fill: parent
                            anchors.margins: -10
                            preventStealing: true
                            onPositionChanged: (mouse) => {
                                if (!pressed) return
                                controlCenter._scrubToFraction(mouse.x / width)
                            }
                            onReleased: (mouse) => controlCenter._scrubToFraction(mouse.x / width)
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        id: expTimeR
                        anchors.right: parent.right
                        text: controlCenter.timeTotalLocal
                        color: IslandMotion.textSecondary
                        font.pixelSize: 11
                        font.family: textFontFamily
                        font.weight: Font.Medium
                    }
                }

                // Transport controls: shuffle, -15, play/pause, +15, loop
                Item {
                    width: parent.width
                    height: 34

                    Row {
                        anchors.centerIn: parent
                        spacing: 26

                        Item {
                            width: 22; height: 22
                            opacity: controlCenter._effectivePlayer && controlCenter._effectivePlayer.shuffle ? 1.0 : 0.35
                            scale: shuffleMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
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
                                    ctx.beginPath(); ctx.moveTo(2,6); ctx.lineTo(12,6); ctx.lineTo(19,15); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(15,13); ctx.lineTo(19,15); ctx.lineTo(15,17); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(2,15); ctx.lineTo(12,15); ctx.lineTo(19,6); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(15,4); ctx.lineTo(19,6); ctx.lineTo(15,8); ctx.stroke()
                                }
                            }
                            MouseArea {
                                id: shuffleMouse
                                anchors.fill: parent
                                anchors.margins: -10
                                onClicked: controlCenter.toggleShuffle()
                            }
                        }

Item {
                            width: 26; height: 26
                            scale: rewindMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "↺"
                                color: "white"
                                font.pixelSize: 22
                                font.family: textFontFamily
                            }
                            MouseArea {
                                id: rewindMouse
                                anchors.fill: parent
                                anchors.margins: -10
                                onClicked: controlCenter.seekBy(-15000)
                            }
                        }

                        Item {
                            width: 26; height: 26
                            scale: playMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Row {
                                anchors.centerIn: parent
                                spacing: 5
                                visible: controlCenter.isPlayingNow
                                Rectangle { width: 5; height: 18; radius: 2; color: "white" }
                                Rectangle { width: 5; height: 18; radius: 2; color: "white" }
                            }
                            Canvas {
                                anchors.fill: parent
                                visible: !controlCenter.isPlayingNow
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = "white"
                                    ctx.beginPath()
                                    ctx.moveTo(7, 3); ctx.lineTo(22, 13); ctx.lineTo(7, 23)
                                    ctx.closePath(); ctx.fill()
                                }
                            }
                            MouseArea {
                                id: playMouse
                                anchors.fill: parent
                                anchors.margins: -10
                                onClicked: controlCenter.togglePlayback()
                            }
                        }

Item {
                            width: 26; height: 26
                            scale: forwardMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "↻"
                                color: "white"
                                font.pixelSize: 22
                                font.family: textFontFamily
                            }
                            MouseArea {
                                id: forwardMouse
                                anchors.fill: parent
                                anchors.margins: -10
                                onClicked: controlCenter.seekBy(15000)
                            }
                        }

                        Item {
                            width: 22; height: 22
                            opacity: controlCenter._effectivePlayer && controlCenter._effectivePlayer.loopState !== MprisLoopState.None ? 1.0 : 0.35
                            scale: loopMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Canvas {
                                id: loopCanvas
                                anchors.fill: parent
                                property bool loopOne: controlCenter._effectivePlayer && controlCenter._effectivePlayer.loopState === MprisLoopState.Track
                                onLoopOneChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.strokeStyle = "white"
                                    ctx.lineWidth = 2
                                    ctx.lineCap = "round"
                                    ctx.lineJoin = "round"
                                    ctx.beginPath(); ctx.moveTo(4,9); ctx.lineTo(4,16); ctx.lineTo(17,16); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(19,13); ctx.lineTo(17,16); ctx.lineTo(19,19); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(19,13); ctx.lineTo(19,6); ctx.lineTo(6,6); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(4,9); ctx.lineTo(6,6); ctx.lineTo(4,3); ctx.stroke()
                                    if (loopOne) {
                                        ctx.font = "bold 7px sans-serif"
                                        ctx.fillStyle = "white"
                                        ctx.textAlign = "center"
                                        ctx.fillText("1", 11, 14)
                                    }
                                }
                            }
                            MouseArea {
                                id: loopMouse
                                anchors.fill: parent
                                anchors.margins: -10
                                onClicked: controlCenter.cycleLoop()
                            }
                        }
                    }
                }
            }
        }
    }
}
