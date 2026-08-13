import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import IslandBackend
import "../shared"

// ── Small circular music button inside the sidebar pill ──────────────────────
Item {
    id: root

    property real   pillWidth:     38
    property var    activePlayer:  null
    property string currentArtUrl: ""
    property string iconFontFamily: ""
    property bool   isOpen:        false

    signal toggled()

    readonly property bool isPlaying: activePlayer !== null
        && activePlayer.playbackState === MprisPlaybackState.Playing

    width:  pillWidth
    height: pillWidth

    Rectangle {
        id: circle
        anchors.centerIn: parent
        width: 28; height: 28; radius: 14

        color: root.isOpen
            ? Qt.rgba(1,1,1,0.18)
            : (btnMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06))

        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor

        Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

        scale: btnMouse.pressed ? 0.88 : 1.0
        Behavior on scale { NumberAnimation { duration: IslandMotion.micro; easing.type: Easing.OutBack } }

        // ── Spinning album art ─────────────────────────────────────────
        Item {
            id: artContainer
            anchors.fill: parent

            // Spin when playing, stop when paused
            RotationAnimation on rotation {
                running:   root.isPlaying
                from:      artContainer.rotation
                to:        artContainer.rotation + 360
                duration:  8000
                direction: RotationAnimation.Clockwise
                loops:     Animation.Infinite
            }
            // Smoothly stop at current angle when paused — no jerk
            NumberAnimation {
                running:  !root.isPlaying
                target:   artContainer
                property: "rotation"
                to:       artContainer.rotation
                duration: 400
                easing.type: Easing.OutCubic
            }

            Image {
                id: artImage
                anchors.fill: parent
                source: root.currentArtUrl
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(56, 56)
                smooth: true; mipmap: true
                visible: false
            }
            Rectangle {
                id: artMask
                anchors.fill: parent
                radius: parent.width / 2
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                source: artImage
                maskSource: artMask
                visible: root.currentArtUrl !== "" && artImage.status === Image.Ready
            }

            // Darken overlay when paused
            Rectangle {
                anchors.fill: parent
                radius: parent.width / 2
                color: "black"
                opacity: root.isPlaying ? 0 : 0.40
                visible: root.currentArtUrl !== "" && artImage.status === Image.Ready
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }

            // Pulse ring OVER art when playing
            Rectangle {
                anchors.fill: parent
                radius: parent.width / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(1,1,1,0.55)
                visible: root.isPlaying && root.currentArtUrl !== "" && artImage.status === Image.Ready
                SequentialAnimation on border.color {
                    running: root.isPlaying && root.currentArtUrl !== "" && artImage.status === Image.Ready
                    loops: Animation.Infinite
                    ColorAnimation { to: Qt.rgba(1,1,1,0.85); duration: 700; easing.type: Easing.InOutSine }
                    ColorAnimation { to: Qt.rgba(1,1,1,0.20); duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── Music note fallback ────────────────────────────────────────
        Text {
            anchors.centerIn: parent
            visible: root.currentArtUrl === "" || artImage.status !== Image.Ready
            text: "\uf001"
            font.family:    root.iconFontFamily
            font.pixelSize: 13
            color: root.isPlaying ? "white" : Qt.rgba(1,1,1,0.55)
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
        }

        // ── Pulse ring (no-art playing state) ─────────────────────────
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(1,1,1,0.55)
            visible: root.isPlaying && (root.currentArtUrl === "" || artImage.status !== Image.Ready)

            SequentialAnimation on border.color {
                running: root.isPlaying
                loops: Animation.Infinite
                ColorAnimation { to: Qt.rgba(1,1,1,0.85); duration: 700; easing.type: Easing.InOutSine }
                ColorAnimation { to: Qt.rgba(1,1,1,0.25); duration: 700; easing.type: Easing.InOutSine }
            }
        }
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                // Right-click: quick pause/play toggle
                if (!root.activePlayer || !root.activePlayer.canControl) return
                if (root.activePlayer.canTogglePlaying)
                    root.activePlayer.togglePlaying()
                else if (root.isPlaying) { if (root.activePlayer.canPause) root.activePlayer.pause() }
                else { if (root.activePlayer.canPlay) root.activePlayer.play() }
            } else {
                root.toggled()
            }
        }
    }
}
