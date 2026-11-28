import QtQuick
import "../shared"

Item {
    id: root

    signal toggled()

    property string label: ""
    property bool on: false
    property string textFontFamily: ""

    implicitHeight: 38

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -8
        anchors.rightMargin: -8
        radius: 12
        color: rowArea.pressed
               ? Qt.rgba(1, 1, 1, 0.14)
               : (rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0))

        Behavior on color {
            ColorAnimation {
                duration: IslandMotion.micro
            }
        }
    }

    Text {
        renderType: Text.NativeRendering
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: IslandMotion.textPrimary
        font.pixelSize: 14
        font.family: root.textFontFamily
        font.weight: Font.DemiBold
    }

    ControlSwitch {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        on: root.on
        interactive: false
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
