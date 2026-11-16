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

    // while Liquid Glass is on the body gets more see-through (same scale as the island)
    readonly property real glassBodyScale: Glass.enabled ? Glass.bodyScale : 1.0

    readonly property color bgColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue * glassBodyScale)
            : Glass.bodyFill(capsuleOpacityValue * glassBodyScale))

    readonly property bool isPlaying: activePlayer !== null
        && activePlayer.playbackState === MprisPlaybackState.Playing

    property bool popupOpen: false
    function open()  { popupOpen = true  }
    function close() { popupOpen = false; tab = 0 }
    function toggle(){ popupOpen = !popupOpen }

    // 0 = Playing tab, 1 = Equalizer tab (rail on the left of the card)
    property alias tab: card.tab

    readonly property real cardW: 600
    readonly property real cardH: 290

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


    SidebarMusicCard {
        id: card
        width:  root.cardW
        height: root.cardH
        anchors.centerIn: parent

        opacity: root.popupOpen ? 1 : 0
        scale:   root.popupOpen ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }

        open:             root.popupOpen
        bgColor:          root.bgColor
        iconFontFamily:   root.iconFontFamily
        textFontFamily:   root.textFontFamily
        activePlayer:     root.activePlayer
        isPlaying:        root.isPlaying
        currentTrack:     root.currentTrack
        currentArtist:    root.currentArtist
        currentArtUrl:    root.currentArtUrl
        trackProgress:    root.trackProgress
        timePlayed:       root.timePlayed
        timeTotal:        root.timeTotal
        mediaWindowLabel: root.mediaWindowLabel
    }
}
