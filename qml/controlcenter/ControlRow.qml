import QtQuick
import "../shared"

Item {
    id: root

    signal clicked()

    property string glyph: ""
    property string title: ""
    property string sub: ""
    property bool active: false
    property bool clickable: true
    property string iconFontFamily: ""
    property string textFontFamily: ""

    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        anchors.margins: -6
        radius: 16
        color: !root.clickable ? Qt.rgba(1, 1, 1, 0)
               : (rowArea.pressed ? Qt.rgba(1, 1, 1, 0.14)
                  : (rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0)))

        Behavior on color {
            ColorAnimation {
                duration: IslandMotion.micro
            }
        }
    }

    Rectangle {
        id: disc
        width: 40
        height: 40
        radius: 20
        color: root.active ? IslandMotion.textPrimary : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Text {
            renderType: Text.NativeRendering
            anchors.centerIn: parent
            text: root.glyph
            color: root.active ? IslandMotion.onLightInk : IslandMotion.textPrimary
            font.pixelSize: 17
            font.family: root.iconFontFamily
            scale: (root.clickable && rowArea.pressed) ? 0.8 : 1.0

            Behavior on scale {
                NumberAnimation {
                    duration: rowArea.pressed ? 90 : 340
                    easing.type: rowArea.pressed ? Easing.OutQuad : Easing.OutBack
                    easing.overshoot: 3.2
                }
            }
        }
    }

    Column {
        anchors.left: disc.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            renderType: Text.NativeRendering
            width: parent.width
            text: root.title
            color: IslandMotion.textPrimary
            font.pixelSize: 14
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            renderType: Text.NativeRendering
            width: parent.width
            visible: text.length > 0
            text: root.sub
            color: IslandMotion.textFaint
            font.pixelSize: 11
            font.family: root.textFontFamily
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.clickable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
