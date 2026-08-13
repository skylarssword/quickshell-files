import QtQuick
import Quickshell
import IslandBackend
import "../shared"

// ── Cog button inside the sidebar pill ───────────────────────────────────────
// Sits below the notification bell. Opens/closes SidebarControlCenterLayer.

Item {
    id: root

    property real   pillWidth:      38
    property string iconFontFamily: ""
    property bool   isOpen:         false
    property bool   gamemodeActive: false

    signal toggled()

    width:  pillWidth
    height: pillWidth

    Text {
        id: cogIcon
        anchors.centerIn: parent
        text: "\uf013"
        font.family: root.iconFontFamily
        font.pixelSize: 16
        color: "white"
        renderType: Text.NativeRendering
        opacity: root.isOpen ? 1.0 : (cogMouse.containsMouse ? 1.0 : 0.65)
        scale:   cogMouse.containsMouse ? 1.15 : (cogMouse.pressed ? 0.82 : 1.0)

        Behavior on opacity { NumberAnimation { duration: IslandMotion.micro } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.micro; easing.type: Easing.OutBack } }

        RotationAnimation on rotation {
            id: spinIn
            running: false
            from: 0; to: 45
            duration: IslandMotion.durationMedium
            easing.type: Easing.OutBack
        }
        RotationAnimation on rotation {
            id: spinOut
            running: false
            from: 45; to: 0
            duration: IslandMotion.durationMedium
            easing.type: Easing.InBack
        }
    }

    MouseArea {
        id: cogMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.toggled()
            if (root.isOpen) spinOut.running = true
            else spinIn.running = true
        }
    }
}
