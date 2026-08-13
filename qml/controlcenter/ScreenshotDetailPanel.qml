import QtQuick
import QtQuick.Controls
import Quickshell.Io
import IslandBackend

Item {
    id: panel

    property string iconFontFamily: ""
    property string textFontFamily: ""

    signal captureRequested(string mode, int delay)

    property string screenshotMode: "area"
    property int screenshotDelay: 0
    property string _ssBuf: ""

    ListModel { id: recentModel }

    Process {
        id: recentLoader
        command: ["bash", "-c",
            "DIR=\"$HOME/Pictures/Screenshots\"\n" +
            "mkdir -p \"$DIR\"\n" +
            "find \"$DIR\" -maxdepth 1 -type f " +
            "\\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) " +
            "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -20 | cut -f2-"
        ]
        stdout: SplitParser {
            onRead: function(data) { panel._ssBuf += data + "\n" }
        }
        onRunningChanged: {
            if (!running) {
                recentModel.clear()
                let lines = panel._ssBuf.trim().split("\n")
                panel._ssBuf = ""
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
        function run(path) { command = ["bash", "-c", "wl-copy < " + JSON.stringify(path)]; running = true }
    }

Process {
        id: openExec
        function run(path) { command = ["bash", "-c", "xdg-open " + JSON.stringify(path)]; running = true }
    }

    Process {
        id: folderExec
        function run() { command = ["bash", "-c", "xdg-open \"$HOME/Pictures/Screenshots\""]; running = true }
    }

    Process {
        id: deleteExec
        function run(path) { command = ["bash", "-c", "rm -f " + JSON.stringify(path)]; running = true }
    }

    Component.onCompleted: recentLoader.running = true

    Column {
        anchors.fill: parent
        spacing: 12

        // ── Header ─────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 0

            Text {
                renderType: Text.NativeRendering
                text: "\uf030  Screenshot"
                color: "white"
                font.pixelSize: 14
                font.family: panel.textFontFamily
                font.weight: Font.Bold
                opacity: 0.9
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - refreshBtn.width
            }

            Rectangle {
                id: refreshBtn
                width: 28; height: 28; radius: 8
                color: refMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                Behavior on color { ColorAnimation { duration: 120 } }
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "\uf021"
                    font.family: panel.iconFontFamily
                    font.pixelSize: 13
                    color: "white"; opacity: 0.7
                }
                MouseArea {
                    id: refMouse; anchors.fill: parent; hoverEnabled: true
                    onClicked: recentLoader.running = true
                }
            }
        }

        // ── Mode picker ────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6

            Text {
                renderType: Text.NativeRendering
                text: "MODE"
                color: "white"; opacity: 0.4
                font.pixelSize: 9; font.family: panel.textFontFamily; font.weight: Font.Bold
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { id: "area",   icon: "\uf0c8", label: "Area" },
                        { id: "screen", icon: "\uf26c", label: "Full Screen" },
                        { id: "active", icon: "\uf2d0", label: "Window" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        property bool sel: panel.screenshotMode === modelData.id
                        width: (parent.width - 12) / 3
                        height: 54; radius: 14
                        color: sel ? Qt.rgba(1,1,1,0.18) : (modeMouse.containsMouse ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04))
                        border.color: sel ? Qt.rgba(1,1,1,0.5) : Qt.rgba(1,1,1,0.1)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 130 } }
                        scale: modeMouse.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        Column {
                            anchors.centerIn: parent; spacing: 4
                            Text {
                                renderType: Text.NativeRendering
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.family: panel.iconFontFamily; font.pixelSize: 16
                                color: "white"; opacity: sel ? 1.0 : 0.5
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            Text {
                                renderType: Text.NativeRendering
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.family: panel.textFontFamily; font.pixelSize: 10
                                color: "white"; opacity: sel ? 0.9 : 0.4; font.weight: sel ? Font.Bold : Font.Normal
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                        }
                        MouseArea {
                            id: modeMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: panel.screenshotMode = modelData.id
                        }
                    }
                }
            }
        }

        // ── Delay picker ───────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6

            Text {
                renderType: Text.NativeRendering
                text: "DELAY"
                color: "white"; opacity: 0.4
                font.pixelSize: 9; font.family: panel.textFontFamily; font.weight: Font.Bold
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { val: 0,  label: "Now" },
                        { val: 3,  label: "3s" },
                        { val: 5,  label: "5s" },
                        { val: 10, label: "10s" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        property bool sel: panel.screenshotDelay === modelData.val
                        width: (parent.width - 18) / 4
                        height: 34; radius: 10
                        color: sel ? Qt.rgba(1,1,1,0.18) : (delayMouse.containsMouse ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04))
                        border.color: sel ? Qt.rgba(1,1,1,0.5) : Qt.rgba(1,1,1,0.1)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 130 } }
                        scale: delayMouse.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        Text {
                            renderType: Text.NativeRendering
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: panel.textFontFamily; font.pixelSize: 12
                            color: "white"; opacity: sel ? 1.0 : 0.45; font.weight: sel ? Font.Bold : Font.Normal
                            Behavior on opacity { NumberAnimation { duration: 130 } }
                        }
                        MouseArea {
                            id: delayMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: panel.screenshotDelay = modelData.val
                        }
                    }
                }
            }
        }

        // ── Capture button ─────────────────────────────────────────────────
        Rectangle {
            width: parent.width; height: 44; radius: 14
            color: captureBtnMouse.containsMouse ? Qt.rgba(1,1,1,0.22) : Qt.rgba(1,1,1,0.14)
            border.color: Qt.rgba(1,1,1,0.3); border.width: 1
            Behavior on color { ColorAnimation { duration: 130 } }
            scale: captureBtnMouse.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

            Row {
                anchors.centerIn: parent; spacing: 8
                Text {
                    renderType: Text.NativeRendering
                    text: "\uf030"
                    font.family: panel.iconFontFamily; font.pixelSize: 16
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    renderType: Text.NativeRendering
                    text: "Capture"
                    font.family: panel.textFontFamily; font.pixelSize: 14; font.weight: Font.Bold
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: captureBtnMouse; anchors.fill: parent; hoverEnabled: true
                onClicked: panel.captureRequested(panel.screenshotMode, panel.screenshotDelay)
            }
        }

        // ── Recent screenshots ─────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6

            Row {
                width: parent.width
                Text {
                    renderType: Text.NativeRendering
                    text: "RECENT"
                    color: "white"; opacity: 0.4
                    font.pixelSize: 9; font.family: panel.textFontFamily; font.weight: Font.Bold
                    width: parent.width - openFolderBtn.width
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    id: openFolderBtn
                    width: 28; height: 28; radius: 8
                    color: folderMouse.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: "\uf07c"
                        font.family: panel.iconFontFamily; font.pixelSize: 13
                        color: "white"; opacity: 0.7
                    }
MouseArea {
                        id: folderMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: folderExec.run()
                    }
                }
            }

