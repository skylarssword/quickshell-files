import QtQuick
import Quickshell.Services.SystemTray

Item {
    id: root
    anchors.fill: parent

    readonly property int iconSize: 16
    readonly property int iconSpacing: 6
    readonly property int iconCount: trayRepeater.count
    readonly property real trayWidth: iconCount > 0 ? (iconCount * (iconSize + iconSpacing)) : 0

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: iconSpacing

        Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Item {
                width: root.iconSize
                height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    anchors.fill: parent
                    source: modelData.icon !== "" ? "image://icon/" + modelData.icon : ""
                    fillMode: Image.PreserveAspectFit
                    visible: source.toString() !== ""
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
		    z: 10
                    onClicked: {
                        if (modelData.hasMenu)
                            modelData.menu.show(0, 0)
                    }
                }
            }
        }
    }
}
