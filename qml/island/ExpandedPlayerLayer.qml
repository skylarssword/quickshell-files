import QtQuick
import Quickshell.Hyprland
import IslandBackend
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import Quickshell.Io
import "../shared"

Item {
    id: root

    signal controlPressed()

    readonly property var userConfig: UserConfig
    property int mediaWorkspaceId: -1
    property string mediaPlayerName: ""
    property bool showCondition: false
    property string currentArtUrl: ""
    property string currentTrack: ""
    property string currentArtist: ""
    property string timePlayed: "0:00"
    property string timeTotal: "0:00"
    property real trackProgress: 0
    property var activePlayer: null
    property var cavaLevels: []
    
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property real visualizerPhase: 0
    property var walColors: null
    readonly property string cavaActiveColor: (walColors && walColors.colors && walColors.colors.color4) ? walColors.colors.color4 : "#FFFFFF"
    readonly property string cavaPausedColor: (walColors && walColors.colors && walColors.colors.color5) ? walColors.colors.color5 : "#202020"
    readonly property bool isPlaying: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing

Timer {
    interval: 16
    running: true
    repeat: true
    onTriggered: {
        console.log("len:", cavaLevels.length, cavaLevels)
    }
}

    Process {
        id: walColorsProc
        stdout: StdioCollector { id: walColorsOut }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return
            const text = walColorsOut.text
            if (text && text.length > 0)
                root.walColors = text
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            walColorsProc.command = ["cat", "/home/userone/.cache/wal/colors.sh"]
            walColorsProc.running = true
        }
    }

//player
   function visualizerLevel(index) {
    if (cavaLevels && cavaLevels.length > 0 && isPlaying) {
        const idx = Math.floor(index * cavaLevels.length / 6)
        const v = cavaLevels[idx] || 0

        // stronger response curve (fixes “too slow / too flat”)
        return Math.min(1.0, Math.pow(v, 1.4) * 1.2)
    }

    const phase = visualizerPhase + index * 0.78
    const primary = (Math.sin(phase) + 1) * 0.5
    const secondary = (Math.sin(phase * 2 + index * 0.95) + 1) * 0.5

    return 0.05 + primary * 0.35 + secondary * 0.2
}

//paused player
    function pausedVisualizerLevel(index) {
        const levels = [0.34, 0.58, 0.82, 0.82, 0.58, 0.34]
        return levels[index] || 0.4
    }

    function togglePlayback() {
        if (!activePlayer || !activePlayer.canControl) return
        if (activePlayer.canTogglePlaying) { activePlayer.togglePlaying(); return }
        if (activePlayer.playbackState === MprisPlaybackState.Playing) {
            if (activePlayer.canPause) activePlayer.pause()
            return
        }
        if (activePlayer.canPlay) activePlayer.play()
    }

    anchors.fill: parent
    anchors.margins: 20
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

    Timer {
        interval: 64
        repeat: true
        running: showCondition && isPlaying
        onTriggered: {
            visualizerPhase += 0.18
            if (visualizerPhase > Math.PI * 2) visualizerPhase -= Math.PI * 2
        }
    }

