import QtQuick
import "../shared"

// Power button icon for the sidebar pill — opens SidebarPowerLayer.
// Uses the same Arch/power glyph (\uf011) as PowerMenuLayer.

Item {
    id: root

    property real   pillWidth:      38
    property string iconFontFamily: "monospace"
    property bool   gamemodeActive: false
    property bool   isOpen:         false

    signal toggled()

    implicitWidth:  pillWidth
    implicitHeight: pillWidth

    Text {
        renderType: Text.NativeRendering
        anchors.centerIn: parent
        text: "󰣇"
        font.family: root.iconFontFamily
        font.pixelSize: 24
        color: root.isOpen
            ? (root.gamemodeActive ? "white" : StyleTokens.accent)
            : (mouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.55))
        scale: mouse.containsMouse ? 1.18 : 1.0

        Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
        Behavior on scale { NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeSpring } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
