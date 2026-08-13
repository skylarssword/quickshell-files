import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import IslandBackend
import "../shared"
import "../island"

// Sidebar power menu — centered on screen, replica of PowerMenuLayer
// without the settings/control-center button. Opened by the power
// icon at the bottom of the sidebar pill.

PanelWindow {
    id: root

    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"
    property bool   gamemodeActive:      false
    property bool   useWalColor:         false
    property color  walColor:            "#000000"
    property real   capsuleOpacityValue: 0.20

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    property bool popupOpen: false
    function open()  { popupOpen = true  }
    function close() { popupOpen = false }
    function toggle(){ popupOpen = !popupOpen }

    // ── Window setup ──────────────────────────────────────────────────
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: popupOpen

    mask: Region {
        Region {
            x: Math.floor(card.x); y: Math.floor(card.y)
            width:  root.popupOpen ? Math.ceil(card.width)  : 0
            height: root.popupOpen ? Math.ceil(card.height) : 0
        }
    }

    MouseArea { anchors.fill: parent; enabled: root.popupOpen; onClicked: root.close(); z: -1 }
    Keys.onEscapePressed: root.close()

    // ── Card ──────────────────────────────────────────────────────────
    Item {
        id: card
        anchors.centerIn: parent
        width:  buttonRow.implicitWidth  + 48
        height: buttonRow.implicitHeight + 48

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        Rectangle {
            anchors.fill: parent; radius: 28
            color: root.bgColor
            border.width: IslandMotion.surfaceBorderWidth
            border.color: IslandMotion.surfaceBorderColor
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 22

            // Lock
            PowerMenuButton {
                glyph: "\uf023"
                iconFontFamily: root.iconFontFamily
                onActivated: { powerExec.run("nohup hyprlock >/dev/null 2>&1 &"); root.close() }
            }

            // Sleep
            PowerMenuButton {
                glyph: "\uf186"
                iconFontFamily: root.iconFontFamily
                onActivated: { powerExec.run("nohup systemctl suspend >/dev/null 2>&1 &"); root.close() }
            }

            // Logout
            PowerMenuButton {
                glyph: "\uf2f5"
                iconFontFamily: root.iconFontFamily
                onActivated: { powerExec.run("nohup uwsm stop >/dev/null 2>&1 &"); root.close() }
            }

            // Reboot
            PowerMenuButton {
                glyph: "\uf021"
                iconFontFamily: root.iconFontFamily
                onActivated: { powerExec.run("nohup systemctl reboot >/dev/null 2>&1 &"); root.close() }
            }

            // Shutdown
            PowerMenuButton {
                glyph: "\uf011"
                iconFontFamily: root.iconFontFamily
                dangerHover: true
                onActivated: { powerExec.run("nohup systemctl poweroff >/dev/null 2>&1 &"); root.close() }
            }
        }
    }

    Process {
        id: powerExec
        function run(cmd) { command = ["bash", "-c", cmd]; running = true }
    }
}
