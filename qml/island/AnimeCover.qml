import QtQuick
import Qt5Compat.GraphicalEffects

// A cover image with rounded corners. Falls back to a tinted gradient + the
// first letter when there is no URL or the download failed.
Item {
    id: cover
    property string source: ""
    property string label: ""
    property real   radius: 10

    readonly property bool ready: img.status === Image.Ready && source !== ""
    readonly property real hue: {
        let h = 0
        for (let i = 0; i < label.length; i++) h = (h * 31 + label.charCodeAt(i)) % 360
        return h / 360
    }

    Rectangle {
        anchors.fill: parent
        radius: cover.radius
        visible: !cover.ready
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla(cover.hue, 0.38, 0.40, 1) }
            GradientStop { position: 1; color: Qt.hsla((cover.hue + 0.08) % 1, 0.42, 0.20, 1) }
        }
        Text {
            anchors.centerIn: parent
            renderType: Text.NativeRendering
            text: cover.label.length > 0 ? cover.label.charAt(0).toUpperCase() : ""
            font.pixelSize: Math.max(12, Math.min(cover.width, cover.height) * 0.42)
            color: "white"
            opacity: 0.35
        }
    }

    Image {
        id: img
        anchors.fill: parent
        visible: false
        source: cover.source
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.max(1, cover.width) * 2, Math.max(1, cover.height) * 2)
    }
    Rectangle { id: coverMask; anchors.fill: parent; radius: cover.radius; visible: false }
    OpacityMask { anchors.fill: parent; source: img; maskSource: coverMask; visible: cover.ready }

    Rectangle {
        anchors.fill: parent; radius: cover.radius
        color: "transparent"
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
    }
}
