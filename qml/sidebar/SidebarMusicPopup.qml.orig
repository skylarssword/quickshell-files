import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import IslandBackend
import "../shared"
import "../island"

PanelWindow {
    id: root

    property bool   gamemodeActive:      false
    property bool   useWalColor:         false
    property color  walColor:            "#000000"
    property real   capsuleOpacityValue: 0.20
    property string iconFontFamily:      ""
    property string textFontFamily:      ""

    property var    activePlayer:  null
    property string currentTrack:  ""
    property string currentArtist: ""
    property string currentArtUrl: ""
    property real   trackProgress: 0
    property string timePlayed:    "0:00"
    property string timeTotal:     "0:00"

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    readonly property bool isPlaying: activePlayer !== null
        && activePlayer.playbackState === MprisPlaybackState.Playing

    property bool popupOpen: false
    function open()  { popupOpen = true  }
    function close() { popupOpen = false }
    function toggle(){ popupOpen = !popupOpen }

    property bool showEqualizer: false

    readonly property real cardW: 400
    readonly property real cardH: 260

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: popupOpen

    mask: Region {
        Region {
            x: Math.floor(card.x)
            y: Math.floor(card.y)
            width:  root.popupOpen ? Math.ceil(card.width)  : 0
            height: root.popupOpen ? Math.ceil(card.height) : 0
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.popupOpen
        onClicked: root.close()
        z: -1
    }
    Keys.onEscapePressed: root.close()

    Process { id: shuffleProc }

    property string mediaWindowLabel: ""

    Process {
        id: mediaWindowQuery
        property string _buf: ""
        command: ["bash", "-c", "hyprctl clients -j 2>/dev/null"]
        stdout: SplitParser { onRead: mediaWindowQuery._buf += data + "\n" }
        onRunningChanged: {
            if (!running) {
                const raw = mediaWindowQuery._buf
                mediaWindowQuery._buf = ""
                root.resolveMediaWindow(raw)
            }
        }
    }

    Timer {
        interval: 2000
        running: root.popupOpen && root.activePlayer !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!mediaWindowQuery.running) mediaWindowQuery.running = true
    }

    function resolveMediaWindow(rawJson) {
        if (!root.activePlayer) { root.mediaWindowLabel = ""; return }
        const identity = String(root.activePlayer.identity || "").toLowerCase().trim()
        if (identity === "") { root.mediaWindowLabel = ""; return }
        try {
            const clients = JSON.parse(rawJson)
            for (let i = 0; i < clients.length; i++) {
                const c = clients[i]
                const cls   = String(c.class  || "").toLowerCase()
                const title = String(c.title  || "").toLowerCase()

                const isSpotify = cls.indexOf("spotify") >= 0
                
                const isYtm = !isSpotify
                    && (identity.indexOf("youtube") >= 0 || identity.indexOf("ytm") >= 0)
                    && title.indexOf("ytm") >= 0
                
                const isGeneric = !isSpotify && !isYtm
                    && cls.length > 3
                    && (cls.indexOf(identity) >= 0 || title.indexOf(identity) >= 0)

                if (isSpotify || isYtm || isGeneric) {
                    const wsId = (c.workspace && c.workspace.id !== undefined) ? c.workspace.id : -1
                    const wsSuffix = wsId >= 1 ? " (Workspace " + wsId + ")" : ""
                    if (isSpotify)
                        root.mediaWindowLabel = "Playing in Spotify" + wsSuffix
                    else if (isYtm)
                        root.mediaWindowLabel = "Playing in YouTube Music" + wsSuffix
                    else
                        root.mediaWindowLabel = "Playing in " + (root.activePlayer.identity || "") + wsSuffix
                    return
                }
            }
        } catch (e) {}
        root.mediaWindowLabel = ""
    }

    Item {
        id: card
        width:  root.cardW
        height: root.cardH
        anchors.centerIn: parent

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        transform: Rotation {
            id: flipRotation
            origin.x: card.width / 2
            origin.y: card.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: 0
        }

        states: [
            State { name: "player";    PropertyChanges { target: flipRotation; angle: 0   } },
            State { name: "equalizer"; PropertyChanges { target: flipRotation; angle: 180 } }
        ]
        state: root.showEqualizer ? "equalizer" : "player"

        property bool showEqFace: false
        transitions: Transition {
            SequentialAnimation {
                NumberAnimation {
                    target: flipRotation; property: "angle"
                    to: 90; duration: 160; easing.type: Easing.InQuad
                }
                ScriptAction { script: card.showEqFace = root.showEqualizer }
                NumberAnimation {
                    target: flipRotation; property: "angle"
                    duration: 160; easing.type: Easing.OutQuad
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: !card.showEqFace

            Rectangle {
                anchors.fill: parent
                radius: 28
                color:  root.bgColor
                border.width: IslandMotion.surfaceBorderWidth
                border.color: IslandMotion.surfaceBorderColor
                clip: true
            }

            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 16

                    Item {
                        width: 100; height: 100

                        Item {
                            id: popupArtContainer
                            anchors.fill: parent

                            RotationAnimation on rotation {
                                running:   root.isPlaying
                                from:      popupArtContainer.rotation
                                to:        popupArtContainer.rotation + 360
                                duration:  12000
                                direction: RotationAnimation.Clockwise
                                loops:     Animation.Infinite
                            }

                            Image {
                                id: artImg
                                anchors.fill: parent
                                source: root.currentArtUrl
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(200, 200)
                                smooth: true; mipmap: true
                                visible: false
                            }
                            Rectangle {
                                id: artMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }
                            OpacityMask {
                                anchors.fill: parent
                                source: artImg
                                maskSource: artMask
                                visible: root.currentArtUrl !== "" && artImg.status === Image.Ready
                            }
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "black"
                                opacity: root.isPlaying ? 0 : 0.45
                                visible: root.currentArtUrl !== "" && artImg.status === Image.Ready
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.rgba(1,1,1,0.07)
                            border.width: IslandMotion.surfaceBorderWidth
                            border.color: IslandMotion.surfaceBorderColor
                            visible: root.currentArtUrl === "" || artImg.status !== Image.Ready

                            Text {
                                anchors.centerIn: parent
                                text: "\uf001"
                                font.family:    root.iconFontFamily
                                font.pixelSize: 26
                                color: Qt.rgba(1,1,1,0.55)
                                renderType: Text.NativeRendering
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 2
                                border.color: Qt.rgba(1,1,1,0.55)
                                visible: root.isPlaying
                                SequentialAnimation on border.color {
                                    running: root.isPlaying
                                    loops: Animation.Infinite
                                    ColorAnimation { to: Qt.rgba(1,1,1,0.85); duration: 700; easing.type: Easing.InOutSine }
                                    ColorAnimation { to: Qt.rgba(1,1,1,0.25); duration: 700; easing.type: Easing.InOutSine }
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: IslandMotion.surfaceBorderWidth
                            border.color: IslandMotion.surfaceBorderColor
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.rgba(1,1,1,0.55)
                            visible: root.isPlaying && root.currentArtUrl !== "" && artImg.status === Image.Ready
                            SequentialAnimation on border.color {
                                running: root.isPlaying && root.currentArtUrl !== "" && artImg.status === Image.Ready
                                loops: Animation.Infinite
                                ColorAnimation { to: Qt.rgba(1,1,1,0.85); duration: 700; easing.type: Easing.InOutSine }
                                ColorAnimation { to: Qt.rgba(1,1,1,0.20); duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    Item {
                        width: parent.width - 100 - 16
                        height: 100

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:  parent.left
                            anchors.right: eqFlipBtn.left
                            anchors.rightMargin: 8
                            spacing: 5

                            Text {
                                renderType: Text.NativeRendering
                                width: parent.width
                                text: root.currentTrack !== "" ? root.currentTrack : "Nothing playing"
                                color: "white"
                                font.family:    root.textFontFamily
                                font.pixelSize: 15
                                font.weight:    Font.DemiBold
                                font.letterSpacing: -0.1
                                elide: Text.ElideRight
                            }
                            Text {
                                renderType: Text.NativeRendering
                                width: parent.width
                                text: root.currentArtist
                                color: IslandMotion.textSecondary
                                font.family:    root.textFontFamily
                                font.pixelSize: 12
                                font.weight:    Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: eqFlipBtn
                            anchors.right:          parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26; radius: 13
                            color: eqFlipMouse.containsMouse
                                ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                            border.width: IslandMotion.surfaceBorderWidth
                            border.color: IslandMotion.surfaceBorderColor
                            Behavior on color { ColorAnimation { duration: IslandMotion.micro } }

                            Text {
                                anchors.centerIn: parent
                                text: "›"
                                color: "white"
                                font.pixelSize: 16
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: eqFlipMouse
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showEqualizer = true
                            }
                        }
                    }
                }

                Item {
                    width: parent.width; height: 20

                    Text {
                        id: timeL
                        renderType: Text.NativeRendering
                        anchors.left:           parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text:  root.timePlayed
                        color: IslandMotion.textSecondary
                        font.family:    root.textFontFamily
                        font.pixelSize: 11
                    }

                    Rectangle {
                        id: progressTrack
                        anchors.left:           timeL.right
                        anchors.right:          timeR.left
                        anchors.leftMargin:     10
                        anchors.rightMargin:    10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5; radius: 3
                        color: Qt.rgba(1,1,1,0.18)

                        Rectangle {
                            id: progressFill
                            height: parent.height; radius: 3
                            color: "white"
                            width: progressTrack.width * Math.max(0, Math.min(1, root.trackProgress))
                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: progressFill.width - width / 2
                            width: 12; height: 12; radius: 6
                            color: "white"
                            visible: scrubArea.containsMouse || scrubArea.pressed
                        }

                        MouseArea {
                            id: scrubArea
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            preventStealing: true
                            onClicked: (mouse) => {
                                if (!root.activePlayer || !root.activePlayer.canSeek) return
                                const frac = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
                                const len  = Number(root.activePlayer.length) || 0
                                if (len > 0) root.activePlayer.position = frac * len
                            }
                        }
                    }

                    Text {
                        id: timeR
                        renderType: Text.NativeRendering
                        anchors.right:          parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text:  root.timeTotal
                        color: IslandMotion.textSecondary
                        font.family:    root.textFontFamily
                        font.pixelSize: 11
                    }
                }

                Item {
                    width: parent.width
                    height: root.mediaWindowLabel !== "" ? 20 : 0
                    clip: true
                    Behavior on height { NumberAnimation { duration: IslandMotion.fast; easing.type: Easing.OutCubic } }

                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: root.mediaWindowLabel
                        color: "#FFFFFF"
                        font.family:    root.textFontFamily
                        font.pixelSize: 13
                        font.weight:    Font.Bold
                        opacity: root.mediaWindowLabel !== "" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: IslandMotion.fast } }
                    }
                }

                Item {
                    width: parent.width; height: 36

                    Row {
                        anchors.centerIn: parent
                        spacing: 26

                        Item {
                            width: 24; height: 24
                            opacity: root.activePlayer && root.activePlayer.shuffle ? 1.0 : 0.35
                            scale: shuffleMouse.pressed ? 0.8 : 1.0
                            Behavior on scale   { NumberAnimation { duration: 100 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Canvas {
                                anchors.fill: parent
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.strokeStyle = "white"; ctx.lineWidth = 2
                                    ctx.lineCap = "round"; ctx.lineJoin = "round"
                                    ctx.beginPath()
                                    ctx.moveTo(3,7); ctx.lineTo(14,7); ctx.lineTo(21,17); ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(17,15); ctx.lineTo(21,17); ctx.lineTo(17,19); ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(3,17); ctx.lineTo(14,17); ctx.lineTo(21,7); ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(17,5); ctx.lineTo(21,7); ctx.lineTo(17,9); ctx.stroke()
                                }
                            }
                            MouseArea {
                                id: shuffleMouse
                                anchors.fill: parent; anchors.margins: -12
                                preventStealing: true
                                onClicked: {
                                    if (!root.activePlayer) return
                                    const next = root.activePlayer.shuffle ? "false" : "true"
                                    shuffleProc.command = [
                                        "dbus-send","--print-reply",
                                        "--dest=" + root.activePlayer.dbusName,
                                        "/org/mpris/MediaPlayer2",
                                        "org.freedesktop.DBus.Properties.Set",
                                        "string:org.mpris.MediaPlayer2.Player",
                                        "string:Shuffle","variant:boolean:" + next
                                    ]
                                    shuffleProc.running = true
                                }
                            }
                        }

                        Item {
                            width: 28; height: 28
                            scale: prevMouse.pressed ? 0.8 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Canvas {
                                anchors.fill: parent
                                property color c: prevMouse.pressed ? "#888" : "white"
                                onCChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = c; ctx.strokeStyle = c
                                    ctx.lineJoin = "round"; ctx.lineWidth = 2
                                    ctx.beginPath(); ctx.rect(3,5,3,18); ctx.fill()
                                    ctx.beginPath(); ctx.moveTo(14,5); ctx.lineTo(6,14); ctx.lineTo(14,23); ctx.closePath(); ctx.fill()
                                    ctx.beginPath(); ctx.moveTo(23,5); ctx.lineTo(15,14); ctx.lineTo(23,23); ctx.closePath(); ctx.fill()
                                }
                            }
                            MouseArea {
                                id: prevMouse; anchors.fill: parent; anchors.margins: -12
                                preventStealing: true
                                onClicked: if (root.activePlayer) root.activePlayer.previous()
                            }
                        }

                        Item {
                            width: 32; height: 32
                            scale: playMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Row {
                                anchors.centerIn: parent; spacing: 5
                                visible: root.isPlaying
                                Rectangle { width: 6; height: 22; radius: 2; color: playMouse.pressed ? "#888" : "white" }
                                Rectangle { width: 6; height: 22; radius: 2; color: playMouse.pressed ? "#888" : "white" }
                            }
                            Canvas {
                                anchors.fill: parent; visible: !root.isPlaying
                                property color c: playMouse.pressed ? "#888" : "white"
                                onCChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = c; ctx.strokeStyle = c
                                    ctx.lineJoin = "round"; ctx.lineWidth = 2
                                    ctx.beginPath(); ctx.moveTo(8,4); ctx.lineTo(26,16); ctx.lineTo(8,28); ctx.closePath()
                                    ctx.fill(); ctx.stroke()
                                }
                            }
                            MouseArea {
                                id: playMouse; anchors.fill: parent; anchors.margins: -10
                                preventStealing: true
                                onClicked: {
                                    if (!root.activePlayer || !root.activePlayer.canControl) return
                                    if (root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying()
                                    else if (root.isPlaying) { if (root.activePlayer.canPause) root.activePlayer.pause() }
                                    else { if (root.activePlayer.canPlay) root.activePlayer.play() }
                                }
                            }
                        }

                        Item {
                            width: 28; height: 28
                            scale: nextMouse.pressed ? 0.8 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Canvas {
                                anchors.fill: parent
                                property color c: nextMouse.pressed ? "#888" : "white"
                                onCChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = c; ctx.strokeStyle = c
                                    ctx.lineJoin = "round"; ctx.lineWidth = 2
                                    ctx.beginPath(); ctx.rect(22,5,3,18); ctx.fill()
                                    ctx.beginPath(); ctx.moveTo(5,5); ctx.lineTo(13,14); ctx.lineTo(5,23); ctx.closePath(); ctx.fill()
                                    ctx.beginPath(); ctx.moveTo(14,5); ctx.lineTo(22,14); ctx.lineTo(14,23); ctx.closePath(); ctx.fill()
                                }
                            }
                            MouseArea {
                                id: nextMouse; anchors.fill: parent; anchors.margins: -12
                                preventStealing: true
                                onClicked: if (root.activePlayer) root.activePlayer.next()
                            }
                        }

                        Item {
                            width: 24; height: 24
                            opacity: root.activePlayer
                                && root.activePlayer.loopState !== MprisLoopState.None ? 1.0 : 0.35
                            scale: loopMouse.pressed ? 0.8 : 1.0
                            Behavior on scale   { NumberAnimation { duration: 100 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Canvas {
                                anchors.fill: parent
                                property bool loopOne: root.activePlayer
                                    && root.activePlayer.loopState === MprisLoopState.Track
                                onLoopOneChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.strokeStyle = "white"; ctx.lineWidth = 2
                                    ctx.lineCap = "round"; ctx.lineJoin = "round"
                                    ctx.beginPath(); ctx.moveTo(4,10); ctx.lineTo(4,17); ctx.lineTo(18,17); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(20,14); ctx.lineTo(18,17); ctx.lineTo(20,20); ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(20,14); ctx.lineTo(20,7);  ctx.lineTo(6,7);  ctx.stroke()
                                    ctx.beginPath(); ctx.moveTo(4,10);  ctx.lineTo(6,7);   ctx.lineTo(4,4);  ctx.stroke()
                                    if (loopOne) {
                                        ctx.font = "bold 8px sans-serif"
                                        ctx.fillStyle = "white"
                                        ctx.textAlign = "center"
                                        ctx.fillText("1", 12, 15)
                                    }
                                }
                            }
                            MouseArea {
                                id: loopMouse; anchors.fill: parent; anchors.margins: -12
                                preventStealing: true
                                onClicked: {
                                    if (!root.activePlayer) return
                                    const s = root.activePlayer.loopState
                                    let next
                                    if (s === MprisLoopState.None) next = MprisLoopState.Playlist
                                    else if (s === MprisLoopState.Playlist) next = MprisLoopState.Track
                                    else next = MprisLoopState.None
                                    root.activePlayer.loopState = next
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: card.showEqFace

            transform: Rotation {
                origin.x: card.width / 2
                origin.y: card.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: 180
            }

            Rectangle {
                anchors.fill: parent
                radius: 28
                color:  root.bgColor
                border.width: IslandMotion.surfaceBorderWidth
                border.color: IslandMotion.surfaceBorderColor
                clip: true
            }

            Rectangle {
                id: backFlipBtn
                anchors.left:    parent.left;    anchors.leftMargin:   14
                anchors.top:     parent.top;     anchors.topMargin:    14
                width: 26; height: 26; radius: 13
                color: backFlipMouse.containsMouse
                    ? Qt.rgba(1,1,1,0.18) : Qt.rgba(1,1,1,0.08)
                border.width: IslandMotion.surfaceBorderWidth
                border.color: IslandMotion.surfaceBorderColor
                Behavior on color { ColorAnimation { duration: IslandMotion.micro } }
                z: 2

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: "white"
                    font.pixelSize: 16
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: backFlipMouse
                    anchors.fill: parent; anchors.margins: -8
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.showEqualizer = false
                }
            }

            EqualizerPanel {
                anchors {
                    top:    parent.top;    topMargin:    14
                    left:   parent.left;   leftMargin:   14
                    right:  parent.right;  rightMargin:  14
                    bottom: parent.bottom; bottomMargin: 14
                }
                showCondition: card.showEqFace
                sidebarMode:   true
                iconFontFamily: root.iconFontFamily
                textFontFamily: root.textFontFamily
            }
        }
    }
}
