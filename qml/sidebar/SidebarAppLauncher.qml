import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import IslandBackend
import "../shared"
import "../island"

// ── Centered app launcher popup ──────────────────────────────────────────────
// Behaves identically to the main island's SearchPillLayer, but lives in its
// own PanelWindow so it floats center-screen independent of the island capsule.
// The window covers the full screen (like WallpaperPickerWindow) but only
// receives input over the capsule via mask + keyboardFocus.

PanelWindow {
    id: root

    // ── Pywal / capsule color wiring ─────────────────────────────────
    property bool   gamemodeActive:    false
    property bool   useWalColor:       false
    property color  walColor:          "#000000"
    property real   capsuleOpacityValue: 0.20

    readonly property color capsuleColor: gamemodeActive
        ? Qt.rgba(0, 0, 0, 1.0)
        : (useWalColor
            ? Qt.rgba(walColor.r, walColor.g, walColor.b, capsuleOpacityValue)
            : Qt.rgba(0, 0, 0, capsuleOpacityValue))

    // ── Font props forwarded from SidebarWindow ───────────────────────
    property string iconFontFamily: UserConfig.iconFontFamily
    property string textFontFamily: UserConfig.textFontFamily

    // ── Open/close ────────────────────────────────────────────────────
    property bool launcherOpen: false

    function open()  { launcherOpen = true  }
    function close() { launcherOpen = false }
    function toggle(){ launcherOpen = !launcherOpen }

    // ── Window setup ─────────────────────────────────────────────────
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    aboveWindows: true
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: launcherOpen
    visible: launcherOpen

    // ── Input mask: only the capsule catches mouse/keyboard ───────────
    mask: Region {
        Region {
            x: Math.floor(capsule.x)
            y: Math.floor(capsule.y)
            width:  launcherOpen ? Math.ceil(capsule.width)  : 0
            height: launcherOpen ? Math.ceil(capsule.height) : 0
        }
    }

    // ── Click-outside-to-close backdrop ──────────────────────────────
    MouseArea {
        anchors.fill: parent
        enabled: root.launcherOpen
        onClicked: root.close()
        z: -1
    }

    Keys.onEscapePressed: root.close()

    // ── App launcher process (same pattern as DynamicIslandWindow) ───
    QtObject {
        id: launchExec

        function run(cmd) {
            let p = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
            p.command = ["bash", "-c", cmd]
            p.running = true
        }

        function launch(exec) {
            let args = exec.replace(/%[UuFfDdNnickvm]/g, "").trim()
                          .split(/\s+/).filter(function(s){ return s.length > 0 })
            let p = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
            p.command = args
            p.running = true
        }
    }

    // ── Capsule ───────────────────────────────────────────────────────
    // Sized by SearchPillLayer's own capsuleWidth / capsuleHeight, same
    // as the main island does. Centred on the screen.
    Item {
        id: capsule
        width:  searchContent.capsuleWidth
        height: searchContent.capsuleHeight
        anchors.centerIn: parent

        opacity: root.launcherOpen ? 1 : 0
        scale:   root.launcherOpen ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        Behavior on scale   { NumberAnimation { duration: IslandMotion.durationMedium; easing.type: IslandMotion.easeMove } }
        clip: true

        // Mugen-style outlined pill background
        Rectangle {
            anchors.fill: parent
            radius: 28
            color: root.capsuleColor
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            clip: true
        }

        // ── SearchPillLayer (identical component, different container) ─
        SearchPillLayer {
            id: searchContent
            anchors.fill: parent
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            showCondition:  root.launcherOpen

            onCloseRequested:  root.close()
            onLaunchRequested: function(exec, isCmd) {
                if (isCmd) launchExec.run(exec)
                else       launchExec.launch(exec)
                root.close()
            }

            // Pass capsule dimensions up so the window mask never clips content
            onCapsuleWidthChanged:  capsule.width  = capsuleWidth
            onCapsuleHeightChanged: capsule.height = capsuleHeight
        }
    }

}
