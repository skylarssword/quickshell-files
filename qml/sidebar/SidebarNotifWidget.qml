import QtQuick
import Quickshell
import IslandBackend
import "../shared"

// ── Notification bell button inside the sidebar pill ─────────────────────────
// SVG assets from SystrayBubble. Shakes on new notification (call shake()).
// Badge shows unread count. Right-click toggles DND.

Item {
    id: root

    property real   pillWidth:      38
    property string iconFontFamily: ""
    property bool   dndActive:      false
    property int    unreadCount:    0
    property bool   isOpen:         false

    signal toggled()
    signal dndToggleRequested()

    function shake() {
        if (!root.dndActive) bellWobble.restart()
    }

    width:  pillWidth
    height: pillWidth

    Image {
        id: bellImg
        anchors.centerIn: parent
        width: 20; height: 20
        source: root.dndActive
            ? Quickshell.shellDir + "/qml/shared/assets/notification-off.svg"
            : Quickshell.shellDir + "/qml/shared/assets/notification.svg"
        sourceSize: Qt.size(40, 40)
        fillMode: Image.PreserveAspectFit
        opacity: root.isOpen ? 1.0 : (bellMouse.containsMouse ? 1.0 : 0.65)
        scale:   bellMouse.containsMouse ? 1.15 : (bellMouse.pressed ? 0.82 : 1.0)
        Behavior on opacity { NumberAnimation { duration: IslandMotion.micro } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.micro; easing.type: Easing.OutBack } }

        transformOrigin: Item.Top

        SequentialAnimation {
            id: bellWobble
            NumberAnimation { target: bellImg; property: "rotation"; to:  16; duration: 70;  easing.type: Easing.OutQuad }
            NumberAnimation { target: bellImg; property: "rotation"; to: -14; duration: 100; easing.type: Easing.InOutQuad }
            NumberAnimation { target: bellImg; property: "rotation"; to:   8; duration: 90;  easing.type: Easing.InOutQuad }
            NumberAnimation { target: bellImg; property: "rotation"; to:   0; duration: 90;  easing.type: Easing.OutQuad }
        }
    }

    // Unread count badge
    Rectangle {
        visible: root.unreadCount > 0 && !root.dndActive
        anchors.top:   bellImg.top
        anchors.right: bellImg.right
        anchors.topMargin:   -2
        anchors.rightMargin: -2
        width: 14; height: 14; radius: 7
        color: "#ff6b6b"
        z: 2

        Text {
            anchors.centerIn: parent
            text: root.unreadCount > 9 ? "9+" : String(root.unreadCount)
            color: "white"
            font.pixelSize: 7
            font.weight: Font.Bold
            font.family: root.iconFontFamily
            renderType: Text.NativeRendering
        }
    }

    MouseArea {
        id: bellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.dndToggleRequested()
            else
                root.toggled()
        }
    }
}
