import QtQuick
import Quickshell.Io
import "../shared"

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

        PowerMenuButton {
            glyph: "\uf023"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup hyprlock >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        PowerMenuButton {
            glyph: "\uf186"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup systemctl suspend >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        PowerMenuButton {
            glyph: "\uf2f5"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup uwsm stop >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        PowerMenuButton {
            glyph: "\uf021"
            iconFontFamily: root.iconFontFamily
            onActivated: {
                powerExec.run("nohup systemctl reboot >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

        PowerMenuButton {
            glyph: "\uf011"
            iconFontFamily: root.iconFontFamily
            dangerHover: true
            onActivated: {
                powerExec.run("nohup systemctl poweroff >/dev/null 2>&1 &")
                root.closeRequested()
            }
        }

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
