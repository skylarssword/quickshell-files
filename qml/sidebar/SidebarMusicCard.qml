import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell.Services.Mpris
import "../shared"
import "../island"

// Visual card for the sidebar music popout: a left rail with two tabs
// (0 = Playing, 1 = Equalizer) and the content for the selected tab.
Item {
    id: card

    property color  bgColor:        Qt.rgba(0, 0, 0, 0.2)
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property bool   open:           true

    property var    activePlayer:   null
    property bool   isPlaying:      false
    property string currentTrack:   ""
    property string currentArtist:  ""
    property string currentArtUrl:  ""
    property real   trackProgress:  0
    property string timePlayed:     "0:00"
    property string timeTotal:      "0:00"
    property string mediaWindowLabel: ""

    property int tab: 0                       // 0 = Playing, 1 = Equalizer

    readonly property real cornerRadius: 28
    readonly property real railWidth:    64

    Process { id: shuffleProc }

    // single-line text that, when too long, waits, scrolls to reveal the end, pauses and slides back
    component Marquee: Item {
        id: mq
        property string text: ""
        property color  color: "white"
        property real   pixelSize: 14
        property int    weight: Font.Normal
        property real   letterSpacing: 0
        property bool   active: true
        readonly property real overflow: Math.max(0, label.implicitWidth - width)
        height: label.height
        clip: true

        Text {
            id: label
            renderType: Text.NativeRendering
            x: 0
            text: mq.text
            color: mq.color
            font.family: card.textFontFamily
            font.pixelSize: mq.pixelSize
            font.weight: mq.weight
            font.letterSpacing: mq.letterSpacing
            onTextChanged: { x = 0; if (anim.running) anim.restart() }
        }
        SequentialAnimation {
            id: anim
            running: mq.overflow > 0 && mq.active
            loops: Animation.Infinite
            onRunningChanged: if (!running) label.x = 0
            PauseAnimation { duration: 2500 }
            NumberAnimation { target: label; property: "x"; to: -mq.overflow
                duration: Math.min(7000, Math.max(900, mq.overflow * 16)); easing.type: Easing.InOutSine }
            PauseAnimation { duration: 1500 }
            NumberAnimation { target: label; property: "x"; to: 0; duration: 500; easing.type: Easing.InOutSine }
        }
    }

    // ── body ────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: card.cornerRadius
        color: card.bgColor
        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor
    }
    GlassSheen { cornerRadius: card.cornerRadius }

    // ── left rail ───────────────────────────────────────────────────────────
    Item {
        id: rail
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: card.railWidth

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -0.5
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Repeater {
                model: 2
                delegate: Item {
                    id: tabBtn
                    required property int index
                    readonly property bool active: card.tab === index
                    width: 46; height: 46

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: tabBtn.active ? Qt.rgba(1, 1, 1, 0.16)
                             : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        border.width: tabBtn.active ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.28)
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    // icons are drawn, so they don't depend on the icon font
                    Canvas {
                        anchors.centerIn: parent
                        width: 56; height: 56
                        scale: 0.5; smooth: true
                        opacity: tabBtn.active ? 1.0 : 0.55
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.setTransform(1, 0, 0, 1, 0, 0)
                            ctx.clearRect(0, 0, width, height)
                            ctx.setTransform(width / 24, 0, 0, height / 24, 0, 0)
                            ctx.strokeStyle = "white"; ctx.fillStyle = "white"
                            ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                            if (tabBtn.index === 0) {
                                // music note
                                ctx.beginPath(); ctx.moveTo(9, 18); ctx.lineTo(9, 5); ctx.lineTo(19, 3); ctx.lineTo(19, 16); ctx.stroke()
                                ctx.beginPath(); ctx.arc(6.5, 18, 3, 0, Math.PI * 2); ctx.fill()
                                ctx.beginPath(); ctx.arc(16.5, 16, 3, 0, Math.PI * 2); ctx.fill()
                            } else {
                                // equalizer: three sliders
                                const xs = [5, 12, 19], ky = [15, 8, 13]
                                for (let i = 0; i < 3; i++) {
                                    ctx.beginPath(); ctx.moveTo(xs[i], 3); ctx.lineTo(xs[i], 21); ctx.stroke()
                                    ctx.beginPath(); ctx.arc(xs[i], ky[i], 2.6, 0, Math.PI * 2)
                                    ctx.fillStyle = "white"; ctx.fill()
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.tab = tabBtn.index
                    }
                }
            }
        }
    }

    // ── content ─────────────────────────────────────────────────────────────
    Item {
        id: content
        anchors { left: rail.right; right: parent.right; top: parent.top; bottom: parent.bottom }

        // ---------- tab 0: playing ----------
        Item {
            id: playingTab
            anchors.fill: parent
            anchors.margins: 16
            opacity: card.tab === 0 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

            // art + title/artist
            Item {
                id: artSection
                width: 190
                height: parent.height

                Item {
                    id: artBox
                    anchors.centerIn: parent
                    width: 164; height: 164

                    Item {
                        id: artRot
                        anchors.fill: parent
                        visible: false
                        Image {
                            id: artImg
                            anchors.fill: parent
                            source: card.currentArtUrl
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(512, 512)
                            smooth: true; mipmap: true
                            rotation: artSpinner.angle
                        }
                    }
                    Rectangle { id: artMask; anchors.fill: parent; radius: width / 2; visible: false }
                    Item {
                        id: artSpinner
                        anchors.fill: parent
                        property real angle: 0
                        visible: card.currentArtUrl !== "" && artImg.status === Image.Ready
                        RotationAnimation on angle {
                            from: 0; to: 360; duration: 8000
                            direction: RotationAnimation.Clockwise
                            loops: Animation.Infinite
                            running: card.isPlaying && card.open
                            paused: !card.isPlaying
                        }
                        OpacityMask {
                            anchors.fill: parent
                            source: artRot
                            maskSource: artMask
                        }
                    }
                    // dim when paused
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                        opacity: card.isPlaying ? 0 : 0.45
                        visible: card.currentArtUrl !== "" && artImg.status === Image.Ready
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                    // placeholder
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.07)
                        visible: card.currentArtUrl === "" || artImg.status !== Image.Ready
                        Canvas {
                            anchors.centerIn: parent
                            width: 104; height: 104
                            scale: 0.5; smooth: true
                            opacity: 0.5
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.setTransform(1, 0, 0, 1, 0, 0)
                                ctx.clearRect(0, 0, width, height)
                                ctx.setTransform(width / 24, 0, 0, height / 24, 0, 0)
                                ctx.strokeStyle = "white"; ctx.fillStyle = "white"
                                ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                                ctx.beginPath(); ctx.moveTo(9, 18); ctx.lineTo(9, 5); ctx.lineTo(19, 3); ctx.lineTo(19, 16); ctx.stroke()
                                ctx.beginPath(); ctx.arc(6.5, 18, 3, 0, Math.PI * 2); ctx.fill()
                                ctx.beginPath(); ctx.arc(16.5, 16, 3, 0, Math.PI * 2); ctx.fill()
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
                }

            }

            // divider between the art section and the controls section
            Rectangle {
                anchors.left: artSection.right
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: parent.height - 24
                color: IslandMotion.surfaceBorderColor
            }

            // everything else lives on the other side
            Item {
                id: infoSection
                anchors.left: artSection.right
                anchors.leftMargin: 20
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: infoCol.height

                Column {
                    id: infoCol
                    width: parent.width
                    spacing: 16
                Column {
                    width: parent.width
                    spacing: 4

                    Marquee {
                        width: parent.width
                        active: card.tab === 0 && card.open
                        text: card.currentTrack !== "" ? card.currentTrack : "Nothing playing"
                        color: "white"
                        pixelSize: 21
                        weight: Font.DemiBold
                        letterSpacing: -0.2
                    }
                    Marquee {
                        width: parent.width
                        active: card.tab === 0 && card.open
                        text: card.currentArtist
                        color: IslandMotion.textSecondary
                        pixelSize: 15
                        weight: Font.Medium
                    }
                }

            // progress
            Item {
                id: progressRow
                width: parent.width
                height: 20

                Text {
                    id: timeL
                    renderType: Text.NativeRendering
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.timePlayed
                    color: IslandMotion.textSecondary
                    font.family: card.textFontFamily
                    font.pixelSize: 12
                }
                Text {
                    id: timeR
                    renderType: Text.NativeRendering
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.timeTotal
                    color: IslandMotion.textSecondary
                    font.family: card.textFontFamily
                    font.pixelSize: 12
                }
                Rectangle {
                    id: progressTrack
                    anchors.left: timeL.right
                    anchors.right: timeR.left
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 5; radius: 3
                    color: Qt.rgba(1, 1, 1, 0.18)

                    Rectangle {
                        id: progressFill
                        height: parent.height; radius: 3
                        color: "white"
                        width: progressTrack.width * Math.max(0, Math.min(1, card.trackProgress))
                        Behavior on width { enabled: !scrubArea.pressed; NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: scrubArea
                        anchors.fill: parent
                        anchors.margins: -9
                        preventStealing: true
                        function seekTo(mx) {
                            if (!card.activePlayer || !card.activePlayer.canSeek) return
                            const frac = Math.max(0, Math.min(1, mx / progressTrack.width))
                            const len = Number(card.activePlayer.length) || 0
                            if (len > 0) card.activePlayer.position = frac * len
                        }
                        onClicked: (mouse) => seekTo(mouse.x - 9)
                    }
                }
            }

            // transport
            Item {
                width: parent.width
                height: 34
            Row {
                id: transport
                anchors.centerIn: parent
                spacing: 28

                component TBtn: Item {
                    id: rb
                    property bool pressed: ma.pressed
                    property real iconOpacity: 1.0
                    default property alias iconSlot: slot.data
                    signal activated()
                    width: 30; height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    Item {
                        id: slot
                        anchors.fill: parent
                        opacity: rb.pressed ? rb.iconOpacity * 0.55 : rb.iconOpacity
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    MouseArea { id: ma; anchors.fill: parent; anchors.margins: -8; preventStealing: true; onClicked: rb.activated() }
                }

                // shuffle
                TBtn {
                    iconOpacity: card.activePlayer && card.activePlayer.shuffle ? 1.0 : 0.4
                    onActivated: {
                        if (!card.activePlayer) return
                        const next = card.activePlayer.shuffle ? "false" : "true"
                        shuffleProc.command = ["dbus-send", "--print-reply",
                            "--dest=" + card.activePlayer.dbusName, "/org/mpris/MediaPlayer2",
                            "org.freedesktop.DBus.Properties.Set", "string:org.mpris.MediaPlayer2.Player",
                            "string:Shuffle", "variant:boolean:" + next]
                        shuffleProc.running = true
                    }
                    Canvas {
                        anchors.centerIn: parent
                        width: 60; height: 60; scale: 0.5; smooth: true
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height)
                            ctx.setTransform(width / 24, 0, 0, height / 24, 0, 0)
                            ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                            ctx.beginPath(); ctx.moveTo(3, 7); ctx.lineTo(14, 7); ctx.lineTo(21, 17); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(17, 15); ctx.lineTo(21, 17); ctx.lineTo(17, 19); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(3, 17); ctx.lineTo(14, 17); ctx.lineTo(21, 7); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(17, 5); ctx.lineTo(21, 7); ctx.lineTo(17, 9); ctx.stroke()
                        }
                    }
                }

                // previous
                TBtn {
                    onActivated: if (card.activePlayer) card.activePlayer.previous()
                    Canvas {
                        anchors.centerIn: parent
                        width: 60; height: 60; scale: 0.5; smooth: true
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height)
                            ctx.setTransform(width / 28, 0, 0, height / 28, 0, 0)
                            ctx.fillStyle = "white"; ctx.strokeStyle = "white"; ctx.lineJoin = "round"; ctx.lineWidth = 2
                            ctx.beginPath(); ctx.rect(3, 5, 3, 18); ctx.fill()
                            ctx.beginPath(); ctx.moveTo(14, 5); ctx.lineTo(6, 14); ctx.lineTo(14, 23); ctx.closePath(); ctx.fill()
                            ctx.beginPath(); ctx.moveTo(23, 5); ctx.lineTo(15, 14); ctx.lineTo(23, 23); ctx.closePath(); ctx.fill()
                        }
                    }
                }

                // play / pause
                TBtn {
                    onActivated: {
                        const p = card.activePlayer
                        if (!p || !p.canControl) return
                        if (p.canTogglePlaying) p.togglePlaying()
                        else if (card.isPlaying) { if (p.canPause) p.pause() }
                        else { if (p.canPlay) p.play() }
                    }
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        visible: card.isPlaying
                        Rectangle { width: 7; height: 22; radius: 2; color: "white" }
                        Rectangle { width: 7; height: 22; radius: 2; color: "white" }
                    }
                    Canvas {
                        anchors.centerIn: parent
                        width: 60; height: 60; scale: 0.5; smooth: true
                        visible: !card.isPlaying
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height)
                            ctx.setTransform(width / 28, 0, 0, height / 28, 0, 0)
                            ctx.fillStyle = "white"; ctx.strokeStyle = "white"; ctx.lineJoin = "round"; ctx.lineWidth = 2
                            ctx.beginPath(); ctx.moveTo(8, 4); ctx.lineTo(24, 14); ctx.lineTo(8, 24); ctx.closePath()
                            ctx.fill(); ctx.stroke()
                        }
                    }
                }

                // next
                TBtn {
                    onActivated: if (card.activePlayer) card.activePlayer.next()
                    Canvas {
                        anchors.centerIn: parent
                        width: 60; height: 60; scale: 0.5; smooth: true
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height)
                            ctx.setTransform(width / 28, 0, 0, height / 28, 0, 0)
                            ctx.fillStyle = "white"; ctx.strokeStyle = "white"; ctx.lineJoin = "round"; ctx.lineWidth = 2
                            ctx.beginPath(); ctx.rect(22, 5, 3, 18); ctx.fill()
                            ctx.beginPath(); ctx.moveTo(5, 5); ctx.lineTo(13, 14); ctx.lineTo(5, 23); ctx.closePath(); ctx.fill()
                            ctx.beginPath(); ctx.moveTo(14, 5); ctx.lineTo(22, 14); ctx.lineTo(14, 23); ctx.closePath(); ctx.fill()
                        }
                    }
                }

                // loop
                TBtn {
                    iconOpacity: card.activePlayer && card.activePlayer.loopState !== MprisLoopState.None ? 1.0 : 0.4
                    onActivated: {
                        if (!card.activePlayer) return
                        const s = card.activePlayer.loopState
                        card.activePlayer.loopState = s === MprisLoopState.None ? MprisLoopState.Playlist
                            : (s === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None)
                    }
                    Canvas {
                        anchors.centerIn: parent
                        width: 60; height: 60; scale: 0.5; smooth: true
                        property bool loopOne: card.activePlayer && card.activePlayer.loopState === MprisLoopState.Track
                        onLoopOneChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, width, height)
                            ctx.setTransform(width / 24, 0, 0, height / 24, 0, 0)
                            ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                            ctx.beginPath(); ctx.moveTo(4, 10); ctx.lineTo(4, 17); ctx.lineTo(18, 17); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(20, 14); ctx.lineTo(18, 17); ctx.lineTo(20, 20); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(20, 14); ctx.lineTo(20, 7); ctx.lineTo(6, 7); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(4, 10); ctx.lineTo(6, 7); ctx.lineTo(4, 4); ctx.stroke()
                            if (loopOne) {
                                ctx.font = "bold 8px sans-serif"; ctx.fillStyle = "white"; ctx.textAlign = "center"
                                ctx.fillText("1", 12, 15)
                            }
                        }
                    }
                }
            }

            }

            // "Playing in <player> (Workspace N)"
            Text {
                renderType: Text.NativeRendering
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: card.mediaWindowLabel !== ""
                text: card.mediaWindowLabel
                color: "#FFFFFF"
                font.family: card.textFontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
            }
                }
            }
        }

        // ---------- tab 1: equalizer ----------
        Item {
            id: eqTab
            anchors.fill: parent
            anchors.margins: 14
            opacity: card.tab === 1 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

            EqualizerPanel {
                anchors.fill: parent
                showCondition: card.tab === 1 && card.open
                sidebarMode: true
                iconFontFamily: card.iconFontFamily
                textFontFamily: card.textFontFamily
            }
        }
    }
}
