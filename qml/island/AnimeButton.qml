import QtQuick
import "../shared"

// pill button used by the Anime Hub (hero, footer)
Rectangle {
    id: btn
    property string label: ""
    property string iconKind: ""
    property string fontFamily: ""
    property bool   primary: false
    property bool   active: true          // false = dimmed, no hover, no click
    property int    labelSize: 12
    signal clicked()

    height: 30
    radius: height / 2
    width: row.width + 26
    color: !active ? Qt.rgba(1, 1, 1, 0.05)
         : (primary ? (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14))
                    : (mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)))
    border.width: 1
    border.color: !active ? Qt.rgba(1, 1, 1, 0.08) : (primary ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.14))
    Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

    GlassSheen {}

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        AnimeIcon {
            visible: btn.iconKind !== ""
            kind: btn.iconKind; sz: 12
            col: "white"; opacity: btn.active ? 0.9 : 0.3
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            renderType: Text.NativeRendering
            text: btn.label
            font.family: btn.fontFamily
            font.pixelSize: btn.labelSize
            color: "white"
            opacity: btn.active ? (btn.primary ? 1.0 : 0.8) : 0.35
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.active
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
