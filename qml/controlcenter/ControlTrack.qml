import QtQuick
import "../shared"

Item {
    id: root

    signal interactionStarted()
    signal valueMoved(real value)
    signal commitRequested()
    signal cancelRequested()

    property real value: 0

    readonly property bool pressed: trackArea.pressed

    function clamp01(nextValue) {
        return Math.max(0, Math.min(1, nextValue));
    }

    implicitHeight: 18

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.18)
    }

    Rectangle {
        width: root.value <= 0.001
            ? 0
            : Math.max(parent.height, Math.min(root.width, root.width * root.value + 1))
        height: parent.height
        radius: height / 2
        color: IslandMotion.textPrimary
    }

    MouseArea {
        id: trackArea
        anchors.fill: parent
        anchors.topMargin: -8
        anchors.bottomMargin: -8
        cursorShape: Qt.PointingHandCursor

        function update(mouseX) {
            root.valueMoved(root.clamp01(mouseX / width));
        }

        onPressed: function(mouse) {
            root.interactionStarted();
            update(mouse.x);
        }
        onPositionChanged: function(mouse) {
            if (pressed)
                update(mouse.x);
        }
        onReleased: root.commitRequested()
        onCanceled: root.cancelRequested()
    }
}
