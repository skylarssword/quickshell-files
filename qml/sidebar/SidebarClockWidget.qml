import QtQuick
import IslandBackend
import "../shared"

// ── Stacked bold clock inside the sidebar pill ────────────────────────────────
// Shows:   02      (hour, large, bold)
//          26      (minute, large, bold)
//          PM      (AM/PM, small, muted)
// Clicking opens SidebarInfoPopup.

Item {
    id: root

    property real   pillWidth:     38
    property string textFontFamily: ""
    property bool   isOpen:        false
    signal toggled()

    // Time is read from IslandClock if available, otherwise a JS timer
    property string _hour:   "12"
    property string _minute: "00"
    property string _ampm:   "AM"

    width:  pillWidth
    height: 72

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const d  = new Date()
            let h    = d.getHours()
            const m  = d.getMinutes()
            const ap = h >= 12 ? "PM" : "AM"
            h = h % 12
            if (h === 0) h = 12
            root._hour   = String(h).padStart(2, "0")
            root._minute = String(m).padStart(2, "0")
            root._ampm   = ap
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        Text {
            renderType: Text.NativeRendering
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._hour
            color: "white"
            font.family:    root.textFontFamily
            font.pixelSize: 15
            font.weight:    Font.Bold
            font.letterSpacing: -0.5
        }
        Text {
            renderType: Text.NativeRendering
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._minute
            color: "white"
            font.family:    root.textFontFamily
            font.pixelSize: 15
            font.weight:    Font.Bold
            font.letterSpacing: -0.5
        }
        Text {
            renderType: Text.NativeRendering
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._ampm
            color: Qt.rgba(1, 1, 1, 0.50)
            font.family:    root.textFontFamily
            font.pixelSize: 9
            font.weight:    Font.DemiBold
            topPadding: 2
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