Column {
        anchors.fill: parent
        spacing: 14

        // ── Workspace indicator — fixed-height slot so the layout never
        // jumps between tracks/players; present but blank when no match
        // is found for the active player's window.
        Item {
            width: parent.width
            height: 7

            Text {
                renderType: Text.NativeRendering
                anchors.centerIn: parent
                visible: root.mediaWorkspaceId >= 1 && root.activePlayer !== null
                text: {
                    const id = root.activePlayer ? String(root.activePlayer.identity || "").toLowerCase() : ""
                    const name = (id.indexOf("ytm") >= 0 || id.indexOf("youtube") >= 0)
                        ? "YouTube Music"
                        : (root.activePlayer ? (root.activePlayer.identity || "Music") : "Music")
                    return "Playing in " + name + " (Workspace " + root.mediaWorkspaceId + ")"
                }
                color: "#FFFFFF"
                font.pixelSize: 12
                font.weight: Font.Bold
                font.family: textFontFamily
                font.letterSpacing: 0.2
            }
        }

        // ── Row 1: Album art + track info + cava ──
        Item {
            width: parent.width
            height: 60

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Item {
                    width: 75
                    height: 75

                    Image {
    id: expandedArtImage
    anchors.fill: parent
    source: currentArtUrl
    fillMode: Image.PreserveAspectCrop
    sourceSize: Qt.size(200, 200)
    smooth: true
    mipmap: true
    visible: false
}

                    Rectangle {
                        id: expandedArtMask
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                    }

                    OpacityMask {
                        anchors.fill: parent
                        source: expandedArtImage
                        maskSource: expandedArtMask
                    }

                    // Circular hairline outline, shares the shell's border tokens
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: IslandMotion.surfaceBorderWidth
                        border.color: IslandMotion.surfaceBorderColor
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        renderType: Text.NativeRendering
                        text: currentTrack
                        color: "white"
                        font.pixelSize: 16
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.15
                        width: 180
                        elide: Text.ElideRight
                    }

                    Text {
                        renderType: Text.NativeRendering
                        text: currentArtist
                        color: IslandMotion.textSecondary
                        font.pixelSize: 14
                        font.family: textFontFamily
                        font.weight: Font.Medium
                        width: 200
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    width: 200
                    height: 60
                    anchors.verticalCenter: parent.verticalCenter
                    preventStealing: true
                    onPressed: (mouse) => { mouse.accepted = true }
                    onClicked: (mouse) => {
                        mouse.accepted = true
                        if (activePlayer && activePlayer.canRaise) activePlayer.raise()
                    }
                }
            }

            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 36

                Row {
                    anchors.centerIn: parent
                    height: parent.height
                    spacing: 4

                    Repeater {
                        model: 6
                        delegate: Rectangle {
                            width: 4
                            smooth: true
                            antialiasing: true
                            readonly property real level: root.visualizerLevel(index)
                            height: isPlaying
                                ? 2 + (parent.height - 2) * level
                                : 2 + (parent.height - 2) * pausedVisualizerLevel(index)
                            radius: 2
                            color: isPlaying ? cavaActiveColor : cavaPausedColor
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on height { NumberAnimation { duration: isPlaying ? 50 : 260; easing.type: Easing.InOutQuad } }
                            Behavior on color { ColorAnimation { duration: isPlaying ? 140 : 280; easing.type: Easing.InOutQuad } }
                        }
                    }
                }
            }
        }

        // ── Row 2: Progress bar ──
        Item {
            width: parent.width
            height: 16

            Text {
                renderType: Text.NativeRendering
                id: timeL
                anchors.left: parent.left
                text: timePlayed
                color: IslandMotion.textSecondary
                font.pixelSize: 12
                font.family: textFontFamily
                font.weight: Font.Medium
            }

            Rectangle {
                id: progressBar
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: timeL.right
                anchors.right: timeR.left
                anchors.margins: 12
                height: 6
                radius: 3
                color: "#333333"

Rectangle {
                    height: parent.height
                    radius: 3
                    color: "white"
                    width: parent.width * Math.max(0, Math.min(1, trackProgress))
                    Behavior on width {
                        enabled: !scrubArea.pressed && !root._justShown
                        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    id: scrubArea
                    anchors.fill: parent
                    anchors.margins: -10
                    preventStealing: true
                    onPressed: (mouse) => { mouse.accepted = true; controlPressed() }
                    onClicked: (mouse) => { mouse.accepted = true }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        if (!activePlayer || !activePlayer.canSeek) return
                        const fraction = Math.max(0, Math.min(1, mouse.x / width))
                        const length = Number(activePlayer.length) || 0
                        if (length > 0) activePlayer.position = fraction * length
                    }
                    onReleased: (mouse) => {
                        if (!activePlayer || !activePlayer.canSeek) return
                        const fraction = Math.max(0, Math.min(1, mouse.x / width))
                        const length = Number(activePlayer.length) || 0
                        if (length > 0) activePlayer.position = fraction * length
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                id: timeR
                anchors.right: parent.right
                text: timeTotal
                color: IslandMotion.textSecondary
                font.pixelSize: 12
                font.family: textFontFamily
                font.weight: Font.Medium
            }
        }

        // ── Row 3: Controls ──
        Item {
            width: parent.width
            height: 36

            Row {
                anchors.centerIn: parent
                spacing: 28

                // Shuffle
                Item {
                    width: 24
                    height: 24
                    opacity: activePlayer && activePlayer.shuffle ? 1.0 : 0.35
                    scale: shuffleArea.pressed ? 0.8 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Canvas {
                        anchors.fill: parent
                        property color fillColor: "white"
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = fillColor
                            ctx.lineWidth = 2
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            ctx.moveTo(3, 7); ctx.lineTo(14, 7); ctx.lineTo(21, 17)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(17, 15); ctx.lineTo(21, 17); ctx.lineTo(17, 19)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(3, 17); ctx.lineTo(14, 17); ctx.lineTo(21, 7)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(17, 5); ctx.lineTo(21, 7); ctx.lineTo(17, 9)
                            ctx.stroke()
                        }
                    }
                    MouseArea {
                        id: shuffleArea
                        anchors.fill: parent
                        anchors.margins: -12
                        preventStealing: true
                        onPressed: (mouse) => { controlPressed(); mouse.accepted = true }
                        onClicked: {
                            if (!activePlayer) return
                            const next = activePlayer.shuffle ? "false" : "true"
                            shuffleProc.command = [
                                "dbus-send", "--print-reply",
                                "--dest=" + activePlayer.dbusName,
                                "/org/mpris/MediaPlayer2",
                                "org.freedesktop.DBus.Properties.Set",
                                "string:org.mpris.MediaPlayer2.Player",
                                "string:Shuffle",
                                "variant:boolean:" + next
                            ]
                            shuffleProc.running = true
                        }
                    }
                }

                // Previous
                Item {
                    width: 28
                    height: 28
                    scale: prevArea.pressed ? 0.8 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Canvas {
                        anchors.fill: parent
                        property color fillColor: prevArea.pressed ? "#888" : "white"
                        onFillColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = fillColor
                            ctx.strokeStyle = fillColor
                            ctx.lineJoin = "round"
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.rect(3, 5, 3, 18)
                            ctx.moveTo(14, 5); ctx.lineTo(6, 14); ctx.lineTo(14, 23)
                            ctx.closePath()
                            ctx.moveTo(23, 5); ctx.lineTo(15, 14); ctx.lineTo(23, 23)
                            ctx.closePath()
                            ctx.fill()
                            ctx.stroke()
                        }
                    }
                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        anchors.margins: -15
                        preventStealing: true
                        onPressed: (mouse) => { controlPressed(); mouse.accepted = true }
                        onClicked: if (activePlayer) activePlayer.previous()
                    }
                }

                // Play/Pause
                Item {
                    width: 28
                    height: 28
                    scale: playArea.pressed ? 0.8 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        visible: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing
                        Rectangle { width: 6; height: 20; radius: 2; color: playArea.pressed ? "#888" : "white" }
                        Rectangle { width: 6; height: 20; radius: 2; color: playArea.pressed ? "#888" : "white" }
                    }
                    Canvas {
                        anchors.fill: parent
                        visible: !activePlayer || activePlayer.playbackState !== MprisPlaybackState.Playing
                        property color fillColor: playArea.pressed ? "#888" : "white"
                        onFillColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = fillColor
                            ctx.strokeStyle = fillColor
                            ctx.lineJoin = "round"
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.moveTo(8, 4); ctx.lineTo(24, 14); ctx.lineTo(8, 24)
                            ctx.closePath()
                            ctx.fill()
                            ctx.stroke()
                        }
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        anchors.margins: -15
                        preventStealing: true
                        onPressed: (mouse) => { controlPressed(); mouse.accepted = true }
                        onClicked: togglePlayback()
                    }
                }

                // Next
                Item {
                    width: 28
                    height: 28
                    scale: nextArea.pressed ? 0.8 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Canvas {
                        anchors.fill: parent
                        property color fillColor: nextArea.pressed ? "#888" : "white"
                        onFillColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = fillColor
                            ctx.strokeStyle = fillColor
                            ctx.lineJoin = "round"
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.moveTo(5, 5); ctx.lineTo(13, 14); ctx.lineTo(5, 23)
                            ctx.closePath()
                            ctx.moveTo(14, 5); ctx.lineTo(22, 14); ctx.lineTo(14, 23)
                            ctx.closePath()
                            ctx.rect(22, 5, 3, 18)
                            ctx.fill()
                            ctx.stroke()
                        }
                    }
                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        anchors.margins: -15
                        preventStealing: true
                        onPressed: (mouse) => { controlPressed(); mouse.accepted = true }
                        onClicked: if (activePlayer) activePlayer.next()
                    }
                }

