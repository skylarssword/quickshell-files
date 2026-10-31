import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import IslandBackend
import "../shared"

Item {
    id: root

    property string iconFontFamily: ""
    property string textFontFamily: ""
    property bool showCondition: true

    signal closeRequested()

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

    focus: true
    Keys.onEscapePressed: root.closeRequested()

    onShowConditionChanged: {
        if (showCondition) { recentLoader.running = true; root.forceActiveFocus() }
    }

    Component.onCompleted: recentLoader.running = true

    readonly property int padding: 12
    readonly property int cols: 3
    readonly property int spacing: 8
    readonly property int cellW: Math.floor((root.width - padding * 2) / cols) - spacing
    readonly property int cellH: Math.floor(cellW * 9 / 16)
    readonly property int cellWOuter: cellW + spacing
    readonly property int cellHOuter: cellH + spacing

    property string _ssBuf: ""
    ListModel { id: recentModel }

    Process {
        id: recentLoader
        command: ["bash", "-c",
            "DIR=\"$HOME/Pictures/Screenshots\"\n" +
            "mkdir -p \"$DIR\"\n" +
            "find \"$DIR\" -maxdepth 1 -type f " +
            "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) " +
            "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -40 | cut -f2-"]
        stdout: SplitParser { onRead: function(data) { root._ssBuf += data + "\n" } }
        onRunningChanged: {
            if (!running) {
                recentModel.clear()
                let lines = root._ssBuf.trim().split("\n")
                root._ssBuf = ""
                for (let p of lines) {
                    let path = p.trim()
                    if (!path) continue
                    recentModel.append({ ssPath: path, ssName: path.split("/").pop() })
                }
            }
        }
    }

    Process {
        id: copyExec
        property var pendingCell: null
        function run(path, cell) {
            pendingCell = cell
            command = ["bash", "-c", "wl-copy < " + JSON.stringify(path)]
            running = true
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0 && pendingCell)
                pendingCell.markCopied()
            pendingCell = null
        }
    }

    Process {
        id: openExec
        function run(path) { command = ["bash", "-c", "loupe " + JSON.stringify(path) + " &"]; running = true }
    }

    Process {
        id: deleteExec
        function run(path) { command = ["bash", "-c", "rm -f " + JSON.stringify(path)]; running = true }
    }

    Item {
        anchors.fill: parent

        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            anchors.topMargin: root.padding

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: "screenshots"
                color: "white"
                opacity: 0.5
                font.pixelSize: 11
                font.family: root.textFontFamily
                font.weight: Font.Medium
            }

            Text {
                renderType: Text.NativeRendering
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf00d"
                font.family: root.iconFontFamily
                font.pixelSize: 12
                color: "white"
                opacity: closeMouse.containsMouse ? 0.9 : 0.4
                Behavior on opacity { NumberAnimation { duration: 120 } }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        GridView {
            id: ssGrid
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.padding
            anchors.rightMargin: root.padding
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            clip: true

            cellWidth: root.cellWOuter
            cellHeight: root.cellHOuter

            model: recentModel

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; radius: 2; color: "white"; opacity: 0.2 }
            }

            delegate: Item {
                id: ssCell
                width: ssGrid.cellWidth
                height: ssGrid.cellHeight

                required property int index
                required property string ssPath
                required property string ssName

                property bool copied: false
                function markCopied() {
                    copied = true
                    copiedTimer.restart()
                }
                Timer {
                    id: copiedTimer
                    interval: 1200
                    onTriggered: ssCell.copied = false
                }

                Item {
                    width: root.cellW
                    height: root.cellH
                    anchors.centerIn: parent

                    HoverHandler { id: cellHover }

                    Item {
                        id: thumbClip
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: thumbClip.width
                                height: thumbClip.height
                                radius: 8
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(1,1,1,0.05)
                        }

                        Image {
                            anchors.fill: parent
                            source: "file://" + ssCell.ssPath
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            cache: true
                            sourceSize.width: root.cellW * 2
                            sourceSize.height: root.cellH * 2
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: IslandMotion.surfaceBorderColor
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Qt.rgba(0,0,0,0.5)
                        opacity: cellHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Row {
                        z: 1
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 5
                        spacing: 4
                        visible: cellHover.hovered

                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: delBtnMouse.containsMouse ? Qt.rgba(1,0.2,0.2,0.7) : Qt.rgba(0,0,0,0.5)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: "\uf1f8"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: "white"; opacity: 0.9
                            }
                            MouseArea {
                                id: delBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    deleteExec.run(ssCell.ssPath)
                                    recentModel.remove(ssCell.index)
                                }
                            }
                        }

                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: ssCell.copied ? Qt.rgba(0.2,0.8,0.4,0.85)
                                : (cpyBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.25) : Qt.rgba(0,0,0,0.5))
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.centerIn: parent
                                text: ssCell.copied ? "\uf00c" : "\uf0c5"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: "white"; opacity: 0.9
                            }
                            MouseArea {
                                id: cpyBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    copyExec.run(ssCell.ssPath, ssCell)
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton)
                                copyExec.run(ssCell.ssPath, ssCell)
                            else
                                openExec.run(ssCell.ssPath)
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 20
            anchors.bottomMargin: root.padding / 2

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                text: recentModel.count + " screenshot" + (recentModel.count === 1 ? "" : "s")
                color: "white"
                opacity: 0.25
                font.pixelSize: 10
                font.family: root.textFontFamily
            }
        }
    }
}
