import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import IslandBackend
import "../shared"

// ── Centered weather + calendar popup ────────────────────────────────────────
// Self-contained: has its own curl processes, same API calls as InfoLayer tab 0.
// Layout: weather on left, vertical divider, calendar on right.

PanelWindow {
    id: root

    property string textFontFamily: ""
    property string iconFontFamily: ""

    // ── Theming ───────────────────────────────────────────────────────
    property bool   gamemodeActive:      false
    property bool   useWalColor:         false
    property color  walColor:            "#000000"
    property real   capsuleOpacityValue: 0.20

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    property bool popupOpen: false
    function open()  { popupOpen = true;  if (!_loaded) { _loaded = true; loadCity("") } }
    function close() { popupOpen = false }
    function toggle(){ if (popupOpen) close(); else open() }
    property bool _loaded: false

    // ── Weather state ─────────────────────────────────────────────────
    property real   tempF:       0
    property string weatherDesc: ""
    property int    weatherCode: -1
    property bool   isDay:       true
    property real   windMph:     0
    property int    humidity:    0
    property real   feelsLikeF:  0
    property string displayCity: ""
    property bool   wxLoading:   false
    property string wxError:     ""
    property var    forecastDates:  []
    property var    forecastMax:    []
    property var    forecastMin:    []
    property var    forecastCodes:  []
    property var    forecastPrecip: []
    property string citySearch:  ""

    // ── Calendar state ────────────────────────────────────────────────
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
        let firstDay    = new Date(year, month, 1)
        let startCell   = firstDay.getDay() === 0 ? 6 : firstDay.getDay() - 1
        let daysInMonth = new Date(year, month + 1, 0).getDate()
        let prevDays    = new Date(year, month, 0).getDate()
        for (let i = 0; i < 42; i++) {
            if (i < startCell)
                calModel.append({ day: prevDays - startCell + i + 1, cur: false, tod: false })
            else if (i < startCell + daysInMonth) {
                let d = i - startCell + 1
                calModel.append({ day: d, cur: true,
                    tod: d === todayD && month === todayM && year === todayY })
            } else {
                calModel.append({ day: i - startCell - daysInMonth + 1, cur: false, tod: false })
            }
        }
    }

    Component.onCompleted: updateCalendar(calYear, calMonth)

    // ── Weather WMO helpers (copy from InfoLayer) ─────────────────────
    function wmoIcon(code, day) {
        if (code === 0)                    return day ? "☀️"  : "🌙"
        if (code <= 2)                     return day ? "🌤️"  : "🌤️"
        if (code === 3)                    return "☁️"
        if (code <= 49)                    return "🌫️"
        if (code <= 59)                    return "🌧️"
        if (code <= 69)                    return "❄️"
        if (code <= 79)                    return "🌨️"
        if (code <= 84)                    return "🌧️"
        if (code <= 94)                    return "⛈️"
        return "🌩️"
    }
    function wmoDesc(code) {
        if (code === 0)   return "Clear sky"
        if (code <= 2)    return "Partly cloudy"
        if (code === 3)   return "Overcast"
        if (code <= 49)   return "Fog"
        if (code <= 59)   return "Drizzle"
        if (code <= 69)   return "Rain"
        if (code <= 79)   return "Snow"
        if (code <= 84)   return "Rain showers"
        if (code <= 94)   return "Thunderstorm"
        return "Storm"
    }
    function shortDay(dateStr) {
        if (!dateStr) return ""
        const d = new Date(dateStr + "T12:00:00")
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()]
    }

    // ── Fetch processes ────────────────────────────────────────────────
    Process {
        id: ipGeoProc
        command: ["curl","-sf","--max-time","5","http://ip-api.com/json/?fields=city,lat,lon,status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse(text.trim())
                    if (j.status === "success") {
                        root.displayCity = j.city
                        fetchWeather(j.lat, j.lon)
                    } else { root.wxError = "Location unavailable"; root.wxLoading = false }
                } catch(e) { root.wxError = "Network error"; root.wxLoading = false }
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
                        fetchWeather(r.latitude, r.longitude)
                    } else { root.wxError = "City not found"; root.wxLoading = false }
                } catch(e) { root.wxError = "Search error"; root.wxLoading = false }
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
                    root.weatherDesc  = root.wmoDesc(c.weather_code)
                    root.forecastDates  = j.daily.time
                    root.forecastMax    = j.daily.temperature_2m_max
                    root.forecastMin    = j.daily.temperature_2m_min
                    root.forecastCodes  = j.daily.weather_code
                    root.forecastPrecip = j.daily.precipitation_probability_max || []
                    root.wxLoading = false
                    root.wxError   = ""
                } catch(e) { root.wxError = "Parse error"; root.wxLoading = false }
            }
        }
    }

    function fetchWeather(lat, lon) {
        let url = "https://api.open-meteo.com/v1/forecast" +
                  "?latitude=" + lat + "&longitude=" + lon +
                  "&current=temperature_2m,apparent_temperature,relative_humidity_2m," +
                  "wind_speed_10m,weather_code,is_day" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code," +
                  "precipitation_probability_max" +
                  "&temperature_unit=fahrenheit&wind_speed_unit=mph&forecast_days=5&timezone=auto"
        weatherProc.command = ["curl","-sf","--max-time","8",url]
        weatherProc.running = true
    }

    function loadCity(name) {
        root.wxLoading = true; root.wxError = ""
        if (!name || name.trim() === "") {
            ipGeoProc.running = true
        } else {
            let enc = encodeURIComponent(name.trim())
            geocodeProc.command = ["curl","-sf","--max-time","6",
                "https://geocoding-api.open-meteo.com/v1/search?name=" + enc + "&count=1&language=en&format=json"]
            geocodeProc.running = true
        }
    }

    // ── Window setup ──────────────────────────────────────────────────
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: popupOpen

    readonly property real cardW: 640
    readonly property real cardH: 320

    mask: Region {
        Region {
            x: Math.floor(card.x); y: Math.floor(card.y)
            width:  root.popupOpen ? Math.ceil(card.width)  : 0
            height: root.popupOpen ? Math.ceil(card.height) : 0
        }
    }

    MouseArea {
        anchors.fill: parent; enabled: root.popupOpen; onClicked: root.close(); z: -1
    }
    Keys.onEscapePressed: root.close()

    // ── Card ──────────────────────────────────────────────────────────
    Item {
        id: card
        width: root.cardW; height: root.cardH
        anchors.centerIn: parent

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        Rectangle {
            anchors.fill: parent; radius: 28
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
        }

        Row {
            anchors.fill: parent
            anchors.margins: 28
            anchors.topMargin: 20
            spacing: 20

            // ── LEFT: Weather ─────────────────────────────────────────
            Item {
                width: parent.width * 0.44
                height: parent.height

                Column {
                    anchors.fill: parent
                    spacing: 6

                    // City + refresh
                    Row {
                        width: parent.width; spacing: 6
                        Text {
                            renderType: Text.NativeRendering
                            text: root.wxLoading ? "Loading…"
                                : (root.wxError !== "" ? root.wxError : root.displayCity)
                            color: root.wxError !== "" ? "#ff6b6b" : "white"
                            opacity: 0.7; font.pixelSize: 11
                            font.family: root.textFontFamily
                            elide: Text.ElideRight
                            width: parent.width - 22
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            renderType: Text.NativeRendering
                            text: "↺"; color: "white"; opacity: 0.78
                            font.pixelSize: 16
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                onClicked: root.loadCity(root.citySearch)
                            }
                        }
                    }

                    // Search bar
                    Rectangle {
                        width: parent.width; height: 22; radius: 11
                        color: Qt.rgba(1,1,1,0.08)
                        TextInput {
                            id: cityInput
                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                            color: "white"; font.pixelSize: 11; font.family: root.textFontFamily
                            verticalAlignment: TextInput.AlignVCenter
                            onAccepted: { root.citySearch = text; root.loadCity(text) }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.fill: parent; text: "Search city…"
                                color: "white"; opacity: 0.3; font.pixelSize: 11
                                font.family: root.textFontFamily
                                verticalAlignment: Text.AlignVCenter
                                visible: cityInput.text.length === 0
                            }
                        }
                    }

                    // Big temp + icon
                    Row {
                        width: parent.width; spacing: 8
                        visible: root.weatherCode !== -1 && !root.wxLoading
                        Text {
                            renderType: Text.NativeRendering
                            text: root.wmoIcon(root.weatherCode, root.isDay)
                            font.pixelSize: 36; font.family: "Noto Color Emoji"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 0
                            Text {
                                renderType: Text.NativeRendering
                                text: Math.round(root.tempF) + "°F"; color: "white"
                                font.pixelSize: 28; font.family: root.textFontFamily; font.weight: Font.Bold
                            }
                            Text {
                                renderType: Text.NativeRendering
                                text: root.weatherDesc; color: "white"; opacity: 0.6
                                font.pixelSize: 11; font.family: root.textFontFamily
                            }
                        }
                    }

                    // Stats
                    Row {
                        width: parent.width; spacing: 10
                        visible: root.weatherCode !== -1 && !root.wxLoading
                        Repeater {
                            model: [
                                { label: "Feels", val: Math.round(root.feelsLikeF) + "°" },
                                { label: "Wind",  val: Math.round(root.windMph) + " mph" },
                                { label: "Humid", val: root.humidity + "%" }
                            ]
                            Column {
                                required property var modelData
                                spacing: 1
                                Text { renderType: Text.NativeRendering; text: modelData.label; color: "white"; opacity: 0.78; font.pixelSize: 11; font.family: root.textFontFamily }
                                Text { renderType: Text.NativeRendering; text: modelData.val;   color: "white"; font.pixelSize: 11; font.family: root.textFontFamily; font.weight: Font.Bold }
                            }
                        }
                    }

                    // 5-day forecast
                    Column {
                        width: parent.width; spacing: 3
                        visible: root.forecastDates.length > 0 && !root.wxLoading
                        Repeater {
                            model: Math.min(5, root.forecastDates.length)
                            Row {
                                width: parent.width; spacing: 0
                                required property int index
                                Text { renderType: Text.NativeRendering; text: index === 0 ? "Today" : root.shortDay(root.forecastDates[index]); color: "white"; opacity: index === 0 ? 0.9 : 0.5; font.pixelSize: 10; font.family: root.textFontFamily; font.weight: index === 0 ? Font.Bold : Font.Normal; width: 34 }
                                Text { renderType: Text.NativeRendering; text: root.wmoIcon(root.forecastCodes[index] || 0, true); font.pixelSize: 11; width: 18; font.family: "Noto Color Emoji" }
                                Text { renderType: Text.NativeRendering; text: root.forecastPrecip[index] > 0 ? root.forecastPrecip[index] + "%" : ""; color: "#60a5fa"; font.pixelSize: 11; font.family: root.textFontFamily; width: 28; anchors.verticalCenter: parent.verticalCenter }
                                Text { renderType: Text.NativeRendering; text: Math.round(root.forecastMin[index] || 0) + "°"; color: "white"; opacity: 0.5; font.pixelSize: 10; font.family: root.textFontFamily; width: 26; horizontalAlignment: Text.AlignRight }
                                Item {
                                    width: 50; height: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    readonly property real allMax: { let m=-999; for(let i=0;i<root.forecastMax.length;i++) if(root.forecastMax[i]>m) m=root.forecastMax[i]; return m }
                                    readonly property real allMin: { let m=999;  for(let i=0;i<root.forecastMin.length;i++) if(root.forecastMin[i]<m) m=root.forecastMin[i]; return m }
                                    readonly property real span: Math.max(1, allMax - allMin)
                                    Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1,1,1,0.15) }
                                    Rectangle {
                                        x: parent.width * (root.forecastMin[index]-parent.allMin)/parent.span
                                        width: parent.width * (root.forecastMax[index]-root.forecastMin[index])/parent.span
                                        height: parent.height; radius: 2; color: "white"; opacity: 0.8
                                    }
                                }
                                Text { renderType: Text.NativeRendering; text: Math.round(root.forecastMax[index] || 0) + "°"; color: "white"; font.pixelSize: 10; font.family: root.textFontFamily; font.weight: Font.Bold; width: 26; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                }
            }

            // ── Divider ───────────────────────────────────────────────
            Rectangle {
                width: 1; height: parent.height
                color: Qt.rgba(1,1,1,0.12)
            }

            // ── RIGHT: Calendar ───────────────────────────────────────
            Item {
                width: parent.width - parent.width * 0.44 - 21
                height: parent.height

                Column {
                    anchors.fill: parent; spacing: 6

                    // Month nav
                    Row {
                        width: parent.width
                        Text {
                            renderType: Text.NativeRendering
                            text: "‹"; color: "white"; font.pixelSize: 15
                            font.family: root.textFontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -8
                                onClicked: {
                                    if (root.calMonth === 0) { root.calMonth = 11; root.calYear-- } else root.calMonth--
                                    root.updateCalendar(root.calYear, root.calMonth)
                                }
                            }
                        }
                        Text {
                            renderType: Text.NativeRendering
                            text: root.monthNames[root.calMonth] + " " + root.calYear
                            color: "white"; font.pixelSize: 13
                            font.family: root.textFontFamily; font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width - 28
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            renderType: Text.NativeRendering
                            text: "›"; color: "white"; font.pixelSize: 15
                            font.family: root.textFontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -8
                                onClicked: {
                                    if (root.calMonth === 11) { root.calMonth = 0; root.calYear++ } else root.calMonth++
                                    root.updateCalendar(root.calYear, root.calMonth)
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
                                text: modelData; color: "white"; opacity: 0.78
                                font.pixelSize: 11; font.family: root.textFontFamily; font.weight: Font.Bold
                                width: parent.width / 7; horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Calendar grid
                    Grid {
                        columns: 7; width: parent.width; spacing: 1
                        Repeater {
                            model: calModel
                            Item {
                                width: parent.width / 7; height: width
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 2; height: width; radius: width / 2
                                    color: model.tod ? "white" : "transparent"
                                    Text {
                                        renderType: Text.NativeRendering
                                        anchors.centerIn: parent; text: model.day
                                        color: model.tod ? "black" : "white"
                                        opacity: model.tod ? 1.0 : (model.cur ? 0.85 : 0.25)
                                        font.pixelSize: 11; font.family: root.textFontFamily
                                        font.weight: model.tod ? Font.Bold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
