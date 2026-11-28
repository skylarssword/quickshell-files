import QtQuick
import "../shared"

Item {
    id: root

    signal toggled()
    signal detailRequested()
    signal contextRequested()

    property string glyph: ""
    property string label: ""
    property string status: ""
    property bool active: false
    property bool hasDetail: false
    property bool detailOpen: false
    property bool toggleEnabled: true
    property string iconFontFamily: ""
    property string textFontFamily: ""

    implicitHeight: 82

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.contextRequested()
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Rectangle {
            id: disc
            width: 46
            height: 46
            radius: 23
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.active
                   ? (discArea.containsMouse ? Qt.rgba(1, 1, 1, 0.88) : IslandMotion.textPrimary)
                   : (discArea.pressed ? Qt.rgba(1, 1, 1, 0.16)
                      : (discArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0)))
            opacity: root.toggleEnabled ? 1 : 0.45

            Behavior on color {
                ColorAnimation {
                    duration: IslandMotion.micro
                }
            }

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: root.glyph
                color: root.active ? IslandMotion.onLightInk : IslandMotion.textPrimary
                font.pixelSize: 18
                font.family: root.iconFontFamily
                scale: discArea.pressed ? 0.8 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: discArea.pressed ? 90 : 340
                        easing.type: discArea.pressed ? Easing.OutQuad : Easing.OutBack
                        easing.overshoot: 3.2
                    }
                }
            }

            MouseArea {
                id: discArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.toggleEnabled
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled()
            }
        }

        Item {
            width: detailColumn.width
            height: detailColumn.height
            anchors.horizontalCenter: parent.horizontalCenter

            MouseArea {
                id: detailArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                enabled: root.hasDetail
                cursorShape: Qt.PointingHandCursor
                onClicked: root.detailRequested()
            }

            Column {
                id: detailColumn
                spacing: 2

                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.label
                    color: root.active ? IslandMotion.textPrimary : IslandMotion.textSecondary
                    font.pixelSize: 11
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, root.width - 4)
                    visible: text.length > 0
                    text: root.status + (root.hasDetail ? "  ›" : "")
                    color: (root.detailOpen || detailArea.containsMouse) ? IslandMotion.textPrimary : IslandMotion.textFaint

                Behavior on color {
                    ColorAnimation {
                        duration: IslandMotion.micro
                    }
                }
                    font.pixelSize: 10
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }
    }
}
