import QtQuick
import "../shared"

Rectangle {
    id: root

    signal clicked()
    signal rightClicked()

    property string label: ""
    property bool active: false
    property int sidePadding: 12
    property int fontSize: 12
    property string textFontFamily: ""

    implicitWidth: pillLabel.implicitWidth + sidePadding * 2
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    scale: pillArea.pressed ? 0.94 : 1.0
    color: active
           ? (pillArea.containsMouse ? Qt.rgba(1, 1, 1, 0.88) : IslandMotion.textPrimary)
           : (pillArea.pressed ? Qt.rgba(1, 1, 1, 0.16)
              : (pillArea.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0)))

    Behavior on color {
        ColorAnimation {
            duration: IslandMotion.micro
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: pillArea.pressed ? 90 : 340
            easing.type: pillArea.pressed ? Easing.OutQuad : Easing.OutBack
            easing.overshoot: 3
        }
    }

    Text {
        id: pillLabel
        renderType: Text.NativeRendering
        anchors.centerIn: parent
        text: root.label
        color: root.active ? IslandMotion.onLightInk : IslandMotion.textSecondary
        font.pixelSize: root.fontSize
        font.family: root.textFontFamily
        font.weight: root.active ? Font.DemiBold : Font.Medium
    }

    MouseArea {
        id: pillArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }
}
