import QtQuick
import Quickshell.Hyprland

Item {
    id: root
    property var screen: null
    property bool showCondition: false
    property bool previewsEnabled: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string wallpaperPath: ""
    property real windowCornerRadius: 22
    property alias overviewView: overviewView
    property alias overviewDataReady: hyprlandData.ready
    signal closeRequested()
    anchors.fill: parent

    HyprlandData {
        id: hyprlandData
    }

    WorkspaceOverviewLayer {
        id: overviewView
        anchors.centerIn: parent
        screen: root.screen
        hyprlandData: hyprlandData
        showCondition: root.showCondition
        previewsEnabled: root.previewsEnabled
        textFontFamily: root.textFontFamily
        heroFontFamily: root.heroFontFamily
        wallpaperPath: root.wallpaperPath
        windowCornerRadius: root.windowCornerRadius
        onCloseRequested: root.closeRequested()
    }

    // ── Workspace number labels ───────────────────────────────────────────────
    // Rendered on top of the cells. Positioned relative to overviewView which
    // is anchors.centerIn: parent, so we mirror that anchor.
    Item {
        id: labelLayer
        visible: root.showCondition
        anchors.centerIn: parent
        // Match the workspaceStage size: outerPadding is 14 inside the card,
        // so stage = card - 2*outerPadding.  We position relative to the card
        // centre which is the same centre as overviewView.
        width:  overviewView.width  - overviewView.outerPadding * 2
        height: overviewView.height - overviewView.outerPadding * 2

        Repeater {
            model: overviewView.rows * overviewView.columns
            delegate: Item {
                id: lbl
                required property int index
                readonly property int col: index % overviewView.columns
                readonly property int row: Math.floor(index / overviewView.columns)
                readonly property real cellW: overviewView.workspaceImplicitWidth
                readonly property real cellH: overviewView.workspaceImplicitHeight
                readonly property real gap:   overviewView.workspaceSpacing
                readonly property int  wsNum: overviewView.workspaceGroup * overviewView.workspacesShown
                                              + row * overviewView.columns + col + 1

                x: col * (cellW + gap)
                y: row * (cellH + gap)
                width:  cellW
                height: cellH

                Text {
                    renderType: Text.NativeRendering
                    anchors.centerIn: parent
                    text: lbl.wsNum
                    font.pixelSize: Math.max(10, Math.min(lbl.cellW, lbl.cellH) * 0.18)
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                    opacity: 0.22
                }
            }
        }
    }

    // ── Middle-click to close + tooltip ──────────────────────────────────────
    // Sits on top of the label layer. Left/right fall through via
    // propagateComposedEvents so the existing overlay still handles them.
    Item {
        id: interactionLayer
        anchors.fill: parent
        visible: root.showCondition

        property string tooltipText: ""
        property real   tooltipX: 0
        property real   tooltipY: 0
        property bool   tooltipVisible: false

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.MiddleButton
            hoverEnabled: true
            propagateComposedEvents: true

            onPositionChanged: (mouse) => {
                // Coords relative to overviewView (which is centered in root)
                const ox = root.width  / 2 - overviewView.width  / 2
                const oy = root.height / 2 - overviewView.height / 2
                const lx = mouse.x - ox
                const ly = mouse.y - oy
                const addr = overviewView.windowAddressAtPoint(lx, ly)
                if (addr !== "") {
                    const ba = hyprlandData.windowByAddress ?? {}
                    const wd = ba[addr] ?? null
                    const title = wd?.title ?? ""
                    const cls   = wd?.class ?? wd?.initialClass ?? ""
                    const xway  = wd?.xwayland ? " [XWayland]" : ""
                    interactionLayer.tooltipText    = title + (cls ? "\n[" + cls + "]" + xway : "")
                    interactionLayer.tooltipX       = mouse.x + 14
                    interactionLayer.tooltipY       = mouse.y - 6
                    interactionLayer.tooltipVisible = true
                } else {
                    interactionLayer.tooltipVisible = false
                }
            }

            onExited: { interactionLayer.tooltipVisible = false }

                        onClicked: (mouse) => {
                if (mouse.button !== Qt.MiddleButton) return
                const ox = root.width  / 2 - overviewView.width  / 2
                const oy = root.height / 2 - overviewView.height / 2
                const addr = overviewView.windowAddressAtPoint(mouse.x - ox, mouse.y - oy)
                if (addr !== "") {
                    const disp = Hyprland.dispatch ?? null
                    // Fix: Target the new Lua dispatch API object explicitly
                    if (disp) disp('hl.dsp.window.close({ address = "' + addr + '" })')
                }
                mouse.accepted = true
            }

            }

        }

        // ── Tooltip popup ─────────────────────────────────────────────────
        Rectangle {
            visible: interactionLayer.tooltipVisible && interactionLayer.tooltipText !== ""
            x: Math.min(interactionLayer.tooltipX, root.width  - width  - 8)
            y: Math.max(interactionLayer.tooltipY - height, 4)
            width:  tipText.implicitWidth  + 18
            height: tipText.implicitHeight + 10
            radius: 8
            color:  "#cc111118"
            border.width: 1
            border.color: "#44ffffff"
            z: 9999

            Text {
                renderType: Text.NativeRendering
                id: tipText
                anchors.centerIn: parent
                text: interactionLayer.tooltipText
                color: "#ffffffff"
                font.pixelSize: 12
                lineHeight: 1.3
            }
        }
    }
