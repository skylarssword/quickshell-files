import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import IslandBackend
import "../shared"

PanelWindow {
    id: root

    property string textFontFamily: ""
    property string iconFontFamily: ""
    property bool   useWalColor:         false
    property color  walColor:            "#000000"
    property real   capsuleOpacityValue: 0.20
    property bool   gamemodeActive:      false

    Process {
        id: gamemodeCheck
        command: ["bash", "-c",
            "[ -f \"$HOME/.config/ml4w/settings/gamemode-enabled\" ] && echo 1 || echo 0"]
        property string _buf: ""
        stdout: SplitParser { onRead: gamemodeCheck._buf += data }
        onRunningChanged: {
            if (!running) {
                root.gamemodeActive = gamemodeCheck._buf.trim() === "1"
                gamemodeCheck._buf = ""
            }
        }
    }

    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!gamemodeCheck.running) gamemodeCheck.running = true
    }

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    readonly property real toastW: 280
    readonly property real toastH: 64

    property string _icon:    ""
    property string _label:   ""
    property real   _progress: 0.0
    property bool   _showing: false

    function showVolume(level, muted) {
        _progress = Math.max(0, Math.min(1, level))
        _label    = Math.round(level * 100) + "%"
        _icon     = muted ? "\u{F075F}" : "\u{F057E}"
        _showing  = true
        autoHide.restart()
    }

    function showBrightness(level) {
        _progress = Math.max(0, Math.min(1, level))
        _label    = Math.round(level * 100) + "%"
        if (level < 0.33)      _icon = "\u{F00DE}"
        else if (level < 0.67) _icon = "\u{F00DF}"
        else                   _icon = "\u{F00E0}"
        _showing = true
        autoHide.restart()
    }

    Timer {
        id: autoHide
        interval: 2500; repeat: false
        onTriggered: root._showing = false
    }

    // Always visible so animations can run
    color: "transparent"
    anchors { top: true; left: true; right: true }
    exclusiveZone: 0
    aboveWindows: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitHeight: toastH + 20
    visible: true

    mask: Region {
        x: _showing ? Math.floor(toast.x) : 0
        y: _showing ? Math.floor(toast.y) : 0
        width:  _showing ? Math.ceil(toast.width)  : 0
        height: _showing ? Math.ceil(toast.height) : 0
    }

    Item {
        id: toast
        width:  root.toastW
        height: root.toastH
        anchors.horizontalCenter: parent.horizontalCenter
        y: root._showing ? 12 : -(root.toastH + 8)

        Behavior on y {
            NumberAnimation {
                duration: 320
                easing.type: root._showing ? Easing.OutBack : Easing.InCubic
            }
        }

        opacity: root._showing ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent; radius: 20
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            id: osdIcon
            renderType: Text.NativeRendering
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: root._icon
            font.family: root.iconFontFamily
            font.pixelSize: 18
            color: "white"; opacity: 0.85
            width: 22; horizontalAlignment: Text.AlignHCenter
        }

        Column {
            anchors.left: osdIcon.right; anchors.leftMargin: 10
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                renderType: Text.NativeRendering
                text: root._label
                color: "white"
                font.family: root.textFontFamily
                font.pixelSize: 13; font.weight: Font.DemiBold
            }

            Rectangle {
                width: parent.width; height: 4; radius: 2
                color: Qt.rgba(1, 1, 1, 0.18)
                Rectangle {
                    width: parent.width * root._progress
                    height: parent.height; radius: 2
                    color: "white"
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root._showing = false
        }
    }
}
