import QtQuick
import "../shared"

Item {
    id: root

    property string glyph: ""
    property string iconFontFamily: "monospace"
    property bool tinted: false
    property color tintColor: "white"
    property bool dangerHover: false

    signal activated()

    width: 34; height: 34

    Text {
        renderType: Text.NativeRendering
        anchors.centerIn: parent
        text: root.glyph
        font.family: root.iconFontFamily
        font.pixelSize: 18
        color: root.tinted
            ? root.tintColor
            : (mouse.containsMouse
                ? (root.dangerHover ? Qt.rgba(1, 0.4, 0.4, 1) : "white")
                : Qt.rgba(1, 1, 1, 0.72))
        scale: mouse.containsMouse ? 1.15 : 1.0

        Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
        Behavior on scale { NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeSpring } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