// ── Loop ──
    Item {
        width: 24
        height: 24
        opacity: activePlayer && activePlayer.loopState !== MprisLoopState.None ? 1.0 : 0.35
        scale: loopArea.pressed ? 0.8 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Canvas {
            anchors.fill: parent
            property color fillColor: "white"
            property bool loopOne: activePlayer && activePlayer.loopState === MprisLoopState.Track
            onLoopOneChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = fillColor
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(4, 10); ctx.lineTo(4, 17); ctx.lineTo(18, 17)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(20, 14); ctx.lineTo(18, 17); ctx.lineTo(20, 20)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(20, 14); ctx.lineTo(20, 7); ctx.lineTo(6, 7)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(4, 10); ctx.lineTo(6, 7); ctx.lineTo(4, 4)
                ctx.stroke()
                if (loopOne) {
                    ctx.font = "bold 8px sans-serif"
                    ctx.fillStyle = fillColor
                    ctx.textAlign = "center"
                    ctx.fillText("1", 12, 15)
                }
            }
        }
        MouseArea {
            id: loopArea
            anchors.fill: parent
            anchors.margins: -12
            preventStealing: true
            onPressed: (mouse) => { controlPressed(); mouse.accepted = true }
            onClicked: {
                if (!activePlayer) return
                const s = activePlayer.loopState
                let next
                if (s === MprisLoopState.None) next = MprisLoopState.Playlist
                else if (s === MprisLoopState.Playlist) next = MprisLoopState.Track
                else next = MprisLoopState.None

                console.log("Loop cycle —", activePlayer.dbusName,
                    "current:", s, "requesting:", next)

                activePlayer.loopState = next
            }
        }
    } // Closes Loop Item

        } // Closes Row (FIXED)
    } // Closes Row 3 Item (FIXED)
} // Closes parent Column (FIXED)

    Process { id: loopProc }
    Process { id: shuffleProc }
} // Closes root Item
