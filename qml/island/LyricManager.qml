import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    width: 0
    height: 0

readonly property string currentLyric:  _currentLyric
    readonly property bool   isSynced:      _isSynced
    readonly property string backendStatus: _backendStatus
    readonly property var    lines:         _lines
    readonly property string fullPlainText: _fullPlainText

    function fetch(artist, title, inlineLyricsRaw) {
        const nextArtist = artist || ""
        const nextTitle  = title  || ""

        // Already have valid data loaded for this exact track — skip reload entirely.
        if (nextArtist === _artist && nextTitle === _title
                && _backendStatus !== "idle" && _backendStatus !== "loading") {
            return
        }

        _artist   = nextArtist
        _title    = nextTitle
        _inline   = inlineLyricsRaw || ""
        _lines    = []
        _activeIndex   = -1
        _currentLyric  = ""
        _isSynced      = false
        _backendStatus = "loading"

        if (_artist === "" && _title === "") {
            _backendStatus = "idle"
            return
        }

        cacheReader.path = _cacheDir + "/" + _cacheKey(_artist, _title) + ".lrc"
        cacheReader.reload()
    }

    function clearCache() {
        const path = _cacheDir + "/" + _cacheKey(_artist, _title) + ".lrc"
        clearProc.command = ["rm", "-f", path]
        clearProc.running = true

        _lines         = []
        _activeIndex   = -1
        _currentLyric  = ""
        _isSynced      = false
        _backendStatus = "missing"
    }

    function setPosition(positionMs) {
        if (!_isSynced || _lines.length === 0) return
        const idx = _findIndex(positionMs)
        if (idx === _activeIndex) return
        _activeIndex  = idx
        _currentLyric = idx >= 0 ? (_lines[idx].text || "") : ""
    }

function applyManual(lrcOrPlainText, artist, title) {
        _artist = artist || _artist
        _title  = title  || _title

        const parsed = _parseLrc(lrcOrPlainText)
        if (parsed.length > 0) {
            _lines         = parsed
            _isSynced      = true
            _activeIndex   = -1
            _currentLyric  = ""
            _fullPlainText = ""
            _backendStatus = "ready"
        } else {
            _lines         = []
            _isSynced      = false
            _currentLyric  = lrcOrPlainText.split("\n")[0].trim()
            _fullPlainText = lrcOrPlainText
            _backendStatus = "ready"
        }
        _saveCache(lrcOrPlainText)
    }

property string _artist:        ""
    property string _title:         ""
    property string _inline:        ""
    property var    _lines:         []
    property int    _activeIndex:   -1
    property string _currentLyric:  ""
    property string _fullPlainText: ""
    property bool   _isSynced:      false
    property string _backendStatus: "idle"

    readonly property string _cacheDir: (Quickshell.env("HOME") || "/tmp") + "/.cache/tide-island/lyrics"

    function _cacheKey(artist, title) {
        function slug(s) {
            return (s || "").toLowerCase()
                            .replace(/[^a-z0-9]+/g, "-")
                            .replace(/^-+|-+$/g, "")
        }
        return slug(artist) + "-" + slug(title)
    }

    function _findIndex(posMs) {
        if (_lines.length === 0) return -1
        let idx = 0
        for (let i = 0; i < _lines.length; i++) {
            if (_lines[i].time <= posMs) idx = i
            else break
        }
        return idx
    }

    function _parseLrc(lrcText) {
        const result = []
        const re = /\[(\d{2}):(\d{2})[\.:](\d{2,3})\](.*)/
        const lines = lrcText.split("\n")
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

    function _applyLrc(lrcText) {
        const parsed = _parseLrc(lrcText)
        if (parsed.length === 0) {
            _useFallback()
            return
        }
        _lines         = parsed
        _isSynced      = true
        _activeIndex   = -1
        _currentLyric  = ""
        _backendStatus = "ready"
    }

function _useFallback() {
    if (_inline !== "") {
        const parsed = _parseLrc(_inline)
        if (parsed.length > 0) {
            _lines         = parsed
            _isSynced      = true
            _activeIndex   = -1
            _currentLyric  = ""
            _fullPlainText = ""
            _backendStatus = "ready"
            return
        }
    }
    _lines         = []
    _isSynced      = false
    _currentLyric  = ""
    _fullPlainText = ""
    _backendStatus = "missing"
}

    // ── Stage 1: cache read ──────────────────────────────────────────────────
    FileView {
        id: cacheReader
        onLoadedChanged: {
            if (!loaded) return
            const text = cacheReader.text()
            if (text && text.trim() !== "")
                root._applyLrc(text)
            else
                root._fetchFromLrcLib()
        }
        onLoadFailed: {
            if (error !== FileViewError.NoError)
                root._fetchFromLrcLib()
        }
    }

    // ── Stage 2: LRCLib via curl ─────────────────────────────────────────────
    function _fetchFromLrcLib() {
        const url = "https://lrclib.net/api/get"
                  + "?artist_name=" + encodeURIComponent(_artist)
                  + "&track_name="  + encodeURIComponent(_title)
        curlProc.command = [
            "curl", "-s", "-f",
            "--max-time", "15",
            "-H", "Lrclib-Client: tide-island/1.0 (quickshell)",
            url
        ]
        curlProc.running = true
    }

    Process {
        id: curlProc
        stdout: StdioCollector {
            id: curlOut
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root._useFallback()
                return
            }
            try {
                const data = JSON.parse(curlOut.text)
                if (data.syncedLyrics && data.syncedLyrics.trim() !== "") {
                    root._saveCache(data.syncedLyrics)
                    root._applyLrc(data.syncedLyrics)
} else if (data.plainLyrics && data.plainLyrics.trim() !== "") {
                    root._lines        = []
                    root._isSynced     = false
                    root._currentLyric = data.plainLyrics.split("\n")[0].trim()
                    root._fullPlainText = data.plainLyrics
                    root._backendStatus = "ready"
                } else {
                    root._useFallback()
                }
            } catch(e) {
                root._useFallback()
            }
        }
    }

    // ── Stage 3: cache write ─────────────────────────────────────────────────
    // We base64-encode the LRC text and decode it on the shell side with a
    // single `sh -c` invocation. This avoids any Process stdin lifecycle
    // complexity (no DataStream type exists in Quickshell.Io — write() lives
    // directly on Process, but coordinating close-then-exit is fragile, so
    // we sidestep it entirely by passing the payload as an argument).
    function _saveCache(lrcContent) {
        const path = _cacheDir + "/" + _cacheKey(_artist, _title) + ".lrc"
        const b64  = Qt.btoa(lrcContent)
        saveProc.command = [
            "sh", "-c",
            "mkdir -p " + JSON.stringify(_cacheDir) + " && echo " + b64 + " | base64 -d > " + JSON.stringify(path) + " && date >> " + JSON.stringify(_cacheDir + "/debug.log") + " && echo SAVED >> " + JSON.stringify(_cacheDir + "/debug.log") + " || echo FAILED >> " + JSON.stringify(_cacheDir + "/debug.log")
        ]
        saveProc.running = true
    }

    Process {
        id: saveProc
    }

    Process {
        id: clearProc
    }
}
