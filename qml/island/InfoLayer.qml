import QtQuick
import QtQuick.Controls
import Quickshell.Io
import IslandBackend
import "../shared"

Item {
    id: root

    property bool showCondition: false
    property string textFontFamily: "Inter Display"
    property string iconFontFamily: "JetBrainsMono Nerd Font"

    // ── Tab state ──────────────────────────────────────────────────────────
    property int activeTab: 0
    signal requestClose()

    // ── Weather state ──────────────────────────────────────────────────────
    property real   tempF:        0
    property string weatherDesc:  ""
    property int    weatherCode:  -1
    property bool   isDay:        true
    property real   windMph:      0
    property int    humidity:     0
    property real   feelsLikeF:   0
    property string displayCity:  ""
    property bool   wxLoading:    false
    property string wxError:      ""
    property var    forecastDates:   []
    property var    forecastMax:     []
    property var    forecastMin:     []
    property var    forecastCodes:   []
    property var    forecastPrecip:  []
    property real   geoLat: 0
    property real   geoLon: 0
    property string citySearch: ""

    // ── Calendar state ─────────────────────────────────────────────────────
    property int calMonth: new Date().getMonth()
    property int calYear:  new Date().getFullYear()
    property int todayD:   new Date().getDate()
    property int todayM:   new Date().getMonth()
    property int todayY:   new Date().getFullYear()

    readonly property var monthNames: ["January","February","March","April","May","June",
                                       "July","August","September","October","November","December"]

    ListModel { id: calModel }

    function updateCalendar(year, month) {
        calModel.clear()
        let firstDay   = new Date(year, month, 1)
        let startCell  = firstDay.getDay() === 0 ? 6 : firstDay.getDay() - 1
        let daysInMonth = new Date(year, month + 1, 0).getDate()
        let prevDays   = new Date(year, month, 0).getDate()
        for (let i = 0; i < 42; i++) {
            if (i < startCell)
                calModel.append({ day: prevDays - startCell + i + 1, cur: false, tod: false })
            else if (i < startCell + daysInMonth) {
                let d = i - startCell + 1
                calModel.append({ day: d, cur: true, tod: d === todayD && month === todayM && year === todayY })
            } else
                calModel.append({ day: i - startCell - daysInMonth + 1, cur: false, tod: false })
        }
    }

    // ── WMO helpers ────────────────────────────────────────────────────────
    function wmoIcon(code, day) {
        if (code === 0)  return day ? "☀" : "☾"
        if (code <= 2)   return "⛅"
        if (code === 3)  return "☁"
        if (code <= 48)  return "🌫"
        if (code <= 67)  return "🌧"
        if (code <= 77)  return "❄"
        if (code <= 82)  return "🌦"
        if (code <= 99)  return "⛈"
        return "☀"
    }
    function wmoDesc(code) {
        if (code === 0)  return "Clear"
        if (code === 1)  return "Mostly clear"
        if (code === 2)  return "Partly cloudy"
        if (code === 3)  return "Overcast"
        if (code <= 48)  return "Foggy"
        if (code <= 55)  return "Drizzle"
        if (code <= 67)  return "Rain"
        if (code <= 77)  return "Snow"
        if (code <= 82)  return "Showers"
        if (code <= 99)  return "Thunderstorm"
        return "Unknown"
    }
    function shortDay(dateStr) {
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][new Date(dateStr + "T12:00:00").getDay()]
    }

    // ── Processes ──────────────────────────────────────────────────────────
    Process {
        id: ipGeoProc
        command: ["curl", "-sf", "--max-time", "5", "http://ip-api.com/json/?fields=city,lat,lon,status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse(text.trim())
                    if (j.status === "success") {
                        root.displayCity = j.city
                        root.geoLat = j.lat
                        root.geoLon = j.lon
                        fetchWeather(j.lat, j.lon)
                    } else {
                        root.wxError = "Location unavailable"
                        root.wxLoading = false
                    }
                } catch(e) {
                    root.wxError = "Network error"
                    root.wxLoading = false
                }
            }
        }
    }

    Process {
        id: geocodeProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse(text.trim())
                    if (j.results && j.results.length > 0) {
                        let r = j.results[0]
                        root.displayCity = r.name + (r.country_code ? ", " + r.country_code : "")
                        root.geoLat = r.latitude
                        root.geoLon = r.longitude
                        fetchWeather(r.latitude, r.longitude)
                    } else {
                        root.wxError = "City not found"
                        root.wxLoading = false
                    }
                } catch(e) {
                    root.wxError = "Search error"
                    root.wxLoading = false
                }
            }
        }
    }

    Process {
        id: weatherProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse(text.trim())
                    let c = j.current
                    root.weatherCode  = c.weather_code
                    root.tempF        = c.temperature_2m
                    root.feelsLikeF   = c.apparent_temperature
                    root.humidity     = c.relative_humidity_2m
                    root.windMph      = c.wind_speed_10m
                    root.isDay        = c.is_day === 1
                    root.weatherDesc  = wmoDesc(c.weather_code)
                    root.forecastDates   = j.daily.time
                    root.forecastMax     = j.daily.temperature_2m_max
                    root.forecastMin     = j.daily.temperature_2m_min
                    root.forecastCodes   = j.daily.weather_code
                    root.forecastPrecip  = j.daily.precipitation_probability_max || []
                    root.wxLoading = false
                    root.wxError = ""
                } catch(e) {
                    root.wxError = "Parse error"
                    root.wxLoading = false
                }
            }
        }
    }

    function fetchWeather(lat, lon) {
        let url = "https://api.open-meteo.com/v1/forecast" +
                  "?latitude=" + lat + "&longitude=" + lon +
                  "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max" +
                  "&temperature_unit=fahrenheit&wind_speed_unit=mph&forecast_days=5&timezone=auto"
        weatherProc.command = ["curl", "-sf", "--max-time", "8", url]
        weatherProc.running = true
    }

    function loadCity(name) {
        root.wxLoading = true
        root.wxError = ""
        if (!name || name.trim() === "") {
            ipGeoProc.running = true
        } else {
            let enc = encodeURIComponent(name.trim())
            geocodeProc.command = ["curl", "-sf", "--max-time", "6",
                "https://geocoding-api.open-meteo.com/v1/search?name=" + enc + "&count=1&language=en&format=json"]
            geocodeProc.running = true
        }
    }

    // ── Clipboard state ────────────────────────────────────────────────────
    property string clipSearch: ""
    property string clipHoveredId: ""
    property string clipHoveredPreview: ""
    property bool   clipHoveredIsImage: false
    property string clipDecodedImagePath: ""
    property string clipDecodedText: ""
    property string _clipTextBuf: ""

    ListModel { id: clipModel }

  Process {
        id: clipExec
        function run(args) { command = args; running = true }
    }

    Process {
        id: clipDeleteExec
        function run(args) { command = args; running = true }
    }

    Process {
        id: clipLoader
        command: root.clipSearch === ""
                 ? ["cliphist", "list"]
                 : ["bash", "-c", "cliphist list | grep -i '" + root.clipSearch + "'"]
stdout: SplitParser {
            onRead: function(data) {
                let line = data.trim()
                if (line.length === 0) return
                let splitIdx = line.indexOf("\t")
                if (splitIdx !== -1)
                    clipModel.append({ clipId: line.substring(0, splitIdx), preview: line.substring(splitIdx + 1) })
            }
        }
    }

    Timer { id: clipSearchDelay; interval: 200; onTriggered: { clipModel.clear(); clipLoader.running = true } }

    Process {
        id: clipImageDecoder
        property string targetId: ""
        property string targetPreview: ""
        property string targetFile: {
            let safe = targetId.replace(/[^a-zA-Z0-9]/g, "_")
            return "/tmp/qs_tide_clip_" + safe + ".png"
        }
        command: ["bash", "-c",
            "printf '%s\\t%s' \"$1\" \"$2\" | cliphist decode > \"$3\" 2>/dev/null && echo ok",
            "_", clipImageDecoder.targetId, clipImageDecoder.targetPreview, clipImageDecoder.targetFile
        ]
stdout: SplitParser {
            onRead: function(data) {
                if (data.trim() === "ok")
                    root.clipDecodedImagePath = "file://" + clipImageDecoder.targetFile + "?t=" + Date.now()
            }
        }
    }

    Process {
        id: clipTextDecoder
        property string targetId: ""
        property string targetPreview: ""
        command: ["bash", "-c",
            "printf '%s\\t%s' \"$1\" \"$2\" | cliphist decode 2>/dev/null",
            "_", clipTextDecoder.targetId, clipTextDecoder.targetPreview
        ]
        stdout: SplitParser { onRead: function(data) { root._clipTextBuf += data + "\n" } }
        onRunningChanged: {
            if (!running)
                root.clipDecodedText = root._clipTextBuf.replace(/\n$/, "")
        }
    }

    Timer {
        id: clipDecodeDebounce; interval: 120
        onTriggered: {
            if (root.clipHoveredId !== "") {
                if (root.clipHoveredIsImage) {
                    clipImageDecoder.targetId      = root.clipHoveredId
                    clipImageDecoder.targetPreview = root.clipHoveredPreview
                    clipImageDecoder.running       = true
                } else {
                    root._clipTextBuf      = ""
                    root.clipDecodedText   = ""
                    clipTextDecoder.targetId      = root.clipHoveredId
                    clipTextDecoder.targetPreview = root.clipHoveredPreview
                    clipTextDecoder.running       = true
                }
            }
        }
    }

    Timer {
        id: clipHidePreviewTimer; interval: 350
        onTriggered: {
            root.clipHoveredId      = ""
            root.clipHoveredPreview = ""
            root.clipHoveredIsImage = false
        }
    }

    // ── Notes (tide-notes) state ───────────────────────────────────────────
    property bool   tideNotesLoaded:  false
    property bool   tideNotesLoading: false
    property bool   tideNotesDirty:   false
    property string tideNotesContent: ""
    property string _tideNotesBuf:    ""

    function loadTideNotes() {
        _tideNotesBuf = ""
        tideNotesReadProc.running = true
    }

    Process {
        id: tideNotesReadProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/quickshell/tide-notes.txt\"\n" +
            "mkdir -p \"$(dirname \"$f\")\"\n" +
            "[ -f \"$f\" ] && cat \"$f\" || true"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                root._tideNotesBuf = root._tideNotesBuf === "" ? data : root._tideNotesBuf + "\n" + data
            }
        }
        onRunningChanged: {
            if (!running) {
                root.tideNotesLoading = true
                tideNotesEdit.text    = root._tideNotesBuf
                root.tideNotesContent = root._tideNotesBuf
                root._tideNotesBuf    = ""
                root.tideNotesLoaded  = true
                root.tideNotesLoading = false
            }
        }
    }

    Process {
        id: tideNotesWriteProc
        function write(content) {
            let b64 = Qt.btoa(unescape(encodeURIComponent(content)))
            command = ["python3", "-c",
                "import base64, pathlib\n" +
                "p = pathlib.Path.home() / '.config/quickshell/tide-notes.txt'\n" +
                "p.parent.mkdir(parents=True, exist_ok=True)\n" +
                "p.write_bytes(base64.b64decode('" + b64 + "'))\n"
            ]
            running = true
        }
    }

    Timer { id: tideNotesDebounce; interval: 1500; repeat: false
        onTriggered: { tideNotesWriteProc.write(root.tideNotesContent); root.tideNotesDirty = false }
    }

    // ── Todo state ─────────────────────────────────────────────────────────
    ListModel { id: tideTodoModel }
    property bool tideTodosLoaded: false

    function loadTideTodos() {
        tideTodosReadProc.running = true
    }

    Process {
        id: tideTodosReadProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/quickshell/tide-todos.txt\"\n" +
            "mkdir -p \"$(dirname \"$f\")\"\n" +
            "[ -f \"$f\" ] && cat \"$f\" || true"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                let l = data
                if (l.trim() === "") return
                let done = l.startsWith("[x] ")
                let txt  = (done || l.startsWith("[ ] ")) ? l.slice(4) : l
                tideTodoModel.append({ todoText: txt, todoDone: done })
            }
        }
        onRunningChanged: { if (!running) root.tideTodosLoaded = true }
    }

    Process {
        id: tideTodosWriteProc
        function write(content) {
            command = ["bash", "-c",
                "mkdir -p ~/.config/quickshell && printf '%s' \"$1\" > ~/.config/quickshell/tide-todos.txt",
                "_", content
            ]
            running = true
        }
    }

    function saveTideTodos() {
        let lines = []
        for (let i = 0; i < tideTodoModel.count; i++) {
            let t = tideTodoModel.get(i)
            lines.push((t.todoDone ? "[x] " : "[ ] ") + t.todoText)
        }
        tideTodosWriteProc.write(lines.join("\n"))
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────
    Component.onCompleted: {
        updateCalendar(calYear, calMonth)
        loadCity(root.citySearch)
    }

onShowConditionChanged: {
        if (showCondition) {
            if (weatherCode === -1 && !wxLoading) loadCity(root.citySearch)
            if (!tideNotesLoaded) loadTideNotes()
            if (!tideTodosLoaded) loadTideTodos()
            clipModel.clear()
            clipLoader.running = true
        }
    }

    // ── UI ─────────────────────────────────────────────────────────────────
    anchors.fill: parent
    opacity: showCondition ? 1 : 0
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: showCondition ? IslandMotion.contentEnterDelay : 0 }
            NumberAnimation {
                duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
            }
        }
    }

    // ── TAB BAR ────────────────────────────────────────────────────────────
