import QtQuick
import Quickshell
import Quickshell.Wayland
import IslandBackend
import "../shared"

PanelWindow {
    id: root

    property string textFontFamily: ""
    property string iconFontFamily: ""

    property bool  useWalColor:         false
    property color walColor:            "#000000"
    property real  capsuleOpacityValue: 0.20
    property bool  gamemodeActive:      false

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    readonly property real toastW: 320
    readonly property real toastH: 56

    property string _appName: ""
    property string _summary: ""
    property string _appIcon: ""
    property int    _entryId: -1
    property bool   _visible: false

    function showToast(appName, summary) {
        _appName = appName
        _summary = summary !== "" ? summary : "New notification"
        _appIcon = ""
        _visible = true
        autoHide.restart()
    }

    function updateIcon(appName, iconPath) {
        
        if (_visible && _appName === appName)
            _appIcon = iconPath
    }

    function hide() {
        _visible = false
        autoHide.stop()
    }

    Timer {
        id: autoHide
        interval: 4000
        repeat: false
        onTriggered: root.hide()
    }

    color: "transparent"
    anchors { top: true; left: true; right: true }
    exclusiveZone: 0
    aboveWindows: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitHeight: 80
    visible: _visible

    mask: Region {
        x: Math.floor(toast.x); y: Math.floor(toast.y)
        width:  Math.ceil(toast.width)
        height: Math.ceil(toast.height)
    }

    Item {
        id: toast
        width:  root.toastW
        height: root.toastH

        anchors.horizontalCenter: parent.horizontalCenter
        y: root._visible ? 12 : -root.toastH - 4

        Behavior on y {
            NumberAnimation {
                duration: IslandMotion.durationMedium
                easing.type: root._visible ? Easing.OutBack : Easing.InCubic
            }
        }

        opacity: root._visible ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            clip: true

            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16; anchors.rightMargin: 16
            anchors.topMargin: 10; anchors.bottomMargin: 10
            spacing: 12

            Item {
                width: 26; height: 26
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: toastIconImg
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true; cache: true
                    visible: status === Image.Ready
                    source: root._appIcon !== "" ? "file://" + root._appIcon : ""
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    visible: !toastIconImg.visible
                    text: "\uf0f3"
                    font.family: root.iconFontFamily
                    font.pixelSize: 16
                    color: "white"; opacity: 0.7
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 26 - 12
                spacing: 2

                Text {
                    renderType: Text.NativeRendering
                    width: parent.width
                    text: root._appName
                    color: "white"; opacity: 0.55
                    font.family: root.textFontFamily
                    font.pixelSize: 10; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    renderType: Text.NativeRendering
                    width: parent.width
                    text: root._summary
                    color: "white"
                    font.family: root.textFontFamily
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    font.letterSpacing: -0.1
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.hide()
        }
    }
}
