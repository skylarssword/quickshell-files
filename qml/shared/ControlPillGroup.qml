import QtQuick

Item {
    id: root

    signal activated(int index)

    property var model: []
    property int currentIndex: -1
    property int pillHeight: 28
    property int sidePadding: 12
    property int fontSize: 12
    property int spacing: 2
    property string textFontFamily: ""

    readonly property Item currentCell: {
        pillRepeater.count;
        return currentIndex >= 0 ? pillRepeater.itemAt(currentIndex) : null;
    }

    implicitWidth: pillRow.width
    implicitHeight: pillHeight
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: highlight
        visible: root.currentCell !== null
        x: root.currentCell ? root.currentCell.x : 0
        width: root.currentCell ? root.currentCell.width : 0
        height: root.pillHeight
        radius: height / 2
        color: IslandMotion.textPrimary

        Behavior on x {
            NumberAnimation {
                duration: 260
                easing.type: IslandMotion.easeOut
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: 260
                easing.type: IslandMotion.easeOut
            }
        }
    }

    Row {
        id: pillRow
        spacing: root.spacing

        Repeater {
            id: pillRepeater
            model: root.model

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === root.currentIndex

                width: pillLabel.implicitWidth + root.sidePadding * 2
                height: root.pillHeight

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: cellArea.pressed
                           ? Qt.rgba(1, 1, 1, 0.16)
                           : ((cellArea.containsMouse && !cell.isCurrent) ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0))

                    Behavior on color {
                        ColorAnimation {
                            duration: IslandMotion.micro
                        }
                    }
                }

                Text {
                    id: pillLabel
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: String(cell.modelData)
                    font.pixelSize: root.fontSize
                    font.family: root.textFontFamily
                    font.weight: cell.isCurrent ? Font.DemiBold : Font.Medium
                    color: cell.isCurrent
                           ? IslandMotion.onLightInk
                           : (cellArea.containsMouse ? IslandMotion.textPrimary : IslandMotion.textSecondary)
                    scale: cellArea.pressed ? 0.88 : 1.0

                    Behavior on color {
                        ColorAnimation {
                            duration: IslandMotion.micro
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: cellArea.pressed ? 90 : 340
                            easing.type: cellArea.pressed ? Easing.OutQuad : Easing.OutBack
                            easing.overshoot: 3
                        }
                    }
                }

                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activated(cell.index)
                }
            }
        }
    }
}
