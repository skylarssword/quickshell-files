import QtQuick
import "../shared"

Item {
    id: root

    property bool showCondition: false
    property var device: null
    property real volumeLevel: -1
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""

    signal volumeChangeRequested(real value)

    property real _pendingVolume: -1

    Timer {
        id: volumeDebounce
        interval: 40
        repeat: false
        onTriggered: if (root._pendingVolume >= 0) root.volumeChangeRequested(root._pendingVolume)
    }

    function _seekVolume(trackX) {
        const clamped = Math.max(0, Math.min(volumeTrack.width, trackX))
        root._pendingVolume = clamped / volumeTrack.width
        volumeDebounce.restart()
    }

    readonly property string deviceName: {
        if (!device) return "Bluetooth device";

        const preferred = String(device.deviceName === undefined || device.deviceName === null ? "" : device.deviceName).trim();
        if (preferred.length > 0) return preferred;

        const alias = String(device.name === undefined || device.name === null ? "" : device.name).trim();
        if (alias.length > 0) return alias;

        const address = String(device.address === undefined || device.address === null ? "" : device.address).trim();
        return address.length > 0 ? address : "Bluetooth device";
    }
    readonly property bool batteryAvailable: !!(device && device.batteryAvailable)
    readonly property real batteryRawValue: batteryAvailable ? Math.max(0, Number(device.battery) || 0) : -1
    readonly property int batteryPercent: batteryAvailable
        ? Math.max(0, Math.min(100, Math.round(batteryRawValue <= 1 ? batteryRawValue * 100 : batteryRawValue)))
        : -1
    readonly property bool volumeAvailable: volumeLevel >= 0
    readonly property int volumePercent: volumeAvailable
        ? Math.max(0, Math.min(100, Math.round(volumeLevel * 100)))
        : -1
    readonly property color batteryColor: {
        if (!batteryAvailable) return "#5d6068";
        if (batteryPercent <= 10) return "#ff3b30";
        if (batteryPercent <= 20) return "#ffcc00";
        return IslandMotion.textPrimary;
    }

    anchors.fill: parent
    anchors.margins: 20
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: showCondition ? IslandMotion.contentEnterDelay : 0 }
            NumberAnimation {
                duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
            }
        }
    }

    Item {
        anchors.fill: parent

        Text {
            id: bluetoothIcon
            renderType: Text.NativeRendering
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 2
            width: 36
            horizontalAlignment: Text.AlignLeft
            text: root.iconText
            color: IslandMotion.textPrimary
            font.pixelSize: 30
            font.family: root.iconFontFamily
        }

        Row {
            id: batteryRow
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 2
            spacing: 8

            Text {
                renderType: Text.NativeRendering
                anchors.verticalCenter: parent.verticalCenter
                text: root.batteryAvailable ? root.batteryPercent + "%" : "--"
                color: root.batteryAvailable ? IslandMotion.textPrimary : IslandMotion.textFaint
                font.pixelSize: 14
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
            }

            Item {
                width: 28
                height: 14
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 2
                    radius: 4
                    color: "transparent"
                    border.color: IslandMotion.textSecondary
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        radius: 2
                        width: root.batteryAvailable ? (parent.width - 4) * (root.batteryPercent / 100.0) : 0
                        color: root.batteryColor

                        Behavior on width {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 160 }
                        }
                    }
                }
                Rectangle {
                    width: 2
                    height: 6
                    radius: 1
                    color: IslandMotion.textSecondary
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Column {
            anchors.left: bluetoothIcon.right
            anchors.leftMargin: 10
            anchors.right: batteryRow.left
            anchors.rightMargin: 12
            anchors.top: parent.top
            spacing: 3

            Text {
                renderType: Text.NativeRendering
                width: parent.width
                text: root.deviceName
                color: IslandMotion.textPrimary
                font.pixelSize: 16
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                renderType: Text.NativeRendering
                width: parent.width
                text: "Connected"
                color: IslandMotion.textSecondary
                font.pixelSize: 12
                font.family: root.textFontFamily
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            height: 18

            Text {
                id: volumeLabel
                renderType: Text.NativeRendering
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Volume"
                color: IslandMotion.textPrimary
                font.pixelSize: 13
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
            }
            Text {
                id: volumeValue
                renderType: Text.NativeRendering
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                horizontalAlignment: Text.AlignRight
                text: root.volumeAvailable ? root.volumePercent : "--"
                color: IslandMotion.textSecondary
                font.pixelSize: 13
                font.family: root.textFontFamily
                font.weight: Font.Medium
            }
            Rectangle {
                id: volumeTrack
                anchors.left: volumeLabel.right
                anchors.leftMargin: 14
                anchors.right: volumeValue.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                radius: 9
                color: Qt.rgba(1, 1, 1, 0.18)

                Rectangle {
                    width: root.volumeAvailable && root.volumePercent > 0
                        ? Math.max(parent.height, parent.width * (root.volumePercent / 100.0))
                        : 0
                    height: parent.height
                    radius: parent.radius
                    color: IslandMotion.textPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    enabled: root.volumeAvailable
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: (mouse) => root._seekVolume(mouse.x - 10)
                    onPositionChanged: (mouse) => { if (pressed) root._seekVolume(mouse.x - 10) }
                }
            }
        }
    }
}