Row {
        id: tabBar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 10
        spacing: 6
        z: 10

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y < 0)
                    root.activeTab = Math.min(3, root.activeTab + 1)
                else
                    root.activeTab = Math.max(0, root.activeTab - 1)
            }
        }

        Repeater {
            model: [
                { label: "  Weather",   idx: 0 },
                { label: "󰅌  Clipboard", idx: 1 },
                { label: "󰎚  Notes",     idx: 2 },
                { label: "󰄳  Todo",      idx: 3 }
            ]
            delegate: Rectangle {
                required property var modelData
                property bool sel: root.activeTab === modelData.idx
                width: tabTxt.implicitWidth + 24; height: 26; radius: 13
                color: sel ? Qt.rgba(1,1,1,0.18) : (tabHover.containsMouse ? Qt.rgba(1,1,1,0.08) : "transparent")
                border.color: Qt.rgba(1,1,1, sel ? 0.5 : 0.2); border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    renderType: Text.NativeRendering
                    id: tabTxt
                    anchors.centerIn: parent
                    text: modelData.label
                    color: "white"
                    opacity: sel ? 1.0 : 0.5
                    font.pixelSize: 11
                    font.family: root.textFontFamily
                    font.weight: sel ? Font.Bold : Font.Normal
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
MouseArea {
                    id: tabHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.activeTab = modelData.idx
                }
            }
        }
    }

    // ── TAB CONTENT ────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.topMargin: 44

        // ══════════════════════════════════════════════════════════════════
        // TAB 0 — WEATHER + CALENDAR (original layout, untouched)
        // ══════════════════════════════════════════════════════════════════
        Item {
            anchors.fill: parent
            visible: root.activeTab === 0

            Row {
                anchors.fill: parent
                anchors.margins: 40
                anchors.topMargin: 10
                spacing: 16

        // ── LEFT: Weather ──────────────────────────────────────────────────
        Item {
            width: parent.width * 0.42
            height: parent.height

            Column {
                anchors.fill: parent
                spacing: 6

                // City + search
                Row {
                    width: parent.width
                    spacing: 6

                    Text {
                        renderType: Text.NativeRendering
                        text: root.wxLoading ? "Loading…" : (root.wxError !== "" ? root.wxError : root.displayCity)
                        color: root.wxError !== "" ? "#ff6b6b" : "white"
                        opacity: 0.7
                        font.pixelSize: 11
                        font.family: textFontFamily
                        elide: Text.ElideRight
                        width: parent.width - 20
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: "↺"
                        color: "white"
                        opacity: 0.78
                        font.pixelSize: 16
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            onClicked: loadCity(root.citySearch)
                        }
                    }
                }

                // Search input
                Rectangle {
                    width: parent.width
                    height: 22
                    radius: 11
                    color: Qt.rgba(1, 1, 1, 0.08)

                    TextInput {
                        id: cityInput
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        color: "white"
                        font.pixelSize: 11
                        font.family: textFontFamily
                        verticalAlignment: TextInput.AlignVCenter
onAccepted: {
                            root.citySearch = text
                            loadCity(text)
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.fill: parent
                            anchors.leftMargin: 0
                            text: "Search city…"
                            color: "white"
                            opacity: 0.3
                            font.pixelSize: 11
                            font.family: textFontFamily
                            verticalAlignment: Text.AlignVCenter
                            visible: cityInput.text.length === 0
                        }
                    }
                }

                // Big temp + icon
                Row {
                    width: parent.width
                    spacing: 8
                    visible: root.weatherCode !== -1 && !root.wxLoading

                    Text {
                        renderType: Text.NativeRendering
                        text: wmoIcon(root.weatherCode, root.isDay)
                        font.pixelSize: 36
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: "Noto Color Emoji"
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            renderType: Text.NativeRendering
                            text: Math.round(root.tempF) + "°F"
                            color: "white"
                            font.pixelSize: 28
                            font.family: textFontFamily
                            font.weight: Font.Bold
                        }

                        Text {
                            renderType: Text.NativeRendering
                            text: root.weatherDesc
                            color: "white"
                            opacity: 0.6
                            font.pixelSize: 11
                            font.family: textFontFamily
                        }
                    }
                }

                // Stats row
                Row {
                    width: parent.width
                    spacing: 10
                    visible: root.weatherCode !== -1 && !root.wxLoading

                    Column {
                        spacing: 1
                        Text {
                            renderType: Text.NativeRendering
 text: "Feels"; color: "white"; opacity: 0.78; font.pixelSize: 11; font.family: textFontFamily }
                        Text {
                            renderType: Text.NativeRendering
 text: Math.round(root.feelsLikeF) + "°"; color: "white"; font.pixelSize: 11; font.family: textFontFamily; font.weight: Font.Bold }
                    }
                    Column {
                        spacing: 1
                        Text {
                            renderType: Text.NativeRendering
 text: "Wind"; color: "white"; opacity: 0.78; font.pixelSize: 11; font.family: textFontFamily }
                        Text {
                            renderType: Text.NativeRendering
 text: Math.round(root.windMph) + " mph"; color: "white"; font.pixelSize: 11; font.family: textFontFamily; font.weight: Font.Bold }
                    }
                    Column {
                        spacing: 1
                        Text {
                            renderType: Text.NativeRendering
 text: "Humid"; color: "white"; opacity: 0.78; font.pixelSize: 11; font.family: textFontFamily }
                        Text {
                            renderType: Text.NativeRendering
 text: root.humidity + "%"; color: "white"; font.pixelSize: 11; font.family: textFontFamily; font.weight: Font.Bold }
                    }
                }

                // 5-day forecast
                Column {
                    width: parent.width
                    spacing: 3
                    visible: root.forecastDates.length > 0 && !root.wxLoading

                    Repeater {
                        model: Math.min(5, root.forecastDates.length)
                        Row {
                            width: parent.width
                            spacing: 0

                            Text {
                                renderType: Text.NativeRendering
                                text: index === 0 ? "Today" : shortDay(root.forecastDates[index])
                                color: "white"
                                opacity: index === 0 ? 0.9 : 0.5
                                font.pixelSize: 10
                                font.family: textFontFamily
                                font.weight: index === 0 ? Font.Bold : Font.Normal
                                width: 34
                            }

                            Text {
                                renderType: Text.NativeRendering
                                text: wmoIcon(root.forecastCodes[index] || 0, true)
                                font.pixelSize: 11
                                width: 18
                                font.family: "Noto Color Emoji"
                            }

                            Text {
                                renderType: Text.NativeRendering
                                text: root.forecastPrecip[index] > 0 ? root.forecastPrecip[index] + "%" : ""
                                color: "#60a5fa"
                                font.pixelSize: 11
                                font.family: textFontFamily
                                width: 28
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                renderType: Text.NativeRendering
                                text: Math.round(root.forecastMin[index] || 0) + "°"
                                color: "white"
                                opacity: 0.5
                                font.pixelSize: 10
                                font.family: textFontFamily
                                width: 26
                                horizontalAlignment: Text.AlignRight
                            }

                            Item {
                                width: 50
                                height: 4
                                anchors.verticalCenter: parent.verticalCenter

                                readonly property real allMax: {
                                    let m = -999
                                    for (let i = 0; i < root.forecastMax.length; i++) if (root.forecastMax[i] > m) m = root.forecastMax[i]
                                    return m
                                }
                                readonly property real allMin: {
                                    let m = 999
                                    for (let i = 0; i < root.forecastMin.length; i++) if (root.forecastMin[i] < m) m = root.forecastMin[i]
                                    return m
                                }
                                readonly property real span: Math.max(1, allMax - allMin)
                                readonly property real barL: (root.forecastMin[index] - allMin) / span
                                readonly property real barR: (root.forecastMax[index] - allMin) / span

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.15)
                                }
                                Rectangle {
                                    x: parent.barL * parent.width
                                    width: (parent.barR - parent.barL) * parent.width
                                    height: parent.height
                                    radius: 2
                                    color: "white"
                                    opacity: 0.8
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                text: Math.round(root.forecastMax[index] || 0) + "°"
                                color: "white"
                                font.pixelSize: 10
                                font.family: textFontFamily
                                font.weight: Font.Bold
                                width: 26
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }

        // ── DIVIDER ────────────────────────────────────────────────────────
        Rectangle {
            width: 1
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        // ── RIGHT: Calendar ────────────────────────────────────────────────
        Item {
            width: parent.width - parent.width * 0.42 - 17
            height: parent.height

            Column {
                anchors.fill: parent
                spacing: 6

                // Month nav
                Row {
                    width: parent.width

                    Text {
                        renderType: Text.NativeRendering
                        text: "‹"
                        color: "white"
                        font.pixelSize: 15
                        font.family: textFontFamily
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
                                if (calMonth === 0) { calMonth = 11; calYear-- } else calMonth--
                                updateCalendar(calYear, calMonth)
                            }
                        }
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: monthNames[calMonth] + " " + calYear
                        color: "white"
                        font.pixelSize: 12
                        font.family: textFontFamily
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width - 28
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: "›"
                        color: "white"
                        font.pixelSize: 15
                        font.family: textFontFamily
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
                                if (calMonth === 11) { calMonth = 0; calYear++ } else calMonth++
                                updateCalendar(calYear, calMonth)
                            }
                        }
                    }
                }

                // Day headers
                Row {
                    width: parent.width
                    Repeater {
                        model: ["M","T","W","T","F","S","S"]
                        Text {
                            renderType: Text.NativeRendering
                            text: modelData
                            color: "white"
                            opacity: 0.78
                            font.pixelSize: 11
                            font.family: textFontFamily
                            font.weight: Font.Bold
                            width: parent.width / 7
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

               // Calendar grid
                Grid {
                    columns: 7
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: calModel
                        Item {
                            width: parent.width / 7
                            height: width

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 2
                                height: width
                                radius: width / 2
                                color: model.tod ? "white" : "transparent"

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: model.day
                                    color: model.tod ? "black" : "white"
                                    opacity: model.tod ? 1.0 : (model.cur ? 0.85 : 0.25)
                                    font.pixelSize: 11
                                    font.family: textFontFamily
                                    font.weight: model.tod ? Font.Bold : Font.Normal
                                }
                            }
                        }
                    }
                }
                // end Grid
            }
            // end Calendar Column
        }
        // end Calendar Item
    }
    // end Weather+Calendar Row
} // end Tab 0 Item

        // ══════════════════════════════════════════════════════════════════
        // TAB 1 — CLIPBOARD
        // ══════════════════════════════════════════════════════════════════
        Item {
            anchors.fill: parent
            visible: root.activeTab === 1

            Row {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 0

                // ── PREVIEW PANE ───────────────────────────────────────────
                Item {
                    id: clipPreviewPane
                    width: root.clipHoveredId !== "" ? parent.width * 0.45 : 0
                    height: parent.height
                    clip: true
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

                    opacity: root.clipHoveredId !== "" ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onEntered: clipHidePreviewTimer.stop()
                        onExited:  clipHidePreviewTimer.restart()
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        Text {
                            renderType: Text.NativeRendering
                            text: root.clipHoveredIsImage ? "󰋼  Image Preview" : "󰈙  Content Preview"
                            color: "white"; opacity: 0.7
                            font.pixelSize: 11; font.family: root.textFontFamily; font.weight: Font.Bold
                        }

                        // Text preview
                        Rectangle {
                            width: parent.width; height: parent.height - 30
                            visible: !root.clipHoveredIsImage
                            radius: 10
                            color: Qt.rgba(1,1,1,0.06)
                            border.color: Qt.rgba(1,1,1,0.1); border.width: 1
                            clip: true

                            Flickable {
                                anchors.fill: parent; anchors.margins: 10
                                contentWidth: width
                                contentHeight: clipPreviewText.implicitHeight
                                clip: true; boundsBehavior: Flickable.StopAtBounds

                                Text {
                                    renderType: Text.NativeRendering
                                    id: clipPreviewText
                                    width: parent.width
                                    text: root.clipDecodedText !== "" ? root.clipDecodedText : root.clipHoveredPreview
                                    color: "white"; opacity: 0.85
                                    font.pixelSize: 12; font.family: root.textFontFamily
                                    wrapMode: Text.WrapAnywhere; lineHeight: 1.3
                                }

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                    contentItem: Rectangle { implicitWidth: 3; radius: 2; color: "white"; opacity: 0.2 }
                                }
                            }

                            Text {
                                renderType: Text.NativeRendering
                                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
                                text: "Decoding…"
                                color: "white"; opacity: 0.78; font.pixelSize: 10
                                font.family: root.textFontFamily
                                visible: clipTextDecoder.running && root.clipDecodedText === ""
                            }
                        }

                        // Image preview
                        Rectangle {
                            width: parent.width; height: parent.height - 30
                            visible: root.clipHoveredIsImage
                            radius: 10
                            color: Qt.rgba(0,0,0,0.2)
                            border.color: Qt.rgba(1,1,1,0.1); border.width: 1
                            clip: true

                            Image {
                                anchors.fill: parent; anchors.margins: 8
                                source: root.clipDecodedImagePath
                                cache: false; fillMode: Image.PreserveAspectFit
                                smooth: true; asynchronous: true

                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    visible: parent.status === Image.Error || parent.status === Image.Null
                                    Text {
                                        renderType: Text.NativeRendering
 anchors.horizontalCenter: parent.horizontalCenter
                                           text: "󰋼"; color: "white"; opacity: 0.2; font.pixelSize: 32 }
                                    Text {
                                        renderType: Text.NativeRendering
 anchors.horizontalCenter: parent.horizontalCenter
                                           text: "Preview unavailable"; color: "white"; opacity: 0.78
                                           font.pixelSize: 11; font.family: root.textFontFamily }
                                }
                            }
                        }
                    }
                }

                // Divider between preview and list
                Rectangle {
                    width: root.clipHoveredId !== "" ? 1 : 0
                    height: parent.height
                    color: Qt.rgba(1,1,1,0.12)
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                }

                // ── LIST PANE ──────────────────────────────────────────────
                Item {
                    width: parent.width - clipPreviewPane.width - (root.clipHoveredId !== "" ? 1 : 0)
                    height: parent.height

                    Column {
                        anchors.fill: parent
                        spacing: 10

                        // Header row
                        Row {
                            width: parent.width
                            spacing: 0

                            Text {
                                renderType: Text.NativeRendering
                                text: "󰅌  Clipboard"
                                color: "white"; opacity: 0.8
                                font.pixelSize: 13; font.family: root.textFontFamily; font.weight: Font.Bold
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - clearClipRect.width
                            }

                            Rectangle {
                                id: clearClipRect
                                width: 64; height: 26; radius: 13
                                color: clearClipMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                                border.color: Qt.rgba(1,1,1,0.25); border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    renderType: Text.NativeRendering
                                    anchors.centerIn: parent
                                    text: "󰃢  Clear"
                                    color: "white"; opacity: 0.7
                                    font.pixelSize: 10; font.family: root.textFontFamily
                                }
                                MouseArea {
                                    id: clearClipMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { clipExec.run(["bash", "-c", "cliphist wipe"]); clipModel.clear() }
                                }
                            }
                        }

                       // Search bar
                        Rectangle {
                            width: parent.width; height: 28; radius: 14
                            color: Qt.rgba(1,1,1,0.08)
                            border.color: clipSearchInput.activeFocus ? Qt.rgba(1,1,1,0.35) : "transparent"
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: clipSearchInput.forceActiveFocus()
                            }

                            Row {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                                Text {
                                    renderType: Text.NativeRendering
 text: "󰍉"; color: "white"; opacity: 0.78; font.pixelSize: 12
                                       anchors.verticalCenter: parent.verticalCenter }
                                TextInput {
                                    id: clipSearchInput
                                    width: parent.width - 40; height: parent.height
                                    color: "white"; font.pixelSize: 11; font.family: root.textFontFamily
                                    verticalAlignment: TextInput.AlignVCenter
                                    activeFocusOnPress: true
                                    onTextChanged: { root.clipSearch = text; clipSearchDelay.restart() }
                                    Text {
                                        renderType: Text.NativeRendering
                                        anchors.fill: parent
                                        text: "Search history…"
                                        color: "white"; opacity: 0.3
                                        font.pixelSize: 11; font.family: root.textFontFamily
                                        verticalAlignment: Text.AlignVCenter
                                        visible: clipSearchInput.text.length === 0
                                    }
                                }
                            }
                        }

                        // Empty state
                        Item {
                            width: parent.width; height: 80
                            visible: clipModel.count === 0
                            Column {
                                anchors.centerIn: parent; spacing: 6
                                Text {
                                    renderType: Text.NativeRendering
 anchors.horizontalCenter: parent.horizontalCenter
                                       text: "󰅌"; color: "white"; opacity: 0.15; font.pixelSize: 36 }
                                Text {
                                    renderType: Text.NativeRendering
 anchors.horizontalCenter: parent.horizontalCenter
                                       text: "Nothing copied yet"
                                       color: "white"; opacity: 0.78; font.pixelSize: 11
                                       font.family: root.textFontFamily }
                            }
                        }

                        // Clip list
                        ListView {
                            id: clipListView
                            width: parent.width
                            height: parent.height - 120
                            model: clipModel
                            spacing: 6
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                width: clipListView.width; height: 44; radius: 10
                                color: clipItemMouse.containsMouse ? Qt.rgba(1,1,1,0.1) : Qt.rgba(1,1,1,0.04)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        renderType: Text.NativeRendering
                                        text: model.preview.startsWith("[[") ? "󰋼" : "󰆒"
                                        color: "white"; opacity: 0.78; font.pixelSize: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        text: model.preview
                                        color: "white"; opacity: 0.8
                                        font.pixelSize: 12; font.family: root.textFontFamily
                                        elide: Text.ElideRight
                                        width: parent.width - 60
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        text: "󰆴"
                                        color: clipDelMouse.containsMouse ? "#ff6b6b" : "white"
                                        opacity: clipDelMouse.containsMouse ? 1.0 : 0.25
                                        font.pixelSize: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Behavior on color   { ColorAnimation   { duration: 120 } }

                                       MouseArea {
                                    id: clipDelMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        clipDeleteExec.run(["bash", "-c",
                                            "printf '%s\\t%s' \"$1\" \"$2\" | cliphist delete",
                                            "_", model.clipId, model.preview])
                                        clipModel.remove(index)
                                        if (root.clipHoveredId === model.clipId) root.clipHoveredId = ""
                                    }
                                }
                                    }
                                }

                                MouseArea {
                                    id: clipItemMouse
                                    anchors.fill: parent
                                    anchors.rightMargin: 28
                                    hoverEnabled: true
                                    onEntered: {
                                        clipHidePreviewTimer.stop()
                                        root.clipHoveredId        = model.clipId
                                        root.clipHoveredPreview   = model.preview
                                        root.clipHoveredIsImage   = model.preview.startsWith("[[")
                                        root.clipDecodedImagePath = ""
                                        clipDecodeDebounce.restart()
                                    }
                                    onExited: clipHidePreviewTimer.restart()
                                    onClicked: {
                                        clipExec.run(["bash", "-c",
                                            "printf '%s\\t%s' \"$1\" \"$2\" | cliphist decode | wl-copy",
                                            "_", model.clipId, model.preview])
                                        root.requestClose()
                                    }
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: 3; radius: 2; color: "white"; opacity: 0.2 }
                            }
                        }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Click to copy  ·  Hover to preview"
                            color: "white"; opacity: 0.25; font.pixelSize: 10
                            font.family: root.textFontFamily
                        }
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // TAB 2 — NOTES
        // ══════════════════════════════════════════════════════════════════
        Item {
            anchors.fill: parent
            visible: root.activeTab === 2

            Column {
                anchors.fill: parent
                anchors.margins: 20
                anchors.topMargin: 6
                spacing: 10

                // Header
                Row {
                    width: parent.width; spacing: 0

                    Text {
                        renderType: Text.NativeRendering
                        text: "󰎚  Tide Notes"
                        color: "white"; opacity: 0.8
                        font.pixelSize: 13; font.family: root.textFontFamily; font.weight: Font.Bold
                        width: parent.width - saveStatusText.implicitWidth - 8
                    }
                    Text {
                        renderType: Text.NativeRendering
                        id: saveStatusText
                        text: root.tideNotesDirty ? "Saving…" : (root.tideNotesLoaded ? "Saved" : "")
                        color: "white"; opacity: 0.78
                        font.pixelSize: 10; font.family: root.textFontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Editor
                Rectangle {
                    width: parent.width
                    height: parent.height - 80
                    radius: 12
                    color: Qt.rgba(1,1,1,0.06)
                    border.color: tideNotesEdit.activeFocus ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.1)
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    clip: true
                    MouseArea {
                        anchors.fill: parent
                        onClicked: tideNotesEdit.forceActiveFocus()
                    }

                    ScrollView {
                        anchors.fill: parent; anchors.margins: 12
                        clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        TextEdit {
                            id: tideNotesEdit
                            width: parent.width
                            color: "white"; font.pixelSize: 13; font.family: root.textFontFamily
                            wrapMode: TextEdit.Wrap
                            activeFocusOnPress: true
                            selectionColor: Qt.rgba(1,1,1,0.3)
                            selectedTextColor: "white"

                            Text {
                                renderType: Text.NativeRendering
                                anchors.fill: parent
                                text: "Start typing…\n\nSaved to ~/.config/quickshell/tide-notes.txt"
                                color: "white"; opacity: 0.2
                                font.pixelSize: 13; font.family: root.textFontFamily
                                wrapMode: Text.Wrap
                                visible: tideNotesEdit.text.length === 0
                            }

                            onTextChanged: {
                                if (!root.tideNotesLoading) {
                                    root.tideNotesContent = text
                                    root.tideNotesDirty   = true
                                    tideNotesDebounce.restart()
                                }
                            }
                        }
                    }
                }

                // Footer buttons
                Row {
                    width: parent.width; spacing: 8

                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: copyNotesMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                        border.color: Qt.rgba(1,1,1,0.2); border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            renderType: Text.NativeRendering
 anchors.centerIn: parent; text: "󰆒"; color: "white"; font.pixelSize: 14 }
                        MouseArea {
                            id: copyNotesMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: clipExec.run(["bash", "-c",
                                "printf '%s' " + JSON.stringify(tideNotesEdit.text) + " | wl-copy"])
                        }
                    }

                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: clearNotesMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                        border.color: Qt.rgba(1,1,1,0.2); border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            renderType: Text.NativeRendering
 anchors.centerIn: parent; text: "󰆴"; color: "white"; font.pixelSize: 14 }
                        MouseArea {
                            id: clearNotesMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                tideNotesEdit.text    = ""
                                root.tideNotesContent = ""
                                tideNotesWriteProc.write("")
                            }
                        }
                    }

                    Item { width: parent.width - 80; height: 1 }

		
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // TAB 3 — TODO
        // ══════════════════════════════════════════════════════════════════
        Item {
            anchors.fill: parent
            visible: root.activeTab === 3

            Column {
                anchors.fill: parent
                anchors.margins: 20
                anchors.topMargin: 6
                spacing: 10

                // Header
                Row {
                    width: parent.width

                    Text {
                        renderType: Text.NativeRendering
                        text: "󰄳  Tasks"
                        color: "white"; opacity: 0.8
                        font.pixelSize: 13; font.family: root.textFontFamily; font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - todoDoneCount.implicitWidth
                    }
                    Text {
                        renderType: Text.NativeRendering
                        id: todoDoneCount
                        text: {
                            let done = 0
                            for (let i = 0; i < tideTodoModel.count; i++)
                                if (tideTodoModel.get(i).todoDone) done++
                            return done + " / " + tideTodoModel.count + " done"
                        }
                        color: "white"; opacity: 0.78
                        font.pixelSize: 10; font.family: root.textFontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

 // Add input
                Rectangle {
                    width: parent.width; height: 32; radius: 16
                    color: Qt.rgba(1,1,1,0.08)
                    border.color: todoAddInput.activeFocus ? Qt.rgba(1,1,1,0.35) : "transparent"
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: todoAddInput.forceActiveFocus()
                    }

                    Row {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
                        Text {
                            renderType: Text.NativeRendering
 text: "󰐕"; color: "white"; opacity: 0.78; font.pixelSize: 14
                               anchors.verticalCenter: parent.verticalCenter }
                       TextInput {
                            id: todoAddInput
                            width: parent.width - 40; height: parent.height
                            color: "white"; font.pixelSize: 12; font.family: root.textFontFamily
                            verticalAlignment: TextInput.AlignVCenter
                            activeFocusOnPress: true
                            Keys.onReturnPressed: {
                                let t = todoAddInput.text.trim()
                                if (t !== "") {
                                    tideTodoModel.append({ todoText: t, todoDone: false })
                                    saveTideTodos()
                                    todoAddInput.text = ""
                                }
                            }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.fill: parent
                                text: "Add a task and press Enter…"
                                color: "white"; opacity: 0.25
                                font.pixelSize: 12; font.family: root.textFontFamily
                                verticalAlignment: Text.AlignVCenter
                                visible: todoAddInput.text.length === 0
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    width: parent.width; height: 60
                    visible: tideTodoModel.count === 0
                    Column {
                        anchors.centerIn: parent; spacing: 6
                        Text {
                            renderType: Text.NativeRendering
 anchors.horizontalCenter: parent.horizontalCenter
                               text: "󰄳"; color: "white"; opacity: 0.12; font.pixelSize: 36 }
                        Text {
                            renderType: Text.NativeRendering
 anchors.horizontalCenter: parent.horizontalCenter
                               text: "No tasks yet"
                               color: "white"; opacity: 0.3; font.pixelSize: 11
                               font.family: root.textFontFamily }
                    }
                }

                // Task list
                ScrollView {
                    width: parent.width
                    height: parent.height - 140
                    visible: tideTodoModel.count > 0
                    clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    Column {
                        width: parent.availableWidth; spacing: 6; bottomPadding: 6

                        Repeater {
                            model: tideTodoModel

                            delegate: Rectangle {
                                required property int    index
                                required property string todoText
                                required property bool   todoDone

                               width: parent.width > 0 ? parent.width : root.width - 40; height: 38; radius: 10
                                color: todoItemHover.containsMouse
                                       ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                                border.color: Qt.rgba(1,1,1, todoDone ? 0.0 : 0.15)
                                border.width: 1
                                opacity: todoDone ? 0.5 : 1.0
                                Behavior on color   { ColorAnimation { duration: 120 } }
                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                MouseArea { id: todoItemHover; anchors.fill: parent; hoverEnabled: true }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 8
                                    spacing: 8

                                    // Checkbox
                                    Rectangle {
                                        width: 18; height: 18; radius: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: todoDone ? "white" : "transparent"
                                        border.color: "white"; border.width: 1.5
                                        scale: checkHover.pressed ? 0.8 : (checkHover.containsMouse ? 1.15 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                        Text {
                                            renderType: Text.NativeRendering
                                            anchors.centerIn: parent; text: "󰄬"
                                            color: "black"; font.pixelSize: 10
                                            visible: todoDone
                                        }
                                        MouseArea {
                                            id: checkHover; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                tideTodoModel.setProperty(index, "todoDone", !todoDone)
                                                saveTideTodos()
                                            }
                                        }
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        text: todoText; color: "white"
                                        opacity: todoDone ? 0.5 : 0.85
                                        font.pixelSize: 12; font.family: root.textFontFamily
                                        font.strikeout: todoDone
                                        elide: Text.ElideRight
                                        width: parent.width - 56
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        renderType: Text.NativeRendering
                                        text: "󰅖"; color: delTodoMouse.containsMouse ? "#ff6b6b" : "white"
                                        opacity: delTodoMouse.containsMouse ? 1.0 : 0.2
                                        font.pixelSize: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        Behavior on color   { ColorAnimation   { duration: 120 } }
                                        MouseArea {
                                            id: delTodoMouse; anchors.fill: parent; hoverEnabled: true
                                            onClicked: { tideTodoModel.remove(index); saveTideTodos() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Footer actions
                Row {
                    width: parent.width
                    visible: tideTodoModel.count > 0
                    spacing: 0

                    Text {
                        renderType: Text.NativeRendering
                        text: "Clear done"
                        color: "white"; opacity: clearDoneHover.containsMouse ? 0.7 : 0.3
                        font.pixelSize: 11; font.family: root.textFontFamily
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        MouseArea {
                            id: clearDoneHover; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                for (let i = tideTodoModel.count - 1; i >= 0; i--)
                                    if (tideTodoModel.get(i).todoDone) tideTodoModel.remove(i)
                                saveTideTodos()
                            }
                        }
                    }

                    Item { width: parent.width - 120; height: 1 }

                    Text {
                        renderType: Text.NativeRendering
                        id: clearAllText
                        text: "Clear all"
                        color: "white"; opacity: clearAllHover.containsMouse ? 0.7 : 0.3
                        font.pixelSize: 11; font.family: root.textFontFamily
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        MouseArea {
                            id: clearAllHover; anchors.fill: parent; hoverEnabled: true
                            onClicked: { tideTodoModel.clear(); saveTideTodos() }
                        }
                    }
                }
            }
        }

    } // end tab content Item
} // end root Item
