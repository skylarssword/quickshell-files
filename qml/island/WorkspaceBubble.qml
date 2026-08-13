import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../shared"

Item {
    id: root

    property string monitorName: ""
    property int currentWorkspace: 1
    property bool useWalColor: false
    property color walColor: "#000000"
    property real capsuleOpacityValue: 0.20
    property bool gamemodeActive: false
    property string iconFontFamily: "monospace"

    signal dotClicked(int workspaceId)

    property bool showTitleBubble: true

    readonly property int dotSize: 8
    readonly property int pillWidth: 22
    readonly property int dotSpacing: 8
    readonly property int sidePadding: 12
    readonly property int titleMaxWidth: 440
    readonly property int titlePadding: 14
    property string textFontFamily: "sans-serif"

    // ── App-grid / search launcher glyph ─────────────────────────────────
    // nf-md-view_grid  (a proper 4-square / waffle grid) — same visual weight
    // as mugen-shell's launcher icon. Falls back to nf-fa-th-large (\uf009)
    // if your font doesn't carry the md set.
    readonly property string gridGlyph: "\udb80\uddc4"  // 󰇄  nf-md-view_grid
    readonly property string tideIpcPath: "/usr/share/tide-island"
    readonly property int gridIconSize: 24
    readonly property int dividerWidth: 2
    readonly property int dividerHeight: 16
    readonly property color dividerColor: IslandMotion.surfaceBorderColor
    readonly property int bubbleGap: 8

    Process {
        id: toggleSearchProcess
        command: ["qs", "ipc", "-p", root.tideIpcPath, "call", "tide", "toggleSearch"]
    }

    // ── Active window title from Hyprland ────────────────────────────────
    readonly property var focusedToplevel: {
        if (!Hyprland.toplevels || !Hyprland.toplevels.values) return null
        const all = Hyprland.toplevels.values
        for (let i = 0; i < all.length; i++) {
            if (all[i].activated) return all[i]
        }
        return null
    }

    readonly property string rawTitle: focusedToplevel ? (focusedToplevel.title || "") : ""
    readonly property string rawClass: focusedToplevel && focusedToplevel.wayland
        ? (focusedToplevel.wayland.appId || "")
        : ""

    readonly property string displayTitle: {
        if (rawTitle === "") return rawClass
        return rawTitle.length > 35 ? rawClass : rawTitle
    }

    readonly property var monitorWorkspaces: {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return []
        const all = Hyprland.workspaces.values
        const filtered = root.monitorName
            ? all.filter(w => w.monitor && w.monitor.name === root.monitorName)
            : all.slice()
        return filtered.sort((a, b) => a.id - b.id)
    }

    width: mainPill.width + (showTitleBubble && displayTitle !== "" ? bubbleGap + titleBubble.width : 0)
    height: 38
    y: 5

    Behavior on width {
        NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive }
    }

    // ── Combined pill: grid icon | divider | workspace dots ──────────────
    Rectangle {
        id: mainPill
        x: 0
        width: Math.max(70, contentRow.implicitWidth + root.sidePadding * 2)
        height: 38
        radius: 19

        color: root.gamemodeActive
            ? Qt.rgba(0, 0, 0, 1.0)
            : (root.useWalColor
                ? Qt.rgba(root.walColor.r, root.walColor.g, root.walColor.b, root.capsuleOpacityValue)
                : Qt.rgba(0, 0, 0, root.capsuleOpacityValue))

        Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }
        Behavior on width { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive } }

        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: root.showTitleBubble = !root.showTitleBubble
        }

        Row {
            id: contentRow
            anchors.left: parent.left
            anchors.leftMargin: root.sidePadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.dotSpacing

            // ── Grid icon (search / app launcher) ──────────────────────
            Item {
                width: root.gridIconSize
                height: root.gridIconSize
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    source: Quickshell.shellDir + "/qml/shared/assets/app-launcher.svg"
                    sourceSize: Qt.size(36, 36)
                    fillMode: Image.PreserveAspectFit
                    opacity: gridMouse.containsMouse ? 1.0 : 0.7
                    scale: gridMouse.containsMouse ? 1.2 : (gridMouse.pressed ? 0.82 : 1.0)

                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: gridMouse
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: toggleSearchProcess.running = true
                }
            }

            // ── Divider ─────────────────────────────────────────────────
            Rectangle {
                width: root.dividerWidth
                height: root.dividerHeight
                radius: root.dividerWidth / 2
                color: root.dividerColor
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Workspace dots ──────────────────────────────────────────
            Row {
                id: dotsRow
                spacing: root.dotSpacing
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: root.monitorWorkspaces

                    delegate: Rectangle {
                        id: dotDelegate
                        required property var modelData
                        readonly property bool isActive: modelData.id === root.currentWorkspace

                        width: isActive ? root.pillWidth : root.dotSize
                        height: root.dotSize
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: isActive ? "white" : Qt.rgba(1, 1, 1, dotMouse.containsMouse ? 0.65 : 0.4)
                        opacity: dotMouse.containsMouse && !isActive ? 0.9 : 1.0
                        scale: dotMouse.containsMouse && !isActive ? 1.25 : 1.0

                        Behavior on width { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive } }
                        Behavior on color { ColorAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeMove } }
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        MouseArea {
                            id: dotMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dotClicked(modelData.id)
                        }
                    }
                }
            }
        }
    }

    // ── Window title bubble (separate pill) ───────────────────────────────
    Rectangle {
        id: titleBubble
        x: mainPill.width + root.bubbleGap
        y: 0
        height: 38
        radius: 19
        width: Math.min(root.titleMaxWidth, titleText.implicitWidth + root.titlePadding * 2)
        visible: root.showTitleBubble && root.displayTitle !== ""
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: IslandMotion.micro; easing.type: IslandMotion.easeOut }
        }

        Behavior on width {
            NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeArrive }
        }

        color: root.gamemodeActive
            ? Qt.rgba(0, 0, 0, 1.0)
            : (root.useWalColor
                ? Qt.rgba(root.walColor.r, root.walColor.g, root.walColor.b, root.capsuleOpacityValue)
                : Qt.rgba(0, 0, 0, root.capsuleOpacityValue))

        Behavior on color { ColorAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeMove } }

        border.width: IslandMotion.surfaceBorderWidth
        border.color: IslandMotion.surfaceBorderColor

        Text {
            renderType: Text.NativeRendering
            id: titleText
            anchors.centerIn: parent
            width: parent.width - root.titlePadding * 2
            text: root.displayTitle
            color: "white"
            font.family: root.textFontFamily
            font.pixelSize: 16
            font.weight: Font.Bold
            font.letterSpacing: -0.35
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }
}
