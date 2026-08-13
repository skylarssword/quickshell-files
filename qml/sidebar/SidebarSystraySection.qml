import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../shared"

// Vertical replica of SystrayBubble's fold-out mechanic.
// The chevron arrow (rotated chevron-double-left) sits at the top;
// tapping it expands the section downward revealing tray icons + package count.

Item {
    id: root

    property real   pillWidth:      38
    property string iconFontFamily: "monospace"
    property string textFontFamily: "sans-serif"
    property bool   gamemodeActive: false

    // How tall the expanded tray content is — parent reads this to grow the pill.
    readonly property real collapsedHeight: toggleBtn.height
    readonly property real expandedHeight:  toggleBtn.height + trayContent.implicitHeight + 8

    property bool expanded: false

    readonly property int trayIconSize: 18
    readonly property int trayIconSpacing: 8

    property int updatesCount: 0

    implicitWidth:  pillWidth
    implicitHeight: expanded ? expandedHeight : collapsedHeight

    Behavior on implicitHeight {
        NumberAnimation { duration: IslandMotion.standard; easing.type: IslandMotion.easeArrive }
    }

    // ── Updates query (same as SystrayBubble) ────────────────────────
    Process {
        id: updatesQuery
        property string _buf: ""
        command: ["bash", "-c",
            "echo $(( $(checkupdates 2>/dev/null | wc -l) + $(paru -Qum 2>/dev/null | wc -l) ))"]
        stdout: SplitParser { onRead: updatesQuery._buf += data }
        onRunningChanged: {
            if (!running) {
                const parsed = parseInt(updatesQuery._buf.trim(), 10)
                root.updatesCount = isNaN(parsed) ? 0 : parsed
                updatesQuery._buf = ""
            }
        }
    }
    Process {
        id: updatesRunner
        command: ["kitty", "-e", "bash", "-c", "~/.config/ml4w/scripts/ml4w-install-system-updates"]
        onRunningChanged: { if (!running) updatesQuery.running = true }
    }
    Timer {
        interval: 3600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!updatesQuery.running) updatesQuery.running = true }
    }

    // ── Chevron toggle button ─────────────────────────────────────────
    Item {
        id: toggleBtn
        width:  root.pillWidth
        height: root.pillWidth
        anchors.top:              parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        Image {
            anchors.centerIn: parent
            width: 20; height: 20
            source: Quickshell.shellDir + "/qml/shared/assets/chevron-double-left.svg"
            sourceSize: Qt.size(40, 40)
            fillMode: Image.PreserveAspectFit

            // Rest = pointing up (270°), expanded = pointing down (90°)
            rotation: root.expanded ? 90 : 270

            opacity: chevronMouse.containsMouse ? 1.0 : 0.60
            scale:   chevronMouse.containsMouse ? 1.15 : (chevronMouse.pressed ? 0.82 : 1.0)

            Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on opacity  { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale    { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: chevronMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Divider ───────────────────────────────────────────────────────
    Rectangle {
        anchors.top: toggleBtn.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 20; height: 1
        color: IslandMotion.surfaceBorderColor
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: IslandMotion.fast } }
    }

    // ── Tray content (expands downward) ──────────────────────────────
    Column {
        id: trayContent
        anchors.top:              toggleBtn.bottom
        anchors.topMargin:        6
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: trayIconSpacing

        opacity: root.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: IslandMotion.fast; easing.type: IslandMotion.easeOut } }

        // ── Package count ─────────────────────────────────────────────
        Item {
            width: root.pillWidth
            height: root.trayIconSize + 4
            anchors.horizontalCenter: parent.horizontalCenter

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf487"
                    font.family: root.iconFontFamily
                    font.pixelSize: root.trayIconSize - 2
                    color: "white"
                    opacity: pkgMouse.containsMouse ? 1.0 : 0.65
                    scale:   pkgMouse.containsMouse ? 1.15 : (pkgMouse.pressed ? 0.82 : 1.0)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
                Text {
                    renderType: Text.NativeRendering
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String(root.updatesCount)
                    font.family: root.textFontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "white"
                    opacity: pkgMouse.containsMouse ? 1.0 : 0.65
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            MouseArea {
                id: pkgMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.expanded
                onClicked: updatesRunner.running = true
            }
        }

        // ── Tray icons ────────────────────────────────────────────────
        Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Item {
                id: trayIconDelegate
                width:  root.trayIconSize
                height: root.trayIconSize
                anchors.horizontalCenter: parent.horizontalCenter

                // ── Context menu popup ────────────────────────────────
                PopupWindow {
                    id: menuPopup
                    visible: false
                    color: "transparent"
                    anchor.item: trayIconDelegate
                    // open to the right of the pill
                    anchor.rect.x: root.pillWidth + 8
                    anchor.rect.y: 0
                    implicitWidth: 200
                    implicitHeight: menuColumn.implicitHeight + 16

                    QsMenuOpener {
                        id: menuOpener
                        menu: modelData.hasMenu ? modelData.menu : null
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#1e1e1e"
                        radius: 8

                        Column {
                            id: menuColumn
                            anchors.top:    parent.top
                            anchors.left:   parent.left
                            anchors.right:  parent.right
                            anchors.margins: 8
                            spacing: 2

                            Repeater {
                                model: menuOpener.children ? menuOpener.children.values : []

                                delegate: Column {
                                    id: menuItemDelegate
                                    width: parent.width
                                    spacing: 2
                                    property bool submenuExpanded: false

                                    Rectangle {
                                        width: parent.width
                                        height: modelData.isSeparator ? 0 : 28
                                        visible: !modelData.isSeparator
                                        radius: 4
                                        color: menuItemArea.containsMouse ? "#333333" : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            renderType: Text.NativeRendering
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left; anchors.leftMargin: 8
                                            text: (modelData.text || "") + (modelData.hasChildren ? " ▶" : "")
                                            color: menuItemArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                            font.pixelSize: 12
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        MouseArea {
                                            id: menuItemArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.hasChildren) {
                                                    menuItemDelegate.submenuExpanded = !menuItemDelegate.submenuExpanded
                                                } else {
                                                    if (modelData.triggered)
                                                        modelData.triggered()
                                                    else if (modelData.activate)
                                                        modelData.activate()
                                                    menuPopup.visible = false
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        visible: menuItemDelegate.submenuExpanded && modelData.hasChildren
                                        width: parent.width
                                        spacing: 2

                                        QsMenuOpener {
                                            id: subMenuOpener
                                            menu: modelData.hasChildren ? modelData : null
                                        }

                                        Repeater {
                                            model: subMenuOpener.children ? subMenuOpener.children.values : []
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: modelData.isSeparator ? 0 : 28
                                                visible: !modelData.isSeparator
                                                radius: 4
                                                color: subMenuArea.containsMouse ? "#333333" : "transparent"
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                Text {
                                                    renderType: Text.NativeRendering
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.left: parent.left; anchors.leftMargin: 16
                                                    text: modelData.text || ""
                                                    color: subMenuArea.containsMouse ? "white" : Qt.rgba(1,1,1,0.75)
                                                    font.pixelSize: 12
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                MouseArea {
                                                    id: subMenuArea
                                                    anchors.fill: parent; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.triggered)
                                                            modelData.triggered()
                                                        else if (modelData.activate)
                                                            modelData.activate()
                                                        menuPopup.visible = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Tray icon image ───────────────────────────────────
                Image {
                    id: trayIcon
                    anchors.fill: parent
                    source: {
                        const icon = modelData.icon
                        if (!icon || icon === "") return ""
                        return icon
                    }
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                    sourceSize: Qt.size(root.trayIconSize * 2, root.trayIconSize * 2)
                    opacity: trayMouse.containsMouse ? 1.0 : 0.75
                    scale:   trayMouse.containsMouse ? 1.2  : 1.0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                // Fallback letter if no image
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    visible: trayIcon.status !== Image.Ready
                    Text {
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: modelData.title ? modelData.title[0] : "?"
                        color: "white"
                        font.pixelSize: root.trayIconSize - 2
                        opacity: trayMouse.containsMouse ? 1.0 : 0.75
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent; anchors.margins: -6
                    z: 10; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.expanded
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        mouse.accepted = true
                        if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                            menuPopup.visible = !menuPopup.visible
                        } else if (modelData.activate) {
                            modelData.activate()
                        }
                    }
                }
            }
        }

        // Bottom padding
        Item { width: 1; height: 4 }
    }
}
