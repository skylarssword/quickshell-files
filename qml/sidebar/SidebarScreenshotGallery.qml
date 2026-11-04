import QtQuick
import Quickshell
import Quickshell.Wayland
import "../shared"
import "../island"

PanelWindow {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""

    property bool   gamemodeActive:      false
    property bool   useWalColor:         false
    property color  walColor:            "#000000"
    property real   capsuleOpacityValue: 0.20

    readonly property color capsuleColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    property bool galleryOpen: false

    function open()  { galleryOpen = true  }
    function close() { galleryOpen = false }
    function toggle(){ galleryOpen = !galleryOpen }

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: galleryOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: galleryOpen
    visible: galleryOpen

    mask: Region {
        Region {
            x: Math.floor(capsule.x)
            y: Math.floor(capsule.y)
            width:  galleryOpen ? Math.ceil(capsule.width)  : 0
            height: galleryOpen ? Math.ceil(capsule.height) : 0
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.galleryOpen
        onClicked: root.close()
        z: -1
    }

    Keys.onEscapePressed: root.close()

    Item {
        id: capsule
        width:  700
        height: 420
        anchors.centerIn: parent

        opacity: root.galleryOpen ? 1 : 0
        scale:   root.galleryOpen ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: root.capsuleColor
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            clip: true
        }

        Loader {
            anchors.fill: parent
            active: root.galleryOpen
            asynchronous: false

            sourceComponent: Component {
                ScreenshotGalleryLayer {
                    iconFontFamily: root.iconFontFamily
                    textFontFamily: root.textFontFamily
                    showCondition:  root.galleryOpen
                    onCloseRequested: root.close()
                }
            }

            onLoaded: if (item) item.forceActiveFocus()
        }
    }
}
