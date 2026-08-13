import QtQuick
import IslandBackend
import "../shared"

// ── Slider card used inside SidebarControlCenterLayer ────────────────────────
// Replica of ControlSliderCard, self-contained.

Rectangle {
    id: root

    signal interactionStarted()
    signal valueMoved(real value)
    signal commitRequested()
    signal cancelRequested()

    property string title: ""
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property real   value: 0
    property real   knobSize: 24
    property color  moduleColor: Qt.rgba(1,1,1,0.05)
    property color  moduleHover: Qt.rgba(1,1,1,0.09)
    property color  trackColor:  StyleTokens.track
    property color  textPrimary: IslandMotion.textPrimary
    property color  textSecondary: IslandMotion.textSecondary
    readonly property bool pressed: sliderArea.pressed

    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    radius: 24
    color:  sliderArea.containsMouse ? moduleHover : moduleColor
    border.width: 1
    border.color: sliderArea.containsMouse ? Qt.rgba(1,1,1,0.30) : Qt.rgba(1,1,1,0.16)
    Behavior on color       { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Item {
        anchors.fill: parent; anchors.margins: 12

        Text {
            renderType: Text.NativeRendering
            anchors.left: parent.left; anchors.top: parent.top
            text: root.title; color: root.textPrimary
            font.pixelSize: 13; font.family: root.textFontFamily; font.weight: Font.DemiBold
        }

        Rectangle {
            id: sliderTrack
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 22; radius: 11; color: root.trackColor; clip: true

            // Icon
            Rectangle {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10; width: 18; height: 18; radius: 9; color: "transparent"
                Text {
                    renderType: Text.NativeRendering; anchors.centerIn: parent
                    text: root.iconText; color: root.textSecondary
                    font.pixelSize: 13; font.family: root.iconFontFamily
                }
            }

            // Fill
            Rectangle {
                width: root.value <= 0.001
                    ? 0
                    : Math.max(34, Math.min(sliderTrack.width, sliderTrack.width * root.value + 1))
                height: parent.height; radius: parent.radius; color: IslandMotion.textPrimary
            }

            // Knob
            Rectangle {
                x: Math.max(0, Math.min(parent.width - width, parent.width * root.value - width / 2))
                y: -1; width: root.knobSize; height: root.knobSize; radius: root.knobSize / 2
                color: StyleTokens.white
            }

            MouseArea {
                id: sliderArea; anchors.fill: parent; hoverEnabled: true
                function update(mx) { root.valueMoved(root.clamp01(mx / width)) }
                onPressed: function(mouse) { root.interactionStarted(); update(mouse.x) }
                onPositionChanged: function(mouse) { if (pressed) update(mouse.x) }
                onReleased: root.commitRequested()
                onCanceled: root.cancelRequested()
            }
        }
    }
}