Item {
                width: parent.width
                height: panel.height
                       - 28        // header
                       - 12        // spacing
                       - 72        // mode picker column
                       - 12
                       - 52        // delay picker column
                       - 12
                       - 44        // capture btn
                       - 12
                       - 28        // recent header row
                       - 12        // spacing
                       - 6
                clip: true

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: "No screenshots yet"
                    color: "white"; opacity: 0.3
                    font.pixelSize: 12; font.family: panel.textFontFamily
                    visible: recentModel.count === 0
                }

ListView {
                    anchors.fill: parent
                    model: recentModel
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: 3; radius: 2; color: "white"; opacity: 0.2 }
                    }
                    interactive: true

                    WheelHandler {
                        target: parent
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            parent.contentY = Math.max(0,
                                Math.min(parent.contentHeight - parent.height,
                                    parent.contentY - event.angleDelta.y * 0.5))
                            event.accepted = true
                        }
                    }


                    delegate: Rectangle {
                        required property int index
                        required property string ssPath
                        required property string ssName

width: ListView.view.width; height: 60; radius: 12
                        clip: true
                        color: rowMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.04)
                        border.color: Qt.rgba(1,1,1,0.1); border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

Row {
                            anchors.fill: parent; anchors.margins: 8; spacing: 6

                            Rectangle {
                                width: 70; height: 44; radius: 8
                                color: Qt.rgba(0,0,0,0.2); clip: true
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + ssPath
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; cache: true
                                    sourceSize.width: 140; sourceSize.height: 88
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                width: parent.width - 70 - 6 - 90 - 6

                                Text {
                                    renderType: Text.NativeRendering
                                    text: ssName
                                    color: "white"; opacity: 0.8
                                    font.pixelSize: 10; font.family: panel.textFontFamily
                                    elide: Text.ElideRight; width: parent.width
                                }
                                Text {
                                    renderType: Text.NativeRendering
                                    text: "Click to copy"
                                    color: "white"; opacity: 0.3
                                    font.pixelSize: 9; font.family: panel.textFontFamily
                                }
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: copyMouse.containsMouse ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        renderType: Text.NativeRendering
 anchors.centerIn: parent; text: "\uf0c5"; font.family: panel.iconFontFamily; font.pixelSize: 12; color: "white"; opacity: 0.7 }
                                    MouseArea { id: copyMouse; anchors.fill: parent; hoverEnabled: true; onClicked: copyExec.run(ssPath) }
                                }

                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: openMouse.containsMouse ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        renderType: Text.NativeRendering
 anchors.centerIn: parent; text: "\uf35d"; font.family: panel.iconFontFamily; font.pixelSize: 12; color: "white"; opacity: 0.7 }
                                    MouseArea { id: openMouse; anchors.fill: parent; hoverEnabled: true; onClicked: openExec.run(ssPath) }
                                }

                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: deleteMouse.containsMouse ? Qt.rgba(1,0.2,0.2,0.35) : Qt.rgba(1,1,1,0.08)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        renderType: Text.NativeRendering
 anchors.centerIn: parent; text: "\uf1f8"; font.family: panel.iconFontFamily; font.pixelSize: 12; color: deleteMouse.containsMouse ? "#ff6b6b" : "white"; opacity: 0.7 }
                                    MouseArea {
                                        id: deleteMouse; anchors.fill: parent; hoverEnabled: true
                                        onClicked: {
                                            deleteExec.run(ssPath)
                                            recentModel.remove(index)
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse; anchors.fill: parent
                            anchors.rightMargin: 96
                            hoverEnabled: true
                            onClicked: copyExec.run(ssPath)
                        }
                    }
                }
            }
        }
    }
}
