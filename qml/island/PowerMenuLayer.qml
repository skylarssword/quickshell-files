import QtQuick
import Quickshell.Io
import "../shared"

// Power menu island state: lock, sleep, logout, reboot, power,
// and settings (opens the control panel). Rendered inside the capsule
// like every other layer (search, control_center, etc), not a popup.
Item {
    id: root

    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"
    property bool showCondition: true

    signal openControlCenterRequested()
    signal closeRequested()

    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: showCondition ? IslandMotion.contentEnterDelay : 0 }
            NumberAnimation {
                duration: showCondition ? IslandMotion.contentEnterDuration : IslandMotion.contentExitDuration
                easing.type: showCondition ? IslandMotion.easeMove : IslandMotion.easeOut
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 22

        // Lock
        PowerMenuButton {
            glyph: "\uf023"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup hyprlock >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        // Sleep
        PowerMenuButton {
            glyph: "\uf186"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup systemctl suspend >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        // Logout
        PowerMenuButton {
            glyph: "\uf2f5"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup uwsm stop >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        // Reboot
        PowerMenuButton {
            glyph: "\uf021"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup systemctl reboot >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        // Shutdown
        PowerMenuButton {
            glyph: "\uf011"
            iconFontFamily: root.iconFontFamily
            dangerHover: true
            onActivated: {
                powerExec.run("nohup systemctl poweroff >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        // Settings / Control Center
        PowerMenuButton {
            glyph: "\uf013"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                root.openControlCenterRequested()
            }
        }
    }

    Process {
        id: powerExec

        function run(cmd) {
            command = ["bash", "-c", cmd]
            running = true
        }
    }
}
