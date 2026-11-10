import QtQuick
import Quickshell
import Quickshell.Io
import "../shared"

// AnimeHub: stacked under the search pill when you type "anime".
// Left: search results + watch history. Right: episode grid.
// All network work goes through scripts/ani-backend (copied from ani-cli's scraper).
//
// Keys (focus always stays in the search box):
//   type            search (debounced)
//   Up / Down       move through results, or through the episode grid
//   Right (at end)  jump into the episode grid   |   Left (first column) jump back
//   Enter           open the highlighted anime   |   play the highlighted episode
//   Tab             toggle sub / dub
//   Esc             back to results -> clear search -> close

Item {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""

    signal closeRequested()

    // ── layout ────────────────────────────────────────────────────────────────
    readonly property int capsuleWidth: 640
    readonly property int bannerHeight: 28
    readonly property int headerHeight: 46
    readonly property int panelsHeight: 290
    readonly property int footerHeight: 46
    readonly property int resultsWidth: 236
    readonly property int epCols: 6
    readonly property bool showBanner: versionState === "outdated"
    readonly property int capsuleHeight: (showBanner ? bannerHeight : 0) + headerHeight + panelsHeight + footerHeight

    width: capsuleWidth
    height: capsuleHeight
    implicitWidth: capsuleWidth
    implicitHeight: capsuleHeight

    // ── state ─────────────────────────────────────────────────────────────────
    readonly property string backend: Quickshell.shellDir + "/scripts/ani-backend"

    property string mode: "sub"            // "sub" | "dub"
    property string zone: "results"        // "results" | "episodes"
    property string query: ""

    property var    results: []            // [{ id, title }]
    property var    history: []            // [{ ep, id, title }], most recent first
    property int    resultIndex: 0

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

    // results first, then history (history rows for anime already in results are folded in)
    readonly property var rows: {
        const q = query.trim().toLowerCase()
        const lastEp = {}
        for (let i = 0; i < history.length; i++) lastEp[history[i].id] = history[i].ep

        let out = []
        const seen = {}
        for (let i = 0; i < results.length; i++) {
            seen[results[i].id] = true
            out.push({ id: results[i].id, title: results[i].title, section: "Results", ep: lastEp[results[i].id] || "", resume: resume[results[i].id] || null })
        }
        for (let j = 0; j < history.length; j++) {
            const h = history[j]
            if (seen[h.id]) continue
            if (q !== "" && h.title.toLowerCase().indexOf(q) < 0) continue
            out.push({ id: h.id, title: h.title, section: "History", ep: h.ep, resume: resume[h.id] || null })
        }
        return out
    }

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
        resultIndex = Math.max(0, Math.min(rows.length - 1, resultIndex + d))
        resultsList.positionViewAtIndex(resultIndex, ListView.Contain)
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
        loadingEps = true
        runEpisodes()
    }

    function openRow(i) {
        const row = rows[i]
        if (!row) return
        resultIndex = i
        selectAnime(row.id, row.title)
    }

    function continueWatching() {
        if (history.length === 0) return
        selectAnime(history[0].id, history[0].title)
    }

    function activate() {
        if (zone === "results") {
            if (searchDebounce.running) {      // user hit Enter before the debounce fired
                searchDebounce.stop()
                runSearch()
                return
            }
            if (rows.length > 0) openRow(resultIndex)
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
                    if (p.length >= 2) parsed.push({ id: p[0], title: p.slice(1).join("\t") })
                }
                results = parsed
            }
            resultIndex = 0
            Qt.callLater(() => resultsList.positionViewAtBeginning())
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
        resultIndex = Math.max(0, Math.min(resultIndex, rows.length - 1))
    }

    function clearHistory() {
        Quickshell.execDetached(["bash", backend, "clear"])
        history = []
        resume = ({})
        watchedIdx = -1
        resultIndex = Math.max(0, Math.min(resultIndex, rows.length - 1))
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
    Column {
        anchors.fill: parent

        // update banner
        Rectangle {
            width: parent.width
            height: root.showBanner ? root.bannerHeight : 0
            visible: root.showBanner
            color: Qt.rgba(1.0, 0.76, 0.28, 0.10)

            Row {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    renderType: Text.NativeRendering
                    text: "\uf071"
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

        // search row
        Item {
            width: parent.width
            height: root.headerHeight

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10

                Text {
                    renderType: Text.NativeRendering
                    text: "\uf002"
                    font.family: root.iconFontFamily
                    font.pixelSize: 13
                    color: "white"
                    opacity: 0.4
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchInput
                    width: parent.width - 60
                    height: 30
                    anchors.verticalCenter: parent.verticalCenter
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
                        if (root.zone === "episodes") root.zone = "results"
                        else if (text.length > 0) text = ""
                        else root.closeRequested()
                    }
                    Keys.onReturnPressed: { if (!root.cancelCountdown()) root.activate() }
                    Keys.onEnterPressed: { if (!root.cancelCountdown()) root.activate() }
                    Keys.onTabPressed: { if (!root.cancelCountdown()) root.toggleMode() }
                    Keys.onUpPressed: {
                        if (root.cancelCountdown()) return
                        if (root.zone === "results") root.moveRow(-1)
                        else root.moveEp(-root.epCols)
                    }
                    Keys.onDownPressed: {
                        if (root.cancelCountdown()) return
                        if (root.zone === "results") root.moveRow(1)
                        else root.moveEp(root.epCols)
                    }
                    Keys.onLeftPressed: (event) => {
                        if (root.cancelCountdown()) return
                        if (root.zone === "episodes") {
                            if (root.epIndex % root.epCols === 0) root.zone = "results"
                            else root.moveEp(-1)
                        } else {
                            event.accepted = false      // normal caret movement
                        }
                    }
                    Keys.onRightPressed: (event) => {
                        if (root.cancelCountdown()) return
                        if (root.zone === "episodes") {
                            root.moveEp(1)
                        } else if (root.episodes.length > 0 && cursorPosition >= text.length) {
                            root.zone = "episodes"
                        } else {
                            event.accepted = false
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search anime…"
                        color: "white"
                        opacity: 0.22
                        font.pixelSize: 13
                        font.family: root.textFontFamily
                        visible: searchInput.text.length === 0
                    }
                }

                Text {
                    id: spinner
                    renderType: Text.NativeRendering
                    text: "\uf110"
                    font.family: root.iconFontFamily
                    font.pixelSize: 13
                    color: "white"
                    opacity: 0.5
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.searching || root.loadingEps || root.playing
                    RotationAnimator on rotation {
                        from: 0; to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: spinner.visible
                    }
                }
            }
        }

        // panels
        Item {
            width: parent.width
            height: root.panelsHeight

            // left: results + history
            Item {
                id: leftPanel
                width: root.resultsWidth
                height: parent.height

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                ListView {
                    id: resultsList
                    anchors.fill: parent
                    anchors.margins: 6
                    anchors.rightMargin: 7
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows

                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index

                        readonly property bool showSection: index === 0 || root.rows[index - 1].section !== modelData.section
                        readonly property bool isCursor: index === root.resultIndex
                        readonly property bool isOpen: modelData.id === root.selectedId

                        width: ListView.view.width
                        height: (showSection ? 24 : 0) + 42

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

                        Text {
                            renderType: Text.NativeRendering
                            visible: rowItem.showSection
                            text: rowItem.modelData.section.toUpperCase()
                            font.family: root.textFontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            color: "white"
                            opacity: 0.25
                            x: 10
                            y: 8
                        }

                        Rectangle {
                            anchors.right: parent.right
                            y: rowItem.showSection ? 24 : 0
                            width: Math.max(0, -rowItem.dragX)
                            height: 40
                            radius: 9
                            clip: true
                            color: Qt.rgba(0.86, 0.26, 0.26, 1)
                            visible: rowItem.dragX < -4

                            Text {
                                renderType: Text.NativeRendering
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf1f8"
                                font.family: root.iconFontFamily
                                font.pixelSize: 14
                                color: "white"
                                opacity: Math.min(1, -rowItem.dragX / -rowItem.dismissThreshold)
                            }
                        }

                        Rectangle {
                            x: rowItem.dragX
                            y: rowItem.showSection ? 24 : 0
                            width: parent.width
                            height: 40
                            radius: 9
                            color: rowItem.isCursor
                                   ? Qt.rgba(1, 1, 1, root.zone === "results" ? 0.12 : 0.07)
                                   : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06)
                                      : (rowItem.isOpen ? Qt.rgba(1, 1, 1, 0.05) : "transparent"))
                            Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

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
                                    opacity: 0.32
                                }
                            }

                        }

                        // Sits outside the moving card so the cursor position
                        // doesn't shift while dragging (1:1 swipe).
                        MouseArea {
                            id: rowMouse
                            x: 0
                            y: rowItem.showSection ? 24 : 0
                            width: rowItem.width
                            height: 40
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

                // empty / error states
                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    width: parent.width - 36
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.rows.length === 0 || root.searchError !== ""
                    font.family: root.textFontFamily
                    font.pixelSize: 12
                    color: root.searchError !== "" ? Qt.rgba(1.0, 0.62, 0.55, 0.95) : "white"
                    opacity: root.searchError !== "" ? 1.0 : 0.3
                    text: root.searchError !== "" ? root.searchError
                          : (root.searching ? "Searching…"
                             : (root.query.trim().length >= 2 ? "No results" : "Type to search anime"))
                }
            }

            // right: episodes
            Item {
                anchors.left: leftPanel.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Item {
                    id: epHeader
                    width: parent.width
                    height: 46

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.selectedTitle !== "" ? root.selectedTitle : "Episodes"
                            font.family: root.textFontFamily
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: "white"
                            opacity: 0.95
                        }
                        Text {
                            renderType: Text.NativeRendering
                            width: parent.width
                            elide: Text.ElideRight
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            color: "white"
                            opacity: 0.32
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
                    anchors.margins: 10
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: Math.floor(width / root.epCols)
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
                            anchors.fill: parent
                            anchors.margins: 2.5
                            radius: 8
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

        // footer
        Item {
            width: parent.width
            height: root.footerHeight

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            Row {
                id: modePills
                visible: root.countdown <= 0      // the footer is the countdown while it runs
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: [ { key: "sub", label: "Sub" }, { key: "dub", label: "Dub" } ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root.mode === modelData.key
                        width: 52; height: 26; radius: 13
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
                    width: 64; height: 26; radius: 13
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
                        Text {
                            renderType: Text.NativeRendering
                            text: "\uf04b"
                            font.family: root.iconFontFamily
                            font.pixelSize: 10
                            color: root.autoplay ? Qt.rgba(0.45, 0.92, 0.6, 1.0) : "white"
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
                    visible: root.history.length > 0
                    property real hold: 0
                    width: 72; height: 26; radius: 13
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
                        Text {
                            renderType: Text.NativeRendering
                            text: "\uf1f8"
                            font.family: root.iconFontFamily
                            font.pixelSize: 11
                            color: "white"
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
                anchors.leftMargin: root.countdown > 0 ? 14 : modePills.width + 28
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
                opacity: root.footerText !== "" ? 1.0 : 0
                text: root.footerText
            }

            Row {
                id: actionRow
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    visible: root.history.length > 0 && root.countdown <= 0
                    width: contRow.width + 20
                    height: 28
                    radius: 8
                    color: contMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                    Row {
                        id: contRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            renderType: Text.NativeRendering
                            text: "\uf1da"
                            font.family: root.iconFontFamily
                            font.pixelSize: 11
                            color: "white"
                            opacity: 0.45
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            renderType: Text.NativeRendering
                            text: "Continue watching"
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            color: "white"
                            opacity: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: contMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.continueWatching(); root.focusInput() }
                    }
                }

                Rectangle {
                    readonly property bool canPlay: root.episodes.length > 0 && !root.playing
                    width: playRow.width + 28
                    height: 30
                    radius: 9
                    color: canPlay ? (playMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.13))
                                   : Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: canPlay ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.08)
                    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                    Row {
                        id: playRow
                        anchors.centerIn: parent
                        spacing: 7
                        Text {
                            renderType: Text.NativeRendering
                            text: "\uf04b"
                            font.family: root.iconFontFamily
                            font.pixelSize: 10
                            color: "white"
                            opacity: parent.parent.canPlay ? 0.9 : 0.3
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            renderType: Text.NativeRendering
                            text: root.episodes.length > 0 ? (root.resumeHere ? "Resume ep " : "Play ep ") + root.episodes[root.epIndex] : "Play"
                            font.family: root.textFontFamily
                            font.pixelSize: 12
                            color: "white"
                            opacity: parent.parent.canPlay ? 1.0 : 0.35
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.canPlay ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { root.playSelected(); root.focusInput() }
                    }
                }
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
