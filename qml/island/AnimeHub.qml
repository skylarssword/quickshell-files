import QtQuick
import Quickshell
import Quickshell.Io
import "../shared"

// AnimeHub: stacked under the search pill when you type "anime".
// Three tabs on a left rail: Home (continue watching), Search (poster grid) and
// List (history + episode grid). The pill above stays a static "anime" line.
// All network work goes through scripts/ani-backend (copied from ani-cli's scraper).
//
// Keys (focus always stays in the hidden input; typing anywhere jumps to Search):
//   type            search (debounced)
//   Arrows          move through the poster grid / history list / episode grid
//   Enter           Home: continue  |  Search: open  |  List: open, then play the episode
//   Tab             toggle sub / dub
//   Esc             back to the list -> clear search -> Home -> close

Item {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""

    signal closeRequested()

    // ── layout ────────────────────────────────────────────────────────────────
    readonly property int capsuleWidth: 640
    readonly property int bannerHeight: 28
    readonly property int railWidth: 58
    readonly property int panelsHeight: 290
    readonly property int footerHeight: 46
    readonly property int resultsWidth: 244
    readonly property int searchCols: 5
    readonly property int epCols: 6
    readonly property bool showBanner: versionState === "outdated"
    readonly property int capsuleHeight: (showBanner ? bannerHeight : 0) + panelsHeight + footerHeight

    width: capsuleWidth
    height: capsuleHeight
    implicitWidth: capsuleWidth
    implicitHeight: capsuleHeight

    // ── state ─────────────────────────────────────────────────────────────────
    readonly property string backend: Quickshell.shellDir + "/scripts/ani-backend"

    property string tab: "home"            // "home" | "search" | "list"
    property string mode: "sub"            // "sub" | "dub"
    property string zone: "results"        // list tab: "results" (history column) | "episodes"
    property string query: ""

    property var    results: []            // [{ id, title, cover }]
    property var    history: []            // [{ ep, id, title }], most recent first
    property int    resultIndex: 0         // search grid cursor
    property int    listIndex: 0           // list tab (history) cursor
    property var    covers: ({})           // { animeId: coverUrl } filled from searches
    property bool   pendingPlay: false     // play as soon as the episodes have loaded

    property string selectedId: ""
    property string selectedTitle: ""
    property var    episodes: []           // ["1", "2", ...]
    property int    epIndex: 0
    property int    watchedIdx: -1

    property bool   searching: false
    property bool   loadingEps: false
    property bool   playing: false
    property string searchError: ""
    property string errorText: ""

    property string versionState: "unknown" // "ok" | "outdated" | "unknown"
    property string versionLocal: ""
    property string versionRemote: ""

    // When true, select the most recent history entry as soon as history has
    // loaded (used when the hub reopens after mpv closes).
    property bool autoContinue: false

    // saved spots (press "c" in mpv): { animeId: { ep, pos } }
    property var  resume: ({})
    property bool _histLoaded: false
    property bool _resumeLoaded: false

    // Auto: quit an episode at 90%+ and the next one starts after a short countdown.
    property bool   autoplay: false
    property int    countdown: 0             // seconds left, 0 = not counting down
    property string noticeText: ""
    property var    finishedMark: null       // { id, ep, mode } left by mpv at 90%+
    property var    pendingAutoplay: null
    property bool   _finishedLoaded: false
    property bool   _autoplayLoaded: false

    readonly property string footerText: playing ? "Getting stream…"
        : (countdown > 0 ? "Next episode in " + countdown + "…  any key to cancel"
        : (errorText !== "" ? errorText.replace(/\n/g, " · ") : noticeText))

    property bool _searchDirty: false
    property bool _epDirty: false

    // List tab: history, plus the anime you opened from Search when it isn't in history yet
    readonly property var listRows: {
        const out = []
        let found = false
        for (let j = 0; j < history.length; j++) {
            const h = history[j]
            if (h.id === selectedId) found = true
            out.push({ id: h.id, title: h.title, ep: h.ep, resume: resume[h.id] || null })
        }
        if (selectedId !== "" && !found)
            out.unshift({ id: selectedId, title: selectedTitle, ep: "", resume: null })
        return out
    }

    // items of the tab that has the cursor
    readonly property var rows: tab === "search" ? results : listRows

    // anime that have a saved spot, newest first (Home strip)
    readonly property var pausedRows: {
        const out = []
        for (let j = 0; j < history.length; j++) {
            const r = resume[history[j].id]
            if (r) out.push({ id: history[j].id, title: history[j].title, ep: r.ep, pos: r.pos })
        }
        return out
    }

    function coverFor(id) { return covers[id] || "" }

    // ── helpers ───────────────────────────────────────────────────────────────
    function lines(raw) {
        return raw.split("\n").filter(l => l.trim() !== "")
    }

    function firstError(raw) {
        const ls = lines(raw)
        for (let i = 0; i < ls.length; i++)
            if (ls[i].indexOf("ERR\t") === 0) return ls[i].substring(4)
        return ls.length > 0 ? ls[0] : ""
    }

    function failureText(detail) {
        const hint = versionState === "outdated"
            ? "Doesn't work right now. Update ani-cli!"
            : "Doesn't work right now. The site may have changed, check for an ani-cli update."
        return hint + (detail ? "\n" + detail : "")
    }

    function fmtTime(s) {
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
    }

    // true when the highlighted episode is the one you paused with "c"
    readonly property bool resumeHere: {
        const r = resume[selectedId]
        return !!r && episodes.length > 0 && episodes[epIndex] === r.ep
    }

    function lastWatchedEp(id) {
        for (let i = 0; i < history.length; i++)
            if (history[i].id === id) return history[i].ep
        return ""
    }

    function focusInput() { searchInput.forceActiveFocus() }
    function inputHasFocus() { return searchInput.activeFocus }

    // ── navigation ────────────────────────────────────────────────────────────
    function moveRow(d) {
        if (rows.length === 0) return
        if (tab === "search") {
            resultIndex = Math.max(0, Math.min(rows.length - 1, resultIndex + d))
            resultsGrid.positionViewAtIndex(resultIndex, GridView.Contain)
        } else {
            listIndex = Math.max(0, Math.min(rows.length - 1, listIndex + d))
            resultsList.positionViewAtIndex(listIndex, ListView.Contain)
        }
    }

    function setTab(t) {
        cancelCountdown()
        if (t === "list" && selectedId === "" && history.length > 0) { continueWatching(); return }
        tab = t
        if (t === "list" && episodes.length === 0) zone = "results"
        focusInput()
    }

    function moveEp(d) {
        if (episodes.length === 0) return
        epIndex = Math.max(0, Math.min(episodes.length - 1, epIndex + d))
        epGrid.positionViewAtIndex(epIndex, GridView.Contain)
    }

    function toggleMode() { mode = mode === "sub" ? "dub" : "sub" }

    function toggleAutoplay() {
        autoplay = !autoplay
        Quickshell.execDetached(["bash", backend, "autoplay", autoplay ? "on" : "off"])
        if (!autoplay) cancelCountdown()
    }

    function notify(msg) {
        noticeText = msg
        noticeTimer.restart()
    }

    function startCountdown() {
        if (!autoplay) return
        countdown = 5
        countdownTimer.restart()
    }

    // returns true when it actually cancelled, so key handlers can swallow the key
    function cancelCountdown() {
        if (countdown <= 0) return false
        countdown = 0
        countdownTimer.stop()
        notify("Autoplay cancelled")
        return true
    }

    function selectAnime(id, title) {
        selectedId = id
        selectedTitle = title
        episodes = []
        epIndex = 0
        watchedIdx = -1
        errorText = ""
        zone = "episodes"
        tab = "list"
        listIndex = Math.max(0, listRows.findIndex(r => r.id === id))
        Qt.callLater(() => resultsList.positionViewAtIndex(root.listIndex, ListView.Contain))
        loadingEps = true
        runEpisodes()
    }

    function openRow(i) {
        const row = rows[i]
        if (!row) return
        if (tab === "search") resultIndex = i; else listIndex = i
        selectAnime(row.id, row.title)
    }

    function continueWatching() {
        if (history.length === 0) return
        selectAnime(history[0].id, history[0].title)
    }

    // Home hero: open the latest show and start the episode you were on
    function resumeLatest() {
        if (history.length === 0) return
        pendingPlay = true
        selectAnime(history[0].id, history[0].title)
    }

    function activate() {
        if (tab === "home") { continueWatching(); return }
        if (tab === "search") {
            if (searchDebounce.running) {      // user hit Enter before the debounce fired
                searchDebounce.stop()
                runSearch()
                return
            }
            if (rows.length > 0) openRow(resultIndex)
            return
        }
        if (zone === "results") {
            if (rows.length > 0) openRow(listIndex)
        } else {
            playSelected()
        }
    }

    // ── backend calls ─────────────────────────────────────────────────────────
    function runSearch() {
        const q = query.trim()
        if (q.length < 2) { searching = false; return }
        if (searchProc.running) { _searchDirty = true; return }
        searchProc.q = q
        searchProc.command = ["bash", backend, "search", q]
        searching = true
        searchProc.running = true
    }

    function finishSearch(q, out, err) {
        if (q === query.trim()) {
            if (err.trim() !== "") {
                results = []
                searchError = failureText(firstError(err))
            } else {
                searchError = ""
                const parsed = []
                const ls = lines(out)
                for (let i = 0; i < ls.length; i++) {
                    const p = ls[i].split("\t")
                    if (p.length >= 2) parsed.push({ id: p[0], title: p[1], cover: p.length > 2 ? p[2] : "" })
                }
                const c = Object.assign({}, covers)
                for (let k = 0; k < parsed.length; k++) if (parsed[k].cover !== "") c[parsed[k].id] = parsed[k].cover
                covers = c
                results = parsed
            }
            resultIndex = 0
            Qt.callLater(() => resultsGrid.positionViewAtBeginning())
        }
        if (_searchDirty) {
            _searchDirty = false
            runSearch()
        } else {
            searching = searchDebounce.running
        }
    }

    function runEpisodes() {
        if (epProc.running) { _epDirty = true; return }
        epProc.animeId = selectedId
        epProc.command = ["bash", backend, "episodes", selectedId]
        epProc.running = true
    }

    function finishEpisodes(id, out, err) {
        if (id === selectedId) {
            if (err.trim() !== "") {
                episodes = []
                pendingAutoplay = null
                pendingPlay = false
                errorText = failureText(firstError(err))
            } else {
                const eps = lines(out).map(l => l.trim())
                episodes = eps
                const idx = eps.indexOf(lastWatchedEp(id))
                const r = resume[id]
                const ri = r ? eps.indexOf(r.ep) : -1
                if (ri >= 0) {              // paused mid-episode: land on it, not the next one
                    watchedIdx = ri - 1
                    epIndex = ri
                } else {
                    watchedIdx = idx
                    epIndex = idx >= 0 ? Math.min(idx + 1, eps.length - 1) : 0
                }
                // Auto: the episode you just finished is done, line up the next one
                if (pendingAutoplay && pendingAutoplay.id === id) {
                    const ni = eps.indexOf(pendingAutoplay.ep) + 1
                    if (ni > 0 && ni < eps.length) {
                        watchedIdx = ni - 1
                        epIndex = ni
                        startCountdown()
                    }
                }
                pendingAutoplay = null
                Qt.callLater(() => epGrid.positionViewAtIndex(root.epIndex, GridView.Contain))
                if (pendingPlay) { pendingPlay = false; Qt.callLater(root.playSelected) }
            }
        }
        if (_epDirty) {
            _epDirty = false
            runEpisodes()
        } else {
            loadingEps = false
        }
    }

    function playSelected() {
        if (playing || selectedId === "" || episodes.length === 0) return
        errorText = ""
        playing = true
        playProc.command = ["bash", backend, "play", selectedId, episodes[epIndex], mode, selectedTitle]
        playProc.running = true
    }

    function finishPlay(out, err) {
        playing = false
        if (lines(out).indexOf("OK") >= 0) {
            historyProc.running = true
            closeRequested()
        } else {
            errorText = failureText(firstError(err))
            errorTimer.restart()
        }
    }

    // Delete one anime from history. Updates the UI right away and tells the
    // backend to drop it from the history file.
    function deleteHistory(id) {
        Quickshell.execDetached(["bash", backend, "delete", id])
        history = history.filter(h => h.id !== id)
        const r = Object.assign({}, resume)
        delete r[id]
        resume = r
        if (selectedId === id) watchedIdx = -1
        listIndex = Math.max(0, Math.min(listIndex, listRows.length - 1))
    }

    function clearHistory() {
        Quickshell.execDetached(["bash", backend, "clear"])
        history = []
        resume = ({})
        watchedIdx = -1
        listIndex = Math.max(0, Math.min(listIndex, listRows.length - 1))
    }

    function loadHistory(raw) {
        const parsed = []
        const ls = lines(raw)
        for (let i = 0; i < ls.length; i++) {
            const p = ls[i].split("\t")
            if (p.length >= 3) parsed.push({ ep: p[0], id: p[1], title: p.slice(2).join("\t") })
        }
        history = parsed
        _histLoaded = true
        maybeAutoContinue()
    }

    function loadCovers(raw) {
        const c = Object.assign({}, covers)
        const ls = lines(raw)
        for (let i = 0; i < ls.length; i++) {
            const p = ls[i].split("\t")
            if (p.length >= 2 && p[1] !== "" && !c[p[0]]) c[p[0]] = p[1]
        }
        covers = c
    }

    function loadResume(raw) {
        const m = {}
        const ls = lines(raw)
        for (let i = 0; i < ls.length; i++) {
            const p = ls[i].split("\t")
            if (p.length >= 3) m[p[0]] = { ep: p[1], pos: parseInt(p[2]) }
        }
        resume = m
        _resumeLoaded = true
        maybeAutoContinue()
    }

    function loadFinished(raw) {
        const first = lines(raw)[0]
        const f = first ? first.split("\t") : []
        finishedMark = f.length >= 2 ? { id: f[0], ep: f[1], mode: f.length > 2 ? f[2] : "" } : null
        _finishedLoaded = true
        maybeAutoContinue()
    }

    // once history, saved spots, the Auto flag and the finished marker are in, select the latest show
    function maybeAutoContinue() {
        if (!autoContinue || !_histLoaded || !_resumeLoaded || !_finishedLoaded || !_autoplayLoaded) return
        if (history.length === 0 && selectedId === "") tab = "home"
        if (selectedId !== "" || history.length === 0) return
        autoContinue = false

        // finished at 90%+ with Auto on: open that show and count down to the next episode
        if (autoplay && finishedMark) {
            const h = history.find(x => x.id === finishedMark.id)
            if (h) {
                if (finishedMark.mode === "sub" || finishedMark.mode === "dub") mode = finishedMark.mode
                pendingAutoplay = finishedMark
                selectAnime(h.id, h.title)
                return
            }
        }
        continueWatching()
    }

    Component.onCompleted: {
        historyProc.running = true
        resumeProc.running = true
        autoplayProc.running = true
        finishedProc.running = true
        versionProc.running = true
        coversProc.running = true
        if (autoContinue) tab = "list"      // reopened after mpv: go straight to the episodes
        focusInput()
    }

    // ── processes ─────────────────────────────────────────────────────────────
    Timer {
        id: searchDebounce
        interval: 450
        repeat: false
        onTriggered: root.runSearch()
    }

    Timer {
        id: errorTimer
        interval: 9000
        repeat: false
        onTriggered: root.errorText = ""
    }

    Timer {
        id: noticeTimer
        interval: 2500
        repeat: false
        onTriggered: root.noticeText = ""
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1
            if (root.countdown <= 0) {
                stop()
                root.countdown = 0
                root.playSelected()
            }
        }
    }

    Process {
        id: searchProc
        property string q: ""
        property string out: ""
        property string err: ""
        stdout: SplitParser { onRead: searchProc.out += data + "\n" }
        stderr: SplitParser { onRead: searchProc.err += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out, e = err
            out = ""; err = ""
            root.finishSearch(q, o, e)
        }
    }

    Process {
        id: epProc
        property string animeId: ""
        property string out: ""
        property string err: ""
        stdout: SplitParser { onRead: epProc.out += data + "\n" }
        stderr: SplitParser { onRead: epProc.err += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out, e = err
            out = ""; err = ""
            root.finishEpisodes(animeId, o, e)
        }
    }

    Process {
        id: playProc
        property string out: ""
        property string err: ""
        stdout: SplitParser { onRead: playProc.out += data + "\n" }
        stderr: SplitParser { onRead: playProc.err += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out, e = err
            out = ""; err = ""
            root.finishPlay(o, e)
        }
    }

    Process {
        id: historyProc
        property string out: ""
        command: ["bash", root.backend, "history"]
        stdout: SplitParser { onRead: historyProc.out += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out
            out = ""
            root.loadHistory(o)
        }
    }

    Process {
        id: resumeProc
        property string out: ""
        command: ["bash", root.backend, "resume"]
        stdout: SplitParser { onRead: resumeProc.out += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out
            out = ""
            root.loadResume(o)
        }
    }

    Process {
        id: autoplayProc
        property string out: ""
        command: ["bash", root.backend, "autoplay"]
        stdout: SplitParser { onRead: autoplayProc.out += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out
            out = ""
            root.autoplay = root.lines(o).indexOf("on") >= 0
            root._autoplayLoaded = true
            root.maybeAutoContinue()
        }
    }

    Process {
        id: finishedProc
        property string out: ""
        command: ["bash", root.backend, "finished"]
        stdout: SplitParser { onRead: finishedProc.out += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out
            out = ""
            root.loadFinished(o)
        }
    }

    Process {
        id: coversProc
        property string out: ""
        command: ["bash", root.backend, "covers"]
        stdout: SplitParser { onRead: coversProc.out += data + "\n" }
        onRunningChanged: {
            if (running) return
            const o = out
            out = ""
            root.loadCovers(o)
        }
    }

    Process {
        id: versionProc
        property string out: ""
        command: ["bash", root.backend, "version"]
        stdout: SplitParser { onRead: versionProc.out += data + "\n" }
        onRunningChanged: {
            if (running) return
            const p = root.lines(out)[0] ? root.lines(out)[0].split("\t") : []
            out = ""
            root.versionState = p.length > 0 ? p[0] : "unknown"
            root.versionLocal = p.length > 1 ? p[1] : ""
            root.versionRemote = p.length > 2 ? p[2] : ""
        }
    }

    // ── ui ────────────────────────────────────────────────────────────────────
    readonly property int topInset: showBanner ? bannerHeight : 0

    // update banner
    Item {
        width: parent.width
        height: root.topInset
        visible: root.showBanner

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.topMargin: 2
            radius: 12
            color: Qt.rgba(1.0, 0.76, 0.28, 0.10)
        }

        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                renderType: Text.NativeRendering
                text: ""
                font.family: root.iconFontFamily
                font.pixelSize: 11
                color: Qt.rgba(1.0, 0.82, 0.45, 0.95)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                renderType: Text.NativeRendering
                text: "ani-cli " + root.versionLocal + " → " + root.versionRemote + " available. Update it if search or playback fails."
                font.family: root.textFontFamily
                font.pixelSize: 11
                color: Qt.rgba(1.0, 0.82, 0.45, 0.95)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── tab rail (three round tabs, centered in the line) ─────────────────────
    Item {
        id: rail
        x: 0
        y: root.topInset
        width: root.railWidth
        height: root.panelsHeight + root.footerHeight

        Column {
            anchors.centerIn: parent
            spacing: 12

            Repeater {
                model: [ "home", "search", "list" ]
                delegate: Rectangle {
                    id: tabBtn
                    required property string modelData
                    readonly property bool active: root.tab === modelData
                    width: 36; height: 36; radius: 18
                    color: active ? Qt.rgba(1, 1, 1, 0.14) : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                    border.width: 1
                    border.color: active ? Qt.rgba(1, 1, 1, 0.34) : "transparent"
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                    GlassSheen { visible: tabBtn.active }

                    AnimeIcon {
                        id: tabIcon
                        anchors.centerIn: parent
                        kind: tabBtn.modelData; sz: 17
                        col: "white"
                        opacity: tabBtn.active ? 1.0 : (tabMouse.containsMouse ? 0.8 : 0.5)
                        scale: tabMouse.pressed ? 0.86 : 1.0
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setTab(tabBtn.modelData)
                    }
                }
            }
        }
    }

    // thin dividers instead of gray panels
    Rectangle {
        x: root.railWidth - 1; y: root.topInset + 14
        width: 1; height: root.panelsHeight + root.footerHeight - 28
        color: Qt.rgba(1, 1, 1, 0.09)
    }
    Rectangle {
        x: root.railWidth + 8; y: root.topInset + root.panelsHeight
        width: root.width - root.railWidth - 22; height: 1
        color: Qt.rgba(1, 1, 1, 0.09)
    }

    // ── body ──────────────────────────────────────────────────────────────────
    Item {
        id: bodyArea
        x: root.railWidth
        y: root.topInset
        width: root.width - root.railWidth
        height: root.panelsHeight

        // ───────────────────────── HOME ─────────────────────────
        Item {
            id: homeTab
            anchors.fill: parent
            visible: root.tab === "home"

            readonly property var h0: root.history.length > 0 ? root.history[0] : null

            // hero
            Item {
                id: hero
                x: 6; y: 2; width: 372; height: 160

                AnimeCover {
                    anchors.fill: parent
                    radius: 22
                    source: homeTab.h0 ? root.coverFor(homeTab.h0.id) : ""
                    label: homeTab.h0 ? homeTab.h0.title : ""
                }
                Rectangle {
                    anchors.fill: parent; radius: 22
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.72) }
                        GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.0) }
                    }
                }
                Column {
                    x: 20; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -8
                    width: parent.width * 0.62
                    spacing: 4
                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        text: homeTab.h0 ? homeTab.h0.title : "Nothing watched yet"
                        elide: Text.ElideRight
                        font.family: root.textFontFamily
                        font.pixelSize: 19
                        font.bold: true
                        color: "white"
                    }
                    Text {
                        renderType: Text.NativeRendering
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: root.textFontFamily
                        font.pixelSize: 11
                        color: "white"
                        opacity: 0.7
                        text: !homeTab.h0 ? "Search an anime to get started"
                              : (root.resume[homeTab.h0.id]
                                 ? "Paused · ep " + root.resume[homeTab.h0.id].ep + " at " + root.fmtTime(root.resume[homeTab.h0.id].pos)
                                 : "Continue watching · ep " + homeTab.h0.ep)
                    }
                }
                Row {
                    x: 20; y: parent.height - 44
                    spacing: 8
                    AnimeButton {
                        visible: homeTab.h0 !== null
                        label: root.resume[homeTab.h0 ? homeTab.h0.id : ""] ? "Resume" : "Continue"
                        iconKind: "play"; primary: true; fontFamily: root.textFontFamily
                        onClicked: { root.resumeLatest(); root.focusInput() }
                    }
                    AnimeButton {
                        visible: homeTab.h0 !== null
                        label: "Episodes"; iconKind: "list"; fontFamily: root.textFontFamily
                        onClicked: { root.continueWatching(); root.focusInput() }
                    }
                    AnimeButton {
                        visible: homeTab.h0 === null
                        label: "Search anime"; iconKind: "search"; primary: true; fontFamily: root.textFontFamily
                        onClicked: root.setTab("search")
                    }
                }
            }

            // recent shows
            Column {
                x: 386; y: 2
                spacing: 8
                Repeater {
                    model: 3
                    delegate: Item {
                        id: tile
                        required property int index
                        readonly property var h: root.history.length > index + 1 ? root.history[index + 1] : null
                        width: 188; height: 48
                        visible: h !== null

                        AnimeCover {
                            anchors.fill: parent; radius: 14
                            source: tile.h ? root.coverFor(tile.h.id) : ""
                            label: tile.h ? tile.h.title : ""
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 14
                            color: tileMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.40) : Qt.rgba(0, 0, 0, 0.55)
                            Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
                        }
                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            Text {
                                renderType: Text.NativeRendering
                                width: parent.width
                                text: tile.h ? tile.h.title : ""
                                elide: Text.ElideRight
                                font.family: root.textFontFamily; font.pixelSize: 12
                                color: "white"
                            }
                            Text {
                                renderType: Text.NativeRendering
                                text: tile.h ? "Ep " + tile.h.ep : ""
                                font.family: root.textFontFamily; font.pixelSize: 10
                                color: "white"; opacity: 0.6
                            }
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selectAnime(tile.h.id, tile.h.title); root.focusInput() }
                        }
                    }
                }
            }

            // paused shows
            Text {
                renderType: Text.NativeRendering
                x: 10; y: 174
                text: "Continue Watching"
                font.family: root.textFontFamily; font.pixelSize: 13; font.bold: true
                color: "white"; opacity: 0.95
            }
            Row {
                x: 6; y: 198
                spacing: 8
                Repeater {
                    model: root.pausedRows.slice(0, 4)
                    delegate: Item {
                        id: card
                        required property var modelData
                        width: 134; height: 82

                        AnimeCover {
                            anchors.fill: parent; radius: 14
                            source: root.coverFor(card.modelData.id)
                            label: card.modelData.title
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 14
                            gradient: Gradient {
                                GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, cardMouse.containsMouse ? 0.0 : 0.1) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.78) }
                            }
                        }
                        Column {
                            x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                            width: parent.width - 20
                            spacing: 0
                            Text {
                                renderType: Text.NativeRendering
                                width: parent.width
                                text: card.modelData.title
                                elide: Text.ElideRight
                                font.family: root.textFontFamily; font.pixelSize: 11
                                color: "white"
                            }
                            Text {
                                renderType: Text.NativeRendering
                                text: "ep " + card.modelData.ep + " · " + root.fmtTime(card.modelData.pos)
                                font.family: root.textFontFamily; font.pixelSize: 10
                                color: "white"; opacity: 0.6
                            }
                        }
                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selectAnime(card.modelData.id, card.modelData.title); root.focusInput() }
                        }
                    }
                }
            }
            Text {
                renderType: Text.NativeRendering
                x: 10; y: 226
                visible: root.pausedRows.length === 0
                text: root.history.length === 0 ? "Shows you watch will show up here"
                      : "Nothing paused. Press c in mpv to save your spot."
                font.family: root.textFontFamily; font.pixelSize: 12
                color: "white"; opacity: 0.3
            }
        }

        // ───────────────────────── SEARCH ─────────────────────────
        Item {
            id: searchTab
            anchors.fill: parent
            visible: root.tab === "search"

            Rectangle {
                id: searchBox
                GlassSheen {}
                x: 8; y: 2
                width: parent.width - 16; height: 32; radius: 16
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 1

                Text {
                    renderType: Text.NativeRendering
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: root.iconFontFamily
                    font.pixelSize: 13
                    color: "white"; opacity: 0.4
                }
                Text {
                    renderType: Text.NativeRendering
                    x: 40; anchors.verticalCenter: parent.verticalCenter
                    text: "Search anime…"
                    visible: searchInput.text.length === 0
                    font.family: root.textFontFamily; font.pixelSize: 13
                    color: "white"; opacity: 0.22
                }
                Text {
                    id: spinner
                    renderType: Text.NativeRendering
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: root.iconFontFamily
                    font.pixelSize: 13
                    color: "white"; opacity: 0.5
                    visible: root.searching || root.loadingEps || root.playing
                    RotationAnimator on rotation {
                        from: 0; to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: spinner.visible
                    }
                }
            }

            GridView {
                id: resultsGrid
                anchors.top: searchBox.bottom; anchors.topMargin: 6
                anchors.bottom: parent.bottom
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 6; anchors.rightMargin: 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / root.searchCols)
                cellHeight: 122
                model: root.results

                delegate: Item {
                    id: resItem
                    required property var modelData
                    required property int index
                    readonly property bool isCursor: index === root.resultIndex
                    width: resultsGrid.cellWidth
                    height: resultsGrid.cellHeight

                    AnimeCover {
                        x: 5; y: 2
                        width: parent.width - 10; height: 92
                        radius: 14
                        source: resItem.modelData.cover
                        label: resItem.modelData.title
                    }
                    Rectangle {
                        x: 5; y: 2
                        width: parent.width - 10; height: 92
                        radius: 14
                        color: resMouse.containsMouse && !resItem.isCursor ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                        border.width: resItem.isCursor ? 2 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.85)
                    }
                    Text {
                        renderType: Text.NativeRendering
                        x: 7; y: 98
                        width: parent.width - 14
                        text: resItem.modelData.title
                        elide: Text.ElideRight
                        font.family: root.textFontFamily; font.pixelSize: 11
                        color: "white"
                        opacity: resItem.isCursor ? 1.0 : 0.7
                    }
                    MouseArea {
                        id: resMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.resultIndex = resItem.index; root.openRow(resItem.index); root.focusInput() }
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                anchors.horizontalCenter: parent.horizontalCenter
                y: 140
                width: parent.width - 48
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.results.length === 0 || root.searchError !== ""
                font.family: root.textFontFamily
                font.pixelSize: 12
                color: root.searchError !== "" ? Qt.rgba(1.0, 0.62, 0.55, 0.95) : "white"
                opacity: root.searchError !== "" ? 1.0 : 0.3
                text: root.searchError !== "" ? root.searchError
                      : (root.searching ? "Searching…"
                         : (root.query.trim().length >= 2 ? "No results" : "Type to search anime"))
            }
        }

        // ───────────────────────── LIST ─────────────────────────
        Item {
            id: listTab
            anchors.fill: parent
            visible: root.tab === "list"

            Text {
                renderType: Text.NativeRendering
                x: 16; y: 8
                text: "History"
                font.family: root.textFontFamily; font.pixelSize: 13; font.bold: true
                color: "white"; opacity: 0.95
            }

            ListView {
                id: resultsList
                x: 6; y: 32
                width: root.resultsWidth - 6
                height: parent.height - 36
                leftMargin: 2; rightMargin: 2; topMargin: 0; bottomMargin: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.listRows

                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index

                    readonly property bool isCursor: index === root.listIndex
                    readonly property bool isOpen: modelData.id === root.selectedId

                    width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                    height: 60

                    // swipe-left-to-delete (same mechanism as the notification center)
                    readonly property bool canDelete: modelData.ep !== ""
                    property real dragX: 0
                    property bool dragging: false
                    property bool pendingDismiss: false
                    readonly property real maxSwipe: -88
                    readonly property real dismissThreshold: -56

                    Behavior on dragX {
                        enabled: !rowItem.dragging
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutQuart
                            onRunningChanged: {
                                if (!running && rowItem.pendingDismiss) {
                                    rowItem.pendingDismiss = false
                                    root.deleteHistory(rowItem.modelData.id)
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        y: 1
                        width: Math.max(0, -rowItem.dragX)
                        height: 56
                        radius: 18
                        clip: true
                        color: Qt.rgba(0.86, 0.26, 0.26, 1)
                        visible: rowItem.dragX < -4

                        AnimeIcon {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "trash"; sz: 15; col: "white"
                            opacity: Math.min(1, -rowItem.dragX / -rowItem.dismissThreshold)
                        }
                    }

                    Rectangle {
                        GlassSheen { visible: rowItem.isCursor || rowItem.isOpen || rowMouse.containsMouse }
                        x: rowItem.dragX
                        y: 1
                        width: parent.width
                        height: 56
                        radius: 18
                        color: rowItem.isCursor
                               ? Qt.rgba(1, 1, 1, root.zone === "results" ? 0.12 : 0.07)
                               : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06)
                                  : (rowItem.isOpen ? Qt.rgba(1, 1, 1, 0.05) : "transparent"))
                        Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                        AnimeCover {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 38; height: 48
                            radius: 9
                            source: root.coverFor(rowItem.modelData.id)
                            label: rowItem.modelData.title
                        }

                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 56
                            anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                renderType: Text.NativeRendering
                                width: parent.width
                                text: rowItem.modelData.title
                                elide: Text.ElideRight
                                font.family: root.textFontFamily
                                font.pixelSize: 13
                                color: "white"
                                opacity: rowItem.isCursor || rowItem.isOpen ? 0.95 : 0.68
                            }
                            Text {
                                renderType: Text.NativeRendering
                                visible: rowItem.modelData.ep !== ""
                                width: parent.width
                                text: rowItem.modelData.resume
                                      ? "Paused: ep " + rowItem.modelData.resume.ep + " at " + root.fmtTime(rowItem.modelData.resume.pos)
                                      : "Last watched: ep " + rowItem.modelData.ep
                                elide: Text.ElideRight
                                font.family: root.textFontFamily
                                font.pixelSize: 10
                                color: "white"
                                opacity: 0.4
                            }
                        }
                    }

                    // Sits outside the moving card so the cursor position
                    // doesn't shift while dragging (1:1 swipe).
                    MouseArea {
                        id: rowMouse
                        x: 0; y: 1
                        width: rowItem.width
                        height: 56
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        property real pressX: 0
                        property bool moved: false

                        onPressed: function(mouse) {
                            pressX = mouse.x
                            moved = false
                            rowItem.dragging = true
                        }

                        onPositionChanged: function(mouse) {
                            if (!pressed || !rowItem.canDelete) return
                            const delta = Math.min(0, mouse.x - pressX)
                            if (!moved && Math.abs(delta) > 6) moved = true
                            if (moved) rowItem.dragX = Math.max(rowItem.maxSwipe, delta)
                        }

                        onReleased: {
                            rowItem.dragging = false
                            if (moved) {
                                if (rowItem.dragX <= rowItem.dismissThreshold) {
                                    rowItem.pendingDismiss = true
                                    rowItem.dragX = -rowItem.width
                                } else {
                                    rowItem.dragX = 0
                                }
                                root.focusInput()
                                return
                            }
                            root.openRow(rowItem.index)
                            root.focusInput()
                        }

                        onCanceled: {
                            rowItem.dragging = false
                            rowItem.dragX = 0
                        }
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                x: 6; y: 120
                width: root.resultsWidth - 6
                horizontalAlignment: Text.AlignHCenter
                visible: root.listRows.length === 0
                text: "Nothing watched yet"
                font.family: root.textFontFamily; font.pixelSize: 12
                color: "white"; opacity: 0.3
            }

            // thin divider between history and episodes
            Rectangle {
                x: root.resultsWidth + 10; y: 10
                width: 1; height: parent.height - 20
                color: Qt.rgba(1, 1, 1, 0.09)
            }

            // right: episodes
            Item {
                id: epPanel
                x: root.resultsWidth + 18
                width: parent.width - x - 8
                height: parent.height

                Item {
                    id: epHeader
                    width: parent.width
                    height: 46

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.selectedTitle !== "" ? root.selectedTitle : "Episodes"
                            font.family: root.textFontFamily
                            font.pixelSize: 15
                            font.bold: true
                            color: "white"
                            opacity: 0.95
                        }
                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            elide: Text.ElideRight
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            color: "white"
                            opacity: 0.4
                            text: root.selectedId === "" ? "Pick an anime on the left"
                                  : (root.loadingEps ? "Loading episodes…"
                                     : (root.episodes.length + (root.episodes.length === 1 ? " episode" : " episodes")))
                        }
                    }
                }

                GridView {
                    id: epGrid
                    anchors.top: epHeader.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 2
                    leftMargin: 4; rightMargin: 4; topMargin: 4; bottomMargin: 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: Math.floor((width - leftMargin - rightMargin) / root.epCols)
                    cellHeight: 36
                    model: root.episodes

                    delegate: Item {
                        id: epItem
                        required property var modelData
                        required property int index

                        readonly property bool isCursor: index === root.epIndex
                        readonly property bool isWatched: index <= root.watchedIdx

                        width: epGrid.cellWidth
                        height: epGrid.cellHeight

                        Rectangle {
                            GlassSheen {}
                            anchors.fill: parent
                            anchors.margins: 2.5
                            radius: 14
                            color: epItem.isCursor
                                   ? Qt.rgba(1, 1, 1, root.zone === "episodes" ? 0.18 : 0.10)
                                   : (epMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12)
                                      : Qt.rgba(1, 1, 1, epItem.isWatched ? 0.03 : 0.07))
                            border.width: 1
                            border.color: epItem.isCursor && root.zone === "episodes"
                                          ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(1, 1, 1, 0.08)
                            Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: epItem.modelData
                                font.family: root.textFontFamily
                                font.pixelSize: 12
                                color: "white"
                                opacity: epItem.isCursor ? 1.0 : (epItem.isWatched ? 0.3 : 0.65)
                            }

                            MouseArea {
                                id: epMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.epIndex = epItem.index; root.zone = "episodes"; root.focusInput() }
                                onDoubleClicked: { root.epIndex = epItem.index; root.playSelected() }
                            }
                        }
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 20
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.selectedId !== "" && !root.loadingEps && root.episodes.length === 0
                    text: root.errorText !== "" ? root.errorText : "No episodes found"
                    font.family: root.textFontFamily
                    font.pixelSize: 12
                    color: Qt.rgba(1.0, 0.62, 0.55, 0.95)
                }
            }
        }

        // The one text input. It sits in the Search tab's bar; on the other tabs it
        // shrinks to nothing but keeps keyboard focus so every key keeps working.
        TextInput {
            id: searchInput
            renderType: TextInput.NativeRendering
            x: root.tab === "search" ? 40 : 0
            y: 2
            width: root.tab === "search" ? bodyArea.width - 16 - 80 : 1
            height: 32
            opacity: root.tab === "search" ? 1 : 0
            color: "white"
            font.pixelSize: 13
            font.family: root.textFontFamily
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnPress: true
            clip: true

            onTextChanged: {
                root.query = text
                root.resultIndex = 0
                root.zone = "results"
                root.searchError = ""
                if (text.length > 0 && root.tab !== "search") root.tab = "search"
                if (text.trim().length < 2) {
                    searchDebounce.stop()
                    root.results = []
                    root.searching = false
                } else {
                    root.searching = true
                    searchDebounce.restart()
                }
            }

            // keys without their own handler below (letters, backspace, ...)
            Keys.onPressed: (event) => {
                if (root.cancelCountdown()) event.accepted = true
            }

            Keys.onEscapePressed: {
                if (root.cancelCountdown()) return
                if (root.tab === "list" && root.zone === "episodes") root.zone = "results"
                else if (root.tab === "search" && text.length > 0) text = ""
                else if (root.tab !== "home") root.tab = "home"
                else root.closeRequested()
            }
            Keys.onReturnPressed: { if (!root.cancelCountdown()) root.activate() }
            Keys.onEnterPressed: { if (!root.cancelCountdown()) root.activate() }
            Keys.onTabPressed: { if (!root.cancelCountdown()) root.toggleMode() }
            Keys.onUpPressed: {
                if (root.cancelCountdown()) return
                if (root.tab === "search") root.moveRow(-root.searchCols)
                else if (root.tab === "list") {
                    if (root.zone === "results") root.moveRow(-1)
                    else root.moveEp(-root.epCols)
                }
            }
            Keys.onDownPressed: {
                if (root.cancelCountdown()) return
                if (root.tab === "search") root.moveRow(root.searchCols)
                else if (root.tab === "list") {
                    if (root.zone === "results") root.moveRow(1)
                    else root.moveEp(root.epCols)
                }
            }
            Keys.onLeftPressed: {
                if (root.cancelCountdown()) return
                if (root.tab === "search") root.moveRow(-1)
                else if (root.tab === "list" && root.zone === "episodes") {
                    if (root.epIndex % root.epCols === 0) root.zone = "results"
                    else root.moveEp(-1)
                }
            }
            Keys.onRightPressed: {
                if (root.cancelCountdown()) return
                if (root.tab === "search") root.moveRow(1)
                else if (root.tab === "list") {
                    if (root.zone === "episodes") root.moveEp(1)
                    else if (root.episodes.length > 0) root.zone = "episodes"
                }
            }
        }
    }

    // ── footer ────────────────────────────────────────────────────────────────
    Item {
        x: root.railWidth
        y: root.topInset + root.panelsHeight
        width: root.width - root.railWidth
        height: root.footerHeight

        Row {
            id: modePills
            visible: root.footerText === ""      // the footer shows status / the countdown while one is active
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: [ { key: "sub", label: "Sub" }, { key: "dub", label: "Dub" } ]
                delegate: Rectangle {
                    GlassSheen {}
                    required property var modelData
                    readonly property bool active: root.mode === modelData.key
                    width: 46; height: 26; radius: 13
                    color: active ? Qt.rgba(1, 1, 1, 0.14) : (pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                    border.width: 1
                    border.color: active ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.15)
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: root.textFontFamily
                        font.pixelSize: 12
                        color: "white"
                        opacity: parent.active ? 1.0 : 0.5
                    }
                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.mode = modelData.key; root.focusInput() }
                    }
                }
            }

            // Auto: play the next episode when one ends at 90%+. Green = on.
            Rectangle {
                id: autoBtn
                GlassSheen {}
                width: 60; height: 26; radius: 13
                color: root.autoplay
                       ? Qt.rgba(0.35, 0.85, 0.5, autoMouse.containsMouse ? 0.24 : 0.16)
                       : (autoMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                border.width: 1
                border.color: root.autoplay ? Qt.rgba(0.35, 0.85, 0.5, 0.55) : Qt.rgba(1, 1, 1, 0.15)
                Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
                Behavior on border.color { ColorAnimation { duration: IslandMotion.micro } }

                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    AnimeIcon {
                        kind: "play"; sz: 10
                        col: root.autoplay ? Qt.rgba(0.45, 0.92, 0.6, 1.0) : "white"
                        opacity: root.autoplay ? 1.0 : 0.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        renderType: Text.NativeRendering
                        text: "Auto"
                        font.family: root.textFontFamily
                        font.pixelSize: 12
                        color: root.autoplay ? Qt.rgba(0.45, 0.92, 0.6, 1.0) : "white"
                        opacity: root.autoplay ? 1.0 : 0.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: autoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.toggleAutoplay(); root.focusInput() }
                }
            }

            // hold to clear all history; the bar fills while you hold
            Rectangle {
                id: clearBtn
                GlassSheen {}
                visible: root.history.length > 0
                property real hold: 0
                width: 66; height: 26; radius: 13
                color: clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * clearBtn.hold
                    radius: parent.radius
                    visible: clearBtn.hold > 0
                    color: Qt.rgba(0.86, 0.26, 0.26, 0.6)
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    AnimeIcon {
                        kind: "trash"; sz: 11; col: "white"
                        opacity: 0.5 + 0.5 * clearBtn.hold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        renderType: Text.NativeRendering
                        text: clearMouse.pressed ? "Hold…" : "Clear"
                        font.family: root.textFontFamily
                        font.pixelSize: 12
                        color: "white"
                        opacity: 0.5 + 0.5 * clearBtn.hold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                NumberAnimation {
                    id: holdAnim
                    target: clearBtn
                    property: "hold"
                    from: 0; to: 1
                    duration: 1200
                    onStopped: {
                        if (clearBtn.hold >= 1) {
                            root.clearHistory()
                            clearBtn.hold = 0
                        }
                    }
                }

                NumberAnimation {
                    id: releaseAnim
                    target: clearBtn
                    property: "hold"
                    to: 0
                    duration: 180
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: { releaseAnim.stop(); holdAnim.restart(); root.focusInput() }
                    onReleased: { if (holdAnim.running) { holdAnim.stop(); releaseAnim.restart() } }
                    onCanceled: { if (holdAnim.running) { holdAnim.stop(); releaseAnim.restart() } }
                }
            }
        }

        Text {
            renderType: Text.NativeRendering
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: actionRow.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: root.textFontFamily
            font.pixelSize: 11
            color: root.countdown > 0 ? Qt.rgba(0.45, 0.92, 0.6, 1.0)
                   : (root.playing ? "white"
                      : (root.errorText !== "" ? Qt.rgba(1.0, 0.62, 0.55, 0.95) : Qt.rgba(1, 1, 1, 0.55)))
            visible: root.footerText !== ""
            text: root.footerText
        }

        // Continue watching is always on the right; it opens the List tab on your latest show
        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            AnimeButton {
                visible: root.history.length > 0 && root.countdown <= 0
                label: "Continue watching"; iconKind: "clock"; labelSize: 11
                fontFamily: root.textFontFamily
                onClicked: { root.continueWatching(); root.focusInput() }
            }

            AnimeButton {
                id: playBtn
                active: root.episodes.length > 0 && !root.playing
                primary: true
                iconKind: "play"
                fontFamily: root.textFontFamily
                label: root.episodes.length > 0 ? (root.resumeHere ? "Resume ep " : "Play ep ") + root.episodes[root.epIndex] : "Play"
                onClicked: { root.playSelected(); root.focusInput() }
            }
        }
    }

    // any click while counting down cancels it (the click still goes through)
    MouseArea {
        anchors.fill: parent
        z: 100
        enabled: root.countdown > 0
        propagateComposedEvents: true
        onPressed: function(mouse) {
            root.cancelCountdown()
            mouse.accepted = false
        }
    }
}
