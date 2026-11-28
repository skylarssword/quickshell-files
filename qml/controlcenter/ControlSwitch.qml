import QtQuick
import IslandBackend
import "../shared"

Rectangle {
    id: root

    signal toggled()

    property bool on: false
    property bool interactive: true

    width: 38
    height: 22
    radius: 11
    color: on ? IslandMotion.textPrimary : StyleTokens.switchOff

    Behavior on color {
        ColorAnimation {
            duration: StyleTokens.durationFast
        }
    }

    Rectangle {
        width: switchArea.pressed ? 20 : 16
        height: 16
        radius: 8
        y: 3
        x: root.on ? root.width - width - 3 : 3
        color: root.on ? IslandMotion.onLightInk : IslandMotion.textSecondary

        Behavior on x {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: switchArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.interactive
        onClicked: root.toggled()
    }
}
